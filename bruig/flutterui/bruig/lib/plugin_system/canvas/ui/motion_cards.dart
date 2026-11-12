import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart'
    show Quantise;
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show KeyframeEasing;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show boxOf;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart' show CopyValue;
import 'package:bruig/plugin_system/canvas/model/layer_blend.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// motion_cards.dart is the Motion chain's Source and Output as the chain
// prototype draws them (Ken, 2026-11-08: "the motion panel design is very
// off"): Timing, Launch and Place as studio cards with a screen, knobs and
// lists -- every setting the old sections had -- and the Output: how much of
// it is seen, and whether it is shown at all.

/// ClipEdit changes the clip shown: live while a knob is dragged, one undo
/// step otherwise.
typedef ClipEdit = void Function(MotionClip Function(MotionClip) change,
    {bool live});

/// StudioDrop is a list to pick from, as the prototype's cards have them: a
/// small name over a boxed choice. [key] is the box's; each item is keyed
/// "[key]-[value's index]".
class StudioDrop<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double width;
  const StudioDrop(
      {required this.label,
      required this.value,
      required this.options,
      required this.onChanged,
      this.width = 150,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var name = (key as ValueKey?)?.value ?? label;
    // In the Motion view, as the settings panel's selects (Ken,
    // 2026-11-12): see ChainPanelStyle.
    var panel = ChainPanelStyle.on(context);
    // Where it is given a row too short for the panel's height -- a
    // trigger's line -- it keeps the compact one.
    return LayoutBuilder(
        builder: (context, box) => _drop(context, look, s, name,
            panel && box.maxHeight >= (label.isEmpty ? 30 : 52)));
  }

  Widget _drop(BuildContext context, MixerLook look, StudioColors s,
      String name, bool panel) {
    var shown =
        options.where((o) => o.$1 == value).firstOrNull?.$2 ?? options.first.$2;
    return SizedBox(
      width: width,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: panel ? 4 : 3),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: panel ? 11.5 : 10, color: s.muted)),
              ),
            MenuAnchor(
              style: chainMenuStyle(look),
              menuChildren: [
                for (var (i, (v, t)) in options.indexed)
                  chainMenuItem(look,
                      key: ValueKey("$name-$i"),
                      text: t,
                      current: v == value,
                      onPressed: () => onChanged(v)),
              ],
              builder: (context, menu, _) => InkWell(
                key: key == null ? null : ValueKey("$name-open"),
                borderRadius: BorderRadius.circular(panel ? 7 : 4),
                onTap: () => menu.isOpen ? menu.close() : menu.open(),
                child: Container(
                  height: panel ? 30 : 22,
                  padding: EdgeInsets.only(left: panel ? 9 : 7, right: 2),
                  decoration: BoxDecoration(
                      color: s.inset,
                      borderRadius: BorderRadius.circular(panel ? 7 : 4),
                      border: Border.all(color: s.edge)),
                  child: Row(children: [
                    Expanded(
                      child: Text(shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: panel ? 12.5 : 11, color: s.text)),
                    ),
                    Icon(panel ? Icons.expand_more : Icons.arrow_drop_down,
                        size: panel ? 17 : 15, color: s.muted),
                  ]),
                ),
              ),
            ),
          ]),
    );
  }
}

const _motionAccent = Color(0xFF3FB08D);

