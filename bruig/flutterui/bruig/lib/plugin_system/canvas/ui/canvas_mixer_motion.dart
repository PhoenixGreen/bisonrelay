part of 'canvas_mixer.dart';

// canvas_mixer_motion.dart is an element's strip in the mixer, beside the
// sound channels': its animation slots, one per cue row as theirs are, and
// its layers' faders.
//
// A slot's triangle launches it; its name picks it into the Animation
// panel; dragged, it goes to another slot (this element's: moved; another's:
// copied) or onto the timeline. An empty slot pressed stops the element's
// clips; double-clicked, it offers a ready-made motion.

/// motionStripKey is [id]'s strip's key among the narrow ones (see
/// CanvasController.narrowStrips): not a channel's.
String motionStripKey(String id) => "motion:$id";

/// _elementStrip is [e]'s strip: narrow, as a channel's can be, with its
/// faders named by layer alone.
Widget _elementStrip(CanvasController controller, MixerLook theme,
    CanvasElement e, _Bands bands, ScrollController scroll) {
  var key = motionStripKey(e.id);
  var narrow = controller.narrowStrips.contains(key);
  // Pressed anywhere, as a channel's strip is: the element picked, and no
  // channel with it but its own sound's, the two being one thing.
  void pick() {
    if (!(controller.selection.length == 1 &&
        controller.selection.first == e.id)) {
      controller.selectOnly(e.id);
    }
    var own = "snd-${e.id}";
    controller.selectedChannel =
        controller.timelineChannels.any((l) => l.key == own) ? own : null;
  }

  return KeyedSubtree(
      key: ValueKey("motionStrip-${e.id}"),
      child: Listener(
          onPointerDown: (_) => pick(),
          child: _StripFrame(
            badges: stripBadges(theme, key, element: e),
            rowColour: controller.rowColour(e.id),
            narrow: narrow,
            onNarrow: () => controller.toggleNarrow(key),
            narrowKey: ValueKey("narrow-$key"),
            selected: controller.selection.contains(e.id),
            theme: theme,
            bands: bands,
            head: GestureDetector(
              key: ValueKey("motionStripName-${e.id}"),
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.selectOnly(e.id),
              child: Row(children: [
                Icon(Icons.animation, size: 11, color: theme.studio.muted),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(e.name.isEmpty ? e.id : e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.studio.text)),
                ),
              ]),
            ),
            clips: () => _clipColumn(
              scroll,
              controller.slotsShown,
              motion: bands.motionClip,
              motionRow: (row) => _MotionSlot(
                  key: ValueKey("motionSlot-${e.id}-$row"),
                  controller: controller,
                  element: e.id,
                  row: row,
                  theme: theme),
              // No sound of its own: nothing under its motion part.
              (row) => const SizedBox(),
              Tooltip(
                message: "Stop this element's clips, on the next bar",
                child: Material(
                  color: theme.studio.inset,
                  borderRadius: BorderRadius.circular(3),
                  child: InkWell(
                    key: ValueKey("motionStop-${e.id}"),
                    borderRadius: BorderRadius.circular(3),
                    onTap: () => controller.stopMotion(e.id),
                    child: Center(
                      child: Icon(Icons.stop,
                          size: 11,
                          color: controller.motionPlayer.isOff(e.id)
                              ? theme.studio.text
                              : theme.studio.muted),
                    ),
                  ),
                ),
              ),
            ),
            deviceCount: _motionDeviceSlots(controller, theme, e).length,
            devices: () => _band([
              ..._slots(_motionDeviceSlots(controller, theme, e)),
              if (e.base.motion.devices.isNotEmpty ||
                  e.base.motion.instances != null)
                const SizedBox(height: _slotGap),
              _ElementSoundBand(
                  controller: controller, element: e, theme: theme),
            ]),
            motion: () => _MotionHalf(
                controller: controller,
                element: e,
                narrow: narrow,
                theme: theme),
            mixer: () => _Well("No sound", theme),
            motionLine: () => _MotionLine(
                controller: controller,
                element: e,
                narrow: narrow,
                theme: theme),
            miniMixer: () => _MiniNote("no sound", theme,
                faint: true, key: ValueKey("noSound-${e.id}")),
          )));
}

