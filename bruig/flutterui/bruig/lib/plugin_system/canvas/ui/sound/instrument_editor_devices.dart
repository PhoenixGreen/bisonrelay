part of 'instrument_editor.dart';

// The cards a MIDI channel shows in its chain: the instrument's own card, and
// the note clips card that is its source, with its notes drawn small. Part of
// instrument_editor.dart.

/// InstrumentDevice is the instrument's card in the chain, between its MIDI
/// effects and its sound's devices: its envelope, filter or voices on its
/// screen, its main knobs, its voicing, and the way into its editor.
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

  bool _macroed(String id) => c.devicesOf(widget.channel).any((d) =>
      d.on &&
      d.kind == DeviceKind.macro &&
      d.mods.any((t) => t.device == instrumentTarget && t.param == id));

  /// _macroMenu is knob [id]'s right-click menu: turn it with any chain
  /// macro, or with none yet, add macros and turn it from the first.
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
          // Right-click: turned by one of the chain's macros.
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
      // How it plays its notes with a second set to compare, or back to plain;
      // the sound itself kept.
      onAB: () => c.toggleABOf("${widget.channel}|instrument", s,
          (o) => _set((_) => o as InstrumentShape, transient: true)),
      showingB: c.showingBOf("${widget.channel}|instrument"),
      onReset: () => _set((_) => const InstrumentShape()),
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

/// NoteClipsDevice is a MIDI channel's source, first in its chain: its
/// part's notes drawn small, its length and slots, and the way into the
/// piano roll.
class NoteClipsDevice extends StatefulWidget {
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
  State<NoteClipsDevice> createState() => _NoteClipsDeviceState();
}

class _NoteClipsDeviceState extends State<NoteClipsDevice> {
  /// _picked is the row of the slot whose clip the card's Length sets.
  int? _picked;

  @override
  Widget build(BuildContext context) {
    var c = widget.controller;
    var channel = widget.channel;
    var skin = widget.skin;
    var folded = widget.folded;
    var onFold = widget.onFold;
    var height = widget.height;
    var studio = MixerLook.of(context).studio;
    var part = c.instrumentOf(channel)?.instrument;
    var notes = part?.notes ?? const <MidiNote>[];
    var slots = c.session.slots[channel] ?? const <SessionClip?>[];
    var clips = [
      for (var (row, s) in slots.indexed)
        if (s != null && s.midi) (row, s)
    ];
    var picked =
        clips.where((x) => x.$1 == _picked).firstOrNull ?? clips.firstOrNull;
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
        // Its feel as it plays: pulled onto the grid and swung; the notes drawn
        // are left as they are.
        if (part != null)
          for (var (key, label, value, change) in [
            (
              "noteQuantise",
              "Quantise",
              part.quantise,
              (InstrumentPart p, double v) => p.copyWith(quantise: v)
            ),
            (
              "noteSwing",
              "Swing",
              part.swing,
              (InstrumentPart p, double v) => p.copyWith(swing: v)
            ),
          ])
            DeviceKnob(
              key: ValueKey(key),
              label: label,
              text: "${(value * 100).round()}%",
              value: value,
              initial: 0,
              min: 0,
              max: 1,
              size: switch (tier) {
                DeviceTier.large => 46,
                DeviceTier.medium => 38,
                _ => 28,
              },
              accent: midiColour,
              ink: studio.text,
              onChanged: (v, {transient = false}) {
                c.beginInteraction();
                c.setChannelPart(channel, (p) => change(p, v), transient: true);
                if (!transient) c.endInteraction();
              },
              onCommit: c.endInteraction,
            ),
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
        // Its note clips as chips: pressed to launch or stop, picked for
        // Length.
        if (clips.isNotEmpty && tier != DeviceTier.small)
          SizedBox(
            width: 260,
            child: SingleChildScrollView(
              key: const ValueKey("noteClipsChips"),
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var (row, clip) in clips)
                  _noteChip(c, row, clip, picked?.$1 == row, studio),
              ]),
            ),
          ),
        if (picked case (var row, var clip))
          StudioDrop<double>(
            key: const ValueKey("noteClipsLength"),
            label: "Length",
            width: 120,
            value: clipBarChoices.contains(clip.bars.round()) &&
                    clip.bars == clip.bars.roundToDouble()
                ? clip.bars
                : -1,
            options: [
              if (!(clipBarChoices.contains(clip.bars.round()) &&
                  clip.bars == clip.bars.roundToDouble()))
                (-1, "${clip.bars} bars"),
              for (var b in clipBarChoices)
                (b.toDouble(), b == 1 ? "1 bar" : "$b bars"),
            ],
            onChanged: (b) {
              if (b <= 0) return;
              c.setSessionClip(channel, row, clip.copyWith(bars: b));
            },
          ),
      ],
      body: const SizedBox(),
    );
  }

  /// _noteChip is one slot's note clip: its name and a play mark, ringed
  /// while it plays.
  Widget _noteChip(CanvasController c, int row, SessionClip clip, bool on,
      StudioColors studio) {
    var state = c.clipState(widget.channel, row);
    var playing = state == ClipState.playing || state == ClipState.queued;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: on ? midiColour.withValues(alpha: 0.35) : studio.raised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
                color: playing
                    ? const Color(0xFF3FB950)
                    : on
                        ? midiColour
                        : studio.edge,
                width: playing ? 1.6 : 1)),
        child: InkWell(
          key: ValueKey("noteClipsChip-$row"),
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => _picked = row),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                key: ValueKey("noteClipsLaunch-$row"),
                onTap: () {
                  setState(() => _picked = row);
                  playing
                      ? c.stopChannelClips(widget.channel)
                      : c.launchClip(widget.channel, row);
                },
                child: Icon(
                    playing ? Icons.radio_button_checked : Icons.play_arrow,
                    size: 14,
                    color: playing ? const Color(0xFF3FB950) : studio.text),
              ),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(clip.name.isEmpty ? "Slot ${row + 1}" : clip.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: studio.text)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// _MiniRollPainter draws notes small, each a bar at its key and time.
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
