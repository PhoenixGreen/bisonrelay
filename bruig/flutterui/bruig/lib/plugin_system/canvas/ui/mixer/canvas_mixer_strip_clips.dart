part of 'canvas_mixer.dart';

// Clip slots: each column's clips band, the master's scene launchers, the cue
// column, and the shared scrolling and beat they keep to. Part of
// canvas_mixer.dart.

/// _CueColumn is the cue launchers in a column of their own on the mixer's
/// left, level with the strips' slots: a launch for each cue row, and Stop
/// all under them. Dragged by its right edge, 40 to 240 wide; narrowed, each
/// keeps its arrow.
class _CueColumn extends StatelessWidget {
  final CanvasController controller;
  final MixerLook theme;
  final _Bands bands;
  final Widget slots;
  final double width;

  /// master is whether these are the master's cues, beside its channels,
  /// on a scene with cues of its own.
  final bool master;

  const _CueColumn(
      {required this.controller,
      required this.theme,
      required this.bands,
      required this.slots,
      required this.width,
      this.master = false});

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    return SizedBox(
      key: ValueKey(master ? "masterCueColumn" : "cueColumn"),
      width: width,
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!bands.bare)
                    SizedBox(
                      height: _headH,
                      child: Row(children: [
                        Expanded(
                          child: Text(master ? "Master cues" : "Cues",
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface)),
                        ),
                        // One "?" for the cues: the scene's column's.
                        if (width >= 72 && !master)
                          const HelpNote(
                              id: "cues",
                              size: 16,
                              title: "Slots",
                              paragraphs: slotsHelp),
                      ]),
                    ),
                  if (bands.clips case var h?) ...[
                    const SizedBox(height: _bandGap),
                    // Scrolled with the slots beside it, no bar of its own.
                    SizedBox(height: h, child: slots),
                  ],
                ]),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: ValueKey(master ? "masterCueColumnGrip" : "cueColumnGrip"),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => master
                  ? controller.masterCueColumnWidth += d.delta.dx
                  : controller.cueColumnWidth += d.delta.dx,
            ),
          ),
        ),
      ]),
    );
  }
}

/// _ClipScrolls keeps every column's clip slots scrolled together, so a row
/// is one line across the mixer however far down it is.
class _ClipScrolls {
  final Map<String, ScrollController> _of = {};
  bool _syncing = false;

  /// following is a column being moved along with another, right now: its
  /// jump ends at no speed, and it does not settle on a row of its own
  /// (see _RowSnap).
  static bool following = false;

  ScrollController of(String column) =>
      _of[column] ??= ScrollController()..addListener(() => _follow(column));

  void _follow(String column) {
    if (_syncing) return;
    var lead = _of[column];
    if (lead == null || !lead.hasClients) return;
    _syncing = true;
    following = true;
    for (var e in _of.entries) {
      if (e.key == column || !e.value.hasClients) continue;
      var p = e.value.position;
      var to = lead.offset.clamp(p.minScrollExtent, p.maxScrollExtent);
      if ((p.pixels - to).abs() > 0.5) e.value.jumpTo(to);
    }
    _syncing = false;
    following = false;
  }

  void dispose() {
    for (var c in _of.values) {
      c.dispose();
    }
  }
}

