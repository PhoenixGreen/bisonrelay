import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/human_targets.dart';
import 'package:bruig/plugin_system/canvas/model/elements/human_wear.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_body.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_garments.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_wear_fit.dart';
import 'package:bruig/plugin_system/canvas/render/model/model_figure.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/human_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/human_wear_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/remote_zip.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_human_body_test.dart is the sculpted body: MakeHuman's files packed
// and read back, a character made of them -- shaped by its type and its
// Appearance, rigged, posed -- and the rules the download keeps.
//
// The real body is 26 MB fetched once; these tests make a small one with
// the same skeleton, joints and file layout, so they run with no network.

/// _bones is the fixture's skeleton: name, parent, head joint position.
const List<(String, String?, List<double>)> _bones = [
  ("root", null, [0, 9, 0]),
  ("spine05", "root", [0, 10, 0]),
  ("neck01", "spine05", [0, 14.5, 0]),
  ("head", "neck01", [0, 15.5, 0]),
  ("eye.L", "head", [0.3, 16.2, 0.8]),
  ("eye.R", "head", [-0.3, 16.2, 0.8]),
  ("upperarm01.L", "spine05", [2, 14, 0]),
  ("lowerarm01.L", "upperarm01.L", [5, 14, 0]),
  ("wrist.L", "lowerarm01.L", [7.5, 14, 0]),
  ("upperarm01.R", "spine05", [-2, 14, 0]),
  ("lowerarm01.R", "upperarm01.R", [-5, 14, 0]),
  ("wrist.R", "lowerarm01.R", [-7.5, 14, 0]),
  ("upperleg01.L", "root", [1, 9, 0]),
  ("lowerleg01.L", "upperleg01.L", [1, 4.5, 0]),
  ("foot.L", "lowerleg01.L", [1, 0.5, 0]),
  ("upperleg01.R", "root", [-1, 9, 0]),
  ("lowerleg01.R", "upperleg01.R", [-1, 4.5, 0]),
  ("foot.R", "lowerleg01.R", [-1, 0.5, 0]),
];

/// _tail is where each bone ends: its first child's head, or a step on.
List<double> _tail(int i) {
  var name = _bones[i].$1;
  for (var b in _bones) {
    if (b.$2 == name) return b.$3;
  }
  var h = _bones[i].$3;
  return [h[0], h[1] + 0.8, h[2] + (name.startsWith("eye") ? 0.3 : 0)];
}

/// _write writes the fixture as MakeHuman lays its files out, under
/// [root]: a box on each bone, a vertex at each joint, a nose that a target
/// widens and a mouth that opens.
void _write(String root) {
  var obj = StringBuffer("# fixture\n");
  var v = 0;
  var joints = <String, List<int>>{};
  var weights = <String, List<List<num>>>{};
  var faces = StringBuffer();
  for (var (i, b) in _bones.indexed) {
    var h = b.$3, t = _tail(i);
    // The joint vertices, which skin follows nothing.
    obj.writeln("v ${h[0]} ${h[1]} ${h[2]}");
    joints["${b.$1}____head"] = [v++];
    obj.writeln("v ${t[0]} ${t[1]} ${t[2]}");
    joints["${b.$1}____tail"] = [v++];
    // A box along the bone.
    var first = v;
    for (var c = 0; c < 8; c++) {
      var p = [
        for (var k = 0; k < 3; k++)
          (c & (1 << k)) == 0 ? (h[k] < t[k] ? h[k] : t[k]) - 0.3 : (h[k] > t[k] ? h[k] : t[k]) + 0.3,
      ];
      obj.writeln("v ${p[0]} ${p[1]} ${p[2]}");
      (weights[b.$1] ??= []).add([v, 1]);
      v++;
    }
    const quads = [
      [0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5],
    ];
    for (var q in quads) {
      faces.writeln("f ${[for (var k in q) "${first + k + 1}/1"].join(" ")}");
    }
  }
  obj.writeln("vt 0 0");
  obj.writeln("g body");
  obj.write(faces);
  File("$root/3dobjs/base.obj")
    ..createSync(recursive: true)
    ..writeAsStringSync(obj.toString());
  File("$root/rigs/default.mhskel")
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode({
      "bones": {
        for (var b in _bones)
          b.$1: {"head": "${b.$1}____head", "tail": "${b.$1}____tail", "parent": b.$2},
      },
      "joints": joints,
    }));
  File("$root/rigs/default_weights.mhw").writeAsStringSync(jsonEncode({"weights": weights}));
  // Every target the body asks for, empty -- but a nose that widens and a
  // mouth that opens, on the head's box.
  var headBox = 2 + _bones.indexWhere((b) => b.$1 == "head") * 10;
  for (var t in humanTargetFiles()) {
    var f = File("$root/targets/$t.target")..createSync(recursive: true);
    if (t == "nose/nose-scale-horiz-incr") {
      f.writeAsStringSync("$headBox 1.5 0 0\n");
    } else if (t == "expression/units/caucasian/mouth-open") {
      // And the head's joint, down the middle of the face, as the lip.
      var headJoint = _bones.indexWhere((b) => b.$1 == "head") * 10;
      f.writeAsStringSync("${headBox + 1} 0 -1 0\n$headJoint 0 -1 0\n");
    } else if (t == "macrodetails/universal-female-young-averagemuscle-averageweight") {
      f.writeAsStringSync("${headBox + 2} 0 0 0.25\n");
    } else {
      f.writeAsStringSync("# nothing\n");
    }
  }
}

