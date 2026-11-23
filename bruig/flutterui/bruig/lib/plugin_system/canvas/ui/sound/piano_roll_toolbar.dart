part of 'piano_roll.dart';

// The toolbar and the status line. Part of _PianoRollState: its fields,
// lifecycle and build are in piano_roll.dart.

extension _PianoRollToolbar on _PianoRollState {
  Widget _toolbar(MixerLook look, RollContent content, double zoom) {
    var studio = look.studio;
    var small = TextStyle(fontSize: 11, color: studio.text);
    Widget pill(String label, bool on, VoidCallback onTap,
            {Key? key, String? tip}) =>
        Material(
          color: on ? look.colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(5),
            onTap: onTap,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: on ? look.colors.onPrimary : studio.muted)),
            ),
          ),
        );
    Widget gap() => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: studio.edge);
    Widget drop<T>(Key key, T value, List<(String, T)> items,
            ValueChanged<T> onChanged) =>
        MenuAnchor(
          style: MenuStyle(
              backgroundColor:
                  WidgetStatePropertyAll(look.colors.surfaceContainerHigh)),
          builder: (context, menu, _) => InkWell(
            key: key,
            borderRadius: BorderRadius.circular(5),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: Container(
              height: 22,
              padding: const EdgeInsets.fromLTRB(6, 0, 2, 0),
              decoration: BoxDecoration(
                color: studio.inset,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: studio.edge),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                      items.where((i) => i.$2 == value).firstOrNull?.$1 ?? "",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small),
                ),
                Icon(Icons.expand_more, size: 13, color: studio.muted),
              ]),
            ),
          ),
          menuChildren: [
            for (var (label, v) in items)
              MenuItemButton(
                onPressed: () => onChanged(v),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            v == value ? FontWeight.w600 : FontWeight.w400)),
              ),
          ],
        );
    // Transform and Generate: the notes' tools, on those picked or all.
    Widget toolMenu(
            String key, String label, List<(String, List<NoteTool>)> groups) =>
        MenuAnchor(
          style: chainMenuStyle(look),
          builder: (context, menu, _) => InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(5),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: Container(
              height: 22,
              padding: const EdgeInsets.fromLTRB(6, 0, 2, 0),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: studio.muted)),
                Icon(Icons.expand_more, size: 13, color: studio.muted),
              ]),
            ),
          ),
          menuChildren: [
            chainMenuHeading(
                look,
                _selected.isEmpty
                    ? "Every note"
                    : "${_selected.length} picked"),
            for (var (i, (title, tools)) in groups.indexed) ...[
              if (i > 0) chainMenuDivider(look),
              chainMenuHeading(look, title),
              for (var t in tools)
                chainMenuItem(look,
                    key: ValueKey("rollTool-${t.name}"),
                    text: t.label,
                    onPressed: () => c.useNoteTool(t, grid: _grid)),
            ],
          ],
        );
    var bars = content.beats / c.document.audio.beatsPerBar;
    List<Widget> left() => [
          // Named by the editor round it, in the strip.
          if (!widget.inClipEditor) ...[
            Text(content.name,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: studio.text)),
            const SizedBox(width: 12),
          ],
          // Its Play, first where it is always in sight: a part's, the
          // timeline from the playhead; a slot's clip's, it alone, round its
          // loop, the timeline quiet -- as the clip editor's bar has it.
          if (widget.inClipEditor && c.pianoRoll?.row == null) ...[
            pill(c.timelinePlaying ? "■ Stop" : "▶ Play", c.timelinePlaying,
                c.togglePlay,
                key: const ValueKey("partPlay")),
            const SizedBox(width: 8),
          ] else if (widget.inClipEditor) ...[
            pill(c.clipPreviewing ? "■ Stop" : "▶ Play", c.clipPreviewing,
                c.previewClip,
                key: const ValueKey("clipPreview")),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: studio.inset,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: studio.edge),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var (tool, icon, letter, key) in [
                (_Tool.select, "select", "V", "rollSelect"),
                (_Tool.draw, "draw", "D", "rollDraw"),
                (_Tool.paint, "paint", "B", "rollPaint"),
                (_Tool.erase, "erase", "E", "rollErase"),
                (_Tool.knife, "knife", "C", "rollKnife"),
                (_Tool.mute, "mute", "M", "rollMute"),
              ])
                Material(
                  color:
                      _tool == tool ? look.colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    key: ValueKey(key),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => setState(() => _tool = tool),
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ChainIcon(icon,
                            size: 14,
                            color: _tool == tool
                                ? look.colors.onPrimary
                                : studio.muted),
                        const SizedBox(width: 3),
                        Text(letter,
                            style: TextStyle(
                                fontSize: 9,
                                color: (_tool == tool
                                        ? look.colors.onPrimary
                                        : studio.muted)
                                    .withValues(alpha: 0.8))),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          gap(),
          Text("Grid", style: TextStyle(fontSize: 11, color: studio.muted)),
          const SizedBox(width: 4),
          drop(
              const ValueKey("rollGridSize"),
              _grid,
              [for (var (l, b) in rollGrids) (l, b)],
              (v) => setState(() {
                    _grid = v;
                    c.rollStepGrid = v;
                  })),
          const SizedBox(width: 4),
          pill("Quantise", false, _quantise,
              key: const ValueKey("rollQuantise"),
              tip: "Onto the grid: the notes picked, or every one"),
          gap(),
          ChainIcon("scale", size: 14, color: studio.muted),
          const SizedBox(width: 4),
          pill("Show", _scale, () => setState(() => _scale = !_scale),
              key: const ValueKey("rollScale")),
          const SizedBox(width: 2),
          pill("Fold", _fold, () => setState(() => _fold = !_fold),
              key: const ValueKey("rollFold")),
          const SizedBox(width: 2),
          pill("Keep in key", _keep, () => setState(() => _keep = !_keep),
              key: const ValueKey("rollKeep")),
          gap(),
          ChainIcon("chord", size: 14, color: studio.muted),
          const SizedBox(width: 4),
          drop(
              const ValueKey("rollChord"),
              _chord,
              [for (var (i, (name, _)) in rollChords.indexed) (name, i)],
              (v) => setState(() => _chord = v)),
          const SizedBox(width: 8),
          ChainIcon("ghost", size: 14, color: studio.muted),
          const SizedBox(width: 4),
          drop(
              const ValueKey("rollGhost"),
              _ghost ?? "",
              [
                ("No ghosts", ""),
                for (var ch in c.timelineChannels)
                  if (ch.key != c.pianoRoll?.channel &&
                      c.instrumentChannel(ch.key))
                    (ch.name, ch.key),
              ],
              (v) => setState(() => _ghost = v.isEmpty ? null : v)),
          const SizedBox(width: 4),
          // Step input: each key played a note at the cursor, and on.
          pill("Step", c.rollStep, () {
            c.setRollStep(!c.rollStep, grid: _grid);
            _focus.requestFocus();
          }, key: const ValueKey("rollStep")),
          gap(),
          toolMenu("rollTransform", "Transform", [
            (
              "Move",
              [
                NoteTool.quantise,
                NoteTool.swing,
                NoteTool.humanise,
                NoteTool.legato,
                NoteTool.strum,
              ]
            ),
            (
              "Shape",
              [
                NoteTool.reverse,
                NoteTool.invert,
                NoteTool.faster,
                NoteTool.slower,
                NoteTool.crescendo,
                NoteTool.chop,
                NoteTool.join,
                NoteTool.duplicate,
              ]
            ),
            (
              "Pitch",
              [
                NoteTool.up,
                NoteTool.down,
                NoteTool.octaveUp,
                NoteTool.octaveDown,
                NoteTool.fitToScale,
              ]
            ),
          ]),
          const SizedBox(width: 2),
          toolMenu("rollGenerate", "Generate", [
            (
              "Add",
              [
                NoteTool.arpeggiate,
                NoteTool.rhythm,
                NoteTool.fillChords,
                NoteTool.third,
                NoteTool.fifth,
              ]
            ),
            ("Play", [NoteTool.chance, NoteTool.always, NoteTool.mute]),
          ]),
          if (content.clip && !widget.inClipEditor) ...[
            gap(),
            Text("Length", style: TextStyle(fontSize: 11, color: studio.muted)),
            const SizedBox(width: 4),
            drop(
                const ValueKey("rollLength"),
                bars,
                [
                  for (var b in {
                    ...clipBarChoices.map((b) => b.toDouble()),
                    bars
                  })
                    (b == 1 ? "1 bar" : "${_PianoRollState._trim(b)} bars", b),
                ],
                (v) =>
                    c.setRollContent(beats: v * c.document.audio.beatsPerBar)),
          ],
          if (!widget.inClipEditor) ...[
            const SizedBox(width: 12),
            pill("Effects", false, () => c.pianoRollShown = false,
                key: const ValueKey("rollToEffects"),
                tip: "Back to the channel's effects"),
          ],
        ];
    Widget iconButton(String key, String icon, VoidCallback onTap) => InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: SizedBox(
              width: 24,
              height: 22,
              child: Center(
                  child: ChainIcon(icon, size: 14, color: studio.muted))),
        );
    Widget materialButton(String key, IconData icon, VoidCallback onTap) =>
        InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: SizedBox(
              width: 24,
              height: 22,
              child: Icon(icon, size: 14, color: studio.muted)),
        );
    var right = <Widget>[
      materialButton("rollUndo", Icons.undo, c.undo),
      materialButton("rollRedo", Icons.redo, c.redo),
      gap(),
      materialButton("rollCopy", Icons.content_copy, _copy),
      materialButton("rollPaste", Icons.content_paste, _paste),
      materialButton("rollDelete", Icons.delete_outline, _delete),
      gap(),
      iconButton("rollZoomOut", "zoomout",
          () => setState(() => _zoom = (zoom + 0.1).clamp(0.0, 1.0))),
      SizedBox(
        width: 72,
        // Closest at the left; at the right, the whole of it.
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
          child: Slider(
            key: const ValueKey("rollZoom"),
            value: zoom.clamp(0.0, 1.0),
            onChanged: (v) => setState(() => _zoom = v),
          ),
        ),
      ),
      iconButton("rollZoomIn", "zoomin",
          () => setState(() => _zoom = (zoom - 0.1).clamp(0.0, 1.0))),
    ];
    return Container(
      height: _toolbarH,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: studio.edge))),
      child: LayoutBuilder(builder: (context, box) {
        // With room, the right end keeps right; short of it, it follows on.
        var pinned = box.maxWidth >= 640;
        var scroll = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ...left(),
            if (!pinned) ...[gap(), ...right],
          ]),
        );
        if (!pinned) return scroll;
        return Row(children: [
          Expanded(child: scroll),
          gap(),
          ...right,
        ]);
      }),
    );
  }

  /// _status is the roll's foot: note count, tool, grid, what the tool does.
  Widget _status(MixerLook look, RollContent content) {
    var studio = look.studio;
    var picked = _selected.length;
    var grid = rollGrids.where((g) => g.$2 == _grid).firstOrNull?.$1 ??
        "${_PianoRollState._trim(_grid)} beat";
    var hint = c.rollStep
        ? "Step: A to K play notes at the cursor, held together a chord "
            "· Tab rests · Z X octave"
        : switch (_tool) {
            _Tool.select =>
              "Drag to move · its end to lengthen · Shift-click adds "
                  "· ↑↓ transpose, ⇧ an octave",
            _Tool.draw => "Click draws a note · drag to lengthen it",
            _Tool.paint => "Drag along to lay notes on the grid",
            _Tool.erase => "Click or drag over notes to take them out",
            _Tool.knife => "Click a note to cut it in two there",
            _Tool.mute => "Click a note to mute it, or play it again",
          };
    var mono = TextStyle(
        fontSize: 10.5,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: studio.muted);
    var strong = mono.copyWith(color: studio.text, fontWeight: FontWeight.w600);
    return Container(
      key: const ValueKey("rollStatus"),
      height: _statusH,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: studio.edge))),
      child: Text.rich(
        TextSpan(style: mono, children: [
          TextSpan(text: "${content.notes.length}", style: strong),
          TextSpan(text: content.notes.length == 1 ? " note" : " notes"),
          if (picked > 0) ...[
            const TextSpan(text: "   "),
            TextSpan(text: "$picked", style: strong),
            const TextSpan(text: " picked"),
          ],
          const TextSpan(text: "   Tool: "),
          TextSpan(text: _tool.name, style: strong),
          const TextSpan(text: "   Grid "),
          TextSpan(text: grid, style: strong),
          TextSpan(text: "   $hint"),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