/// _OnSessionPulse builds a slot again on each beat of the session's pulse
/// (see _sessionPulse) while [_pulses]: waiting to blink, or playing to go
/// round. The desk is not built again for it.
mixin _OnSessionPulse<T extends StatefulWidget> on State<T> {
  bool get _pulses;

  /// _slotNow is the slot's state now, and _slotWas what it was built
  /// with: changed on a beat -- a clip played out, the playhead moving on
  /// -- it is built again even once it no longer pulses.
  Object? get _slotNow;
  Object? _slotWas;

  void _beat() {
    if (!mounted) return;
    var now = _slotNow;
    if (_pulses || now != _slotWas) {
      _slotWas = now;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _sessionPulse.addListener(_beat);
  }

  @override
  void dispose() {
    _sessionPulse.removeListener(_beat);
    super.dispose();
  }
}

/// _blinkOn is whether something waiting for a bar is lit at this moment:
/// a quarter of a second on, a quarter off.
bool get _blinkOn => DateTime.now().millisecondsSinceEpoch ~/ 250 % 2 == 0;

/// _clipColumn lays a column of clip rows out: [row] for each scene, a
/// slot's height and gap apart, scrolled by [scroll], over [foot]. With
/// [motion], each row is a motion part ([motionRow], or nothing) over its
/// sound part ([row]); [whole] is a row that is both (the cue launch).
/// [clip] is the sound part's height (taller in the Slots panel), and [stop]
/// whether the stop goes under the slots here.
Widget _clipColumn(ScrollController scroll, int rows,
        Widget Function(int row) row, Widget foot,
        {double motion = 0,
        Widget Function(int row)? motionRow,
        bool whole = false,
        double clip = _clipH,
        bool stop = true}) =>
    LayoutBuilder(builder: (context, box) {
      var extent = clip + _clipGap + motion;
      // The wheel a row a notch, as a fling ends on one: taken on the row,
      // before the list's own scrolling (the first to ask has it).
      void wheel(PointerSignalEvent event) {
        if (event is! PointerScrollEvent || !scroll.hasClients) return;
        var d = event.scrollDelta.dy;
        if (d == 0) return;
        GestureBinding.instance.pointerSignalResolver.register(event, (e) {
          var p = scroll.position;
          var now = (p.pixels / extent).round() * extent;
          var to = (now + (d > 0 ? extent : -extent))
              .clamp(p.minScrollExtent, p.maxScrollExtent)
              .toDouble();
          scroll.jumpTo(to);
        });
      }

      Widget slots = ListView.builder(
        // Built again at a new row height: a list keeps its physics while
        // only their numbers change.
        key: ValueKey(extent),
        controller: scroll,
        padding: EdgeInsets.zero,
        physics: _RowSnap(extent),
        itemExtent: extent,
        itemCount: rows,
        itemBuilder: (context, i) => Listener(
          // The whole row, its gaps and an empty part too.
          behavior: HitTestBehavior.opaque,
          onPointerSignal: wheel,
          child: Padding(
            padding: const EdgeInsets.only(bottom: _clipGap),
            child: motion == 0 || whole
                ? row(i)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        SizedBox(
                            height: motion - _motionClipGap,
                            child: motion - _motionClipGap >= _motionClipH
                                ? motionRow?.call(i) ?? const SizedBox()
                                // Minimised: the top of it, its colour.
                                : ClipRect(
                                    child: OverflowBox(
                                        alignment: Alignment.topCenter,
                                        minHeight: _motionClipH,
                                        maxHeight: _motionClipH,
                                        child: IgnorePointer(
                                            child: motionRow?.call(i) ??
                                                const SizedBox())))),
                        const SizedBox(height: _motionClipGap),
                        Expanded(child: row(i)),
                      ]),
          ),
        ),
      );
      // Squeezed past the stop's room: the slots alone, rather than a
      // stop button running out of the band.
      if (!stop || box.maxHeight < _slotGap + _stopH + 4) return slots;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: slots),
        const SizedBox(height: _slotGap),
        SizedBox(height: _stopH, child: foot),
      ]);
    });

/// _RowSnap is the slots' scrolling: let go, they rest on a whole row.
class _RowSnap extends ClampingScrollPhysics {
  final double extent;
  const _RowSnap(this.extent, {super.parent});

  @override
  _RowSnap applyTo(ScrollPhysics? ancestor) =>
      _RowSnap(extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // Not when moved along with another column: only the column let go
    // settles, and the rest follow it.
    if (extent <= 0 ||
        _ClipScrolls.following ||
        position.outOfRange ||
        position.maxScrollExtent <= position.minScrollExtent) {
      return super.createBallisticSimulation(position, velocity);
    }
    var target =
        ((position.pixels + velocity * 0.15) / extent).round() * extent;
    target = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    var tolerance = toleranceFor(position);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity,
        tolerance: tolerance);
  }
}

