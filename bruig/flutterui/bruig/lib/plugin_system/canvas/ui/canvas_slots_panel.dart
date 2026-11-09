part of 'canvas_mixer.dart';

// canvas_slots_panel.dart is the Slots panel as the approved design has it
// (Ken, 2026-11-08: "like Bitwig's clip launcher"): a grid of its own, not
// the timeline's rows with slots beside them. A column for each row the
// timeline shows -- an element with its own sound, or a sound alone -- its
// head along the top, each slot a motion part over a sound part; the cues in
// a column on the left; a stop under each column and Stop all under the
// cues. The Scenes column, where there are scenes, holds the transitions,
// outside the cue rows.

/// _slotsSizes are the sound and motion parts' heights at each slot size,
/// small to large; Fill shares the panel's height, up to [_slotsFillMost] a
/// part.
const _slotsSizes = [(20.0, 14.0), (28.0, 20.0), (40.0, 28.0)];
const double _slotsFillMost = 64;

/// _slotsColumnLeast and _slotsColumnMost are a column's width as the panel
/// fills, and _slotsColumnNarrow it narrowed.
const double _slotsColumnLeast = 132;
const double _slotsColumnMost = 300;
const double _slotsColumnNarrow = 84;

/// _slotsHeadH is a column's head: its name, and what it is.
const double _slotsHeadH = 34;

/// CanvasSlotsPanel is the Slots panel, [height] tall, its top edge
/// dragged to [onResize].
class CanvasSlotsPanel extends StatefulWidget {
  final CanvasController controller;
  final double height;
  final ValueChanged<double> onResize;
  const CanvasSlotsPanel(
      {required this.controller,
      required this.height,
      required this.onResize,
      super.key});

  @override
  State<CanvasSlotsPanel> createState() => _CanvasSlotsPanelState();
}

class _CanvasSlotsPanelState extends State<CanvasSlotsPanel> {
  CanvasController get controller => widget.controller;

  /// _scrolls keeps every column's slots scrolled together, the cues' too.
  final _ClipScrolls _scrolls = _ClipScrolls();
  final ScrollController _across = ScrollController();

  @override
  void dispose() {
    _scrolls.dispose();
    _across.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TooltipVisibility(
        visible: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _panel(context),
        ),
      );