/// MotionTimingCard is when [clip] plays: its length and whether it loops;
/// what it shows before it starts and after it ends; and, placed on the
/// timeline, where its start and end are pinned.
class MotionTimingCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MotionClip clip;
  final ClipEdit edit;
  final double height;
  final bool folded;
  final VoidCallback onFold;
  const MotionTimingCard(
      {required this.controller,
      required this.element,
      required this.clip,
      required this.edit,
      required this.height,
      required this.folded,
      required this.onFold,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var c = clip, e = element;
    var placeId = controller.pickedPlacement;
    var p = placeId == null ? null : e.base.motion.placement(placeId);
    var span = placeId == null ? null : controller.spanOf(placeId);
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
          if (x.id != placeId)
            (
              "after:${x.id}",
              "End of ${o.name.isEmpty ? o.id : o.name} · ${o.base.motion.clip(x.clip)?.name ?? ""}"
            ),
    ];
    var ends = [
      ("", "Its own length"),
      ("sceneEnd", "The scene's end"),
      for (var x in pins.skip(2)) x,
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

    List<Widget> controls(DeviceTier tier) => [
          DevicePack(key: const ValueKey("motionTimingPack"), children: [
            DeviceKnob(
              key: const ValueKey("animClipLength"),
              label: "Length",
              text: "${c.length.toStringAsFixed(2)}s",
              value: c.length,
              initial: 1,
              min: 0.05,
              max: 30,
              log: true,
              accent: _motionAccent,
              ink: skin.ink,
              onChanged: (v, {transient = false}) => edit(
                  (x) => x.retimed((v * 100).roundToDouble() / 100),
                  live: transient),
              onCommit: controller.endInteraction,
            ),
            StudioDrop<bool>(
              key: const ValueKey("animClipLoop"),
              label: "Plays",
              value: c.loop,
              options: const [(false, "Once"), (true, "Round and round")],
              onChanged: (v) => edit((x) => x.copyWith(loop: v)),
            ),
            if (!c.isSound) ...[
              StudioDrop<ClipHold>(
                key: const ValueKey("animBefore"),
                label: "Before it starts",
                value: c.before,
                options: const [
                  (ClipHold.rest, "As it is"),
                  (ClipHold.first, "Holds its first frame")
                ],
                onChanged: (h) => edit((x) => x.copyWith(before: h)),
              ),
              StudioDrop<ClipHold>(
                key: const ValueKey("animAfter"),
                label: "After it ends",
                value: c.after,
                options: const [
                  (ClipHold.rest, "Back as it is"),
                  (ClipHold.last, "Holds its last frame")
                ],
                onChanged: (h) => edit((x) => x.copyWith(after: h)),
              ),
            ],
            if (p != null && span != null) ...[
              // Where it starts, as a number: the sidebar's Delay (Ken,
              // 2026-11-08). Moved here, it lets go of its pins.
              DeviceKnob(
                key: const ValueKey("animStart"),
                label: "Starts",
                text: "${span.start.toStringAsFixed(2)}s",
                value: span.start,
                initial: 0,
                min: 0,
                max: math.max(
                    1.0,
                    controller.document.frames /
                        math.max(1, controller.document.frameRate)),
                accent: _motionAccent,
                ink: skin.ink,
                onChanged: (v, {transient = false}) {
                  controller.beginInteraction();
                  controller.movePlacement(
                      e.id, p.id, (v * 20).roundToDouble() / 20,
                      transient: true);
                  if (!transient) controller.endInteraction();
                },
                onCommit: controller.endInteraction,
              ),
              StudioDrop<String>(
                key: const ValueKey("animStartPin"),
                label: "Pinned to",
                width: 200,
                value: pins.any((x) => x.$1 == pinKey(p.startPin))
                    ? pinKey(p.startPin)
                    : "",
                options: pins,
                onChanged: (v) => controller.pinPlacement(e.id, p.id, pinOf(v)),
              ),
              StudioDrop<String>(
                key: const ValueKey("animEndPin"),
                label: "Ends at",
                width: 200,
                value: ends.any((x) => x.$1 == pinKey(p.endPin))
                    ? pinKey(p.endPin)
                    : "",
                options: ends,
                onChanged: (v) =>
                    controller.pinPlacement(e.id, p.id, pinOf(v), end: true),
              ),
            ],
            // Its own arrival tied to a word cue, or said on a word, and the
            // rest dimmed as it arrives: the sidebar's, in the chain.
            if (c.inside["own"] == true && c.kind == MotionKind.arrive) ...[
              if (controller.cues.isNotEmpty)
                StudioDrop<String>(
                  key: const ValueKey("animWordCue"),
                  label: "On word cue",
                  value: controller.cues.any((q) => q.id == e.base.cue)
                      ? e.base.cue
                      : "",
                  options: [
                    ("", "None"),
                    for (var q in controller.cues) (q.id, q.name),
                  ],
                  onChanged: (v) =>
                      controller.cueTo(e.id, v.isEmpty ? null : v),
                ),
              if (controller.words.isNotEmpty) ...[
                // Found by what is said, among every word; with nothing
                // looked for, the first of them in order.
                _WordFind(
                    key: const ValueKey("animWordFind"),
                    query: controller.wordQuery,
                    onChanged: (v) => controller.wordQuery = v),
                StudioDrop<int>(
                  key: const ValueKey("animOnWord"),
                  label: "On a word",
                  value: -1,
                  options: [
                    (
                      -1,
                      controller.wordQuery.isNotEmpty &&
                              controller
                                  .wordsMatching(controller.wordQuery)
                                  .isEmpty
                          ? "Not said"
                          : "Pick a word…"
                    ),
                    for (var w in controller.wordQuery.isEmpty
                        ? controller.words.take(200)
                        : controller.wordsMatching(controller.wordQuery,
                            most: 60))
                      (
                        controller.words.indexOf(w),
                        "${controller.wordQuery.isEmpty ? w.text : controller.wordInContext(w)} · ${(w.frame / math.max(1, controller.document.frameRate)).toStringAsFixed(1)}s"
                      ),
                  ],
                  onChanged: (i) {
                    if (i < 0) return;
                    controller.cueOnWord(e.id, controller.words[i]);
                    controller.wordQuery = "";
                  },
                ),
              ],
              PackWide(_DimButton(
                  key: const ValueKey("animDimOthers"),
                  onTap: () => controller.dimOthers(e.id))),
            ],
          ]),
        ];
    return DeviceFrame(
      id: "motionTiming",
      title: "Timing",
      help: "How long it is and whether it repeats; what it shows before it "
          "starts and after it ends. Placed on the timeline, its start and "
          "end can be pinned to markers, the scene, or another clip's end.",
      skin: skin,
      icon: Icons.schedule,
      accent: _motionAccent,
      folded: folded,
      onFold: onFold,
      width: 320,
      besideDisplay: 240,
      besideSettings: 300,
      height: height,
      summary: "${c.length.toStringAsFixed(2)} s${c.loop ? " · loops" : ""}",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: controls,
      // Where it sits, and -- placed -- its span in words at the foot.
      display: Stack(fit: StackFit.expand, children: [
        CustomPaint(
          key: const ValueKey("motionTimingSpan"),
          painter: _SpanPainter(
              span == null ? null : (span.start, span.end),
              controller.document.frames /
                  math.max(1, controller.document.frameRate),
              c.length,
              c.loop,
              look.studio),
          child: const SizedBox.expand(),
        ),
        if (p != null && span != null)
          Positioned(
            left: 6,
            right: 6,
            bottom: 4,
            child: Text(
                "${span.start.toStringAsFixed(2)}–${span.end.toStringAsFixed(2)} s · "
                "${c.loop ? "repeats to fill it" : "retimed to fit: ${span.speed.toStringAsFixed(2)}×"}",
                key: const ValueKey("animSpanText"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: look.studio.muted)),
          ),
      ]),
    );
  }
}

