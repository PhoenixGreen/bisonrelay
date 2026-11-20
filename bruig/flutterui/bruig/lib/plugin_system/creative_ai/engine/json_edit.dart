import 'dart:convert';

// json_edit.dart is the three ways an assistant says how to change a piece of
// JSON, and the way a large piece is cut down before it is shown to one.
//
//   - a merge patch (RFC 7396): an object laid over the original, where a
//     key set to null is taken out and an object merges into an object.
//     What an assistant reaches for first: send only what changes.
//   - set: a JSON Pointer (RFC 6901) and the value to put there, for a
//     place in a list a merge patch cannot reach ("/keys/2/frame"), with
//     "-" at the end of a list to add to it.
//   - remove: a JSON Pointer to take out.
//
// Pure Dart, no Flutter: everything here is tested on its own.

/// JsonEditError is an edit that could not be made, said for the assistant
/// that asked for it.
class JsonEditError implements Exception {
  final String message;
  JsonEditError(this.message);
  @override
  String toString() => message;
}

/// mergePatch is [target] with [patch] laid over it (RFC 7396).
Object? mergePatch(Object? target, Object? patch) {
  if (patch is! Map) return patch;
  var out =
      target is Map ? Map<String, dynamic>.from(target) : <String, dynamic>{};
  for (var e in patch.entries) {
    var key = "${e.key}";
    if (e.value == null) {
      out.remove(key);
    } else {
      out[key] = mergePatch(out[key], e.value);
    }
  }
  return out;
}

/// pointerParts splits a JSON Pointer into its unescaped parts. "" and "/"
/// are the whole document.
List<String> pointerParts(String pointer) {
  if (pointer.isEmpty || pointer == "/") return const [];
  if (!pointer.startsWith("/")) {
    throw JsonEditError(
        'A path starts with "/", as in "/textSpec/fontSize": "$pointer".');
  }
  return [
    for (var p in pointer.substring(1).split("/"))
      p.replaceAll("~1", "/").replaceAll("~0", "~")
  ];
}

/// readPointer is what [pointer] names inside [json].
Object? readPointer(Object? json, String pointer) {
  Object? at = json;
  for (var part in pointerParts(pointer)) {
    if (at is Map) {
      if (!at.containsKey(part)) {
        throw JsonEditError('Nothing at "$pointer": no "$part".');
      }
      at = at[part];
    } else if (at is List) {
      var i = int.tryParse(part);
      if (i == null || i < 0 || i >= at.length) {
        throw JsonEditError(
            'Nothing at "$pointer": "$part" is not a place in a list of '
            '${at.length}.');
      }
      at = at[i];
    } else {
      throw JsonEditError('Nothing at "$pointer": "$part" is inside a value.');
    }
  }
  return at;
}

/// setPointer is [json] with [value] put at [pointer]: a key added or
/// replaced, a place in a list replaced, or "-" added to the end of one.
/// Objects missing on the way are made.
Object? setPointer(Object? json, String pointer, Object? value) {
  var parts = pointerParts(pointer);
  if (parts.isEmpty) return value;
  return _set(json, parts, 0, value, pointer);
}

Object? _set(
    Object? at, List<String> parts, int i, Object? value, String pointer) {
  var part = parts[i];
  var last = i == parts.length - 1;
  if (at is List) {
    var list = [...at];
    if (part == "-") {
      if (!last) throw JsonEditError('"-" can only end a path: "$pointer".');
      list.add(value);
      return list;
    }
    var n = int.tryParse(part);
    if (n == null || n < 0 || n >= list.length) {
      throw JsonEditError('"$part" is not a place in the list at "$pointer" '
          '(it holds ${list.length}).');
    }
    list[n] = last ? value : _set(list[n], parts, i + 1, value, pointer);
    return list;
  }
  var map = at is Map ? Map<String, dynamic>.from(at) : <String, dynamic>{};
  if (at != null && at is! Map) {
    throw JsonEditError(
        'Cannot set "$pointer": the value before "$part" is not an object.');
  }
  map[part] = last ? value : _set(map[part], parts, i + 1, value, pointer);
  return map;
}

/// removePointer is [json] with what [pointer] names taken out.
Object? removePointer(Object? json, String pointer) {
  var parts = pointerParts(pointer);
  if (parts.isEmpty) throw JsonEditError("The whole of it cannot be removed.");
  readPointer(json, pointer); // Says clearly when there is nothing there.
  return _remove(json, parts, 0);
}

Object? _remove(Object? at, List<String> parts, int i) {
  var part = parts[i];
  var last = i == parts.length - 1;
  if (at is List) {
    var list = [...at];
    var n = int.parse(part);
    if (last) {
      list.removeAt(n);
    } else {
      list[n] = _remove(list[n], parts, i + 1);
    }
    return list;
  }
  var map = Map<String, dynamic>.from(at as Map);
  if (last) {
    map.remove(part);
  } else {
    map[part] = _remove(map[part], parts, i + 1);
  }
  return map;
}

/// JsonSet is one "set" edit: [value] at [path].
class JsonSet {
  final String path;
  final Object? value;
  const JsonSet(this.path, this.value);
}

/// applyEdits is [json] with a merge [patch], then each of [sets], then each
/// of [removes], in that order.
Object? applyEdits(Object? json,
    {Object? patch,
    List<JsonSet> sets = const [],
    List<String> removes = const []}) {
  var out = json;
  if (patch != null) out = mergePatch(out, patch);
  for (var s in sets) {
    out = setPointer(out, s.path, s.value);
  }
  for (var r in removes) {
    out = removePointer(out, r);
  }
  return out;
}

/// compactJson is [json] cut down to about [budget] characters for showing:
/// long strings shortened, long lists trimmed, and deep levels summed up,
/// each cut saying what was left out and how to see it.
Object? compactJson(Object? json, {int budget = 40000}) {
  if (jsonEncode(json).length <= budget) return json;
  for (var (stringMax, listMax, depth) in const [
    (400, 40, 8),
    (200, 20, 5),
    (120, 10, 4),
    (80, 6, 3),
    (60, 4, 2),
  ]) {
    var cut = _cut(json, "", stringMax, listMax, depth);
    if (jsonEncode(cut).length <= budget) return cut;
  }
  return _cut(json, "", 60, 3, 1);
}

Object? _cut(Object? v, String path, int stringMax, int listMax, int depth) {
  if (v is String) {
    return v.length <= stringMax
        ? v
        : "${v.substring(0, stringMax)}… (${v.length - stringMax} more "
            "characters: read \"$path\" to see all of it)";
  }
  if (v is List) {
    if (depth <= 0) return "[a list of ${v.length}: read \"$path\"]";
    var out = [
      for (var i = 0; i < v.length && i < listMax; i++)
        _cut(v[i], "$path/$i", stringMax, listMax, depth - 1)
    ];
    if (v.length > listMax) {
      out.add("… ${v.length - listMax} more: read \"$path/$listMax\" and on");
    }
    return out;
  }
  if (v is Map) {
    if (depth <= 0) {
      return "{an object of ${v.length} keys: read \"$path\"}";
    }
    return {
      for (var e in v.entries)
        "${e.key}": _cut(e.value, "$path/${_escape("${e.key}")}", stringMax,
            listMax, depth - 1)
    };
  }
  return v;
}

String _escape(String key) => key.replaceAll("~", "~0").replaceAll("/", "~1");
