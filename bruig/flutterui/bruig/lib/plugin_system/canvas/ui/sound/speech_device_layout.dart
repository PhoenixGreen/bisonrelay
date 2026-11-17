part of 'speech_device.dart';

// How the device is put together: the panels side by side, each folding to a
// strip, the clip strip under them, the engine switches, and the device as the
// Speech view or as a card. Part of _SpeechDeviceState: its fields, lifecycle
// and build are in speech_device.dart.

extension _SpeechLayout on _SpeechDeviceState {
  /// _clipStrip is the strip under the panels: the sections, each with its
  /// slot picked, laid along a line as long as they are spoken, and the
  /// button that puts them on the timeline, only when asked.
  Widget _clipStrip(_SpeechView view) {
    var spec = view.spec,
        k = view.k,
        s = view.s,
        lines = view.lines,
        busy = view.busy,
        spoken = view.spoken;
    var onTimeline = spec.clip.isNotEmpty &&
        c.document.elements.any((e) => e.id == spec.clip);
    var clipTake = onTimeline ? spec.takes.lastOrNull : null;
    return Row(children: [
      SizedBox(
        width: 190,
        child: k.button(
            onTimeline
                ? "Update the timeline clip"
                : "Add all sections to timeline",
            spoken == 0 || busy
                ? null
                : () => _run(() => c.joinSpeech(widget.channel)),
            key: const ValueKey("speechAddAll"),
            icon: Icons.playlist_add_check,
            small: true,
            tip: "Each line's picked take, joined with its pauses and the "
                "feel's room and boost, in one clip -- a line with none is "
                "left out"),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          // As tall as its words, at the reader's text size.
          height: MediaQuery.textScalerOf(context).scale(12) + 10,
          padding: const EdgeInsets.all(3),
          decoration: k.box(s.inset),
          child: LayoutBuilder(builder: (context, room) {
            // Each line as long as its take, or as its words would be.
            double long(SpeechLine l) =>
                l.take?.length ?? math.max(0.6, l.text.split(" ").length * 0.4);
            var total = lines.fold(0.0, (n, l) => n + long(l)) +
                math.max(0, lines.length - 1) * lineGap(spec.speed);
            if (total <= 0) return const SizedBox();
            var per = room.maxWidth / total;
            return Row(children: [
              for (var (i, l) in lines.indexed) ...[
                if (i > 0) SizedBox(width: lineGap(spec.speed) * per),
                SizedBox(
                  width: math.max(0, long(l) * per),
                  child: GestureDetector(
                    onTap: () => _pickLine(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: l.take != null
                            ? (i == _line
                                ? s.solo.withValues(alpha: 0.35)
                                : s.raised)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                            color: i == _line
                                ? s.solo
                                : l.take != null
                                    ? s.on.withValues(alpha: 0.5)
                                    : s.edge),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                          "${i + 1}  "
                          "${l.text.replaceAll(RegExp(r"\s*\[[^\]]*\]"), "")}",
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: k.text(9,
                              colour: l.take != null ? s.text : s.muted)),
                    ),
                  ),
                ),
              ],
            ]);
          }),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 170,
        child: Text(
          key: const ValueKey("speechStatus"),
          _problem ??
              (clipTake != null
                  ? "On the timeline: ${clipTake.length.toStringAsFixed(1)} s"
                  : "$spoken of ${lines.length} sections with a take"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: k.text(10.5, colour: _problem != null ? _problemInk : s.muted),
        ),
      ),
    ]);
  }

  /// _divider is the rule between two panels.
  Widget _divider(_SpeechView view) => Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: view.s.edge.withValues(alpha: 0.7));

  /// _sideName is the right-hand panel's name: the word picked while
  /// phrasing, the feel otherwise.
  String _sideName(_SpeechView view) => view.phrasingOn ? "Word" : "Feel";

  /// _panels are the device's side panels (voices, the section's takes, and
  /// the feel or the word picked), each folding to a strip, kept as the clip
  /// editor's are (CanvasController.settingsShut).
  List<(String, String, double)> _panels(_SpeechView view) => [
        if (!view.phrasingOn) ("voice", "Voice", 190.0),
        ("takes", "Takes", 300.0),
        ("side", _sideName(view), 200.0),
      ];

  /// _shown is whether panel [kind] is open rather than folded.
  bool _shown(String kind) => !c.settingsShut("speech-$kind");

  /// _strip is a panel folded away: a strip that opens it again.
  Widget _strip(_SpeechView view, String kind, String name) {
    var k = view.k, s = view.s;
    return Tooltip(
      message: "Show the ${name.toLowerCase()} panel",
      child: InkWell(
        key: ValueKey("speechPanelOpen-$kind"),
        borderRadius: BorderRadius.circular(4),
        onTap: () => c.toggleSettingsShut("speech-$kind"),
        child: Container(
          width: 22,
          decoration: BoxDecoration(
              color: s.inset.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4)),
          child: Column(children: [
            const SizedBox(height: 6),
            Icon(kind == "voice" ? Icons.chevron_right : Icons.chevron_left,
                size: 15, color: s.muted),
            const SizedBox(height: 6),
            Expanded(
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: k.text(10.5, colour: s.muted)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// _panel is [child] at [width] while open, its strip while folded.
  Widget _panel(_SpeechView view, String kind, String name, double width,
          Widget child) =>
      _shown(kind)
          ? SizedBox(width: width, child: child)
          : _strip(view, kind, name);

  /// Each panel's switch, lit while it shows.
  Widget _toggle(_SpeechView view, String kind, String name) {
    var k = view.k, s = view.s;
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Material(
        color: _shown(kind) ? s.raised : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
                color: _shown(kind) ? s.edge : s.edge.withValues(alpha: 0.5))),
        child: InkWell(
          key: ValueKey("speechPanel-$kind"),
          borderRadius: BorderRadius.circular(4),
          onTap: () => c.toggleSettingsShut("speech-$kind"),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  kind == "voice"
                      ? Icons.view_sidebar_outlined
                      : kind == "takes"
                          ? Icons.view_list_outlined
                          : Icons.tune,
                  size: 12,
                  color: _shown(kind) ? s.text : s.muted),
              const SizedBox(width: 4),
              Text(name,
                  style: k.text(10.5, colour: _shown(kind) ? s.text : s.muted)),
            ]),
          ),
        ),
      ),
    );
  }

  /// _engines are the bar's engine switches, then Phrasing.
  List<Widget> _engines(_SpeechView view) {
    var spec = view.spec,
        k = view.k,
        s = view.s,
        engine = view.engine,
        line = view.line,
        phrasingOn = view.phrasingOn,
        pickedSlot = view.pickedSlot;
    return [
      Text("Engine", style: k.text(11, colour: s.muted)),
      const SizedBox(width: 6),
      for (var e in SpeechEngineKind.values)
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Material(
            color: engine == e ? s.on : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              key: ValueKey("speechEngine-${e.name}"),
              borderRadius: BorderRadius.circular(4),
              onTap: () =>
                  _set(spec.copyWith(engine: e, voice: "", voiceName: "")),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                child: Text(e.label,
                    style: k.text(11,
                        weight: FontWeight.w600,
                        colour: engine == e ? s.onOn : s.text)),
              ),
            ),
          ),
        ),
      // Phrasing, after a voice has spoken: the take's words shaped.
      Container(
          key: const ValueKey("speechPhrasingRule"),
          width: 1.5,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          color: s.muted.withValues(alpha: 0.7)),
      Tooltip(
        message: phrasingOn
            ? "Back to the sections"
            : line == null
                ? "Phrasing shapes a spoken take's words: write a script "
                    "and speak it first"
                : "Shape the picked take's words: each one's pitch, "
                    "length and loudness",
        child: Material(
          color: phrasingOn ? s.on : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            key: const ValueKey("speechPhrasing"),
            borderRadius: BorderRadius.circular(4),
            onTap: phrasingOn
                ? c.closePhrasing
                : line == null
                    ? null
                    : () => c.openPhrasing(widget.channel, _line, pickedSlot),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.graphic_eq,
                    size: 13,
                    color: phrasingOn
                        ? s.onOn
                        : line == null
                            ? s.muted
                            : s.text),
                const SizedBox(width: 4),
                Text("Phrasing",
                    style: k.text(11,
                        weight: FontWeight.w600,
                        colour: phrasingOn
                            ? s.onOn
                            : line == null
                                ? s.muted
                                : s.text)),
              ]),
            ),
          ),
        ),
      ),
    ];
  }

  /// _removeButton takes the device off the channel.
  Widget _removeButton(_SpeechView view) {
    var s = view.s, skin = view.skin;
    return IconButton(
      key: const ValueKey("speechRemove"),
      tooltip: "Take the Speech device off. Its takes stay on the "
          "timeline.",
      iconSize: 14,
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.close, color: widget.editor ? s.muted : skin.ink),
      onPressed: _takeOff,
    );
  }

  /// _inside is the device's body: the panels side by side, and the clip
  /// strip under them.
  Widget _inside(_SpeechView view,
      {required Widget voiceColumn,
      required Widget scriptColumn,
      required Widget feelColumn,
      required Widget clipStrip}) {
    var sideName = _sideName(view);
    var panels = _panels(view);
    var phrasingOn = view.phrasingOn;
    // The middle (sections, or Phrasing's lanes) has a least width: narrower,
    // it scrolls sideways, and folding a panel gives the room back.
    var sides = [
      for (var (kind, _, width) in panels) _shown(kind) ? width : 22.0,
    ].fold(0.0, (a, b) => a + b + 21);
    var least = sides + MediaQuery.textScalerOf(context).scale(10) * 34;
    Widget room(Widget row) => LayoutBuilder(
        builder: (context, box) => box.maxWidth >= least
            ? row
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: least, child: row)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child:
            room(Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (phrasingOn) ...[
            Expanded(child: PhrasingLanes(controller: c)),
            _divider(view),
            _panel(view, "takes", "Takes", 300, _linePanel(view)),
            _divider(view),
            _panel(
                view, "side", sideName, 200, PhrasingWordPanel(controller: c)),
          ] else ...[
            _panel(view, "voice", "Voice", 190, voiceColumn),
            _divider(view),
            Expanded(child: scriptColumn),
            _divider(view),
            _panel(view, "takes", "Takes", 300, _linePanel(view)),
            _divider(view),
            _panel(view, "side", sideName, 200, feelColumn),
          ],
        ])),
      ),
      const SizedBox(height: 7),
      clipStrip,
    ]);
  }

  /// _editorView is the device filling the Chain as the Speech view.
  Widget _editorView(_SpeechView view, Widget inside, List<Widget> engines,
      List<Widget> toggles, Widget remove) {
    var k = view.k, s = view.s;
    // The Speech view: a bar of its own, as the clip editor's, and all the
    // panel's room.
    return Container(
      key: const ValueKey("speechEditor"),
      color: s.panel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: MediaQuery.textScalerOf(context).scale(11) + 19,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: s.edge))),
          child: Row(children: [
            const Icon(Icons.record_voice_over, size: 14, color: voiceColour),
            const SizedBox(width: 6),
            Text("SPEECH",
                style: k
                    .text(10.5, weight: FontWeight.w700)
                    .copyWith(letterSpacing: 0.6)),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: engines),
              ),
            ),
            Flexible(
              flex: 2,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(children: toggles),
              ),
            ),
            const SizedBox(width: 4),
            remove,
          ]),
        ),
        // Its columns need a least height: shorter, it scrolls rather than
        // squeezing them.
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            var least = MediaQuery.textScalerOf(context).scale(10) * 16;
            var padded = Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: inside,
            );
            if (box.maxHeight >= least) return padded;
            return SingleChildScrollView(
              child: SizedBox(height: least, child: padded),
            );
          }),
        ),
      ]),
    );
  }

  /// _cardView is the device as a card in the chain.
  Widget _cardView(
      _SpeechView view, Widget inside, List<Widget> engines, Widget remove) {
    var spec = view.spec, k = view.k, s = view.s, skin = view.skin;
    return DeviceFrame(
      id: "speech",
      title: "Speech",
      skin: skin,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 1140,
      height: widget.height,
      // As a card its bar has no room for the panels' switches: each folded
      // panel opens again from its strip.
      actions: [
        ...engines,
        const SizedBox(width: 6),
        remove,
      ],
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
              "Speech · ${spec.voiceName.isEmpty ? "voice" : spec.voiceName}",
              style: k.text(11, colour: s.muted)),
        ),
      ),
      body: Container(
        color: s.panel,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: inside,
      ),
    );
  }
}
