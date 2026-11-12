import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/glb_info.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';
import 'package:bruig/plugin_system/canvas/ui/track_curves.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/keys_strip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/copies_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_clips_card.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_curves.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/own_style.dart';
import 'package:bruig/plugin_system/canvas/ui/parts_card.dart';
import 'package:bruig/plugin_system/canvas/ui/scene_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// animation_panel.dart is the Animation panel: the picked clip, laid out as
// the effects are, a row of devices side by side, each folding to its
// title. Clip; Motion, the ready-made motions; Keys, as wide as the room
// allows and dragged wider; Inside, what only this kind of element does;
// Timing, where it is placed and pinned; Place; and Launch.
//
// Every change goes through motion_editing.dart, so it is one undo step: a
// slider dragged is one step for the whole drag.

/// AnimationPanel is the panel, [height] tall.
class AnimationPanel extends StatefulWidget {
  final CanvasController controller;
  final double height;

  /// onResize is the panel's top edge dragged: the height asked for.
  final ValueChanged<double>? onResize;

  const AnimationPanel(
      {required this.controller,
      required this.height,
      this.onResize,
      super.key});

  /// cardsLeast is the least room the cards keep under the Keys strip: a
  /// card's header and a row of its settings. A panel too short for both
  /// shows the strip alone (Ken, 2026-11-12: a short panel squeezed the
  /// cards below their headers).
  static const cardsLeast = 150.0;

  @override
  State<AnimationPanel> createState() => _AnimationPanelState();
}

class _AnimationPanelState extends State<AnimationPanel> {
  CanvasController get controller => widget.controller;

  /// _folded are the devices folded to their titles, by id. For the session.
  static final Set<String> _folded = {};

  /// _focusKeys find a card the settings panel asks to be shown: see
  /// CanvasController.showInChain.
  final Map<String, GlobalKey> _focusKeys = {};
  GlobalKey _focusKey(String id) => _focusKeys.putIfAbsent(id, GlobalKey.new);

