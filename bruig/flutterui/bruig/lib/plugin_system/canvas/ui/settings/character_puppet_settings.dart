import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_doll.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_body.dart';
import 'package:bruig/plugin_system/canvas/storage/human_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_doll_pose.dart';
import 'package:bruig/plugin_system/canvas/ui/character_draw_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion_files.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
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
          ? "${look.kind.label} · ${form?.body.label ?? "As the character"}"
          : "Flat",
      changes: form == null || form.isAsMade ? 0 : 1,
      onReset: form == null || form.isAsMade ? null : () => now(formed(PuppetForm.of(form.body))),
      initiallyOpen: true,
      children: [
        CanvasDropdown<DollKind?>(
          key: const ValueKey("puppetKind"),
          label: "Puppet",
          value: controller.puppet3D ? look.kind : null,
          options: [
            (null, "Flat, with its handles"),
            for (var k in DollKind.values) (k, k.label),
          ],
          onChanged: (v) {
            if (v != null) controller.dollLook = look.copyWith(kind: v);
            controller.puppet3D = v != null;
          },
        ),
        if (controller.puppet3D && look.kind == DollKind.human)
          const _HumanBodyStatus(key: ValueKey("puppetHumanStatus")),
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
                  drawnFrom: "${e.dna.toJson()}|${e.style.name}|${look.kind.name}",
                  paint: (canvas, size) =>
                      _dollTile(canvas, size, e.style.dnaOf(e.dna), null, look.kind)),
              for (var t in puppetBodies)
                CanvasTile(t.name, t.label,
                    drawnFrom: "puppet|${t.name}|${look.kind.name}",
                    paint: (canvas, size) =>
                        _dollTile(canvas, size, t.dna, PuppetForm.of(t).feminine, look.kind)),
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
          PoseLibrary(
              key: ValueKey("puppetPoses-${e.id}"),
              controller: controller,
              character: e,
              write: write,
              commit: commit),
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
                // Drawn on the smooth doll; the human body and the wooden
                // doll show their own form.
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

/// _dollTile draws the doll made as [dna] standing, filling the tile: the
/// wooden one, or -- quicker to draw than the human body, seven times over
/// -- the smooth one for a human.
void _dollTile(ui.Canvas canvas, Size size, CharacterDna dna, double? feminine, DollKind kind) {
  var h = size.height * 0.94;
  var box = Rect.fromCenter(center: size.center(Offset.zero), width: h * 0.45, height: h);
  paintDoll(canvas, CharacterRig.of(dna, CharacterElement.restPose, box), dna,
      look: DollLook(lines: false, kind: kind), feminine: feminine);
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

/// _HumanBodyStatus is whether the human body is here to be the doll -- and,
/// when it is not, the button that fetches it. The smooth doll stands in
/// meanwhile.
class _HumanBodyStatus extends StatefulWidget {
  const _HumanBodyStatus({super.key});

  @override
  State<_HumanBodyStatus> createState() => _HumanBodyStatusState();
}

class _HumanBodyStatusState extends State<_HumanBodyStatus> {
  double? _progress;
  String _said = "";

  HumanBody get _body => HumanBody.instance;

  @override
  void initState() {
    super.initState();
    _body.addListener(_changed);
    _body.load();
  }

  @override
  void dispose() {
    _body.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _said = "";
    });
    try {
      await HumanAssets.install(progress: (p) => mounted ? setState(() => _progress = p) : null);
      await _body.installed();
    } catch (e) {
      _said = "$e";
    }
    if (mounted) setState(() => _progress = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_body.ready && _said.isEmpty) return const SizedBox.shrink();
    var status = _progress != null
        ? "Downloading the body… ${(_progress! * 100).round()}%"
        : _said.isNotEmpty
            ? _said
            : _body.missing
                ? "The human body is downloaded once: about "
                    "${humanDownloadBytes >> 20} MB from MakeHuman on GitHub, "
                    "free to use for anything -- the same body Sculpted 3D "
                    "uses. Until then a smooth doll stands in."
                : "Looking for the body…";
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_body.missing && _progress == null)
        CanvasTextButton(
          key: const ValueKey("puppetHumanDownload"),
          icon: Icons.download_outlined,
          label: "Download the human body",
          primary: true,
          onPressed: _download,
        ),
      CanvasStatus(status),
    ]);
  }
}

/// PoseLibrary is the poses a sketch can be put in from its Puppet section:
/// standing ones, ones in action, the ones kept -- each tile the doll in it
/// -- and a pose taken from a frame of a motion file.
class PoseLibrary extends StatefulWidget {
  final CanvasController controller;
  final CharacterElement character;
  final SettingsWrite write;
  final VoidCallback commit;
  const PoseLibrary(
      {required this.controller,
      required this.character,
      required this.write,
      required this.commit,
      super.key});

  @override
  State<PoseLibrary> createState() => PoseLibraryState();
}

class PoseLibraryState extends State<PoseLibrary> {
  SavedPresetStore get _kept => SavedPresetStore.poses;

  /// _file is the motion file a pose is being taken from, its poses, and
  /// the frame of it looked at.
  String? _file;
  List<CharacterPose> _frames = const [];
  int _frame = 0;
  String _said = "";

  @override
  void initState() {
    super.initState();
    _kept.addListener(_changed);
    _kept.load();
  }