/// _ElementSoundBand is an element's sound in its strip's devices band: a
/// channel of its own to give it, or, with one, where that goes (the master,
/// or a return shared with others as a group bus).
class _ElementSoundBand extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MixerLook theme;

  const _ElementSoundBand(
      {required this.controller, required this.element, required this.theme});

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    var small = TextStyle(fontSize: 10, color: studio.muted);
    var id = element.id;
    if (controller.soundChannelOf(id) == null) {
      return Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: studio.inset,
          borderRadius: BorderRadius.circular(3),
          child: InkWell(
            key: ValueKey("elementSoundAdd-$id"),
            borderRadius: BorderRadius.circular(3),
            onTap: () => controller.ensureElementSound(id),
            child: SizedBox(
              height: _slotH,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.music_note, size: 11, color: studio.text),
                    Text(" Give it a sound",
                        style: TextStyle(fontSize: 10, color: studio.text)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }
    var output = controller.soundOutputOf(id);
    var returns = controller.document.returns;
    var to = returns.where((r) => r.id == output).firstOrNull;
    var menu = MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: ValueKey("elementSoundOut-$id-master"),
          onPressed: () => controller.setSoundOutput(id, ""),
          child: const Text("The master, on its own"),
        ),
        for (var r in returns)
          MenuItemButton(
            key: ValueKey("elementSoundOut-$id-${r.id}"),
            onPressed: () => controller.setSoundOutput(id, r.id),
            child: Text("${r.name}, shared"),
          ),
      ],
      builder: (context, menu, _) => Material(
        color: studio.inset,
        borderRadius: BorderRadius.circular(3),
        child: InkWell(
          key: ValueKey("elementSoundOut-$id"),
          borderRadius: BorderRadius.circular(3),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: SizedBox(
            height: _slotH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                Expanded(
                  child: Text(to?.name ?? "Master",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: studio.text)),
                ),
                Icon(Icons.arrow_drop_down, size: 12, color: studio.muted),
              ]),
            ),
          ),
        ),
      ),
    );
    // The label only where there is room for it over the menu: a band
    // squeezed short keeps the menu.
    return LayoutBuilder(builder: (context, box) {
      var label = Text("Sound goes to", style: small, maxLines: 1);
      var labelled = box.maxHeight >=
          _slotH + 4 + MediaQuery.textScalerOf(context).scale(14);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (labelled) ...[label, const SizedBox(height: 2)],
        menu,
      ]);
    });
  }
}

/// _MotionSlot is one of an element's slots: a clip, coloured by what it is
/// for, or empty.
class _MotionSlot extends StatefulWidget {
  final CanvasController controller;
  final String element;
  final int row;
  final MixerLook theme;

  const _MotionSlot({
    required this.controller,
    required this.element,
    required this.row,
    required this.theme,
    super.key,
  });

  @override
  State<_MotionSlot> createState() => _MotionSlotState();
}

class _MotionSlotState extends State<_MotionSlot> with _OnSessionPulse {
  @override
  Object? get _slotNow =>
      widget.controller.motionSlotState(widget.element, widget.row);

  @override
  bool get _pulses =>
      switch (widget.controller.motionSlotState(widget.element, widget.row)) {
        MotionSlotState.queued ||
        MotionSlotState.playing ||
        MotionSlotState.stopping =>
          true,
        _ => false,
      };

  final MenuController _menu = MenuController();
  Offset? _menuAt;

  CanvasController get c => widget.controller;

  /// _pick picks [clip]: shown in the Chain where it is open, without
  /// opening it (Ken: a single click doesn't open the Chain).
  void _pick(MotionClip clip) {
    c.pickMotion(widget.element, clip.id);
    _keys.requestFocus();
  }

  /// _open opens [clip] in the Chain: a double-click, or its menu's Open.
  void _open(MotionClip clip) {
    c.pickMotion(widget.element, clip.id);
    c.animationOpen = true;
  }

  /// _keys has the keyboard once the slot is clicked: see SlotKeys.
  final FocusNode _keys = FocusNode(debugLabel: "motionSlot");

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  void _make(MotionPreset? preset, {bool open = true}) {
    var id = c.newClip(widget.element,
        preset: preset,
        kind: _camera ? MotionKind.camera : MotionKind.action,
        slot: widget.row,
        target: preset != null && preset.aims ? _target() : "");
    c.pickMotion(widget.element, id);
    if (open) c.animationOpen = true;
  }

