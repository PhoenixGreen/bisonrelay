import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart' show SessionClip;
import 'package:bruig/plugin_system/canvas/model/devices.dart'
    show DeviceGroup, DeviceKind, MixDevice;
import 'package:bruig/plugin_system/canvas/model/modulation.dart'
    show ModTarget, macroKnobs;
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart'
    show loadSoundBank;
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, KeyEvent, LogicalKeyboardKey;

// instrument_editor.dart is the Instrument editor, in the Chain: how a MIDI
// channel's instrument plays its sound (instrument_shape.dart) -- its volume
// envelope (the sound's own, or set here, its dots dragged), a filter with
// an envelope of its own (its curve dragged), an LFO, and its voices: one at
// a time or many, gliding, the bend wheel's range, tuning and the velocity
// curve -- each a card of knobs over a picture of what it does. And the
// instrument's card in the chain, between its MIDI effects and its sound's.

/// The cards' colours: each its device family's (see deviceGroupLook).
Color get _envelopeAccent => deviceGroupLook(DeviceGroup.dynamics).$2;
Color get _filterAccent => deviceGroupLook(DeviceGroup.filter).$2;
Color get _voicesAccent => const Color(0xFF9A92EA);

/// seconds is [s] as a reading: milliseconds under one.
String seconds(double s) => s < 1
    ? "${(s * 1000).round()} ms"
    : "${s.toStringAsFixed(s < 10 ? 2 : 1)} s";

/// hertz is [hz] as a reading.
String hertz(double hz) => hz < 1000
    ? "${hz.toStringAsFixed(hz < 10 ? 2 : 0)} Hz"
    : "${(hz / 1000).toStringAsFixed(1)} kHz";

/// gmFamilies are General MIDI's sixteen families of eight sounds, in
/// program order: the sound browser's headings.
const gmFamilies = [
  "Piano",
  "Chromatic percussion",
  "Organ",
  "Guitar",
  "Bass",
  "Strings",
  "Ensemble",
  "Brass",
  "Reed",
  "Pipe",
  "Synth lead",
  "Synth pad",
  "Synth effects",
  "World",
  "Percussive",
  "Sound effects",
];

/// keyRow is the computer's keys, left to right, that play the keyboard's
/// keys from its lowest C up -- white on the home row, black above it.
const keyRow = "awsedftgyhujkolp;'";

class InstrumentEditor extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  const InstrumentEditor(
      {required this.controller, required this.channel, super.key});

  @override
  State<InstrumentEditor> createState() => _InstrumentEditorState();
}

class _InstrumentEditorState extends State<InstrumentEditor> {
  CanvasController get c => widget.controller;
  String get channel => widget.channel;

  /// _dragging is the envelope's dot being dragged: 0 its peak, 1 where it
  /// meets the sustain, 2 its release's end.
  int? _dragging;

  /// _find is what the sound browser is filtered by.
  String _find = "";

  /// _font is the sound bank, read for the Zones card once its sound is
  /// the bank's; _fontAsked whether it has been asked for.
  SoundFont? _font;
  bool _fontAsked = false;

  void _set(InstrumentShape Function(InstrumentShape) change,
      {bool transient = false}) {
    c.beginInteraction();
    c.setInstrumentShape(channel, change, transient: true);
    if (!transient) c.endInteraction();
  }

