import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// vrm_convert.dart turns a VRM 0.x character (the glTF extension "VRM") into
// VRM 1.0 (VRMC_vrm, VRMC_springBone, VRMC_materials_mtoon), which is what
// the character renderer reads.
//
// VRM 0.x characters face -z and VRM 1.0 ones +z. The half turn about y is
// built into the file -- vertices, normals, tangents, morph targets, bones,
// skin matrices, collider offsets -- so the result is a plain VRM 1.0
// character, with no turned root.
//
// There is no official migration document. The material, expression,
// humanoid and spring-bone rules follow three-vrm's own VRM 0 compatibility
// code (MIT), which every VRM 0 viewer on the web agrees with.

/// VrmConvertError is a file that is not a VRM 0.x character this can turn
/// into VRM 1.0.
class VrmConvertError implements Exception {
  final String message;
  VrmConvertError(this.message);
  @override
  String toString() => message;
}

/// vrmConvertVersion is how the conversion is done: a character converted
/// by another is converted again.
const int vrmConvertVersion = 1;

/// isVrm0 is whether [glb] is a VRM 0.x character.
bool isVrm0(Uint8List glb) {
  try {
    return (_Glb.read(glb).json['extensions'] as Map?)?.containsKey('VRM') ??
        false;
  } catch (_) {
    return false;
  }
}

/// convertVrm0 returns [glb], a VRM 0.x character, as VRM 1.0. With
/// [hairOnly] every picture not drawn on its hair is replaced by a single
/// pixel: for a character kept only to borrow its hair from.
Uint8List convertVrm0(Uint8List glb, {bool hairOnly = false}) {
  final f = _Glb.read(glb);
  final j = f.json;
  final v0 = (j['extensions'] as Map?)?['VRM'] as Map<String, dynamic>?;
  if (v0 == null) throw VrmConvertError('This is not a VRM 0.x character.');
  _turnModel(j, f.bin);

  final nodes = (j['nodes'] as List).cast<Map<String, dynamic>>();
  final nodesOfMesh = <int, List<int>>{};
  for (var i = 0; i < nodes.length; i++) {
    final m = nodes[i]['mesh'];
    if (m is int) nodesOfMesh.putIfAbsent(m, () => []).add(i);
  }
  final used = <String>{};

  // Materials, matched to their VRM 0 properties by name.
  final props = {
    for (final mp in (v0['materialProperties'] as List? ?? const [])
        .cast<Map<String, dynamic>>())
      mp['name']: mp,
  };
  final materials =
      (j['materials'] as List? ?? const []).cast<Map<String, dynamic>>();
  j['materials'] = [
    for (final m in materials)
      props.containsKey(m['name']) ? _material(m, props[m['name']]!, used) : m,
  ];
  final matIndex = <String, int>{
    for (var i = 0; i < (j['materials'] as List).length; i++)
      ((j['materials'] as List)[i]['name'] ?? '') as String: i,
  };

  j['extensions']['VRMC_vrm'] = {
    'specVersion': '1.0',
    'meta': _meta(v0['meta'] as Map<String, dynamic>? ?? const {}, j),
    'humanoid': {'humanBones': _humanoid(v0)},
    'firstPerson': _firstPerson(v0, nodesOfMesh),
    'lookAt': _lookAt(v0),
    'expressions': _expressions(v0, nodesOfMesh, matIndex),
  };
  j['extensions']['VRMC_springBone'] = _springs(v0, j);

  (j['extensions'] as Map).remove('VRM');
  for (final m in (j['materials'] as List).cast<Map<String, dynamic>>()) {
    (m['extensions'] as Map?)?.remove('KHR_materials_unlit');
  }
  final keep = [
    for (final e in (j['extensionsUsed'] as List? ?? const []).cast<String>())
      if (e != 'VRM' && e != 'KHR_materials_unlit') e,
  ];
  j['extensionsUsed'] = [
    ...keep,
    ...({'VRMC_vrm', 'VRMC_springBone', ...used}
        .difference(keep.toSet())
        .toList()
      ..sort())
  ];
  if (hairOnly) _blankAllButHair(j, f);
  return f.write();
}

// ---------------------------------------------------------------------------
// The file.

class _Glb {
  final Map<String, dynamic> json;
  Uint8List bin;
  _Glb(this.json, this.bin);

