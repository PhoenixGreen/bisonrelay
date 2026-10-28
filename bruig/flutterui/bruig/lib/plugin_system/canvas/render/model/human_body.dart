import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/human_targets.dart';
import 'package:bruig/plugin_system/canvas/model/elements/human_wear.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/model_math.dart';
import 'package:bruig/plugin_system/canvas/render/model/mannequin.dart';
import 'package:bruig/plugin_system/canvas/render/model/model_figure.dart';
import 'package:bruig/plugin_system/canvas/storage/human_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/human_wear_assets.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_garments.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_wear_fit.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// human_body.dart is a character sculpted in 3D: the MakeHuman body made
// into this character -- its age and sex from its type, its build and
// every part of its face and body from its Appearance -- with a skeleton
// fitted to it and clothes painted on, handed to the model drawing like
// any model brought in from a file. So it is posed, lip-synced and stood
// on a stage the same way.

/// HumanPack is the stored body, read: the mesh, its pieces, and the
/// shapes it can take.
class HumanPack {
  final Float32List base;
  final Float32List uvs;

  /// groups is each piece of the mesh as its triangles' corners: a vertex
  /// index then a uv index, three corners a triangle.
  final Map<String, Uint32List> groups;
  final Map<String, (Uint16List, Int16List)> targets;

  /// bones is the skeleton: each bone's head and tail joint, and parent.
  final Map<String, ({String head, String tail, String? parent})> bones;

  /// joints is the vertices whose middle each joint is.
  final Map<String, List<int>> joints;

  /// weights is how much each vertex follows each bone.
  final Map<String, List<(int, double)>> weights;

  HumanPack(this.base, this.uvs, this.groups, this.targets, this.bones,
      this.joints, this.weights);

  int get vertexCount => base.length ~/ 3;

