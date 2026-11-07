import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// motion_clips_card.dart is the Motion chain's first card, as the chain
// prototype has it (Ken, 2026-11-08): the element's clips as chips to pick
// and launch, the picked one's path drawn, its Speed and its layer's
// Weight, and whether it arrives, loops, leaves or acts -- with how its
// layer mixes (Replace or Add) and how a press launches it.

/// MotionClipsCard is [element]'s clips: [clip] the one picked.
class MotionClipsCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MotionClip? clip;
  final double height;
  final bool folded;
  final VoidCallback onFold;
  const MotionClipsCard(
      {required this.controller,
      required this.element,
      required this.clip,
      required this.height,
      required this.folded,
      required this.onFold,
      super.key});

  /// _kinds are the Preset row's choices: none, then each kind of clip.
  static const _kinds = [
    (null, "None"),
    (MotionKind.arrive, "Arriving"),
    (MotionKind.loop, "Looping"),
    (MotionKind.leave, "Leaving"),
    (MotionKind.action, "Action"),
  ];

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    var skin = DeviceSkin.studio(studio);
    var c = clip;
    var e = element;
    var m = e.base.motion;
    const accent = Color(0xFF3FB08D);

    void edit(MotionClip Function(MotionClip) change, {bool live = false}) {
      var now = controller.motionOf(e.id).clip(c!.id);
      if (now == null) return;
      controller.beginInteraction();
      controller.setMotion(
          e.id, controller.motionOf(e.id).withClip(change(now)),
          transient: true);
      if (!live) controller.endInteraction();
    }

    // Its clips in their slots, in order; a "+" for another.
    var slotted = [
      for (var (i, id) in m.slots.indexed)
        if (id.isNotEmpty)
          if (m.clip(id) case var x?) (i, x),
    ];
    var free = m.slots.indexWhere((s) => s.isEmpty);
    Widget chip(int slot, MotionClip x) {
      var on = c?.id == x.id;
      return Material(
        color: on ? const Color(0xFF2E6B4F) : const Color(0xFF244536),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(
                color: on ? const Color(0xFF8FE3C3) : const Color(0xFF3A7A5C))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // ▶ launches it, as its slot does; held, a gate or a repeat goes
          // on until let go.
          Listener(
            key: ValueKey("motionClipsLaunch-${x.id}"),
            onPointerDown: (_) => controller.pressMotionSlot(e.id, slot),
            onPointerUp: (_) => controller.releaseMotionClip(e.id, x.id),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(6, 3, 2, 3),
              child: Icon(Icons.play_arrow, size: 13, color: Colors.white),
            ),
          ),
          InkWell(
            key: ValueKey("motionClipsPick-${x.id}"),
            onTap: () => controller.pickMotion(e.id, x.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 3, 8, 3),
              child: Text(x.name.isEmpty ? x.kind.label : x.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white)),
            ),
          ),
        ]),
      );
    }

    var chips = Wrap(spacing: 4, runSpacing: 4, children: [
      for (var (i, x) in slotted) chip(i, x),
      if (free >= 0)
        InkWell(
          key: const ValueKey("motionClipsNew"),
          borderRadius: BorderRadius.circular(5),
          onTap: () {
            controller.beginInteraction();
            var id = controller.newClip(e.id, slot: free);
            controller.endInteraction();
            controller.pickMotion(e.id, id);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: studio.edge)),
            child: Text("+ Clip",
                style: TextStyle(fontSize: 11, color: studio.muted)),
          ),
        ),
    ]);

    var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var kinds = c != null &&
            (c.kind == MotionKind.camera || e.kind == ElementKind.camera)
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
    String target() => others.isEmpty ? "" : others.first.id;
    // Its settings packed under its path, as the prototype's: Speed and
    // Weight, then what it is and the ready-made motion it starts from --
    // the element's own styles among them -- which way, its layer and how
    // that mixes, and its name.
    List<Widget> controls(DeviceTier tier) => [
          chips,
          if (c != null)
            DevicePack(key: const ValueKey("motionClipsPack"), children: [
              if (!c.isSound) ...[
                DeviceKnob(
                  key: const ValueKey("motionClipsSpeed"),
                  label: "Speed",
                  text: "${c.speed.toStringAsFixed(2)}×",
                  value: c.speed,
                  initial: 1,
                  min: 0.25,
                  max: 3,
                  accent: accent,
                  ink: skin.ink,
                  onChanged: (v, {transient = false}) => edit(
                      (x) => x.copyWith(speed: (v * 20).roundToDouble() / 20),
                      live: transient),
                  onCommit: controller.endInteraction,
                ),
                DeviceKnob(
                  key: const ValueKey("motionClipsWeight"),
                  label: "Weight",
                  text: "${(m.weight(c.layer) * 100).round()}%",
                  value: m.weight(c.layer),
                  initial: 1,
                  min: 0,
                  max: 1,
                  accent: accent,
                  ink: skin.ink,
                  onChanged: (v, {transient = false}) {
                    controller.beginInteraction();
                    controller.weighLayer(e.id, c.layer, v, transient: true);
                    if (!transient) controller.endInteraction();
                  },
                  onCommit: controller.endInteraction,
                ),
                StudioDrop<MotionKind?>(
                  key: const ValueKey("motionClipsKind"),
                  label: "Kind",
                  value:
                      c.keys.isEmpty && c.inside["own"] != true ? null : c.kind,
                  options: [
                    for (var (kind, label) in _kinds)
                      if (kind == null || kinds.contains(kind)) (kind, label),
                    for (var k in kinds)
                      if (!_kinds.any((x) => x.$1 == k)) (k, k.label),
                  ],
                  onChanged: (kind) => edit((x) => _kindOf(x, kind)),
                ),
                ..._presetDrops(context, look, c, edit, target),
              ],
              StudioDrop<int>(
                key: const ValueKey("motionClipsOn"),
                label: "Layer",
                value: c.layer,
                options: [
                  for (var l = 0; l < motionLayers; l++) (l, "L${l + 1}")
                ],
                onChanged: (l) => edit((x) => x.copyWith(layer: l)),
              ),
              // Whether it takes over from the layers under it or adds to
              // them.
              StudioDrop<bool>(
                key: const ValueKey("motionClipsLayer"),
                label: "Mixes",
                value: c.replace,
                options: const [(false, "Add"), (true, "Replace")],
                onChanged: (v) => edit((x) => x.copyWith(replace: v)),
              ),
              _ClipName(
                  key: ValueKey("animClipName-${c.id}"),
                  name: c.name,
                  onNamed: (v) => edit((x) => x.copyWith(name: v))),
            ]),
        ];

    return DeviceFrame(
      id: "motionClips",
      title: "Motion clips",
      help: "The element's clips: pick one to change it, ▶ to play it. "
          "Preset makes it arrive, loop, leave or act; Layer says whether "
          "it takes over from the clips under it or adds to them; Launch is "
          "what a press does.",
      skin: skin,
      icon: Icons.view_agenda_outlined,
      accent: accent,
      glows: true,
      folded: folded,
      onFold: onFold,
      // Three settings across under its path; wider with a larger text
      // size, so they keep their words.
      width: 400 * scale,
      besideDisplay: 240,
      besideSettings: 400,
      height: height,
      actions: [
        if (c != null)
          IconButton(
            key: const ValueKey("motionClipsCurves"),
            tooltip: "Open its curves",
            icon: const Icon(Icons.open_in_new),
            onPressed: () => controller.showMotionCurves(e.id, c.id),
          ),
      ],
      summary: c == null
          ? "No clips"
          : "${c.name} · ${c.kind.label}${c.replace ? " · replaces" : ""}",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: controls,
      display: CustomPaint(
        key: const ValueKey("motionClipsPath"),
        painter: _ClipPath(
            c,
            controller.frame / math.max(1, controller.document.frameRate),
            studio.display,
            accent),
        // The whole screen: a painter with no child is given no room.
        child: const SizedBox.expand(),
      ),
    );
  }

  /// _presetDrops are [c]'s Preset -- the ready-made motions of its kind,
  /// then the element's own ways to arrive or leave (Ken, 2026-11-08: the
  /// clip holds how it arrives, leaves and loops; picked, in one step) --
  /// and, by what is picked, which way it goes and how far; for a loop,
  /// the element's own loop beside it.
  List<Widget> _presetDrops(
      BuildContext context,
      MixerLook look,
      MotionClip c,
      void Function(MotionClip Function(MotionClip), {bool live}) edit,
      String Function() target) {
    var e = element;
    var animates = CanvasController.animates(e);
    var a = CanvasController.elementAnimationOf(e);
    var own = c.inside["own"] == true;
    var arriving = c.kind == MotionKind.arrive;
    var ownKind = animates && (arriving || c.kind == MotionKind.leave);
    var chosen = arriving ? a.preset : a.exit;
    void style(ElementAnimation next, {bool asOwn = true}) {
      // One step: the clip made its own, and the style chosen.
      if (asOwn) {
        edit(
            (x) => x.copyWith(
                inside: {...x.inside, "own": true},
                keys: const {},
                preset: "",
                edited: false),
            live: true);
      } else {
        controller.beginInteraction();
      }
      controller.setElementAnimation(e.id, next);
      controller.endInteraction();
    }

    var presets = presetsFor(c.kind);
    if (presets.isEmpty && !ownKind && c.kind != MotionKind.loop) {
      return const [];
    }
    var preset = presetNamed(c.preset);
    var value = own
        ? "own:${chosen.name}"
        : !c.edited && c.preset.isNotEmpty
            ? "p:${c.preset}"
            : "";
    var directed = arriving ? a.arrivalDirected : a.exitDirected;
    var strengthens = arriving ? a.arrivalStrengthens : a.exitStrengthens;
    return [
      StudioDrop<String>(
        key: const ValueKey("motionClipsPreset"),
        label: "Preset",
        value: value,
        options: [
          ("", c.edited ? "Its own keys" : "None"),
          for (var p in presets) ("p:${p.name}", p.name),
          if (ownKind)
            for (var p in ElementAnimationPreset.values)
              if (p != ElementAnimationPreset.none)
                ("own:${p.name}", "Its own: ${p.label}"),
        ],
        onChanged: (v) {
          if (v.startsWith("own:")) {
            var p = ElementAnimationPreset.values.byName(v.substring(4));
            style(arriving ? a.copyWith(preset: p) : a.copyWith(exit: p));
          } else if (v.startsWith("p:")) {
            var p = presetNamed(v.substring(2));
            if (p == null) return;
            edit((x) => p.onto(x.copyWith(inside: {...x.inside}..remove("own")),
                target: p.aims ? target() : ""));
          }
        },
      ),
      if (!own && preset != null && preset.ways.isNotEmpty && !c.edited)
        StudioDrop<MotionWay>(
          key: const ValueKey("animPresetWay"),
          label: "Which way",
          value: _wayOf(c, preset),
          options: [for (var w in preset.ways) (w, w.label)],
          onChanged: (w) => edit((x) => preset.onto(x, way: w)),
        ),
      if (own && directed)
        StudioDrop<AnimationDirection?>(
          key: const ValueKey("ownDirection"),
          label: arriving ? "Comes from" : "Goes to",
          value: arriving ? a.direction : a.exitDirection,
          options: [
            (null, "Its own way"),
            for (var d in AnimationDirection.values) (d, d.label),
          ],
          onChanged: (d) => style(
              arriving
                  ? (d == null
                      ? a.copyWith(clearDirection: true)
                      : a.copyWith(direction: d))
                  : a.copyWith(exitDirection: d),
              asOwn: false),
        ),
      if (own && strengthens)
        DeviceKnob(
          key: const ValueKey("ownStrength"),
          label: "How far",
          text: "${((arriving ? a.strength : a.exitStrength) * 100).round()}%",
          value: arriving ? a.strength : a.exitStrength,
          initial: 1,
          min: 0.25,
          max: 3,
          accent: const Color(0xFF3FB08D),
          ink: look.studio.text,
          onChanged: (v, {transient = false}) {
            controller.beginInteraction();
            controller.setElementAnimation(
                e.id,
                arriving
                    ? a.copyWith(strength: v)
                    : a.copyWith(exitStrength: v));
            if (!transient) controller.endInteraction();
          },
          onCommit: controller.endInteraction,
        ),
      if (animates && c.kind == MotionKind.loop)
        StudioDrop<LoopPreset>(
          key: const ValueKey("ownLoop"),
          label: "Its own loop",
          value: a.loop.preset,
          options: [
            for (var p in LoopPreset.values)
              (p, p == LoopPreset.none ? "None" : p.label)
          ],
          onChanged: (p) =>
              style(a.copyWith(loop: a.loop.copyWith(preset: p)), asOwn: false),
        ),
    ];
  }

  /// _wayOf is which way [p] goes as [c]'s keys have it.
  static MotionWay _wayOf(MotionClip c, MotionPreset p) {
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

  /// _kindOf is [c] made [kind]: its first ready-made motion of that kind,
  /// or -- None -- no motion at all, its keys gone.
  static MotionClip _kindOf(MotionClip c, MotionKind? kind) {
    if (kind == null) {
      return c.copyWith(keys: const {}, preset: "", edited: false);
    }
    if (c.kind == kind && c.keys.isNotEmpty) return c;
    var first = presetsFor(kind).firstOrNull;
    return first == null ? c.copyWith(kind: kind) : first.onto(c);
  }
}