/// _DimButton fades everything already on the canvas as the element
/// arrives, and keeps it there.
/// _WordFind is a one-line box to look for a word said by: what is typed
/// narrows "On a word" to the words it is found in.
class _WordFind extends StatefulWidget {
  final String query;
  final ValueChanged<String> onChanged;
  const _WordFind({required this.query, required this.onChanged, super.key});

  @override
  State<_WordFind> createState() => _WordFindState();
}

class _WordFindState extends State<_WordFind> {
  late final _text = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(_WordFind old) {
    super.didUpdateWidget(old);
    if (widget.query != _text.text) _text.text = widget.query;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text("Find a word",
                maxLines: 1, style: TextStyle(fontSize: 10, color: s.muted)),
          ),
          Container(
            height: 22,
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: s.inset,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: s.edge)),
            child: TextField(
              controller: _text,
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: s.text),
              decoration: InputDecoration.collapsed(
                  hintText: "what is said",
                  hintStyle: TextStyle(fontSize: 11, color: s.muted)),
              onChanged: widget.onChanged,
            ),
          ),
        ]);
  }
}

class _DimButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DimButton({required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: s.raised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: s.edge)),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text("Dim the others as it arrives",
                style: TextStyle(fontSize: 10.5, color: s.text)),
          ),
        ),
      ),
    );
  }
}