  void _setPart(InstrumentPart Function(InstrumentPart) change) {
    c.beginInteraction();
    c.setChannelPart(channel, change);
    c.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var element = c.instrumentOf(channel);
    var part = element?.instrument;
    if (element == null || part == null) return const SizedBox();
    var shape = part.shape;
    var look = MixerLook.of(context);
    var muted = TextStyle(fontSize: 11, color: look.studio.muted);
    return LayoutBuilder(builder: (context, room) {
      // Short, only the keyboard: the cards and the sounds want room.
      var tall = room.maxHeight > 230;
      var keys = tall
          ? (room.maxHeight * 0.3).clamp(64.0, 130.0)
          : math.max(40.0, room.maxHeight - 34);
      return Column(children: [
        // What it plays, what it plays like, and how to play it here.
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: look.studio.panel,
            border: Border(bottom: BorderSide(color: look.studio.edge)),
          ),
          child: Row(children: [
            Text("Sound", style: muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(part.name,
                  key: const ValueKey("instrumentEditorSound"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: look.studio.text)),
            ),
            Text(
                part.sound == InstrumentSound.bank
                    ? " · MuseScore General"
                    : " · built in",
                style: muted),
            const SizedBox(width: 12),
            Text("Plays like", style: muted),
            const SizedBox(width: 6),
            Flexible(
              flex: 3,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: DeviceChoices(options: [
                  for (var l in InstrumentLook.values)
                    (
                      ValueKey("instrumentLook-${l.name}"),
                      l.label,
                      part.look == l,
                      () => _setPart((p) => p.withLook(l)),
                    ),
                ]),
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                  switch (part.look) {
                    InstrumentLook.drums =>
                      "Your computer keys play the pads: A to ' along the row",
                    InstrumentLook.keyboard => "Your computer keys play it: "
                        "A to K, with W E T Y U for the black keys",
                    _ => "Press a string at a fret, or play it from your "
                        "computer keys: A to K",
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted),
            ),
            if (!shape.plain) ...[
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey("instrumentPlain"),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: look.colors.primary),
                onPressed: () => _set((_) => const InstrumentShape()),
                child: const Text("As the sound is"),
              ),
            ],
          ]),
        ),
        if (tall)
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 190, child: _sounds(look, part)),
              Container(width: 1, color: look.studio.edge),
              Expanded(child: _cards(look, shape)),
            ]),
          ),
        SizedBox(
          height: keys,
          child: _Keyboard(
              key: const ValueKey("instrumentKeyboard"),
              controller: c,
              element: element),
        ),
      ]);
    });
  }

  /// _sounds is the sound browser: General MIDI's sounds by family, found
  /// as they are typed, the one playing picked out.
  Widget _sounds(MixerLook look, InstrumentPart part) {
    var q = _find.toLowerCase();
    bool shows(String name, String family) =>
        q.isEmpty ||
        name.toLowerCase().contains(q) ||
        family.toLowerCase().contains(q);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 3),
          child: Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w500,
                  color: look.studio.muted)),
        );
    Widget item(String key, String name, String number, bool on,
            VoidCallback pick) =>
        InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(4),
          onTap: pick,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: on ? look.colors.primary : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: on ? look.colors.onPrimary : look.studio.text)),
              ),
              Text(number,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: on ? look.colors.onPrimary : look.studio.muted)),
            ]),
          ),
        );
    var bank = part.sound == InstrumentSound.bank;
    var drums = part.look == InstrumentLook.drums;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: SizedBox(
          height: 28,
          child: TextField(
            key: const ValueKey("instrumentFind"),
            style: TextStyle(fontSize: 11.5, color: look.studio.text),
            decoration: InputDecoration(
              hintText: "Find a sound",
              isDense: true,
              filled: true,
              fillColor: look.studio.inset,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: look.studio.edge)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: look.studio.edge)),
            ),
            onChanged: (v) => setState(() => _find = v),
          ),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          children: [
            if (shows("Built in", "Built in")) ...[
              heading("Built in"),
              item("instrumentSound-builtin", "${part.look.label}, built in",
                  "", !bank, () {
                _setPart((p) => p.copyWith(sound: InstrumentSound.builtin));
              }),
            ],
            for (var (f, family) in gmFamilies.indexed)
              if ([
                for (var i = f * 8; i < f * 8 + 8; i++)
                  if (shows(gmPrograms[i], family)) i
              ]
                  case var found when found.isNotEmpty) ...[
                heading(family),
                for (var i in found)
                  item(
                      "instrumentSound-$i",
                      gmPrograms[i],
                      "${i + 1}",
                      bank && !drums && part.program == i,
                      () => _setPart((p) => (p.look == InstrumentLook.drums
                              ? p.withLook(InstrumentLook.keyboard)
                              : p)
                          .copyWith(
                              sound: InstrumentSound.bank,
                              bank: 0,
                              program: i))),
              ],
            if (shows("Drum kit", "Drum kits")) ...[
              heading("Drum kits"),
              item("instrumentSound-drums", "Standard kit", "", bank && drums,
                  () {
                _setPart((p) => p
                    .withLook(InstrumentLook.drums)
                    .copyWith(sound: InstrumentSound.bank));
              }),
            ],
          ],
        ),
      ),
    ]);
  }

  /// _cards are the instrument's cards, side by side: as wide as the room
  /// lets them be, scrolled across where it does not.
  Widget _cards(MixerLook look, InstrumentShape shape) =>
      LayoutBuilder(builder: (context, room) {
        const least = 236.0;
        var cards = [
          _envelopeCard(look, shape),
          _filterCard(look, shape),
          _lfoCard(look, shape),
          _voicesCard(look, shape),
          _zonesCard(look),
        ];
        if (room.maxWidth >= least * cards.length + 40) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              for (var (i, card) in cards.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: card),
              ],
            ]),
          );
        }
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8),
          children: [
            for (var (i, card) in cards.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              SizedBox(width: least, child: card),
            ],
          ],
        );
      });

  /// _zonesCard is the prototype's Zones: the samples the sound is made
  /// of, drawn by key along and by how hard up, with how many layers a
  /// key has by velocity and how many ranges the keys are split into.
  Widget _zonesCard(MixerLook look) {
    const accent = Color(0xFFA7A3B8);
    var part = c.instrumentOf(channel)?.instrument;
    var bank = part?.sound == InstrumentSound.bank;
    if (bank && !_fontAsked) {
      _fontAsked = true;
      loadSoundBank().then((f) {
        if (mounted) setState(() => _font = f);
      });
    }
    var map = bank && part != null && _font != null
        ? zoneMap(_font!, part.bank, part.program)
        : null;
    var muted = TextStyle(fontSize: 10, color: look.studio.muted);
    var strong = TextStyle(fontSize: 10.5, color: look.studio.text);
    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            SizedBox(width: 74, child: Text(label, style: muted)),
            Expanded(
                child: Text(value,
                    key: ValueKey("instrumentZones-$label"),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: strong)),
          ]),
        );
    return _card(look,
        id: "instrumentZonesCard",
        title: "Zones",
        accent: accent,
        picture: CustomPaint(
            painter: _ZonesPainter(map,
                accent: accent,
                back: look.studio.display,
                text: look.studio.muted)),
        knobs: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (map == null) ...[
              fact("Layers", bank ? "reading the bank…" : "one"),
              fact("Key ranges", bank ? "" : "one, every key"),
              Text(
                  bank
                      ? "From the sound bank: each zone a sample, a key "
                          "range and a velocity range."
                      : "The built-in sound is made, not sampled: one zone "
                          "over every key and velocity.",
                  style: muted),
            ] else ...[
              fact("Layers", "${map.layers} by velocity"),
              fact("Key ranges", "${map.ranges}"),
              fact("Round robin", "off"),
            ],
          ]),
        ]);
  }

  /// _card is one of the editor's cards, as the prototype draws them: its
  /// colour along its top, its title in capitals, a picture, its knobs on a
  /// row and its choice under them.
  Widget _card(MixerLook look,
      {required String id,
      required String title,
      required Color accent,
      required Widget picture,
      required List<Widget> knobs,
      Widget? choice,
      bool dim = false}) {
    var knobRow = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var k in knobs) Expanded(child: k),
    ]);
    var controls = Opacity(
      opacity: dim ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: dim,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: knobRow,
        ),
      ),
    );
    var choose = choice != null
        ? Padding(padding: const EdgeInsets.fromLTRB(6, 4, 6, 6), child: choice)
        : const SizedBox(height: 6);
    return Container(
      key: ValueKey(id),
      decoration: BoxDecoration(
        color: look.studio.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: look.studio.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 2, color: accent),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: look.studio.edge.withValues(alpha: 0.7)))),
          child: Text(title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: look.studio.text)),
        ),
        // Short, its knobs and choice without the picture, scrolled where
        // even they will not fit.
        Expanded(
          child: LayoutBuilder(builder: (context, room) {
            if (room.maxHeight < 150) {
              return SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [controls, choose]),
              );
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: picture),
                    ),
                  ),
                  controls,
                  choose,
                ]);
          }),
        ),
      ]),
    );
  }

  Widget _knob(
          MixerLook look,
          String key,
          String label,
          String text,
          double value,
          double initial,
          double min,
          double max,
          Color accent,
          InstrumentShape Function(InstrumentShape, double) change,
          {bool log = false,
          bool bipolar = false}) =>
      DeviceKnob(
        key: ValueKey(key),
        label: label,
        text: text,
        value: value,
        initial: initial,
        min: min,
        max: max,
        log: log,
        bipolar: bipolar,
        size: 38,
        accent: accent,
        ink: look.studio.text,
        onChanged: (v, {transient = false}) =>
            _set((s) => change(s, v), transient: transient),
        onCommit: c.endInteraction,
      );

  Widget _choices<T>(
          String prefix,
          List<T> values,
          T now,
          String Function(T) label,
          String Function(T) name,
          ValueChanged<T> pick) =>
      DeviceChoices(options: [
        for (var v in values)
          (ValueKey("$prefix-${name(v)}"), label(v), v == now, () => pick(v)),
      ]);

  Widget _envelopeCard(MixerLook look, InstrumentShape s) {
    const d = InstrumentShape();
    var a = _envelopeAccent;
    return _card(
      look,
      id: "instrumentEnvelopeCard",
      title: "Volume envelope",
      accent: a,
      dim: !s.envelope,
      picture: LayoutBuilder(builder: (context, room) {
        var size = room.biggest;
        var points = envelopePoints(s, size);
        return GestureDetector(
          supportedDevices: dragPointers,
          key: const ValueKey("instrumentEnvelopeGraph"),
          // The dot nearest where it was pressed, not where the drag began.
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          onPanStart: (e) {
            var best = -1;
            var near = 18.0;
            for (var (i, p) in [points.$3, points.$4, points.$6].indexed) {
              var dist = (p - e.localPosition).distance;
              if (dist < near) {
                near = dist;
                best = i;
              }
            }
            if (best >= 0) setState(() => _dragging = best);
          },
          onPanUpdate: (e) {
            var i = _dragging;
            if (i == null) return;
            var (scale, _, _, _, _, _) = points;
            var t = math.max(0.0, (e.localPosition.dx - 6) / scale);
            var level = (1 - (e.localPosition.dy - 6) / (size.height - 12))
                .clamp(0.0, 1.0);
            // Dragged, it is the instrument's own envelope.
            _set(
                (x) => switch (i) {
                      0 => x.copyWith(attack: t, envelope: true),
                      1 => x.copyWith(
                          decay: t - x.attack, sustain: level, envelope: true),
                      _ => x.copyWith(
                          release: t - x.attack - x.decay - _held,
                          envelope: true),
                    },
                transient: true);
          },
          onPanEnd: (_) {
            if (_dragging == null) return;
            setState(() => _dragging = null);
            c.endInteraction();
          },
          child: CustomPaint(
            painter: EnvelopePainter(s,
                accent: a,
                back: look.studio.display,
                faint: !s.envelope,
                text: look.studio.muted),
          ),
        );
      }),
      choice: _choices<bool>(
          "instrumentEnvelope",
          const [false, true],
          s.envelope,
          (v) => v ? "Set here" : "The sound's own",
          (v) => v ? "own" : "sound",
          (v) => _set((x) => x.copyWith(envelope: v))),
      knobs: [
        _knob(look, "instrumentAttack", "Attack", seconds(s.attack), s.attack,
            d.attack, 0.001, 10, a, (x, v) => x.copyWith(attack: v),
            log: true),
        _knob(look, "instrumentDecay", "Decay", seconds(s.decay), s.decay,
            d.decay, 0.01, 20, a, (x, v) => x.copyWith(decay: v),
            log: true),
        _knob(
            look,
            "instrumentSustain",
            "Sustain",
            "${(s.sustain * 100).round()}%",
            s.sustain,
            d.sustain,
            0,
            1,
            a,
            (x, v) => x.copyWith(sustain: v)),
        _knob(look, "instrumentRelease", "Release", seconds(s.release),
            s.release, d.release, 0.01, 20, a, (x, v) => x.copyWith(release: v),
            log: true),
      ],
    );
  }

  Widget _filterCard(MixerLook look, InstrumentShape s) {
    const d = InstrumentShape();
    var a = _filterAccent;
    var on = s.filter != SynthFilter.off;
    return _card(
      look,
      id: "instrumentFilterCard",
      title: "Filter",
      accent: a,
      picture: LayoutBuilder(builder: (context, room) {
        var w = room.maxWidth;
        return GestureDetector(
          supportedDevices: dragPointers,
          key: const ValueKey("instrumentFilterGraph"),
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          // Across for its corner, up and down for its resonance -- a
          // filter switched on by it, where there was none.
          onPanStart: (_) => c.beginInteraction(),
          onPanUpdate: (e) {
            var u = (e.localPosition.dx / w).clamp(0.0, 1.0);
            _set(
                (x) => x.copyWith(
                    filter: x.filter == SynthFilter.off
                        ? SynthFilter.lowPass
                        : null,
                    cutoff: 20 * math.pow(1000, u).toDouble(),
                    resonance: x.resonance - e.delta.dy / 120),
                transient: true);
          },
          onPanEnd: (_) => c.endInteraction(),
          child: CustomPaint(
            painter: FilterPainter(s,
                accent: a, back: look.studio.display, text: look.studio.muted),
          ),
        );
      }),
      choice: _choices<SynthFilter>(
          "instrumentFilter",
          SynthFilter.values,
          s.filter,
          (f) => f == SynthFilter.off ? "Off" : f.label.replaceAll("-pass", ""),
          (f) => f.name,
          (f) => _set((x) => x.copyWith(filter: f))),
      dim: !on,
      knobs: [
        _knob(look, "instrumentCutoff", "Cutoff", hertz(s.cutoff), s.cutoff,
            d.cutoff, 20, 20000, a, (x, v) => x.copyWith(cutoff: v),
            log: true),
        _knob(
            look,
            "instrumentResonance",
            "Resonance",
            "${(s.resonance * 100).round()}%",
            s.resonance,
            d.resonance,
            0,
            1,
            a,
            (x, v) => x.copyWith(resonance: v)),
        _knob(
            look,
            "instrumentFilterEnvelope",
            "Envelope",
            "${s.filterEnvelope >= 0 ? "+" : ""}"
                "${(s.filterEnvelope * 4).toStringAsFixed(1)} oct",
            s.filterEnvelope,
            d.filterEnvelope,
            -1,
            1,
            a,
            (x, v) => x.copyWith(filterEnvelope: v),
            bipolar: true),
        _knob(
            look,
            "instrumentFilterDecay",
            "Decay",
            seconds(s.filterDecay),
            s.filterDecay,
            d.filterDecay,
            0.01,
            10,
            a,
            (x, v) => x.copyWith(filterDecay: v),
            log: true),
      ],
    );
  }

  Widget _lfoCard(MixerLook look, InstrumentShape s) {
    const d = InstrumentShape();
    var a = modulationColour;
    return _card(
      look,
      id: "instrumentLfoCard",
      title: "LFO",
      accent: a,
      picture: CustomPaint(
        painter: LfoPainter(s,
            accent: a, back: look.studio.display, text: look.studio.muted),
      ),
      choice: _choices<LfoTarget>(
          "instrumentLfoTarget",
          LfoTarget.values,
          s.lfoTarget,
          (t) => t.label,
          (t) => t.name,
          (t) => _set((x) => x.copyWith(lfoTarget: t))),
      knobs: [
        _knob(look, "instrumentLfoRate", "Rate", hertz(s.lfoRate), s.lfoRate,
            d.lfoRate, 0.05, 30, a, (x, v) => x.copyWith(lfoRate: v),
            log: true),
        _knob(
            look,
            "instrumentLfoDepth",
            "Depth",
            "${(s.lfoDepth * 100).round()}%",
            s.lfoDepth,
            d.lfoDepth,
            0,
            1,
            a,
            (x, v) => x.copyWith(lfoDepth: v)),
      ],
    );
  }

  Widget _voicesCard(MixerLook look, InstrumentShape s) {
    const d = InstrumentShape();
    var a = _voicesAccent;
    return _card(
      look,
      id: "instrumentVoicesCard",
      title: "Voices",
      accent: a,
      picture: CustomPaint(
        painter: VelocityPainter(s,
            accent: a, back: look.studio.display, text: look.studio.muted),
      ),
      choice: _choices<VoiceMode>(
          "instrumentVoiceMode",
          VoiceMode.values,
          s.mode,
          (m) => m.label,
          (m) => m.name,
          (m) => _set((x) => x.copyWith(mode: m))),
      knobs: [
        // A glide is from one note to the next: one voice's.
        Opacity(
          opacity: s.mode == VoiceMode.poly ? 0.45 : 1,
          child: _knob(look, "instrumentGlide", "Glide", seconds(s.glide),
              s.glide, d.glide, 0, 5, a, (x, v) => x.copyWith(glide: v)),
        ),
        _knob(
            look,
            "instrumentVoices",
            "Voices",
            "${s.voices}",
            s.voices.toDouble(),
            d.voices.toDouble(),
            1,
            64,
            a,
            (x, v) => x.copyWith(voices: v.round())),
        _knob(
            look,
            "instrumentBend",
            "Bend",
            "±${s.bendRange.round()} st",
            s.bendRange,
            d.bendRange,
            0,
            24,
            a,
            (x, v) => x.copyWith(bendRange: v.roundToDouble())),
        _knob(
            look,
            "instrumentTune",
            "Tune",
            "${s.tune >= 0 ? "+" : ""}${s.tune.round()} ct",
            s.tune,
            d.tune,
            -100,
            100,
            a,
            (x, v) => x.copyWith(tune: v.roundToDouble()),
            bipolar: true),
        _knob(
            look,
            "instrumentVelocity",
            "Velocity",
            s.velocityCurve.abs() < 0.01
                ? "As played"
                : s.velocityCurve > 0
                    ? "Harder"
                    : "Lighter",
            s.velocityCurve,
            d.velocityCurve,
            -1,
            1,
            a,
            (x, v) => x.copyWith(velocityCurve: v),
            bipolar: true),
      ],
    );
  }
}

