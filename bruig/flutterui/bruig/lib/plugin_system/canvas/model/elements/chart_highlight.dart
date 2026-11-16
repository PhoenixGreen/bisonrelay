import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:flutter/foundation.dart';

// chart_highlight.dart is a chart's highlights (the Data Studio's Charts
// tab, prototype v5): marks lit in a colour of their own, made as a table's
// styles are -- what it picks out, then its look. They follow the numbers:
// "top 4 by Points" picks out whoever is in the top four after a refresh.

/// ChartReach is what a highlight picks out.
enum ChartReach {
  /// one is the mark whose label is [ChartHighlight.who].
  one("One"),

  /// top and bottom are the [ChartHighlight.n] largest or smallest by a
  /// column.
  top("Top"),
  bottom("Bottom"),

  /// when is every mark whose column meets a number: "GD under 0".
  when("A rule");

  final String label;
  const ChartReach(this.label);

  static ChartReach fromName(String? name) =>
      values.firstWhere((r) => r.name == name, orElse: () => one);
}

/// ChartHighlight is marks picked out in a colour, the rest faded or not.
@immutable
class ChartHighlight {
  /// name is what the Charts tab calls it; empty, named from its reach.
  final String name;
  final ChartReach reach;

  /// who is the label of the one mark picked out.
  final String who;

  /// n is how many, for top and bottom.
  final int n;

  /// by is the column (counted from the range's first) whose numbers rank
  /// the marks, or are tested; -1, the chart's first series.
  final int by;

  /// op and value are the rule: one of ">=", "<=", ">", "<" and "=".
  final String op;
  final double value;

  final Color colour;

  /// fade dims every mark it does not pick out.
  final bool fade;

  /// named writes the label beside the marks it picks out.
  final bool named;

  /// off keeps it without drawing it.
  final bool off;

  const ChartHighlight({
    this.name = "",
    this.reach = ChartReach.one,
    this.who = "",
    this.n = 3,
    this.by = -1,
    this.op = ">=",
    this.value = 0,
    this.colour = const Color(0xFFF2B33D),
    this.fade = false,
    this.named = false,
    this.off = false,
  });

  /// holds is whether a mark worth [v] meets the rule.
  bool holds(double v) => switch (op) {
        ">=" => v >= value,
        "<=" => v <= value,
        ">" => v > value,
        "<" => v < value,
        _ => v == value,
      };

