import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// text_parts.dart is "these words, not the others".
//
// Its own idea rather than a setting on any one feature, because it is the
// same question asked by several: colour these words, animate these letters,
// echo that one. Written once, the answer is the same wherever it is asked
// and a new feature gets it for nothing; written per feature, it is three
// range pickers that drift apart.
//
// A *list* of parts rather than one range, because one range cannot say
// "words 1 to 5 in red and 6 to 10 in blue" -- which is the first thing
// anybody wants after they have coloured one word.

/// TextUnit is what a part counts in.
enum TextUnit {
  words("Words"),
  characters("Characters");

  final String label;
  const TextUnit(this.label);

  static TextUnit fromName(String? name) =>
      values.firstWhere((u) => u.name == name, orElse: () => words);
}

/// TextPart is a range of the words, and what is different about it.
///
/// Counted from one, because "the sixth word" is how somebody says it and
/// making them say "the fifth" is making them do arithmetic to talk to a
/// settings panel.
class TextPart {
  final TextUnit unit;

  /// from is the first word or letter, counting from one.
  final int from;

  /// to is the last, counting from one and included -- or zero for "to the
  /// end", which is what "words ten till the end" needs and what a range with
  /// a number in it cannot say when the text is edited afterwards.
  final int to;

  /// color is what this part is drawn in, or null to leave it alone.
  final Color? color;

  /// weight and italic are the other two things worth changing about a few
  /// words in a sentence. Null leaves them as the element's own.
  final int? weight;
  final bool? italic;

  const TextPart({
    this.unit = TextUnit.words,
    this.from = 1,
    this.to = 0,
    this.color,
    this.weight,
    this.italic,
  });

  bool get toTheEnd => to <= 0;

  /// says is this part in words, for the settings to show without the reader
  /// having to work it out from three numbers.
  String get says {
    var what = unit == TextUnit.words ? "word" : "letter";
    if (toTheEnd) {
      return from <= 1 ? "Every $what" : "From $what $from to the end";
    }
    if (from == to) return "${what[0].toUpperCase()}${what.substring(1)} $from";
    return "${what[0].toUpperCase()}${what.substring(1)}s $from to $to";
  }

  TextPart copyWith({
    TextUnit? unit,
    int? from,
    int? to,
    Color? color,
    bool clearColor = false,
    int? weight,
    bool? italic,
  }) =>
      TextPart(
        unit: unit ?? this.unit,
        from: from ?? this.from,
        to: to ?? this.to,
        color: clearColor ? null : (color ?? this.color),
        weight: weight ?? this.weight,
        italic: italic ?? this.italic,
      );

  Map<String, dynamic> toJson() => {
        if (unit != TextUnit.words) "unit": unit.name,
        "from": from,
        if (to > 0) "to": to,
        if (color != null) "color": colorToJson(color!),
        if (weight != null) "weight": weight,
        if (italic != null) "italic": italic,
      };

  factory TextPart.fromJson(Map<String, dynamic> json) => TextPart(
        unit: TextUnit.fromName(json["unit"] as String?),
        from: jsonInt(json["from"], 1).clamp(1, 100000),
        to: jsonInt(json["to"], 0).clamp(0, 100000),
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        weight: json["weight"] is num ? (json["weight"] as num).toInt() : null,
        italic: json["italic"] is bool ? json["italic"] as bool : null,
      );
}

/// rangeOf is the characters a part covers, as a start and an end offset into
/// [text].
///
/// Empty where the part names something that is not there -- word twelve of a
/// sentence with six in it -- rather than clamping to the last word: a part
/// that quietly moved to the end would be a part that appeared to work and
/// coloured the wrong thing.
(int, int)? rangeOf(String text, TextPart part) {
  if (text.isEmpty || part.from < 1) return null;

  if (part.unit == TextUnit.characters) {
    // Letters, not code units of whitespace: "the third letter" means the
    // third one somebody can see.
    var at = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (text[i].trim().isNotEmpty) at.add(i);
    }
    if (at.length < part.from) return null;
    var last = part.toTheEnd ? at.length : part.to;
    if (last < part.from) return null;
    var end = at[(last.clamp(part.from, at.length)) - 1] + 1;
    return (at[part.from - 1], end);
  }

  var words = <(int, int)>[];
  var i = 0;
  while (i < text.length) {
    while (i < text.length && text[i].trim().isEmpty) {
      i++;
    }
    var start = i;
    while (i < text.length && text[i].trim().isNotEmpty) {
      i++;
    }
    if (i > start) words.add((start, i));
  }
  if (words.length < part.from) return null;
  var last = part.toTheEnd ? words.length : part.to;
  if (last < part.from) return null;
  return (
    words[part.from - 1].$1,
    words[last.clamp(part.from, words.length) - 1].$2
  );
}

/// partAt is the part covering [index], or null.
///
/// The last one wins where two overlap: the list is the reader's own order,
/// and the thing they added most recently is the thing they are working on.
TextPart? partAt(String text, List<TextPart> parts, int index) {
  TextPart? found;
  for (var part in parts) {
    var range = rangeOf(text, part);
    if (range == null) continue;
    if (index >= range.$1 && index < range.$2) found = part;
  }
  return found;
}