/// _chords are the keyboard's chords: what a key plays, from it up.
const _chords = <(String, List<int>)>[
  ("No chord", [0]),
  ("Major", [0, 4, 7]),
  ("Minor", [0, 3, 7]),
  ("Seventh", [0, 4, 7, 10]),
  ("Octave", [0, 12]),
];

/// _Keyboard is the editor's keyboard, as the prototype has it: bend and
/// mod wheels, the octave and the sustain pedal; how hard keys are struck,
/// a chord, hold and the keys' letters; then the keys, played with the
/// pointer -- lower on a key, harder -- or the computer's keys.
class _Keyboard extends StatefulWidget {
  final CanvasController controller;
  final AudioElement element;
  const _Keyboard({required this.controller, required this.element, super.key});

  @override
  State<_Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<_Keyboard> {
  CanvasController get c => widget.controller;
  final FocusNode _focus = FocusNode(debugLabel: "instrumentKeys");

  /// _octave is the C the keys start from: 48 is C3.
  int _octave = 48;
  bool _byHeight = true;
  final int _velocity = 100;
  int _chord = 0;
  bool _hold = false;
  bool _sustain = false;

  /// _labels is what is written on the keys: 0 the computer's letters, 1
  /// their names, 2 nothing.
  int _labels = 0;

  /// _held are the keys down, each with the notes it plays.
  final Map<int, List<int>> _held = {};

  /// _pressed is the key each pointer holds down, by pointer: kept on the
  /// state, not in the build, so the press that let go finds the key it
  /// played -- a rebuild between the two once left it sounding (Ken).
  final Map<int, int> _pressed = {};

  /// _typed is the key each computer key plays, by that key: let go, the
  /// same note stops, whatever the octave has become meanwhile.
  final Map<LogicalKeyboardKey, int> _typed = {};
  double _bend = 0.5, _mod = 0;

  @override
  void initState() {
    super.initState();
    // Focus gone, no key up comes: what the computer keys hold goes.
    _focus.addListener(() {
      if (_focus.hasFocus) return;
      for (var k in [..._typed.values]) {
        _off(k);
      }
      _typed.clear();
    });
  }

  @override
  void dispose() {
    for (var k in [..._held.keys]) {
      _off(k, force: true);
    }
    if (_sustain) c.sustain(false);
    _focus.dispose();
    super.dispose();
  }

  void _on(int key, int velocity) {
    if (_held.containsKey(key)) return;
    var notes = [for (var d in _chords[_chord].$2) key + d];
    for (var n in notes) {
      c.noteOn(widget.element, n, velocity: velocity);
    }
    setState(() => _held[key] = notes);
  }

  void _off(int key, {bool force = false}) {
    if (_hold && !force) return;
    var notes = _held.remove(key);
    if (notes == null) return;
    for (var n in notes) {
      c.noteOff(widget.element, n);
    }
    if (mounted && !force) setState(() {});
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    var ch = e.character?.toLowerCase() ?? e.logicalKey.keyLabel.toLowerCase();
    if (e is KeyDownEvent) {
      if (ch == "z") {
        setState(() => _octave = math.max(12, _octave - 12));
        return KeyEventResult.handled;
      }
      if (ch == "x") {
        setState(() => _octave = math.min(96, _octave + 12));
        return KeyEventResult.handled;
      }
    }
    // Let go: the note it started, found by the key, not worked out again.
    if (e is KeyUpEvent) {
      var was = _typed.remove(e.logicalKey);
      if (was == null) return KeyEventResult.ignored;
      _off(was);
      return KeyEventResult.handled;
    }
    var key = _keyFor(ch);
    if (key == null) return KeyEventResult.ignored;
    if (e is KeyDownEvent && !_typed.containsKey(e.logicalKey)) {
      _typed[e.logicalKey] = key;
      _on(key, _byHeight ? 100 : _velocity);
    }
    return KeyEventResult.handled;
  }

  /// _keyFor is the note computer key [ch] plays, or null: drum pads by
  /// their place along the row, anything else up from the octave's C.
  int? _keyFor(String ch) {
    var i = ch.length == 1 ? keyRow.indexOf(ch) : -1;
    if (i < 0) return null;
    var drums = widget.element.instrument?.look == InstrumentLook.drums;
    if (drums) return i < drumPads.length ? drumPads[i].$1 : null;
    return _octave + i;
  }

  /// _played is [child] played with the pointer, [hit] the key under a
  /// point and how hard it strikes there: pressed, dragged across, and let
  /// go -- or dragged off it -- the note stops.
  Widget _played(
          {required Key key,
          required (int, int)? Function(Offset) hit,
          required Widget child}) =>
      Listener(
        key: key,
        onPointerDown: (e) {
          _focus.requestFocus();
          var h = hit(e.localPosition);
          if (h == null) return;
          // Held keys let go by a second press.
          if (_hold && _held.containsKey(h.$1)) {
            _off(h.$1, force: true);
            setState(() {});
            return;
          }
          _pressed[e.pointer] = h.$1;
          _on(h.$1, h.$2);
        },
        onPointerMove: (e) {
          var h = hit(e.localPosition);
          var was = _pressed[e.pointer];
          if (h?.$1 == was) return;
          if (was != null) {
            _pressed.remove(e.pointer);
            _off(was);
          }
          if (h == null) return;
          _pressed[e.pointer] = h.$1;
          _on(h.$1, h.$2);
        },
        onPointerUp: (e) => _letGo(e.pointer),
        onPointerCancel: (e) => _letGo(e.pointer),
        child: child,
      );

  void _letGo(int pointer) {
    var was = _pressed.remove(pointer);
    if (was != null) _off(was);
  }

  /// _surface is the pads or the neck [size] big, played as the keys are:
  /// pressed, dragged across, let go -- lower on a pad, harder.
  Widget _surface(InstrumentPart part, Size size, MixerLook look) {
    var layout = keyboardLayout(part, Offset.zero & size, titled: false);
    int velocity(double depth) =>
        _byHeight ? (40 + 87 * depth).round() : _velocity;
    var drums = part.look == InstrumentLook.drums;
    return _played(
      key: const ValueKey("instrumentKeys"),
      hit: (p) => switch (layout.keyAt(p)) {
        (var key, var depth)? => (key, velocity(depth)),
        null => null,
      },
      child: CustomPaint(
        key: ValueKey("instrumentSurface-${part.look.name}"),
        size: size,
        painter: _SurfacePainter(layout, part,
            down: {for (var n in _held.values) ...n},
            // The computer key each pad is played by, as Letters asks.
            letters: drums && _labels == 0
                ? {
                    for (var (i, (key, _)) in drumPads.indexed)
                      if (i < keyRow.length) key: keyRow[i].toUpperCase()
                  }
                : const {},
            face: look.studio.raised,
            ink: look.studio.text,
            accent: look.colors.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    Widget pill(String key, String label, bool on, VoidCallback tap) =>
        GestureDetector(
          key: ValueKey(key),
          onTap: tap,
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? look.colors.primary : null,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color: on ? look.colors.primary : look.studio.edge),
            ),
            child: Text(label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 10,
                    color: on ? look.colors.onPrimary : look.studio.muted)),
          ),
        );
    String name(int key) => "${const [
          "C",
          "C♯",
          "D",
          "E♭",
          "E",
          "F",
          "F♯",
          "G",
          "A♭",
          "A",
          "B♭",
          "B"
        ][key % 12]}${key ~/ 12 - 1}";
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Container(
        decoration: BoxDecoration(
          color: look.studio.inset,
          border: Border(top: BorderSide(color: look.studio.edge)),
        ),
        child: LayoutBuilder(builder: (context, room) {
          var roomy = room.maxHeight >= 80;
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // The wheels, the octave and the pedal.
            Container(
              width: 116,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: look.studio.edge))),
              child: Row(children: [
                _Wheel(
                  key: const ValueKey("instrumentBendWheel"),
                  value: _bend,
                  springs: true,
                  look: look,
                  onChanged: (v) {
                    setState(() => _bend = v);
                    c.controlOn(widget.element, MidiControl.pitchBend, v);
                  },
                ),
                const SizedBox(width: 5),
                _Wheel(
                  key: const ValueKey("instrumentModWheel"),
                  value: _mod,
                  look: look,
                  onChanged: (v) {
                    setState(() => _mod = v);
                    c.controlOn(widget.element, MidiControl.modulation, v);
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 52,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            pill(
                                "instrumentOctaveDown",
                                "◀ ${name(_octave - 12)}",
                                false,
                                () => setState(() =>
                                    _octave = math.max(12, _octave - 12))),
                            if (roomy) const SizedBox(height: 3),
                            pill(
                                "instrumentOctaveUp",
                                "${name(_octave + 12)} ▶",
                                false,
                                () => setState(() =>
                                    _octave = math.min(96, _octave + 12))),
                            if (roomy) ...[
                              const SizedBox(height: 3),
                              pill("instrumentSustain", "Sustain", _sustain,
                                  () {
                                setState(() => _sustain = !_sustain);
                                c.sustain(_sustain);
                              }),
                            ],
                          ]),
                    ),
                  ),
                ),
              ]),
            ),
            // How it is played.
            if (roomy)
              Container(
                width: 92,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: look.studio.edge))),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 80,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          pill(
                              "instrumentVelocityMode",
                              _byHeight ? "Vel: by height" : "Vel: $_velocity",
                              _byHeight,
                              () => setState(() => _byHeight = !_byHeight)),
                          const SizedBox(height: 3),
                          pill(
                              "instrumentChord",
                              _chords[_chord].$1,
                              _chord > 0,
                              () => setState(() =>
                                  _chord = (_chord + 1) % _chords.length)),
                          const SizedBox(height: 3),
                          pill("instrumentHold", "Hold", _hold, () {
                            setState(() => _hold = !_hold);
                            if (!_hold) {
                              for (var k in [..._held.keys]) {
                                _off(k, force: true);
                              }
                              setState(() {});
                            }
                          }),
                          const SizedBox(height: 3),
                          pill(
                              "instrumentLabels",
                              const ["Letters", "Names", "No labels"][_labels],
                              false,
                              () =>
                                  setState(() => _labels = (_labels + 1) % 3)),
                        ]),
                  ),
                ),
              ),
            // The keys -- or the pads, or the neck, as it plays like.
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                var part = widget.element.instrument;
                if (part != null && part.look != InstrumentLook.keyboard) {
                  return _surface(part, box.biggest, look);
                }
                var layout = _KeysLayout(box.biggest, _octave);
                int? at(Offset p) => layout.keyAt(p);
                int velocity(Offset p) => _byHeight
                    ? (40 + 87 * (p.dy / box.maxHeight).clamp(0.0, 1.0)).round()
                    : _velocity;
                return _played(
                  key: const ValueKey("instrumentKeys"),
                  hit: (p) => switch (at(p)) {
                    var k? => (k, velocity(p)),
                    null => null,
                  },
                  child: CustomPaint(
                    size: box.biggest,
                    painter: _KeysPainter(
                      layout,
                      down: {for (var n in _held.values) ...n},
                      labels: _labels,
                      look: look,
                    ),
                  ),
                );
              }),
            ),
          ]);
        }),
      ),
    );
  }
}