  ChartHighlight copyWith({
    String? name,
    ChartReach? reach,
    String? who,
    int? n,
    int? by,
    String? op,
    double? value,
    Color? colour,
    bool? fade,
    bool? named,
    bool? off,
  }) =>
      ChartHighlight(
        name: name ?? this.name,
        reach: reach ?? this.reach,
        who: who ?? this.who,
        n: n ?? this.n,
        by: by ?? this.by,
        op: op ?? this.op,
        value: value ?? this.value,
        colour: colour ?? this.colour,
        fade: fade ?? this.fade,
        named: named ?? this.named,
        off: off ?? this.off,
      );

  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) "name": name,
        "reach": reach.name,
        if (who.isNotEmpty) "who": who,
        if (reach == ChartReach.top || reach == ChartReach.bottom) "n": n,
        if (by >= 0) "by": by,
        if (reach == ChartReach.when) "op": op,
        if (reach == ChartReach.when) "value": value,
        "colour": colour.toARGB32(),
        if (fade) "fade": true,
        if (named) "named": true,
        if (off) "off": true,
      };

  static ChartHighlight? fromJson(Object? j) {
    if (j is! Map) return null;
    var op = j["op"];
    return ChartHighlight(
      name: jsonString(j["name"], ""),
      reach: ChartReach.fromName(j["reach"] as String?),
      who: jsonString(j["who"], ""),
      n: j["n"] is num ? (j["n"] as num).toInt().clamp(1, 1000) : 3,
      by: j["by"] is num ? (j["by"] as num).toInt() : -1,
      op: const [">=", "<=", ">", "<", "="].contains(op) ? op as String : ">=",
      value: j["value"] is num ? (j["value"] as num).toDouble() : 0,
      colour: j["colour"] is int
          ? Color(j["colour"] as int)
          : const Color(0xFFF2B33D),
      fade: j["fade"] == true,
      named: j["named"] == true,
      off: j["off"] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChartHighlight &&
      other.name == name &&
      other.reach == reach &&
      other.who == who &&
      other.n == n &&
      other.by == by &&
      other.op == op &&
      other.value == value &&
      other.colour == colour &&
      other.fade == fade &&
      other.named == named &&
      other.off == off;

  @override
  int get hashCode =>
      Object.hash(name, reach, who, n, by, op, value, colour, fade, named, off);
}

/// picksOut is which of [labels] a set of [highlights] lights, and in what
/// colour: [valuesOf] gives the numbers of a column (by), one per label.
/// Later highlights win. Null where none reaches a mark; the faded colour
/// where one fades the rest; [base] is what a faded mark was.
List<Color?> marksOf(List<ChartHighlight> highlights, List<String> labels,
    List<double> Function(int by) valuesOf, Color Function(int i) base) {
  var out = List<Color?>.filled(labels.length, null);
  var lit = List<bool>.filled(labels.length, false);
  var fades = false;
  for (var h in highlights) {
    if (h.off) continue;
    var hit = _reached(h, labels, valuesOf);
    for (var i = 0; i < labels.length; i++) {
      if (hit.contains(i)) {
        out[i] = h.colour;
        lit[i] = true;
      }
    }
    fades = fades || h.fade;
  }
  if (fades) {
    for (var i = 0; i < labels.length; i++) {
      if (!lit[i]) out[i] = base(i).withValues(alpha: base(i).a * 0.25);
    }
  }
  return out;
}

Set<int> _reached(ChartHighlight h, List<String> labels,
    List<double> Function(int by) valuesOf) {
  switch (h.reach) {
    case ChartReach.one:
      var who = h.who.trim().toLowerCase();
      return {
        for (var (i, l) in labels.indexed)
          if (l.trim().toLowerCase() == who) i
      };
    case ChartReach.top:
    case ChartReach.bottom:
      var v = valuesOf(h.by);
      var order = [
        for (var i = 0; i < labels.length; i++)
          if (i < v.length && !v[i].isNaN) i
      ];
      // Ties keep the sheet's order (Dart's sort is not stable).
      order.sort((a, b) {
        var c = v[b].compareTo(v[a]);
        return c != 0 ? c : a.compareTo(b);
      });
      var n = h.n.clamp(0, order.length);
      return (h.reach == ChartReach.top
              ? order.take(n)
              : order.skip(order.length - n))
          .toSet();
    case ChartReach.when:
      var v = valuesOf(h.by);
      return {
        for (var i = 0; i < labels.length && i < v.length; i++)
          if (!v[i].isNaN && h.holds(v[i])) i
      };
  }
}

/// ChartNoteKind is what a note on a chart is: a line across it at a value
/// (or the average), a band behind some places (a drop zone), or a word
/// over one mark.
enum ChartNoteKind { line, band, label }

/// ChartNote is something written or drawn on a chart beside its data
/// (prototype v5's notes): an average line, a band behind 18th to 20th, a
/// word over a bar.
@immutable
class ChartNote {
  final ChartNoteKind kind;

  /// text is its words: a line's and a band's label, a label's text.
  final String text;

  /// value is where a line crosses; NaN, the average of the first series.
  final double value;

  /// from and to are the places a band lies behind, counting from 1 along
  /// the chart as it shows them.
  final int from, to;

  /// who is the label of the mark a label is written over.
  final String who;

  final Color colour;
  final bool off;

  const ChartNote({
    this.kind = ChartNoteKind.line,
    this.text = "",
    this.value = double.nan,
    this.from = 1,
    this.to = 1,
    this.who = "",
    this.colour = const Color(0xFFF2B33D),
    this.off = false,
  });

  ChartNote copyWith({
    ChartNoteKind? kind,
    String? text,
    double? value,
    int? from,
    int? to,
    String? who,
    Color? colour,
    bool? off,
  }) =>
      ChartNote(
        kind: kind ?? this.kind,
        text: text ?? this.text,
        value: value ?? this.value,
        from: from ?? this.from,
        to: to ?? this.to,
        who: who ?? this.who,
        colour: colour ?? this.colour,
        off: off ?? this.off,
      );

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (text.isNotEmpty) "text": text,
        if (kind == ChartNoteKind.line && !value.isNaN) "value": value,
        if (kind == ChartNoteKind.band) "from": from,
        if (kind == ChartNoteKind.band) "to": to,
        if (who.isNotEmpty) "who": who,
        "colour": colour.toARGB32(),
        if (off) "off": true,
      };

  static ChartNote? fromJson(Object? j) {
    if (j is! Map) return null;
    int n(String k, int or) => j[k] is num ? (j[k] as num).toInt() : or;
    return ChartNote(
      kind:
          ChartNoteKind.values.where((k) => k.name == j["kind"]).firstOrNull ??
              ChartNoteKind.line,
      text: jsonString(j["text"], ""),
      value: j["value"] is num ? (j["value"] as num).toDouble() : double.nan,
      from: n("from", 1),
      to: n("to", 1),
      who: jsonString(j["who"], ""),
      colour: j["colour"] is int
          ? Color(j["colour"] as int)
          : const Color(0xFFF2B33D),
      off: j["off"] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChartNote &&
      other.kind == kind &&
      other.text == text &&
      (other.value == value || (other.value.isNaN && value.isNaN)) &&
      other.from == from &&
      other.to == to &&
      other.who == who &&
      other.colour == colour &&
      other.off == off;

  @override
  int get hashCode => Object.hash(
      kind, text, value.isNaN ? -1 : value, from, to, who, colour, off);
}

/// ChartStep is one step of a chart told in parts (prototype v6's steps):
/// its own title, highlights, notes and date, the rest of the chart shared.
/// On the timeline the chart moves from step to step (ChartElement.play
/// seconds each), easing between them.
@immutable
class ChartStep {
  final String name;
  final String title;
  final List<ChartHighlight> highlights;
  final List<ChartNote> notes;

  /// at is the date it shows, for a chart playing through dates; empty, the
  /// last.
  final String at;

  const ChartStep({
    this.name = "",
    this.title = "",
    this.highlights = const [],
    this.notes = const [],
    this.at = "",
  });

  ChartStep copyWith({
    String? name,
    String? title,
    List<ChartHighlight>? highlights,
    List<ChartNote>? notes,
    String? at,
  }) =>
      ChartStep(
        name: name ?? this.name,
        title: title ?? this.title,
        highlights: highlights ?? this.highlights,
        notes: notes ?? this.notes,
        at: at ?? this.at,
      );

  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) "name": name,
        if (title.isNotEmpty) "title": title,
        if (highlights.isNotEmpty)
          "highlights": [for (var h in highlights) h.toJson()],
        if (notes.isNotEmpty) "notes": [for (var n in notes) n.toJson()],
        if (at.isNotEmpty) "at": at,
      };

  static ChartStep? fromJson(Object? j) {
    if (j is! Map) return null;
    return ChartStep(
      name: jsonString(j["name"], ""),
      title: jsonString(j["title"], ""),
      highlights: [
        if (j["highlights"] case List hs)
          for (var h in hs)
            if (ChartHighlight.fromJson(h) case var hl?) hl,
      ],
      notes: [
        if (j["notes"] case List ns)
          for (var n in ns)
            if (ChartNote.fromJson(n) case var note?) note,
      ],
      at: jsonString(j["at"], ""),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChartStep &&
      other.name == name &&
      other.title == title &&
      listEquals(other.highlights, highlights) &&
      listEquals(other.notes, notes) &&
      other.at == at;

  @override
  int get hashCode => Object.hash(
      name, title, Object.hashAll(highlights), Object.hashAll(notes), at);
}
