import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vrm_convert.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/vroid_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// A VRM 0.x character turned into VRM 1.0: the half turn built into it, and
// its materials, face, bones and springs as three-vrm reads VRM 0; and the
// VRoid characters fetched once, converted, and kept.

/// _glb is a .glb of [json] over [bin].
Uint8List _glb(Map<String, dynamic> json, Uint8List bin) {
  final js = utf8.encode(jsonEncode(json));
  final jl = (js.length + 3) & ~3, bl = (bin.length + 3) & ~3;
  final b = BytesBuilder()
    ..add((ByteData(12)
          ..setUint32(0, 0x46546C67, Endian.little)
          ..setUint32(4, 2, Endian.little)
          ..setUint32(8, 12 + 8 + jl + 8 + bl, Endian.little))
        .buffer
        .asUint8List())
    ..add((ByteData(8)
          ..setUint32(0, jl, Endian.little)
          ..setUint32(4, 0x4E4F534A, Endian.little))
        .buffer
        .asUint8List())
    ..add(js)
    ..add(List.filled(jl - js.length, 0x20))
    ..add((ByteData(8)
          ..setUint32(0, bl, Endian.little)
          ..setUint32(4, 0x004E4942, Endian.little))
        .buffer
        .asUint8List())
    ..add(bin)
    ..add(List.filled(bl - bin.length, 0));
  return b.takeBytes();
}

/// _read is a .glb's json and its floats, from the start of its buffer.
(Map<String, dynamic>, Float32List) _read(Uint8List glb) {
  final d = ByteData.sublistView(glb);
  final jl = d.getUint32(12, Endian.little);
  final json =
      jsonDecode(utf8.decode(glb.sublist(20, 20 + jl))) as Map<String, dynamic>;
  final bl = d.getUint32(20 + jl, Endian.little);
  final bin = Uint8List.fromList(glb.sublist(28 + jl, 28 + jl + bl));
  return (json, bin.buffer.asFloat32List(0, bin.length ~/ 4));
}