/// _SurfacePainter draws drum pads or a neck, as the canvas draws an
/// instrument element, the notes held lit.
class _SurfacePainter extends CustomPainter {
  final KeyboardLayout layout;
  final InstrumentPart part;
  final Set<int> down;
  final Map<int, String> letters;
  final Color face;
  final Color ink;
  final Color accent;
  _SurfacePainter(this.layout, this.part,
      {required this.down,
      required this.accent,
      required this.face,
      required this.ink,
      this.letters = const {}});

  @override
  void paint(Canvas canvas, Size size) =>
      paintPlayingSurface(canvas, layout, part,
          lit: down, accent: accent, letters: letters, face: face, ink: ink);

  @override
  bool shouldRepaint(_SurfacePainter old) =>
      old.part != part ||
      old.layout.board != layout.board ||
      old.accent != accent ||
      old.face != face ||
      old.ink != ink ||
      old.letters.length != letters.length ||
      !old.down.containsAll(down) ||
      !down.containsAll(old.down);
}

/// _Wheel is a bend or mod wheel: dragged up and down; the bend wheel
/// springs back to the middle when let go.
class _Wheel extends StatelessWidget {
  final double value;
  final bool springs;
  final MixerLook look;
  final ValueChanged<double> onChanged;
  const _Wheel(
      {required this.value,
      required this.look,
      required this.onChanged,
      this.springs = false,
      super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var h = box.maxHeight;
        double at(Offset p) => (1 - p.dy / h).clamp(0.0, 1.0);
        return GestureDetector(
          supportedDevices: dragPointers,
          onVerticalDragStart: (d) => onChanged(at(d.localPosition)),
          onVerticalDragUpdate: (d) => onChanged(at(d.localPosition)),
          onVerticalDragEnd: (_) {
            if (springs) onChanged(0.5);
          },
          child: Container(
            width: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: look.studio.edge),
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [look.studio.raised, look.studio.inset]),
            ),
            child: Stack(children: [
              Positioned(
                left: 1,
                right: 1,
                top: (1 - value) * (h - 12),
                height: 10,
                child: Container(
                  decoration: BoxDecoration(
                      color: look.colors.primary,
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ]),
          ),
        );
      });
}