  /// _showFocus opens the card the settings panel asked for, and brings it
  /// into view once it is drawn.
  void _showFocus() {
    var focus = controller.chainFocus;
    if (focus == null) return;
    _folded.removeWhere((k) =>
        (k.startsWith("mdev:") && k.endsWith(":$focus")) ||
        (focus == "clips" && k.startsWith("motionClips:")));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var at = _focusKeys[focus]?.currentContext;
      if (at != null) {
        Scrollable.ensureVisible(at,
            alignment: 0.5, duration: const Duration(milliseconds: 250));
      }
      controller.chainFocused();
    });
  }

  String? _was;

  /// _strip is how tall the Keys strip over the cards is, while it is open;
  /// the cards have the rest (see _room).
  double _strip = 0;

  double get _room => widget.height - _strip;

  /// _withKeys is [cards] under the Keys strip of [e], where it is open
  /// (Ken, 2026-11-12: "opens above" the cards, as Curves opens instead).
  Widget _withKeys(CanvasElement e, Widget cards) {
    if (!controller.keysShown) return cards;
    var strip = KeysStrip(
        key: ValueKey("keysStrip-${e.id}"),
        controller: controller,
        element: e,
        height: _strip);
    // Too short for both: the strip alone, until Keys is shut.
    if (_strip >= widget.height) return strip;
    var most = widget.height - AnimationPanel.cardsLeast;
    return Column(children: [
      Stack(children: [
        strip,
        // Its bottom edge, dragged: taller or shorter, the cards keeping
        // their room. Double-clicked, back to how it opens.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              key: const ValueKey("keysGrip"),
              behavior: HitTestBehavior.opaque,
              supportedDevices: dragPointers,
              onVerticalDragUpdate: (d) => controller.keysHeight =
                  (_strip + d.delta.dy).clamp(KeysStrip.leastHeight, most),
              onDoubleTap: () => controller.keysHeight = null,
            ),
          ),
        ),
      ]),
      Expanded(child: cards),
    ]);
  }

  /// _stripFor sets [_strip] for [e]: as tall as its rows, leaving the
  /// cards room.
  void _stripFor(CanvasElement? e) {
    if (e == null || !controller.keysShown) {
      _strip = 0;
      return;
    }
    var room = widget.height - AnimationPanel.cardsLeast;
    if (room < KeysStrip.rulerHeight + 2 * KeysStrip.rowHeight) {
      _strip = widget.height;
      return;
    }
    // As tall as it was dragged; else as its rows, up to how it opens.
    var want = controller.keysHeight ??
        KeysStrip.heightFor(
            KeysStrip.rowsFor(controller, e), KeysStrip.startHeight);
    _strip = want.clamp(math.min(KeysStrip.leastHeight, room), room);
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (controller.pickedMotion != _was) {
      _was = controller.pickedMotion;
    }
    setState(() {});
  }

  /// _picked is the clip picked -- or, with none, the selected element's
  /// first: in a slot, else on the timeline.
  (CanvasElement, MotionClip)? get _picked {
    var id = controller.pickedMotion;
    if (id == null) {
      var e = controller.selected;
      if (e == null) return null;
      var m = e.base.motion;
      var first = [
        for (var s in m.slots)
          if (s.isNotEmpty) s,
        for (var p in m.placed) p.clip,
      ].map(m.clip).whereType<MotionClip>().firstOrNull;
      return first == null ? null : (e, first);
    }
    for (var e in controller.document.elements) {
      if (e.base.motion.clip(id) case var c?) return (e, c);
    }
    return null;
  }

  /// _pickedId is the id of the clip shown: picked, or the selected
  /// element's first.
  String? get _pickedId => _picked?.$2.id;

  void _edit(CanvasElement e, MotionClip Function(MotionClip) change,
      {bool live = false}) {
    if (live) {
      controller.beginInteraction();
      controller.editMotionClip(e.id, _pickedId!, change, transient: true);
    } else {
      controller.editMotionClip(e.id, _pickedId!, change);
    }
  }

  /// _device is one section of the panel: drawn at its text's own size
  /// whatever the panel's height, scrolling where it is taller than the
  /// room. [help], when there is any, is behind a "?" in its header.
  Widget _device(
      String id, String title, double width, Widget body, ColorScheme colors,
      {List<Widget> actions = const [], String? help}) {
    return DeviceFrame(
      key: ValueKey("animDevice-$id"),
      id: "anim-$id",
      title: title,
      skin: DeviceSkin.themed(colors),
      folded: _folded.contains(id),
      onFold: () => setState(
          () => _folded.contains(id) ? _folded.remove(id) : _folded.add(id)),
      width: width,
      height: _room - 40,
      drawnHeight: _room - 40,
      actions: actions,
      // Behind its "?", read when clicked: the Chain shows no tips on hover.
      help: help ?? "",
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(child: body),
      ),
      foldedBody: const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    _showFocus();
    var resize = widget.onResize;
    return Stack(children: [
      // Every card in the settings panel's style (Ken, 2026-11-12).
      ChainPanelStyle(child: _body(context)),
      // Its top edge, dragged: taller or shorter, as the effects are.
      if (resize != null)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              supportedDevices: dragPointers,
              key: const ValueKey("animationGrip"),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => resize(widget.height - d.delta.dy),
            ),
          ),
        ),
    ]);
  }

  /// _sceneBody is a scene picked from the timeline, as a chain like every
  /// other (Ken, 2026-11-08: the prototype's scene design): its own clips
  /// -- a Camera's, keying its zoom and where it looks -- how it gives way
  /// to the next, its camera's slow move, and its Output.
  Widget _sceneBody(BuildContext context, int index) {
    var studio = MixerLook.of(context).studio;
    var master = controller.document.editingMaster;
    var h = widget.height - 40;
    var camera = master ? null : sceneCameraOf(controller, index);
    // Its clips edited where they are: on the scene open.
    var keyed = camera != null && controller.document.at == index;
    MotionClip? firstClip(CanvasElement e) {
      var m = e.base.motion;
      return [
        for (var s in m.slots)
          if (s.isNotEmpty) s,
        for (var p in m.placed) p.clip,
      ].map(m.clip).whereType<MotionClip>().firstOrNull;
    }

    bool shut(String id) => _folded.contains("$id:scene$index");
    VoidCallback fold(String id) => () => setState(() => shut(id)
        ? _folded.remove("$id:scene$index")
        : _folded.add("$id:scene$index"));
    return Container(
      key: const ValueKey("animationPanel"),
      height: widget.height,
      color: studio.panel,
      child: ListView(
        scrollDirection: Axis.horizontal,
        // Every card built, not only those in view: one asked for by the
        // settings panel is scrolled to (see _showFocus).
        cacheExtent: 100000,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          // Source: its own clips, as an element's (the master's are its
          // elements': it has no camera of its own).
          if (!master) ...[
            _zone("Source", "Its clips: a camera keyed over it"),
            if (keyed) ...[
              _clipsCard(camera, firstClip(camera)),
              MotionJoin(
                  key: const ValueKey("sceneJoin-0"),
                  controller: controller,
                  element: camera.id,
                  upto: 0,
                  height: h),
            ] else
              SceneAddCamera(
                  key: const ValueKey("sceneAddCameraCard"),
                  controller: controller,
                  scene: index,
                  height: h),
          ],
          _zone("Transition", "How it gives way to the next"),
          SceneTransitionCard(
              key: const ValueKey("sceneTransitionCard"),
              controller: controller,
              scene: index,
              folded: shut("transition"),
              onFold: fold("transition"),
              height: h),
          // The master has no camera of its own: each scene has its move.
          if (!master) ...[
            _zone("Camera", "Its slow move over the scene"),
            if (camera != null)
              SceneCameraNote(
                  key: const ValueKey("sceneCameraNote"),
                  camera: camera,
                  height: h)
            else
              SceneCameraCard(
                  key: const ValueKey("sceneCameraCard"),
                  controller: controller,
                  scene: index,
                  folded: shut("camera"),
                  onFold: fold("camera"),
                  height: h),
          ],
          _zone("Output", "Where it is shown, and what comes after"),
          SceneOutputCard(
              key: const ValueKey("sceneOutputCard"),
              controller: controller,
              scene: index,
              folded: shut("output"),
              onFold: fold("output"),
              height: h),
        ].expand((w) => [w, const SizedBox(width: 6)]).toList(),
      ),
    );
  }

  Widget _body(BuildContext context) {
    _strip = 0;
    if (controller.pickedScene case var scene?) {
      return _sceneBody(context, scene);
    }
    var colors = ThemeNotifier.of(context).colors;
    var picked = _picked;
    var hint = TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant);
    // An element with no clips still has a chain: its moves and its looks.
    // The Keyframes card's Curves, across the whole panel (Ken,
    // 2026-11-09), while what it edits is picked.
    if (controller.trackCurvesShown &&
        controller.keyframeTarget?.points == false) {
      return TrackCurves(
          key: const ValueKey("trackCurvesPanel"),
          controller: controller,
          height: widget.height);
    }
    if (picked == null && controller.selected != null) {
      return _chainOnly(context, controller.selected!);
    }
    if (picked == null) {
      return Container(
        key: const ValueKey("animationPanel"),
        height: widget.height,
        color: colors.surfaceContainerLow,
        alignment: Alignment.center,
        child: Text(
            "Pick a slot, a clip on the timeline or an element to see its "
            "animation here -- or double-click a scene on the timeline for "
            "its transition.",
            style: hint),
      );
    }
    var (e, c) = picked;
    _stripFor(e);
    // Its Curves, across the whole panel (the Chain's Curves tab), as the
    // chain prototype's curve editor.
    if (controller.motionCurvesShown && !c.isSound) {
      return SizedBox(
        key: const ValueKey("motionCurves"),
        height: widget.height,
        child: MotionCurves(
          key: ValueKey("motionCurves-${c.id}"),
          controller: controller,
          element: e,
          clip: c,
          playhead: _playhead(e, c),
          onEdit: (change, {bool live = false}) => _edit(e, change, live: live),
          onCommit: controller.endInteraction,
        ),
      );
    }
    var h = _room - 40;
    var studio = MixerLook.of(context).studio;
    void edit(MotionClip Function(MotionClip) change, {bool live = false}) =>
        _edit(e, change, live: live);
    bool shut(String id) => _folded.contains("$id:${e.id}");
    VoidCallback fold(String id) =>
        () => setState(() => _folded.contains("$id:${e.id}")
            ? _folded.remove("$id:${e.id}")
            : _folded.add("$id:${e.id}"));
    return Container(
      key: const ValueKey("animationPanel"),
      height: widget.height,
      color: studio.panel,
      child: _withKeys(
          e,
          ListView(
            scrollDirection: Axis.horizontal,
            // Every card built, not only those in view: one asked for by the
            // settings panel is scrolled to (see _showFocus).
            cacheExtent: 100000,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              // Its keyframes are the Keys strip's (Ken, 2026-11-12): the
              // Keyframes card is gone.
              // The element and its copies first: what the rest edits (Ken,
              // 2026-11-08).
              _zone("Copies",
                  "The element and its copies: which the chain edits"),
              _instancesCard(e),
              // Source: what it plays, when, and what starts it -- as the chain
              // prototype has it. Its keys are the Curves tab's.
              _zone("Source", "Its clips: what it plays, when and where"),
              _clipsCard(e, c),
              // The rest of its own style, beside the clip playing it: what the
              // sidebar's Animation section had (Ken, 2026-11-08).
              if (OwnStyleCard.shows(e, c))
                OwnStyleCard(
                    key: const ValueKey("ownStyleCard"),
                    controller: controller,
                    element: e,
                    clip: c,
                    folded: shut("ownStyle"),
                    onFold: fold("ownStyle"),
                    height: h),
              if (PartsCard.shows(e)) _partsCard(e),
              if (c.kind == MotionKind.model) _motionDevice(e, c, colors),
              MotionTimingCard(
                  key: const ValueKey("motionTimingCard"),
                  controller: controller,
                  element: e,
                  clip: c,
                  edit: edit,
                  height: h,
                  folded: shut("timing"),
                  onFold: fold("timing")),
              MotionLaunchCard(
                  key: const ValueKey("motionLaunchCard"),
                  controller: controller,
                  element: e,
                  clip: c,
                  edit: edit,
                  height: h,
                  folded: shut("launch"),
                  onFold: fold("launch"),
                  triggerName: _triggerName),
              if (!c.isSound)
                MotionPlaceCard(
                    key: const ValueKey("motionPlaceCard"),
                    controller: controller,
                    element: e,
                    clip: c,
                    edit: edit,
                    height: h,
                    folded: shut("place"),
                    onFold: fold("place")),
              if (!c.isSound && _insideShown(e, c)) _insideDevice(e, c, colors),
              ..._chain(e),
              _outputCard(e),
            ].expand((w) => [w, const SizedBox(width: 6)]).toList(),
          )),
    );
  }

  /// _outputCard is where [e]'s chain ends (see MotionOutputCard).
  Widget _outputCard(CanvasElement e) => MotionOutputCard(
      key: const ValueKey("motionOutputCard"),
      controller: controller,
      element: e,
      height: _room - 40,
      folded: _folded.contains("output:${e.id}"),
      onFold: () => setState(() => _folded.contains("output:${e.id}")
          ? _folded.remove("output:${e.id}")
          : _folded.add("output:${e.id}")));

  /// _partsCard is [e]'s layers or shapes, each in its own time: see
  /// PartsCard.
  Widget _partsCard(CanvasElement e) => PartsCard(
      key: const ValueKey("partsCard"),
      controller: controller,
      element: e,
      folded: _folded.contains("parts:${e.id}"),
      onFold: () => setState(() => _folded.contains("parts:${e.id}")
          ? _folded.remove("parts:${e.id}")
          : _folded.add("parts:${e.id}")),
      height: _room - 40);

  /// _instancesCard is [e]'s copies, the chain's first card: see
  /// InstancesCard.
  Widget _instancesCard(CanvasElement e) => InstancesCard(
      key: const ValueKey("instancesCard"),
      controller: controller,
      element: e.id,
      folded: _folded.contains("instances:${e.id}"),
      onFold: () => setState(() => _folded.contains("instances:${e.id}")
          ? _folded.remove("instances:${e.id}")
          : _folded.add("instances:${e.id}")),
      height: _room - 40);

  /// _clipsCard is the Source's first card: [e]'s clips, [c] the one
  /// picked (see MotionClipsCard).
  Widget _clipsCard(CanvasElement e, MotionClip? c) => KeyedSubtree(
      key: _focusKey("clips"),
      child: MotionClipsCard(
          key: const ValueKey("motionClipsCard"),
          controller: controller,
          element: e,
          clip: c,
          height: _room - 40,
          folded: _folded.contains("motionClips:${e.id}"),
          onFold: () => setState(() => _folded.contains("motionClips:${e.id}")
              ? _folded.remove("motionClips:${e.id}")
              : _folded.add("motionClips:${e.id}"))));

  /// _chain is [e]'s motion chain after its clips (the Source): its moves,
  /// a way to add one, its drawing, its looks and a way to add one -- the
  /// drawing between the two sides, as rule 1 has it.
  List<Widget> _chain(CanvasElement e) {
    var h = _room - 40;
    var devices = controller.motionDevicesOf(e.id);
    Widget card(MotionDevice d) => KeyedSubtree(
        key: _focusKey(d.id),
        child: MotionDeviceCard(
            key: ValueKey("mdevCard-${d.id}"),
            controller: controller,
            element: e.id,
            device: d.id,
            // By element and device: ids start again at m0 on each element.
            folded: _folded.contains("mdev:${e.id}:${d.id}"),
            onFold: () => setState(() =>
                _folded.contains("mdev:${e.id}:${d.id}")
                    ? _folded.remove("mdev:${e.id}:${d.id}")
                    : _folded.add("mdev:${e.id}:${d.id}")),
            height: h));
    // How fast it goes after its clips, and after each move: and, clicked,
    // the stage showing it as it is there.
    Widget join(int upto) => MotionJoin(
        key: ValueKey("motionJoinOf-$upto"),
        controller: controller,
        element: e.id,
        upto: upto,
        height: h);
    // Its moves. Its Instances is the chain's first card (see
    // _instancesCard): every copy has all of them, each with its own values.
    var reused = e.base.motion.instances != null;
    // The Chain's filter: only what plays in one phase (Ken, 2026-11-12).
    var only = controller.chainPhase;
    bool shows(MotionDevice? d) =>
        only == null || (d?.playing(only) ?? only == MotionPhase.free);
    var moves = [
      for (var d in devices)
        if (d.side == MotionDeviceSide.pose) d,
    ];
    // Each join counts the moves switched on before it, as the chain runs --
    // the Instances step first of them, reused.
    var upto = reused ? 1 : 0;
    var first = upto;
    var row = <Widget>[];
    for (var d in moves) {
      if (shows(d)) row.add(card(d));
      // Switched off, it passes what it is given, and a modulator moves
      // knobs, not the element: the join after either would be the one
      // before it again. A modulator is still counted, as the preview
      // counts it (MotionPreview.upto).
      if (d.on) {
        upto++;
        if (!d.modulates) row.add(join(upto));
      }
    }
    return [
      _zone("Before", "Moves: where it is, and when"),
      join(first),
      ...row,
      AddMotionDeviceSlot(
          key: const ValueKey("addMotionPose"),
          controller: controller,
          element: e.id,
          side: MotionDeviceSide.pose,
          height: h),
      // A camera is never drawn: it frames the page. Looks on it would
      // change nothing, so none are offered.
      if (e is CameraElement)
        _cameraNote(h)
      else ...[
        // Its Design: the element itself, where it is drawn (Ken,
        // 2026-11-12) -- and, reused or drawn at another size, how its
        // copies are drawn.
        if (shows(controller.designOf(e.id)))
          KeyedSubtree(
            key: _focusKey("design"),
            child: DesignCard(
                controller: controller,
                element: e,
                folded: _folded.contains("design:${e.id}"),
                onFold: () => setState(() => _folded.contains("design:${e.id}")
                    ? _folded.remove("design:${e.id}")
                    : _folded.add("design:${e.id}")),
                height: h),
          ),
        if (reused || e.base.motion.drawSize != 1)
          DrawingCard(
              key: const ValueKey("drawingCard"),
              controller: controller,
              element: e,
              folded: _folded.contains("drawing:${e.id}"),
              onFold: () => setState(() => _folded.contains("drawing:${e.id}")
                  ? _folded.remove("drawing:${e.id}")
                  : _folded.add("drawing:${e.id}")),
              height: h),
        _zone("After", "Looks: how it looks once drawn"),
        for (var d in devices)
          if (d.side == MotionDeviceSide.look && shows(d))
            KeyedSubtree(
              key: _focusKey(d.id),
              child: LookCard(
                  controller: controller,
                  element: e,
                  device: d,
                  folded: _folded.contains("mdev:${e.id}:${d.id}"),
                  onFold: () => setState(() =>
                      _folded.contains("mdev:${e.id}:${d.id}")
                          ? _folded.remove("mdev:${e.id}:${d.id}")
                          : _folded.add("mdev:${e.id}:${d.id}")),
                  height: h),
            ),
        AddMotionDeviceSlot(
            key: const ValueKey("addMotionLook"),
            controller: controller,
            element: e.id,
            side: MotionDeviceSide.look,
            height: h),
      ],
    ];
  }

  /// _cameraNote stands where a drawn element's looks would: a camera's
  /// moves frame the page, and it has no looks of its own.
  Widget _cameraNote(double h) {
    var look = MixerLook.of(context);
    return Container(
      key: const ValueKey("cameraNoLooks"),
      width: 170,
      height: h,
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: look.studio.edge),
      ),
      child: Text(
          "A camera frames the page and is never drawn itself, so it has no "
          "looks. Its moves above pan, push in and turn the view.",
          style:
              TextStyle(fontSize: 10.5, height: 1.4, color: look.studio.muted)),
    );
  }

  /// _zone marks where one part of the chain begins, as the Sound view's
  /// do: its name up the side by a line in the motion colour.
  Widget _zone(String label, String tip) {
    var look = MixerLook.of(context);
    return Tooltip(
      message: tip,
      child: Container(
        key: ValueKey("motionZone-$label"),
        width: 16,
        margin: const EdgeInsets.only(right: 2),
        decoration: const BoxDecoration(
            border:
                Border(left: BorderSide(color: Color(0xFF3FB08D), width: 2))),
        alignment: Alignment.center,
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(label.toUpperCase(),
              maxLines: 1,
              style: TextStyle(
                  fontSize: 9, letterSpacing: 1.1, color: look.studio.muted)),
        ),
      ),
    );
  }

  /// _chainOnly is an element with no clips: its chain alone.
  Widget _chainOnly(BuildContext context, CanvasElement e) {
    var colors = ThemeNotifier.of(context).colors;
    _stripFor(e);
    return Container(
      key: const ValueKey("animationPanel"),
      height: widget.height,
      color: colors.surfaceContainerLow,
      child: _withKeys(
        e,
        ListView(
          scrollDirection: Axis.horizontal,
          // As the chain with a clip picked: every card built.
          cacheExtent: 100000,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: [
            _zone(
                "Copies", "The element and its copies: which the chain edits"),
            _instancesCard(e),
            _zone("Source", "Its clips: what it plays, when and where"),
            _clipsCard(e, null),
            if (PartsCard.shows(e)) _partsCard(e),
            ..._chain(e),
            _outputCard(e),
          ].expand((w) => [w, const SizedBox(width: 6)]).toList(),
        ),
      ),
    );
  }

  /// _playhead is where in [c] it is playing: from its slot, or the
  /// playhead on the stretch of the timeline picked.
  double? _playhead(CanvasElement e, MotionClip c) {
    if (controller.liveMotion case var live?) {
      for (var p in live.of(e.id)?.plays ?? const <LivePlay?>[]) {
        if (p != null && p.clip == c.id && !p.ended) {
          return liveTime(c, p, live.clock);
        }
      }
    }
    var place = controller.pickedPlacement;
    var span = place == null ? null : controller.spanOf(place);
    if (span == null) return null;
    var at = controller.secondsAt(controller.frame);
    if (at < span.start || at > span.end) return null;
    return span.clipTime(c, at);
  }

  Widget _motionDevice(CanvasElement e, MotionClip c, ColorScheme colors) {
    if (c.kind == MotionKind.model) {
      var own = e is Object3dElement ? e.animations : const <ModelAnimation>[];
      var playing = c.inside["animation"] is String
          ? c.inside["animation"] as String
          : c.name;
      return _device(
          "motion",
          "Motion · from the model",
          260,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (own.isNotEmpty)
              CanvasDropdown<String>(
                key: const ValueKey("animModelAnimation"),
                label: "Plays",
                value: own.any((a) => a.$1 == playing) ? playing : own.first.$1,
                width: 200,
                options: [for (var (name, _) in own) (name, name)],
                // Its own length with it, as the model has it.
                onChanged: (name) => _edit(e, (c) {
                  var length = own.firstWhere((a) => a.$1 == name).$2;
                  return c.copyWith(
                      name: name,
                      length: length > 0 ? length : c.length,
                      inside: {...c.inside, "animation": name});
                }),
              ),
            Text(
                "One of the model's own animations, read from its file. When "
                "it plays, how fast, and how it is launched are set here; "
                "the bones' movements stay in the model.",
                style:
                    TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
          ]),
          colors);
    }
    if (c.isSound) {
      return _device(
          "motion",
          "Sound",
          240,
          Text("A sound's own editing is the clip editor's, in Effects.",
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
          colors);
    }
    var kinds = c.kind == MotionKind.camera || e is CameraElement
        ? const [MotionKind.camera, MotionKind.action]
        : const [
            MotionKind.arrive,
            MotionKind.loop,
            MotionKind.leave,
            MotionKind.action
          ];
    var others = [
      for (var o in controller.document.elements)
        if (o.id != e.id) o
    ];
    var preset = presetNamed(c.preset);
    String target() => others.isEmpty ? "" : others.first.id;
    return _device(
        "motion",
        "Motion",
        300,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var kind in kinds) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(kind.label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      color: colors.onSurfaceVariant)),
            ),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (var p in presetsFor(kind))
                ChoiceChip(
                  key: ValueKey("animPreset-${p.name}"),
                  label: Text(p.name, style: const TextStyle(fontSize: 11.5)),
                  visualDensity: VisualDensity.compact,
                  selected: !c.edited && c.preset == p.name,
                  onSelected: (_) => _edit(
                      e, (c) => p.onto(c, target: p.aims ? target() : "")),
                ),
            ]),
          ],
          if (preset != null && preset.ways.isNotEmpty && !c.edited)
            CanvasDropdown<MotionWay>(
              key: const ValueKey("animPresetWay"),
              label: "Which way",
              value: _wayOf(c, preset),
              width: 150,
              options: [for (var w in preset.ways) (w, w.label)],
              onChanged: (w) => _edit(e, (c) => preset.onto(c, way: w)),
            ),
        ]),
        colors,
        help: c.edited
            ? "Keys made by hand. Picking a motion replaces them."
            : "A ready-made motion writes the keys; change one and they "
                "are yours.");
  }

  MotionWay _wayOf(MotionClip c, MotionPreset p) {
    for (var keys in c.keys.values) {
      for (var k in keys) {
        if (k.value case MotionPlace(:var kind)) {
          for (var w in p.ways) {
            var edge = switch (w) {
              MotionWay.left => MotionPlaceKind.offLeft,
              MotionWay.right => MotionPlaceKind.offRight,
              MotionWay.top => MotionPlaceKind.offTop,
              MotionWay.bottom => MotionPlaceKind.offBottom,
            };
            if (edge == kind) return w;
          }
        }
      }
    }
    return p.ways.first;
  }

  /// _ownWay is whether [e] has an arrival and a way out of its own -- as
  /// its Animation settings have them -- that a clip can play.
  bool _ownWay(CanvasElement e) =>
      e is TextElement ||
      e is ShapeElement ||
      e is ImageElement ||
      e is ChartElement;

  bool _insideShown(CanvasElement e, MotionClip c) =>
      (_ownWay(e) &&
          (c.kind == MotionKind.arrive || c.kind == MotionKind.leave)) ||
      e is CounterElement ||
      e is LineElement ||
      (e is TextElement && e.curve != null);

  /// _insideDevice is what only this kind of element does in the clip, kept
  /// as its settings rather than as keys: its own arrival or way out played
  /// across the clip; a counter counting; a line bowing; text sliding along
  /// its line.
  Widget _insideDevice(CanvasElement e, MotionClip c, ColorScheme colors) {
    void set(String key, Object? value) => _edit(
        e,
        (c) => c.copyWith(
            inside: {...c.inside, key: value}
              ..removeWhere((_, v) => v == null || v == false)));

    /// span is a from--to pair: a switch, and the two ends when on.
    List<Widget> span(String key, String label, double from, double to,
        {int decimals = 2}) {
      var on = switch (c.inside[key]) { [num _, num _] => true, _ => false };
      var pair = on ? c.inside[key] as List : [from, to];
      var a = (pair[0] as num).toDouble(), b = (pair[1] as num).toDouble();
      return [
        CanvasToggle(
          key: ValueKey("animInside-$key"),
          label: label,
          value: on,
          onChanged: (v) => set(key, v ? [a, b] : null),
        ),
        if (on)
          Row(children: [
            CanvasNumberField(
              key: ValueKey("animInside-$key-from"),
              label: "From",
              value: a,
              decimals: decimals,
              width: 100,
              onChanged: (v) => set(key, [v, b]),
            ),
            const SizedBox(width: 8),
            CanvasNumberField(
              key: ValueKey("animInside-$key-to"),
              label: "To",
              value: b,
              decimals: decimals,
              width: 100,
              onChanged: (v) => set(key, [a, v]),
            ),
          ]),
      ];
    }

    var arriving = c.kind == MotionKind.arrive;
    return _device(
        "inside",
        "Inside it",
        260,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_ownWay(e) &&
              (c.kind == MotionKind.arrive || c.kind == MotionKind.leave)) ...[
            CanvasToggle(
              key: const ValueKey("animInside-own"),
              label:
                  arriving ? "Plays its own arrival" : "Plays its own way out",
              value: c.inside["own"] == true,
              onChanged: (v) => set("own", v),
            ),
            const SizedBox(height: 6),
          ],
          if (e is CounterElement)
            ...span("count", "Counts", e.from, e.to, decimals: 0),
          if (e is LineElement)
            ...span("bow", "Bows", e.curvature, e.curvature == 0 ? 0.5 : 0),
          if (e is TextElement && e.curve != null)
            ...span("slide", "Slides along its line", e.curve!.offset, 1),
        ]),
        colors,
        help: !_ownWay(e) ||
                (c.kind != MotionKind.arrive && c.kind != MotionKind.leave)
            ? null
            : arriving
                ? "Its own arrival: its words, pieces or layers come in as its "
                    "Own style card says, across this clip. Before the clip, "
                    "it is not there yet."
                : "Its own way out: it goes as its Own style card says, "
                    "across this clip.");
  }

  String _triggerName(ClipTrigger t) {
    String name(String id) {
      var e = controller.document.elementById(id);
      if (e != null) return e.name.isEmpty ? e.id : e.name;
      for (var o in controller.document.elements) {
        if (o.base.motion.clip(id) case var c?) return c.name;
      }
      return id;
    }

    return switch (t.kind) {
      ClipTriggerKind.sceneStarts => "The scene starts",
      ClipTriggerKind.clicked => "Clicked: ${name(t.target)}",
      ClipTriggerKind.key => "Key pressed: ${t.target}",
      ClipTriggerKind.clipEnds => "When ${name(t.target)} ends",
      ClipTriggerKind.marker => "Reaching a marker",
      ClipTriggerKind.touched => "A player touches it",
      ClipTriggerKind.hit => "A punch or a kick hits it",
      ClipTriggerKind.count => switch (controller.document.counts
            .where((n) => n.id == t.target)
            .firstOrNull) {
          var n? when t.amount == 0 => "${n.name} changes",
          var n? => "${n.name} reaches ${t.amount.round()}",
          null => "A count reaches ${t.amount.round()}",
        },
    };
  }
}