/// _SpanPainter is where the clip sits in its scene: placed, its span along
/// the scene; in a slot, its own length, repeated where it loops.
class _SpanPainter extends CustomPainter {
  final (double, double)? span;
  final double scene, length;
  final bool loop;
  final StudioColors studio;
  _SpanPainter(this.span, this.scene, this.length, this.loop, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var grid = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 1; i < 8; i++) {
      canvas.drawRect(Rect.fromLTWH(i * w / 8, 0, 1, h), grid);
    }
    var tp = TextPainter(
        text: TextSpan(
            text: span == null ? "in a slot: its own length" : "scene start",
            style: TextStyle(fontSize: 10, color: studio.muted)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, const Offset(6, 5));
    var fill = Paint()..color = _motionAccent.withValues(alpha: 0.3);
    var edge = Paint()
      ..style = PaintingStyle.stroke
      ..color = _motionAccent;
    var total = math.max(0.1, span == null ? length * (loop ? 3 : 1.5) : scene);
    var parts = span == null
        ? [
            for (var i = 0; i < (loop ? 3 : 1); i++)
              (i * length, (i + 1) * length)
          ]
        : [span!];
    for (var (i, (a, b)) in parts.indexed) {
      var r = Rect.fromLTRB(w * a / total + 4, h * 0.42,
          math.max(w * a / total + 8, w * b / total - 2), h * 0.62);
      canvas.drawRect(
          r,
          i == 0
              ? fill
              : (Paint()..color = fill.color.withValues(alpha: 0.12)));
      canvas.drawRect(r, edge);
    }
  }

  @override
  bool shouldRepaint(_SpanPainter old) =>
      old.span != span || old.length != length || old.loop != loop;
}

/// MotionLaunchCard is what starts [clip] from its slot: the triggers it
/// answers -- listed on its screen -- and a press's way, what it waits for
/// and what comes after it.
class MotionLaunchCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MotionClip clip;
  final ClipEdit edit;
  final double height;
  final bool folded;
  final VoidCallback onFold;
  final String Function(ClipTrigger) triggerName;
  const MotionLaunchCard(
      {required this.controller,
      required this.element,
      required this.clip,
      required this.edit,
      required this.height,
      required this.folded,
      required this.onFold,
      required this.triggerName,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var skin = DeviceSkin.studio(s);
    var c = clip, e = element;
    var mates = [
      for (var o in e.base.motion.clips)
        if (o.id != c.id) o
    ];
    var adds = <(String, String)>[
      ("", "Add a trigger…"),
      (ClipTriggerKind.sceneStarts.name, ClipTriggerKind.sceneStarts.label),
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
            ("${ClipTriggerKind.clipEnds.name}:${x.id}", "When ${x.name} ends"),
      (ClipTriggerKind.touched.name, ClipTriggerKind.touched.label),
      for (var n in controller.document.counts)
        (
          "${ClipTriggerKind.count.name}:${n.id}",
          "${n.name.isEmpty ? n.id : n.name} changes"
        ),
    ];
    // Its screen: the triggers, a row each, as the prototype lists them.
    var screen = Container(
      color: s.display,
      padding: const EdgeInsets.all(6),
      child: ListView(children: [
        for (var (i, t) in c.triggers.indexed)
          Container(
            key: ValueKey("animTrigger-$i"),
            height: 24,
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.only(left: 8),
            color: s.raised,
            child: Row(children: [
              Expanded(
                child: Text(triggerName(t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: s.text)),
              ),
              // A count's: any change, or as it reaches a number.
              if (t.kind == ClipTriggerKind.count)
                StudioDrop<double>(
                  key: ValueKey("animTriggerAmount-$i"),
                  label: "",
                  width: 72,
                  value: t.amount,
                  options: [
                    (0, "Any"),
                    for (var n in const [
                      1.0,
                      3.0,
                      5.0,
                      10.0,
                      20.0,
                      50.0,
                      100.0
                    ])
                      (n, "At ${n.round()}"),
                    if (![0.0, 1.0, 3.0, 5.0, 10.0, 20.0, 50.0, 100.0]
                        .contains(t.amount))
                      (t.amount, "At ${t.amount.round()}"),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(triggers: [
                        for (var (j, y) in x.triggers.indexed)
                          j == i
                              ? ClipTrigger(y.kind,
                                  target: y.target, amount: v.roundToDouble())
                              : y,
                      ])),
                ),
              IconButton(
                key: ValueKey("animTriggerRemove-$i"),
                visualDensity: VisualDensity.compact,
                iconSize: 13,
                icon: Icon(Icons.close, color: s.muted),
                tooltip: "Remove",
                onPressed: () => edit(
                    (x) => x.copyWith(triggers: [...x.triggers]..removeAt(i))),
              ),
            ]),
          ),
        if (c.triggers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text("Only its slot starts it: add a trigger below.",
                style: TextStyle(fontSize: 11, color: s.muted)),
          ),
      ]),
    );
    List<Widget> controls(DeviceTier tier) => [
          DevicePack(key: const ValueKey("motionLaunchPack"), children: [
            StudioDrop<ClipLaunch>(
              key: const ValueKey("animLaunch"),
              label: "Pressed",
              value: c.launch,
              options: [for (var l in ClipLaunch.values) (l, l.label)],
              onChanged: (l) => edit((x) => x.copyWith(launch: l)),
            ),
            StudioDrop<String>(
              key: const ValueKey("animQuantise"),
              label: "Waits for",
              value: c.quantise ?? "",
              options: [
                ("", "The timeline's setting"),
                for (var q in Quantise.values)
                  (
                    q.name,
                    q == Quantise.off ? "Nothing" : "The next ${q.label}"
                  ),
              ],
              onChanged: (q) =>
                  edit((x) => x.copyWith(quantise: () => q.isEmpty ? null : q)),
            ),
            StudioDrop<String>(
              key: const ValueKey("animThen"),
              label: "Then",
              value:
                  c.then == ClipThen.play ? "play:${c.thenClip}" : c.then.name,
              options: [
                for (var t in ClipThen.values)
                  if (t != ClipThen.play) (t.name, t.label),
                for (var o in mates) ("play:${o.id}", "Plays ${o.name}"),
              ],
              onChanged: (v) => edit((x) => v.startsWith("play:")
                  ? x.copyWith(then: ClipThen.play, thenClip: v.substring(5))
                  : x.copyWith(then: ClipThen.fromName(v), thenClip: "")),
            ),
            StudioDrop<String>(
              key: const ValueKey("animTriggerAdd"),
              label: "Also starts when",
              width: 200,
              value: "",
              options: adds,
              onChanged: (v) {
                if (v.isEmpty) return;
                var parts = v.split(":");
                var kind = ClipTriggerKind.fromName(parts[0])!;
                edit((x) => x.copyWith(triggers: [
                      ...x.triggers,
                      ClipTrigger(kind,
                          target: parts.length > 1
                              ? parts.sublist(1).join(":")
                              : ""),
                    ]));
              },
            ),
          ]),
        ];
    return DeviceFrame(
      id: "motionLaunch",
      title: "Launch",
      help: "What starts it from its slot besides a press: the scene "
          "starting, a click, a key, another clip ending, a player's touch, "
          "a count. A press starts it, plays it while held, toggles it or "
          "repeats it; Then says what comes after.",
      skin: skin,
      icon: Icons.bolt,
      accent: _motionAccent,
      folded: folded,
      onFold: onFold,
      width: 320,
      besideDisplay: 240,
      besideSettings: 300,
      height: height,
      summary: "${c.launch.label} · ${c.triggers.length} trigger"
          "${c.triggers.length == 1 ? "" : "s"}",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: controls,
      display: screen,
    );
  }
}