  String _target() =>
      c.document.elements
          .where((e) => e.id != widget.element)
          .map((e) => e.id)
          .firstOrNull ??
      "";

  bool get _camera => c.document.elementById(widget.element) is CameraElement;

  List<Widget> _emptyMenu() => [
        for (var kind in _camera
            ? const [MotionKind.camera]
            : const [
                MotionKind.arrive,
                MotionKind.loop,
                MotionKind.leave,
                MotionKind.action
              ])
          SubmenuButton(
            menuChildren: [
              for (var p in presetsFor(kind))
                MenuItemButton(
                  key: ValueKey("slotMotion-${p.name}"),
                  onPressed: () => _make(p),
                  child: Text(p.name),
                ),
            ],
            child: Text(kind.label),
          ),
        MenuItemButton(
          key: const ValueKey("slotMotion-empty"),
          onPressed: () => _make(null),
          child: const Text("An empty clip, to key by hand"),
        ),
      ];

  List<Widget> _clipMenu(MotionClip clip) => [
        MenuItemButton(
          key: const ValueKey("motionSlotOpen"),
          onPressed: () => _open(clip),
          child: const Text("Open in Animation"),
        ),
        MenuItemButton(
          key: const ValueKey("motionSlotDuplicate"),
          onPressed: () {
            var m = c.motionOf(widget.element);
            var to = widget.row + 1;
            while (m.slot(to) != null) {
              to++;
            }
            if (to >= c.session.rows) c.addClipScene();
            c.moveMotionSlot(widget.element, widget.row, widget.element, to,
                copy: true);
          },
          child: const Text("Duplicate"),
        ),
        MenuItemButton(
          key: const ValueKey("motionSlotClear"),
          onPressed: () => c.clearMotionSlot(widget.element, widget.row),
          child: const Text("Take it out of the slot"),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    var studio = widget.theme.studio;
    var m = c.motionOf(widget.element);
    var clip = m.slot(widget.row);
    var state = c.motionSlotState(widget.element, widget.row);
    Widget body;
    if (clip == null) {
      // Empty: the well (slot_face.dart).
      body = const SlotFace(side: SlotSide.motion);
    } else {
      // In its row's colour (Ken, 2026-11-10).
      var col = c.rowColour(widget.element);
      var lit = state == MotionSlotState.playing ||
          state == MotionSlotState.stopping ||
          (state == MotionSlotState.queued && _blinkOn);
      var name = Text(clip.name.isEmpty ? "Clip" : clip.name,
          maxLines: 1, softWrap: false, overflow: TextOverflow.fade);
      var secs = clip.length;
      body = SlotFace(
        side: SlotSide.motion,
        colour: col,
        playing: lit,
        seed: clip.id,
        meta:
            "${secs == secs.roundToDouble() ? secs.round() : secs.toStringAsFixed(1)} s"
            "${clip.loop ? " · loops" : ""}",
        go: Listener(
          key: ValueKey("motionLaunch-${widget.element}-${widget.row}"),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_menuClick(e)) return;
            c.pressMotionSlot(widget.element, widget.row);
          },
          onPointerUp: (_) => c.releaseMotionClip(widget.element, clip.id),
          child: SizedBox.expand(
            child: Icon(Icons.play_arrow,
                size: 11, color: lit ? slotPlayingInk : slotInk),
          ),
        ),
        label: Draggable<Object>(
          key: ValueKey("motionDrag-${widget.element}-${widget.row}"),
          data: MotionSlotDrag(widget.element, widget.row, clip.id),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            color: col,
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
            onDelete: () => c.clearMotionSlot(widget.element, widget.row),
            child: GestureDetector(
              key: ValueKey("motionName-${widget.element}-${widget.row}"),
              behavior: HitTestBehavior.opaque,
              onTap: () => _pick(clip),
              onDoubleTap: () => _open(clip),
              child: Align(alignment: Alignment.centerLeft, child: name),
            ),
          ),
        ),
      );
    }
    var picked = clip != null && c.pickedMotion == clip.id;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        MotionSlotDrag from =>
          (from.element, from.slot) != (widget.element, widget.row),
        _ => false,
      },
      onAcceptWithDetails: (d) {
        if (d.data case MotionSlotDrag from) {
          c.moveMotionSlot(from.element, from.slot, widget.element, widget.row,
              copy: HardwareKeyboard.instance.isAltPressed);
        }
      },
      builder: (context, over, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: over.isNotEmpty
              ? Border.all(color: studio.on, width: 2)
              : picked
                  ? Border.all(color: studio.text, width: 1)
                  : null,
        ),
        child: MenuAnchor(
          controller: _menu,
          menuChildren: clip == null ? _emptyMenu() : _clipMenu(clip),
          child: Listener(
            onPointerDown: (e) {
              if (_menuClick(e)) {
                _menuAt = e.localPosition;
                return;
              }
              if (clip == null) c.pressMotionSlot(widget.element, widget.row);
            },
            onPointerUp: (e) {
              if (_menuAt case var at?) {
                _menuAt = null;
                _menu.open(position: at);
              }
            },
            onPointerCancel: (_) => _menuAt = null,
            child: GestureDetector(
              // Empty, double-clicked: a new clip in it at once, picked --
              // double-clicked again, set up in the Chain (Ken).
              onDoubleTap: clip == null ? () => _make(null, open: false) : null,
              child: MouseRegion(cursor: SystemMouseCursors.click, child: body),
            ),
          ),
        ),
      ),
    );
  }
}

