import 'dart:convert' show jsonEncode;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_clip_display.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/own_style.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                // A camera move's own amount: how close it gets, or how
                // hard it shakes.
                if (cameraZoomOf(c) case var zoom?)
                  DeviceKnob(
                    key: const ValueKey("motionClipsZoom"),
                    label: "Zoom",
                    text: "${zoom.toStringAsFixed(2)}×",
                    value: zoom,
                    initial: 1.7,
                    min: 1.05,
                    max: 4,
                    accent: accent,
                    ink: skin.ink,
                    onChanged: (v, {transient = false}) => edit(
                        (x) => withCameraZoom(x, (v * 20).roundToDouble() / 20),
                        live: transient),
                    onCommit: controller.endInteraction,
                  ),
                if (cameraShakeOf(c) case var shake?)
                  DeviceKnob(
                    key: const ValueKey("motionClipsShake"),
                    label: "Strength",
                    text: "${shake.round()} px",
                    value: shake,
                    initial: 9,
                    min: 1,
                    max: 60,
                    accent: accent,
                    ink: skin.ink,
                    onChanged: (v, {transient = false}) => edit(
                        (x) => withCameraShake(x, v.roundToDouble()),
                        live: transient),
                    onCommit: controller.endInteraction,
                  ),
                DeviceKnob(
                  key: const ValueKey("motionClipsWeight"),
                  label: "Weight",
                  text: "${(m.layerWeight(c.layer) * 100).round()}%",
                  value: m.layerWeight(c.layer),
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
      // Its own arrival, loop and leaving first, to set up and to switch
      // between (Ken, 2026-11-12); its other clips under them.
      lead: [
        if (OwnStyle.of(e) != null)
          OwnTabsRow(controller: controller, element: e),
      ],
      // Its screen: what it does, drawn as the settings have it, and
      // edited there (see motion_clip_display.dart).
      display: MotionClipDisplay(
        key: ValueKey("motionClipDisplay-${c?.id}"),
        controller: controller,
        element: e,
        clip: c,
        accent: accent,
        edit: edit,
        onReset: c == null ? null : _reset(c, edit, target),
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
    // Its own animation, whichever kind: a box's, the words', a chart's
    // (Ken, 2026-11-08: text and chart too, as the sidebar had them).
    var styled = OwnStyle.of(e);
    var own = c.inside["own"] == true;
    var arriving = c.kind == MotionKind.arrive;
    var leaving = c.kind == MotionKind.leave;
    var ownKind = styled != null && (arriving || leaving);
    // [make] is given the element as it is once the clip is its own, so
    // writing the style back does not undo that.
    void styleTo(CanvasElement Function(OwnStyle s) make, {bool asOwn = true}) {
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
      var now = controller.document.elementById(e.id);
      if (now != null) {
        controller.replaceElement(make(OwnStyle(now)), transient: true);
      }
      controller.endInteraction();
    }

    void style(ElementAnimation next, {bool asOwn = true}) =>
        styleTo((s) => CanvasController.withElementAnimation(s.element, next),
            asOwn: asOwn);

    var presets = presetsFor(c.kind);
    if (presets.isEmpty && !ownKind && c.kind != MotionKind.loop) {
      return const [];
    }
    var preset = presetNamed(c.preset);
    var value = own && styled != null
        ? "own:${styled.preset(leaving: leaving)}"
        : !c.edited && c.preset.isNotEmpty
            ? "p:${c.preset}"
            : "";
    var directed = arriving ? a.arrivalDirected : a.exitDirected;
    return [
      StudioDrop<String>(
        key: const ValueKey("motionClipsPreset"),
        label: "Preset",
        value: value,
        options: [
          ("", c.edited ? "Its own keys" : "None"),
          for (var p in presets) ("p:${p.name}", p.name),
          if (ownKind)
            for (var (name, label) in styled.presets(leaving: leaving))
              ("own:$name", "Its own: $label"),
        ],
        onChanged: (v) {
          if (v.startsWith("own:")) {
            styleTo((s) => s.withPreset(v.substring(4), leaving: leaving));
          } else if (v.startsWith("p:")) {
            var p = presetNamed(v.substring(2));
            if (p == null) return;
            edit((x) => p.onto(x.copyWith(inside: {...x.inside}..remove("own")),
                target: p.aims ? target() : ""));
          }
        },
      ),
      // Shown edited too, so the settings -- and the screen over them --
      // keep their places as it is edited; picked, the preset again.
      if (!own && preset != null && preset.ways.isNotEmpty)
        StudioDrop<MotionWay>(
          key: const ValueKey("animPresetWay"),
          label: "Which way",
          value: _wayOf(c, preset),
          options: [for (var w in preset.ways) (w, w.label)],
          onChanged: (w) => edit((x) => preset.onto(x, way: w)),
        ),
      if (own && animates && directed)
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
      if (styled != null && c.kind == MotionKind.loop)
        StudioDrop<LoopPreset>(
          key: const ValueKey("ownLoop"),
          label: "Its own loop",
          value: styled.loop.preset,
          options: [
            for (var p in LoopPreset.values)
              (p, p == LoopPreset.none ? "None" : p.label)
          ],
          onChanged: (p) => styleTo(
              (s) => s.withLoop(s.loop.copyWith(preset: p)),
              asOwn: false),
        ),
    ];
  }

  /// _reset puts [c] back as its preset made it -- which way it goes, its
  /// name, speed, layer and launch kept -- or, its own style, that style's
  /// direction and reach as they start. Null where it is as it was made.
  VoidCallback? _reset(
      MotionClip c, ClipEditFn edit, String Function() target) {
    if (c.isSound) return null;
    var e = element;
    if (c.inside["own"] == true && c.keys.isEmpty) {
      var styled = OwnStyle.of(e);
      if (styled == null) return null;
      if (!CanvasController.animates(e)) {
        var leaving = c.kind == MotionKind.leave;
        if (styled.strength(leaving: leaving) == 1) return null;
        return () {
          controller.beginInteraction();
          controller.replaceElement(styled.withStrength(1, leaving: leaving));
          controller.endInteraction();
        };
      }
      var a = CanvasController.elementAnimationOf(e);
      var arriving = c.kind == MotionKind.arrive;
      var changed = arriving
          ? a.direction != null || a.strength != 1
          : a.exitStrength != 1;
      if (!changed) return null;
      return () {
        controller.beginInteraction();
        controller.setElementAnimation(
            e.id,
            arriving
                ? a.copyWith(clearDirection: true, strength: 1)
                : a.copyWith(exitStrength: 1));
        controller.endInteraction();
      };
    }
    var p = presetNamed(c.preset);
    if (p == null) return null;
    MotionWay? way(MotionClip x) => p.ways.isEmpty ? null : _wayOf(x, p);
    var fresh = p.onto(c, way: way(c), target: p.aims ? target() : "");
    if (jsonEncode(fresh.toJson()) == jsonEncode(c.toJson())) return null;
    return () =>
        edit((x) => p.onto(x, way: way(x), target: p.aims ? target() : ""));
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
  final _focus = FocusNode(debugLabel: "clipName");

  @override
  void didUpdateWidget(_ClipName old) {
    super.didUpdateWidget(old);
    if (widget.name != _text.text && !_focus.hasFocus) {
      _text.text = widget.name;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    var panel = ChainPanelStyle.on(context);
    // Laid out as a StudioDrop is -- its label over a box 22 high -- to
    // line up with the dropdowns beside it (Ken). One line: Return keeps
    // the name and leaves it, Escape leaves it as it was (Ken: it could not
    // be left once renamed).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: panel ? 4 : 3),
          child: Text("Name",
              maxLines: 1,
              style: TextStyle(fontSize: panel ? 11.5 : 10, color: s.muted)),
        ),
        Container(
          key: const ValueKey("animClipNameBox"),
          height: panel ? 30 : 22,
          padding: EdgeInsets.symmetric(horizontal: panel ? 9 : 7),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              color: s.inset,
              borderRadius: BorderRadius.circular(panel ? 7 : 4),
              border: Border.all(color: s.edge)),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                _text.text = widget.name;
                _focus.unfocus();
              },
            },
            child: TextField(
              key: const ValueKey("animClipName"),
              controller: _text,
              focusNode: _focus,
              maxLines: 1,
              style: TextStyle(fontSize: panel ? 12.5 : 11, color: s.text),
              decoration: const InputDecoration.collapsed(hintText: ""),
              onSubmitted: (v) {
                widget.onNamed(v);
                _focus.unfocus();
              },
              onTapOutside: (_) {
                if (!_focus.hasFocus) return;
                if (_text.text != widget.name) widget.onNamed(_text.text);
                _focus.unfocus();
              },
            ),
          ),
        ),
      ],
    );
  }
}
