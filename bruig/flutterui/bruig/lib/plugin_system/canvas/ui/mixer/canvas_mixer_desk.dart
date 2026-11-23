part of 'canvas_mixer.dart';

// The desk: the rail of bands, the strips across it (channels, returns, scenes,
// the master) and the cue column. Part of _CanvasMixerState: its fields,
// lifecycle and build are in canvas_mixer.dart.

extension _MixerDesk on _CanvasMixerState {
  /// _desk is the mixer, or the effects, laid out at [zoom]'s share of its
  /// height (see build).
  Widget _desk(BuildContext context, double zoom) {
    var theme = MixerLook.of(context);
    return ListenableBuilder(
      listenable: _deskChanges,
      builder: (context, _) {
        mixerDeskBuilds++;
        _channelsWere =
            [for (var l in controller.timelineChannels) l.key].join("|");
        var lanes = [
          for (var l in controller.timelineChannels)
            if (widget.only == null || l.key == widget.only) l,
        ];
        var editing = _editing;
        var focused = false;
        if (widget.effects &&
            controller.effectsFocusCount != _focusSeen &&
            controller.effectsFocus != null) {
          _focusSeen = controller.effectsFocusCount;
          _scrollTo(controller.effectsFocus!);
          focused = true;
        }
        // Each chain where it was left, so the meters being watched stay in
        // view -- unless a device was asked for, which is scrolled to.
        var chainKey =
            editing == null ? null : "$editing|${controller.speechShown}";
        if (widget.effects && chainKey != _chainKey) {
          if (_chainKey case var was? when _chainScroll.hasClients) {
            _chainOffsets[was] = _chainScroll.offset;
          }
          _chainKey = chainKey;
          var back = chainKey == null ? null : _chainOffsets[chainKey];
          if (!focused) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_chainScroll.hasClients) return;
              _chainScroll.jumpTo((back ?? 0)
                  .clamp(0.0, _chainScroll.position.maxScrollExtent));
            });
          }
        }
        TimelineChannel? lane;
        if (editing != null && editing != _master) {
          lane = lanes.where((l) => l.key == editing).firstOrNull;
          // A channel gone from the timeline: the master's, in the effects
          // panel, which always shows a chain. A return keeps its own.
          if (lane == null &&
              controller.returnOf(editing) == null &&
              editing != sceneBusKey) {
            editing = widget.effects ? _master : null;
          }
        }
        // No scroll bars: the wheel or trackpad scrolls, and a bar would be
        // a stripe across the meters.
        return _SoundScene(
            speakers: controller.document.audio.speakers,
            placed: controller.placementsNow,
            child: ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: Container(
                height: widget.height / zoom,
                decoration: BoxDecoration(
                  color:
                      theme.colors.surfaceContainerLow.withValues(alpha: 0.97),
                  border: Border(
                      top: BorderSide(
                          color: theme.colors.outlineVariant, width: 1)),
                ),
                child: Stack(children: [
                  Positioned.fill(
                    child: Column(children: [
                      if (!widget.embedded && widget.resizable)
                        const SizedBox(height: _edgeRoom),
                      if (widget.embedded) const SizedBox(height: 8),
                      Expanded(
                        child: editing == null
                            ? _leastOrScrolled(_strips(theme, lanes))
                            : _editor(theme, editing, lane),
                      ),
                    ]),
                  ),
                  // Its top edge, dragged to size it. The drag is in the
                  // desk's zoomed coordinates, put back into the screen's so
                  // the edge stays with the pointer.
                  if (!widget.embedded && widget.resizable)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          supportedDevices: dragPointers,
                          key: ValueKey(
                              widget.effects ? "effectsGrip" : "mixerGrip"),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (d) => widget
                              .onResize(widget.height - d.delta.dy * zoom),
                        ),
                      ),
                    ),
                ]),
              ),
            ));
      },
    );
  }

  /// _leastOrScrolled is [strips] given at least their least height (see
  /// mixerLeastHeight) and scrolled where the panel is shorter, as a window
  /// can be.
  Widget _leastOrScrolled(Widget strips) => LayoutBuilder(builder: (c, box) {
        var least = mixerLeastHeight(controller) - _edgeRoom;
        if (widget.embedded || box.maxHeight >= least) return strips;
        return SingleChildScrollView(
            child: SizedBox(height: least, child: strips));
      });

  Widget _strips(MixerLook theme, List<TimelineChannel> lanes) {
    var master = controller.document.masterMix;
    var returns = controller.document.returns;
    var narrow = controller.narrowStrips;
    // In a sound's own settings: its devices and its fader, not clips.
    var states = widget.embedded
        ? const {
            MixerSection.clips: BandState.hidden,
            MixerSection.devices: BandState.shown,
            MixerSection.mixer: BandState.shown,
            MixerSection.sends: BandState.shown,
          }
        : {for (var s in MixerSection.values) s: controller.bandState(s)};
    var showReturns = !widget.embedded && controller.returnsShown;
    // Every band is one height in every column: the tallest column's devices
    // set it, so the faders all start on one line.
    var devicesWanted = [
      for (var l in lanes)
        _ChannelStrip.devicesWanted(
            part: controller.instrumentOf(l.key)?.instrument,
            devices: l.mix.devices.length +
                (l.mix.speech == null ? 0 : 1) +
                (l.mix.vocaliser == null ? 0 : 1)),
      _MasterStrip.devicesWanted(master.devices.length),
      if (showReturns)
        for (var r in returns) _ReturnStrip.devicesWanted(r),
    ].reduce(math.max);
    // Three slots, while the clips and the mixer show whole: a longer chain
    // scrolls rather than squeezing them.
    var devicesCap = _slotsHeight(3);
    // The sends: as tall as the most dials take (a narrow column's, two to a
    // row, where there is one).
    var sendsH = widget.embedded && lanes.isEmpty
        ? 0.0
        : math.max(
            sendsHeight(returns.length),
            lanes.any((l) => narrow.contains(l.key))
                ? sendsHeight(returns.length, narrow: true)
                : 0.0);
    // The rows every panel shows (see canvas_rows.dart), outside a sound's
    // settings and the effects: each element's strip with its own sound
    // beside it, then the sounds that are nobody's, in the timeline's order.
    var canvasRows = widget.embedded || widget.effects
        ? const <CanvasRow>[]
        : canvasRowsOf(controller);
    var rows = [
      for (var r in canvasRows)
        if (r.element case var e?) e
    ];
    var ownedKeys = {
      for (var r in canvasRows)
        if (r.element != null)
          for (var c in r.channels) c.key
    };
    // The sounds that are nobody's, each with its place among the strips'
    // lanes: in the rows' order, or -- with no rows, in a sound's own
    // settings or the effects -- every lane as it comes.
    var loose = canvasRows.isEmpty
        ? [
            for (var (i, l) in lanes.indexed)
              if (!ownedKeys.contains(l.key)) (i, l)
          ]
        : [
            for (var r in canvasRows)
              // The transitions' sounds are the Scenes strip's, a slot for
              // each join, not a strip of their own.
              if (r.element == null && !(r.transitions && _sceneShown))
                for (var c in r.channels)
                  if (lanes.indexWhere((l) => l.key == c.key) case var i
                      when i >= 0)
                    (i, lanes[i])
          ];
    var show = controller.timelineShow;
    // The All group's: on the master canvas, there in every scene.
    var everyScene = {
      for (var r in canvasRows)
        if (r.group == RowGroup.all)
          for (var ch in r.channels) ch.key
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: LayoutBuilder(builder: (context, box) {
        // At its smallest: no heads, and no rail of bands.
        var bare =
            !widget.embedded && !widget.effects && controller.mixerSmallest;
        // Elements with strips: every column a motion half over its sound
        // half, every slot row a motion part over its sound part.
        var withMotion = rows.isNotEmpty && show != TimelineShow.sound;
        // Each element's own sound's place among the lanes, -1 for none.
        var ownLane = {
          for (var e in rows)
            e.id: lanes.indexWhere(
                (l) => l.key == ownChannelOf(controller.document, e.id))
        };
        // What was chosen, stepped down a band at a time while it does not
        // fit: the devices to a line, the sends hidden, the mixer minimised
        // (on its side), the devices hidden, and last the slots. Each stepped
        // band is lit amber on the rail; all grow back as soon as they fit.
        var inner = box.maxHeight - 14;
        var fitted = Map.of(states);
        var auto = <MixerSection>{};
        double need() => _Bands.need(fitted,
            devicesWanted: devicesWanted,
            devicesCap: devicesCap,
            sendsH: sendsH,
            bare: bare,
            motion: withMotion,
            motionSlots: controller.motionSlots);
        void stepDown(MixerSection s, BandState to) {
          var now = fitted[s]!;
          if (now == BandState.hidden || now == to) return;
          if (to == BandState.minimised && now != BandState.shown) return;
          fitted[s] = to;
          auto.add(s);
        }

        if (!widget.embedded && !widget.effects && !bare) {
          for (var (s, to) in [
            (MixerSection.devices, BandState.minimised),
            (MixerSection.sends, BandState.hidden),
            (MixerSection.mixer, BandState.minimised),
            (MixerSection.devices, BandState.hidden),
            (MixerSection.clips, BandState.hidden),
          ]) {
            if (need() <= inner) break;
            stepDown(s, to);
          }
        }
        var bands = _Bands.fit(
            inner, fitted, devicesWanted, devicesCap,
            sendsH: sendsH,
            bare: bare,
            clipRows: controller.slotsShown,
            motion: withMotion,
            motionSlots: controller.motionSlots);
        // The rail first, then the channels, scrolled; the returns, the
        // scene's bus and the master pinned on the right as wide as they are
        // -- or, where that leaves no room for a channel, scrolled themselves.
        var rail = widget.embedded || bare
            ? null
            : _BandRail(
                theme: theme,
                // Folded in a narrow room, for a channel's room.
                folded: controller.mixerRailFolded || box.maxWidth < 320,
                onFold: () => controller.mixerRailFolded =
                    !controller.mixerRailFolded,
                bands: [
                  if (withMotion)
                    _RailBand("motion", "Motion", Icons.animation,
                        controller.motionSlots,
                        (s) => controller.motionSlots = s),
                  for (var s in [
                    MixerSection.clips,
                    MixerSection.devices,
                    MixerSection.sends,
                    MixerSection.mixer,
                  ])
                    _RailBand(
                        s.name,
                        switch (s) {
                          MixerSection.clips => "Sound",
                          MixerSection.devices => "Devices",
                          MixerSection.sends => "Sends",
                          MixerSection.mixer => "Mixer",
                        },
                        switch (s) {
                          MixerSection.clips => Icons.grid_view,
                          MixerSection.devices => Icons.tune,
                          MixerSection.sends => Icons.call_made,
                          MixerSection.mixer => Icons.equalizer,
                        },
                        states[s]!,
                        (state) => controller.setMixerSection(s, state),
                        canMinimise: s != MixerSection.sends,
                        auto: auto.contains(s)),
                ],
                returnsShown: controller.returnsShown,
                onReturns: () =>
                    controller.returnsShown = !controller.returnsShown,
                allNarrow: _allKeys(lanes, rows).every(narrow.contains),
                onNarrowAll: () {
                  var keys = _allKeys(lanes, rows);
                  controller.setAllNarrow(keys, !keys.every(narrow.contains));
                },
              );
        var desk = CustomMultiChildLayout(
            delegate: _PinnedRight(leftLeast: 124),
            children: [
              LayoutId(
                id: _PinnedRight.left,
                child: lanes.isEmpty && widget.embedded
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            "A strip appears here for each video and background "
                            "sound on the timeline. The master strip is always "
                            "here, and sets how the whole canvas sounds.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colors.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // The elements' strips first, as the timeline has
                          // their rows: one strip each, its motion half and
                          // slots over its own sound's; with no sound of its
                          // own, or the motion alone shown, its motion strip.
                          for (var e in rows)
                            if (show != TimelineShow.animation &&
                                (ownLane[e.id] ?? -1) >= 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: KeyedSubtree(
                                  key: show == TimelineShow.sound
                                      ? null
                                      : ValueKey("motionStrip-${e.id}"),
                                  child: _channelStrip(theme,
                                      lanes[ownLane[e.id]!], ownLane[e.id]!,
                                      bands,
                                      element: show == TimelineShow.sound
                                          ? null
                                          : e),
                                ),
                              )
                            else if (show != TimelineShow.sound)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _elementStrip(controller, theme, e,
                                    bands, _clipScrolls.of("motion:${e.id}")),
                              ),
                          // Then the sounds that are nobody's; none shows
                          // only the animation.
                          if (show != TimelineShow.animation) ...[
                            for (var (i, lane) in loose)
                              if (!everyScene.contains(lane.key))
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _channelStrip(theme, lane, i, bands),
                                ),
                            // The All group's last, behind a tab that folds
                            // them away, as on the timeline.
                            if (loose.any((l) => everyScene.contains(l.$2.key)))
                              ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _AllFold(
                                  controller: controller,
                                  theme: theme,
                                  count: loose
                                      .where((l) =>
                                          everyScene.contains(l.$2.key))
                                      .length,
                                ),
                              ),
                              // The master's cues before its channels, on a
                              // scene with cues of its own.
                              if (!controller.allFolded &&
                                  controller.cuesApart &&
                                  bands.clips != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _CueColumn(
                                    controller: controller,
                                    theme: theme,
                                    bands: bands,
                                    master: true,
                                    width: controller.masterCueColumnWidth,
                                    slots: _SceneBand(
                                        controller: controller,
                                        theme: theme,
                                        master: true,
                                        motion: bands.motionClip,
                                        scroll: _clipScrolls.of("masterCues")),
                                  ),
                                ),
                              if (!controller.allFolded)
                                for (var (i, lane) in loose)
                                  if (everyScene.contains(lane.key))
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8),
                                      child: _channelStrip(
                                          theme, lane, i, bands,
                                          all: true),
                                    ),
                            ],
                          ],
                        ],
                      ),
              ),
              LayoutId(
                id: _PinnedRight.right,
                child: SingleChildScrollView(
                  key: const ValueKey("mixerPinned"),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The returns, pinned beside the master as Ableton's
                        // are. At most half the width; past that they scroll.
                        if (showReturns) ...[
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: box.maxWidth / 2),
                            child: SingleChildScrollView(
                              key: const ValueKey("returnsPinned"),
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (var (i, ret) in returns.indexed)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child:
                                            _returnStrip(theme, ret, i, bands),
                                      ),
                                    if (returns.length < maxReturns)
                                      _AddReturn(
                                          theme: theme,
                                          onAdd: () {
                                            controller.beginInteraction();
                                            controller.addReturn();
                                            controller.endInteraction();
                                          }),
                                  ]),
                            ),
                          ),
                        ],
                        if (_sceneShown) ...[
                          const SizedBox(width: 8),
                          _SceneStrip(
                            key: const ValueKey("strip-scene"),
                            // A slot for each join between scenes, outside
                            // the cue rows; its motion, the camera.
                            joins: controller.document.allScenes.length < 2
                                ? null
                                : () => _clipColumn(
                                    _joinScroll,
                                    controller.document.allScenes.length - 1,
                                    (i) => _JoinSlot(
                                        key: ValueKey("join-$i"),
                                        controller: controller,
                                        join: i,
                                        theme: theme),
                                    // A cue launches every column's row
                                    // but this one's.
                                    controller.narrowStrips
                                            .contains(sceneBusKey)
                                        ? const SizedBox()
                                        : _MiniNote("not in cues", theme,
                                            key: const ValueKey(
                                                "sceneNotInCues")),
                                    motion: bands.motionClip,
                                    whole: true),
                            motionLine: () => _MiniNote(
                                controller.narrowStrips.contains(sceneBusKey)
                                    ? ""
                                    : _transitionsSaid(
                                        controller.document.allScenes.length -
                                            1),
                                theme,
                                diamond: true,
                                key: const ValueKey("sceneMotionLine")),
                            motion: () => _SceneMotion(
                                theme: theme,
                                narrow: controller.narrowStrips
                                    .contains(sceneBusKey)),
                            name: controller.document.scene.saysAt(
                                controller.document.at,
                                controller.document.kind),
                            mix: controller.sceneBus,
                            chain: controller.chainOf(sceneBusKey),
                            meter: _Meter(_board, sceneBusKey),
                            theme: theme,
                            bands: bands,
                            narrow: narrow.contains(sceneBusKey),
                            onNarrow: () =>
                                controller.toggleNarrow(sceneBusKey),
                            onChanged: (mix, {transient = false}) {
                              controller.beginInteraction();
                              controller.setSceneBus(mix, transient: true);
                              if (!transient) controller.endInteraction();
                            },
                            onCommit: controller.endInteraction,
                            onOpen: (device) => controller
                                .openEffects(sceneBusKey, device: device),
                            onRemoveDevice: (id) =>
                                _removeDevice(sceneBusKey, id),
                            selected: controller.selectedChannel == sceneBusKey,
                            onSelect: () => controller.pickStrip(sceneBusKey),
                          ),
                        ],
                        const SizedBox(width: 8),
                        _MasterStrip(
                          key: const ValueKey("strip-master"),
                          mix: master,
                          speakers: controller.document.audio.speakers,
                          meter: _Meter(_board, _master),
                          theme: theme,
                          bands: bands,
                          narrow: narrow.contains(_master),
                          onNarrow: () => controller.toggleNarrow(_master),
                          onChanged: (mix, {transient = false}) {
                            controller.beginInteraction();
                            controller.setMasterMix(mix, transient: true);
                            if (!transient) controller.endInteraction();
                          },
                          onCommit: controller.endInteraction,
                          onOpenEq: () => _open(_master, _Opened.eq),
                          onOpenComp: () => _open(_master, _Opened.comp),
                          onOpenLoudness: () =>
                              _open(_master, _Opened.loudness),
                          onOpenDevice: (id) =>
                              controller.openEffects(_master, device: id),
                          onRemoveDevice: (id) => _removeDevice(_master, id),
                          // The cues are a column of their own, on the left:
                          // see _CueColumn.
                          scenes: () => widget.embedded || widget.effects
                              ? _SceneBand(
                                  controller: controller,
                                  theme: theme,
                                  motion: bands.motionClip,
                                  scroll: _clipScrolls.of(_master))
                              : const SizedBox(),
                          selected: controller.selectedChannel == _master,
                          onSelect: () => controller.pickStrip(_master),
                        ),
                      ]),
                ),
              ),
            ]);
        if (rail == null) return desk;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          rail,
          const SizedBox(width: 6),
          if (bands.clips != null) ...[
            _CueColumn(
              controller: controller,
              theme: theme,
              bands: bands,
              // At its least in a narrow room: the arrows alone.
              width: box.maxWidth < 480
                  ? MixerLayout.cueColumnLeast
                  : controller.cueColumnWidth,
              slots: _SceneBand(
                  controller: controller,
                  theme: theme,
                  motion: bands.motionClip,
                  scroll: _clipScrolls.of(_master)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: desk),
        ]);
      }),
    );
  }

  /// _removeDevice takes device [id] ("dev:d2", "midi0", "speech") out of strip
  /// [key]'s chain, as one change to undo.
  void _removeDevice(String key, String id) {
    controller.beginInteraction();
    if (id == "speech") {
      controller.setSpeech(key, null);
    } else if (id == "vocaliser") {
      controller.setVocaliser(key, null);
    } else if (id.startsWith("midi")) {
      var i = int.tryParse(id.substring(4)) ?? -1;
      controller.setChannelPart(
          key,
          (p) => i < 0 || i >= p.effects.length
              ? p
              : p.copyWith(effects: [...p.effects]..removeAt(i)));
    } else if (deviceKeyId(id) case var dev?) {
      var now = controller.devicesOf(key);
      var i = deviceIndexOf(now, dev);
      if (i >= 0) controller.setDevicesOf(key, [...now]..removeAt(i));
    }
    controller.endInteraction();
  }

  List<String> _allKeys(
          List<TimelineChannel> lanes, List<CanvasElement> rows) =>
      [
        for (var l in lanes) l.key,
        for (var e in rows) motionStripKey(e.id),
        for (var r in controller.document.returns) r.id,
        if (_sceneShown) sceneBusKey,
        _master,
      ];

  /// _sceneShown is whether the scene's bus has a strip: in a document of
  /// scenes, or with a master's sounds to go past it. Not in a sound's own
  /// settings, which show its channel and the master's.
  bool get _sceneShown =>
      widget.only == null &&
      (controller.document.hasScenes || controller.document.masterOn);

  Widget _channelStrip(
      MixerLook theme, TimelineChannel lane, int index, _Bands bands,
      {CanvasElement? element, bool all = false}) {
    var e = lane.first.element;
    var narrowNow = controller.narrowStrips.contains(lane.key);
    // As it plays now: a setting a lane moves, where the lane has it, and a
    // hand on one holds it there. See changeChannelMix.
    var shown = controller.mixNow(lane);
    return _ChannelStrip(
      key: ValueKey("strip-${lane.key}"),
      motionDevices: element == null
          ? const []
          : _motionDeviceSlots(controller, theme, element),
      badges: stripBadges(theme, lane.key, element: element, all: all),
      rowColour: controller.rowColour(element?.id ?? lane.key),
      name: lane.name,
      number: index + 1,
      channelKey: lane.key,
      mix: shown,
      automated: {
        for (var l in lane.mix.automation)
          if (l.points.isNotEmpty) l.target
      },
      held: controller.overridden[lane.key] ?? const {},
      // In a sound's own settings it was picked on purpose, and is changed
      // there wherever it is.
      editable: lane.editable || widget.embedded,
      soloed: controller.solo.contains(lane.key),
      midi: e is AudioElement && e.instrument != null,
      part: controller.instrumentOf(lane.key)?.instrument,
      onOpenDevice: (id) => controller.openEffects(lane.key, device: id),
      onRemoveDevice: (id) => _removeDevice(lane.key, id),
      armed: controller.armed.contains(lane.key),
      meter: _Meter(_board, lane.key),
      theme: theme,
      bands: bands,
      narrow: controller.narrowStrips.contains(lane.key),
      onNarrow: () => controller.toggleNarrow(lane.key),
      onChanged: (mix, {transient = false}) {
        controller.beginInteraction();
        controller.changeChannelMix(lane, shown, mix,
            transient: true, anywhere: widget.embedded);
        if (!transient) controller.endInteraction();
      },
      onCommit: controller.endInteraction,
      onSolo: () => controller.toggleSolo(lane.key),
      onArm: () => controller.toggleArm(lane.key),
      onOpenEq: () => _open(lane.key, _Opened.eq),
      onOpenComp: () => _open(lane.key, _Opened.comp),
      onOpenDuck: () => _open(lane.key, _Opened.duck),
      onOpenPanner: () => controller.openEffects(lane.key, device: "panner"),
      motion: element == null
          ? null
          : () => _MotionHalf(
              controller: controller,
              element: element,
              narrow: narrowNow,
              theme: theme),
      leadSlot: element == null
          ? null
          : _ElementSoundBand(
              controller: controller, element: element, theme: theme),
      motionLine: element == null
          ? null
          : () => _MotionLine(
              controller: controller,
              element: element,
              narrow: narrowNow,
              theme: theme),
      clips: () => _ClipBand(
          controller: controller,
          channel: lane.key,
          theme: theme,
          scroll: _clipScrolls.of(lane.key),
          motion: bands.motionClip,
          motionRow: element == null
              ? null
              : (row) => _MotionSlot(
                  key: ValueKey("motionSlot-${element.id}-$row"),
                  controller: controller,
                  element: element.id,
                  row: row,
                  theme: theme)),
      selected: controller.selectedChannel == lane.key,
      onSelect: () => controller.pickStrip(lane.key),
      onRename: (name) => controller.renameChannel(lane, name),
      returns: controller.document.returns,
    );
  }

  Widget _returnStrip(
          MixerLook theme, ReturnChannel ret, int index, _Bands bands) =>
      _ReturnStrip(
        key: ValueKey("strip-${ret.id}"),
        letter: returnLetter(index),
        ret: ret,
        meter: _Meter(_board, ret.id),
        theme: theme,
        bands: bands,
        narrow: controller.narrowStrips.contains(ret.id),
        onNarrow: () => controller.toggleNarrow(ret.id),
        onChanged: (next, {transient = false}) {
          controller.beginInteraction();
          controller.setReturn(next, transient: true);
          if (!transient) controller.endInteraction();
        },
        onCommit: controller.endInteraction,
        onOpen: (device) => controller.openEffects(ret.id, device: device),
        onRemoveDevice: (id) => _removeDevice(ret.id, id),
        onRemove: () {
          controller.beginInteraction();
          controller.removeReturn(ret.id);
          controller.endInteraction();
        },
        selected: controller.selectedChannel == ret.id,
        onSelect: () => controller.pickStrip(ret.id),
      );
}
