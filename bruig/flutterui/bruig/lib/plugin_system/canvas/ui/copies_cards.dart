import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show MovedElement, poseWithMotion;
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show paintElement;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

// copies_cards.dart is an element's Instances and Drawing in its Chain, as
// the chain prototype draws them (Ken, 2026-11-08).
//
// Instances is the first card of the chain: the element and its copies, the
// picker for what the rest of the chain edits. Placed once it says so, with
// Reuse… and + Place another. Reused, it lists the copies -- the element
// first, for all of them -- with what each has of its own; it adds copies
// (a click on the canvas places each), lays them out, and says how they
// differ: by order, at random, from the middle. Picked, a copy's own start,
// speed, size, turn, opacity and colour are its knobs, with a dot where they
// are its own and Revert to take them back.
//
// Drawing is where the element becomes pixels: the copies drawn as the page
// draws them, its Size, and whether it is drawn once and stamped at each
// copy or drawn for each.

const _instancesAccent = Color(0xFF6FA8FF);

/// InstancesCard is [element]'s copies, first of its chain.
class InstancesCard extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const InstancesCard({
    required this.controller,
    required this.element,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  void _step(VoidCallback change) {
    controller.beginInteraction();
    change();
    controller.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    var skin = DeviceSkin.studio(studio);
    var set = controller.motionOf(element).instances;
    var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var placing = controller.placingCopies == element;
    var picked = controller.pickedCopiesOf(element);
    var muted = TextStyle(fontSize: 10.5, height: 1.4, color: studio.muted);
    void place() => controller.placingCopies = placing ? null : element;

    // Not reused yet: a slim card, its two ways to start -- the full card
    // once there are copies (Ken, 2026-11-12: less in the way).
    if (set == null && ChainPanelStyle.on(context)) {
      return Container(
        width: 104 * scale,
        height: height,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: studio.edge),
        ),
        child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text("Copies",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: studio.text)),
              const SizedBox(height: 4),
              Text("Placed once", style: muted),
              const SizedBox(height: 8),
              CopyButton(
                  key: const ValueKey("instancesReuse"),
                  label: "Reuse…",
                  main: true,
                  onTap: () =>
                      _step(() => controller.reuseElement(element, 5))),
              const SizedBox(height: 5),
              CopyButton(
                  key: const ValueKey("instancesPlace"),
                  label: placing ? "Placing…" : "+ Place",
                  on: placing,
                  onTap: place),
            ])),
      );
    }

    List<Widget> once(DeviceTier tier) => [
          PackWide(Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Text("Placed", style: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text("once · this one",
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: studio.text)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                    "Reuse it to place more of the same: still one channel "
                    "and one chain, each copy keeping its own place and "
                    "start.",
                    style: muted),
                const SizedBox(height: 8),
                Wrap(spacing: 5, runSpacing: 5, children: [
                  CopyButton(
                      key: const ValueKey("instancesReuse"),
                      label: "Reuse…",
                      main: true,
                      onTap: () =>
                          _step(() => controller.reuseElement(element, 5))),
                  CopyButton(
                      key: const ValueKey("instancesPlace"),
                      label: placing ? "Placing… (Esc)" : "+ Place another",
                      on: placing,
                      onTap: place),
                ]),
              ])),
        ];

    List<Widget> many(InstanceSet set, DeviceTier tier) => [
          PackWide(Wrap(spacing: 5, runSpacing: 5, children: [
            CopyButton(
                key: const ValueKey("instancesPlace"),
                label: placing ? "Placing… (Esc)" : "+ Add",
                on: placing,
                onTap: place),
            SizedBox(
              width: 104,
              child: StudioDrop<InstanceLayout?>(
                key: const ValueKey("instancesLayout"),
                label: "",
                value: null,
                options: [
                  (null, "Lay out…"),
                  for (var l in InstanceLayout.values) (l, l.label),
                ],
                onChanged: (l) {
                  if (l != null) {
                    _step(() => controller.layOutInstances(element, l));
                  }
                },
              ),
            ),
            if (picked.isEmpty)
              CopyButton(
                  key: const ValueKey("instancesOnce"),
                  label: "Back to one",
                  onTap: () =>
                      _step(() => controller.setInstances(element, null))),
            if (picked.isEmpty &&
                set.vary.values.any((v) => v.how == VaryHow.random))
              CopyButton(
                  key: const ValueKey("instancesReroll"),
                  label: "Re-roll",
                  onTap: () => _step(() => controller.setInstances(
                      element, set.copyWith(seed: set.seed + 1)))),
            if (picked.isNotEmpty) ...[
              CopyButton(
                  key: const ValueKey("copiesRevert"),
                  label: "Revert",
                  onTap: set.items
                          .any((x) => picked.contains(x.id) && x.own.isNotEmpty)
                      ? () => _step(() => controller.revertCopies(element))
                      : null),
              CopyButton(
                  key: const ValueKey("copiesRemove"),
                  label: picked.length == 1 ? "Remove it" : "Remove them",
                  onTap: () =>
                      _step(() => controller.removeCopies(element, picked))),
            ],
          ])),
          if (picked.isEmpty)
            for (var w in VaryWhat.values)
              PackWide(_VaryRow(
                controller: controller,
                element: element,
                set: set,
                what: w,
                accent: _instancesAccent,
                ink: skin.ink,
              ))
          else
            DevicePack(key: const ValueKey("copyKnobs"), children: [
              for (var v in CopyValue.values) _copyKnob(v, skin.ink, tier),
            ]),
        ];

    var varied = set == null
        ? 0
        : VaryWhat.values
            .where((w) => set.varyOf(w).how != VaryHow.same)
            .length;
    return DeviceFrame(
      id: "instances",
      title: set == null ? "Instances" : "Instances ×${set.count}",
      help: "The element and its copies, and what the rest of the chain "
          "edits: the element for all of them, or the copies picked -- here "
          "or on the canvas, Shift for more. A picked copy's knobs, all along "
          "the chain, are its own: a dot shows one, Revert takes them back. "
          "Placing, each click on the canvas puts a copy there; Alt-drag a "
          "copy for another.",
      skin: skin,
      folded: folded,
      onFold: onFold,
      width: (set == null ? 250 : 430) * scale,
      height: height,
      // Its copies listed down its left, the full height; its settings
      // beside them.
      displayBeside: true,
      besideDisplay: 250,
      besideSettings: 320,
      icon: Icons.copy_all_outlined,
      accent: _instancesAccent,
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => set == null ? once(tier) : many(set, tier),
      display: set == null
          ? null
          : _CopiesTable(
              key: const ValueKey("copiesTable"),
              controller: controller,
              element: element,
              set: set,
              picked: picked),
      summary: set == null
          ? "placed once"
          : picked.isNotEmpty
              ? "editing ${picked.length} of ${set.count}"
              : "×${set.count}${varied == 0 ? " · alike" : " · $varied vary"}",
    );
  }

  /// _copyKnob is [v] of the picked copies: their own, or as the set has it,
  /// turned to be their own.
  Widget _copyKnob(CopyValue v, Color ink, DeviceTier tier) {
    var value = controller.copyValue(element, v);
    var own = controller.copyOwnOf(element, v.name) != null;
    String reading(double x) => switch (v.unit) {
          "s" => "${x.toStringAsFixed(2)} s",
          "×" => "${x.toStringAsFixed(2)}×",
          "%" => "${(x * 100).round()}%",
          _ => "${x.round()}°",
        };
    return DeviceKnob(
      key: ValueKey("copyKnob-${v.name}"),
      label: v.label,
      text: reading(value),
      value: value.clamp(v.min, v.max),
      initial: v.initial,
      min: v.min,
      max: v.max,
      // As big as every other device's at this height.
      size: switch (tier) {
        DeviceTier.large => 46,
        DeviceTier.medium => 38,
        _ => 30,
      },
      own: own,
      bipolar: v.min < 0,
      accent: _instancesAccent,
      ink: ink,
      menu: [
        if (own)
          (
            "Back to the shared value",
            () => _step(() => controller.setCopyOwn(element, v.name, null))
          ),
      ],
      onChanged: (x, {transient = false}) {
        controller.beginInteraction();
        controller.setCopyOwn(element, v.name, x, transient: true);
        if (!transient) controller.endInteraction();
      },
      onCommit: controller.endInteraction,
    );
  }
}