/// _KeysLayout is where each key is on a keyboard [size] big starting at
/// [low]: white keys across, black ones over them.
class _KeysLayout {
  final Size size;
  final int low;
  late final double white = (size.width / 29).clamp(16.0, 34.0);
  late final List<(int, Rect, bool)> keys = _lay();

  _KeysLayout(this.size, this.low);

  List<(int, Rect, bool)> _lay() {
    var whites = <(int, Rect, bool)>[];
    var count = (size.width / white).floor();
    var p = low;
    while (whites.length < count && p < 128) {
      if (!isBlackKey(p)) {
        whites.add((
          p,
          Rect.fromLTWH(whites.length * white, 0, white, size.height),
          false
        ));
      }
      p++;
    }
    var blacks = <(int, Rect, bool)>[];
    for (var (k, r, _) in whites) {
      if (isBlackKey(k + 1) && k + 1 < p) {
        blacks.add((
          k + 1,
          Rect.fromLTWH(
              r.left + white * 0.66, 0, white * 0.68, size.height * 0.6),
          true
        ));
      }
    }
    return [...whites, ...blacks];
  }

  /// keyAt is the key under [p], a black one before the white under it.
  int? keyAt(Offset p) {
    for (var (k, r, black) in keys.reversed) {
      if (black && r.contains(p)) return k;
    }
    for (var (k, r, black) in keys) {
      if (!black && r.contains(p)) return k;
    }
    return null;
  }
}

class _KeysPainter extends CustomPainter {
  final _KeysLayout layout;
  final Set<int> down;
  final int labels;
  final MixerLook look;
  _KeysPainter(this.layout,
      {required this.down, required this.labels, required this.look});

  @override
  void paint(Canvas canvas, Size size) {
    var lit = Paint()..color = midiColour;
    void say(String text, Offset at, Color colour) {
      var p = TextPainter(
          text: TextSpan(
              text: text, style: TextStyle(fontSize: 9.5, color: colour)),
          textDirection: TextDirection.ltr)
        ..layout();
      p.paint(canvas, at - Offset(p.width / 2, 0));
    }

    String? label(int k) {
      if (labels == 2) return null;
      if (labels == 1) {
        return k % 12 == 0 ? "C${k ~/ 12 - 1}" : null;
      }
      var i = k - layout.low;
      return i >= 0 && i < keyRow.length ? keyRow[i].toUpperCase() : null;
    }

    for (var (k, r, black) in layout.keys) {
      if (black) continue;
      canvas.drawRRect(
          RRect.fromRectAndCorners(r.deflate(0.5),
              bottomLeft: const Radius.circular(4),
              bottomRight: const Radius.circular(4)),
          down.contains(k) ? lit : (Paint()..color = const Color(0xFFECE9F2)));
      if (k % 12 == 0 && labels != 1) {
        say("C${k ~/ 12 - 1}", Offset(r.left + 10, 3), const Color(0xFF6C6788));
      }
      if (label(k) case var l?) {
        say(l, Offset(r.center.dx, r.bottom - 16), const Color(0xFF6C6788));
      }
    }
    for (var (k, r, black) in layout.keys) {
      if (!black) continue;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          down.contains(k) ? lit : (Paint()..color = const Color(0xFF1C1A2C)));
      var l = labels == 0 ? label(k) : null;
      if (l != null) {
        say(l, Offset(r.center.dx, r.bottom - 14), const Color(0xFFB9B4CC));
      }
    }
  }

  @override
  bool shouldRepaint(_KeysPainter old) => true;
}

/// _held is how long the envelope's picture shows the key held, in
/// seconds, between its decay and its release.
const double _held = 0.6;

