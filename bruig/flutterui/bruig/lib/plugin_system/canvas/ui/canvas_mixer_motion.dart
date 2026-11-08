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
              (row) => _MotionSlot(
                  key: ValueKey("motionSlot-${e.id}-$row"),
                  controller: controller,
                  element: e.id,
                  row: row,
                  theme: theme),
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
            devices: () => _ElementSoundBand(
                controller: controller, element: e, theme: theme),
            mixer: () => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var layer = 0; layer < motionLayers; layer++) ...[
                  if (layer > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _LayerFader(
                      key: ValueKey("layerFader-${e.id}-$layer"),
                      label: "L${layer + 1}",
                      short: narrow,
                      value: e.base.motion.weight(layer),
                      theme: theme,
                      onChanged: (v) {
                        controller.beginInteraction();
                        controller.weighLayer(e.id, layer, v, transient: true);
                      },
                      onCommit: controller.endInteraction,
                    ),
                  ),
                ],
              ],
            ),
            miniMixer: () => Row(children: [
              for (var layer = 0; layer < motionLayers; layer++) ...[
                if (layer > 0) const SizedBox(width: 3),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: e.base.motion.weight(layer),
                      minHeight: 6,
                      color: theme.studio.on,
                      backgroundColor: theme.studio.inset,
                    ),
                  ),
                ),
              ],
            ]),
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

/// _LayerFader is how much a layer counts, nought to all of it: dragged up
/// and down; double-clicked, all of it again.
class _LayerFader extends StatelessWidget {
  final String label;

  /// short is its name alone under it, in a narrow strip: no room for how
  /// much the layer counts as well.
  final bool short;
  final double value;
  final MixerLook theme;
  final ValueChanged<double> onChanged;
  final VoidCallback onCommit;

  const _LayerFader({
    required this.label,
    required this.value,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    this.short = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          void at(double y) =>
              onChanged((1 - y / math.max(1, box.maxHeight)).clamp(0.0, 1.0));
          return GestureDetector(
            supportedDevices: dragPointers,
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (d) => at(d.localPosition.dy),
            onVerticalDragUpdate: (d) => at(d.localPosition.dy),
            onVerticalDragEnd: (_) => onCommit(),
            onTapUp: (d) {
              at(d.localPosition.dy);
              onCommit();
            },
            onDoubleTap: () {
              onChanged(1);
              onCommit();
            },
            child: CustomPaint(
              painter: _LayerFaderPainter(value, studio),
            ),
          );
        }),
      ),
      const SizedBox(height: 3),
      Text(short ? label : "$label ${(value * 100).round()}",
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(fontSize: 9, color: studio.muted)),
    ]);
  }
}

class _LayerFaderPainter extends CustomPainter {
  final double value;
  final StudioColors studio;
  _LayerFaderPainter(this.value, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var track =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3));
    canvas.drawRRect(track, Paint()..color = studio.inset);
    var top = size.height * (1 - value);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(0, top, size.width, size.height),
            const Radius.circular(3)),
        Paint()..color = studio.on.withValues(alpha: 0.75));
    canvas.drawRect(
        Rect.fromLTWH(0, top - 1, size.width, 2), Paint()..color = studio.text);
  }

  @override
  bool shouldRepaint(_LayerFaderPainter old) =>
      old.value != value || old.studio != studio;
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
    if (clip.isSound && c.effectsOpen) c.effectsOpen = true;
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
      body = Container(
        decoration: BoxDecoration(
          color: studio.inset,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: studio.edge),
        ),
        child: Center(
          child: Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(border: Border.all(color: studio.edge, width: 1)),
          ),
        ),
      );
    } else {
      var col = motionKindColours[clip.kind]!;
      var lit = state == MotionSlotState.playing ||
          state == MotionSlotState.stopping ||
          (state == MotionSlotState.queued && _blinkOn);
      var ink = lit ? const Color(0xFF0E0F12) : studio.text;
      var name = Text(clip.name.isEmpty ? "Clip" : clip.name,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style:
              TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ink));
      body = Container(
        decoration: BoxDecoration(
          color: lit ? col : col.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(3),
        ),
        padding: const EdgeInsets.only(right: 4),
        child: Row(children: [
          Listener(
            key: ValueKey("motionLaunch-${widget.element}-${widget.row}"),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (_menuClick(e)) return;
              c.pressMotionSlot(widget.element, widget.row);
            },
            onPointerUp: (_) => c.releaseMotionClip(widget.element, clip.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(3, 0, 2, 0),
              child: Icon(Icons.play_arrow, size: 12, color: ink),
            ),
          ),
          Expanded(
            child: Draggable<Object>(
              key: ValueKey("motionDrag-${widget.element}-${widget.row}"),
              data: MotionSlotDrag(widget.element, widget.row, clip.id),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: Material(
                color: col,
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ),
          if (clip.isSound) Icon(Icons.music_note, size: 10, color: ink),
        ]),
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