/// CopyButton is a small button of the Instances card.
class CopyButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool on, main;
  const CopyButton(
      {required this.label,
      required this.onTap,
      this.on = false,
      this.main = false,
      super.key});

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    var lit = on || main;
    return Material(
      color: lit ? _instancesAccent.withValues(alpha: 0.22) : s.raised,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: lit ? _instancesAccent : s.edge)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10.5, color: onTap == null ? s.muted : s.text)),
        ),
      ),
    );
  }
}

/// _VaryRow is one way the copies differ: its name, a bar for each copy as
/// far as it goes, how -- the same, by order, at random, from the middle --
/// and by at most how much.
class _VaryRow extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final InstanceSet set;
  final VaryWhat what;
  final Color accent, ink;
  const _VaryRow(
      {required this.controller,
      required this.element,
      required this.set,
      required this.what,
      required this.accent,
      required this.ink});

  String _reading(double v) => switch (what.unit) {
        "s" => "${v.toStringAsFixed(2)} s",
        "°" => "${v.round()}°",
        _ => "${v >= 0 ? "+" : "−"}${(v.abs() * 100).round()}%",
      };

  void _write(InstanceSet next, {bool transient = false}) {
    controller.beginInteraction();
    controller.setInstances(element, next, transient: true);
    if (!transient) controller.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    var vary = set.varyOf(what);
    // As tall as what is in it, at any text size.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 50,
          child: Text(what.label,
              style: TextStyle(fontSize: 10.5, color: s.muted)),
        ),
        Expanded(
          child: SizedBox(
            height: 18,
            child: CustomPaint(
              key: ValueKey("varyBars-${what.name}"),
              painter: _VaryBars(set, what, accent, s.edge),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 108,
          child: StudioDrop<VaryHow>(
            key: ValueKey("vary-${what.name}"),
            label: "",
            value: vary.how,
            options: [for (var h in VaryHow.values) (h, h.label)],
            onChanged: (h) => _write(set.withVary(what, Vary(h, vary.amount))),
          ),
        ),
        SizedBox(
          width: 54,
          child: vary.how == VaryHow.same
              ? null
              : DeviceKnob(
                  key: ValueKey("vary-${what.name}-amount"),
                  label: "",
                  text: _reading(vary.amount),
                  value: vary.amount,
                  initial: what.initial,
                  min: what.min,
                  max: what.max,
                  size: 30,
                  bipolar: what.min < 0,
                  accent: accent,
                  ink: ink,
                  onChanged: (v, {transient = false}) => _write(
                      set.withVary(what, Vary(vary.how, v)),
                      transient: transient),
                  onCommit: controller.endInteraction,
                ),
        ),
      ]),
    );
  }
}