  static _Glb read(Uint8List b) {
    if (b.length < 20 ||
        ascii.decode(b.sublist(0, 4), allowInvalid: true) != 'glTF') {
      throw VrmConvertError('This is not a .vrm file.');
    }
    final d = ByteData.sublistView(b);
    final jl = d.getUint32(12, Endian.little);
    final json =
        jsonDecode(utf8.decode(b.sublist(20, 20 + jl))) as Map<String, dynamic>;
    final off = 20 + jl;
    if (off + 8 > b.length) return _Glb(json, Uint8List(0));
    final bl = d.getUint32(off, Endian.little);
    return _Glb(json, Uint8List.fromList(b.sublist(off + 8, off + 8 + bl)));
  }

  Uint8List write() {
    var js = utf8.encode(jsonEncode(json));
    final jsPad = (4 - js.length % 4) % 4;
    final binPad = (4 - bin.length % 4) % 4;
    final jl = js.length + jsPad, bl = bin.length + binPad;
    final out = BytesBuilder(copy: false);
    final head = ByteData(12)
      ..setUint32(0, 0x46546C67, Endian.little)
      ..setUint32(4, 2, Endian.little)
      ..setUint32(8, 12 + 8 + jl + 8 + bl, Endian.little);
    out.add(head.buffer.asUint8List());
    out.add((ByteData(8)
          ..setUint32(0, jl, Endian.little)
          ..setUint32(4, 0x4E4F534A, Endian.little))
        .buffer
        .asUint8List());
    out.add(js);
    out.add(List.filled(jsPad, 0x20));
    out.add((ByteData(8)
          ..setUint32(0, bl, Endian.little)
          ..setUint32(4, 0x004E4942, Endian.little))
        .buffer
        .asUint8List());
    out.add(bin);
    out.add(List.filled(binPad, 0));
    return out.takeBytes();
  }
}

// ---------------------------------------------------------------------------
// The half turn: x and z change sign.

/// _floats is the float accessor [ai]'s values, read and written in place.
class _Floats {
  final ByteData data;
  final int start, stride, count, width;
  _Floats(this.data, this.start, this.stride, this.count, this.width);

  double get(int item, int c) =>
      data.getFloat32(start + item * stride + c * 4, Endian.little);
  void set(int item, int c, double v) =>
      data.setFloat32(start + item * stride + c * 4, v, Endian.little);
}

_Floats _accessor(Map<String, dynamic> j, Uint8List bin, int ai) {
  final a = (j['accessors'] as List)[ai] as Map<String, dynamic>;
  if (a['componentType'] != 5126) {
    throw VrmConvertError('Accessor $ai is not made of floats.');
  }
  if (a.containsKey('sparse')) {
    throw VrmConvertError('Accessor $ai is sparse, which is not handled.');
  }
  final width = const {
    'SCALAR': 1,
    'VEC2': 2,
    'VEC3': 3,
    'VEC4': 4,
    'MAT4': 16
  }[a['type']]!;
  final bv = (j['bufferViews'] as List)[a['bufferView'] as int]
      as Map<String, dynamic>;
  final start =
      ((bv['byteOffset'] ?? 0) as int) + ((a['byteOffset'] ?? 0) as int);
  final stride = (bv['byteStride'] ?? 4 * width) as int;
  return _Floats(
      ByteData.sublistView(bin), start, stride, a['count'] as int, width);
}

void _turnVectors(Map<String, dynamic> j, Uint8List bin, int ai) {
  final f = _accessor(j, bin, ai);
  for (var i = 0; i < f.count; i++) {
    f.set(i, 0, -f.get(i, 0));
    f.set(i, 2, -f.get(i, 2));
  }
  final a = (j['accessors'] as List)[ai] as Map<String, dynamic>;
  final lo = (a['min'] as List?)?.cast<num>(),
      hi = (a['max'] as List?)?.cast<num>();
  if (lo != null && hi != null && lo.length >= 3) {
    a['min'] = [-hi[0], lo[1], -hi[2], ...lo.skip(3)];
    a['max'] = [-lo[0], hi[1], -lo[2], ...hi.skip(3)];
  }
}

void _turnMatrices(Map<String, dynamic> j, Uint8List bin, int ai) {
  // M' = T M T with T = diag(-1, 1, -1, 1): an entry changes sign when
  // exactly one of its row and column is x or z. glTF is column-major.
  const s = [-1, 1, -1, 1];
  final f = _accessor(j, bin, ai);
  for (var i = 0; i < f.count; i++) {
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 4; row++) {
        if (s[row] * s[col] < 0) {
          f.set(i, col * 4 + row, -f.get(i, col * 4 + row));
        }
      }
    }
  }
}

