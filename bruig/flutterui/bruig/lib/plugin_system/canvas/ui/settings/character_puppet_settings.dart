import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_doll.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_doll_pose.dart';
import 'package:bruig/plugin_system/canvas/ui/character_draw_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// character_puppet_settings.dart is the Puppet section of a sketch's
// settings, there while its puppet is out: the puppet flat or as a doll in
// 3D, the doll's body -- the character's own, or a kind of person shaped
// as wanted -- and how it is shown. See character_doll.dart.

/// characterPuppetSection is the Puppet section for sketch [e].
Widget characterPuppetSection(BuildContext context, CanvasController controller,
    CharacterElement e, SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var form = e.puppet;
  var look = controller.dollLook;

  // The doll's body as [f] -- or the character's own, for null. One drawn
  // from nothing is that body: what is drawn on it rides on the doll.
  CharacterElement formed(PuppetForm? f) {
    if (f == null) return e.copyWith(ownPuppet: true);
    var next = e.copyWith(puppet: f);
    if (e.dna.kind == CharacterType.empty) {
      next = next.copyWith(
          dna: e.dna.copyWith(headsTall: f.headsTall, build: f.build, look: f.look));
    }
    return next;
  }

  void now(CharacterElement next) {
    begin();
    write(next);
    commit();
  }

  Widget percent(String key, String label, double value, double min, double max,
          double rest, PuppetForm Function(double) change) =>
      CanvasStepper(
        key: ValueKey(key),
        label: label,
        value: value * 100,
        min: min * 100,
        max: max * 100,
        step: 5,
        suffix: "%",
        defaultValue: rest * 100,
        onChanged: (v) => write(formed(change(v / 100))),
        onCommit: commit,
      );

  var under = (look.place ??
          (e.dna.kind == CharacterType.empty ? DollGuide.under : DollGuide.over)) ==
      DollGuide.under;
  return section(e, "puppet",
      icon: Icons.accessibility_new,
      title: "Puppet",
      summary: controller.puppet3D
          ? "3D doll · ${form?.body.label ?? "As the character"}"
          : "Flat",
      changes: form == null || form.isAsMade ? 0 : 1,
      onReset: form == null || form.isAsMade ? null : () => now(formed(PuppetForm.of(form.body))),
      initiallyOpen: true,
      children: [
        CanvasDropdown<bool>(
          key: const ValueKey("puppetKind"),
          label: "Puppet",
          value: controller.puppet3D,
          options: const [(false, "Flat, with its handles"), (true, "A doll in 3D")],
          onChanged: (v) => controller.puppet3D = v,
        ),
        if (controller.puppet3D) ...[
          CanvasTiles<String>(
            label: "Body",
            help: "Who the doll is: the character as made, or a kind of "
                "person to pose and draw over, shaped below. For a character "
                "drawn from nothing, the doll's body is its body.",
            columns: 4,
            previewHeight: 70,
            tiles: [
              CanvasTile("", "As the character",
                  drawnFrom: "${e.dna.toJson()}|${e.style.name}",
                  paint: (canvas, size) => _dollTile(canvas, size, e.style.dnaOf(e.dna), null)),
              for (var t in puppetBodies)
                CanvasTile(t.name, t.label,
                    drawnFrom: "puppet|${t.name}",
                    paint: (canvas, size) =>
                        _dollTile(canvas, size, t.dna, PuppetForm.of(t).feminine)),
            ],
            selected: (k) => k == (form?.body.name ?? ""),
            keyOf: (k) => "puppetBody-${k.isEmpty ? "character" : k}",
            onPick: (k) => now(formed(switch (CharacterType.fromName(k)) {
              var t? => PuppetForm.of(t),
              null => null,
            })),
          ),
          if (form != null)
            CanvasControlGroup(
              key: const ValueKey("puppetForm"),
              label: "Form",
              help: "The doll's shape: how many heads tall, how broad, how "
                  "much a woman's figure, and its body part by part.",
              children: [
                CanvasStepper(
                  key: const ValueKey("puppetHeadsTall"),
                  label: "Heads tall",
                  value: form.headsTall,
                  min: 2,
                  max: 9,
                  step: 0.1,
                  decimals: 1,
                  defaultValue: PuppetForm.of(form.body).headsTall,
                  onChanged: (v) => write(formed(form.copyWith(headsTall: v))),
                  onCommit: commit,
                ),
                percent("puppetBuild", "Build", form.build, 0, 1,
                    PuppetForm.of(form.body).build, (v) => form.copyWith(build: v)),
                percent("puppetFeminine", "Figure", form.feminine, 0, 1,
                    PuppetForm.of(form.body).feminine, (v) => form.copyWith(feminine: v)),
                for (var l in puppetLooks)
                  percent("puppetLook-${l.name}", l.label, form.look[l], -1, 1,
                      PuppetForm.of(form.body).look[l],
                      (v) => form.copyWith(look: form.look.withValue(l, v))),
              ],
            ),
          if (controller.dollJoint case var joint?)
            _jointGroup(controller, e, joint, write, commit),
          CanvasControlGroup(
            key: const ValueKey("puppetShown"),
            label: "Shown",
            help: "Where the doll is drawn -- under the drawing, to draw "
                "over, or over it, to see the pose through it -- how solid, "
                "its guide lines, and how strongly in perspective.",
            children: [
              CanvasDropdown<DollGuide?>(
                key: const ValueKey("puppetPlace"),
                label: "Drawn",
                value: look.place,
                options: const [
                  (null, "As it suits"),
                  (DollGuide.under, "Under the drawing"),
                  (DollGuide.over, "Over the drawing"),
                ],
                onChanged: (v) => controller.dollLook =
                    v == null ? look.copyWith(autoPlace: true) : look.copyWith(place: v),
              ),
              CanvasStepper(
                key: const ValueKey("puppetOpacity"),
                label: "Opacity",
                value: (look.opacity ?? (under ? 1 : 0.4)) * 100,
                min: 10,
                max: 100,
                step: 5,
                suffix: "%",
                defaultValue: under ? 100 : 40,
                onChanged: (v) => controller.dollLook = look.copyWith(opacity: v / 100),
              ),
              CanvasToggle(
                key: const ValueKey("puppetLines"),
                label: "Guide lines",
                value: look.lines,
                onChanged: (v) => controller.dollLines = v,
              ),
              CanvasDropdown<double>(
                key: const ValueKey("puppetLens"),
                label: "Lens",
                value: dollLenses.any((l) => l.$1 == look.lens) ? look.lens : dollLenses.first.$1,
                options: dollLenses,
                onChanged: (v) => controller.dollLens = v,
              ),
            ],
          ),
        ],
      ]);
}