late HumanPack _pack;

/// _headBox is the first vertex of the box on the head bone, and _wristBox
/// of the left wrist's.
final _headBox = 2 + _bones.indexWhere((b) => b.$1 == "head") * 10;
final _wristBox = 2 + _bones.indexWhere((b) => b.$1 == "wrist.L") * 10;

/// _hair is a piece of hair: one card pinned to the head's box, as
/// MakeHuman's are -- and, to see delete_verts read, hiding the wrist.
WearMesh _hair() => WearMesh.parse(
    wearItem("messy")!,
    "v 0 0 0\nv 0 0 0\nv 0 0 0\nvt 0 0\nvt 1 0\nvt 0 1\nf 1/1 2/2 3/3\n",
    "name messy\n"
    "x_scale $_headBox ${_headBox + 1} 0.3\n"
    "y_scale $_headBox ${_headBox + 2} 0.6\n"
    "z_scale $_headBox ${_headBox + 4} 0.6\n"
    "verts 0\n"
    "$_headBox ${_headBox + 1} ${_headBox + 2} 0.5 0.25 0.25 0 0.2 0\n"
    "${_headBox + 3} ${_headBox + 4} ${_headBox + 5} 1 0 0 0 0 0\n"
    "${_headBox + 6}\n"
    "delete_verts\n"
    "$_wristBox - ${_wristBox + 7}\n");

/// _zip is a zip of [files], the first stored, the rest deflated.
Uint8List _zip(Map<String, List<int>> files) {
  var out = BytesBuilder();
  var dir = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 255, v >> 8]);
  void u32(BytesBuilder b, int v) => b.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, v >> 24]);
  for (var (i, e) in files.entries.indexed) {
    var name = utf8.encode(e.key);
    var data = i == 0 ? e.value : ZLibEncoder(raw: true).convert(e.value);
    var method = i == 0 ? 0 : 8;
    var at = out.length;
    u32(out, 0x04034b50);
    for (var v in [20, 0, method, 0, 0]) {
      u16(out, v);
    }
    u32(out, 0);
    u32(out, data.length);
    u32(out, e.value.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(data);
    u32(dir, 0x02014b50);
    for (var v in [20, 20, 0, method, 0, 0]) {
      u16(dir, v);
    }
    u32(dir, 0);
    u32(dir, data.length);
    u32(dir, e.value.length);
    for (var v in [name.length, 0, 0, 0, 0]) {
      u16(dir, v);
    }
    u32(dir, 0);
    u32(dir, at);
    dir.add(name);
  }
  var cdAt = out.length, cd = dir.takeBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  for (var v in [0, 0, files.length, files.length]) {
    u16(out, v);
  }
  u32(out, cd.length);
  u32(out, cdAt);
  u16(out, 0);
  return out.takeBytes();
}