/// _vrm0 is a small VRM 0.x character: a skinned triangle with a face shape,
/// a hip and a hair bone, one toon material, a smile, a spring and a
/// collider, and a picture on its body and one on its hair.
Uint8List _vrm0({String licence = 'CC0'}) {
  final floats = <double>[
    // 0: positions
    1, 2, 3, 4, 5, 6, -1, 0, 2,
    // 9: normals
    1, 0, 0, 0, 1, 0, 0, 0, 1,
    // 18: a face shape's moves
    0.5, 0, -0.5, 0, 0, 0, 0, 0, 0,
    // 27: two inverse bind matrices, column-major, moved by (0.5, 1, 0.25)
    1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0.5, 1, 0.25, 1,
    1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0.5, 1, 0.25, 1,
  ];
  final bin = BytesBuilder()
    ..add(Float32List.fromList(floats).buffer.asUint8List());
  final geo = bin.length;
  // Two pictures, of any bytes: what matters is which are kept.
  bin.add(List.filled(100, 7));
  bin.add(List.filled(200, 9));
  final json = <String, dynamic>{
    'asset': {'version': '2.0'},
    'extensionsUsed': ['VRM', 'KHR_materials_unlit'],
    'buffers': [
      {'byteLength': bin.length},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 36, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 72, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 108, 'byteLength': 128},
      {'buffer': 0, 'byteOffset': geo, 'byteLength': 100},
      {'buffer': 0, 'byteOffset': geo + 100, 'byteLength': 200},
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [-1, 0, 2],
        'max': [4, 5, 6]
      },
      {'bufferView': 1, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
      {'bufferView': 2, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
      {'bufferView': 3, 'componentType': 5126, 'count': 2, 'type': 'MAT4'},
    ],
    'images': [
      {'bufferView': 4, 'mimeType': 'image/png'},
      {'bufferView': 5, 'mimeType': 'image/png'},
    ],
    'textures': [
      {'source': 0},
      {'source': 1},
    ],
    'materials': [
      {
        'name': 'Body_SKIN',
        'pbrMetallicRoughness': {
          'baseColorTexture': {'index': 0},
        },
        'extensions': {'KHR_materials_unlit': {}},
      },
      {
        'name': 'Hair_HAIR',
        'pbrMetallicRoughness': {
          'baseColorTexture': {'index': 1},
        },
      },
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'NORMAL': 1},
            'targets': [
              {'POSITION': 2},
            ],
            'material': 1,
          },
        ],
      },
    ],
    'skins': [
      {
        'joints': [1, 2],
        'inverseBindMatrices': 3,
      },
    ],
    'nodes': [
      {
        'name': 'Root',
        'children': [1, 3],
      },
      {
        'name': 'Hips',
        'translation': [0.1, 1, 0.2],
        'rotation': [0.1, 0.2, 0.3, 0.927],
        'children': [2],
      },
      {
        'name': 'Hair1',
        'translation': [0, 0.2, 0],
      },
      {'name': 'Body', 'mesh': 0, 'skin': 0},
    ],
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'extensions': {
      'VRM': {
        'meta': {
          'title': 'Tester',
          'author': '',
          'licenseName': licence,
          'allowedUserName': 'Everyone',
          'commercialUssageName': 'Allow',
          'texture': 1
        },
        'humanoid': {
          'humanBones': [
            {'bone': 'hips', 'node': 1},
            {'bone': 'leftThumbProximal', 'node': 2},
          ],
        },
        'firstPerson': {
          'firstPersonBoneOffset': {'x': 0.1, 'y': 0.06, 'z': 0.2},
          'lookAtTypeName': 'Bone',
          'lookAtHorizontalInner': {'xRange': 90, 'yRange': 8},
          'meshAnnotations': [
            {'mesh': 0, 'firstPersonFlag': 'ThirdPersonOnly'},
          ],
        },
        'blendShapeMaster': {
          'blendShapeGroups': [
            {
              'name': 'Joy',
              'presetName': 'joy',
              'binds': [
                {'mesh': 0, 'index': 0, 'weight': 50},
              ],
            },
            {'name': 'Surprised', 'presetName': 'unknown', 'binds': []},
            {'name': 'Extra', 'presetName': 'unknown', 'binds': []},
          ],
        },
        'materialProperties': [
          {
            'name': 'Hair_HAIR',
            'shader': 'VRM/MToon',
            'floatProperties': {
              '_ShadeShift': -0.2,
              '_ShadeToony': 0.8,
              '_OutlineWidth': 0.5,
              '_OutlineWidthMode': 1,
              '_CullMode': 0
            },
            'vectorProperties': {
              '_Color': [0.5, 0.5, 0.5, 0.25],
              '_ShadeColor': [0.5, 0.25, 1, 1],
            },
            'textureProperties': {'_MainTex': 1},
            'keywordMap': {'_ALPHATEST_ON': true},
          },
        ],
        'secondaryAnimation': {
          'boneGroups': [
            {
              'comment': 'Hair',
              'stiffiness': 0.5,
              'gravityPower': 0.1,
              'gravityDir': {'x': 0.2, 'y': -1, 'z': 0.3},
              'dragForce': 0.4,
              'center': -1,
              'hitRadius': 0.02,
              'bones': [1],
              'colliderGroups': [0],
            },
          ],
          'colliderGroups': [
            {
              'node': 1,
              'colliders': [
                {
                  'offset': {'x': 0.1, 'y': 0, 'z': 0.05},
                  'radius': 0.1,
                },
              ],
            },
          ],
        },
      },
    },
  };
  return _glb(json, bin.takeBytes());
}

/// _FakeStock hands back [file] for every download, and counts them.
class _FakeStock extends StockClient {
  final Uint8List file;
  final urls = <String>[];
  _FakeStock(this.file);

  @override
  Future<bool> download(String url, File to,
      {required int maxBytes,
      required bool allowFetching,
      required bool proxied}) async {
    if (!allowFetching || proxied) return false;
    urls.add(url);
    await to.writeAsBytes(file);
    return true;
  }
}