/// _ClipBand is a channel's clip slots, a row per scene, over its stop.
class _ClipBand extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final MixerLook theme;
  final ScrollController scroll;

  /// motion and motionRow are each row's motion part: see _clipColumn.
  final double motion;
  final Widget Function(int row)? motionRow;

  const _ClipBand({
    required this.controller,
    required this.channel,
    required this.theme,
    required this.scroll,
    this.motion = 0,
    this.motionRow,
  });

  @override
  Widget build(BuildContext context) {
    var stopping = controller.clipPlaying(channel);
    return _clipColumn(
      scroll,
      controller.slotsShown,
      (row) => _ClipSlot(
          key: ValueKey("clip-$channel-$row"),
          controller: controller,
          channel: channel,
          row: row,
          theme: theme),
      motion: motion,
      motionRow: motionRow,
      Tooltip(
        message: "Stop this channel's clips, on the next bar",
        child: Material(
          color: theme.studio.inset,
          borderRadius: BorderRadius.circular(3),
          child: InkWell(
            key: ValueKey("clipStop-$channel"),
            borderRadius: BorderRadius.circular(3),
            onTap: () => controller.stopChannelClips(channel),
            child: Center(
              child: Icon(Icons.stop,
                  size: 11,
                  color: stopping ? theme.studio.text : theme.studio.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// _ClipSlot is one slot: a clip (its colour, a play mark, its name) or an
/// empty slot, which stops the channel when pressed or records on an armed
/// MIDI channel. Right-click for its menu; double-click empty to make one.
class _ClipSlot extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final int row;
  final MixerLook theme;

  const _ClipSlot({
    required this.controller,
    required this.channel,
    required this.row,
    required this.theme,
    super.key,
  });

  @override
  State<_ClipSlot> createState() => _ClipSlotState();
}

class _ClipSlotState extends State<_ClipSlot> with _OnSessionPulse {
  @override
  Object? get _slotNow =>
      widget.controller.clipState(widget.channel, widget.row);

  @override
  bool get _pulses =>
      switch (widget.controller.clipState(widget.channel, widget.row)) {
        ClipState.queued ||
        ClipState.playing ||
        ClipState.stopping ||
        ClipState.recordQueued ||
        ClipState.recording =>
          true,
        _ => false,
      };

  /// _keys has the keyboard once the slot is clicked: see SlotKeys.
  final FocusNode _keys = FocusNode(debugLabel: "clipSlot");

  final MenuController _menu = MenuController();
  bool _renaming = false;
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();

  CanvasController get c => widget.controller;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    _keys.dispose();
    super.dispose();
  }

  void _rename(SessionClip clip) {
    _name.text = clip.name;
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        _name.selection =
            TextSelection(baseOffset: 0, extentOffset: _name.text.length);
      }
    });
  }

  void _renamed(SessionClip clip) {
    if (!_renaming) return;
    setState(() => _renaming = false);
    var name = _name.text.trim();
    if (name != clip.name) {
      c.setSessionClip(widget.channel, widget.row, clip.copyWith(name: name));
    }
  }

  void _set(SessionClip clip) =>
      c.setSessionClip(widget.channel, widget.row, clip);

  /// _duplicate copies the clip into the next empty slot down.
  void _duplicate(SessionClip clip) {
    var grid = c.session;
    var row = widget.row + 1;
    while (grid.at(widget.channel, row) != null) {
      row++;
    }
    if (row >= grid.rows) c.addClipScene();
    c.setSessionClip(widget.channel, row, clip.copyWith(id: newElementId()));
  }

  List<Widget> _clipMenu(SessionClip clip) {
    var studio = widget.theme.studio;
    Widget check(bool on) => Icon(on ? Icons.check : null, size: 14);
    // An element's own sound with a motion in the same row: linked, the
    // two launch together.
    var owner = soundOwnerOf(c.document, widget.channel);
    var link = owner != null && owner.base.motion.slot(widget.row) != null
        ? MenuItemButton(
            key: const ValueKey("clipSlotLink"),
            onPressed: () => c.linkMotionSlot(
                owner.id, widget.row, !owner.base.motion.isLinked(widget.row)),
            child: Text(owner.base.motion.isLinked(widget.row)
                ? "Unlink from its motion"
                : "Link with its motion"),
          )
        : null;
    return [
      if (link != null) link,
      if (clip.midi)
        MenuItemButton(
          key: const ValueKey("clipEditNotes"),
          leadingIcon: const Icon(Icons.piano, size: 14),
          onPressed: () => c.openPianoRoll(widget.channel, row: widget.row),
          child: const Text("Edit its notes"),
        ),
      SubmenuButton(
        menuChildren: [
          for (var m in LaunchMode.values)
            MenuItemButton(
              key: ValueKey("clipLaunch-${m.name}"),
              leadingIcon: check(clip.launch == m),
              onPressed: () => _set(clip.copyWith(launch: m)),
              child: Tooltip(message: m.hint, child: Text(m.label)),
            ),
        ],
        child: Text("Launch: ${clip.launch.label}"),
      ),
      MenuItemButton(
        key: const ValueKey("clipLoop"),
        leadingIcon: check(clip.loop),
        onPressed: () => _set(clip.copyWith(loop: !clip.loop)),
        child: const Text("Loop"),
      ),
      SubmenuButton(
        menuChildren: [
          for (var b in clipBarChoices)
            MenuItemButton(
              key: ValueKey("clipBars-$b"),
              leadingIcon: check(clip.bars == b),
              onPressed: () => _set(clip.copyWith(bars: b.toDouble())),
              child: Text(b == 1 ? "1 bar" : "$b bars"),
            ),
        ],
        child: Text("Length: ${_barsText(clip.bars)}"),
      ),
      SubmenuButton(
        menuChildren: [
          for (var (i, col) in sectionColors.indexed)
            MenuItemButton(
              key: ValueKey("clipColor-$i"),
              leadingIcon: Icon(Icons.circle, size: 14, color: Color(col)),
              trailingIcon: check(clip.color == i),
              onPressed: () => _set(clip.copyWith(color: i)),
              child: const SizedBox(width: 8),
            ),
        ],
        child: const Text("Colour"),
      ),
      MenuItemButton(
        key: const ValueKey("clipRename"),
        onPressed: () => _rename(clip),
        child: const Text("Rename"),
      ),
      MenuItemButton(
        key: const ValueKey("clipDuplicate"),
        onPressed: () => _duplicate(clip),
        child: const Text("Duplicate below"),
      ),
      MenuItemButton(
        key: const ValueKey("clipDelete"),
        leadingIcon: Icon(Icons.delete_outline, size: 14, color: studio.arm),
        onPressed: () => c.setSessionClip(widget.channel, widget.row, null),
        child: const Text("Delete"),
      ),
    ];
  }

  List<Widget> _emptyMenu() {
    if (c.instrumentChannel(widget.channel)) {
      return [
        MenuItemButton(
          key: const ValueKey("clipRecordHere"),
          leadingIcon: Icon(Icons.fiber_manual_record,
              size: 14, color: widget.theme.studio.arm),
          onPressed: () => c.recordClip(widget.channel, widget.row),
          child: const Text("Record into this slot"),
        ),
        MenuItemButton(
          key: const ValueKey("clipNewMidi"),
          leadingIcon: const Icon(Icons.piano, size: 14),
          onPressed: () {
            c.newMidiClip(widget.channel, widget.row);
            c.openPianoRoll(widget.channel, row: widget.row);
          },
          child: const Text("New MIDI clip, to draw notes into"),
        ),
        MenuItemButton(
          key: const ValueKey("clipFromPart"),
          onPressed: () =>
              c.newMidiClip(widget.channel, widget.row, fromPart: true),
          child: const Text("Copy the channel's part"),
        ),
      ];
    }
    var sounds = c.soundsOf(widget.channel);
    if (sounds.isEmpty) {
      return [
        const MenuItemButton(
          onPressed: null,
          child: Text("No sounds on this channel's timeline yet"),
        ),
      ];
    }
    return [
      for (var (i, s) in sounds.indexed)
        MenuItemButton(
          key: ValueKey("clipSound-$i"),
          leadingIcon: const Icon(Icons.graphic_eq, size: 14),
          onPressed: () => c.clipFromSound(widget.channel, widget.row, s),
          child: Text(s.name.isEmpty ? "Sound ${i + 1}" : s.name),
        ),
    ];
  }

  void _openMenu(Offset at) => _menu.open(position: at);

  /// _make puts a clip in this empty slot on a double-click, as the motion
  /// slots do: an empty one to draw notes into on a MIDI channel, else one of
  /// the channel's first sound (the menu has the rest). Picked, it takes
  /// Delete; double-clicked again, it opens. With no sound, the menu says so.
  void _make(Offset at) {
    if (!c.makeSessionClip(widget.channel, widget.row)) {
      _openMenu(at);
      return;
    }
    // Its name, which has the keys, is built on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keys.requestFocus();
    });
  }

  /// _menuAt is where a right-click (or a Mac's Control-click) went down, so
  /// its menu opens when it comes up: opened on the press, a menu still open
  /// from another slot, closing on the same press, could take it along.
  Offset? _menuAt;

  @override
  Widget build(BuildContext context) {
    var theme = widget.theme;
    var studio = theme.studio;
    var clip = c.session.at(widget.channel, widget.row);
    var state = c.clipState(widget.channel, widget.row);
    var armed =
        c.armed.contains(widget.channel) && c.instrumentChannel(widget.channel);
    Widget body;
    if (clip == null) {
      var recording = state == ClipState.recording ||
          (state == ClipState.recordQueued && _blinkOn);
      // Empty: the well (slot_face.dart), armed to record where it is.
      body = SlotFace(
        side: SlotSide.sound,
        empty: armed || recording
            ? Icon(Icons.fiber_manual_record,
                size: 9, color: recording ? studio.arm : studio.muted)
            : null,
      );
    } else {
      var col = Color(sectionColors[clip.color % sectionColors.length]);
      var lit = state == ClipState.playing ||
          state == ClipState.stopping ||
          (state == ClipState.queued && _blinkOn);
      var progress = c.clipProgress(widget.channel);
      var bars = clip.bars;
      body = SlotFace(
        side: SlotSide.sound,
        colour: col,
        playing: lit,
        seed: clip.id,
        midi: clip.midi,
        meta:
            "${bars == bars.roundToDouble() ? bars.round() : bars.toStringAsFixed(1)} "
            "bar${bars == 1 ? "" : "s"}${clip.loop ? " · loops" : ""}",
        progress: state == ClipState.queued ? null : progress,
        // Its launch button, as Ableton's: pressed, it plays (held, for a
        // gated clip). The rest of the slot is for picking it, opening it
        // and dragging it to another slot.
        go: Listener(
          key: ValueKey("clipLaunch-${widget.channel}-${widget.row}"),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_menuClick(e) || _renaming) return;
            c.pressClip(widget.channel, widget.row);
          },
          onPointerUp: (_) => c.releaseClip(widget.channel, widget.row),
          child: SizedBox.expand(
            child: Icon(Icons.play_arrow,
                size: 11, color: lit ? slotPlayingInk : slotInk),
          ),
        ),
        label: _renaming
            // Return or a click away keeps the name; Escape undoes it.
            ? CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      setState(() => _renaming = false),
                },
                child: TextField(
                  key: const ValueKey("clipNameField"),
                  controller: _name,
                  focusNode: _focus,
                  style: const TextStyle(fontSize: 10, color: slotInk),
                  decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none),
                  onSubmitted: (_) => _renamed(clip),
                  onTapOutside: (_) => _renamed(clip),
                ),
              )
            : _named(
                clip,
                Text(clip.name.isEmpty ? "Clip" : clip.name,
                    maxLines: 1, softWrap: false, overflow: TextOverflow.fade)),
      );
    }
    // A sound dragged from the assets (or, on a MIDI channel, a MIDI file) is
    // let go on a slot to be its clip; a clip from another slot is moved here,
    // or copied with Option (Alt) held.
    var midiChannel = c.instrumentChannel(widget.channel);
    var picked = c.selectedSlot == (widget.channel, widget.row);
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        SessionSlotDrag from => c.canMoveClip(from.clip, widget.channel) &&
            (from.channel, from.row) != (widget.channel, widget.row),
        var other => droppedKind(other) == AssetKind.audio &&
            (other is LibraryAsset && isMidiId(other.id)) == midiChannel,
      },
      onAcceptWithDetails: (d) async {
        if (d.data case SessionSlotDrag from) {
          c.moveClip(from.channel, from.row, widget.channel, widget.row,
              copy: HardwareKeyboard.instance.isAltPressed);
          return;
        }
        var asset = await droppedAsset(d.data);
        if (asset == null) return;
        if (isMidiId(asset.id)) {
          await c.midiClipFromFile(widget.channel, widget.row, asset.id,
              name: asset.name);
        } else {
          c.clipFromSound(widget.channel, widget.row, asset.source);
        }
      },
      builder: (context, over, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: over.isNotEmpty
              ? Border.all(color: widget.theme.studio.on, width: 2)
              : picked && clip != null
                  ? Border.all(color: widget.theme.studio.text, width: 1)
                  : null,
        ),
        child: _slotBody(clip, body),
      ),
    );
  }

  Widget _slotBody(SessionClip? clip, Widget body) {
    return MenuAnchor(
      controller: _menu,
      menuChildren: clip == null ? _emptyMenu() : _clipMenu(clip),
      child: Listener(
        onPointerDown: (e) {
          if (_menuClick(e)) {
            _menuAt = e.localPosition;
            return;
          }
          // An empty slot pressed stops its channel or, armed, records into it. A
          // clip is launched from its own button (keyed clipLaunch).
          if (_renaming || clip != null) return;
          c.pressClip(widget.channel, widget.row);
        },
        onPointerUp: (e) {
          if (_menuAt case var at?) {
            _menuAt = null;
            _openMenu(at);
            return;
          }
          if (clip == null) c.releaseClip(widget.channel, widget.row);
        },
        onPointerCancel: (_) => _menuAt = null,
        child: GestureDetector(
          onDoubleTapDown: clip == null ? (d) => _make(d.localPosition) : null,
          onDoubleTap: clip == null ? () {} : null,
          child: MouseRegion(cursor: SystemMouseCursors.click, child: body),
        ),
      ),
    );
  }

  /// _named is a clip's name in its slot: clicked, the clip picked (and shown
  /// in the clip editor, where that is open); double-clicked, the editor
  /// opened on it; dragged, the clip moved to another slot.
  Widget _named(SessionClip clip, Widget name) {
    var from = SessionSlotDrag(widget.channel, widget.row, clip);
    return Draggable<Object>(
      key: ValueKey("clipDrag-${widget.channel}-${widget.row}"),
      data: from,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Color(sectionColors[clip.color % sectionColors.length]),
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(clip.name.isEmpty ? "Clip" : clip.name,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0E0F12))),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: name),
      child: SlotKeys(
        focus: _keys,
        onDelete: () {
          c.beginInteraction();
          c.setSessionClip(widget.channel, widget.row, null);
          c.endInteraction();
        },
        child: GestureDetector(
          key: ValueKey("clipName-${widget.channel}-${widget.row}"),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            c.selectSlot(widget.channel, widget.row);
            _keys.requestFocus();
          },
          onDoubleTap: () => c.openClipEditor(widget.channel, widget.row),
          child: Align(alignment: Alignment.centerLeft, child: name),
        ),
      ),
    );
  }
}