/// MotionPlaceCard is where [clip] moves from: where the element is, so one
/// clip works on any element, or to set places on the page.
class MotionPlaceCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MotionClip clip;
  final ClipEdit edit;
  final double height;
  final bool folded;
  final VoidCallback onFold;
  const MotionPlaceCard(
      {required this.controller,
      required this.element,
      required this.clip,
      required this.edit,
      required this.height,
      required this.folded,
      required this.onFold,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var c = clip, e = element;
    var leaving = c.kind == MotionKind.leave;
    var place = placeOf(c);
    var others = [
      for (var x in controller.document.elements)
        if (x.id != e.id) x,
    ];
    return DeviceFrame(
      id: "motionPlace",
      title: "Place",
      help: "From where it is, one clip works on any element, wherever it "
          "stands. To set places, its keys are spots on the page.",
      skin: skin,
      icon: Icons.place_outlined,
      accent: _motionAccent,
      folded: folded,
      onFold: onFold,
      width: 240,
      height: height,
      summary: switch (placeOf(c)) {
        var p? => "${leaving ? "To" : "From"} ${p.kind.label.toLowerCase()}",
        null => c.absolute ? "To set places" : "From where it is",
      },
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        // Where it comes from -- or, leaving, goes to -- worked out as it
        // plays: an edge, beside another element, on its ground. The
        // prototype's From and Offset.
        DevicePack(key: const ValueKey("animPlacePack"), children: [
          StudioDrop<String>(
            key: const ValueKey("animPlaceFrom"),
            label: leaving ? "To" : "From",
            value: place?.kind.name ?? "",
            options: [
              ("", "Where it is"),
              for (var k in _placeKinds) (k.name, k.label),
            ],
            onChanged: (name) {
              var kind = MotionPlaceKind.fromName(name);
              var target = kind != null && kind.needsTarget
                  ? (place?.target.isNotEmpty == true
                      ? place!.target
                      : others.firstOrNull?.id ?? "")
                  : "";
              edit((x) => withPlace(x, kind, boxOf(e),
                  target: target, by: place?.by ?? 0));
            },
          ),
          if (place != null && place.kind.needsTarget)
            StudioDrop<String>(
              key: const ValueKey("animPlaceOf"),
              label: "Of",
              value:
                  others.any((x) => x.id == place.target) ? place.target : "",
              options: [
                if (!others.any((x) => x.id == place.target)) ("", "Pick one"),
                for (var x in others) (x.id, x.name.isEmpty ? x.id : x.name),
              ],
              onChanged: (id) => edit((x) =>
                  withPlace(x, place.kind, boxOf(e), target: id, by: place.by)),
            ),
          if (place != null)
            DeviceKnob(
              key: const ValueKey("animPlaceOffset"),
              label: "Offset",
              text: "${place.by.round()} px",
              value: place.by.clamp(-200.0, 200.0),
              initial: 0,
              min: -200,
              max: 200,
              accent: _motionAccent,
              ink: skin.ink,
              bipolar: true,
              onChanged: (v, {transient = false}) => edit(
                  (x) => withPlace(x, place.kind, boxOf(e),
                      target: place.target, by: v.roundToDouble()),
                  live: transient),
              onCommit: controller.endInteraction,
            ),
        ]),
        StudioDrop<bool>(
          key: const ValueKey("animPlace"),
          label: "Moves",
          value: c.absolute,
          options: const [(false, "From where it is"), (true, "To set places")],
          onChanged: (abs) {
            // Every key kept where it lands, written the other way.
            var box = boxOf(e);
            MotionKey turn(MotionKey k, double by) => switch (k.value) {
                  MotionNumber(:var value) => k.copyWith(
                      value: MotionNumber(abs ? value + by : value - by)),
                  _ => k,
                };
            edit((x) => x.copyWith(absolute: abs, keys: {
                  for (var MapEntry(:key, :value) in x.keys.entries)
                    key: key == MotionProp.x
                        ? [for (var k in value) turn(k, box.center.dx)]
                        : key == MotionProp.y
                            ? [for (var k in value) turn(k, box.center.dy)]
                            : value,
                }));
          },
        ),
      ],
    );
  }
}

