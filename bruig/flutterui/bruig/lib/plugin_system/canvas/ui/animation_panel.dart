import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart'
    show Quantise;
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_lanes.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// animation_panel.dart is the Animation panel: the picked clip, laid out as
// the effects are -- a row of devices side by side, each folding to its
// title. Clip; Motion, the ready-made motions; Keys, as wide as it is let be
// and dragged wider (Ken); Inside it, what only this kind of element does;
// Timing, where it is placed and pinned; Place; and Launch.
//
// Every change goes through motion_editing.dart, so it is one undo step --
// a slider dragged, one step for the whole drag.

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

  @override
  State<AnimationPanel> createState() => _AnimationPanelState();
}

class _AnimationPanelState extends State<AnimationPanel> {
  CanvasController get controller => widget.controller;

  /// _folded are the devices folded to their titles, by id. For the session.
  static final Set<String> _folded = {};

  /// _keysWidth is how wide the Keys device has been dragged.
  static double _keysWidth = 620;

  /// _keyPicked is the key picked in the Keys device: its property and
  /// index.
  (MotionProp, int)? _keyPicked;

  String? _was;

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
      _keyPicked = null;
    }
    setState(() {});
  }

  (CanvasElement, MotionClip)? get _picked {
    var id = controller.pickedMotion;
    if (id == null) return null;
    for (var e in controller.document.elements) {
      if (e.base.motion.clip(id) case var c?) return (e, c);
    }
    return null;
  }

  void _edit(CanvasElement e, MotionClip Function(MotionClip) change,
      {bool live = false}) {
    if (live) {
      controller.beginInteraction();
      controller.editMotionClip(e.id, controller.pickedMotion!, change,
          transient: true);
    } else {
      controller.editMotionClip(e.id, controller.pickedMotion!, change);
    }
  }

  Widget _device(
      String id, String title, double width, Widget body, ColorScheme colors,
      {List<Widget> actions = const []}) {
    return DeviceFrame(
      key: ValueKey("animDevice-$id"),
      id: "anim-$id",
      title: title,
      skin: DeviceSkin.themed(colors),
      folded: _folded.contains(id),
      onFold: () => setState(
          () => _folded.contains(id) ? _folded.remove(id) : _folded.add(id)),
      width: width,
      height: widget.height - 40,
      actions: actions,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(child: body),
      ),
      foldedBody: const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    var resize = widget.onResize;
    return Stack(children: [
      _body(context),
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
              key: const ValueKey("animationGrip"),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => resize(widget.height - d.delta.dy),
            ),
          ),
        ),
    ]);
  }

  Widget _body(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var picked = _picked;
    var hint = TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant);
    if (picked == null) {
      return Container(
        key: const ValueKey("animationPanel"),
        height: widget.height,
        color: colors.surfaceContainerLow,
        alignment: Alignment.center,
        child: Text(
            "Pick a slot, a clip on the timeline or an element to see its "
            "animation here.",
            style: hint),
      );
    }
    var (e, c) = picked;
    var place = controller.pickedPlacement;
    var span = place == null ? null : controller.spanOf(place);
    var colour = motionKindColours[c.kind]!;
    return Container(
      key: const ValueKey("animationPanel"),
      height: widget.height,
      color: colors.surfaceContainerLow,
      child: Column(children: [
        SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: colour, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Flexible(
                child: Text("${e.name.isEmpty ? e.id : e.name} · ${c.name}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: colors.onSurface)),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                    "${span != null ? "On the timeline" : _slotLabel(e, c)}"
                    "${c.isSound ? "" : " · layer ${c.layer + 1}"} · ${c.kind.label}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hint),
              ),
            ]),
          ),
        ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              _clipDevice(e, c, colors),
              _motionDevice(e, c, colors),
              if (!c.isSound && c.kind != MotionKind.model)
                _keysDevice(e, c, colors),
              _timingDevice(e, c, span, colors),
              if (!c.isSound) _placeDevice(e, c, colors),
              _launchDevice(e, c, colors),
            ].expand((w) => [w, const SizedBox(width: 6)]).toList(),
          ),
        ),
      ]),
    );
  }

  String _slotLabel(CanvasElement e, MotionClip c) {
    var i = e.base.motion.slots.indexOf(c.id);
    return i < 0 ? "In no slot" : "Slot ${i + 1}";
  }

  Widget _clipDevice(CanvasElement e, MotionClip c, ColorScheme colors) =>
      _device(
          "clip",
          "Clip",
          220,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CanvasTextField(
              key: const ValueKey("animClipName"),
              label: "Name",
              value: c.name,
              width: 190,
              onChanged: (v) =>
                  _edit(e, (c) => c.copyWith(name: v), live: true),
              onCommit: controller.endInteraction,
            ),
            if (!c.isSound)
              CanvasDropdown<int>(
                key: const ValueKey("animClipLayer"),
                label: "Layer",
                value: c.layer.clamp(0, motionLayers - 1),
                width: 120,
                options: [
                  for (var l = 0; l < motionLayers; l++) (l, "Layer ${l + 1}")
                ],
                onChanged: (l) => _edit(e, (c) => c.copyWith(layer: l)),
              ),
            CanvasNumberField(
              key: const ValueKey("animClipLength"),
              label: "Length",
              value: c.length,
              min: 0.05,
              max: 600,
              decimals: 2,
              suffix: " s",
              onChanged: (v) => _edit(e, (c) => c.retimed(v)),
            ),
            CanvasSlider(
              key: const ValueKey("animClipSpeed"),
              label: "Speed",
              value: c.speed,
              min: 0.25,
              max: 3,
              onChanged: (v) =>
                  _edit(e, (c) => c.copyWith(speed: v), live: true),
              onCommit: controller.endInteraction,
            ),
            CanvasToggle(
              key: const ValueKey("animClipLoop"),
              label: "Loops",
              value: c.loop,
              onChanged: (v) => _edit(e, (c) => c.copyWith(loop: v)),
            ),
            if (!c.isSound)
              Text("Layers add together: one walks while another waves.",
                  style:
                      TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ]),
          colors);

  Widget _motionDevice(CanvasElement e, MotionClip c, ColorScheme colors) {
    if (c.kind == MotionKind.model) {
      return _device(
          "motion",
          "Motion · from the model",
          240,
          Text(
              "The model's own animation, read from its file. Its timing, "
              "launching and place are set here; the bones' keys stay in "
              "the model.",
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
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
    var kinds = c.kind == MotionKind.camera
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
          const SizedBox(height: 6),
          Text(
              c.edited
                  ? "Keys made by hand. Picking a motion replaces them."
                  : "A ready-made motion writes the keys; change one and they "
                      "are yours.",
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        ]),
        colors);
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

  Widget _keysDevice(CanvasElement e, MotionClip c, ColorScheme colors) {
    var picked = _keyPicked;
    var key =
        picked == null ? null : c.keys[picked.$1]?.elementAtOrNull(picked.$2);
    var editor = _KeysEditor(
      clip: c,
      picked: key == null ? null : picked,
      colors: colors,
      onPick: (p) => setState(() => _keyPicked = p),
      onAdd: (prop, t) {
        var scene = motionSceneOf(controller.document, controller.frame);
        var v = sampleProp(c, prop, t, boxOf(e), scene) ?? prop.rest;
        var keys = [
          ...?c.keys[prop],
          MotionKey(t, MotionNumber(_round(v)), ease: KeyframeEasing.easeInOut)
        ]..sort((a, b) => a.t.compareTo(b.t));
        _edit(
            e, (c) => c.copyWith(keys: {...c.keys, prop: keys}, edited: true));
        setState(() => _keyPicked = (prop, keys.indexWhere((k) => k.t == t)));
      },
      onMove: (prop, i, t, done) {
        var keys = [...c.keys[prop]!];
        keys[i] = keys[i].copyWith(t: t);
        if (!done) {
          _edit(
              e, (c) => c.copyWith(keys: {...c.keys, prop: keys}, edited: true),
              live: true);
          return;
        }
        var moved = keys[i];
        keys.sort((a, b) => a.t.compareTo(b.t));
        _edit(e, (c) => c.copyWith(keys: {...c.keys, prop: keys}, edited: true),
            live: true);
        controller.endInteraction();
        setState(() => _keyPicked = (prop, keys.indexOf(moved)));
      },
    );
    var side = key == null
        ? Text(
            "Click a row to add a key, drag a key to retime it, click one "
            "to change it. Amber keys are places worked out as it plays.",
            style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant))
        : _keyFields(e, c, picked!.$1, picked.$2, key, colors);
    // Its right edge is dragged to make it wider (Ken: the keys' timeline
    // as big as it can be, and resizable).
    return Stack(children: [
      _device(
          "keys",
          "Keys",
          _keysWidth,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: editor),
            const SizedBox(width: 10),
            SizedBox(width: 200, child: side),
          ]),
          colors),
      if (!_folded.contains("keys"))
        Positioned(
          right: 0,
          top: 28,
          bottom: 0,
          width: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              key: const ValueKey("animKeysGrip"),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(() =>
                  _keysWidth = (_keysWidth + d.delta.dx).clamp(380.0, 2400.0)),
            ),
          ),
        ),
    ]);
  }

  double _round(double v) => (v * 100).roundToDouble() / 100;

  Widget _keyFields(CanvasElement e, MotionClip c, MotionProp prop, int i,
      MotionKey k, ColorScheme colors) {
    var keys = c.keys[prop]!;
    void write(MotionKey next) {
      var list = [...keys];
      list[i] = next;
      list.sort((a, b) => a.t.compareTo(b.t));
      _edit(e, (c) => c.copyWith(keys: {...c.keys, prop: list}, edited: true));
      setState(() => _keyPicked = (prop, list.indexOf(next)));
    }

    var places = <(String, String)>[
      ("", "A number"),
      if (prop == MotionProp.x) ...[
        (MotionPlaceKind.offLeft.name, MotionPlaceKind.offLeft.label),
        (MotionPlaceKind.offRight.name, MotionPlaceKind.offRight.label),
      ],
      if (prop == MotionProp.y) ...[
        (MotionPlaceKind.offTop.name, MotionPlaceKind.offTop.label),
        (MotionPlaceKind.offBottom.name, MotionPlaceKind.offBottom.label),
      ],
      if (prop == MotionProp.x || prop == MotionProp.y)
        for (var o in controller.document.elements)
          if (o.id != e.id)
            for (var kind in [
              prop == MotionProp.x
                  ? MotionPlaceKind.beside
                  : MotionPlaceKind.ground,
              MotionPlaceKind.on
            ])
              (
                "${kind.name}:${o.id}",
                "${kind.label} ${o.name.isEmpty ? o.id : o.name}"
              ),
    ];
    var current = switch (k.value) {
      MotionNumber() => "",
      MotionPlace(:var kind, :var target) =>
        kind.needsTarget ? "${kind.name}:$target" : kind.name,
    };
    var scene = motionSceneOf(controller.document, controller.frame);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text("${prop.label} · key ${i + 1} of ${keys.length}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: colors.onSurface)),
        ),
        IconButton(
          key: const ValueKey("animKeyRemove"),
          tooltip: "Remove this key",
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.close, size: 16),
          onPressed: () {
            var list = [...keys]..removeAt(i);
            _edit(
                e,
                (c) => c.copyWith(
                    keys: {...c.keys, prop: list}
                      ..removeWhere((_, v) => v.isEmpty),
                    edited: true));
            setState(() => _keyPicked = null);
          },
        ),
      ]),
      CanvasNumberField(
        key: const ValueKey("animKeyAt"),
        label: "At",
        value: k.t,
        min: 0,
        max: c.length,
        decimals: 2,
        suffix: " s",
        onChanged: (v) => write(k.copyWith(t: v.clamp(0.0, c.length))),
      ),
      CanvasDropdown<String>(
        key: const ValueKey("animKeyPlace"),
        label: "Value",
        value: places.any((p) => p.$1 == current) ? current : "",
        width: 190,
        options: places,
        onChanged: (v) {
          if (v.isEmpty) {
            write(k.copyWith(
                value: MotionNumber(
                    _round(motionValue(c, prop, k.value, boxOf(e), scene)))));
            return;
          }
          var parts = v.split(":");
          var kind = MotionPlaceKind.fromName(parts[0])!;
          write(k.copyWith(
              value:
                  MotionPlace(kind, target: parts.length > 1 ? parts[1] : "")));
        },
      ),
      if (k.value case MotionNumber(:var value))
        CanvasNumberField(
          key: const ValueKey("animKeyValue"),
          label: prop.label,
          value: value,
          decimals:
              prop == MotionProp.scale || prop == MotionProp.opacity ? 2 : 0,
          onChanged: (v) => write(k.copyWith(value: MotionNumber(v))),
        ),
      CanvasDropdown<KeyframeEasing>(
        key: const ValueKey("animKeyEase"),
        label: "Getting here",
        value: k.ease,
        width: 150,
        options: [for (var x in KeyframeEasing.values) (x, x.label)],
        onChanged: (x) => write(k.copyWith(ease: x)),
      ),
    ]);
  }

  Widget _timingDevice(
      CanvasElement e, MotionClip c, ClipSpan? span, ColorScheme colors) {
    var place = controller.pickedPlacement;
    var p = place == null ? null : e.base.motion.placement(place);
    var pins = <(String, String)>[
      ("", "Where it is put"),
      ("sceneStart", "The scene's start"),
      for (var a in controller.document.actions)
        (
          "marker:${markerKey(a)}",
          "Marker ${a.label.isEmpty ? a.frame + 1 : a.label}"
        ),
      for (var o in controller.document.elements)
        for (var x in o.base.motion.placed)
          if (x.id != place)
            (
              "after:${x.id}",
              "End of ${o.name.isEmpty ? o.id : o.name} · ${o.base.motion.clip(x.clip)?.name ?? ""}"
            ),
    ];
    String pinKey(ClipPin? pin) => switch (pin?.kind) {
          null => "",
          PinKind.sceneStart => "sceneStart",
          PinKind.sceneEnd => "sceneEnd",
          PinKind.marker => "marker:${pin!.target}",
          PinKind.after => "after:${pin!.target}",
        };
    ClipPin? pinOf(String v) {
      if (v.isEmpty) return null;
      if (v == "sceneStart") return const ClipPin(PinKind.sceneStart);
      if (v == "sceneEnd") return const ClipPin(PinKind.sceneEnd);
      var parts = v.split(":");
      return ClipPin(parts[0] == "marker" ? PinKind.marker : PinKind.after,
          target: parts.sublist(1).join(":"));
    }

    var ends = [
      ("", "Its own length"),
      ("sceneEnd", "The scene's end"),
      for (var x in pins.skip(2)) x,
    ];
    return _device(
        "timing",
        "Timing",
        290,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!c.isSound) ...[
            CanvasDropdown<ClipHold>(
              key: const ValueKey("animBefore"),
              label: "Before it starts",
              value: c.before,
              width: 180,
              options: const [
                (ClipHold.rest, "As it is"),
                (ClipHold.first, "Holds its first frame")
              ],
              onChanged: (h) => _edit(e, (c) => c.copyWith(before: h)),
            ),
            CanvasDropdown<ClipHold>(
              key: const ValueKey("animAfter"),
              label: "After it ends",
              value: c.after,
              width: 180,
              options: const [
                (ClipHold.rest, "Back as it is"),
                (ClipHold.last, "Holds its last frame")
              ],
              onChanged: (h) => _edit(e, (c) => c.copyWith(after: h)),
            ),
          ],
          if (p != null && span != null) ...[
            CanvasDropdown<String>(
              key: const ValueKey("animStartPin"),
              label: "Starts at",
              value: pins.any((x) => x.$1 == pinKey(p.startPin))
                  ? pinKey(p.startPin)
                  : "",
              width: 220,
              options: pins,
              onChanged: (v) => controller.pinPlacement(e.id, p.id, pinOf(v)),
            ),
            CanvasDropdown<String>(
              key: const ValueKey("animEndPin"),
              label: "Ends at",
              value: ends.any((x) => x.$1 == pinKey(p.endPin))
                  ? pinKey(p.endPin)
                  : "",
              width: 220,
              options: ends,
              onChanged: (v) =>
                  controller.pinPlacement(e.id, p.id, pinOf(v), end: true),
            ),
            Text(
                "${span.start.toStringAsFixed(2)}–${span.end.toStringAsFixed(2)} s · "
                "${c.loop ? "repeats to fill it" : "retimed to fit: ${span.speed.toStringAsFixed(2)}×"}. "
                "A pinned end follows what it is pinned to.",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ] else
            Text(
                "Placed on the timeline, its start and end can be pinned to "
                "markers, the scene, or another clip's end.",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        ]),
        colors);
  }

  Widget _placeDevice(CanvasElement e, MotionClip c, ColorScheme colors) =>
      _device(
          "place",
          "Place",
          240,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CanvasDropdown<bool>(
              key: const ValueKey("animPlace"),
              label: "Moves",
              value: c.absolute,
              width: 180,
              options: const [
                (false, "From where it is"),
                (true, "To set places")
              ],
              onChanged: (abs) {
                // Every key kept where it lands, written the other way.
                var box = boxOf(e);
                MotionKey turn(MotionKey k, double by) => switch (k.value) {
                      MotionNumber(:var value) => k.copyWith(
                          value: MotionNumber(abs ? value + by : value - by)),
                      _ => k,
                    };
                _edit(
                    e,
                    (c) => c.copyWith(absolute: abs, keys: {
                          for (var MapEntry(:key, :value) in c.keys.entries)
                            key: key == MotionProp.x
                                ? [for (var k in value) turn(k, box.center.dx)]
                                : key == MotionProp.y
                                    ? [
                                        for (var k in value)
                                          turn(k, box.center.dy)
                                      ]
                                    : value,
                        }));
              },
            ),
            Text(
                "From where it is, one clip works on any element, wherever it is "
                "moved. Off an edge, beside or on another element are worked "
                "out as it plays.",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ]),
          colors);

  Widget _launchDevice(CanvasElement e, MotionClip c, ColorScheme colors) {
    var mates = [
      for (var o in e.base.motion.clips)
        if (o.id != c.id) o
    ];
    return _device(
        "launch",
        "Launch",
        300,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CanvasDropdown<ClipLaunch>(
            key: const ValueKey("animLaunch"),
            label: "A press",
            value: c.launch,
            width: 200,
            options: [for (var l in ClipLaunch.values) (l, l.label)],
            onChanged: (l) => _edit(e, (c) => c.copyWith(launch: l)),
          ),
          CanvasDropdown<String>(
            key: const ValueKey("animQuantise"),
            label: "Waits for",
            value: c.quantise ?? "",
            width: 200,
            // The audio slots' grid: a bar, a beat, finer, or nothing.
            options: [
              ("", "The timeline's setting"),
              for (var q in Quantise.values)
                (q.name, q == Quantise.off ? "Nothing" : "The next ${q.label}"),
            ],
            onChanged: (q) => _edit(
                e, (c) => c.copyWith(quantise: () => q.isEmpty ? null : q)),
          ),
          CanvasDropdown<String>(
            key: const ValueKey("animThen"),
            label: "Then",
            value: c.then == ClipThen.play ? "play:${c.thenClip}" : c.then.name,
            width: 200,
            options: [
              for (var t in ClipThen.values)
                if (t != ClipThen.play) (t.name, t.label),
              for (var o in mates) ("play:${o.id}", "Plays ${o.name}"),
            ],
            onChanged: (v) => _edit(
                e,
                (c) => v.startsWith("play:")
                    ? c.copyWith(then: ClipThen.play, thenClip: v.substring(5))
                    : c.copyWith(then: ClipThen.fromName(v), thenClip: "")),
          ),
          const SizedBox(height: 6),
          Text("ALSO STARTS WHEN",
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: colors.onSurfaceVariant)),
          for (var (i, t) in c.triggers.indexed)
            Row(children: [
              Expanded(
                child: Text(_triggerName(t),
                    style: TextStyle(fontSize: 12, color: colors.onSurface)),
              ),
              IconButton(
                key: ValueKey("animTriggerRemove-$i"),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 15),
                tooltip: "Remove",
                onPressed: () => _edit(e,
                    (c) => c.copyWith(triggers: [...c.triggers]..removeAt(i))),
              ),
            ]),
          if (c.triggers.isEmpty)
            Text(
                "Only from its slot, its cue, the timeline or another clip's Then.",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          CanvasDropdown<String>(
            key: const ValueKey("animTriggerAdd"),
            label: "Add",
            value: "",
            width: 200,
            options: [
              ("", "Add a trigger…"),
              (
                ClipTriggerKind.sceneStarts.name,
                ClipTriggerKind.sceneStarts.label
              ),
              for (var o in controller.document.elements)
                (
                  "${ClipTriggerKind.clicked.name}:${o.id}",
                  "Clicked: ${o.name.isEmpty ? o.id : o.name}"
                ),
              for (var key in const ["Space", "Enter", "A", "D"])
                ("${ClipTriggerKind.key.name}:$key", "Key pressed: $key"),
              for (var o in controller.document.elements)
                for (var x in o.base.motion.clips)
                  if (x.id != c.id)
                    (
                      "${ClipTriggerKind.clipEnds.name}:${x.id}",
                      "When ${x.name} ends"
                    ),
              (ClipTriggerKind.touched.name, ClipTriggerKind.touched.label),
            ],
            onChanged: (v) {
              if (v.isEmpty) return;
              var parts = v.split(":");
              var kind = ClipTriggerKind.fromName(parts[0])!;
              _edit(
                  e,
                  (c) => c.copyWith(triggers: [
                        ...c.triggers,
                        ClipTrigger(kind,
                            target: parts.length > 1
                                ? parts.sublist(1).join(":")
                                : ""),
                      ]));
            },
          ),
        ]),
        colors);
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
      ClipTriggerKind.count => "A count reaches ${t.amount.round()}",
    };
  }
}