/// _ClipPath is [clip]'s path, from its across and down keys, with where it
/// is at [seconds] on it: the prototype's Motion clips screen.
class _ClipPath extends CustomPainter {
  final MotionClip? clip;
  final double seconds;
  final Color back, accent;
  _ClipPath(this.clip, this.seconds, this.back, this.accent);

  static double _at(List<MotionKey>? keys, double t) {
    if (keys == null || keys.isEmpty) return 0;
    double v(MotionKey k) =>
        k.value is MotionNumber ? (k.value as MotionNumber).value : 0;
    if (t <= keys.first.t) return v(keys.first);
    for (var i = 1; i < keys.length; i++) {
      if (t <= keys[i].t) {
        var a = keys[i - 1], b = keys[i];
        var u = b.t == a.t ? 1.0 : (t - a.t) / (b.t - a.t);
        return v(a) + (v(b) - v(a)) * u;
      }
    }
    return v(keys.last);
  }

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    var grid = Paint()..color = Color.lerp(back, Colors.white, 0.06)!;
    for (var i = 1; i < 8; i++) {
      canvas.drawRect(
          Rect.fromLTWH((i * w / 8).roundToDouble(), 0, 1, h), grid);
    }
    for (var i = 1; i < 4; i++) {
      canvas.drawRect(
          Rect.fromLTWH(0, (i * h / 4).roundToDouble(), w, 1), grid);
    }
    var c = clip;
    if (c == null || c.length <= 0) return;
    var xs = c.keys[MotionProp.x], ys = c.keys[MotionProp.y];
    // Its path, scaled to fit: across and down over its length; with
    // neither, how big it gets over time, as a line.
    var pts = <Offset>[];
    for (var i = 0; i <= 60; i++) {
      var t = c.length * i / 60;
      pts.add(xs == null && ys == null
          ? Offset(t / c.length, -_at(c.keys[MotionProp.scale], t))
          : Offset(_at(xs, t), _at(ys, t)));
    }
    var minX = pts.map((p) => p.dx).reduce(math.min),
        maxX = pts.map((p) => p.dx).reduce(math.max),
        minY = pts.map((p) => p.dy).reduce(math.min),
        maxY = pts.map((p) => p.dy).reduce(math.max);
    var spanX = math.max(1e-6, maxX - minX),
        spanY = math.max(1e-6, maxY - minY);
    Offset fit(Offset p) => Offset(
        14 + (spanX < 1e-3 ? 0.5 : (p.dx - minX) / spanX) * (w - 28),
        14 + (spanY < 1e-3 ? 0.5 : (p.dy - minY) / spanY) * (h - 28));
    var dash = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < pts.length - 1; i += 2) {
      canvas.drawLine(fit(pts[i]), fit(pts[i + 1]), dash);
    }
    // Where it is now, round its length.
    var t = c.loop
        ? (seconds * c.speed) % c.length
        : math.min(c.length, seconds * c.speed % (c.length * 1.5));
    var now = xs == null && ys == null
        ? Offset(t / c.length, -_at(c.keys[MotionProp.scale], t))
        : Offset(_at(xs, t), _at(ys, t));
    canvas.drawCircle(fit(now), 7, Paint()..color = const Color(0xFFE2B04A));
    canvas.drawCircle(
        fit(now),
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFB8860B));
  }

  @override
  bool shouldRepaint(_ClipPath old) =>
      old.clip != clip || old.seconds != seconds || old.accent != accent;
}