/// _VaryBars is a bar for each copy, as tall as [what] goes for it: flat
/// where they are all the same.
class _VaryBars extends CustomPainter {
  final InstanceSet set;
  final VaryWhat what;
  final Color accent, edge;
  _VaryBars(this.set, this.what, this.accent, this.edge);

  @override
  void paint(Canvas canvas, Size size) {
    var n = math.min(set.count, 40);
    if (n == 0) return;
    var same = set.varyOf(what).how == VaryHow.same;
    var w = size.width / n;
    for (var i = 0; i < n; i++) {
      var v = same ? 0.3 : set.share(what, i).clamp(0.0, 1.0);
      var h = 2 + v * (size.height - 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  i * w + 0.5, size.height - h, math.max(1, w - 1.5), h),
              const Radius.circular(1)),
          Paint()..color = same ? edge : accent);
    }
  }

  @override
  bool shouldRepaint(_VaryBars old) =>
      old.set != set || old.what != what || old.accent != accent;
}

/// _CopiesTable is the element and its copies, a row each: the element's
/// for all of them, then each copy's place, start and speed as it plays,
/// a dot where it has something of its own. Clicked, a row is what the
/// chain edits; Shift picks more.
class _CopiesTable extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final InstanceSet set;
  final Set<String> picked;
  const _CopiesTable(
      {required this.controller,
      required this.element,
      required this.set,
      required this.picked,
      super.key});

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    var e = controller.document.elementById(element);
    if (e == null) return const SizedBox.expand();
    var head = TextStyle(fontSize: 9.5, color: s.muted, letterSpacing: 0.3);
    var cell = TextStyle(
        fontSize: 10.5,
        color: s.text,
        fontFeatures: const [FontFeature.tabularFigures()]);
    // #, Where, Starts, Speed, Own: the number and the dot narrow, the
    // place widest.
    Widget cellsOf(List<Widget> c) => Row(children: [
          SizedBox(width: 30, child: c[0]),
          Expanded(flex: 5, child: c[1]),
          Expanded(flex: 3, child: c[2]),
          Expanded(flex: 3, child: c[3]),
          SizedBox(width: 30, child: c[4]),
        ]);
    Widget row(
            {required Key key,
            required bool lit,
            required VoidCallback onTap,
            required List<Widget> cells}) =>
        Material(
          color: lit
              ? _instancesAccent.withValues(alpha: 0.2)
              : Colors.transparent,
          child: InkWell(
            key: key,
            onTap: onTap,
            child: SizedBox(height: 20, child: cellsOf(cells)),
          ),
        );
    Widget text(String t, [TextStyle? st]) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: st ?? cell));
    return Container(
      color: s.display,
      child: Column(children: [
        SizedBox(
          height: 20,
          child: cellsOf([
            text("#", head),
            text("WHERE", head),
            text("STARTS", head),
            text("SPEED", head),
            text("", head),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: set.count + 1,
            itemExtent: 20,
            itemBuilder: (context, n) {
              if (n == 0) {
                return row(
                  key: const ValueKey("copyRow-all"),
                  lit: picked.isEmpty,
                  onTap: () => controller.pickAllCopies(element),
                  cells: [
                    text("All"),
                    text(
                        "${e.name.isEmpty ? "The element" : e.name} · every copy"),
                    text(""),
                    text(""),
                    text(""),
                  ],
                );
              }
              var i = n - 1;
              var copy = set.items[i];
              var at = controller.copyCentre(e, copy);
              return row(
                key: ValueKey("copyRow-${copy.id}"),
                lit: picked.contains(copy.id),
                onTap: () => controller.pickCopy(element, copy.id,
                    toggle: HardwareKeyboard.instance.isShiftPressed),
                cells: [
                  text("${i + 1}"),
                  text("${at.dx.round()}, ${at.dy.round()}"),
                  text("${set.startOf(i).toStringAsFixed(2)}s"),
                  text("${set.speedOf(i).toStringAsFixed(2)}×"),
                  copy.own.isEmpty
                      ? text("")
                      : Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              key: ValueKey("copyOwn-${copy.id}"),
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: ownColour, shape: BoxShape.circle),
                            ),
                          ),
                        ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// DrawingCard is where [element] becomes pixels: between its moves and its
/// looks. Its screen is the element drawn as the page draws it -- every
/// copy, picked ones ringed -- with its Size and, reused, whether it is
/// drawn once and stamped at each copy or drawn for each.
class DrawingCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const DrawingCard(
      {required this.controller,
      required this.element,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var e = element;
    var m = e.base.motion;
    var set = m.instances;
    var picked = controller.pickedCopiesOf(e.id);
    const accent = Color(0xFF3FB08D);
    var size = picked.isEmpty
        ? (m.drawSize, false)
        : switch (controller.copyOwnOf(e.id, "drawSize")) {
            var own? => (own, true),
            null => (m.drawSize, false),
          };
    // Stamped while the copies differ only in where they are.
    var stamped = set == null || set.uniform;
    var caption = set == null || set.count < 2
        ? "drawn once"
        : stamped
            ? "drawn once, stamped ×${set.count}"
            : set.each
                ? "drawn ×${set.count}, each its own"
                : "drawn ×${set.count}: the copies differ";
    void setSize(double v, {bool transient = false}) {
      controller.beginInteraction();
      if (picked.isEmpty) {
        controller.setMotion(
            e.id, controller.motionOf(e.id).copyWith(drawSize: v),
            transient: true);
      } else {
        controller.setCopyOwn(e.id, "drawSize", v, transient: true);
      }
      if (!transient) controller.endInteraction();
    }

    return DeviceFrame(
      id: "drawing",
      title: "Drawing",
      help: "Where it is drawn: what is left of here moves it, what is right "
          "of here changes how it looks. Reused, it is drawn once and "
          "stamped at each copy while they differ only in where they are; "
          "Each its own draws every one.",
      skin: skin,
      folded: folded,
      onFold: onFold,
      width: 250 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
      height: height,
      icon: Icons.draw_outlined,
      accent: accent,
      glows: true,
      besideDisplay: 230,
      besideSettings: 200,
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      summary: caption,
      controls: (tier) => [
        DevicePack(key: const ValueKey("drawingPack"), children: [
          DeviceKnob(
            key: const ValueKey("drawingSize"),
            label: "Size",
            text: "${size.$1.toStringAsFixed(2)}×",
            value: size.$1,
            initial: 1,
            min: 0.25,
            max: 3,
            log: true,
            own: size.$2,
            accent: accent,
            ink: skin.ink,
            onChanged: setSize,
            onCommit: controller.endInteraction,
          ),
          if (set != null && set.count > 1)
            StudioDrop<bool>(
              key: const ValueKey("drawingEach"),
              label: "Drawn",
              value: set.each,
              options: const [(false, "Once, stamped"), (true, "Each its own")],
              onChanged: (v) {
                controller.beginInteraction();
                controller.setInstances(e.id, set.copyWith(each: v));
                controller.endInteraction();
              },
            ),
        ]),
      ],
      display: Stack(fit: StackFit.expand, children: [
        CustomPaint(
          key: const ValueKey("drawingScreen"),
          painter: _DrawingScreen(controller, e, picked, look.studio),
          child: const SizedBox.expand(),
        ),
        Positioned(
          left: 6,
          right: 6,
          bottom: 4,
          child: Text(caption,
              key: const ValueKey("drawingCaption"),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: look.studio.muted)),
        ),
      ]),
    );
  }
}

/// _DrawingScreen draws the element as the page does, every copy, fitted to
/// the screen; the picked copies ringed.
class _DrawingScreen extends CustomPainter {
  final CanvasController controller;
  final CanvasElement element;
  final Set<String> picked;
  final StudioColors studio;
  _DrawingScreen(this.controller, this.element, this.picked, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var doc = controller.document;
    var frame = controller.frame;
    var box = element.movedBoundsAt(frame, doc, live: controller.liveMotion);
    if (box.isEmpty || size.width < 8 || size.height < 8) return;
    var room = Rect.fromLTRB(8, 8, size.width - 8, size.height - 20);
    var s = math.min(room.width / box.width, room.height / box.height);
    // Not blown up past twice its size: one alone stays a thing on a page.
    s = math.min(s, 2.0);
    var at = room.center - box.center * s;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(at.dx, at.dy);
    canvas.scale(s);
    paintElement(canvas, element, frame,
        frameRate: doc.frameRate,
        images: controller.images,
        document: doc,
        liveMotion: controller.liveMotion);
    canvas.restore();
    var set = element.base.motion.instances;
    if (set == null || picked.isEmpty) return;
    var ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ownColour;
    for (var (i, copy) in set.items.indexed) {
      if (!picked.contains(copy.id)) continue;
      var b = element.boundsWith(poseWithMotion(element, frame, doc,
          live: controller.liveMotion, instance: i));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(b.left * s + at.dx, b.top * s + at.dy,
                      b.right * s + at.dx, b.bottom * s + at.dy)
                  .inflate(2),
              const Radius.circular(3)),
          ring);
    }
  }

  @override
  bool shouldRepaint(_DrawingScreen old) => true;
}