/// _KeysEditor is the Keys device's rows: one per property, its keys as
/// diamonds along the clip's length.
class _KeysEditor extends StatefulWidget {
  final MotionClip clip;
  final (MotionProp, int)? picked;
  final ColorScheme colors;
  final ValueChanged<(MotionProp, int)?> onPick;
  final void Function(MotionProp prop, double t) onAdd;
  final void Function(MotionProp prop, int index, double t, bool done) onMove;

  const _KeysEditor({
    required this.clip,
    required this.picked,
    required this.colors,
    required this.onPick,
    required this.onAdd,
    required this.onMove,
  });

  @override
  State<_KeysEditor> createState() => _KeysEditorState();
}

class _KeysEditorState extends State<_KeysEditor> {
  (MotionProp, int)? _dragging;

  static const double _row = 24;

  @override
  Widget build(BuildContext context) {
    var c = widget.clip;
    var colors = widget.colors;
    var label = TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant);
    return LayoutBuilder(builder: (context, box) {
      var trackWidth = math.max(60.0, box.maxWidth - 70);
      double t(double x) => (x / trackWidth * c.length).clamp(0.0, c.length);
      double xOf(double time) =>
          c.length <= 0 ? 0 : time / c.length * trackWidth;
      var step = c.length > 3
          ? 1.0
          : c.length > 1.2
              ? 0.5
              : 0.25;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The seconds along the top.
        SizedBox(
          height: 16,
          child: Row(children: [
            const SizedBox(width: 70),
            SizedBox(
              width: trackWidth,
              child: Stack(clipBehavior: Clip.none, children: [
                for (var s = 0.0; s <= c.length + 1e-6; s += step)
                  Positioned(
                    left: xOf(s) - 10,
                    width: 20,
                    child: Text("${(s * 100).round() / 100}",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9.5, color: colors.onSurfaceVariant)),
                  ),
              ]),
            ),
          ]),
        ),
        for (var prop in MotionProp.values)
          SizedBox(
            height: _row,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                  width: 70,
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(prop.label, style: label))),
              SizedBox(
                width: trackWidth,
                child: GestureDetector(
                  key: ValueKey("animKeysRow-${prop.name}"),
                  behavior: HitTestBehavior.opaque,
                  // The key under the press is the one dragged, not
                  // whatever is under the pointer once it has moved enough
                  // to be a drag.
                  dragStartBehavior: DragStartBehavior.down,
                  onTapUp: (d) {
                    var keys = c.keys[prop] ?? const [];
                    for (var (i, k) in keys.indexed) {
                      if ((xOf(k.t) - d.localPosition.dx).abs() <= 7) {
                        widget.onPick((prop, i));
                        return;
                      }
                    }
                    widget.onAdd(prop,
                        (t(d.localPosition.dx) * 20).roundToDouble() / 20);
                  },
                  onHorizontalDragStart: (d) {
                    var keys = c.keys[prop] ?? const [];
                    for (var (i, k) in keys.indexed) {
                      if ((xOf(k.t) - d.localPosition.dx).abs() <= 7) {
                        _dragging = (prop, i);
                        widget.onPick((prop, i));
                        return;
                      }
                    }
                    _dragging = null;
                  },
                  onHorizontalDragUpdate: (d) {
                    if (_dragging case (var p, var i)) {
                      var at = HardwareKeyboard.instance.isAltPressed
                          ? t(d.localPosition.dx)
                          : (t(d.localPosition.dx) * 20).roundToDouble() / 20;
                      widget.onMove(p, i, at, false);
                    }
                  },
                  onHorizontalDragEnd: (d) {
                    if (_dragging case (var p, var i)) {
                      widget.onMove(p, i, widget.clip.keys[p]![i].t, true);
                    }
                    _dragging = null;
                  },
                  child: CustomPaint(
                    painter: _RowPainter(
                      keys: c.keys[prop] ?? const [],
                      x: xOf,
                      picked:
                          widget.picked?.$1 == prop ? widget.picked!.$2 : null,
                      colors: colors,
                    ),
                  ),
                ),
              ),
            ]),
          ),
      ]);
    });
  }
}

class _RowPainter extends CustomPainter {
  final List<MotionKey> keys;
  final double Function(double) x;
  final int? picked;
  final ColorScheme colors;

  _RowPainter(
      {required this.keys,
      required this.x,
      required this.picked,
      required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    var track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 3, size.width, size.height - 6),
        const Radius.circular(4));
    canvas.drawRRect(track, Paint()..color = colors.surfaceContainerLowest);
    canvas.drawRRect(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = colors.outlineVariant);
    for (var (i, k) in keys.indexed) {
      var c = Offset(x(k.t), size.height / 2);
      var place = k.value is MotionPlace;
      var diamond = Path()
        ..moveTo(c.dx, c.dy - 6)
        ..lineTo(c.dx + 6, c.dy)
        ..lineTo(c.dx, c.dy + 6)
        ..lineTo(c.dx - 6, c.dy)
        ..close();
      canvas.drawPath(
          diamond,
          Paint()
            ..color = i == picked
                ? colors.primary
                : place
                    ? const Color(0xFFF5B335)
                    : colors.onSurface);
    }
  }

  @override
  bool shouldRepaint(_RowPainter old) => true;
}