/// _placeKinds are the places From offers: the edges, and by another.
const _placeKinds = [
  MotionPlaceKind.offLeft,
  MotionPlaceKind.offRight,
  MotionPlaceKind.offTop,
  MotionPlaceKind.offBottom,
  MotionPlaceKind.beside,
  MotionPlaceKind.ground,
];

/// placeOf is the place [c] comes from -- its first keys across and up and
/// down -- or, leaving, goes to (its last): null for where it is.
MotionPlace? placeOf(MotionClip c) {
  var leaving = c.kind == MotionKind.leave;
  for (var prop in const [MotionProp.x, MotionProp.y]) {
    var keys = c.keys[prop];
    if (keys == null || keys.isEmpty) continue;
    if ((leaving ? keys.last : keys.first).value case MotionPlace p) return p;
  }
  return null;
}

/// withPlace is [c] coming from [kind] -- or, leaving, going to it -- of
/// [target], [by] pixels on: its first keys across and up and down made the
/// place (its last, leaving), keys made where it has none. Null puts it
/// back where it is ([box], the element's, for a clip of set places).
MotionClip withPlace(MotionClip c, MotionPlaceKind? kind, Rect box,
    {String target = "", double by = 0}) {
  var leaving = c.kind == MotionKind.leave;
  var place = kind == null ? null : MotionPlace(kind, target: target, by: by);
  var keys = {...c.keys};
  for (var prop in const [MotionProp.x, MotionProp.y]) {
    // Where it is, in the clip's own terms: nought from it, or its centre.
    var still = MotionNumber(!c.absolute
        ? 0
        : prop == MotionProp.x
            ? box.center.dx
            : box.center.dy);
    var want = place != null && place.moves(prop) ? place : null;
    var list = [...?keys[prop]];
    if (list.isEmpty) {
      if (want == null) continue;
      var end = math.max(0.05, c.length);
      keys[prop] = leaving
          ? [
              MotionKey(0, still),
              MotionKey(end, want, ease: KeyframeEasing.easeIn),
            ]
          : [
              MotionKey(0, want),
              MotionKey(end, still, ease: KeyframeEasing.easeOut),
            ];
      continue;
    }
    var at = leaving ? list.length - 1 : 0;
    if (want != null) {
      list[at] = list[at].copyWith(value: want);
    } else if (list[at].value is MotionPlace) {
      list[at] = list[at].copyWith(value: still);
    }
    keys[prop] = list;
  }
  return c.copyWith(keys: keys, edited: true);
}