/// motionHalfHeight is the motion half's on every strip, wide or narrow, so
/// the sound halves under them start on one line (the approved design).
const motionHalfHeight = 78.0;

/// _MotionHalf is an element strip's motion: MOTION and how much of it is
/// seen; a bar for how much of each layer plays, striped when pinned; the
/// layer cross-fader, blending the free layers (Shift snaps to one); and a
/// chip for each layer, pressed to pin it -- in place of three sliders
/// (Ken, 2026-11-08: "the cross-fader with pins is enough").
class _MotionHalf extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final bool narrow;
  final MixerLook theme;
  const _MotionHalf(
      {required this.controller,
      required this.element,
      required this.narrow,
      required this.theme});

  @override
  Widget build(BuildContext context) {
    var id = element.id;
    var m = element.base.motion;
    var used = m.layersInUse;
    var studio = theme.studio;
    var label = TextStyle(
        fontSize: 9,
        letterSpacing: narrow ? 0 : 0.6,
        fontWeight: FontWeight.w600,
        color: studio.muted);
    return SizedBox(
      key: ValueKey("motionHalf-$id"),
      height: motionHalfHeight,
      child: Opacity(
        opacity: m.off ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 14,
              child: Row(children: [
                // The label gives way first: the amount is the number.
                Flexible(
                  child: Text(narrow ? "MOT" : "MOTION",
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: label),
                ),
                if (!narrow) ...[
                  const SizedBox(width: 3),
                  const HelpNote(
                    id: "crossFader",
                    size: 12,
                    title: "Layer cross-fader",
                    paragraphs: [
                      "Slide it to blend from one layer to the next. "
                          "Half way between two layers plays half of each. "
                          "Hold Shift to land on a layer.",
                      "Press a layer's name to pin it: a pinned layer "
                          "always plays in full, and the fader blends the "
                          "others.",
                      "The bars show how much of each layer plays. The "
                          "number is how much of the motion is seen: drag "
                          "it up or down.",
                    ],
                  ),
                ],
                const SizedBox(width: 2),
                // Smaller rather than cut, on a narrow strip at a large
                // text size.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _MotionAmount(
                          controller: controller,
                          element: element,
                          theme: theme),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 3),
            if (used.isEmpty)
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: studio.inset,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text("No clips yet",
                      maxLines: 1,
                      style: TextStyle(fontSize: 9.5, color: studio.muted)),
                ),
              )
            else ...[
              SizedBox(
                height: 16,
                child: Row(children: [
                  for (var (i, l) in used.indexed) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: _WeightBar(
                          key: ValueKey("layerBar-$id-$l"),
                          weight: m.layerWeight(l),
                          pinned: m.isPinned(l),
                          theme: theme),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 4),
              _CrossFader(
                  key: ValueKey("crossFader-$id"),
                  controller: controller,
                  element: element,
                  height: 14,
                  theme: theme),
              const SizedBox(height: 4),
              SizedBox(
                height: 16,
                child: Row(children: [
                  for (var (i, l) in used.indexed) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: _LayerChip(
                        key: ValueKey("layerPin-$id-$l"),
                        name: narrow
                            ? motionLayerName(m, l)
                                .characters
                                .take(2)
                                .toString()
                            : motionLayerName(m, l),
                        pinned: m.isPinned(l),
                        theme: theme,
                        onTap: () => controller.pinLayer(id, l, !m.isPinned(l)),
                      ),
                    ),
                  ],
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// _MotionLine is the motion half on a minimised mixer: the motion switch,
/// a thin cross-fader and how much is seen, on one line.
class _MotionLine extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final bool narrow;
  final MixerLook theme;
  const _MotionLine(
      {required this.controller,
      required this.element,
      required this.narrow,
      required this.theme});

  @override
  Widget build(BuildContext context) {
    var m = element.base.motion;
    var studio = theme.studio;
    return SizedBox(
      key: ValueKey("motionLine-${element.id}"),
      height: 16,
      child: Row(children: [
        InkWell(
          key: ValueKey("motionSwitch-${element.id}"),
          onTap: () => controller.switchMotion(element.id, m.off),
          child: SizedBox(
            width: 16,
            child: Icon(Icons.diamond,
                size: 10, color: m.off ? studio.muted : motionColour),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: _CrossFader(
              key: ValueKey("crossFaderLine-${element.id}"),
              controller: controller,
              element: element,
              height: 8,
              theme: theme),
        ),
        if (!narrow) ...[
          const SizedBox(width: 4),
          _MotionAmount(controller: controller, element: element, theme: theme),
        ],
      ]),
    );
  }
}

/// _MotionAmount is how much of the element's motion is seen, as a
/// percentage dragged up or down; double-clicked, all of it.
class _MotionAmount extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MixerLook theme;
  const _MotionAmount(
      {required this.controller, required this.element, required this.theme});

  @override
  Widget build(BuildContext context) {
    var amount = element.base.motion.amount;
    return GestureDetector(
      key: ValueKey("motionAmount-${element.id}"),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => controller.beginInteraction(),
      onVerticalDragUpdate: (d) => controller.setMotionAmount(
          element.id, controller.motionOf(element.id).amount - d.delta.dy / 150,
          transient: true),
      onVerticalDragEnd: (_) => controller.endInteraction(),
      onDoubleTap: () => controller.setMotionAmount(element.id, 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Text("${(amount * 100).round()}%",
            maxLines: 1,
            style: TextStyle(
                fontSize: 9.5,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.studio.text)),
      ),
    );
  }
}

/// _CrossFader is the layer cross-fader's track: a tick for each free layer
/// and the thumb where it stands. Pressed or dragged, it moves there; Shift
/// snaps it to a layer. With fewer than two free layers there is nothing to
/// blend, and it is dimmed.
class _CrossFader extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final double height;
  final MixerLook theme;
  const _CrossFader(
      {super.key,
      required this.controller,
      required this.element,
      required this.height,
      required this.theme});

  @override
  Widget build(BuildContext context) {
    var m = element.base.motion;
    var free = m.freeLayers.length;
    var track = CustomPaint(
      size: Size.fromHeight(height),
      painter: _CrossFaderPainter(
          fade: m.fade,
          ticks: free,
          live: free > 1,
          // Hollow until the fader sets the layers' weights: a new element
          // plays every layer in full, which is no place on the fader.
          set: listEquals(m.weights, crossFade(m.layersInUse, m.pins, m.fade)),
          theme: theme),
    );
    if (free < 2) return Opacity(opacity: 0.35, child: track);
    double at(double x, double width) {
      var f = ((x - 6) / math.max(1, width - 12)).clamp(0.0, 1.0);
      if (HardwareKeyboard.instance.isShiftPressed) {
        f = (f * (free - 1)).roundToDouble() / (free - 1);
      }
      return f;
    }

    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          controller.beginInteraction();
          controller.fadeLayers(
              element.id, at(d.localPosition.dx, box.maxWidth),
              transient: true);
        },
        onHorizontalDragUpdate: (d) => controller.fadeLayers(
            element.id, at(d.localPosition.dx, box.maxWidth),
            transient: true),
        onHorizontalDragEnd: (_) => controller.endInteraction(),
        onTapUp: (d) => controller.fadeLayers(
            element.id, at(d.localPosition.dx, box.maxWidth)),
        child: MouseRegion(cursor: SystemMouseCursors.click, child: track),
      ),
    );
  }
}