void main() {
  test('only a VRM 0.x character is converted', () {
    expect(isVrm0(_vrm0()), isTrue);
    expect(isVrm0(convertVrm0(_vrm0())), isFalse);
    expect(() => convertVrm0(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<VrmConvertError>()));
  });

  group('the half turn', () {
    final (j, f) = _read(convertVrm0(_vrm0()));

    test('points, normals and face shapes turn: x and z change sign', () {
      expect(f.sublist(0, 9), [-1, 2, -3, -4, 5, -6, 1, 0, -2]);
      expect(f.sublist(9, 18), [-1, 0, 0, 0, 1, 0, 0, 0, -1]);
      expect(f.sublist(18, 21), [-0.5, 0, 0.5]);
      final pos = (j['accessors'] as List)[0] as Map;
      expect(pos['min'], [-4, 0, -6]);
      expect(pos['max'], [1, 5, -2]);
    });

    test('bones turn, and the skin with them', () {
      final hips = (j['nodes'] as List)[1] as Map;
      expect(hips['translation'], [-0.1, 1, -0.2]);
      expect(hips['rotation'], [-0.1, 0.2, -0.3, 0.927]);
      // The bind matrix's move turns like a point.
      expect(f.sublist(27 + 12, 27 + 15), [-0.5, 1, -0.25]);
      expect(f.sublist(27, 27 + 11), [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    });
  });

  group('VRM 1.0', () {
    final (j, _) = _read(convertVrm0(_vrm0()));
    final vrm = (j['extensions'] as Map)['VRMC_vrm'] as Map;

    test('the extensions are VRM 1.0 ones', () {
      expect(j['extensionsUsed'],
          containsAll(['VRMC_vrm', 'VRMC_springBone', 'VRMC_materials_mtoon']));
      expect(j['extensionsUsed'], isNot(contains('VRM')));
      expect(j['extensionsUsed'], isNot(contains('KHR_materials_unlit')));
      expect((j['extensions'] as Map).containsKey('VRM'), isFalse);
      expect(vrm['specVersion'], '1.0');
    });

    test('CC0 is kept as VRM 1.0 permissions', () {
      final meta = vrm['meta'] as Map;
      expect(meta['name'], 'Tester');
      expect(meta['otherLicenseUrl'], contains('publicdomain/zero'));
      expect(meta['avatarPermission'], 'everyone');
      expect(meta['commercialUsage'], 'corporation');
      expect(meta['creditNotation'], 'unnecessary');
      expect(meta['authors'], isNotEmpty);
      expect(meta['thumbnailImage'], 1);
    });

    test('the thumb bones take their VRM 1.0 names', () {
      final bones = (vrm['humanoid'] as Map)['humanBones'] as Map;
      expect(bones['hips'], {'node': 1});
      expect(bones['leftThumbMetacarpal'], {'node': 2});
      expect(bones.containsKey('leftThumbProximal'), isFalse);
    });

    test('expressions bind to nodes, weighed nought to one', () {
      final ex = vrm['expressions'] as Map;
      final happy = (ex['preset'] as Map)['happy'] as Map;
      expect(happy['morphTargetBinds'], [
        {'node': 3, 'index': 0, 'weight': 0.5},
      ]);
      expect((ex['preset'] as Map).containsKey('surprised'), isTrue);
      expect((ex['custom'] as Map).keys, ['Extra']);
    });

    test('where it looks, from the head, turned', () {
      final look = vrm['lookAt'] as Map;
      expect(look['type'], 'bone');
      expect(look['offsetFromHeadBone'], [-0.1, 0.06, -0.2]);
      expect(look['rangeMapHorizontalInner'],
          {'inputMaxValue': 90, 'outputScale': 8});
      expect((vrm['firstPerson'] as Map)['meshAnnotations'], [
        {'node': 3, 'type': 'thirdPersonOnly'},
      ]);
    });

    test('MToon shading as three-vrm reads VRM 0', () {
      final hair = (j['materials'] as List)[1] as Map;
      final mt = (hair['extensions'] as Map)['VRMC_materials_mtoon'] as Map;
      // toony = lerp(0.8, 1, 0.5 + 0.5 * -0.2) = 0.88; shift = 0.2 - (1 - 0.88).
      expect(mt['shadingToonyFactor'], closeTo(0.88, 1e-9));
      expect(mt['shadingShiftFactor'], closeTo(0.08, 1e-9));
      expect(mt['outlineWidthMode'], 'worldCoordinates');
      expect(mt['outlineWidthFactor'], closeTo(0.005, 1e-12));
      // Colours from gamma to linear; alpha as it is.
      final base =
          (hair['pbrMetallicRoughness'] as Map)['baseColorFactor'] as List;
      expect(base[0], closeTo(math.pow(0.5, 2.2), 1e-12));
      expect(base[3], 0.25);
      expect((mt['shadeColorFactor'] as List)[1],
          closeTo(math.pow(0.25, 2.2), 1e-12));
      expect(hair['alphaMode'], 'MASK');
      expect(hair['doubleSided'], isTrue);
      expect((hair['pbrMetallicRoughness'] as Map)['baseColorTexture'],
          {'index': 1});
    });

    test('a spring is its chain, a tail 7 cm on, and its colliders turned', () {
      final sb = (j['extensions'] as Map)['VRMC_springBone'] as Map;
      final spring = (sb['springs'] as List).single as Map;
      final joints = (spring['joints'] as List).cast<Map>();
      expect([for (final x in joints) x['node']], [1, 2, 4]);
      expect(joints.first['stiffness'], 0.5);
      expect(joints.first['gravityDir'], [-0.2, -1, -0.3]);
      expect(spring['colliderGroups'], [0]);
      final tail = (j['nodes'] as List)[4] as Map;
      expect(tail['name'], 'Hair1_tail');
      final t = (tail['translation'] as List).cast<num>();
      expect(math.sqrt(t[0] * t[0] + t[1] * t[1] + t[2] * t[2]),
          closeTo(0.07, 1e-9));
      expect(((j['nodes'] as List)[2] as Map)['children'], [4]);
      final collider = (sb['colliders'] as List).single as Map;
      expect(collider['node'], 1);
      expect(((collider['shape'] as Map)['sphere'] as Map)['offset'],
          [-0.1, 0, -0.05]);
    });

    test('the app reads the result as VRM 1.0', () {
      final g = parseGltf(convertVrm0(_vrm0()));
      expect(g.meshes, isNotEmpty);
    });
  });

  test('kept for its hair, only the hair keeps its pictures', () {
    final (j, _) = _read(convertVrm0(_vrm0(), hairOnly: true));
    final views = (j['bufferViews'] as List).cast<Map>();
    final images = (j['images'] as List).cast<Map>();
    expect(views[images[0]['bufferView'] as int]['byteLength'], lessThan(100),
        reason: 'the body picture is a pixel');
    expect(views[images[1]['bufferView'] as int]['byteLength'], 200,
        reason: 'the hair picture is kept');
    expect((j['buffers'] as List)[0]['byteLength'], greaterThan(236));
  });

  group('the VRoid characters', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('canvas_vroid');
      CanvasStorage.rootOverride = root.path;
      CanvasLibrary.resetForTest();
    });
    tearDown(() {
      CanvasStorage.rootOverride = null;
      StockClient.instance = StockClient();
      proxiedForTest = null;
      root.deleteSync(recursive: true);
    });

    test('are fetched once, converted, and kept', () async {
      final fake = _FakeStock(_vrm0());
      StockClient.instance = fake;
      proxiedForTest = false;
      final shares = <double>[];
      await VroidAssets.install(vroidBodies, progress: shares.add);
      expect(fake.urls, hasLength(4));
      expect(
          fake.urls.first,
          contains(
              '/e16eb187100149a315ad92c3c9968f1d5baa6c7d/vroid/beta/Vivi.vrm'));
      expect(shares.last, 1.0);
      for (final m in vroidBodies) {
        expect(await VroidAssets.installed(m.id), isTrue);
        final kept = File(await VroidAssets.modelPath(m.id)).readAsBytesSync();
        expect(isVrm0(kept), isFalse, reason: 'kept as VRM 1.0');
      }
      await VroidAssets.install(vroidBodies);
      expect(fake.urls, hasLength(4), reason: 'not fetched again');
    });

    test('are fetched again when converted another way', () async {
      final fake = _FakeStock(_vrm0());
      StockClient.instance = fake;
      proxiedForTest = false;
      await VroidAssets.install([vroidBodies.first]);
      File('${await VroidAssets.dir()}/Vivi.version').writeAsStringSync('0');
      expect(await VroidAssets.installed('Vivi'), isFalse);
      await VroidAssets.install([vroidBodies.first]);
      expect(fake.urls, hasLength(2));
    });

    test('are refused through a proxy, which the download cannot use',
        () async {
      StockClient.instance = _FakeStock(_vrm0());
      proxiedForTest = true;
      await expectLater(VroidAssets.install(vroidBodies),
          throwsA(predicate((e) => '$e'.contains('proxy'))));
    });

    test('are not kept unless they say they are CC0', () async {
      StockClient.instance = _FakeStock(_vrm0(licence: 'CC_BY'));
      proxiedForTest = false;
      await expectLater(VroidAssets.install([vroidBodies.first]),
          throwsA(predicate((e) => '$e'.contains('not CC0'))));
      expect(await VroidAssets.installed('Vivi'), isFalse);
    });
  });
}