/// envelopePoints is [s]'s envelope drawn in [size]: seconds to pixels, then
/// where it starts, peaks, meets its sustain, is let go and ends.
(double, Offset, Offset, Offset, Offset, Offset) envelopePoints(
    InstrumentShape s, Size size) {
  var span = math.max(2.2, s.attack + s.decay + _held + s.release);
  var scale = (size.width - 12) / span;
  double y(double level) => size.height - 6 - level * (size.height - 12);
  var x0 = 6.0;
  return (
    scale,
    Offset(x0, y(0)),
    Offset(x0 + s.attack * scale, y(1)),
    Offset(x0 + (s.attack + s.decay) * scale, y(s.sustain)),
    Offset(x0 + (s.attack + s.decay + _held) * scale, y(s.sustain)),
    Offset(x0 + (s.attack + s.decay + _held + s.release) * scale, y(0)),
  );
}

/// _screen draws a card's picture's ground: its colour, and a faint grid.
void _screen(Canvas canvas, Size size, Color back) {
  var r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
  canvas.drawRRect(r, Paint()..color = back);
  var grid = Paint()..color = Color.lerp(back, Colors.white, 0.06)!;
  for (var i = 1; i < 6; i++) {
    canvas.drawRect(
        Rect.fromLTWH((i * size.width / 6).roundToDouble(), 0, 1, size.height),
        grid);
  }
  for (var i = 1; i < 3; i++) {
    canvas.drawRect(
        Rect.fromLTWH(0, (i * size.height / 3).roundToDouble(), size.width, 1),
        grid);
  }
}

void _say(Canvas canvas, String text, Offset at, Color color) {
  var p = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 10, color: color)),
      textDirection: TextDirection.ltr)
    ..layout();
  p.paint(canvas, at);
}

/// _line strokes [path] in [accent], filled faintly beneath down to [floor].
void _line(Canvas canvas, Path path, Color accent, double floor,
    {double alpha = 1}) {
  var b = path.getBounds();
  var fill = Path.from(path)
    ..lineTo(b.right, floor)
    ..lineTo(b.left, floor)
    ..close();
  canvas.drawPath(
      fill, Paint()..color = accent.withValues(alpha: 0.18 * alpha));
  canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round);
}

/// EnvelopePainter draws a volume envelope: up, down to its sustain, held,
/// released -- its three dots to drag, or faint where the sound's own is
/// used.
class EnvelopePainter extends CustomPainter {
  final InstrumentShape shape;
  final Color accent, back, text;
  final bool faint;

  /// dots is whether its dots are drawn to drag: not on the chain's card.
  final bool dots;
  EnvelopePainter(this.shape,
      {required this.accent,
      required this.back,
      required this.text,
      this.faint = false,
      this.dots = true});