/// _menuClick is whether [e] asks for a slot's menu: the right button, or
/// the left with Control held, as on a Mac.
bool _menuClick(PointerDownEvent e) =>
    e.buttons & kSecondaryMouseButton != 0 ||
    (e.buttons == kPrimaryMouseButton &&
        HardwareKeyboard.instance.isControlPressed);

String _barsText(double bars) {
  var whole = bars == bars.roundToDouble();
  var n = whole ? "${bars.round()}" : bars.toStringAsFixed(2);
  return bars == 1 ? "1 bar" : "$n bars";
}

/// _SceneBand is the master's clips band: a launch button for each scene,
/// beside the channels' rows, and Stop All and a new scene under them.
class _SceneBand extends StatelessWidget {
  final CanvasController controller;
  final MixerLook theme;
  final ScrollController scroll;

  /// motion is the rows' motion part: a cue's launch is the whole row.
  final double motion;

  final bool master;

  const _SceneBand({
    required this.controller,
    required this.theme,
    required this.scroll,
    this.motion = 0,
    this.master = false,
  });

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    return _clipColumn(
      scroll,
      controller.slotsShown,
      (row) => _SceneSlot(
          key: ValueKey(master ? "masterCue-$row" : "scene-$row"),
          controller: controller,
          row: row,
          master: master,
          theme: theme),
      motion: motion,
      whole: true,
      // Narrowed, Stop all alone, an arrow's width: a cue is added from a
      // cue's menu ("Add a cue below").
      LayoutBuilder(builder: (context, box) {
        var narrow = box.maxWidth < 50;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Tooltip(
              message: "Stop every channel's clips, on the next bar",
              child: Material(
                color: studio.inset,
                borderRadius: BorderRadius.circular(3),
                child: InkWell(
                  key: ValueKey(master ? "masterStopAll" : "clipStopAll"),
                  borderRadius: BorderRadius.circular(3),
                  onTap: controller.stopAllClips,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.stop, size: 11, color: studio.text),
                        if (!narrow)
                          Text(" Stop all",
                              style:
                                  TextStyle(fontSize: 9, color: studio.text)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!narrow) ...[
            const SizedBox(width: 3),
            Tooltip(
              message: "Add a cue: a row of clips to launch together",
              child: Material(
                color: studio.inset,
                borderRadius: BorderRadius.circular(3),
                child: InkWell(
                  key: ValueKey(master ? "addMasterCue" : "addClipScene"),
                  borderRadius: BorderRadius.circular(3),
                  onTap: () => controller.addClipScene(master: master),
                  child: SizedBox(
                      width: 20,
                      child: Icon(Icons.add, size: 12, color: studio.text)),
                ),
              ),
            ),
          ],
        ]);
      }),
    );
  }
}