/// _ClipName is the picked clip's name, typed into.
class _ClipName extends StatefulWidget {
  final String name;
  final ValueChanged<String> onNamed;
  const _ClipName({required this.name, required this.onNamed, super.key});

  @override
  State<_ClipName> createState() => _ClipNameState();
}

class _ClipNameState extends State<_ClipName> {
  late final _text = TextEditingController(text: widget.name);

  @override
  void didUpdateWidget(_ClipName old) {
    super.didUpdateWidget(old);
    if (widget.name != _text.text && !FocusScope.of(context).hasFocus) {
      _text.text = widget.name;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    // Laid out as a StudioDrop is -- its label over a box 22 high -- to
    // line up with the dropdowns beside it (Ken).
    var edge = OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: s.edge));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text("Name",
              maxLines: 1, style: TextStyle(fontSize: 10, color: s.muted)),
        ),
        SizedBox(
          height: 22,
          child: TextField(
            key: const ValueKey("animClipName"),
            controller: _text,
            style: TextStyle(fontSize: 11, color: s.text),
            textAlignVertical: TextAlignVertical.center,
            // The whole 22, as the dropdowns' boxes.
            expands: true,
            maxLines: null,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: s.inset,
              contentPadding: const EdgeInsets.symmetric(horizontal: 7),
              border: edge,
              enabledBorder: edge,
              focusedBorder: edge,
            ),
            onSubmitted: widget.onNamed,
            onTapOutside: (_) {
              if (_text.text != widget.name) widget.onNamed(_text.text);
              FocusScope.of(context).unfocus();
            },
          ),
        ),
      ],
    );
  }
}
