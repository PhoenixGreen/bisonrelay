import 'package:flutter/foundation.dart' show mapEquals;
import 'package:bruig/plugin_system/canvas/model/fretting.dart' show FretPlace;
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart'
    show SessionClip, clipBarChoices;
import 'package:bruig/plugin_system/canvas/model/devices.dart'
    show DeviceGroup, DeviceKind, MixDevice;
import 'package:bruig/plugin_system/canvas/model/modulation.dart'
    show ModTarget, macroKnobs;
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart'
    show loadSoundBank;
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_cards.dart'
    show StudioDrop;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, KeyEvent, LogicalKeyboardKey;

part 'instrument_editor_keyboard.dart';
part 'instrument_editor_pictures.dart';
part 'instrument_editor_devices.dart';

// instrument_editor.dart is the Instrument editor, in the Chain: how a MIDI
// channel's instrument plays its sound (instrument_shape.dart). Each card
// is knobs over a picture of what it does: the volume envelope, a filter
// with its own envelope, an LFO, and the voices (mono or poly, glide, bend
// range, tuning, velocity curve). Also the instrument's card in the chain.

/// Each card's colour is its device family's (see deviceGroupLook).
Color get _envelopeAccent => deviceGroupLook(DeviceGroup.dynamics).$2;
Color get _filterAccent => deviceGroupLook(DeviceGroup.filter).$2;
Color get _voicesAccent => const Color(0xFF9A92EA);

String seconds(double s) => s < 1
    ? "${(s * 1000).round()} ms"
    : "${s.toStringAsFixed(s < 10 ? 2 : 1)} s";

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

/// keyRow is the computer keys that play the keyboard from its lowest C
/// up: white on the home row, black above it.
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

  /// _dragging is the envelope dot dragged: 0 peak, 1 sustain, 2 release end.
  int? _dragging;

  String _find = "";

  /// _font is the sound bank, read for the Zones card once its sound is the
  /// bank's; _fontAsked whether it has been asked for.
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

  /// _sounds is the sound browser: General MIDI's sounds by family, filtered
  /// as typed.
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

  /// _cards are the cards side by side, scrolled where they do not fit.
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

  /// _zonesCard draws the samples the sound is made of by key and velocity,
  /// with how many velocity layers a key has and how many ranges the keys
  /// are split into.
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

  /// _card is one of the editor's cards: a coloured top, a title in
  /// capitals, a picture, a row of knobs and a choice under them.
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
        // Short: knobs and choice without the picture, scrolled if still too
        // tall.
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
          // Across for its corner, up and down for its resonance; this switches
          // a filter on where there was none.
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