/// _SceneSlot is a scene's launch button: the whole row from the next bar.
/// Right-clicked: rename it, add one under it, or take it away.
class _SceneSlot extends StatefulWidget {
  final CanvasController controller;
  final int row;
  final MixerLook theme;

  final bool master;
  const _SceneSlot(
      {required this.controller,
      required this.row,
      required this.theme,
      this.master = false,
      super.key});

  @override
  State<_SceneSlot> createState() => _SceneSlotState();
}

/// _cueGo is a cue's launch: a small square, green while its row plays.
Widget _cueGo(bool lit, StudioColors studio) => Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
          color: lit ? const Color(0xFF2E7D4F) : studio.raised,
          borderRadius: BorderRadius.circular(4)),
      child: Icon(Icons.play_arrow, size: 10, color: studio.text),
    );

class _SceneSlotState extends State<_SceneSlot> {
  /// _menuAt is where a right-click went down: see _ClipSlotState._menuAt.
  Offset? _menuAt;

  final MenuController _menu = MenuController();
  bool _renaming = false;
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();

  CanvasController get c => widget.controller;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _renamed() {
    if (!_renaming) return;
    setState(() => _renaming = false);
    c.renameClipScene(widget.row, _name.text, master: widget.master);
  }

  @override
  Widget build(BuildContext context) {
    var studio = widget.theme.studio;
    var master = widget.master;
    var lit = c.cueLaunched(master: master) == widget.row;
    var name = c.cueName(widget.row, master: master);
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(
          key: const ValueKey("sceneRename"),
          onPressed: () {
            var names = c.cueNames(master: master);
            _name.text = widget.row < names.length ? names[widget.row] : "";
            setState(() => _renaming = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focus.requestFocus();
            });
          },
          child: const Text("Rename"),
        ),
        MenuItemButton(
          key: const ValueKey("sceneInsert"),
          onPressed: () => c.addClipScene(after: widget.row, master: master),
          child: const Text("Add a cue below"),
        ),
        MenuItemButton(
          key: const ValueKey("sceneDelete"),
          onPressed: c.cueNames(master: master).length > 1
              ? () => c.removeClipScene(widget.row, master: master)
              : null,
          child: const Text("Delete, with its clips"),
        ),
      ],
      child: Tooltip(
        message: "Cue $name: launch every channel's and element's clip in "
            "this row together, from the next bar. Right-click to rename it.",
        waitDuration: const Duration(milliseconds: 600),
        child: Listener(
          onPointerDown: (e) {
            if (_menuClick(e)) {
              _menuAt = e.localPosition;
              return;
            }
            if (!_renaming) c.launchCue(widget.row, master: master);
          },
          onPointerUp: (e) {
            if (_menuAt case var at?) {
              _menuAt = null;
              _menu.open(position: at);
            }
          },
          onPointerCancel: (_) => _menuAt = null,
          child: Container(
            decoration: BoxDecoration(
              color: studio.strip,
              borderRadius: BorderRadius.circular(3),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: LayoutBuilder(
                builder: (context, box) => box.maxWidth < 30 && !_renaming
                    ? Center(child: _cueGo(lit, studio))
                    : Row(children: [
                        _cueGo(lit, studio),
                        const SizedBox(width: 5),
                        Expanded(
                          child: _renaming
                              ? TextField(
                                  key: const ValueKey("sceneNameField"),
                                  controller: _name,
                                  focusNode: _focus,
                                  style: const TextStyle(fontSize: 10),
                                  decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      border: InputBorder.none),
                                  onSubmitted: (_) => _renamed(),
                                  onTapOutside: (_) => _renamed(),
                                )
                              : Text(name,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.fade,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: studio.text)),
                        ),
                      ])),
          ),
        ),
      ),
    );
  }
}