void _turnModel(Map<String, dynamic> j, Uint8List bin) {
  final vectors = <int>{}, matrices = <int>{};
  for (final m
      in (j['meshes'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    for (final p in (m['primitives'] as List).cast<Map<String, dynamic>>()) {
      (p['attributes'] as Map).forEach((kind, ai) {
        if (kind == 'POSITION' || kind == 'NORMAL' || kind == 'TANGENT') {
          vectors.add(ai as int);
        }
      });
      for (final t in (p['targets'] as List? ?? const []).cast<Map>()) {
        t.forEach((kind, ai) {
          if (kind == 'POSITION' || kind == 'NORMAL' || kind == 'TANGENT') {
            vectors.add(ai as int);
          }
        });
      }
    }
  }
  for (final s
      in (j['skins'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    if (s['inverseBindMatrices'] is int) {
      matrices.add(s['inverseBindMatrices'] as int);
    }
  }
  for (final ai in vectors) {
    _turnVectors(j, bin, ai);
  }
  for (final ai in matrices) {
    _turnMatrices(j, bin, ai);
  }
  for (final n in (j['nodes'] as List).cast<Map<String, dynamic>>()) {
    if (n.containsKey('matrix')) {
      throw VrmConvertError('Nodes placed by a matrix are not handled.');
    }
    final t = (n['translation'] as List?)?.cast<num>();
    if (t != null) n['translation'] = [-t[0], t[1], -t[2]];
    final q = (n['rotation'] as List?)?.cast<num>();
    if (q != null) n['rotation'] = [-q[0], q[1], -q[2], q[3]];
  }
}

List<double> _turned(Map? v) => [
      -((v?['x'] ?? 0) as num).toDouble(),
      ((v?['y'] ?? 0) as num).toDouble(),
      -((v?['z'] ?? 0) as num).toDouble()
    ];

// ---------------------------------------------------------------------------
// Materials: VRM/MToon and VRM/Unlit* to VRMC_materials_mtoon.

double _g(num v) => math.pow(v.toDouble(), 2.2).toDouble();

Map<String, dynamic>? _texTransform(Map<String, dynamic> mp) {
  final t =
      ((mp['vectorProperties'] as Map?)?['_MainTex'] as List?)?.cast<num>();
  if (t == null || t.length < 4) return null;
  final scale = [t[2].toDouble(), t[3].toDouble()];
  final offset = [t[0].toDouble(), 1.0 - t[3] - t[1]];
  if (offset[0] == 0 && offset[1] == 0 && scale[0] == 1 && scale[1] == 1) {
    return null;
  }
  return {'offset': offset, 'scale': scale};
}

Map<String, dynamic>? _texInfo(
    Object? index, Map<String, dynamic>? transform, Set<String> used) {
  if (index is! int) return null;
  final info = <String, dynamic>{'index': index};
  if (transform != null) {
    info['extensions'] = {'KHR_texture_transform': Map.of(transform)};
    used.add('KHR_texture_transform');
  }
  return info;
}

Map<String, dynamic> _material(
    Map<String, dynamic> mat, Map<String, dynamic> mp, Set<String> used) {
  final shader = (mp['shader'] ?? '') as String;
  final fp = (mp['floatProperties'] as Map?) ?? const {};
  final vp = (mp['vectorProperties'] as Map?) ?? const {};
  final tp = (mp['textureProperties'] as Map?) ?? const {};
  final kw = (mp['keywordMap'] as Map?) ?? const {};
  num f(String k, num d) => (fp[k] as num?) ?? d;
  List<num> v(String k, List<num> d) => ((vp[k] as List?)?.cast<num>()) ?? d;
  final tt = _texTransform(mp);
  const dropped = {
    'extensions',
    'pbrMetallicRoughness',
    'alphaMode',
    'alphaCutoff',
    'doubleSided',
    'emissiveFactor',
    'emissiveTexture',
    'normalTexture'
  };
  final out = <String, dynamic>{
    for (final e in mat.entries)
      if (!dropped.contains(e.key)) e.key: e.value,
  };
  Map<String, dynamic> mt;
  if (shader == 'VRM/MToon') {
    final transparent = kw['_ALPHABLEND_ON'] == true;
    final cutoff = kw['_ALPHATEST_ON'] == true;
    out['alphaMode'] = transparent
        ? 'BLEND'
        : cutoff
            ? 'MASK'
            : 'OPAQUE';
    if (cutoff) out['alphaCutoff'] = f('_Cutoff', 0.5);
    out['doubleSided'] = f('_CullMode', 2) == 0;
    final c = v('_Color', [1, 1, 1, 1]);
    final pbr = <String, dynamic>{
      'baseColorFactor': [
        _g(c[0]),
        _g(c[1]),
        _g(c[2]),
        c.length > 3 ? c[3].toDouble() : 1.0
      ],
      'metallicFactor': 0,
      'roughnessFactor': 1,
    };
    final bt = _texInfo(tp['_MainTex'], tt, used);
    if (bt != null) pbr['baseColorTexture'] = bt;
    out['pbrMetallicRoughness'] = pbr;
    final nt = _texInfo(tp['_BumpMap'], tt, used);
    if (nt != null) out['normalTexture'] = nt..['scale'] = f('_BumpScale', 1.0);
    final et = _texInfo(tp['_EmissionMap'], tt, used);
    if (et != null) out['emissiveTexture'] = et;
    out['emissiveFactor'] = [
      for (final x in v('_EmissionColor', [0, 0, 0, 1]).take(3)) _g(x)
    ];
    final shift0 = f('_ShadeShift', 0.0).toDouble();
    var toony = f('_ShadeToony', 0.9).toDouble();
    toony = toony + (1.0 - toony) * (0.5 + 0.5 * shift0);
    final shift = -shift0 - (1.0 - toony);
    final gi = f('_IndirectLightIntensity', 0.1).toDouble();
    mt = {
      'specVersion': '1.0',
      'transparentWithZWrite': f('_ZWrite', 0) == 1 && transparent,
      'renderQueueOffsetNumber': 0,
      'shadeColorFactor': [
        for (final x in v('_ShadeColor', [0.97, 0.81, 0.86, 1]).take(3)) _g(x)
      ],
      'shadingShiftFactor': shift,
      'shadingToonyFactor': toony,
      'giEqualizationFactor': gi != 0 ? 1.0 - gi : 0.9,
      'rimLightingMixFactor': f('_RimLightingMix', 0.0),
      'parametricRimColorFactor': [
        for (final x in v('_RimColor', [0, 0, 0, 1]).take(3)) _g(x)
      ],
      'parametricRimFresnelPowerFactor': f('_RimFresnelPower', 1.0),
      'parametricRimLiftFactor': f('_RimLift', 0.0),
      'outlineWidthMode': const [
        'none',
        'worldCoordinates',
        'screenCoordinates'
      ][f('_OutlineWidthMode', 0).toInt().clamp(0, 2)],
      'outlineWidthFactor': 0.01 * f('_OutlineWidth', 0.0),
      'outlineColorFactor': [
        for (final x in v('_OutlineColor', [0, 0, 0]).take(3)) _g(x)
      ],
      'outlineLightingMixFactor':
          f('_OutlineColorMode', 0) == 1 ? f('_OutlineLightingMix', 1.0) : 0.0,
      'uvAnimationScrollXSpeedFactor': f('_UvAnimScrollX', 0.0),
      'uvAnimationScrollYSpeedFactor': -f('_UvAnimScrollY', 0.0),
      'uvAnimationRotationSpeedFactor': f('_UvAnimRotation', 0.0),
    };
    for (final (key, prop) in const [
      ('shadeMultiplyTexture', '_ShadeTexture'),
      ('rimMultiplyTexture', '_RimTexture'),
      ('outlineWidthMultiplyTexture', '_OutlineWidthTexture'),
      ('uvAnimationMaskTexture', '_UvAnimMaskTexture'),
    ]) {
      final t = _texInfo(tp[prop], tt, used);
      if (t != null) mt[key] = t;
    }
    if (tp['_SphereAdd'] is int) {
      mt['matcapTexture'] = {'index': tp['_SphereAdd']};
      mt['matcapFactor'] = [1.0, 1.0, 1.0];
    }
  } else if (shader.startsWith('VRM/Unlit')) {
    final zw = shader == 'VRM/UnlitTransparentZWrite';
    final transparent = shader == 'VRM/UnlitTransparent' || zw;
    final cutoff = shader == 'VRM/UnlitCutout';
    out['alphaMode'] = transparent
        ? 'BLEND'
        : cutoff
            ? 'MASK'
            : 'OPAQUE';
    if (cutoff) out['alphaCutoff'] = f('_Cutoff', 0.5);
    final base = [
      for (final x in v('_Color', [1, 1, 1, 1])) _g(x)
    ];
    final pbr = <String, dynamic>{
      'baseColorFactor': base,
      'metallicFactor': 0,
      'roughnessFactor': 1
    };
    final bt = _texInfo(tp['_MainTex'], tt, used);
    if (bt != null) pbr['baseColorTexture'] = bt;
    out['pbrMetallicRoughness'] = pbr;
    mt = {
      'specVersion': '1.0',
      'transparentWithZWrite': zw,
      'renderQueueOffsetNumber': 0,
      'shadeColorFactor': base.take(3).toList()
    };
    if (bt != null) mt['shadeMultiplyTexture'] = Map.of(bt);
  } else {
    return mat; // glTF's own shading, or a shader this does not know: as it is
  }
  out['extensions'] = {'VRMC_materials_mtoon': mt};
  used.add('VRMC_materials_mtoon');
  return out;
}

// ---------------------------------------------------------------------------
// Who it is, its bones, where it looks, its face.

const _cc0 = 'https://creativecommons.org/publicdomain/zero/1.0/';

Map<String, dynamic> _meta(Map<String, dynamic> m0, Map<String, dynamic> j) {
  final cc0 = m0['licenseName'] == 'CC0';
  String s(String k) => (m0[k] ?? '') as String;
  final meta = <String, dynamic>{
    'name': s('title').isEmpty ? 'Untitled' : s('title'),
    'version': s('version'),
    'authors': [
      s('author').isEmpty ? 'VRoid Project, pixiv Inc.' : s('author')
    ],
    'contactInformation': s('contactInformation'),
    'references': [if (s('reference').isNotEmpty) s('reference')],
    'licenseUrl': 'https://vrm.dev/licenses/1.0/',
    'avatarPermission': const {
          'Everyone': 'everyone',
          'ExplicitlyLicensedPerson': 'onlySeparatelyLicensedPerson'
        }[m0['allowedUserName']] ??
        'onlyAuthor',
    'allowExcessivelyViolentUsage': m0['violentUssageName'] == 'Allow',
    'allowExcessivelySexualUsage': m0['sexualUssageName'] == 'Allow',
    'commercialUsage': m0['commercialUssageName'] == 'Allow'
        ? 'corporation'
        : 'personalNonProfit',
    'allowPoliticalOrReligiousUsage': cc0,
    'allowAntisocialOrHateUsage': false,
    'creditNotation': cc0 ? 'unnecessary' : 'required',
    'allowRedistribution': cc0,
    'modification': cc0 ? 'allowModificationRedistribution' : 'prohibited',
  };
  if (cc0) {
    meta['otherLicenseUrl'] = _cc0;
  } else if (s('otherLicenseUrl').isNotEmpty) {
    meta['otherLicenseUrl'] = s('otherLicenseUrl');
  }
  final tex = m0['texture'];
  final textures = j['textures'] as List? ?? const [];
  if (tex is int && tex >= 0 && tex < textures.length) {
    meta['thumbnailImage'] = (textures[tex] as Map)['source'];
  }
  return meta;
}

const _thumbs = {
  'leftThumbProximal': 'leftThumbMetacarpal',
  'leftThumbIntermediate': 'leftThumbProximal',
  'rightThumbProximal': 'rightThumbMetacarpal',
  'rightThumbIntermediate': 'rightThumbProximal',
};

Map<String, dynamic> _humanoid(Map<String, dynamic> v0) {
  final bones = <String, dynamic>{};
  for (final hb
      in ((v0['humanoid'] as Map?)?['humanBones'] as List? ?? const [])
          .cast<Map>()) {
    final name = _thumbs[hb['bone']] ?? hb['bone'] as String;
    final node = hb['node'];
    if (node is int && node >= 0 && !bones.containsKey(name)) {
      bones[name] = {'node': node};
    }
  }
  return bones;
}

Map<String, dynamic> _firstPerson(
    Map<String, dynamic> v0, Map<int, List<int>> nodesOfMesh) {
  const types = {
    'Auto': 'auto',
    'Both': 'both',
    'ThirdPersonOnly': 'thirdPersonOnly',
    'FirstPersonOnly': 'firstPersonOnly'
  };
  return {
    'meshAnnotations': [
      for (final a
          in ((v0['firstPerson'] as Map?)?['meshAnnotations'] as List? ??
                  const [])
              .cast<Map>())
        for (final node in nodesOfMesh[a['mesh']] ?? const <int>[])
          {'node': node, 'type': types[a['firstPersonFlag']] ?? 'auto'},
    ],
  };
}

Map<String, dynamic> _lookAt(Map<String, dynamic> v0) {
  final fp = (v0['firstPerson'] as Map?) ?? const {};
  Map<String, dynamic> range(String k) {
    final d = (fp[k] as Map?) ?? const {};
    return {
      'inputMaxValue': (d['xRange'] ?? 90) as num,
      'outputScale': (d['yRange'] ?? 10) as num
    };
  }

  return {
    'offsetFromHeadBone': _turned((fp['firstPersonBoneOffset'] as Map?) ??
        const {'x': 0, 'y': 0.06, 'z': 0}),
    'type': fp['lookAtTypeName'] == 'BlendShape' ? 'expression' : 'bone',
    'rangeMapHorizontalInner': range('lookAtHorizontalInner'),
    'rangeMapHorizontalOuter': range('lookAtHorizontalOuter'),
    'rangeMapVerticalDown': range('lookAtVerticalDown'),
    'rangeMapVerticalUp': range('lookAtVerticalUp'),
  };
}

const _presets = {
  'a': 'aa',
  'e': 'ee',
  'i': 'ih',
  'o': 'oh',
  'u': 'ou',
  'blink': 'blink',
  'joy': 'happy',
  'angry': 'angry',
  'sorrow': 'sad',
  'fun': 'relaxed',
  'lookup': 'lookUp',
  'lookdown': 'lookDown',
  'lookleft': 'lookLeft',
  'lookright': 'lookRight',
  'blink_l': 'blinkLeft',
  'blink_r': 'blinkRight',
  'neutral': 'neutral',
};

Map<String, dynamic> _expressions(Map<String, dynamic> v0,
    Map<int, List<int>> nodesOfMesh, Map<String, int> matIndex) {
  final preset = <String, dynamic>{}, custom = <String, dynamic>{};
  final groups =
      ((v0['blendShapeMaster'] as Map?)?['blendShapeGroups'] as List? ??
              const [])
          .cast<Map>();
  for (final g in groups) {
    final groupName = (g['name'] ?? '') as String;
    var name =
        _presets[((g['presetName'] ?? 'unknown') as String).toLowerCase()];
    // VRoid keeps Surprised as an unnamed preset; VRM 1.0 has one for it.
    if (name == null && groupName.toLowerCase() == 'surprised') {
      name = 'surprised';
    }
    final e = <String, dynamic>{
      'isBinary': g['isBinary'] == true,
      'overrideBlink': 'none',
      'overrideLookAt': 'none',
      'overrideMouth': 'none'
    };
    final binds = [
      for (final b in (g['binds'] as List? ?? const []).cast<Map>())
        for (final node in nodesOfMesh[b['mesh']] ?? const <int>[])
          {
            'node': node,
            'index': b['index'],
            'weight': 0.01 * ((b['weight'] ?? 100) as num)
          },
    ];
    if (binds.isNotEmpty) e['morphTargetBinds'] = binds;
    final colours = <Map<String, dynamic>>[],
        transforms = <Map<String, dynamic>>[];
    for (final mv in (g['materialValues'] as List? ?? const []).cast<Map>()) {
      final mn = (mv['materialName'] ?? '') as String;
      final mi = matIndex[mn] ?? matIndex[mn.replaceAll(' (Outline)', '')];
      final tv = ((mv['targetValue'] as List?) ?? const []).cast<num>();
      if (mi == null || tv.length < 4) continue;
      if (mv['propertyName'] == '_MainTex_ST') {
        transforms.add({
          'material': mi,
          'scale': [tv[0], tv[1]],
          'offset': [tv[2], 1.0 - tv[3] - tv[1]]
        });
      } else {
        final kind = const {
          '_Color': 'color',
          '_EmissionColor': 'emissionColor',
          '_ShadeColor': 'shadeColor',
          '_RimColor': 'rimColor',
          '_OutlineColor': 'outlineColor'
        }[mv['propertyName']];
        if (kind != null) {
          colours.add({'material': mi, 'type': kind, 'targetValue': tv});
        }
      }
    }
    if (colours.isNotEmpty) e['materialColorBinds'] = colours;
    if (transforms.isNotEmpty) e['textureTransformBinds'] = transforms;
    if (name != null) {
      preset.putIfAbsent(name, () => e);
    } else {
      custom[groupName.isEmpty ? 'expression${custom.length}' : groupName] = e;
    }
  }
  return {'preset': preset, 'custom': custom};
}

// ---------------------------------------------------------------------------
// Spring bones: each root's line of descendants is a chain, and each branch
// off it a chain of its own; a chain's last bone gets a tail 7 cm on, as
// VRM 0 imagined one.

List<double> _rotate(List<double> q, List<double> v) {
  final x = q[0], y = q[1], z = q[2], w = q[3];
  final tx = 2 * (y * v[2] - z * v[1]),
      ty = 2 * (z * v[0] - x * v[2]),
      tz = 2 * (x * v[1] - y * v[0]);
  return [
    v[0] + w * tx + (y * tz - z * ty),
    v[1] + w * ty + (z * tx - x * tz),
    v[2] + w * tz + (x * ty - y * tx)
  ];
}

List<double> _mul(List<double> a, List<double> b) => [
      a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
      a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
      a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
      a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    ];

Map<String, dynamic> _springs(Map<String, dynamic> v0, Map<String, dynamic> j) {
  final nodes = (j['nodes'] as List).cast<Map<String, dynamic>>();
  final sa = (v0['secondaryAnimation'] as Map?) ?? const {};
  final colliders = <Map<String, dynamic>>[], groups = <Map<String, dynamic>>[];
  for (final cg in (sa['colliderGroups'] as List? ?? const []).cast<Map>()) {
    final start = colliders.length;
    for (final c in (cg['colliders'] as List? ?? const []).cast<Map>()) {
      colliders.add({
        'node': cg['node'],
        'shape': {
          'sphere': {
            'offset': _turned(c['offset'] as Map?),
            'radius': (c['radius'] ?? 0) as num
          },
        },
      });
    }
    groups.add({
      'name': 'group${groups.length}',
      'colliders': [for (var i = start; i < colliders.length; i++) i]
    });
  }

  final parent = <int, int>{};
  for (var i = 0; i < nodes.length; i++) {
    for (final c in (nodes[i]['children'] as List? ?? const []).cast<int>()) {
      parent[c] = i;
    }
  }
  final worlds = <int, (List<double>, List<double>)>{};
  (List<double>, List<double>) world(int i) {
    final known = worlds[i];
    if (known != null) return known;
    final n = nodes[i];
    final t = [
      for (final x in (n['translation'] as List? ?? const [0, 0, 0]))
        (x as num).toDouble()
    ];
    var r = [
      for (final x in (n['rotation'] as List? ?? const [0, 0, 0, 1]))
        (x as num).toDouble()
    ];
    // A turn written to a few places is not quite of unit length.
    final rl = math.sqrt(r.fold<double>(0, (s, x) => s + x * x));
    if (rl > 0) r = [for (final x in r) x / rl];
    final p = parent[i];
    final w = p == null
        ? (t, r)
        : (() {
            final (pt, pr) = world(p);
            final moved = _rotate(pr, t);
            return (
              [pt[0] + moved[0], pt[1] + moved[1], pt[2] + moved[2]],
              _mul(pr, r)
            );
          })();
    return worlds[i] = w;
  }

  int? tailFor(int leaf) {
    final p = parent[leaf];
    if (p == null) return null;
    final (lt, lr) = world(leaf);
    final (pt, _) = world(p);
    var d = [lt[0] - pt[0], lt[1] - pt[1], lt[2] - pt[2]];
    final len = math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    final k = 0.07 / (len == 0 ? 1 : len);
    d = [d[0] * k, d[1] * k, d[2] * k];
    nodes.add({
      'name': '${nodes[leaf]['name'] ?? 'joint'}_tail',
      'translation': _rotate([-lr[0], -lr[1], -lr[2], lr[3]], d)
    });
    ((nodes[leaf]['children'] ??= <int>[]) as List).add(nodes.length - 1);
    return nodes.length - 1;
  }

  final usedJoints = <int>{}, springs = <Map<String, dynamic>>[];
  for (final bg in (sa['boneGroups'] as List? ?? const []).cast<Map>()) {
    Map<String, dynamic> joint(int node) => {
          'node': node,
          'hitRadius': (bg['hitRadius'] ?? 0.02) as num,
          'stiffness': (bg['stiffiness'] ?? 1.0) as num,
          'gravityPower': (bg['gravityPower'] ?? 0.0) as num,
          'gravityDir': _turned(
              (bg['gravityDir'] as Map?) ?? const {'x': 0, 'y': -1, 'z': 0}),
          'dragForce': (bg['dragForce'] ?? 0.4) as num,
        };
    final chains = <List<int>>[];
    void walk(int start) {
      final chain = [start];
      var node = start;
      while (true) {
        final kids = [
          for (final c
              in (nodes[node]['children'] as List? ?? const []).cast<int>())
            if (!usedJoints.contains(c)) c
        ];
        if (kids.isEmpty) break;
        for (final k in kids.skip(1)) {
          walk(k);
        }
        node = kids.first;
        chain.add(node);
      }
      chains.add(chain);
    }

    for (final root in (bg['bones'] as List? ?? const []).cast<int>()) {
      if (!usedJoints.contains(root)) walk(root);
    }
    for (var chain in chains) {
      chain = [
        for (final c in chain)
          if (!usedJoints.contains(c)) c
      ];
      if (chain.isEmpty) continue;
      final tail = tailFor(chain.last);
      usedJoints.addAll(chain);
      final spring = <String, dynamic>{
        'name': ((bg['comment'] ?? '') as String).isEmpty
            ? 'spring${springs.length}'
            : bg['comment'],
        'joints': [
          for (final c in chain) joint(c),
          if (tail != null) joint(tail)
        ],
      };
      final cgs = (bg['colliderGroups'] as List? ?? const []);
      if (cgs.isNotEmpty) spring['colliderGroups'] = List.of(cgs);
      final center = bg['center'];
      if (center is int && center >= 0) spring['center'] = center;
      springs.add(spring);
    }
  }
  return {
    'specVersion': '1.0',
    'colliders': colliders,
    'colliderGroups': groups,
    'springs': springs
  };
}

// ---------------------------------------------------------------------------
// A character kept only for its hair keeps only its hair's pictures.

final Uint8List _onePixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4/58BAAT/Af9jgNErAAAAAElFTkSuQmCC');

void _blankAllButHair(Map<String, dynamic> j, _Glb f) {
  final textures = (j['textures'] as List? ?? const []).cast<Map>();
  final keep = <int>{};
  void note(Object? info) {
    if (info is Map && info['index'] is int) {
      final t = info['index'] as int;
      if (t < textures.length && textures[t]['source'] is int) {
        keep.add(textures[t]['source'] as int);
      }
    }
  }

  for (final m in (j['materials'] as List).cast<Map<String, dynamic>>()) {
    if (!((m['name'] ?? '') as String).contains('HAIR')) continue;
    note((m['pbrMetallicRoughness'] as Map?)?['baseColorTexture']);
    final mt = (m['extensions'] as Map?)?['VRMC_materials_mtoon'] as Map?;
    for (final k in const [
      'shadeMultiplyTexture',
      'rimMultiplyTexture',
      'matcapTexture',
      'outlineWidthMultiplyTexture',
      'uvAnimationMaskTexture'
    ]) {
      note(mt?[k]);
    }
    note(m['normalTexture']);
    note(m['emissiveTexture']);
  }
  final images =
      (j['images'] as List? ?? const []).cast<Map<String, dynamic>>();
  final views = (j['bufferViews'] as List).cast<Map<String, dynamic>>();
  final blank = <int>{
    for (var i = 0; i < images.length; i++)
      if (!keep.contains(i) && images[i]['bufferView'] is int)
        images[i]['bufferView'] as int,
  };
  for (var i = 0; i < images.length; i++) {
    if (!keep.contains(i)) images[i]['mimeType'] = 'image/png';
  }
  // The buffer laid out again, the blanked pictures a pixel each.
  final out = BytesBuilder(copy: false);
  var at = 0;
  for (var i = 0; i < views.length; i++) {
    final v = views[i];
    final start = (v['byteOffset'] ?? 0) as int;
    final data = blank.contains(i)
        ? _onePixel
        : Uint8List.sublistView(f.bin, start, start + (v['byteLength'] as int));
    final pad = (4 - at % 4) % 4;
    if (pad > 0) out.add(Uint8List(pad));
    at += pad;
    v['byteOffset'] = at;
    v['byteLength'] = data.length;
    out.add(data);
    at += data.length;
  }
  f.bin = out.takeBytes();
  (j['buffers'] as List)[0]['byteLength'] = f.bin.length;
}
