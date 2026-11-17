part of 'clip_editor.dart';

// The layout, and its columns: parts, clips, launches and notes. Part of
// _ClipEditorState: its fields, lifecycle and build are in clip_editor.dart.

extension _ClipEditorColumns on _ClipEditorState {
  /// _layout is the editor: its header over its settings columns, and what
  /// it plays beside them.
  Widget _layout(MixerLook look, Widget? header,
      List<(String, List<Widget>, String)> settings, Widget editor) {
    var columns = [
      for (var (title, children, key) in settings)
        _column(look, title, children, key: ValueKey(key)),
    ];
    var shown = _shown.clamp(0, columns.length - 1);
    var kind = widget.part ? "roll" : "clip";
    var shut = c.settingsShut(kind);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (header != null) header,
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: editor),
          Container(width: 1, color: look.studio.edge),
          if (shut)
            _shutStrip(look, settings.map((s) => s.$1).join(" · "), kind)
          else if (widget.wide) ...[
            Column(children: [
              const SizedBox(height: 4),
              _foldButton(look, kind),
              Expanded(child: _columnsButton(look, wide: true)),
            ]),
            ...columns,
          ] else
            SizedBox(
              width: _columnW,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: Row(children: [
                        Expanded(
                          child: Wrap(spacing: 3, runSpacing: 3, children: [
                            for (var (i, (label, _, _)) in settings.indexed)
                              _pill(look, label, i == shown,
                                  () => setState(() => _shown = i),
                                  key: ValueKey("clipShow-$i")),
                          ]),
                        ),
                        if (widget.canWiden) _columnsButton(look, wide: false),
                        _foldButton(look, kind),
                      ]),
                    ),
                    Expanded(child: columns[shown]),
                  ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _shutStrip(MixerLook look, String names, String kind) => Tooltip(
        message: "Show $names",
        child: InkWell(
          key: const ValueKey("editorSettingsOpen"),
          onTap: () => c.toggleSettingsShut(kind),
          child: SizedBox(
            width: 24,
            child: Column(children: [
              const SizedBox(height: 6),
              Icon(Icons.chevron_left, size: 16, color: look.studio.muted),
              const SizedBox(height: 6),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: Text(names,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style:
                          TextStyle(fontSize: 10.5, color: look.studio.muted)),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _foldButton(MixerLook look, String kind) => Tooltip(
        message: "Hide the settings",
        child: InkWell(
          key: const ValueKey("editorSettingsShut"),
          borderRadius: BorderRadius.circular(5),
          onTap: () => c.toggleSettingsShut(kind),
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(Icons.last_page, size: 16, color: look.studio.muted),
          ),
        ),
      );

  /// _columnsButton shows every settings column, or folds them to one.
  Widget _columnsButton(MixerLook look, {required bool wide}) => Tooltip(
        message: wide ? "Show one column" : "Show every column",
        child: InkWell(
          key: const ValueKey("editorWide"),
          borderRadius: BorderRadius.circular(5),
          onTap: c.toggleEditorWide,
          child: SizedBox(
            width: 22,
            height: wide ? null : 22,
            child: Align(
              alignment: wide ? Alignment.topCenter : Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(top: wide ? 8 : 0),
                child: Icon(wide ? Icons.chevron_right : Icons.chevron_left,
                    size: 16, color: look.studio.muted),
              ),
            ),
          ),
        ),
      );

  /// _partLaunchColumn is a part's Launch: it plays with the timeline, but a
  /// copy in a slot is launched as any clip is.
  List<Widget> _partLaunchColumn(MixerLook look, String channel) {
    var row = c.emptySlotOf(channel);
    return [
      Text(
          "A part plays with the timeline, from where it starts. To launch "
          "it, copy it into a slot: its launch settings are there.",
          style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: _pill(
            look, "Copy into a slot", false, row == null ? null : c.partToSlot,
            key: const ValueKey("partToSlot"),
            tip: row == null
                ? "Every slot of the channel is full"
                : "Into slot ${row + 1}, and open it there"),
      ),
      if (row == null) ...[
        const SizedBox(height: 4),
        Text("Every slot of the channel is full.",
            style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
      ],
    ];
  }

  /// _partColumn is a part's timeline start, its length in the roll, and the
  /// playhead's place in it (where a paste goes and Play starts).
  List<Widget> _partColumn(
      MixerLook look, AudioElement e, RollContent content) {
    var a = c.document.audio;
    var startBeats = e.clip.at /
        math.max(1, c.document.frameRate) /
        math.max(0.001, a.secondsPerBeat);
    var bars = content.beats / a.beatsPerBar;
    var cursor = c.rollCursor;
    return [
      _row(
          look,
          "Starts",
          _stepper(
              look,
              "partStart",
              _place(startBeats),
              e.clip.at <= 0 ? null : () => c.movePart(-1),
              () => c.movePart(1))),
      _row(
          look,
          "Length",
          Text(bars == 1 ? "1 bar" : "${bars.round()} bars",
              key: const ValueKey("partLength"), style: _small(look))),
      _row(
          look,
          "Playhead",
          _stepper(
              look,
              "partCursor",
              _place(cursor),
              cursor <= 0
                  ? null
                  : () => c.rollCursor = (cursor - 1).ceilToDouble(),
              () => c.rollCursor = (cursor + 1).floorToDouble())),
      Text(
          "Where a paste goes, and Play starts. Drag it along the ruler "
          "over the notes.",
          style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
    ];
  }

  TextStyle _small(MixerLook look, [Color? colour]) =>
      TextStyle(fontSize: 11, color: colour ?? look.studio.text);

  Widget _pill(MixerLook look, String label, bool on, VoidCallback? onTap,
          {Key? key, String? tip}) =>
      Tooltip(
        message: tip ?? label,
        child: Material(
          color: on ? look.studio.on : look.studio.raised,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: BorderSide(color: on ? look.studio.on : look.studio.edge)),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(5),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: onTap == null
                          ? look.studio.muted
                          : on
                              ? look.studio.onOn
                              : look.studio.text)),
            ),
          ),
        ),
      );

