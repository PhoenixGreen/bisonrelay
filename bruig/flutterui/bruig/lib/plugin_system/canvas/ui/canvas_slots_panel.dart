part of 'canvas_mixer.dart';

// canvas_slots_panel.dart is the Slots panel as the approved design has it
// (Ken, 2026-11-08: "like Bitwig's clip launcher"): a grid of its own, not
// the timeline's rows with slots beside them. A column for each row the
// timeline shows -- an element with its own sound, or a sound alone -- its
// head along the top, each slot a motion part over a sound part; the cues in
// a column on the left; a stop under each column and Stop all under the
// cues. The Scenes column, where there are scenes, holds the transitions,
// outside the cue rows.

/// _slotsSizes are a part's height at each slot size, small to large, a
/// motion part as tall as its sound part (the prototype's); Fill shares the
/// panel's height, up to [_slotsFillMost] a part.
const _slotsSizes = [20.0, 30.0, 44.0];
const double _slotsFillMost = 64;

/// _slotsColumnLeast and _slotsColumnMost are a column's width as the panel
/// fills, and _slotsColumnNarrow it narrowed.
const double _slotsColumnLeast = 132;
const double _slotsColumnMost = 300;
const double _slotsColumnNarrow = 84;

/// _slotsHeadH is a column's head: its name, and what it is.
const double _slotsHeadH = 40;