/// _dollTile draws the doll made as [dna] standing, filling the tile.
void _dollTile(ui.Canvas canvas, Size size, CharacterDna dna, double? feminine) {
  var h = size.height * 0.94;
  var box = Rect.fromCenter(center: size.center(Offset.zero), width: h * 0.45, height: h);
  paintDoll(canvas, CharacterRig.of(dna, CharacterElement.restPose, box), dna,
      look: const DollLook(lines: false), feminine: feminine);
}

/// _jointGroup is the doll's joint picked on the canvas, set by number: the
/// bone below it bent in the picture and swung towards the reader -- and,
/// a wrist, the hand's shape and each finger's curl.
Widget _jointGroup(CanvasController controller, CharacterElement e, DollJoint joint,
    SettingsWrite write, VoidCallback commit) {
  var pose = e.poseAtFrame(controller.frame);
  var bone = joint.bone;
  void posed(CharacterPose next) => write(controller.characterPosed(e, next));
  Widget degrees(String key, String label, double value, double min, double max,
          void Function(double) set) =>
      CanvasStepper(
        key: ValueKey(key),
        label: label,
        value: value,
        min: min,
        max: max,
        step: 5,
        suffix: "°",
        defaultValue: 0,
        onChanged: set,
        onCommit: commit,
      );

  var arm = joint.hand;
  var left = arm == CharacterLimb.armL;
  var shape = arm == null ? null : HandShape.of(pose, left);
  return CanvasControlGroup(
    key: const ValueKey("puppetJoint"),
    label: joint.label,
    help: "The joint picked on the doll. Drag round its blue ring to bend "
        "it, along its orange ring to swing it towards you or away, or set "
        "them here. On a wrist, drag a fingertip to curl that finger.",
    children: [
      degrees("puppetJointBend", "Bend", pose[bone], -180, 180,
          (v) => posed(pose.withAngle(bone, v))),
      degrees("puppetJointSwing", "Swing", pose.swing(bone), -170, 170,
          (v) => posed(pose.withSwing(bone, v))),
      CanvasTextButton(
        key: const ValueKey("puppetJointStraighten"),
        label: "Straighten",
        icon: Icons.straighten,
        onPressed: () {
          posed(pose.withAngle(bone, 0).withSwing(bone, 0));
          commit();
        },
      ),
      if (shape != null) ...[
        CanvasDropdown<String>(
          key: const ValueKey("puppetHandShape"),
          label: "Hand",
          value: handShapes.firstWhere((h) => h.same(shape), orElse: () => const HandShape("", [], 0)).name,
          options: [
            if (!handShapes.any((h) => h.same(shape))) ("", "As posed"),
            for (var h in handShapes) (h.name, h.name),
          ],
          onChanged: (name) {
            for (var h in handShapes) {
              if (h.name == name) posed(h.on(pose, left));
            }
            commit();
          },
        ),
        for (var f in Finger.values)
          degrees("puppetFinger-${f.name}", f.label, pose[f.bone(left)], -30, 110,
              (v) => posed(pose.withAngle(f.bone(left), v))),
      ],
    ],
  );
}