  Widget _panel(BuildContext context) {
    var theme = MixerLook.of(context);
    var colors = theme.colors;
    return Container(
      key: const ValueKey("slotsPanel"),
      height: widget.height,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, _edgeRoom + 2, 10, 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(theme),
                  const SizedBox(height: 6),
                  Expanded(
                      child: LayoutBuilder(
                          builder: (context, box) => _grid(theme, box))),
                ]),
          ),
        ),
        // Its top edge, dragged: taller or shorter.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              key: const ValueKey("slotsGrip"),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) =>
                  widget.onResize(widget.height - d.delta.dy),
            ),
          ),
        ),
      ]),
    );
  }

  /// _header is the panel's title, its three buttons and a "?".
  Widget _header(MixerLook theme) {
    var studio = theme.studio;
    var colors = theme.colors;
    Widget button(
            {required Key key,
            required String label,
            required bool lit,
            required VoidCallback onTap,
            Widget? under}) =>
        InkWell(
          key: key,
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: lit ? studio.on.withValues(alpha: 0.18) : studio.inset,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: lit ? studio.on : studio.edge),
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 10, color: lit ? studio.text : studio.muted)),
              if (under != null) under,
            ]),
          ),
        );
    var motion = controller.motionSlots;
    var bars = switch (motion) {
      BandState.shown => 3,
      BandState.minimised => 1,
      BandState.hidden => 0,
    };
    return SizedBox(
      height: 24,
      child: Row(children: [
        Text("Slots",
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface)),
        const SizedBox(width: 10),
        // In a narrow panel, along under the title rather than past its
        // edge.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              button(
                  key: const ValueKey("slotsNarrow"),
                  label: "Narrow",
                  lit: controller.slotsPanelNarrow,
                  onTap: () => controller.slotsPanelNarrow =
                      !controller.slotsPanelNarrow),
              const SizedBox(width: 4),
              button(
                  key: const ValueKey("slotsHeight"),
                  label: "Height ${const [
                    "S",
                    "M",
                    "L",
                    "Fill"
                  ][controller.slotsPanelSize]}",
                  lit: false,
                  onTap: () => controller.slotsPanelSize =
                      (controller.slotsPanelSize + 1) % 4),
              const SizedBox(width: 4),
              button(
                  key: const ValueKey("slotsMotion"),
                  label: "Motion",
                  lit: motion != BandState.hidden,
                  onTap: () => controller.motionSlots = switch (motion) {
                        BandState.shown => BandState.minimised,
                        BandState.minimised => BandState.hidden,
                        BandState.hidden => BandState.shown,
                      },
                  under: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 7,
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        color: i < bars ? studio.on : studio.edge,
                      ),
                  ])),
              const SizedBox(width: 6),
              const HelpNote(
                id: "slots",
                size: 16,
                title: "Slots",
                paragraphs: [
                  "A column for each element and sound, as the timeline has them. "
                      "Each slot is the element's motion over its sound: press one "
                      "to launch it on the next bar.",
                  "The cues on the left launch a whole row together. The Scenes "
                      "column holds the transitions, one per join; a cue passes it "
                      "by.",
                  "Narrow makes every column narrow. Height steps the slots small, "
                      "medium, large, or to fill the panel. Motion shows the motion "
                      "parts, thins them to a line, or hides them.",
                ],
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  /// _grid is the cue column and a column for each row, filling the width.
  Widget _grid(MixerLook theme, BoxConstraints box) {
    var rows = controller.slotsShown;
    var motionShown = controller.motionSlots;
    var rowsOf = canvasRowsOf(controller);
    var withMotion = rowsOf.any((r) => r.element != null);
    // Each part's height at this size; filling, shared out by the room.
    var bodyH = math.max(0.0, box.maxHeight - _slotsHeadH - 6 - _stopH - 10);
    double sound, motion;
    if (controller.slotsPanelSize < 3) {
      (sound, motion) = _slotsSizes[controller.slotsPanelSize];
    } else {
      var per = bodyH / math.max(1, rows) - _clipGap;
      motion = withMotion ? math.min(_slotsFillMost, per * 0.4) : 0;
      sound = math.min(_slotsFillMost, per - motion);
      sound = math.max(sound, _slotsSizes[0].$1);
      motion = math.max(motion, withMotion ? _slotsSizes[0].$2 : 0);
    }
    var motionPart = !withMotion
        ? 0.0
        : switch (motionShown) {
            BandState.shown => motion + _motionClipGap,
            BandState.minimised => _motionClipMini + _motionClipGap,
            BandState.hidden => 0.0,
          };
    var columns = <Widget Function(double width)>[];
    for (var r in rowsOf) {
      if (r.transitions) continue;
      columns.add((w) => _column(theme, r, w, sound, motionPart));
    }
    var scenes = controller.document.allScenes.length;
    var narrow = controller.slotsPanelNarrow;
    var cueW = box.maxWidth < 480
        ? CanvasController.cueColumnLeast
        : controller.slotsCueWidth;
    var avail = math.max(0.0, box.maxWidth - cueW - 8);
    var count = columns.length + (scenes > 1 ? 1 : 0);
    var width = narrow
        ? _slotsColumnNarrow
        : (count == 0 ? _slotsColumnLeast : avail / count - 6)
            .clamp(_slotsColumnLeast, _slotsColumnMost)
            .toDouble();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _cues(theme, cueW, sound, motionPart),
      const SizedBox(width: 8),
      Expanded(
        child: ListView(
          controller: _across,
          scrollDirection: Axis.horizontal,
          children: [
            for (var c in columns) ...[
              c(width),
              const SizedBox(width: 6),
            ],
            if (scenes > 1) _scenesColumn(theme, width, sound, motionPart),
          ],
        ),
      ),
    ]);
  }

  /// _frame is a column: its edge, its head, its slots and its stop.
  Widget _frame(MixerLook theme,
      {required Key key,
      required double width,
      required Widget head,
      required Widget slots,
      required Widget foot,
      Color? edge}) {
    var colors = theme.colors;
    return Container(
      key: key,
      width: width,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outlineVariant),
      ),
      foregroundDecoration: edge == null
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border(top: BorderSide(color: edge, width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: _slotsHeadH, child: head),
        const SizedBox(height: 6),
        Expanded(child: slots),
        const SizedBox(height: 4),
        SizedBox(height: _stopH, child: foot),
      ]),
    );
  }

  /// _head is a column's name, and on a second line what it is.
  Widget _head(MixerLook theme, String name, List<String> marks) {
    var studio = theme.studio;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colors.onSurface)),
      const SizedBox(height: 2),
      Text(marks.join(" · "),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 9, color: studio.muted)),
    ]);
  }

  Widget _stop(MixerLook theme, Key key, bool lit, VoidCallback onTap) =>
      Material(
        color: theme.studio.inset,
        borderRadius: BorderRadius.circular(3),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          child: Center(
            child: Icon(Icons.stop,
                size: 11, color: lit ? theme.studio.text : theme.studio.muted),
          ),
        ),
      );

  /// _column is one row's column: an element's motion over its own sound,
  /// or a sound alone.
  Widget _column(
      MixerLook theme, CanvasRow r, double width, double sound, double motion) {
    var e = r.element;
    var channel = r.channel;
    var key = r.key;
    var marks = <String>[
      if (e != null) "motion",
      if (channel != null) "sound",
      if (e != null && (e.base.motion.instances?.count ?? 1) > 1)
        "×${e.base.motion.instances!.count}",
      if (e != null && e.base.motion.layersInUse.length > 1)
        "${e.base.motion.layersInUse.length} layers",
      if ((channel != null && controller.clipPlaying(channel.key)) ||
          (e != null && controller.motionPlayer.isOff(e.id)))
        "playing",
    ];
    var name =
        e != null ? (e.name.isEmpty ? e.id : e.name) : channel?.name ?? key;
    return _frame(
      theme,
      key: ValueKey("slotsColumn-$key"),
      width: width,
      edge: e != null ? motionColour : soundColour,
      head: _head(theme, name, marks),
      slots: _clipColumn(
        _scrolls.of(key),
        controller.slotsShown,
        (row) => channel == null
            ? const SizedBox()
            : _ClipSlot(
                key: ValueKey("clip-${channel.key}-$row"),
                controller: controller,
                channel: channel.key,
                row: row,
                theme: theme),
        const SizedBox(),
        clip: sound,
        motion: motion,
        motionRow: e == null
            ? null
            : (row) => _MotionSlot(
                key: ValueKey("motionSlot-${e.id}-$row"),
                controller: controller,
                element: e.id,
                row: row,
                theme: theme),
        stop: false,
      ),
      foot: _stop(
          theme,
          ValueKey("slotsStop-$key"),
          (channel != null && controller.clipPlaying(channel.key)) ||
              (e != null && controller.motionPlayer.isOff(e.id)), () {
        if (e != null) controller.stopMotion(e.id);
        if (channel != null) controller.stopChannelClips(channel.key);
      }),
    );
  }

  /// _scenesColumn is the transitions, one per join, outside the cue rows.
  Widget _scenesColumn(
      MixerLook theme, double width, double sound, double motion) {
    var joins = controller.document.allScenes.length - 1;
    return _frame(
      theme,
      key: const ValueKey("slotsColumn-scenes"),
      width: width,
      edge: sceneColour,
      head: _head(theme, "Scenes", ["transitions, not in cues"]),
      slots: _clipColumn(
        _scrolls.of("scenes"),
        joins,
        (i) => _JoinSlot(
            key: ValueKey("join-$i"),
            controller: controller,
            join: i,
            theme: theme),
        const SizedBox(),
        clip: sound,
        motion: motion,
        whole: true,
        stop: false,
      ),
      foot: const SizedBox(),
    );
  }

  /// _cues is the cue column: a launch for each cue row, Stop all under.
  Widget _cues(MixerLook theme, double width, double sound, double motion) =>
      Stack(children: [
        _frame(
          theme,
          key: const ValueKey("slotsCues"),
          width: width,
          head: Align(
            alignment: Alignment.topLeft,
            child: Text("Cues",
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colors.onSurface)),
          ),
          slots: _clipColumn(
            _scrolls.of(_master),
            controller.slotsShown,
            (row) => _SceneSlot(
                key: ValueKey("scene-$row"),
                controller: controller,
                row: row,
                theme: theme),
            const SizedBox(),
            clip: sound,
            motion: motion,
            whole: true,
            stop: false,
          ),
          foot: _stop(theme, const ValueKey("clipStopAll"), true,
              controller.stopAllClips),
        ),
        // Its right edge, dragged to widen or narrow it.
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: const ValueKey("slotsCueGrip"),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) =>
                  controller.slotsCueWidth += d.delta.dx,
            ),
          ),
        ),
      ]);
}
