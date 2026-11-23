import 'dart:ui' show Color, Offset;

// json_read.dart is how every saved field is read.
//
// A saved canvas may be old, from a newer build, or from somebody hostile, so
// a reader never throws and never keeps a value at any size it likes: a
// missing or mistyped field becomes its fallback, a number must be finite, a
// string is cut and a list is counted. A cast that throws (`as String`)
// loses the whole document; read through these instead. ARCHITECTURE.md
// ("Saved form") says what each limit is for.

/// maxTextLength is the most characters any string is read with: far more
/// than a page holds, and a received canvas's ten million would be laid out
/// every frame.
const maxTextLength = 200000;

/// maxIdLength and maxLabelLength bound an id, and a name, label, title or
/// font, as read: far longer than any real one, while a received canvas's
/// millions of characters would be compared, hashed and laid out wherever
/// the field is used.
const maxIdLength = 200, maxLabelLength = 1000;

/// maxListLength is the most entries a list is read with where its field
/// sets no smaller limit of its own.
const maxListLength = 100000;

/// maxDesignLength is the most a length in design units is read with where
/// its field sets no limit of its own (a letter spacing, a border, a
/// padding, a blur): ten times what a panel offers, so a page enlarged
/// several times over reads as it was made, while a received canvas's
/// billion-unit blur is never attempted.
const maxDesignLength = 4000.0;

/// jsonLength is [v] as a length in design units, from nought (or, [signed],
/// as far below it) to [maxDesignLength]; or [fallback].
double jsonLength(Object? v, double fallback, {bool signed = false}) =>
    jsonDouble(v, fallback)
        .clamp(signed ? -maxDesignLength : 0.0, maxDesignLength);

/// jsonDouble and jsonInt are [v] as a finite number, or [fallback]. JSON
/// reads 1e999 as infinity, which would throw at the first round().
double jsonDouble(Object? v, double fallback) =>
    v is num && v.isFinite ? v.toDouble() : fallback;
int jsonInt(Object? v, int fallback) =>
    v is num && v.isFinite ? v.toInt() : fallback;

bool jsonBool(Object? v, bool fallback) => v is bool ? v : fallback;

/// jsonString is [v] as a string of at most [most] characters, or
/// [fallback].
String jsonString(Object? v, String fallback, {int most = maxTextLength}) =>
    v is String ? _cut(v, most) : fallback;

/// jsonId is an id, and jsonLabel a name, label, title or font: strings
/// with the shorter limits above.
String jsonId(Object? v, String fallback) =>
    _cut(jsonString(v, fallback), maxIdLength);
String jsonLabel(Object? v, String fallback) =>
    _cut(jsonString(v, fallback), maxLabelLength);

String _cut(String s, int most) => s.length <= most ? s : s.substring(0, most);

/// jsonStr, jsonNum and jsonMap are [v] as a string, a finite number or a
/// JSON object, or null where it is not one: for a field whose absence
/// means something, and for an enum's fromName.
String? jsonStr(Object? v) => v is String ? _cut(v, maxTextLength) : null;
num? jsonNum(Object? v) => v is num && v.isFinite ? v : null;
Map<String, dynamic>? jsonMap(Object? v) =>
    v is Map<String, dynamic> ? v : null;

/// jsonSpec reads a nested value object (TextSpec, BoxSpec...) with [parse],
/// or is [fallback] when the field is missing or not an object.
T jsonSpec<T>(Object? v, T Function(Map<String, dynamic>) parse, T fallback) =>
    v is Map<String, dynamic> ? parse(v) : fallback;

/// jsonList reads a list with [parse], which is handed each entry and
/// returns null for one to leave out. At most [most] entries are read. Not
/// a list gives an empty list.
List<T> jsonList<T>(Object? v, T? Function(Object? entry) parse,
        {int most = maxListLength}) =>
    [
      if (v is List)
        for (var entry in v.take(most))
          if (parse(entry) case var read?) read,
    ];

/// jsonObjects is [jsonList] for entries that are JSON objects read by a
/// [parse] that takes one; anything else in the list is left out.
List<T> jsonObjects<T>(Object? v, T Function(Map<String, dynamic>) parse,
        {int most = maxListLength}) =>
    jsonList(v, (entry) => entry is Map<String, dynamic> ? parse(entry) : null,
        most: most);

/// colorToJson and colorFromJson save a colour as 0xAARRGGBB in a plain
/// integer, so it round-trips exactly (float channels through JSON would not).
int colorToJson(Color c) =>
    (_channel(c.a) << 24) |
    (_channel(c.r) << 16) |
    (_channel(c.g) << 8) |
    _channel(c.b);

int _channel(double v) => (v * 255).round().clamp(0, 255);

Color colorFromJson(Object? v, [Color fallback = const Color(0xFFFFFFFF)]) =>
    v is num && v.isFinite ? Color(v.toInt() & 0xFFFFFFFF) : fallback;

/// fractionsFromJson reads a flat [x, y, ...] list of points as fractions of
/// a picture: within a width either side, and at most 100,000, so a sent
/// stroke cannot ask for billions of dabs.
List<Offset> fractionsFromJson(Object? flat) {
  var points = <Offset>[];
  if (flat is! List) return points;
  for (var i = 0;
      i + 1 < flat.length && points.length < maxListLength;
      i += 2) {
    var x = flat[i], y = flat[i + 1];
    if (x is num && y is num && x.isFinite && y.isFinite) {
      points.add(
          Offset(x.toDouble().clamp(-1.0, 2.0), y.toDouble().clamp(-1.0, 2.0)));
    }
  }
  return points;
}

/// finiteJson is [json] with non-finite numbers (1e999 reads as infinity)
/// dropped from maps and made nought in lists. A whole document goes
/// through it once as it is decoded.
Object? finiteJson(Object? json) => switch (json) {
      Map m => <String, dynamic>{
          for (var e in m.entries)
            if (!(e.value is double && !(e.value as double).isFinite))
              "${e.key}": finiteJson(e.value),
        },
      List l => [
          for (var x in l) x is double && !x.isFinite ? 0 : finiteJson(x),
        ],
      _ => json,
    };