void main() {
  setUpAll(() {
    var dir = Directory.systemTemp.createTempSync("human");
    _write(dir.path);
    var bytes = packHumanFiles(dir.path);
    _pack = HumanPack.read(bytes, File("${dir.path}/rigs/default.mhskel").readAsStringSync(),
        File("${dir.path}/rigs/default_weights.mhw").readAsStringSync());
    dir.deleteSync(recursive: true);
  });

  group("the pack", () {
    test("keeps the mesh, its pieces, the shapes and the skeleton", () {
      expect(_pack.vertexCount, _bones.length * 10);
      expect(_pack.groups.keys, ["body"]);
      expect(_pack.groups["body"]!.length, _bones.length * 12 * 3 * 2);
      expect(_pack.bones.keys, containsAll(["root", "head", "wrist.L"]));
      expect(_pack.targets.containsKey("nose/nose-scale-horiz-incr"), isTrue);
      // The three peoples are blended into one target per sex and age.
      expect(_pack.targets.containsKey("macro/female-young"), isTrue);
      expect(_pack.targets.keys.any((k) => k.contains("african")), isFalse);
    });
  });

  group("the targets", () {
    test("every target named is one file, sides apart", () {
      var files = humanTargetFiles();
      expect(files.where((f) => f.contains("X-")), isEmpty);
      expect(files.toSet().length, files.length);
      expect(files, contains("eyes/l-eye-scale-incr"));
      expect(files, contains("eyes/r-eye-scale-incr"));
    });

    test("age, sex, muscle and weight blend to a whole", () {
      for (var t in [CharacterType.woman, CharacterType.boy, CharacterType.elder]) {
        var w = macroWeights(humanMacroOf(t.dna));
        var sex = w.entries.where((e) => e.key.startsWith("macro/"));
        expect(sex.fold(0.0, (a, e) => a + e.value), closeTo(1, 1e-9));
        var uni = w.entries.where((e) => e.key.contains("universal"));
        expect(uni.fold(0.0, (a, e) => a + e.value), closeTo(1, 1e-9));
      }
      expect(humanMacroOf(CharacterType.man.dna).gender, 1);
      expect(humanMacroOf(CharacterType.baby.dna).age, 0);
    });
  });

  group("a character made of it", () {
    test("is shaped by its Appearance", () {
      var dna = CharacterType.man.dna;
      var plain = buildHuman(_pack, dna);
      var wide = buildHuman(_pack, dna.copyWith(look: dna.look.withValue(Look.noseWidth, 1)));
      expect(wide.meshes.first.primitives.first.positions,
          isNot(plain.meshes.first.primitives.first.positions));
    });

    test("has a human skeleton, and face shapes for its expressions", () {
      var g = buildHuman(_pack, CharacterType.woman.dna);
      for (var b in [HumanBone.hips, HumanBone.head, HumanBone.leftUpperArm,
          HumanBone.rightFoot, HumanBone.neck]) {
        expect(g.humanoid.containsKey(b), isTrue, reason: "$b");
      }
      expect(g.expressions.keys, containsAll(["happy", "aa", "blink"]));
      var aa = g.meshes.first.targetNames.indexOf("aa");
      expect(g.meshes.first.primitives.first.targets[aa].any((d) => d != 0), isTrue);
    });

    test("is posed by the rig: arms made in a T hang at its sides", () async {
      var model = LoadedModel.of(buildHuman(_pack, CharacterType.man.dna), const []);
      var rig = CharacterRig.of(CharacterType.man.dna, CharacterElement.restPose,
          const Rect.fromLTWH(0, 0, 200, 400));
      var hand = model.boneAt(rig, CharacterFace.rest, HumanBone.leftHand)!;
      var neck = model.boneAt(rig, CharacterFace.rest, HumanBone.neck)!;
      expect(hand[1], lessThan(neck[1] - 2));
    });

    test("animals are not sculpted, but stand in as a mannequin", () {
      HumanBody.instance.useForTest(_pack);
      expect(HumanBody.instance.modelFor(CharacterType.dog.dna), isNull);
      expect(HumanBody.instance.modelFor(CharacterType.girl.dna), isNotNull);
    });
  });

  group("the download", () {
    test("is refused through a proxy, which it cannot use", () async {
      proxiedForTest = true;
      addTearDown(() => proxiedForTest = null);
      await expectLater(HumanAssets.install(),
          throwsA(predicate((e) => "$e".contains("proxy"))));
    });
  });

  group("what a sculpted body wears", () {
    test("a piece is pinned to the body, and stretches with it", () {
      var w = _hair();
      expect(w.vertexCount, 3);
      expect(w.hides, {for (var k = 0; k < 8; k++) _wristBox + k});
      var body = Float32List(_pack.vertexCount * 3);
      for (var v = 0; v < _pack.vertexCount; v++) {
        body[v * 3] = v.toDouble();
        body[v * 3 + 1] = 1;
      }
      var fitted = w.fit(body);
      // A share of each of three vertices, then off them.
      var x = 0.5 * _headBox + 0.25 * (_headBox + 1) + 0.25 * (_headBox + 2);
      expect(fitted[0], closeTo(x, 1e-4));
      // Off them along y by 0.2, scaled by how much taller the body is
      // between its two measuring vertices: here, not at all, so nought.
      expect(fitted[1], closeTo(1, 1e-4));
      expect(fitted[6], closeTo((_headBox + 6).toDouble(), 1e-4),
          reason: "a vertex pinned to one of the body's sits on it");
      expect(w.uvs.sublist(0, 2), [0, 1], reason: "pictures read the other way up");
    });

    test("is chosen from its style and its shoes", () {
      var wear = {
        for (var id in ["messy", "bobcut", "long", "brow1", "brow2", "shoes02", "shoes03", "teeth"])
          id: WearMesh(wearItem(id)!, Int32List(0), Float32List(0), Float32List(0),
              const [null, null, null], Float32List(0), Uint32List(0), const {}),
      };
      List<String> ids(CharacterDna d) => [for (var w in wearFor(d, wear)) w.item.id];
      var man = CharacterType.man.dna.copyWith(
          hairStyle: HairStyle.short,
          wardrobe: [const Garment(GarmentKind.boots, color: Color(0xFF000000))]);
      expect(ids(man), ["messy", "brow2", "shoes03", "teeth"]);
      expect(ids(man.copyWith(hairStyle: HairStyle.long)).first, "long");
      expect(ids(man.copyWith(hairModel: "bobcut")).first, "bobcut",
          reason: "a hair chosen is worn whatever the style");
      expect(ids(man.copyWith(hairStyle: HairStyle.bald)), isNot(contains("messy")));
      expect(ids(man.copyWith(wardrobe: const [])), isNot(contains("shoes03")),
          reason: "barefoot");
      expect(wearFor(man, const {}), isEmpty);
      expect(ids(man.copyWith(hairStyle: HairStyle.short)).first, "messy");
      expect([for (var w in wearFor(man, wear, prefer: "bobcut")) w.item.id].first,
          "bobcut", reason: "the hair its style gives it");
      expect([for (var w in wearFor(man.copyWith(hairModel: "long"), wear, prefer: "bobcut")) w.item.id].first,
          "long", reason: "a hair chosen beats the style's");
    });

    test("is worn: skinned to the head, cut out, and the skin under it hidden", () {
      var dna = CharacterType.man.dna;
      var bare = buildHuman(_pack, dna);
      var worn = buildHuman(_pack, dna, wearing: [_hair()]);
      GltfPrimitive body(Gltf g) => g.meshes.first.primitives.firstWhere((p) => p.targets.isNotEmpty);
      expect(body(worn).indices.length, lessThan(body(bare).indices.length),
          reason: "the wrist's faces, hidden by the piece");
      var piece = worn.meshes.first.primitives.firstWhere((p) => worn.materials[p.material!].cutOut);
      expect(worn.materials[piece.material!].image, 0, reason: "its picture, first of the images");
      var head = worn.nodes.indexWhere((n) => n.name == "head");
      expect(piece.joints![0], head);
      expect(piece.colors![0], closeTo(dna.hair.r, 1e-6));
      // And no hair grown from the scalp under it.
      expect(worn.meshes.first.primitives.length,
          bare.meshes.first.primitives.length,
          reason: "the grown cap gives way to the piece");
    });
  });

  group("clothes made from the body", () {
    ({List<ShellPiece> pieces, Set<int> hides}) shells(List<Garment> clothes) {
      var g = buildHuman(_pack, CharacterType.man.dna);
      var heads = <String, List<double>>{};
      for (var b in _bones) {
        heads[b.$1] = b.$3;
      }
      var best = List.generate(_pack.vertexCount, (_) => <(int, double)>[]);
      var order = [for (var n in g.nodes) n.name];
      for (var e in _pack.weights.entries) {
        for (var (v, w) in e.value) {
          best[v].add((order.indexOf(e.key), w));
        }
      }
      return garmentShells(
          dna: CharacterType.man.dna.copyWith(wardrobe: clothes, baseLayer: false),
          pos: Float32List.fromList(_pack.base),
          corners: _pack.groups["body"]!,
          best: best,
          bones: order,
          heads: heads);
    }

    double low(ShellPiece p) => [for (var k = 1; k < p.positions.length; k += 3) p.positions[k]]
        .reduce((a, b) => a < b ? a : b);
    double high(ShellPiece p) => [for (var k = 1; k < p.positions.length; k += 3) p.positions[k]]
        .reduce((a, b) => a > b ? a : b);

    test("a top ends at its hem, trousers at the waist, and hide the skin", () {
      const c = Color(0xFF336699);
      var s = shells(const [Garment(GarmentKind.tee, color: c), Garment(GarmentKind.trousers, color: c)]);
      expect(s.pieces, hasLength(2));
      expect(s.hides, isNotEmpty);
      // Worn in order: the trousers under, the top over.
      var trousers = s.pieces[0], top = s.pieces[1];
      expect(low(top), greaterThan(8.0), reason: "the hips are at 9");
      expect(high(trousers), lessThan(11.0), reason: "the waist, half a unit over the hips");
      expect(low(trousers), lessThan(2.0), reason: "to the ankles");
      expect(top.open, isFalse);
      expect(top.colour, c);
      // Under the top, the trousers stop just inside its hem: drawn there
      // too, so near it, they would show through in specks.
      expect(high(trousers), lessThan(low(top) + 0.3));
    });

    test("a skirt is a cone, open, and longer for a long one", () {
      const c = Color(0xFF993366);
      var short = shells(const [Garment(GarmentKind.skirt, color: c)]).pieces.single;
      var long = shells(const [Garment(GarmentKind.longSkirt, color: c)]).pieces.single;
      expect(short.open, isTrue);
      expect(low(long), lessThan(low(short)));
      expect(shells(const []).pieces, isEmpty);
      // Only what is drawn by hand: no shell made for it.
      expect(shells(const [Garment(GarmentKind.skirt, color: c, drawnOnly: true)]).pieces,
          isEmpty);
    });

    test("a top under a coat stops inside it, rather than showing through", () {
      const c = Color(0xFF000000);
      var alone = shells(const [Garment(GarmentKind.tee, color: c)]).pieces;
      var under = shells(const [
        Garment(GarmentKind.tee, color: c),
        Garment(GarmentKind.coat, color: c),
      ]).pieces;
      expect(low(under.first), greaterThan(low(alone.first)));
      expect(under.where((p) => p.open), hasLength(1), reason: "the coat's skirt");
      var layered = shells(const [
        Garment(GarmentKind.sweater, color: c),
        Garment(GarmentKind.coat, color: c),
      ]).pieces;
      expect(layered.where((p) => p.open), hasLength(1),
          reason: "the sweater's own short skirt is inside the coat's, unseen");
    });
  });

  group("fetching only what is needed", () {
    test("a file is read out of a zip on a server, a range at a time", () async {
      var saved = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = saved);
      var zip = _zip({"a/stored.txt": utf8.encode("plain"), "a/packed.obj": utf8.encode("v 1 2 3\n" * 50)});
      var ranges = <String>[];
      var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        var range = r.headers.value(HttpHeaders.rangeHeader);
        if (r.method == "HEAD" || range == null) {
          r.response.contentLength = zip.length;
          if (r.method != "HEAD") r.response.add(zip);
        } else {
          ranges.add(range);
          var m = RegExp(r"bytes=(\d+)-(\d+)").firstMatch(range)!;
          var a = int.parse(m[1]!), b = int.parse(m[2]!);
          r.response.statusCode = 206;
          r.response.add(zip.sublist(a, b + 1));
        }
        await r.response.close();
      });
      var z = await RemoteZip.open("http://127.0.0.1:${server.port}/pack.zip");
      expect(z.entries.keys, ["a/stored.txt", "a/packed.obj"]);
      expect(utf8.decode(await z.read("a/stored.txt")), "plain");
      expect(utf8.decode(await z.read("a/packed.obj")), "v 1 2 3\n" * 50);
      expect(ranges, isNotEmpty, reason: "never the whole zip");
      await expectLater(z.read("missing"), throwsA(anything));
    });

    test("hair and shoes are refused through a proxy too", () async {
      proxiedForTest = true;
      addTearDown(() => proxiedForTest = null);
      await expectLater(HumanWearAssets.install(),
          throwsA(predicate((e) => "$e".contains("proxy"))));
    });

    test("the catalogue names each piece once, from a known collection", () {
      var ids = [for (var w in wearCatalogue) w.id];
      expect(ids.toSet().length, ids.length);
      for (var w in wearCatalogue) {
        expect(wearZips.containsKey(w.zip), isTrue, reason: w.id);
        expect(w.cutOut, w.kind == WearKind.hair || w.kind == WearKind.eyebrows, reason: w.id);
      }
    });
  });

  group("a style's face on the sculpted head", () {
    test("marks the mouth, and leaves speaking and blinking to the drawing", () {
      var dna = CharacterType.woman.dna;
      var drawn = buildHuman(_pack, dna, drawnFace: true);
      var real = buildHuman(_pack, dna);
      var mouth = drawn.nodes.indexWhere((n) => n.name == mouthLandmark);
      expect(mouth, greaterThanOrEqualTo(0));
      expect(drawn.nodes[mouth].parent, drawn.nodes.indexWhere((n) => n.name == "head"));
      // At the lip: the head's joint here, which opening the mouth moves.
      var at = drawn.world()[mouth].translation;
      expect(at[1], closeTo(15.5, 0.6));
      var aa = drawn.meshes.first.targetNames.indexOf("aa");
      expect(drawn.meshes.first.primitives.first.targets[aa].every((d) => d == 0), isTrue);
      expect(real.meshes.first.primitives.first.targets[aa].any((d) => d != 0), isTrue);
      var happy = drawn.meshes.first.targetNames.indexOf("happy");
      expect(happy, greaterThanOrEqualTo(0), reason: "the cheeks still move");
    });

    test("is found on the posed head: eyes, skull and mouth on the page", () {
      var model = LoadedModel.of(buildHuman(_pack, CharacterType.man.dna, drawnFace: true), const []);
      var rig = CharacterRig.of(CharacterType.man.dna, CharacterElement.restPose,
          const Rect.fromLTWH(0, 0, 200, 400));
      var f = model.faceFrame(rig, CharacterFace.rest, const Rect.fromLTWH(0, 0, 200, 400))!;
      expect(f.mouth, isNotNull);
      expect(f.top[1], lessThan(f.base[1]), reason: "up the page");
      expect(f.mouth![1], greaterThan(f.eyeL[1]), reason: "below the eyes");
      expect((f.eyeL[0] - f.eyeR[0]).abs(), greaterThan(1));
      var turned = CharacterRig.of(CharacterType.man.dna,
          CharacterElement.restPose.withTurn(60), const Rect.fromLTWH(0, 0, 200, 400));
      var g = model.faceFrame(turned, CharacterFace.rest, const Rect.fromLTWH(0, 0, 200, 400))!;
      expect((g.eyeL[0] - g.eyeR[0]).abs(), lessThan((f.eyeL[0] - f.eyeR[0]).abs()),
          reason: "the eyes closer together on the page, turned");
    });

    test("is drawn in every style but the painterly", () async {
      HumanBody.instance.useForTest(_pack);
      Future<List<int>> draw(CharacterStyle style, {double turn = 0}) async {
        var rec = PictureRecorder();
        paintCharacterFigure(Canvas(rec), const Rect.fromLTWH(20, 20, 160, 360),
            CharacterType.woman.dna, CharacterElement.restPose.withTurn(turn),
            style: style, body: const CharacterBody(kind: BodyKind.mannequin));
        var img = await rec.endRecording().toImage(200, 400);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      var real = await draw(CharacterStyle.painterly);
      for (var style in [CharacterStyle.anime, CharacterStyle.featureCartoon]) {
        var drawn = await draw(style);
        var changed = 0;
        // The head: the top fifth of the figure.
        for (var i = 0; i < 200 * 90 * 4; i++) {
          if (drawn[i] != real[i]) changed++;
        }
        expect(changed, greaterThan(200), reason: "\$style's eyes and mouth");
      }
    });
  });

  group("changing a sculpted character", () {
    test("shows the body it was while the new one is made, out of the way", () async {
      HumanBody.instance.useForTest(_pack, inBackground: true);
      addTearDown(() => HumanBody.instance.useForTest(_pack));
      var dna = CharacterType.man.dna;
      var first = HumanBody.instance.modelFor(dna);
      expect(first, isNotNull, reason: "nothing to stand in: made at once");
      var wider = dna.copyWith(look: dna.look.withValue(Look.noseWidth, 1));
      expect(HumanBody.instance.modelFor(wider), same(first), reason: "the stand-in");
      // Asked again and again as a slider is dragged: still the stand-in.
      var wider2 = dna.copyWith(look: dna.look.withValue(Look.noseWidth, 0.8));
      expect(HumanBody.instance.modelFor(wider2), same(first));
      for (var i = 0; i < 500 && HumanBody.instance.making; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(HumanBody.instance.making, isFalse);
      var made = HumanBody.instance.modelFor(wider2);
      expect(made, isNot(same(first)), reason: "the last asked for, made");
      var plainNose = made!.gltf.meshes.first.primitives.first.positions;
      var direct = buildHuman(_pack, wider2).meshes.first.primitives.first.positions;
      expect(plainNose, direct, reason: "the same as made where it was asked");
    });

    test("an export makes the body there and then", () {
      HumanBody.instance.useForTest(_pack, inBackground: true);
      addTearDown(() {
        HumanBody.instance.buildNow = false;
        HumanBody.instance.useForTest(_pack);
      });
      var dna = CharacterType.woman.dna;
      var first = HumanBody.instance.modelFor(dna);
      HumanBody.instance.buildNow = true;
      var changed = dna.copyWith(look: dna.look.withValue(Look.jaw, 1));
      expect(HumanBody.instance.modelFor(changed), isNot(same(first)));
    });
  });

  group("a style's proportions", () {
    double headShare(Gltf g) {
      var head = g.nodes.indexWhere((n) => n.name == "head");
      var body = g.meshes.first.primitives.first;
      var lo = double.infinity, hi = -double.infinity;
      var headLo = double.infinity, headHi = -double.infinity;
      for (var i = 0; i < body.positions.length ~/ 3; i++) {
        var y = body.positions[i * 3 + 1];
        lo = y < lo ? y : lo;
        hi = y > hi ? y : hi;
        if (body.joints![i * 4] == head && body.weights![i * 4] > 0.5) {
          headLo = y < headLo ? y : headLo;
          headHi = y > headHi ? y : headHi;
        }
      }
      return (headHi - headLo) / (hi - lo);
    }

    test("a chibi's head is a bigger share of it, a webtoon's smaller", () {
      var dna = CharacterType.woman.dna;
      var usual = headShare(buildHuman(_pack, dna));
      var chibi = headShare(buildHuman(_pack, CharacterStyle.chibi.dnaOf(dna)));
      var webtoon = headShare(buildHuman(_pack, CharacterStyle.webtoon.dnaOf(dna)));
      expect(chibi, greaterThan(usual * 1.5));
      expect(webtoon, lessThan(usual));
      expect(headShare(buildHuman(_pack, CharacterStyle.featureCartoon.dnaOf(dna))),
          closeTo(usual, usual * 0.02), reason: "as many heads as the type");
    });
  });

  group("a style's limbs", () {
    double armWidth(Gltf g) {
      var lower = g.nodes.indexWhere((n) => n.name == "lowerarm01.L");
      var body = g.meshes.first.primitives.first;
      var lo = double.infinity, hi = -double.infinity;
      for (var i = 0; i < body.positions.length ~/ 3; i++) {
        if (body.joints![i * 4] != lower || body.weights![i * 4] < 0.9) continue;
        var y = body.positions[i * 3 + 1];
        lo = y < lo ? y : lo;
        hi = y > hi ? y : hi;
      }
      return hi - lo;
    }

    test("are drawn thinner, and gloved, as rubber hose draws them", () {
      var dna = CharacterType.man.dna;
      var usual = buildHuman(_pack, dna);
      var hose = buildHuman(_pack, dna, limbs: 0.5, gloves: true);
      expect(armWidth(hose), lessThan(armWidth(usual) * 0.8));
      var wrist = hose.nodes.indexWhere((n) => n.name == "wrist.L");
      var body = hose.meshes.first.primitives.first;
      var white = false;
      for (var i = 0; i < body.positions.length ~/ 3; i++) {
        if (body.joints![i * 4] == wrist && body.colors![i * 4] > 0.95) white = true;
      }
      expect(white, isTrue, reason: "white gloves");
    });
  });
}