/// _footH is the stop row under the slots.
const double _footH = 26;

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

  /// _joins scrolls the Scenes column by itself: it is not on the cue rows,
  /// and with fewer rows it would hold the others back.
  final ScrollController _joins = ScrollController();

  @override
  void dispose() {
    _scrolls.dispose();
    _across.dispose();
    _joins.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TooltipVisibility(
        visible: false,
        // No scroll bars anywhere on it (Ken, 2026-11-10): the columns and
        // the cues scroll together by the wheel, as the mixer's slots do.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _panel(context),
          ),
        ),
      );

  Widget _panel(BuildContext context) {
    var theme = MixerLook.of(context);
    var colors = theme.colors;
    return Container(
      key: const ValueKey("slotsPanel"),
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.studio.inset,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Stack(children: [
        Positioned.fill(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(theme),
            Expanded(
                child: LayoutBuilder(
                    builder: (context, box) => _grid(theme, box))),
          ]),
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

  /// _header is the panel's bar: SLOTS, then its three buttons -- every
  /// column narrow, the slots' height (S, M, L, Fill, its bars rising) and
  /// the motion slots (lit as the mixer's rail lights them) -- and a "?".
  Widget _header(MixerLook theme) {
    var studio = theme.studio;
    var colors = theme.colors;
    Widget button(
            {required Key key,
            required bool lit,
            required VoidCallback onTap,
            required List<Widget> children}) =>
        InkWell(
          key: key,
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color:
                  lit ? studio.on.withValues(alpha: 0.18) : theme.studio.inset,
              borderRadius: BorderRadius.circular(5),
              border: lit ? Border.all(color: studio.on) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        );
    Widget bars(List<double> heights, int lit, {bool rising = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var (i, h) in heights.indexed)
              Container(
                width: rising ? 3 : 7,
                height: h,
                margin: EdgeInsets.symmetric(horizontal: rising ? 0.5 : 1),
                color: i < lit ? studio.on : studio.edge,
              ),
          ],
        );
    var size = controller.slotsPanelSize;
    var motion = controller.motionSlots;
    var motionLit = switch (motion) {
      BandState.shown => 3,
      BandState.minimised => 1,
      BandState.hidden => 0,
    };
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.studio.raised,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(children: [
        Text("SLOTS",
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w600,
                color: studio.muted)),
        const SizedBox(width: 8),
        // In a narrow panel, along under the title rather than past its
        // edge; against the right edge otherwise, as the prototype has them.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                button(
                    key: const ValueKey("slotsNarrow"),
                    lit: controller.slotsPanelNarrow,
                    onTap: () => controller.slotsPanelNarrow =
                        !controller.slotsPanelNarrow,
                    children: [
                      RotatedBox(
                          quarterTurns: 1,
                          child: Icon(Icons.compress,
                              size: 13, color: studio.text)),
                    ]),
                const SizedBox(width: 6),
                button(
                    key: const ValueKey("slotsHeight"),
                    lit: false,
                    onTap: () => controller.slotsPanelSize = (size + 1) % 4,
                    children: [
                      bars(const [4, 7, 10], size == 3 ? 3 : size + 1,
                          rising: true),
                      const SizedBox(width: 5),
                      Text(const ["S", "M", "L", "Fill"][size],
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: studio.text)),
                    ]),
                const SizedBox(width: 6),
                button(
                    key: const ValueKey("slotsMotion"),
                    lit: false,
                    onTap: () => controller.motionSlots = switch (motion) {
                          BandState.shown => BandState.minimised,
                          BandState.minimised => BandState.hidden,
                          BandState.hidden => BandState.shown,
                        },
                    children: [
                      Icon(Icons.animation,
                          size: 13,
                          color: motion == BandState.hidden
                              ? studio.muted
                              : studio.text),
                      const SizedBox(width: 5),
                      bars(const [2, 2, 2], motionLit),
                    ]),
                const SizedBox(width: 8),
                const HelpNote(
                    id: "slots",
                    size: 16,
                    title: "Slots",
                    paragraphs: slotsHelp),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  /// _grid is the cue column and a column for each row, filling the width,
  /// a line apart.
  Widget _grid(MixerLook theme, BoxConstraints box) {
    var rows = controller.slotsShown;
    var motionShown = controller.motionSlots;
    var rowsOf = canvasRowsOf(controller);
    var withMotion = rowsOf.any((r) => r.element != null);
    var pair = withMotion && motionShown == BandState.shown;
    // Each part's height at this size; filling, the rows sharing the room.
    var bodyH =
        math.max(0.0, box.maxHeight - _headHeight(context) - _footH - 2);
    double part;
    if (controller.slotsPanelSize < 3) {
      part = _slotsSizes[controller.slotsPanelSize];
    } else {
      var per = bodyH / math.max(1, rows) -
          _clipGap -
          (motionShown == BandState.minimised && withMotion ? 8 : 0);
      part = (per / (pair ? 2 : 1)).clamp(18.0, _slotsFillMost).toDouble();
    }
    var motionPart = !withMotion
        ? 0.0
        : switch (motionShown) {
            BandState.shown => part + _motionClipGap,
            BandState.minimised => _motionClipMini + _motionClipGap,
            BandState.hidden => 0.0,
          };
    var columns = <Widget Function(double width)>[];
    var masterCues = false;
    for (var r in rowsOf) {
      if (r.transitions) continue;
      // The master's cues before its channels, on a scene with cues of its
      // own (Ken, 2026-11-10: per-canvas cues).
      if (r.group == RowGroup.all && controller.cuesApart && !masterCues) {
        masterCues = true;
        columns.add((w) => _cues(
            theme, controller.slotsMasterCueWidth, part, motionPart,
            master: true));
      }
      columns.add((w) => _column(theme, r, w, part, motionPart));
    }
    var scenes = controller.document.allScenes.length;
    var narrow = controller.slotsPanelNarrow;
    var cueW = box.maxWidth < 480
        ? CanvasController.cueColumnLeast
        : controller.slotsCueWidth;
    var avail = math.max(0.0, box.maxWidth - cueW - 1);
    var count = columns.length + (scenes > 1 ? 1 : 0);
    var width = narrow
        ? _slotsColumnNarrow
        : (count == 0 ? _slotsColumnLeast : avail / count - 1)
            .clamp(_slotsColumnLeast, _slotsColumnMost)
            .toDouble();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _cues(theme, cueW, part, motionPart),
      const SizedBox(width: 1),
      Expanded(
        child: ListView(
          controller: _across,
          scrollDirection: Axis.horizontal,
          children: [
            for (var c in columns) ...[
              c(width),
              const SizedBox(width: 1),
            ],
            if (scenes > 1) _scenesColumn(theme, width, part, motionPart),
          ],
        ),
      ),
    ]);
  }

  /// _frame is a column of the grid: its head, its slots and its foot, a
  /// line apart.
  Widget _frame(MixerLook theme,
      {required Key key,
      required double width,
      required Widget head,
      required Widget slots,
      required Widget foot}) {
    return SizedBox(
      key: key,
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: _headHeight(context), child: head),
        const SizedBox(height: 1),
        Expanded(
            child: ColoredBox(
                color: theme.studio.strip,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                    child: slots))),
        const SizedBox(height: 1),
        SizedBox(
            height: _footH,
            child: ColoredBox(color: theme.studio.strip, child: foot)),
      ]),
    );
  }

  /// _headHeight is a column's head at the text size: its two lines.
  double _headHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_slotsHeadH);

  /// _head is a column's head: a bar in its colour along the top, its name
  /// with what it holds (motion, sound) and its copies, and under them its
  /// layers, what its sound is, and whether it plays.
  Widget _head(MixerLook theme,
      {required String name,
      required Color colour,
      List<Widget> glyphs = const [],
      List<(String, Color?)> under = const [],
      bool picked = false}) {
    var studio = theme.studio;
    var narrow = controller.slotsPanelNarrow;
    return Container(
      color: picked ? theme.studio.edge : theme.studio.raised,
      child: Stack(children: [
        Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 2,
            child: ColoredBox(color: colour)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: narrow ? 5 : 7),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colors.onSurface)),
                  ),
                  if (!narrow) ...glyphs,
                ]),
                if (!narrow && under.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      for (var (i, (t, c)) in under.indexed)
                        TextSpan(
                            text: i == 0 ? t : "  $t",
                            style: TextStyle(color: c ?? studio.muted)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5),
                  ),
                ],
              ]),
        ),
      ]),
    );
  }

  /// _glyph is a small square mark of what a column holds: its motion, or
  /// its sound -- an instrument's, a voice's, or any other.
  Widget _glyph(IconData mark, Color colour, Color ink) => Container(
        width: 13,
        height: 13,
        margin: const EdgeInsets.only(left: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3)),
        child: Icon(mark, size: 9, color: ink),
      );

  /// _stop is a column's stop, under its slots: lit while it plays.
  Widget _stop(MixerLook theme, Key key, bool lit, VoidCallback onTap) =>
      Center(
        child: Material(
          color: lit ? theme.studio.edge : theme.studio.inset,
          borderRadius: BorderRadius.circular(3),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(3),
            onTap: onTap,
            child: SizedBox(
              width: 22,
              height: 14,
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: lit ? theme.studio.text : theme.studio.muted,
                      borderRadius: BorderRadius.circular(1)),
                ),
              ),
            ),
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
    var playing = (channel != null && controller.clipPlaying(channel.key)) ||
        (e != null && controller.motionPlayer.isOff(e.id));
    var instrument =
        channel != null && controller.instrumentChannel(channel.key);
    var copies = e?.base.motion.instances?.count ?? 1;
    var layers = e?.base.motion.layersInUse.length ?? 0;
    var name =
        e != null ? (e.name.isEmpty ? e.id : e.name) : channel?.name ?? key;
    return _frame(
      theme,
      key: ValueKey("slotsColumn-$key"),
      width: width,
      head: _head(theme,
          name: name,
          // Its row's colour (Ken, 2026-11-10).
          colour: controller.rowColour(key),
          picked: e != null
              ? controller.selection.contains(e.id)
              : controller.selectedChannel == channel?.key,
          glyphs: [
            if (e != null)
              _glyph(Icons.diamond, motionColour, const Color(0xFF8FE3C6)),
            if (channel != null)
              instrument
                  ? _glyph(Icons.music_note, const Color(0xFFD9A15A),
                      const Color(0xFFF1C089))
                  : _glyph(
                      Icons.music_note, soundColour, const Color(0xFFA9CBF2)),
            if (copies > 1)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text("×$copies",
                    style: const TextStyle(
                        fontSize: 9.5, color: Color(0xFFE2B04A))),
              ),
          ],
          under: [
            if (layers > 0) ("$layers layer${layers == 1 ? "" : "s"}", null),
            if (channel != null)
              (
                e != null
                    ? "Sound"
                    : instrument
                        ? "MIDI"
                        : "Audio",
                null
              ),
            if (r.group == RowGroup.all) ("All", null),
            if (playing) ("playing", const Color(0xFF9BF0A6)),
          ]),
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
      foot: _stop(theme, ValueKey("slotsStop-$key"), playing, () {
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
      head: _head(theme,
          name: "Scenes",
          colour: sceneColour,
          under: const [("transitions, not in cues", null)]),
      slots: _clipColumn(
        _joins,
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

  /// _cues is the cue column: a launch for each cue row, Stop all under,
  /// its right edge dragged wider or narrower.
  Widget _cues(MixerLook theme, double width, double sound, double motion,
      {bool master = false}) {
    var studio = theme.studio;
    return Stack(children: [
      _frame(
        theme,
        key: ValueKey(master ? "slotsMasterCues" : "slotsCues"),
        width: width,
        head: _head(theme,
            name: master ? "Master cues" : "Cues",
            colour: studio.muted,
            under: [
              (master ? "launch every scene's row" : "launch a row", null)
            ]),
        slots: _clipColumn(
          _scrolls.of(master ? "masterCues" : _master),
          controller.slotsShown,
          (row) => _SceneSlot(
              key: ValueKey(master ? "masterCue-$row" : "scene-$row"),
              controller: controller,
              row: row,
              master: master,
              theme: theme),
          const SizedBox(),
          clip: sound,
          motion: motion,
          whole: true,
          stop: false,
        ),
        foot: InkWell(
          key: ValueKey(master ? "slotsMasterStopAll" : "clipStopAll"),
          onTap: controller.stopAllClips,
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.stop, size: 12, color: studio.muted),
              if (width >= 70)
                Text(" Stop all",
                    style: TextStyle(fontSize: 10.5, color: studio.muted)),
            ]),
          ),
        ),
      ),
      // Its right edge, dragged to widen or narrow it: each cue column its
      // own width (Ken, 2026-11-10).
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: 6,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: ValueKey(master ? "slotsMasterCueGrip" : "slotsCueGrip"),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => master
                ? controller.slotsMasterCueWidth += d.delta.dx
                : controller.slotsCueWidth += d.delta.dx,
          ),
        ),
      ),
    ]);
  }
}

/// slotsHelp is the slots' "?": the Slots panel's, and the mixer's cue
/// column's.
const slotsHelp = [
  "A column for each element and sound, as the timeline "
      "has them. Each slot is the element's motion over its "
      "sound: press one to launch it on the next bar.",
  "The cues on the left launch a whole row together. The "
      "Scenes column holds the transitions, one per join; a "
      "cue passes it by.",
  "The first button makes every column narrow. The second "
      "steps the slots small, medium, large, or to fill the "
      "panel. The third shows the motion parts, thins them "
      "to a line, or hides them.",
];