  @override
  void paint(Canvas canvas, Size size) {
    _screen(canvas, size, back);
    var (_, a, b, c, d, e) = envelopePoints(shape, size);
    var path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..lineTo(e.dx, e.dy);
    _line(canvas, path, accent, size.height - 6, alpha: faint ? 0.3 : 1);
    if (faint) {
      _say(canvas, "As the sound has it", const Offset(8, 4), text);
      return;
    }
    if (!dots) return;
    for (var p in [b, c, e]) {
      canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(
          p,
          4.5,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(EnvelopePainter old) =>
      old.shape != shape ||
      old.faint != faint ||
      old.dots != dots ||
      old.accent != accent;
}

/// filterGain is [s]'s filter's response at [hz], in decibels: the
/// analogue two-pole it is modelled on.
double filterGain(InstrumentShape s, double hz) {
  if (s.filter == SynthFilter.off) return 0;
  var w = hz / s.cutoff;
  var q = math.sqrt1_2 * math.pow(28, s.resonance);
  var den = math.sqrt(math.pow(1 - w * w, 2) + math.pow(w / q, 2));
  var g = switch (s.filter) {
    SynthFilter.lowPass => 1 / den,
    SynthFilter.highPass => w * w / den,
    SynthFilter.bandPass => (w / q) / den,
    SynthFilter.off => 1.0,
  };
  return 20 * math.log(math.max(g, 1e-6)) / math.ln10;
}

/// FilterPainter draws the filter's curve, 20Hz to 20kHz across, -36dB to
/// +24dB up, with its corner marked.
class FilterPainter extends CustomPainter {
  final InstrumentShape shape;
  final Color accent, back, text;
  FilterPainter(this.shape,
      {required this.accent, required this.back, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    _screen(canvas, size, back);
    double y(double db) =>
        (size.height - 4) -
        (db.clamp(-36.0, 24.0) + 36) / 60 * (size.height - 8);
    var path = Path();
    for (var x = 0.0; x <= size.width; x += 2) {
      var hz = 20 * math.pow(1000, x / size.width).toDouble();
      var yy = y(filterGain(shape, hz));
      x == 0 ? path.moveTo(x, yy) : path.lineTo(x, yy);
    }
    var on = shape.filter != SynthFilter.off;
    _line(canvas, path, accent, size.height, alpha: on ? 1 : 0.3);
    if (!on) {
      _say(canvas, "Off: the sound as it is", const Offset(8, 4), text);
      return;
    }
    var cx = math.log(shape.cutoff / 20) / math.log(1000) * size.width;
    canvas.drawCircle(Offset(cx, y(filterGain(shape, shape.cutoff))), 4.5,
        Paint()..color = Colors.white);
    _say(canvas, hertz(shape.cutoff), const Offset(8, 4), text);
  }

  @override
  bool shouldRepaint(FilterPainter old) => old.shape != shape;
}

/// LfoPainter draws two of the LFO's cycles, as tall as its depth.
class LfoPainter extends CustomPainter {
  final InstrumentShape shape;
  final Color accent, back, text;
  LfoPainter(this.shape,
      {required this.accent, required this.back, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    _screen(canvas, size, back);
    var mid = size.height / 2;
    var depth = math.max(0.06, shape.lfoDepth) * (mid - 6);
    var path = Path();
    for (var x = 0.0; x <= size.width; x += 2) {
      var yy = mid - math.sin(x / size.width * 4 * math.pi) * depth;
      x == 0 ? path.moveTo(x, yy) : path.lineTo(x, yy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: shape.lfoDepth > 0 ? 1 : 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    _say(
        canvas,
        shape.lfoDepth > 0
            ? "Moves the ${shape.lfoTarget.label.toLowerCase()}"
            : "No depth: it moves nothing",
        const Offset(8, 4),
        text);
  }

  @override
  bool shouldRepaint(LfoPainter old) => old.shape != shape;
}

/// VelocityPainter draws the velocity curve: how hard a key is struck
/// across, how loud it is heard up, the straight line as played.
class VelocityPainter extends CustomPainter {
  final InstrumentShape shape;
  final Color accent, back, text;
  VelocityPainter(this.shape,
      {required this.accent, required this.back, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    _screen(canvas, size, back);
    var w = size.width - 8, h = size.height - 8;
    canvas.drawLine(Offset(4, size.height - 4), Offset(size.width - 4, 4),
        Paint()..color = text.withValues(alpha: 0.4));
    var path = Path();
    for (var i = 1; i <= 127; i += 2) {
      var x = 4 + (i / 127) * w;
      var y = size.height - 4 - shape.velocity(i) / 127 * h;
      i == 1 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    _line(canvas, path, accent, size.height - 4);
    _say(
        canvas,
        "${shape.mode.label} · "
        "${shape.mode == VoiceMode.poly ? "${shape.voices} voices" : "glide ${seconds(shape.glide)}"}",
        const Offset(8, 4),
        text);
  }

  @override
  bool shouldRepaint(VelocityPainter old) => old.shape != shape;
}

/// InstrumentDevice is the instrument's card in the chain, after its MIDI
/// effects and before its sound's devices -- the Generator, as the
/// prototype draws it: its envelope (or filter, or voices) on its screen,
/// its main knobs on a row, how its voices go and what it plays like, and
/// the way into its editor.
class InstrumentDevice extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  final DeviceSkin skin;

  const InstrumentDevice({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    required this.skin,
    super.key,
  });

  @override
  State<InstrumentDevice> createState() => _InstrumentDeviceState();
}

/// _Screen is what the Instrument card's screen shows.
enum _Screen { envelope, filter, voices }

class _InstrumentDeviceState extends State<InstrumentDevice> {
  _Screen _screen = _Screen.envelope;

  CanvasController get c => widget.controller;

  void _set(InstrumentShape Function(InstrumentShape) change,
      {bool transient = false}) {
    c.beginInteraction();
    c.setInstrumentShape(widget.channel, change, transient: true);
    if (!transient) c.endInteraction();
  }

  /// _macroed is whether a macro of the chain turns its setting [id].
  bool _macroed(String id) => c.devicesOf(widget.channel).any((d) =>
      d.on &&
      d.kind == DeviceKind.macro &&
      d.mods.any((t) => t.device == instrumentTarget && t.param == id));

  /// _macroMenu is its knob [id]'s right-click: turned with any knob of the
  /// chain's macros, or -- with none yet -- macros added, turning it from
  /// their first.
  List<(String, VoidCallback)> _macroMenu(String id) {
    var devices = c.devicesOf(widget.channel);
    void give(int at, int knob) {
      var now = c.devicesOf(widget.channel);
      if (at >= now.length) return;
      var m = now[at];
      if (m.mods.any((t) =>
          t.device == instrumentTarget && t.param == id && t.from == knob)) {
        return;
      }
      c.beginInteraction();
      c.setDevicesOf(
          widget.channel,
          [...now]..[at] = m.withMods(
              [...m.mods, ModTarget(instrumentTarget, id, 0.5, knob)]));
      c.endInteraction();
    }

    var macros = [
      for (var (i, d) in devices.indexed)
        if (d.kind == DeviceKind.macro) i
    ];
    if (macros.isEmpty) {
      return [
        (
          "Turn it with Macro 1 (adds the chain's macros)",
          () {
            c.beginInteraction();
            c.setDevicesOf(widget.channel, [
              ...c.devicesOf(widget.channel),
              MixDevice(DeviceKind.macro,
                  mods: [ModTarget(instrumentTarget, id, 0.5, 0)]),
            ]);
            c.endInteraction();
          }
        ),
      ];
    }
    return [
      for (var at in macros)
        for (var k = 0; k < macroKnobs; k++)
          ("Turn it with Macro ${k + 1}", () => give(at, k)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    var part = c.instrumentOf(widget.channel)?.instrument;
    if (part == null) return const SizedBox();
    var s = part.shape;
    const d = InstrumentShape();
    var look = MixerLook.of(context);
    var studio = look.studio;
    Widget knob(
            DeviceTier tier,
            String key,
            String label,
            String text,
            double value,
            double initial,
            double min,
            double max,
            InstrumentShape Function(InstrumentShape, double) change,
            {bool log = false}) =>
        DeviceKnob(
          key: ValueKey(key),
          // Right-click: turned by one of the chain's macros (Ken).
          menu: _macroMenu(label.toLowerCase()),
          modulated: _macroed(label.toLowerCase()),
          label: label,
          text: text,
          value: value,
          initial: initial,
          min: min,
          max: max,
          log: log,
          size: switch (tier) {
            DeviceTier.large => 46,
            DeviceTier.medium => 38,
            _ => 28,
          },
          accent: midiColour,
          ink: studio.text,
          onChanged: (v, {transient = false}) =>
              _set((x) => change(x, v), transient: transient),
          onCommit: c.endInteraction,
        );
    Widget row(String label, Widget choices) => Row(children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: TextStyle(fontSize: 9.5, color: studio.muted)),
          ),
          Expanded(child: choices),
        ]);
    var screen = switch (_screen) {
      _Screen.envelope => EnvelopePainter(s,
          accent: midiColour,
          back: studio.display,
          faint: !s.envelope,
          dots: false,
          text: studio.muted),
      _Screen.filter => FilterPainter(s,
          accent: midiColour, back: studio.display, text: studio.muted),
      _Screen.voices => VelocityPainter(s,
          accent: midiColour, back: studio.display, text: studio.muted),
    };
    return DeviceFrame(
      id: "instrumentCard",
      title: "Instrument",
      help: "What plays the channel's notes. Its envelope, filter and "
          "voices are here; open its editor for all of them, the LFO and the "
          "velocity curve. The sound's own envelope is used until one of the "
          "envelope's knobs is turned.",
      skin: widget.skin,
      icon: Icons.piano,
      accent: midiColour,
      glows: true,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 392,
      height: widget.height,
      actions: [
        IconButton(
          key: const ValueKey("instrumentEdit"),
          tooltip: "Open its editor",
          icon: const Icon(Icons.open_in_new),
          onPressed: () => c.showInstrument(widget.channel),
        ),
      ],
      summary: "${part.name} · ${s.mode.label}",
      foldedBody: const SizedBox(),
      display: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            // Its screen, pressed: the editor, for every setting.
            onDoubleTap: () => c.showInstrument(widget.channel),
            child: CustomPaint(painter: screen),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Row(children: [
            for (var (i, v) in _Screen.values.indexed) ...[
              if (i > 0) const SizedBox(width: 3),
              GestureDetector(
                key: ValueKey("instrumentScreen-${v.name}"),
                onTap: () => setState(() => _screen = v),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: studio.panel.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color:
                            _screen == v ? look.colors.primary : studio.edge),
                  ),
                  child: Text(
                      switch (v) {
                        _Screen.envelope => "Envelope",
                        _Screen.filter => "Filter",
                        _Screen.voices => "Voices",
                      },
                      style: TextStyle(
                          fontSize: 9.5,
                          color: _screen == v ? studio.text : studio.muted)),
                ),
              ),
            ],
          ]),
        ),
        Positioned(
          left: 6,
          bottom: 4,
          child: IgnorePointer(
            child: Text("${part.name} · open for every setting",
                style: TextStyle(fontSize: 9.5, color: studio.muted)),
          ),
        ),
      ]),
      // Turned, the envelope's knobs give it an envelope of its own, and the
      // cutoff a filter: moving something is asking to hear it.
      controls: (tier) => [
        knob(
            tier,
            "instrumentCardAttack",
            "Attack",
            seconds(s.attack),
            s.attack,
            d.attack,
            0.001,
            10,
            (x, v) => x.copyWith(attack: v, envelope: true),
            log: true),
        knob(tier, "instrumentCardDecay", "Decay", seconds(s.decay), s.decay,
            d.decay, 0.01, 20, (x, v) => x.copyWith(decay: v, envelope: true),
            log: true),
        knob(
            tier,
            "instrumentCardSustain",
            "Sustain",
            "${(s.sustain * 100).round()}%",
            s.sustain,
            d.sustain,
            0,
            1,
            (x, v) => x.copyWith(sustain: v, envelope: true)),
        knob(
            tier,
            "instrumentCardRelease",
            "Release",
            seconds(s.release),
            s.release,
            d.release,
            0.01,
            20,
            (x, v) => x.copyWith(release: v, envelope: true),
            log: true),
        knob(
            tier,
            "instrumentCardCutoff",
            "Cutoff",
            hertz(s.cutoff),
            s.cutoff,
            d.cutoff,
            20,
            20000,
            (x, v) => x.copyWith(
                cutoff: v,
                filter: x.filter == SynthFilter.off
                    ? SynthFilter.lowPass
                    : x.filter),
            log: true),
        knob(tier, "instrumentCardGlide", "Glide", seconds(s.glide), s.glide,
            d.glide, 0, 5, (x, v) => x.copyWith(glide: v)),
        row(
            "Voices",
            DeviceChoices(options: [
              for (var m in VoiceMode.values)
                (
                  ValueKey("instrumentCardMode-${m.name}"),
                  m.label,
                  s.mode == m,
                  () => _set((x) => x.copyWith(mode: m)),
                ),
            ])),
        row(
            "Plays like",
            DeviceChoices(options: [
              for (var l in InstrumentLook.values)
                (
                  ValueKey("instrumentCardLook-${l.name}"),
                  l.label,
                  part.look == l,
                  () {
                    c.beginInteraction();
                    c.setChannelPart(widget.channel, (p) => p.withLook(l));
                    c.endInteraction();
                  },
                ),
            ])),
      ],
      body: const SizedBox(),
    );
  }
}

/// NoteClipsDevice is a MIDI channel's source, first in its chain as the
/// prototype's Note clips: its part's notes, drawn small; how long it is
/// and how many clips its slots hold; and the way into the piano roll.
class NoteClipsDevice extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  final DeviceSkin skin;