class _CrossFaderPainter extends CustomPainter {
  final double fade;
  final int ticks;
  final bool live;
  final bool set;
  final MixerLook theme;
  _CrossFaderPainter(
      {required this.fade,
      required this.ticks,
      required this.live,
      required this.set,
      required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    var studio = theme.studio;
    var mid = size.height / 2;
    var groove = RRect.fromRectAndRadius(
        Rect.fromLTRB(0, mid - 2, size.width, mid + 2),
        const Radius.circular(2));
    canvas.drawRRect(groove, Paint()..color = studio.inset);
    var span = size.width - 12;
    if (ticks > 1) {
      var tick = Paint()
        ..color = studio.muted
        ..strokeWidth = 1;
      for (var k = 0; k < ticks; k++) {
        var x = 6 + span * k / (ticks - 1);
        canvas.drawLine(Offset(x, mid - size.height * 0.35),
            Offset(x, mid + size.height * 0.35), tick);
      }
    }
    if (!live) return;
    var x = 6 + span * fade;
    var thumb = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(x, mid), width: 8, height: size.height - 2),
        const Radius.circular(2));
    canvas.drawRRect(
        thumb,
        set
            ? (Paint()..color = motionColour)
            : (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = motionColour));
  }

  @override
  bool shouldRepaint(_CrossFaderPainter old) =>
      old.fade != fade ||
      old.ticks != ticks ||
      old.live != live ||
      old.set != set;
}