/// MotionOutputCard is where the chain ends, as the prototype's Output: how
/// much of the element is seen, and whether it is shown at all.
class MotionOutputCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final double height;
  final bool folded;
  final VoidCallback onFold;
  const MotionOutputCard(
      {required this.controller,
      required this.element,
      required this.height,
      required this.folded,
      required this.onFold,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var skin = DeviceSkin.studio(s);
    var e = element;
    var elements = controller.document.elements;
    var at = elements.indexWhere((x) => x.id == e.id);
    var under = at > 0 ? elements[at - 1] : null;
    void write(CanvasElement next, {bool transient = false}) {
      controller.beginInteraction();
      controller.replaceElement(next, transient: true);
      if (!transient) controller.endInteraction();
    }

    Widget row(String label, String value) => Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 10.5, color: s.muted))),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: s.text)),
          ),
        ]);
    return DeviceFrame(
      id: "motionOutput",
      title: "Output",
      help: "Where its chain ends: how much of it is seen, whether it is "
          "shown, and what it is drawn over.",
      skin: skin,
      icon: Icons.output,
      accent: const Color(0xFFCFCBDF),
      folded: folded,
      onFold: onFold,
      width: 190,
      height: height,
      summary: "${(e.opacity * 100).round()}% · ${e.base.blend.label}",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        // With copies picked, how much of them is seen: theirs.
        if (controller.copiesPicked(e.id))
          DeviceKnob(
            key: const ValueKey("motionOutputOpacity"),
            label: "Opacity",
            text:
                "${(controller.copyValue(e.id, CopyValue.opacity) * 100).round()}%",
            value: controller.copyValue(e.id, CopyValue.opacity),
            initial: 1,
            min: 0,
            max: 1,
            own: controller.copyOwnOf(e.id, CopyValue.opacity.name) != null,
            accent: const Color(0xFFCFCBDF),
            ink: skin.ink,
            onChanged: (v, {transient = false}) {
              controller.beginInteraction();
              controller.setCopyOwn(
                  e.id, CopyValue.opacity.name, (v * 100).roundToDouble() / 100,
                  transient: true);
              if (!transient) controller.endInteraction();
            },
            onCommit: controller.endInteraction,
          )
        else
          DeviceKnob(
            key: const ValueKey("motionOutputOpacity"),
            label: "Opacity",
            text: "${(e.opacity * 100).round()}%",
            value: e.opacity,
            initial: 1,
            min: 0,
            max: 1,
            accent: const Color(0xFFCFCBDF),
            ink: skin.ink,
            onChanged: (v, {transient = false}) => write(
                e.withBase(opacity: (v * 100).roundToDouble() / 100),
                transient: transient),
            onCommit: controller.endInteraction,
          ),
        StudioDrop<bool>(
          key: const ValueKey("motionOutputShown"),
          label: "Shown",
          width: 160,
          value: e.visible,
          options: const [(true, "Yes"), (false, "Hidden")],
          onChanged: (v) => write(e.withBase(visible: v)),
        ),
        // How it is laid over what is under it, as the prototype's Blend.
        StudioDrop<LayerBlend>(
          key: const ValueKey("motionOutputBlend"),
          label: "Blend",
          width: 160,
          value: e.base.blend,
          options: [for (var b in LayerBlend.values) (b, b.label)],
          onChanged: (b) => write(e.withBase(blend: b)),
        ),
        SizedBox(
          width: 160,
          child: row(
              "Drawn over",
              under == null
                  ? "the page"
                  : (under.name.isEmpty ? under.id : under.name)),
        ),
      ],
    );
  }
}