  @override
  void dispose() {
    _kept.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  CharacterElement get _e => widget.character;

  /// _put puts the character in [pose], facing as it faces now.
  void _put(CharacterPose pose) {
    var now = _e.poseAtFrame(widget.controller.frame);
    widget.write(widget.controller.characterPosed(_e, pose.withTurn(now.turn).withTilt(now.tilt)));
    widget.commit();
  }

  Future<void> _keep() async {
    var pose = _e.poseAtFrame(widget.controller.frame);
    var n = _kept.presets.length + 1;
    while (_kept.presets.any((p) => p.name == "My pose $n")) {
      n++;
    }
    await _kept.save("My pose $n", {"pose": pose.withTurn(0).withTilt(0).toJson()});
  }

  Future<void> _pickFile() async {
    var picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: motionExtensions,
      withData: false,
    );
    var file = picked?.files.singleOrNull?.path;
    if (file == null) return;
    String said;
    try {
      var bytes = await File(file).readAsBytes();
      var (motion, from) = readMotionFile(bytes, file, frameRate: 12, animation: 0);
      var frames = motionPoses(motion, frameRate: 12, headsTall: _e.dna.headsTall);
      setState(() {
        _file = from;
        _frames = frames;
        _frame = 0;
      });
      if (frames.isNotEmpty) _put(frames.first);
      said = "${frames.length} frames in $from: step through them to pick the pose.";
    } on MotionError catch (error) {
      said = "That file could not be read: $error";
    } on GltfError catch (error) {
      said = "That file could not be read: $error";
    } on FormatException {
      said = "That file could not be read.";
    } on FileSystemException {
      said = "That file could not be opened.";
    }
    if (mounted) setState(() => _said = said);
  }

  @override
  Widget build(BuildContext context) {
    var e = _e;
    var pose = e.poseAtFrame(widget.controller.frame);
    var dna = e.style.dnaOf(e.puppet?.dna ?? e.dna);
    var feminine = e.puppet?.feminine;
    var kept = [
      for (var p in _kept.presets)
        if (p.data["pose"] != null) (p, CharacterPose.fromJson(p.data["pose"])),
    ];
    var all = <(String, String, CharacterPose)>[
      for (var p in posePresets) ("stand-${p.name}", p.name, p.pose),
      for (var p in actionPoses) ("action-${p.name}", p.name, p.pose),
      for (var (p, q) in kept) ("kept-${p.id}", p.name, q),
    ];
    bool same(CharacterPose a, CharacterPose b) {
      for (var bone in CharacterBone.values) {
        if ((a[bone] - b[bone]).abs() > 0.5 || (a.swing(bone) - b.swing(bone)).abs() > 0.5) {
          return false;
        }
      }
      return (a.lift - b.lift).abs() < 0.01;
    }

    var keptNow = [for (var (p, q) in kept) if (same(q, pose)) p].firstOrNull;
    return CanvasControlGroup(
      key: const ValueKey("puppetPoses"),
      label: "Poses",
      help: "Put it in a pose: standing, in action, or one you kept -- each "
          "drawn as the doll in it -- then shape it joint by joint. Keep the "
          "pose it is in to use again on any character, or take one from a "
          "frame of a motion file: BVH, FBX, or the animation in a .glb.",
      children: [
        CanvasTiles<String>(
          label: "Pose",
          columns: 5,
          previewHeight: 70,
          tiles: [
            for (var (key, name, p) in all)
              CanvasTile(key, name,
                  drawnFrom: "${p.toJson()}|${dna.toJson()}|$feminine",
                  paint: (canvas, size) => _poseTile(canvas, size, dna, p, feminine)),
          ],
          selected: (key) => all.any((x) => x.$1 == key && same(x.$3, pose)),
          keyOf: (key) => "puppetPose-$key",
          onPick: (key) {
            for (var (k, _, p) in all) {
              if (k == key) _put(p);
            }
          },
        ),
        CanvasTextButton(
          key: const ValueKey("puppetPoseKeep"),
          label: "Keep this pose",
          icon: Icons.bookmark_add_outlined,
          onPressed: _keep,
        ),
        if (keptNow != null)
          CanvasTextButton(
            key: const ValueKey("puppetPoseForget"),
            label: "Remove \"${keptNow.name}\"",
            icon: Icons.bookmark_remove_outlined,
            onPressed: () => _kept.remove(keptNow),
          ),
        CanvasTextButton(
          key: const ValueKey("puppetPoseFile"),
          label: "Pose from a motion file…",
          icon: Icons.file_open_outlined,
          onPressed: _pickFile,
        ),
        if (_file != null && _frames.length > 1)
          CanvasStepper(
            key: const ValueKey("puppetPoseFrame"),
            label: "Frame",
            value: _frame.toDouble(),
            min: 0,
            max: (_frames.length - 1).toDouble(),
            step: 1,
            onChanged: (v) {
              var f = v.round().clamp(0, _frames.length - 1);
              setState(() => _frame = f);
              widget.write(widget.controller.characterPosed(e, _frames[f]));
            },
            onCommit: widget.commit,
          ),
        if (_said.isNotEmpty) CanvasStatus(_said),
      ],
    );
  }
}

/// _poseTile draws the wooden doll -- its joints plain -- made as [dna]
/// is, in [pose], turned a little to show it in depth.
void _poseTile(ui.Canvas canvas, Size size, CharacterDna dna, CharacterPose pose, double? feminine) {
  var h = size.height * 0.86;
  var box = Rect.fromCenter(
      center: size.center(Offset.zero) + Offset(0, size.height * 0.04), width: h * 0.45, height: h);
  paintDoll(canvas, CharacterRig.of(dna, pose.withTurn(35), box), dna,
      look: const DollLook(kind: DollKind.wooden), feminine: feminine, box: box);
}