/// _WeightBar is how much of one layer plays, filling from the bottom;
/// striped when the layer is pinned.
class _WeightBar extends StatelessWidget {
  final double weight;
  final bool pinned;
  final MixerLook theme;
  const _WeightBar(
      {super.key,
      required this.weight,
      required this.pinned,
      required this.theme});

  @override
  Widget build(BuildContext context) => SizedBox.expand(
      child: CustomPaint(
          painter: _WeightBarPainter(weight, pinned, theme.studio.inset)));
}

class _WeightBarPainter extends CustomPainter {
  final double weight;
  final bool pinned;
  final Color well;
  _WeightBarPainter(this.weight, this.pinned, this.well);

  @override
  void paint(Canvas canvas, Size size) {
    var r = const Radius.circular(2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = well);
    var h = size.height * weight.clamp(0.0, 1.0);
    if (h <= 0) return;
    var fill = Rect.fromLTRB(0, size.height - h, size.width, size.height);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(fill, r));
    canvas.drawRect(fill, Paint()..color = motionColour);
    if (pinned) {
      var stripe = Paint()
        ..color = const Color(0xFF2D8A6D)
        ..strokeWidth = 3;
      for (var x = -size.height; x < size.width; x += 6) {
        canvas.drawLine(
            Offset(x, size.height), Offset(x + size.height, 0), stripe);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WeightBarPainter old) =>
      old.weight != weight || old.pinned != pinned || old.well != well;
}

/// _LayerChip is a layer's name under the cross-fader: pressed, it pins
/// the layer, or unpins it.
class _LayerChip extends StatelessWidget {
  final String name;
  final bool pinned;
  final MixerLook theme;
  final VoidCallback onTap;
  const _LayerChip(
      {super.key,
      required this.name,
      required this.pinned,
      required this.theme,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    return Material(
      color: pinned ? motionColour.withValues(alpha: 0.22) : studio.inset,
      shape: RoundedRectangleBorder(
          side: BorderSide(color: pinned ? motionColour : studio.edge),
          borderRadius: BorderRadius.circular(4)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Center(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                  fontSize: 9, color: pinned ? studio.text : studio.muted)),
        ),
      ),
    );
  }
}