  Widget _drop<T>(MixerLook look, Key key, T value, List<(String, T)> items,
          ValueChanged<T> onChanged) =>
      Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: look.studio.inset,
          border: Border.all(color: look.studio.edge),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButton<T>(
          key: key,
          value: value,
          isDense: true,
          isExpanded: true,
          underline: const SizedBox(),
          iconSize: 14,
          iconEnabledColor: look.studio.muted,
          style: _small(look).copyWith(fontSize: 10.5),
          dropdownColor: look.colors.surfaceContainerHigh,
          items: [
            for (var (label, v) in items)
              DropdownMenuItem(
                  value: v,
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );

  Widget _row(MixerLook look, String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          SizedBox(
              width: 64,
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _small(look, look.studio.muted))),
          Expanded(child: child),
        ]),
      );

  Widget _stepper(MixerLook look, String key, String value, VoidCallback? down,
      VoidCallback? up,
      {ValueChanged<String>? typed}) {
    var style = _small(look).copyWith(fontFeatures: const [
      FontFeature.tabularFigures(),
    ]);
    return Row(children: [
      _step(look, "$key-down", Icons.remove, down),
      Expanded(
        child: typed == null
            ? Text(value,
                key: ValueKey(key),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style)
            : _TypedPlace(
                key: ValueKey(key), value: value, style: style, onTyped: typed),
      ),
      _step(look, "$key-up", Icons.add, up),
    ]);
  }

  Widget _step(
          MixerLook look, String key, IconData icon, VoidCallback? onTap) =>
      InkWell(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
              color: look.studio.raised,
              borderRadius: BorderRadius.circular(3)),
          child: Icon(icon,
              size: 12,
              color: onTap == null ? look.studio.muted : look.studio.text),
        ),
      );

  /// _head is a column's heading: small, uppercase, quiet, [end] at right.
  Widget _head(MixerLook look, String title, {String? end, Key? key}) {
    var style = TextStyle(
        fontSize: 10,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: look.studio.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(
            child: Text(title.toUpperCase(),
                key: key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style)),
        if (end != null) Text(end.toUpperCase(), style: style),
      ]),
    );
  }

  Widget _column(MixerLook look, String title, List<Widget> children,
          {Key? key}) =>
      Container(
        key: key,
        width: _columnW,
        decoration: BoxDecoration(
            border: Border(right: BorderSide(color: look.studio.edge))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _head(look, title),
            ...children,
          ]),
        ),
      );

  /// _envelopeChoices are what an audio clip's envelope can change: its own
  /// gain and pan, drawn into its sound, then its channel's settings, moved
  /// on the channel while it plays.
  List<(String, String)> _envelopeChoices(SessionClip clip, PianoRollTarget t) {
    var lane = c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    var returns = c.document.returns;
    return [
      for (var e in ClipEnvelope.values) ("Clip › ${e.label}", e.name),
      if (lane != null)
        for (var a in automationTargets(lane.mix, returns))
          (settingLabel(a, lane.mix, returns), a.id),
    ];
  }

  /// _envelopeKey is the chosen envelope while its channel has it, else gain.
  String _envelopeKey(SessionClip clip, PianoRollTarget t) {
    var key = _envelope;
    if (key != null && _envelopeChoices(clip, t).any((c) => c.$2 == key)) {
      return key;
    }
    return ClipEnvelope.gain.name;
  }

  /// _envelopeRest is envelope [key]'s height with no points.
  double _envelopeRest(String key, PianoRollTarget t) {
    for (var e in ClipEnvelope.values) {
      if (e.name == key) return e.rest;
    }
    var what = AutomationTarget.parse(key);
    var lane = c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    if (what == null || lane == null) return 0.5;
    return what.height(what.own(lane.mix));
  }

  /// _place is a place in a clip as bar.beat.sixteenth, from one.
  String _place(double beats) {
    var bpb = c.document.audio.beatsPerBar;
    var bar = (beats / bpb).floor() + 1;
    var beat = (beats % bpb).floor() + 1;
    var sixteenth = ((beats % 1) * 4).floor() + 1;
    return "$bar.$beat.$sixteenth";
  }

  /// _secondsAt and _beatsAt convert a place in [clip] in beats to seconds
  /// into its sound and back: by its warp map when warped, else at the
  /// song's tempo (faster with its pitch).
  double _secondsAt(SessionClip clip, double beats) {
    var spb = math.max(0.001, c.document.audio.secondsPerBeat);
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    return clip.warp ? clip.warpMap.sourceAt(beats) : beats * spb * speed;
  }

  double _beatsAt(SessionClip clip, double seconds) {
    var spb = math.max(0.001, c.document.audio.secondsPerBeat);
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    return clip.warp ? clip.warpMap.beatAt(seconds) : seconds / speed / spb;
  }

  List<Widget> _clipColumn(MixerLook look, SessionClip clip) {
    var bpb = c.document.audio.beatsPerBar;
    // A place typed as "3", "3.2" or "3.2.3"; anything else is ignored.
    ValueChanged<String> typed(
            SessionClip Function(SessionClip x, double beats) change) =>
        (text) {
          if (beatsOfPlace(text, bpb) case var b?) {
            c.editClip((x) => change(x, b));
          }
        };
    var bars = clip.bars;
    var lengths = {
      0.25, 0.5, //
      ...clipBarChoices.map((b) => b.toDouble()),
      bars,
    }.toList()
      ..sort();
    String barsText(double b) =>
        b == 1 ? "1 bar" : "${b == b.roundToDouble() ? b.round() : b} bars";
    var readout = _small(look).copyWith(
        fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()]);
    Widget place(String key, String value, ValueChanged<String> onTyped) =>
        _TypedPlace(
            key: ValueKey(key),
            value: value,
            style: readout,
            align: TextAlign.left,
            onTyped: onTyped);
    return [
      _row(
          look,
          "Starts",
          // A place or a time ("0.18s", "180ms"): a sound's start is set by
          // ear.
          place(
              "clipStart",
              "${_place(clip.start)} · "
                  "${_secondsAt(clip, clip.start).toStringAsFixed(2)}s",
              (text) {
            var t = text.trim().toLowerCase();
            var ms = RegExp(r"^([0-9.]+)\s*ms$").firstMatch(t);
            var sec = RegExp(r"^([0-9.]+)\s*s$").firstMatch(t);
            var seconds = ms != null
                ? (double.tryParse(ms.group(1)!) ?? -1) / 1000
                : sec != null
                    ? double.tryParse(sec.group(1)!) ?? -1
                    : null;
            if (seconds != null) {
              if (seconds >= 0) {
                c.editClip((x) => x.copyWith(start: _beatsAt(x, seconds)));
              }
              return;
            }
            typed((x, b) => x.copyWith(start: b))(text);
          })),
      _row(
          look,
          "Loop",
          Row(children: [
            Flexible(
              child: place("clipLoopStart", _place(clip.loopStart),
                  typed((x, b) => x.copyWith(loopStart: b))),
            ),
            Text(" – ", style: readout),
            Flexible(
              child: place(
                  "clipEnds",
                  _place(clip.loopEnd(bpb)),
                  typed((x, b) => b > x.loopStart
                      ? x.copyWith(bars: (b - x.loopStart) / bpb)
                      : x)),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: clip.loop
                  ? "Loops: round until it is stopped"
                  : "Plays once through",
              child: InkWell(
                key: const ValueKey("clipLoop"),
                borderRadius: BorderRadius.circular(4),
                onTap: () => c.editClip((x) => x.copyWith(loop: !x.loop)),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.repeat,
                      size: 15,
                      color: clip.loop ? look.studio.on : look.studio.muted),
                ),
              ),
            ),
          ])),
      _row(
          look,
          "Length",
          _drop(
              look,
              const ValueKey("clipLength"),
              bars,
              [for (var b in lengths) (barsText(b), b)],
              (v) => c.editClip((x) => x.copyWith(bars: v)))),
      _row(
          look,
          "Colour",
          Align(
            alignment: Alignment.centerLeft,
            child: MenuAnchor(
              menuChildren: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Wrap(spacing: 4, runSpacing: 4, children: [
                    for (var (i, colour) in sectionColors.indexed)
                      GestureDetector(
                        key: ValueKey("clipColour-$i"),
                        onTap: () => c.editClip((x) => x.copyWith(color: i)),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                              color: Color(colour),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                  color: i == clip.color
                                      ? look.studio.text
                                      : Colors.transparent,
                                  width: 2)),
                        ),
                      ),
                  ]),
                ),
              ],
              builder: (context, menu, _) => InkWell(
                key: const ValueKey("clipColour"),
                onTap: () => menu.isOpen ? menu.close() : menu.open(),
                child: Container(
                  width: 28,
                  height: 16,
                  decoration: BoxDecoration(
                      color: Color(
                          sectionColors[clip.color % sectionColors.length]),
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          )),
    ];
  }

  List<Widget> _launchColumn(MixerLook look, SessionClip clip) => [
        _row(
            look,
            "Pressed",
            Tooltip(
              message: clip.launch.hint,
              child: _drop(
                  look,
                  const ValueKey("clipLaunchMode"),
                  clip.launch,
                  [for (var m in LaunchMode.values) (m.label, m)],
                  (v) => c.editClip((x) => x.copyWith(launch: v))),
            )),
        _row(
            look,
            "Waits for",
            _drop<Quantise?>(
                look,
                const ValueKey("clipQuantise"),
                clip.quantise,
                [
                  ("The song's", null),
                  for (var q in Quantise.values)
                    (q == Quantise.off ? "Nothing" : q.label, q),
                ],
                (v) => c.editClip((x) => v == null
                    ? x.copyWith(clearQuantise: true)
                    : x.copyWith(quantise: v)))),
        _row(
            look,
            "Then",
            _drop(
                look,
                const ValueKey("clipFollow"),
                clip.follow,
                [for (var f in FollowAction.values) (f.label, f)],
                (v) => c.editClip((x) => x.copyWith(follow: v)))),
        if (clip.follow != FollowAction.none)
          _row(
              look,
              "After",
              _drop<double?>(
                  look,
                  const ValueKey("clipFollowAfter"),
                  clip.followBars,
                  [
                    ("Its loop", null),
                    for (var b in const [1.0, 2.0, 4.0, 8.0, 16.0])
                      (b == 1 ? "1 bar" : "${b.round()} bars", b),
                    if (clip.followBars case var f?
                        when !const [1.0, 2.0, 4.0, 8.0, 16.0].contains(f))
                      ("$f bars", f),
                  ],
                  (v) => c.editClip((x) => v == null
                      ? x.copyWith(clearFollowBars: true)
                      : x.copyWith(followBars: v)))),
        // Take over from where the clip playing on the channel had got to.
        _row(
            look,
            "Legato",
            Tooltip(
              message: "Take over from where the clip playing on the "
                  "channel had got to, rather than from the start",
              child: _drop(
                  look,
                  const ValueKey("clipLegato"),
                  clip.legato,
                  const [("From its start", false), ("Takes over", true)],
                  (v) => c.editClip((x) => x.copyWith(legato: v))),
            )),
        // How much a pad's velocity (a Push launching it) sets the loudness; a
        // click is full velocity.
        _row(
            look,
            "Velocity",
            Tooltip(
              message: "How much a pad's velocity sets how loud it plays",
              child: _drop(
                  look,
                  const ValueKey("clipVelocity"),
                  (clip.velocity * 4).round() / 4,
                  [
                    for (var v in const [0.0, 0.25, 0.5, 0.75, 1.0])
                      ("${(v * 100).round()}%", v)
                  ],
                  (v) => c.editClip((x) => x.copyWith(velocity: v))),
            )),
      ];

  List<Widget> _notesColumn(MixerLook look) {
    Widget tool(NoteTool t, String tip) =>
        _pill(look, t.label, false, () => c.useNoteTool(t),
            key: ValueKey("noteTool-${t.name}"), tip: tip);
    var picked = c.rollSelected.length;
    var all = c.rollContent?.notes.length ?? 0;
    Widget group(List<Widget> tools) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 4, runSpacing: 4, children: tools),
        );
    return [
      Text(
          picked == 0
              ? "On every note -- or pick some in the notes: drag across "
                  "empty space, Shift-click to add one."
              : "On the $picked note${picked == 1 ? "" : "s"} picked.",
          key: const ValueKey("notesToolsOn"),
          style: _small(look, look.studio.muted).copyWith(fontSize: 10.5)),
      Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 2),
        child: Text("$all in all",
            style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
      ),
      _head(look, "Transpose"),
      group([
        tool(NoteTool.down, "Down a semitone"),
        tool(NoteTool.up, "Up a semitone"),
        tool(NoteTool.octaveDown, "Down an octave"),
        tool(NoteTool.octaveUp, "Up an octave"),
        tool(NoteTool.fitToScale,
            "Each to the nearest note of the channel's scale"),
      ]),
      _head(look, "Transform", end: picked == 0 ? "Every note" : "Picked"),
      group([
        tool(
            NoteTool.humanise,
            "A little off the grid, a little louder "
            "or softer"),
        tool(NoteTool.legato, "Each held until the next"),
        tool(NoteTool.strum, "A chord's notes one after another, upwards"),
        tool(NoteTool.reverse, "Played backwards"),
        tool(NoteTool.invert, "Upside down: the highest the lowest"),
        tool(NoteTool.faster, "Twice as fast"),
        tool(NoteTool.slower, "Half as fast"),
        tool(NoteTool.crescendo, "Softer to louder, first to last"),
        tool(NoteTool.chop, "Each cut in two"),
        tool(NoteTool.join, "Notes of one key that touch made one"),
        tool(NoteTool.swing, "Every second sixteenth a little late"),
        tool(NoteTool.duplicate, "A copy after them"),
      ]),
      _head(look, "Generate"),
      group([
        tool(NoteTool.arpeggiate, "Each chord's notes one after another"),
        tool(NoteTool.rhythm, "Five notes in every eight sixteenths"),
        tool(NoteTool.fillChords, "The scale's chord on each note"),
        tool(NoteTool.third, "A third added over each: a chord"),
        tool(NoteTool.fifth, "A fifth added over each"),
        tool(NoteTool.chance, "Played half the time round"),
        tool(NoteTool.always, "Played every time"),
        tool(NoteTool.mute, "Kept but not played, or played again"),
      ]),
    ];
  }
}
