part of 'canvas_channels.dart';

// The rows: headings, the scenes' header, each channel's row and its lanes.
// Part of _CanvasChannelsState: its fields, lifecycle and build are in
// canvas_channels.dart.

extension _ChannelRows on _CanvasChannelsState {
  /// _allHeading is the All group's heading: "All scenes", how many rows
  /// are in it, and an arrow folding them away. On a scene with cues of its
  /// own, the master's cues are over the slots beside it; [width] is the
  /// strips'.
  Widget _allHeading(ThemeNotifier theme, int count, double width) {
    var colors = theme.colors;
    var folded = controller.allFolded;
    var slots = slotsWidthIn(context, controller);
    var cues = controller.cuesApart && slots > 0;
    var fold = InkWell(
      key: const ValueKey("allGroupFold"),
      onTap: () => controller.allFolded = !folded,
      child: Row(children: [
        const SizedBox(width: 6),
        Icon(folded ? Icons.chevron_right : Icons.expand_more,
            size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text("All scenes",
            maxLines: 1,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.onSurface)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6)),
          child: Text("$count",
              key: const ValueKey("allGroupCount"),
              style: TextStyle(
                  fontSize: 9.5, height: 1.4, color: colors.onSurfaceVariant)),
        ),
      ]),
    );
    return Container(
      key: const ValueKey("allGroupHeading"),
      height: 24,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(
            bottom: BorderSide(color: colors.outline.withValues(alpha: 0.5))),
      ),
      child: !cues
          ? fold
          : LayoutBuilder(
              builder: (context, box) => Row(children: [
                    SizedBox(width: math.min(width, box.maxWidth), child: fold),
                    SizedBox(
                      key: const ValueKey("masterCueLaunches"),
                      width:
                          math.min(slots, math.max(0.0, box.maxWidth - width)),
                      child: cueLaunchRow(controller, colors, master: true),
                    ),
                  ])),
    );
  }

  /// _scenesHeader is the Scenes row's header (row_header.dart): its
  /// count, the scene's motion (its camera and transitions) shown, and its
  /// sound button the transitions' sounds'.
  Widget _scenesHeader(
      ThemeNotifier theme, double width, List<TimelineChannel> transitions) {
    var colors = theme.colors;
    var heard = transitions.isNotEmpty &&
        controller.laneSize > 0 &&
        controller.timelineShow != TimelineShow.animation;
    var scenes = controller.document.allScenes.length;
    void mute(TimelineChannel ch) {
      var now = controller.mixNow(ch);
      controller.beginInteraction();
      controller.changeChannelMix(ch, now, now.copyWith(mute: !now.mute),
          transient: true);
      controller.endInteraction();
    }

    return RowHeader(
      key: const ValueKey("scenesHeader"),
      fold: RowFold(
          key: const ValueKey("rowFold-scenes"),
          folded: controller.rowFolded("scenes"),
          onTap: () => controller.toggleRowFold("scenes")),
      colour: sceneColour,
      width: width,
      height: sceneStripHeight,
      joinsBelow: heard,
      name: Text("Scenes",
          key: const ValueKey("sceneStripLabel"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface)),

      motion: const RowToggle(ValueKey("rowMotion-scenes"), on: true),
      // The transitions' sounds are made from the transitions, not kept as
      // a channel to change: their button shows them heard, and switches
      // them only where they can be.
      sound: transitions.isEmpty
          ? null
          : RowToggle(const ValueKey("rowMute-scenes"),
              on: !controller.mixNow(transitions.first).mute,
              onTap: transitions.first.editable
                  ? () => mute(transitions.first)
                  : null),
      // How many, beside the row, so the name keeps its room.
      bands: [
        RowBand(0, sceneStripHeight, "$scenes scene${scenes == 1 ? "" : "s"}",
            sceneColour)
      ],
    );
  }

  /// _channelRows is [channel]'s row and, opened under it, its automation.
  /// [movable] is whether its strip is dragged to move it among the others:
  /// not an element's own sound, which stays under the element.
  List<Widget> _channelRows(TimelineChannel channel, double width,
          ThemeNotifier theme, List<TimelineChannel> channels,
          {bool movable = true,
          bool owned = false,
          bool all = false,
          bool alt = false,
          Color? accent}) =>
      [
        _row(channel.key, _heightOf(channel.key), width,
            alt: alt,
            moving: channel.key == _moving,
            accent: owned ? accent ?? theme.colors.primary : null,
            // Playing from its slots: striped, saying so on its own row, or
            // on its element's above.
            over: controller.fromSlotsOf(channel.key) == null
                ? null
                : SlotsStripes(
                    key: ValueKey("rowFromSlots-${channel.key}"),
                    note: !owned ||
                        controller.timelineShow == TimelineShow.sound),
            beside: controller.slotsBeside
                ? SessionRowSlots(controller: controller, channel: channel.key)
                : null,
            header: _ChannelHeader(
              key: ValueKey("channelStrip-${channel.key}"),
              controller: controller,
              rowColour: controller.rowColour(_foldKeyOf(channel.key)),
              onColour: (colour) =>
                  controller.setRowColour(_foldKeyOf(channel.key), colour),
              fold: RowFold(
                  key: ValueKey("rowFold-${channel.key}"),
                  folded: controller.rowFolded(channel.key),
                  onTap: () => controller.toggleRowFold(channel.key)),
              owned: owned && controller.timelineShow != TimelineShow.sound,
              onBack: switch (controller.fromSlotsOf(channel.key)) {
                var item?
                    when !owned ||
                        controller.timelineShow == TimelineShow.sound =>
                  () => controller.backToTimelineFor(item),
                _ => null,
              },
              channel: channel,
              mix: controller.mixNow(channel),
              automation: controller.automationShown.contains(channel.key),
              onAutomation: () => controller.toggleAutomation(channel.key),
              // Which canvas its clips are on -- M for the master, S1 for the
              // first scene, "All" in the All group -- beside the band whose
              // colour says sound or video.
              label: all ? "All" : channel.sceneLabel,
              width: width,
              height: _heightOf(channel.key),
              selected: controller.selectedChannels.contains(channel.key),
              soloed: controller.solo.contains(channel.key),
              theme: theme,
              // Shift picks it as well as the others, or leaves it.
              onSelect: () {
                if (HardwareKeyboard.instance.isShiftPressed) {
                  controller.toggleChannel(channel.key);
                  return;
                }
                controller.selectedChannel = channel.key;
                // And what it is the sound of -- its element, or the one
                // sound on it -- so the settings, the mixer and the Chain
                // show it too.
                var owner = soundOwnerOf(controller.document, channel.key);
                var on = {for (var l in channel.lanes) l.element.id};
                var id = owner?.id ?? (on.length == 1 ? on.single : null);
                if (id != null) controller.pickClip(id);
              },
              onRename: (name) => controller.renameChannel(channel, name),
              // As the mixer's fader: a level typed over a lane is
              // held by hand -- see changeChannelMix.
              onMix: (mix) {
                controller.beginInteraction();
                controller.changeChannelMix(
                    channel, controller.mixNow(channel), mix,
                    transient: true);
                controller.endInteraction();
              },
              onLock: () => controller.lockChannel(channel, !channel.locked),
              onSolo: () => controller.toggleSolo(channel.key),
              onGripStart: (y) {
                _gripFrom = y;
                _gripHeight = _heightOf(channel.key);
              },
              onGripMove: (y) => controller.setLaneHeight(
                  channel.key,
                  (_gripHeight + y - _gripFrom)
                      .clamp(_laneMin, _laneMax)
                      .toDouble()),
              onMoveStart: (_) {
                if (movable) _startMove(channels, channel.key);
              },
              onMove: (y) {
                var to = _slotAt(y);
                if (to != _moveTo) setState(() => _moveTo = to);
              },
              onMoveEnd: _endMove,
            ),
            lane: _lane(channel, theme)),
        // Its automation, opened under it: a lane for each setting
        // shown, and a row to show another.
        if (controller.automationShown.contains(channel.key) &&
            channel.editable &&
            channel.key != _moving) ...[
          for (var (i, target) in controller.automationRows(channel).indexed)
            SizedBox(
              key: ValueKey("autoRow-${channel.key}-$i"),
              height: automationLaneHeight,
              child: Row(children: [
                SizedBox(
                    width: leftWidthIn(context, controller),
                    child: AutomationLaneHeader(
                        controller: controller,
                        channel: channel,
                        index: i,
                        width: width)),
                Expanded(
                    child: AutomationLaneBody(
                        key: ValueKey("autoBody-${channel.key}-$target"),
                        controller: controller,
                        channel: channel,
                        target: target,
                        view: _view)),
              ]),
            ),
          SizedBox(
            height: automationAddHeight,
            child: Row(children: [
              SizedBox(
                  width: leftWidthIn(context, controller),
                  child: AutomationAddRow(
                      controller: controller, channel: channel)),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ],
      ];

  void _startMove(List<TimelineChannel> channels, String key) {
    var mids = <double>[];
    var at = 0;
    for (var (i, c) in channels.indexed) {
      if (c.key == key) {
        at = i;
        continue;
      }
      var box = _keyFor(c.key).currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      mids.add(box.localToGlobal(Offset.zero).dy + box.size.height / 2);
    }
    setState(() {
      _moving = key;
      _moveTo = at;
      _rowsAtStart = mids;
    });
  }

  /// _slotAt is where in the list, without the channel being moved, a
  /// pointer at [y] would put it: after every row whose middle it is below.
  int _slotAt(double y) => _rowsAtStart.where((mid) => y > mid).length;

  /// _withMoving is [channels] in the order the drag would leave them.
  List<TimelineChannel> _withMoving(List<TimelineChannel> channels) {
    var key = _moving, to = _moveTo;
    if (key == null || to == null) return channels;
    var moving = channels.where((c) => c.key == key).firstOrNull;
    if (moving == null) return channels;
    var rest = [
      for (var c in channels)
        if (c.key != key) c
    ];
    rest.insert(to.clamp(0, rest.length).toInt(), moving);
    return rest;
  }

  void _endMove() {
    var key = _moving, to = _moveTo;
    setState(() {
      _moving = null;
      _moveTo = null;
      _rowsAtStart = const [];
    });
    if (key == null || to == null) return;
    // Its place among the others moved, in the list of every channel --
    // an element's own among them, which stay under their elements.
    var all = [
      for (var c in controller.timelineChannels)
        if (c.key != key) c.key
    ];
    var free = [
      for (var k in all)
        if (soundOwnerOf(controller.document, k) == null) k
    ];
    controller.moveChannel(
        key, to >= free.length ? all.length : all.indexOf(free[to]));
  }

  Widget _boxOverlay(ThemeNotifier theme) {
    var stack = _stack.currentContext?.findRenderObject();
    if (stack is! RenderBox) return const SizedBox.shrink();
    var rect = Rect.fromPoints(
        stack.globalToLocal(_boxFrom!), stack.globalToLocal(_boxTo!));
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Container(
          key: const ValueKey("channelsBox"),
          decoration: BoxDecoration(
            color: theme.colors.primary.withValues(alpha: 0.08),
            border: Border.all(color: theme.colors.primary),
          ),
        ),
      ),
    );
  }

  Widget _row(String channel, double height, double width,
      {required Widget header,
      required Widget lane,
      bool moving = false,
      Color? accent,
      Widget? beside,
      Widget? over,
      bool alt = false}) {
    // The strip and the slots at most as wide as the row: shown alone, the
    // slots fill to the edge, and a scaled text size can leave them a
    // fraction of a pixel over it.
    var row = LayoutBuilder(builder: (context, box) {
      var head = math.min(width, box.maxWidth);
      var slots = math.min(slotsWidthIn(context, controller),
          math.max(0.0, box.maxWidth - head));
      return Row(children: [
        // An element's own sound: the element's stripe down its left, drawn
        // over the strip so nothing in it moves.
        SizedBox(
            width: head,
            child: accent == null
                ? header
                : DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                        border:
                            Border(left: BorderSide(color: accent, width: 3))),
                    child: header)),
        // The slots beside the rows, when they are: a channel's, or room.
        if (slots > 0)
          SizedBox(width: slots, child: beside ?? const SizedBox()),
        // The frames, unless this is the slots shown alone.
        Expanded(
            child: !lanesIn(context)
                ? const SizedBox()
                : over == null
                    // Every other row tinted.
                    ? alt
                        ? ColoredBox(
                            color: ThemeNotifier.of(context)
                                .colors
                                .onSurface
                                .withValues(alpha: 0.025),
                            child: lane)
                        : lane
                    : Stack(children: [
                        Positioned.fill(child: lane),
                        Positioned.fill(child: over),
                      ])),
      ]);
    });
    var colors = ThemeNotifier.of(context).colors;
    return SizedBox(
      key: _keyFor(channel),
      height: height,
      // The channel being moved, lit across its strip and its lane. Always
      // in a Stack, lit or not: changing what the row is built from as the
      // drag began would throw away the strip the drag started on.
      child: Stack(children: [
        Positioned.fill(child: row),
        if (moving)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey("channelMoving"),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.16),
                  border: Border.all(color: colors.primary, width: 1.5),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  /// _playedIn is the frames of this view [channel]'s clips are played in:
  /// its own scene's while every scene plays (the master's, the whole run),
  /// so a clip running past its scene is shaded there; else the scene's.
  (int?, int?) _playedIn(TimelineChannel channel) {
    var document = controller.document;
    if (!controller.allChannels || !document.hasScenes) {
      return (null, document.frames);
    }
    var lane = channel.first;
    var from = -lane.offset;
    var scenes = document.allScenes;
    var long = lane.scene >= 0 && lane.scene < scenes.length
        ? scenes[lane.scene].frames
        : document.sequenceFrames;
    return (from, from + long);
  }

  /// _placeSlot puts the clip dragged from a slot onto [channel]'s lane at
  /// [frame]: its own channel's, or another of its kind.
  void _placeSlot(SessionSlotDrag from, int frame, TimelineChannel channel) =>
      controller.placeSessionClip(from.channel, from.row, frame,
          onto: channel.key);

  /// _addAt makes a new sound from [source] at [frame] on [channel], or on a
  /// channel of its own.
  void _addAt(MediaSource source, int frame, TimelineChannel? channel) {
    // A MIDI file: its notes onto a MIDI channel, or a MIDI channel of its
    // own -- never a silent sound on an audio one.
    if (isMidiId(source.assetId)) {
      if (channel != null && controller.instrumentChannel(channel.key)) {
        controller.putMidiOn(channel.key, source.assetId, frame);
      } else if (channel == null) {
        controller.addMidiChannelFrom(source, frame: frame, onCanvas: false);
      }
      return;
    }
    var key = channel?.key ?? controller.newChannelId();
    controller.addElement(channelClip(controller.document, frame,
        source: source,
        channel: key,
        channelName: channel?.name ?? controller.newChannelName(),
        mix: channel?.mix ?? const ChannelMix()));
    controller.selectedChannel = key;
  }

  /// _addVideoAt puts the video [asset] on the canvas, in the middle at its
  /// own shape, and on the timeline from [frame], its soundtrack on a lane of
  /// its own: what "On the timeline" in its settings does.
  void _addVideoAt(LibraryAsset asset, int frame, TimelineChannel? channel) {
    var made = elementForAsset(asset, controller.document);
    if (made is! VideoElement) return;
    var key = channel?.key ?? controller.newChannelId();
    controller.addElement(made.copyWith(
        clip: made.clip.copyWith(
            timed: true,
            at: frame,
            channel: key,
            channelName: channel?.name ?? controller.newChannelName(),
            mix: channel?.mix ?? const ChannelMix())));
    controller.selectedChannel = key;
  }

  /// _slotsOnly is whether [channel] plays from its sample slots and has
  /// nothing on the timeline: its lane greyed, saying so, but still a lane a
  /// sound can be dropped on.
  bool _slotsOnly(TimelineChannel channel) =>
      (controller.session.slots[channel.key]?.any((c) => c != null) ?? false) &&
      channel.lanes.every((l) => l.clip.isEmpty || !l.clip.timed);

  Widget _lane(TimelineChannel channel, ThemeNotifier theme) {
    if (channel.interactive) return _interactiveLane(channel, theme);
    var slotsOnly = _slotsOnly(channel);
    var height = _heightOf(channel.key);
    var tall = height >= _waveformFrom;
    // A sound's shape from its file, and a video's from the soundtrack that
    // was taken out of it when it was added.
    var shapes = <String, Float32List?>{
      if (tall)
        for (var lane in channel.lanes)
          for (var s in lane.clip.playlist)
            if (_shapeOf(lane, s).isNotEmpty)
              _shapeOf(lane, s): controller.waveformOf(_shapeOf(lane, s)),
    };
    var knife = controller.timelineTool == TimelineTool.knife;
    return DragTarget<Object>(
      key: ValueKey("lane-${channel.key}"),
      // A sound or a video joins the channel it is let go on.
      onWillAcceptWithDetails: (d) => switch (d.data) {
        // A clip from a slot, onto its own kind of channel: placed there,
        // once through.
        SessionSlotDrag from =>
          controller.canMoveClip(from.clip, channel.key) &&
              channel.editable &&
              !channel.locked,
        _ => (droppedKind(d.data) == AssetKind.video ||
                droppedKind(d.data) == AssetKind.audio) &&
            // A MIDI file only onto a MIDI channel; a sound only onto one
            // that is not.
            (d.data is LibraryAsset && isMidiId((d.data as LibraryAsset).id)) ==
                controller.instrumentChannel(channel.key) &&
            channel.editable &&
            !channel.locked,
      },
      onAcceptWithDetails: (d) async {
        var at = _frameIn(channel.key, d.offset);
        if (d.data case SessionSlotDrag from) {
          _placeSlot(from, at, channel);
          return;
        }
        var asset = await droppedAsset(d.data);
        if (asset == null) return;
        asset.kind == AssetKind.video
            ? _addVideoAt(asset, at, channel)
            : _addAt(asset.source, at, channel);
      },
      builder: (context, candidate, _) => LayoutBuilder(
        builder: (context, box) => GestureDetector(
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _press(channel, d.localPosition, d.globalPosition,
              box.maxWidth, box.maxHeight),
          // The start is a move too: a pan is recognised only once the
          // pointer has gone some way, and a short drag can end on that step.
          onPanStart: (d) =>
              _drag(d.globalPosition, box.maxWidth, box.maxHeight),
          onPanUpdate: (d) =>
              _drag(d.globalPosition, box.maxWidth, box.maxHeight),
          onPanEnd: (_) => _release(),
          onPanCancel: () {
            // A tap cancels the pan before it lands; only a drag in progress
            // is let go here.
            if (_dragging) _release();
          },
          onTapUp: (d) => _tap(channel, d.localPosition, box.maxWidth),
          child: MouseRegion(
            // From what is under the pointer: the arrow to move a sound,
            // left and right for its ends and fades, up and down for its
            // volume, and the knife's crosshair.
            cursor: knife
                ? SystemMouseCursors.precise
                : _cursors[channel.key] ?? SystemMouseCursors.basic,
            onHover: (e) =>
                _hover(channel, e.localPosition, box.maxWidth, box.maxHeight),
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              foregroundPainter: slotsOnly
                  ? _InteractiveLanePainter(
                      label: "Sample slots in use",
                      colors: theme.colors,
                      chosen: controller.selectedChannels.contains(channel.key),
                      frame: controller.frame,
                      view: _view)
                  : null,
              painter: _LanePainter(
                linked: {
                  for (var l in channel.lanes)
                    if (controller.placementsLinkedTo(l.element.id).isNotEmpty)
                      l.element.id,
                },
                own: soundOwnerOf(controller.document, channel.key) == null
                    ? null
                    : controller.rowColour(_foldKeyOf(channel.key)),
                onMaster: controller.document.editingMaster,
                channel: channel,
                spans: [for (var lane in channel.lanes) _span(lane)],
                view: _view,
                frame: controller.frame,
                frameRate: controller.document.frameRate,
                colors: theme.colors,
                selected: controller.clipSelection,
                chosenChannel:
                    controller.selectedChannels.contains(channel.key),
                held: _dragging ? _held?.element.id : null,
                showVolume: _dragging && _grip == _Grip.volume,
                target: candidate.isNotEmpty || _over == channel.key,
                shapes: shapes,
                sceneFrom: _playedIn(channel).$1,
                sceneTo: _playedIn(channel).$2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// _interactiveLane is the lane of sounds played by pressing them on the
  /// canvas: greyed, with nothing on it to move, cut or drop onto. Pressed,
  /// it picks the channel, so its strip and effects can be opened.
  Widget _interactiveLane(TimelineChannel channel, ThemeNotifier theme) =>
      GestureDetector(
        key: ValueKey("lane-${channel.key}"),
        supportedDevices: timelinePointers,
        behavior: HitTestBehavior.opaque,
        onTapUp: (_) {
          controller.clearSelection();
          controller.selectedChannel = channel.key;
        },
        child: CustomPaint(
          size: Size.infinite,
          painter: _InteractiveLanePainter(
            label: _slotsOnly(channel)
                ? "Sample slots in use"
                : channel.lanes.length > 1
                    ? "${channel.lanes.length} sounds that play when pressed"
                    : channel.video
                        ? "A video that plays when pressed on the canvas"
                        : "Plays when pressed on the canvas",
            colors: theme.colors,
            chosen: controller.selectedChannels.contains(channel.key),
            frame: controller.frame,
            view: _view,
          ),
        ),
      );

  /// _emptyLane is the lane under the last channel: a sound dropped on it,
  /// or chosen by clicking it, starts a channel.
  Widget _emptyLane(ThemeNotifier theme) => DragTarget<Object>(
        key: const ValueKey("lane-new"),
        onWillAcceptWithDetails: (d) =>
            droppedKind(d.data) == AssetKind.audio ||
            droppedKind(d.data) == AssetKind.video,
        onAcceptWithDetails: (d) async {
          var at = _frameIn(_CanvasChannelsState._newLane, d.offset);
          var asset = await droppedAsset(d.data);
          if (asset == null) return;
          asset.kind == AssetKind.video
              ? _addVideoAt(asset, at, null)
              : _addAt(asset.source, at, null);
        },
        builder: (context, candidate, _) => GestureDetector(
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) async {
            var at = _frameIn(_CanvasChannelsState._newLane, d.globalPosition);
            var chosen = await pickCanvasAudio(context, controller);
            if (chosen != null && mounted) _addAt(chosen, at, null);
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _EmptyLanePainter(
              label: CanvasChannels.hint,
              colors: theme.colors,
              lit: candidate.isNotEmpty ||
                  _over == _CanvasChannelsState._newLane,
            ),
          ),
        ),
      );

  /// _frameIn is the frame under [global] across lane [channel]'s frames.
  int _frameIn(String channel, Offset global) {
    var box = _keyFor(channel).currentContext?.findRenderObject();
    var width = leftWidthNow(context, controller);
    if (box is! RenderBox || box.size.width <= width) return controller.frame;
    var x = box.globalToLocal(global).dx - width;
    return _view.frameAt(x, box.size.width - width, controller.timelineReach);
  }
}