  const NoteClipsDevice({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    required this.skin,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var studio = MixerLook.of(context).studio;
    var part = c.instrumentOf(channel)?.instrument;
    var notes = part?.notes ?? const <MidiNote>[];
    var clips = [
      for (var s in c.session.slots[channel] ?? const <SessionClip?>[])
        if (s != null && s.midi) s
    ];
    var seconds = notes.isEmpty
        ? 0.0
        : notes.map((n) => n.start + n.length).reduce(math.max);
    var beat = 60 / c.document.audio.tempo;
    var bars = (seconds / beat / c.document.audio.beatsPerBar).ceil();
    var muted = TextStyle(fontSize: 10, color: studio.muted);
    var strong = TextStyle(fontSize: 10.5, color: studio.text);
    Widget fact(String label, String value) => Row(children: [
          SizedBox(width: 52, child: Text(label, style: muted)),
          Flexible(
              child: Text(value,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: strong)),
        ]);
    return DeviceFrame(
      id: "noteClips",
      title: "Note clips",
      help: "What the channel plays: its part on the timeline, and the note "
          "clips in its slots. Open the piano roll to draw and edit notes.",
      skin: skin,
      icon: Icons.music_note,
      accent: midiColour,
      folded: folded,
      onFold: onFold,
      width: 300,
      height: height,
      actions: [
        IconButton(
          key: const ValueKey("noteClipsEdit"),
          tooltip: "Open the piano roll",
          icon: const Icon(Icons.open_in_new),
          onPressed: () => c.openPianoRoll(channel),
        ),
      ],
      summary: notes.isEmpty
          ? "No notes"
          : "${notes.length} notes · $bars bar${bars == 1 ? "" : "s"}",
      foldedBody: const SizedBox(),
      display: GestureDetector(
        key: const ValueKey("noteClipsRoll"),
        onDoubleTap: () => c.openPianoRoll(channel),
        child: CustomPaint(
          size: Size.infinite,
          painter: _MiniRollPainter(notes,
              accent: midiColour, back: studio.display, line: studio.edge),
          child: notes.isEmpty
              ? Center(
                  child: Text("No notes yet: open the piano roll to draw some",
                      textAlign: TextAlign.center, style: muted))
              : null,
        ),
      ),
      controls: (tier) => [
        SizedBox(
          width: 170,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fact(
                    "Part",
                    notes.isEmpty
                        ? "empty"
                        : "${notes.length} notes, $bars "
                            "bar${bars == 1 ? "" : "s"}"),
                const SizedBox(height: 3),
                fact("Slots",
                    clips.isEmpty ? "no note clips" : "${clips.length} clips"),
              ]),
        ),
      ],
      body: const SizedBox(),
    );
  }
}

/// _MiniRollPainter draws notes small: each a bar at its key and its time,
/// the lowest note at the foot and the highest at the top.
class _MiniRollPainter extends CustomPainter {
  final List<MidiNote> notes;
  final Color accent, back, line;
  _MiniRollPainter(this.notes,
      {required this.accent, required this.back, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    var r =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = back);
    if (notes.isEmpty) return;
    var low = notes.map((n) => n.key).reduce(math.min) - 1;
    var high = notes.map((n) => n.key).reduce(math.max) + 1;
    var end = notes.map((n) => n.start + n.length).reduce(math.max);
    if (end <= 0) return;
    var rows = math.max(1, high - low + 1);
    var rowH = (size.height - 8) / rows;
    var paint = Paint()..color = accent;
    for (var n in notes) {
      var x = 4 + (size.width - 8) * n.start / end;
      var w = math.max(2.0, (size.width - 8) * n.length / end - 1);
      var y = 4 + (high - n.key) * rowH;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, w, math.max(2.0, rowH - 1)),
              const Radius.circular(1.5)),
          paint..color = accent.withValues(alpha: n.muted ? 0.35 : 0.95));
    }
  }

  @override
  bool shouldRepaint(_MiniRollPainter old) =>
      !identical(old.notes, notes) || old.accent != accent || old.back != back;
}

/// ZoneMap is a sound's zones, as the Zones card draws them: which sample
/// group plays at each key (21 to 108) and each band of velocity, and how
/// many layers and key ranges that makes.
class ZoneMap {
  static const lowKey = 21, keys = 88, bands = 16;

  /// cells are the group at each band (from the softest) of each key: the
  /// same number, the same samples.
  final List<List<int>> cells;
  final int layers, ranges;
  const ZoneMap(this.cells, this.layers, this.ranges);
}

final Map<(SoundFont, int, int), ZoneMap> _zoneMaps = {};

/// zoneMap is [font]'s zones for the sound at [bank] and [program], worked
/// out once.
ZoneMap? zoneMap(SoundFont font, int bank, int program) {
  var key = (font, bank, program);
  if (_zoneMaps[key] case var m?) return m;
  var preset = font.preset(bank, program);
  if (preset == null) return null;
  var groups = <String, int>{};
  int groupOf(int k, int v) {
    var names = [for (var z in font.zones(preset, k, v)) z.sample.name]..sort();
    if (names.isEmpty) return -1;
    return groups.putIfAbsent(names.join("|"), () => groups.length);
  }

  var cells = [
    for (var k = 0; k < ZoneMap.keys; k++)
      [
        for (var b = 0; b < ZoneMap.bands; b++)
          groupOf(ZoneMap.lowKey + k, 1 + b * 8)
      ],
  ];
  // Layers: the most groups any one key changes through, softest to
  // hardest; ranges: the groups along the keys, played moderately hard.
  var layers = 1;
  for (var col in cells) {
    var n = col.where((g) => g >= 0).toSet().length;
    if (n > layers) layers = n;
  }
  var ranges = 0, last = -2;
  for (var col in cells) {
    var g = col[12];
    if (g >= 0 && g != last) ranges++;
    last = g;
  }
  return _zoneMaps[key] = ZoneMap(cells, layers, math.max(1, ranges));
}

/// _ZonesPainter draws a ZoneMap: keys along, velocity up, each group of
/// samples its own shade; with none, one zone over all of it.
class _ZonesPainter extends CustomPainter {
  final ZoneMap? map;
  final Color accent, back, text;
  _ZonesPainter(this.map,
      {required this.accent, required this.back, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    var m = map;
    if (m == null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              (Offset.zero & size).deflate(6), const Radius.circular(3)),
          Paint()..color = accent.withValues(alpha: 0.25));
      return;
    }
    var w = size.width / ZoneMap.keys, h = size.height / ZoneMap.bands;
    for (var (k, col) in m.cells.indexed) {
      for (var (b, g) in col.indexed) {
        if (g < 0) continue;
        // Neighbouring groups told apart by how light they are.
        var shade = 0.25 + 0.6 * ((g * 37) % 11) / 10;
        canvas.drawRect(
            Rect.fromLTWH(k * w, size.height - (b + 1) * h, w + 0.5, h + 0.5),
            Paint()..color = accent.withValues(alpha: shade));
      }
    }
  }

  @override
  bool shouldRepaint(_ZonesPainter old) =>
      old.map != map || old.accent != accent || old.back != back;
}