  static HumanPack read(Uint8List bytes, String skeleton, String weights) {
    var data = ByteData.sublistView(bytes);
    var at = 8;
    int u32() {
      var v = data.getUint32(at, Endian.little);
      at += 4;
      return v;
    }

    String name() {
      var n = data.getUint16(at, Endian.little);
      var s = utf8.decode(Uint8List.sublistView(bytes, at + 2, at + 2 + n));
      at += 2 + n;
      at += (4 - (2 + n) % 4) % 4;
      return s;
    }

    var n = u32();
    var base = Float32List.fromList(bytes.buffer.asFloat32List(bytes.offsetInBytes + at, n * 3));
    at += n * 12;
    var nuv = u32();
    var uvs = Float32List.fromList(bytes.buffer.asFloat32List(bytes.offsetInBytes + at, nuv * 2));
    at += nuv * 8;
    var groups = <String, Uint32List>{};
    for (var g = u32(); g > 0; g--) {
      var key = name();
      var corners = u32();
      groups[key] = Uint32List.fromList(
          bytes.buffer.asUint32List(bytes.offsetInBytes + at, corners * 2));
      at += corners * 8;
    }
    var targets = <String, (Uint16List, Int16List)>{};
    for (var t = u32(); t > 0; t--) {
      var key = name();
      var count = u32();
      var odd = count.isOdd ? 1 : 0;
      var idx = Uint16List.fromList(
          bytes.buffer.asUint16List(bytes.offsetInBytes + at, count));
      at += (count + odd) * 2;
      var d = Int16List.fromList(
          bytes.buffer.asInt16List(bytes.offsetInBytes + at, count * 3));
      at += (count * 3 + odd) * 2;
      targets[key] = (idx, d);
    }

    var sk = jsonDecode(skeleton) as Map<String, dynamic>;
    var bones = <String, ({String head, String tail, String? parent})>{
      for (var e in (sk["bones"] as Map<String, dynamic>).entries)
        e.key: (
          head: (e.value as Map)["head"] as String,
          tail: (e.value as Map)["tail"] as String,
          parent: (e.value as Map)["parent"] as String?,
        ),
    };
    var joints = <String, List<int>>{
      for (var e in (sk["joints"] as Map<String, dynamic>).entries)
        e.key: [for (var v in e.value as List) (v as num).toInt()],
    };
    var w = jsonDecode(weights) as Map<String, dynamic>;
    var ws = <String, List<(int, double)>>{
      for (var e in (w["weights"] as Map<String, dynamic>).entries)
        e.key: [
          for (var p in e.value as List)
            ((p as List)[0] as num).toInt().let((v) => (v, (p[1] as num).toDouble())),
        ],
    };
    return HumanPack(base, uvs, groups, targets, bones, joints, ws);
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// HumanBody holds the stored body once it is read, and the characters
/// made of it.
class HumanBody extends ChangeNotifier {
  static final HumanBody instance = HumanBody();

  HumanPack? _pack;
  bool _loading = false;

  /// _missing is whether the body was looked for and is not downloaded.
  bool _missing = false;

  /// ready is whether characters can be made of it now.
  bool get ready => _pack != null;

  /// missing is whether it was looked for and is not on this computer.
  bool get missing => _missing;

  final Map<String, LoadedModel> _made = {};

  /// _wear is the hair, brows, shoes and teeth, read; _masks where each
  /// cut-out one is solid.
  Map<String, WearMesh> _wear = const {};
  Map<String, ui.Image> _masks = const {};
  bool _wearMissing = false;

  /// wearReady is whether hair and shoes are here to be worn;
  /// wearMissing whether they were looked for and are not downloaded.
  bool get wearReady => _wear.isNotEmpty;
  bool get wearMissing => _wearMissing;

  Future<void> _loadWear() async {
    try {
      if (!await HumanWearAssets.installed()) {
        _wearMissing = true;
        return;
      }
      var root = await HumanWearAssets.dir();
      var files = <String, (String, String)>{};
      for (var item in wearCatalogue) {
        var d = path.join(root, item.id);
        var obj = File(path.join(d, "mesh.obj"));
        var fit = File(path.join(d, "fit.mhclo"));
        if (!await obj.exists() || !await fit.exists()) continue;
        files[item.id] = (await obj.readAsString(), await fit.readAsString());
      }
      var wear = await Isolate.run(() => {
            for (var e in files.entries)
              e.key: WearMesh.parse(wearItem(e.key)!, e.value.$1, e.value.$2),
          });
      var masks = <String, ui.Image>{};
      for (var id in wear.keys) {
        var f = File(path.join(root, id, "mask.png"));
        if (!await f.exists()) continue;
        var codec = await ui.instantiateImageCodec(await f.readAsBytes());
        masks[id] = (await codec.getNextFrame()).image;
        codec.dispose();
      }
      _wear = wear;
      _masks = masks;
      _wearMissing = false;
      _made.clear();
    } catch (e) {
      debugPrint("Unable to read the stored hair and shoes: $e");
      _wearMissing = true;
    }
  }

  /// wearInstalled is called once hair and shoes have been downloaded.
  Future<void> wearInstalled() async {
    _wearMissing = false;
    await _loadWear();
    notifyListeners();
  }

  @visibleForTesting
  Map<String, WearMesh> get wearForTest => _wear;

  @visibleForTesting
  void useWearForTest(Map<String, WearMesh> wear, [Map<String, ui.Image> masks = const {}]) {
    _wear = wear;
    _masks = masks;
    _made.clear();
    notifyListeners();
  }

  /// load reads the stored body, once, if it is there.
  Future<void> load() async {
    if (_pack != null || _loading) return;
    _loading = true;
    try {
      if (!await HumanAssets.installed()) {
        _missing = true;
        return;
      }
      var root = await HumanAssets.dir();
      var bytes = await File(await HumanAssets.packPath()).readAsBytes();
      var skel = await File(path.join(root, "default.mhskel")).readAsString();
      var weights =
          await File(path.join(root, "default_weights.mhw")).readAsString();
      _pack = await Isolate.run(() => HumanPack.read(bytes, skel, weights));
      _missing = false;
      await _loadWear();
    } catch (e) {
      debugPrint("Unable to read the stored body: $e");
      _missing = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// installed is called once the body has been downloaded.
  Future<void> installed() async {
    _missing = false;
    await load();
  }

  @visibleForTesting
  void useForTest(HumanPack pack, {bool inBackground = false}) {
    _pack = pack;
    _inForeground = !inBackground;
    _builder = null;
    _made.clear();
    _lastOf.clear();
    notifyListeners();
  }

  /// modelFor is [dna] made of the body, ready to pose -- or null while the
  /// body is not here, or for a character it cannot make: an animal.
  LoadedModel? modelFor(CharacterDna dna,
      {bool drawnFace = false,
      String? preferHair,
      double limbs = 1,
      bool gloves = false,
      double? gender}) {
    var pack = _pack;
    if (pack == null) {
      if (!_missing) {
        stoodIn++;
        load();
      }
      return null;
    }
    if (!dna.kind.person) return null;
    var wearing = [
      for (var w in wearFor(dna, _wear, prefer: preferHair))
        if (!drawnFace ||
            (w.item.kind != WearKind.eyebrows && w.item.kind != WearKind.teeth))
          w,
    ];
    var key = jsonEncode([
      drawnFace,
      limbs,
      gloves,
      gender,
      dna.kind.name,
      dna.headsTall,
      dna.build,
      dna.look.toJson(),
      dna.skin.toARGB32(),
      dna.hair.toARGB32(),
      dna.eyes.toARGB32(),
      dna.hairStyle.name,
      dna.hairModel,
      dna.browModel,
      [for (var w in wearing) w.item.id],
      [for (var g in dna.worn) g.toJson()],
    ]);
    if (_made.remove(key) case var kept?) {
      _lastOf[(dna.kind, drawnFace)] = key;
      return _made[key] = kept;
    }
    var images = [for (var w in wearing) _masks[w.item.id]];
    // Being changed -- a slider dragged -- the body it was a moment ago
    // stands in while the new one is made away from the screen: making
    // one takes a fifth of a second, too long to hold up every frame.
    CanvasPerf.count("bodyBuild");
    var standIn = _made[_lastOf[(dna.kind, drawnFace)]];
    if (standIn != null && !buildNow && !_inForeground) {
      _buildAway(key, pack, dna, wearing, drawnFace, images, limbs, gloves, gender);
      stoodIn++;
      return standIn;
    }
    return _keep(key, dna, drawnFace,
        LoadedModel.of(
            buildHuman(pack, dna,
                wearing: wearing,
                drawnFace: drawnFace,
                limbs: limbs,
                gloves: gloves,
                gender: gender),
            images));
  }

  LoadedModel _keep(String key, CharacterDna dna, bool drawnFace, LoadedModel model) {
    _made[key] = model;
    _lastOf[(dna.kind, drawnFace)] = key;
    if (_made.length > 6) _made.remove(_made.keys.first);
    return model;
  }

  /// stoodIn counts the times a body was asked for and something stood in
  /// for it: a stand-in, or nothing while the body is read.
  int stoodIn = 0;

  /// making is whether a body is being made away from the screen.
  bool get making => _away != null;

  /// buildNow makes every body as it is asked for, never a stand-in: for
  /// an export, every frame of which must show the body as it is.
  bool buildNow = false;

  /// _inForeground makes bodies where they are asked for: in tests.
  bool _inForeground = false;

  /// _lastOf is the body last made or drawn for each kind of person, with
  /// a drawn face or its own: the stand-in while one like it is made.
  final Map<(CharacterType, bool), String> _lastOf = {};

  /// _away is the body being made away from the screen, and _next the one
  /// asked for meanwhile -- only the last asked for is made next.
  String? _away;
  (String, CharacterDna, List<WearMesh>, bool, List<ui.Image?>, double, bool, double?)? _next;
  _Builder? _builder;

  void _buildAway(String key, HumanPack pack, CharacterDna dna,
      List<WearMesh> wearing, bool drawnFace, List<ui.Image?> images,
      double limbs, bool gloves, double? gender) {
    if (_away == key) return;
    if (_away != null) {
      _next = (key, dna, wearing, drawnFace, images, limbs, gloves, gender);
      return;
    }
    _away = key;
    () async {
      try {
        var builder = _builder ??= await _Builder.start(pack);
        var gltf = await builder.build(dna, wearing, drawnFace, limbs, gloves, gender);
        if (identical(_pack, pack)) {
          _keep(key, dna, drawnFace, LoadedModel.of(gltf, images));
        }
      } catch (e) {
        debugPrint("Unable to make the body: $e");
      } finally {
        _away = null;
        var next = _next;
        _next = null;
        if (next != null && !_made.containsKey(next.$1) && identical(_pack, pack)) {
          _buildAway(next.$1, pack, next.$2, next.$3, next.$4, next.$5,
              next.$6, next.$7, next.$8);
        }
        notifyListeners();
      }
    }();
  }
}

/// _Builder is an isolate that holds the body and makes characters of it,
/// so that the main one only sends a character and gets a model back.
class _Builder {
  final SendPort _to;
  final ReceivePort _from;
  final Map<int, Completer<Gltf>> _waiting = {};
  int _ids = 0;

  _Builder(this._to, this._from) {
    _from.listen((m) {
      var (id, gltf, error) = m as (int, Gltf?, String?);
      var c = _waiting.remove(id);
      if (gltf != null) {
        c?.complete(gltf);
      } else {
        c?.completeError(error ?? "no body made");
      }
    });
  }

  static Future<_Builder> start(HumanPack pack) async {
    var hello = ReceivePort();
    await Isolate.spawn(_work, (hello.sendPort, pack));
    var events = hello.asBroadcastStream();
    var to = await events.first as SendPort;
    var from = ReceivePort();
    to.send(from.sendPort);
    hello.close();
    return _Builder(to, from);
  }

  Future<Gltf> build(CharacterDna dna, List<WearMesh> wearing, bool drawnFace,
      double limbs, bool gloves, double? gender) {
    var id = _ids++;
    var c = _waiting[id] = Completer<Gltf>();
    _to.send((id, dna, wearing, drawnFace, limbs, gloves, gender));
    return c.future;
  }

  static Future<void> _work((SendPort, HumanPack) start) async {
    var (hello, pack) = start;
    var inbox = ReceivePort();
    hello.send(inbox.sendPort);
    SendPort? reply;
    await for (var m in inbox) {
      if (m is SendPort) {
        reply = m;
        continue;
      }
      var (id, dna, wearing, drawnFace, limbs, gloves, gender) =
          m as (int, CharacterDna, List<WearMesh>, bool, double, bool, double?);
      try {
        reply?.send((
          id,
          buildHuman(pack, dna,
              wearing: wearing,
              drawnFace: drawnFace,
              limbs: limbs,
              gloves: gloves,
              gender: gender),
          null
        ));
      } catch (e) {
        reply?.send((id, null, "$e"));
      }
    }
  }
}

/// _humanoid is the MakeHuman skeleton's bones, as a human skeleton.
const Map<HumanBone, String> _humanoid = {
  HumanBone.hips: "root",
  HumanBone.spine: "spine05",
  HumanBone.chest: "spine02",
  HumanBone.neck: "neck01",
  HumanBone.head: "head",
  HumanBone.leftUpperArm: "upperarm01.L",
  HumanBone.leftLowerArm: "lowerarm01.L",
  HumanBone.leftHand: "wrist.L",
  HumanBone.rightUpperArm: "upperarm01.R",
  HumanBone.rightLowerArm: "lowerarm01.R",
  HumanBone.rightHand: "wrist.R",
  HumanBone.leftUpperLeg: "upperleg01.L",
  HumanBone.leftLowerLeg: "lowerleg01.L",
  HumanBone.leftFoot: "foot.L",
  HumanBone.rightUpperLeg: "upperleg01.R",
  HumanBone.rightLowerLeg: "lowerleg01.R",
  HumanBone.rightFoot: "foot.R",
  HumanBone.leftEye: "eye.L",
  HumanBone.rightEye: "eye.R",
  HumanBone.leftShoulder: "shoulder01.L",
  HumanBone.rightShoulder: "shoulder01.R",
};

/// wearFor is what [dna] wears of [wear]: its hair, its brows, its shoes
/// if it wears shoes, and teeth. [prefer] is the hair its style would give
/// it, where none is chosen.
List<WearMesh> wearFor(CharacterDna dna, Map<String, WearMesh> wear,
    {String? prefer}) {
  if (wear.isEmpty) return const [];
  var out = <WearMesh>[];
  void put(String id) {
    if (wear[id] case var w?) out.add(w);
  }

  var female = dna.kind == CharacterType.woman || dna.kind == CharacterType.girl;
  if (dna.hairStyle != HairStyle.bald) {
    var chosen = dna.hairModel.isNotEmpty && wear.containsKey(dna.hairModel)
        ? dna.hairModel
        : prefer != null && wear.containsKey(prefer)
            ? prefer
            : switch (dna.hairStyle) {
            HairStyle.long => "long",
            HairStyle.bun => "bun",
            HairStyle.curly => "afro",
            _ => female ? "bobcut" : (dna.kind == CharacterType.elder ? "short1" : "messy"),
          };
    put(chosen);
  }
  put(dna.browModel.isNotEmpty && wear.containsKey(dna.browModel)
      ? dna.browModel
      : (female ? "brow1" : "brow2"));
  var shoe = dna.worn.where((g) => g.kind.shape == GarmentShape.shoes).lastOrNull;
  if (shoe != null) {
    // Heels, sandals and slippers have no shoe of their own here: the feet
    // are coloured as they are, rather than in a trainer and socks.
    switch (shoe.kind) {
      case GarmentKind.boots:
        put("shoes03");
      case GarmentKind.heels || GarmentKind.sandals || GarmentKind.slippers:
        break;
      default:
        put("shoes02");
    }
  }
  put("teeth");
  return out;
}

/// buildHuman is [dna] made of [pack], as a glTF ready to pose, wearing
/// [wearing] -- whose pictures, where they are cut out, are the images in
/// the same order.
///
/// With [drawnFace], a style's face is to be drawn on it: its eyes are left
/// as skin and its lashes and brows off, so they are not drawn twice.
///
/// [limbs] is how thick its arms and legs are against the usual, as a
/// style draws them; [gloves] puts white cartoon gloves on its hands.
Gltf buildHuman(HumanPack pack, CharacterDna dna,
    {List<WearMesh> wearing = const [],
    bool drawnFace = false,
    double limbs = 1,
    bool gloves = false,
    double? gender}) {
  var n = pack.vertexCount;
  var pos = Float32List.fromList(pack.base);
  void apply(String name, double w) {
    if (w == 0) return;
    var t = pack.targets[name];
    if (t == null) return;
    var (idx, d) = t;
    var k = w / 2000;
    for (var i = 0; i < idx.length; i++) {
      var v = idx[i] * 3;
      pos[v] += d[i * 3] * k;
      pos[v + 1] += d[i * 3 + 1] * k;
      pos[v + 2] += d[i * 3 + 2] * k;
    }
  }

  void applySided(String name, double w) {
    if (name.contains("X-")) {
      apply(name.replaceFirst("X-", "l-"), w);
      apply(name.replaceFirst("X-", "r-"), w);
    } else {
      apply(name, w);
    }
  }

  var macro = humanMacroOf(dna, gender: gender);
  for (var e in macroWeights(macro).entries) {
    apply(e.key, e.value);
  }
  var look = dna.look;
  for (var e in lookTargets.entries) {
    var v = look[e.key];
    if (v == 0) continue;
    for (var (low, high) in e.value) {
      var name = v < 0 ? low : high;
      if (name != null) applySided(name, v.abs());
    }
  }
  // A woman's chest is her bust, fuller or smaller.
  var female = 1 - macro.gender;
  var chest = look[Look.chest];
  if (female > 0) {
    apply(chest >= 0 ? fullCup : smallCup, female * (chest >= 0 ? 0.35 + 0.65 * chest : -chest));
  }

  // Smooth anatomy: the chest, belly and groin are smoothed over, so the
  // body is shaped but carries no anatomical detail -- as the drawn
  // character's bare view has none. Done before the skeleton is fitted.
  _smoothTorso(pack, pos);

  // A style's proportions: as many heads tall as it draws people, against
  // the type's usual -- a chibi's head grown and its body made small, a
  // webtoon's head a little smaller. grow is how much each vertex was
  // scaled, so the face's movements scale with it.
  var grow = _proportion(pack, pos, dna.headsTall / dna.kind.dna.headsTall);

  // Where each joint is now, the middle of its vertices.
  List<double> joint(String name) {
    var vs = pack.joints[name] ?? const [];
    if (vs.isEmpty) return [0, 0, 0];
    var s = [0.0, 0.0, 0.0];
    for (var v in vs) {
      for (var c = 0; c < 3; c++) {
        s[c] += pos[v * 3 + c];
      }
    }
    return [for (var c in s) c / vs.length];
  }

  // The skeleton, parents before children.
  var order = <String>[];
  void place(String b) {
    if (order.contains(b)) return;
    var p = pack.bones[b]!.parent;
    if (p != null && pack.bones.containsKey(p)) place(p);
    order.add(b);
  }

  for (var b in pack.bones.keys) {
    place(b);
  }
  var index = {for (var (i, b) in order.indexed) b: i};
  var heads = {for (var b in order) b: joint(pack.bones[b]!.head)};
  var nodes = <GltfNode>[];
  for (var b in order) {
    var bone = pack.bones[b]!;
    var h = heads[b]!;
    var p = bone.parent == null ? null : heads[bone.parent];
    nodes.add(GltfNode(
        b,
        [
          for (var c in order)
            if (pack.bones[c]!.parent == b) index[c]!,
        ],
        p == null ? h : [h[0] - p[0], h[1] - p[1], h[2] - p[2]],
        Quat.identity,
        const [1, 1, 1],
        null,
        null,
        null));
  }
  for (var (i, node) in nodes.indexed) {
    for (var c in node.children) {
      nodes[c].parent = i;
    }
  }
  var inverseBind = [
    for (var b in order)
      Mat4.trs([-heads[b]![0], -heads[b]![1], -heads[b]![2]], Quat.identity,
          const [1, 1, 1]),
  ];

  // A drawn face's eyes and mouth are drawn: the lids under them shut, and
  // the lips smoothed into the face, so there are not two of each.
  if (drawnFace) {
    for (var side in ["left", "right"]) {
      if (pack.targets["expression/units/caucasian/eye-$side-closure"]
          case (var idx, var d)) {
        for (var k = 0; k < idx.length; k++) {
          if (idx[k] * 3 + 2 >= pos.length) continue;
          for (var c = 0; c < 3; c++) {
            pos[idx[k] * 3 + c] += d[k * 3 + c] / 2000 * grow[idx[k]];
          }
        }
      }
    }
    if (_mouthAt(pack, pos, heads["eye.L"] ?? const [0.3, 7.0, 1.0],
            heads["eye.R"] ?? const [-0.3, 7.0, 1.0])
        case var m?) {
      _smoothLips(pack, pos, grow, m,
          ((heads["eye.L"]?[0] ?? 0.3) - (heads["eye.R"]?[0] ?? -0.3)).abs());
    }
  }

  // A style's limbs: thinner, drawn in towards the bones down them.
  var wrists = dna.look[Look.wrists], ankles = dna.look[Look.ankles];
  if ((limbs - 1).abs() > 0.01 || gloves || wrists != 0 || ankles != 0) {
    _shapeLimbs(pack, pos, heads, limbs, gloves ? 1.25 : 1,
        wrists: wrists, ankles: ankles);
  }

  // Each vertex's four strongest bones.
  var best = List.generate(n, (_) => <(int, double)>[]);
  for (var e in pack.weights.entries) {
    var bi = index[e.key];
    if (bi == null) continue;
    for (var (v, w) in e.value) {
      if (v < n) best[v].add((bi, w));
    }
  }

  // Normals from the body's faces, so it is lit as a surface.
  var normals = Float32List(n * 3);
  for (var g in pack.groups.values) {
    for (var k = 0; k + 5 < g.length; k += 6) {
      var a = g[k] * 3, b = g[k + 2] * 3, c = g[k + 4] * 3;
      var ux = pos[b] - pos[a], uy = pos[b + 1] - pos[a + 1], uz = pos[b + 2] - pos[a + 2];
      var wx = pos[c] - pos[a], wy = pos[c + 1] - pos[a + 1], wz = pos[c + 2] - pos[a + 2];
      var nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
      for (var v in [a, b, c]) {
        normals[v] += nx;
        normals[v + 1] += ny;
        normals[v + 2] += nz;
      }
    }
  }

  // Clothes painted on by which bone the skin follows; skin elsewhere.
  var colours = BodyColours(dna);
  // Clothes over the body, made from it; the skin under them is skin.
  var shells = garmentShells(
      dna: dna,
      pos: pos,
      corners: pack.groups["body"] ?? Uint32List(0),
      best: best,
      bones: order,
      heads: heads);
  if (shells.pieces.isNotEmpty) {
    colours
      ..torso = colours.skin
      ..upperArm = colours.skin
      ..foreArm = colours.skin
      ..pelvis = colours.skin
      ..thigh = colours.skin
      ..shin = colours.skin;
  }
  Color regionOf(String bone) {
    if (bone.contains("upperarm") || bone.contains("shoulder") ||
        bone.contains("clavicle")) {
      return colours.upperArm;
    }
    if (bone.contains("lowerarm")) return colours.foreArm;
    if (bone.contains("spine") || bone.contains("breast")) return colours.torso;
    if (bone == "root" || bone.contains("pelvis")) return colours.pelvis;
    if (bone.contains("upperleg")) return colours.thigh;
    if (bone.contains("lowerleg")) return colours.shin;
    if (bone.contains("foot") || bone.contains("toe")) return colours.foot;
    if (gloves &&
        (bone.contains("wrist") || bone.contains("finger") ||
            bone.contains("metacarpal") || bone.contains("thumb"))) {
      return const Color(0xFFF7F5F0);
    }
    return colours.skin;
  }

  var boneColour = [for (var b in order) regionOf(b)];

  // The head's landmarks: the eyes, the top of the head, the nape.
  var eyeL = heads["eye.L"] ?? [0.3, 7.0, 1.0];
  var eyeR = heads["eye.R"] ?? [-0.3, 7.0, 1.0];
  var eye = [for (var c = 0; c < 3; c++) (eyeL[c] + eyeR[c]) / 2];
  var top = pack.bones["head"] == null ? [0.0, 8.5, 0.0] : joint(pack.bones["head"]!.tail);
  var span = math.max(0.1, top[1] - eye[1]);
  var eyeGap = (eyeL[0] - eyeR[0]).abs();
  var hairline = dna.look[Look.hairline];
  // Scalp: above the hairline at the front, down to the nape behind.
  bool scalp(int v) {
    var x = pos[v * 3], y = pos[v * 3 + 1], z = pos[v * 3 + 2];
    var rel = (y - eye[1]) / span;
    var front = z > eye[2] - 0.35 * span;
    if (front) return rel > 0.5 - 0.15 * hairline;
    var ears = (x - eye[0]).abs() > eyeGap * 0.9 && rel < 0.2 && z > eye[2] - 0.9 * span;
    if (ears) return false;
    return rel > -0.75;
  }

  var onScalp = List.generate(n, (v) => pack.base.length > v * 3 && scalp(v));
  // Brows: a band over each eye.
  var brow = List.generate(n, (v) {
    var x = pos[v * 3], y = pos[v * 3 + 1], z = pos[v * 3 + 2];
    var rel = (y - eye[1]) / span;
    if (z < eye[2] - 0.1 * span) return false;
    var nearL = (x - eyeL[0]).abs() < eyeGap * 0.4;
    var nearR = (x - eyeR[0]).abs() < eyeGap * 0.4;
    return (nearL || nearR) &&
        rel > 0.17 + 0.05 * dna.look[Look.browHeight] &&
        rel < 0.225 + 0.05 * dna.look[Look.browHeight] + 0.03 * dna.look[Look.browThickness];
  });

  // What is worn hides the body under it.
  var hidden = <int>{for (var w in wearing) ...w.hides};

  var wearsBrows = wearing.any((w) => w.item.kind == WearKind.eyebrows);
  var wearsHair = wearing.any((w) => w.item.kind == WearKind.hair);

  // The pieces, each its own vertices.
  var primitives = <GltfPrimitive>[];
  var materials = <GltfMaterial>[];
  var expressionNames = expressionTargets.keys.toList();
  for (var e in pack.groups.entries) {
    var isHair = e.key == "helper-hair";
    var isEye = e.key.startsWith("helper-l-eye") || e.key.startsWith("helper-r-eye");
    var isLash = e.key.contains("eyelashes");
    // MakeHuman's hair helper is a guide for fitting long hair, not hair:
    // the hair is grown from the scalp instead, below.
    if (isHair) continue;
    if (drawnFace && isLash) continue;
    var corners = e.value;
    if ((hidden.isNotEmpty || shells.hides.isNotEmpty) && e.key == "body") {
      var kept = <int>[];
      for (var k = 0; k + 5 < corners.length; k += 6) {
        if (shells.hides.contains(k)) continue;
        if (hidden.contains(corners[k]) &&
            hidden.contains(corners[k + 2]) &&
            hidden.contains(corners[k + 4])) {
          continue;
        }
        kept.addAll(corners.sublist(k, k + 6));
      }
      corners = Uint32List.fromList(kept);
    }
    var remap = <int, int>{};
    var src = <int>[], uvIdx = <int>[];
    var indices = Uint32List(corners.length ~/ 2);
    for (var k = 0; k < corners.length ~/ 2; k++) {
      var v = corners[k * 2], t = corners[k * 2 + 1];
      var key = v * 65536 + t;
      var at = remap[key];
      if (at == null) {
        at = src.length;
        remap[key] = at;
        src.add(v);
        uvIdx.add(t);
      }
      indices[k] = at;
    }
    var m = src.length;
    var p = Float32List(m * 3), nm = Float32List(m * 3), uv = Float32List(m * 2);
    var joints = Uint16List(m * 4), weights = Float32List(m * 4);
    var col = Float32List(m * 4);
    // An eye's middle and size, for where its iris goes.
    var centre = [0.0, 0.0, 0.0];
    var radius = 1.0;
    if (isEye) {
      for (var v in src) {
        for (var c = 0; c < 3; c++) {
          centre[c] += pos[v * 3 + c] / m;
        }
      }
      radius = 0;
      for (var v in src) {
        radius = math.max(radius, (pos[v * 3 + 2] - centre[2]).abs());
      }
    }
    // Hair stands a little off the scalp, more for fuller hair.
    var lift = isHair ? 0.03 + 0.08 * math.max(0.0, look[Look.hairVolume]) : 0.0;
    for (var i = 0; i < m; i++) {
      var v = src[i];
      var nl = math.sqrt(normals[v * 3] * normals[v * 3] +
          normals[v * 3 + 1] * normals[v * 3 + 1] +
          normals[v * 3 + 2] * normals[v * 3 + 2]);
      for (var c = 0; c < 3; c++) {
        var nc = nl == 0 ? 0.0 : normals[v * 3 + c] / nl;
        nm[i * 3 + c] = nc;
        p[i * 3 + c] = pos[v * 3 + c] + nc * lift;
      }
      if (uvIdx[i] * 2 + 1 < pack.uvs.length) {
        uv[i * 2] = pack.uvs[uvIdx[i] * 2];
        uv[i * 2 + 1] = 1 - pack.uvs[uvIdx[i] * 2 + 1];
      }
      var ws = [...best[v]]..sort((a, b) => b.$2.compareTo(a.$2));
      var total = 0.0;
      for (var k = 0; k < 4 && k < ws.length; k++) {
        total += ws[k].$2;
      }
      for (var k = 0; k < 4 && k < ws.length; k++) {
        joints[i * 4 + k] = ws[k].$1;
        weights[i * 4 + k] = total == 0 ? 0 : ws[k].$2 / total;
      }
      Color c;
      if (isEye && drawnFace) {
        c = colours.skin;
      } else if (isEye) {
        var front = (pos[v * 3 + 2] - centre[2]) / (radius == 0 ? 1 : radius);
        c = front > 0.975
            ? const Color(0xFF15100C)
            : front > 0.86
                ? Color.lerp(dna.eyes, const Color(0xFFFFFFFF), 0.12)!
                : front > 0.82
                    ? Color.lerp(dna.eyes, const Color(0xFF000000), 0.4)!
                    : const Color(0xFFF4F1EC);
      } else if (isHair) {
        c = dna.hair;
      } else if (isLash) {
        c = const Color(0xFF1B1512);
      } else if (ws.isEmpty) {
        c = colours.skin;
      } else {
        // Blended by how much the skin follows each bone, so where clothes
        // end is a soft edge rather than the mesh's own steps.
        // Weights raised to a power: the change from one colour to the
        // next is a narrow band, nearly a line, as clothes end.
        var r = 0.0, g = 0.0, bl = 0.0;
        var sharp = 0.0;
        for (var k = 0; k < 4 && k < ws.length; k++) {
          sharp += math.pow(ws[k].$2, 6);
        }
        for (var k = 0; k < 4 && k < ws.length; k++) {
          var w = sharp == 0 ? 0.0 : math.pow(ws[k].$2, 6) / sharp;
          var bc = boneColour[ws[k].$1];
          r += bc.r * w;
          g += bc.g * w;
          bl += bc.b * w;
        }
        c = Color.from(alpha: 1, red: r, green: g, blue: bl);
        if (brow[v] && !wearsBrows && !drawnFace) c = Color.lerp(c, dna.hair, 0.55)!;
      }
      col[i * 4] = c.r;
      col[i * 4 + 1] = c.g;
      col[i * 4 + 2] = c.b;
      col[i * 4 + 3] = 1;
    }
    // The face's movements, for the body only.
    var targets = <Float32List>[];
    if (e.key == "body") {
      for (var name in expressionNames) {
        var t = Float32List(m * 3);
        // A drawn face speaks and blinks with its drawn mouth and eyes.
        if (drawnFace && _drawnMoves.contains(name)) {
          targets.add(t);
          continue;
        }
        for (var (unit, w) in expressionTargets[name]!) {
          var tg = pack.targets["expression/units/caucasian/$unit"];
          if (tg == null) continue;
          var (idx, d) = tg;
          var moved = <int, (double, double, double)>{};
          for (var k = 0; k < idx.length; k++) {
            var g = idx[k] < grow.length ? grow[idx[k]] * w : w;
            moved[idx[k]] = (d[k * 3] / 2000 * g, d[k * 3 + 1] / 2000 * g,
                d[k * 3 + 2] / 2000 * g);
          }
          for (var i = 0; i < m; i++) {
            if (moved[src[i]] case var o?) {
              t[i * 3] += o.$1;
              t[i * 3 + 1] += o.$2;
              t[i * 3 + 2] += o.$3;
            }
          }
        }
        targets.add(t);
      }
    }
    materials.add(GltfMaterial(const [1, 1, 1, 1], null, isHair || isLash, false, false));
    primitives.add(GltfPrimitive(p, nm, uv, joints, weights, col, indices,
        materials.length - 1, targets));
  }

  // Hair: the scalp's triangles again, a little off it, in the hair's
  // colour -- fuller hair further off.
  if (dna.hairStyle != HairStyle.bald && !wearsHair) {
    var body = pack.groups["body"];
    if (body != null) {
      var remap = <int, int>{};
      var src = <int>[];
      var tris = <int>[];
      for (var k = 0; k + 5 < body.length; k += 6) {
        var a = body[k], b = body[k + 2], c = body[k + 4];
        if (!(onScalp[a] && onScalp[b] && onScalp[c])) continue;
        for (var v in [a, b, c]) {
          tris.add(remap.putIfAbsent(v, () {
            src.add(v);
            return src.length - 1;
          }));
        }
      }
      var m = src.length;
      var lift = 0.06 + 0.12 * math.max(0.0, look[Look.hairVolume]);
      var p = Float32List(m * 3), nm = Float32List(m * 3);
      var joints = Uint16List(m * 4), weights = Float32List(m * 4);
      var col = Float32List(m * 4);
      for (var i = 0; i < m; i++) {
        var v = src[i];
        var nl = math.sqrt(normals[v * 3] * normals[v * 3] +
            normals[v * 3 + 1] * normals[v * 3 + 1] +
            normals[v * 3 + 2] * normals[v * 3 + 2]);
        for (var c = 0; c < 3; c++) {
          var nc = nl == 0 ? 0.0 : normals[v * 3 + c] / nl;
          nm[i * 3 + c] = nc;
          p[i * 3 + c] = pos[v * 3 + c] + nc * lift;
        }
        var ws = [...best[v]]..sort((a, b) => b.$2.compareTo(a.$2));
        var total = 0.0;
        for (var k = 0; k < 4 && k < ws.length; k++) {
          total += ws[k].$2;
        }
        for (var k = 0; k < 4 && k < ws.length; k++) {
          joints[i * 4 + k] = ws[k].$1;
          weights[i * 4 + k] = total == 0 ? 0 : ws[k].$2 / total;
        }
        // Lighter at the crown, where the light falls on it.
        var shine = ((pos[v * 3 + 1] - eye[1]) / span).clamp(0.0, 1.0) *
            0.15 * (1 + look[Look.highlights]);
        var hc = Color.lerp(dna.hair, dna.hair2, shine)!;
        col[i * 4] = hc.r;
        col[i * 4 + 1] = hc.g;
        col[i * 4 + 2] = hc.b;
        col[i * 4 + 3] = 1;
      }
      materials.add(const GltfMaterial([1, 1, 1, 1], null, false, false, false));
      primitives.add(GltfPrimitive(p, nm, null, joints, weights, col,
          Uint32List.fromList(tris), materials.length - 1, const []));
    }
  }

  // What is worn, fitted to this body, skinned as the body under it is.
  var ankle = heads["foot.L"] ?? const [0.0, 0.0, 0.0];
  var knee = heads["lowerleg01.L"] ?? const [0.0, 1.0, 0.0];
  var sockLine = ankle[1] + (knee[1] - ankle[1]) * 0.12;
  var sock = dna.worn
          .where((g) => g.kind == GarmentKind.socks || g.kind == GarmentKind.tights)
          .lastOrNull
          ?.color ??
      const Color(0xFFEDEDEA);
  var hairLength = dna.look[Look.hairLength];
  var nape = (heads["neck01"] ?? const [0.0, 0.0, 0.0])[1];
  for (var (wi, w) in wearing.indexed) {
    var fitted = w.fit(pos);
    // Hair grown longer or cut shorter: what hangs below the nape drawn
    // down further, or up.
    if (w.item.kind == WearKind.hair && hairLength != 0) {
      var stretch = hairLength > 0 ? 1 + 1.2 * hairLength : 1 + 0.5 * hairLength;
      for (var v = 1; v < fitted.length; v += 3) {
        if (fitted[v] < nape) fitted[v] = nape - (nape - fitted[v]) * stretch;
      }
    }
    var remap = <int, int>{};
    var src = <int>[], uvIdx = <int>[];
    var tris = <int>[];
    for (var k = 0; k + 1 < w.corners.length; k += 2) {
      var v = w.corners[k], t = w.corners[k + 1];
      if (v * 3 + 2 >= fitted.length) continue;
      tris.add(remap.putIfAbsent(v * 65536 + t, () {
        src.add(v);
        uvIdx.add(t);
        return src.length - 1;
      }));
    }
    var m = src.length;
    var p = Float32List(m * 3), nm = Float32List(m * 3), uv = Float32List(m * 2);
    var joints = Uint16List(m * 4), weights = Float32List(m * 4);
    var col = Float32List(m * 4);
    for (var i = 0; i < m; i++) {
      for (var c = 0; c < 3; c++) {
        p[i * 3 + c] = fitted[src[i] * 3 + c];
      }
      if (uvIdx[i] * 2 + 1 < w.uvs.length) {
        uv[i * 2] = w.uvs[uvIdx[i] * 2];
        uv[i * 2 + 1] = w.uvs[uvIdx[i] * 2 + 1];
      }
    }
    // Its own surface's facing.
    for (var k = 0; k + 2 < tris.length; k += 3) {
      var a = tris[k] * 3, b = tris[k + 1] * 3, c = tris[k + 2] * 3;
      var ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
      var wx = p[c] - p[a], wy = p[c + 1] - p[a + 1], wz = p[c + 2] - p[a + 2];
      var nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
      for (var v in [a, b, c]) {
        nm[v] += nx;
        nm[v + 1] += ny;
        nm[v + 2] += nz;
      }
    }
    var colour = switch (w.item.kind) {
      WearKind.hair => dna.hair,
      WearKind.eyebrows => Color.lerp(dna.hair, const Color(0xFF000000), 0.25)!,
      WearKind.shoes => dna.worn
          .lastWhere((g) => g.kind.shape == GarmentShape.shoes)
          .color,
      WearKind.teeth => const Color(0xFFF2EEE4),
    };
    for (var i = 0; i < m; i++) {
      // Skinned as the three body vertices it is pinned to, that much each.
      var mix = <int, double>{};
      for (var k = 0; k < 3; k++) {
        var r = w.refs[src[i] * 3 + k];
        var share = w.weights[src[i] * 3 + k];
        if (share == 0 || r >= n) continue;
        for (var (bone, bw) in best[r]) {
          mix[bone] = (mix[bone] ?? 0) + bw * share;
        }
      }
      var ws = mix.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      var total = 0.0;
      for (var k = 0; k < 4 && k < ws.length; k++) {
        total += ws[k].value;
      }
      for (var k = 0; k < 4 && k < ws.length; k++) {
        joints[i * 4 + k] = ws[k].key;
        weights[i * 4 + k] = total == 0 ? 0 : ws[k].value / total;
      }
      // Shoes come with socks in them: above the ankle is the sock.
      var c = w.item.kind == WearKind.shoes && w.item.id != "shoes03" &&
              p[i * 3 + 1] > sockLine
          ? sock
          : colour;
      col[i * 4] = c.r;
      col[i * 4 + 1] = c.g;
      col[i * 4 + 2] = c.b;
      col[i * 4 + 3] = 1;
    }
    var cutOut = w.item.cutOut;
    materials.add(GltfMaterial(const [1, 1, 1, 1], cutOut ? wi : null,
        w.item.kind == WearKind.hair || w.item.kind == WearKind.eyebrows,
        false, cutOut,
        cutOut: cutOut));
    primitives.add(GltfPrimitive(p, nm, uv, joints, weights, col,
        Uint32List.fromList(tris), materials.length - 1, const []));
  }

  for (var shell in shells.pieces) {
    var m = shell.positions.length ~/ 3;
    var col = Float32List(m * 4);
    for (var i = 0; i < m; i++) {
      col[i * 4] = shell.colour.r;
      col[i * 4 + 1] = shell.colour.g;
      col[i * 4 + 2] = shell.colour.b;
      col[i * 4 + 3] = 1;
    }
    materials.add(GltfMaterial(const [1, 1, 1, 1], null, shell.open, false, false));
    primitives.add(GltfPrimitive(shell.positions, shell.normals, Float32List(m * 2),
        shell.joints, shell.weights, col, shell.triangles, materials.length - 1,
        const []));
  }

  // Where the mouth is, for a face drawn on the head: a point riding on
  // the head, at the top of the lower lip -- the middle of what moves
  // most as the mouth opens.
  if (index["head"] case var head?) {
    if (_mouthAt(pack, pos, eyeL, eyeR) case var m?) {
      var h = heads["head"]!;
      nodes[head].children.add(nodes.length);
      nodes.add(GltfNode(mouthLandmark, [], [m[0] - h[0], m[1] - h[1], m[2] - h[2]],
          Quat.identity, const [1, 1, 1], null, null, null)
        ..parent = head);
    }
  }

  // The body first, so its face shapes are the mesh's.
  primitives.sort((a, b) => b.targets.length.compareTo(a.targets.length));
  var mesh = GltfMesh("Body", primitives, expressionNames,
      List.filled(expressionNames.length, 0));
  var meshNode = GltfNode("Body", const [], const [0, 0, 0], Quat.identity,
      const [1, 1, 1], null, 0, 0);
  nodes.add(meshNode);
  var root = index["root"] ?? 0;
  return Gltf(
    nodes,
    [mesh],
    [GltfSkin([for (var i = 0; i < order.length; i++) i], inverseBind)],
    materials,
    const [],
    [root, nodes.length - 1],
    {
      for (var e in _humanoid.entries)
        if (index[e.value] case var i?) e.key: i,
    },
    {
      for (var (i, name) in expressionNames.indexed)
        name: [(mesh: 0, target: i, weight: 1.0)],
    },
    null,
    "MakeHuman",
  );
}


/// _mouthAt is the top of the lower lip on the body at [pos], found by
/// what opening the mouth moves: the highest of the vertices down the
/// middle of the face that move at least half as far as any.
List<double>? _mouthAt(
    HumanPack pack, Float32List pos, List<double> eyeL, List<double> eyeR) {
  var tg = pack.targets["expression/units/caucasian/mouth-open"];
  if (tg == null) return null;
  var (idx, d) = tg;
  var mid = (eyeL[0] + eyeR[0]) / 2;
  var gap = (eyeL[0] - eyeR[0]).abs();
  var most = 0.0;
  for (var k = 0; k < idx.length; k++) {
    most = math.max(most, -d[k * 3 + 1].toDouble());
  }
  if (most <= 0) return null;
  var moving = [
    for (var k = 0; k < idx.length; k++)
      if (idx[k] * 3 + 2 < pos.length &&
          -d[k * 3 + 1] >= most * 0.5 &&
          (pos[idx[k] * 3] - mid).abs() <= gap * 0.15)
        idx[k],
  ];
  if (moving.isEmpty) return null;
  // The lip's front: not the inside of the mouth, which moves too.
  var front = moving.map((v) => pos[v * 3 + 2]).reduce(math.max);
  List<double>? best;
  for (var v in moving) {
    if (pos[v * 3 + 2] < front - gap * 0.15) continue;
    if (best == null || pos[v * 3 + 1] > best[1]) {
      best = [pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]];
    }
  }
  return best;
}

/// _drawnMoves is the face's movements a drawn face makes itself.
const Set<String> _drawnMoves = {"blink", "aa", "ih", "ou", "ee", "oh"};

/// _smoothLips smooths [pos] round the mouth at [mouth] -- an oval as wide
/// as the eyes are far apart, [gap] -- most in the middle.
void _smoothLips(HumanPack pack, Float32List pos, Float32List grow,
    List<double> mouth, double gap) {
  var body = pack.groups["body"];
  if (body == null || gap <= 0) return;
  var n = pack.vertexCount;
  // The lips shut first -- the mouth opened the other way -- so nothing
  // behind them shows between them.
  if (pack.targets["expression/units/caucasian/mouth-open"] case (var idx, var dd)) {
    for (var k = 0; k < idx.length; k++) {
      var v = idx[k];
      if (v * 3 + 2 >= pos.length) continue;
      for (var c = 0; c < 3; c++) {
        pos[v * 3 + c] -= dd[k * 3 + c] / 2000 * 0.3 * grow[v];
      }
    }
  }
  var amount = <int, double>{};
  for (var v = 0; v < n; v++) {
    var dx = (pos[v * 3] - mouth[0]) / (gap * 0.6);
    var dy = (pos[v * 3 + 1] - mouth[1]) / (gap * 0.32);
    var dz = pos[v * 3 + 2] - mouth[2];
    // The front of the face only: not the inside of the mouth behind it.
    if (dz < -gap * 0.1) continue;
    var d = dx * dx + dy * dy;
    if (d < 1) amount[v] = 0.8 * (1 - d) * (1 - d);
  }
  var near = <int, Set<int>>{};
  for (var k = 0; k + 5 < body.length; k += 6) {
    var tri = [body[k], body[k + 2], body[k + 4]];
    for (var a in tri) {
      if (!amount.containsKey(a)) continue;
      var set = near.putIfAbsent(a, () => {});
      for (var b in tri) {
        if (b != a) set.add(b);
      }
    }
  }
  for (var pass = 0; pass < 12; pass++) {
    var next = <int, List<double>>{};
    for (var e in amount.entries) {
      var ns = near[e.key];
      if (ns == null || ns.isEmpty) continue;
      next[e.key] = [
        for (var c = 0; c < 3; c++)
          pos[e.key * 3 + c] +
              (ns.fold(0.0, (a, u) => a + pos[u * 3 + c]) / ns.length -
                      pos[e.key * 3 + c]) *
                  e.value,
      ];
    }
    for (var e in next.entries) {
      pos.setAll(e.key * 3, e.value);
    }
  }
}

/// _proportion makes the body at [pos] [ratio] times as many heads tall as
/// it is: the head scaled about the chin, and -- past how far a head can
/// sensibly grow -- the body below it made smaller about the same point,
/// so the head is that share of the whole. Each vertex's scale, returned.
Float32List _proportion(HumanPack pack, Float32List pos, double ratio) {
  var n = pack.vertexCount;
  var grow = Float32List(n)..fillRange(0, n, 1);
  if ((ratio - 1).abs() < 0.02) return grow;
  List<double>? at(String bone) {
    var b = pack.bones[bone];
    var vs = b == null ? null : pack.joints[b.head];
    if (vs == null || vs.isEmpty) return null;
    var p = [0.0, 0.0, 0.0];
    for (var v in vs) {
      for (var c = 0; c < 3; c++) {
        p[c] += pos[v * 3 + c] / vs.length;
      }
    }
    return p;
  }

  var eyeL = at("eye.L"), eyeR = at("eye.R"), neck = at("neck01");
  if (eyeL == null || eyeR == null || neck == null) return grow;
  var body = pack.groups["body"];
  var low = double.infinity, high = -double.infinity;
  for (var k = 0; body != null && k < body.length; k += 2) {
    var y = pos[body[k] * 3 + 1];
    low = math.min(low, y);
    high = math.max(high, y);
  }
  if (!low.isFinite) return grow;
  // The eyes are halfway down the head.
  var eyeY = (eyeL[1] + eyeR[1]) / 2;
  var head = 2 * (high - eyeY);
  var tall = high - low;
  if (head <= 0 || tall <= head) return grow;
  var heads = math.max(1.2, tall / head * ratio);
  // How much the head alone would have to grow; past 1.6 it grows less and
  // the body shrinks the rest of the way.
  var r = (tall - head) / (head * (heads - 1));
  var h = r <= 1.6 ? r : 1.6 * math.sqrt(r / 1.6);
  var f = h / r;
  var chin = [neck[0], eyeY - head / 2, neck[2]];
  for (var v = 0; v < n && v * 3 + 2 < pos.length; v++) {
    var y = pos[v * 3 + 1];
    // Head above the chin, body below the neck's base, blended between.
    var t = ((y - (chin[1] - head * 0.25)) / (head * 0.25)).clamp(0.0, 1.0);
    t = t * t * (3 - 2 * t);
    var k = f + (h - f) * t;
    grow[v] = k;
    for (var c = 0; c < 3; c++) {
      pos[v * 3 + c] = chin[c] + (pos[v * 3 + c] - chin[c]) * k;
    }
  }
  return grow;
}

/// _shapeLimbs draws each arm and leg at [pos] in towards its bones, to
/// [limbs] of its thickness, and makes the hands [hands] times as big about
/// the wrist -- as much as each vertex follows the limb.
///
/// [wrists] and [ankles] narrow or thicken the forearm and the shin from
/// the elbow and the knee down, as the Appearance says.
void _shapeLimbs(HumanPack pack, Float32List pos,
    Map<String, List<double>> heads, double limbs, double hands,
    {double wrists = 0, double ankles = 0}) {
  var n = pack.vertexCount;
  var limb = Float32List(n), hand = Float32List(n);
  var side = List<int>.filled(n, 0);
  var leg = List<bool>.filled(n, false);
  var most = Float32List(n);
  for (var e in pack.weights.entries) {
    var b = e.key;
    var isArm = b.contains("upperarm") || b.contains("lowerarm");
    var isLeg = b.contains("upperleg") || b.contains("lowerleg");
    var isHand = b.contains("wrist") || b.contains("finger") ||
        b.contains("metacarpal") || b.contains("thumb");
    if (!isArm && !isLeg && !isHand) continue;
    for (var (v, w) in e.value) {
      if (v >= n) continue;
      if (isHand) {
        hand[v] += w;
      } else {
        limb[v] += w;
      }
      if (w > most[v]) {
        most[v] = w;
        side[v] = b.endsWith(".L") ? 1 : -1;
        leg[v] = isLeg;
      }
    }
  }
  List<double> at(String b) => heads[b] ?? const [0.0, 0.0, 0.0];
  // The bones down each limb, as lines to draw in towards.
  List<List<double>> chain(bool isLeg, int s) {
    var x = s > 0 ? "L" : "R";
    return isLeg
        ? [at("upperleg01.$x"), at("lowerleg01.$x"), at("foot.$x")]
        : [at("upperarm01.$x"), at("lowerarm01.$x"), at("wrist.$x")];
  }

  for (var v = 0; v < n && v * 3 + 2 < pos.length; v++) {
    if (side[v] == 0) continue;
    var p = [pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]];
    if (hand[v] > 0.5 && hands != 1) {
      var wrist = at("wrist.${side[v] > 0 ? "L" : "R"}");
      var k = 1 + (hands - 1) * hand[v].clamp(0.0, 1.0);
      for (var c = 0; c < 3; c++) {
        pos[v * 3 + c] = wrist[c] + (p[c] - wrist[c]) * k;
      }
      continue;
    }
    var share = limb[v].clamp(0.0, 1.0);
    var taper = leg[v] ? ankles : wrists;
    if (share == 0 || (limbs == 1 && taper == 0)) continue;
    // The nearest point on the bones.
    var bones = chain(leg[v], side[v]);
    List<double>? best;
    var bestD = double.infinity;
    var down = 0.0;
    for (var i = 0; i + 1 < bones.length; i++) {
      var a = bones[i], b = bones[i + 1];
      var ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
      var len2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
      if (len2 <= 0) continue;
      var t = (((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1] + (p[2] - a[2]) * ab[2]) /
              len2)
          .clamp(0.0, 1.0);
      var q = [a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t];
      var d = math.pow(p[0] - q[0], 2) + math.pow(p[1] - q[1], 2) + math.pow(p[2] - q[2], 2);
      if (d < bestD) {
        bestD = d.toDouble();
        best = q;
        // How far down the forearm or shin, for the taper to the end.
        down = i == 1 ? t : 0;
      }
    }
    if (best == null) continue;
    var k = (1 + (limbs - 1) * share) *
        (1 + 0.35 * taper * math.pow(down, 1.3) * share);
    for (var c = 0; c < 3; c++) {
      pos[v * 3 + c] = best[c] + (p[c] - best[c]) * k;
    }
  }
}

/// _smoothed is the bones whose skin is smoothed over -- see _smoothTorso.
bool _smoothed(String bone) =>
    bone.startsWith("spine") ||
    bone.startsWith("breast") ||
    bone.startsWith("pelvis") ||
    bone == "root";

/// _smoothTorso smooths [pos] over the chest, belly and groin: each vertex
/// moved towards the middle of its neighbours, as much as it follows the
/// bones there, several times over.
void _smoothTorso(HumanPack pack, Float32List pos) {
  var n = pack.vertexCount;
  var amount = Float32List(n);
  for (var e in pack.weights.entries) {
    if (!_smoothed(e.key)) continue;
    for (var (v, w) in e.value) {
      if (v < n) amount[v] += w;
    }
  }
  var body = pack.groups["body"];
  if (body == null) return;
  var near = List.generate(n, (_) => <int>{});
  for (var k = 0; k + 5 < body.length; k += 6) {
    var a = body[k], b = body[k + 2], c = body[k + 4];
    if (amount[a] == 0 && amount[b] == 0 && amount[c] == 0) continue;
    near[a]..add(b)..add(c);
    near[b]..add(a)..add(c);
    near[c]..add(a)..add(b);
  }
  var next = Float32List.fromList(pos);
  for (var pass = 0; pass < 10; pass++) {
    for (var v = 0; v < n; v++) {
      var w = amount[v].clamp(0.0, 1.0) * 0.6;
      if (w == 0 || near[v].isEmpty) continue;
      for (var c = 0; c < 3; c++) {
        var sum = 0.0;
        for (var u in near[v]) {
          sum += pos[u * 3 + c];
        }
        var mid = sum / near[v].length;
        next[v * 3 + c] = pos[v * 3 + c] + (mid - pos[v * 3 + c]) * w;
      }
    }
    pos.setAll(0, next);
  }
}
