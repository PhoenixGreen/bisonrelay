import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// counter_element.dart is a number that counts.
//
// Two things in one element, and deliberately: a number that counts from one
// value to another across the timeline, and -- with the keyframes switched
// off -- a number that counts in real time. The first is a figure animating
// up in a video; the second is a clock, a stopwatch, a countdown or a
// metronome on an interactive canvas. They are the same element because they
// are the same thing to look at and to style: a formatted number with words
// either side of it in a box, and the only difference is where the number
// comes from.
//
// The number is not text. A text element with "100" typed in it cannot count,
// cannot be counted from, and has no idea what a thousands separator is -- and
// the whole reason to reach for this is that "1,240,000" and "1.24M" and
// "20:41" are the same number written three ways.

/// CounterSeparator is how the digits are grouped and punctuated.
///
/// The grouping and the point are one setting rather than two because they
/// are one decision -- a number written 1.234,56 is not a number written
/// 1,234.56 with a different point, it is a different convention -- and
/// because the two time formats are not grouping at all.
enum CounterSeparator {
  none("None", "1234.5"),
  comma("1,234.5", "Thousands in commas"),
  dot("1.234,5", "Thousands in points"),
  space("1 234,5", "Thousands in spaces"),

  /// minutes and hours are the counter as a duration rather than as a
  /// quantity: the value is counted in seconds and written in the parts a
  /// clock is written in.
  minutes("1:57", "Minutes and seconds"),
  hours("1:57:03", "Hours, minutes and seconds");

  final String label;
  final String description;
  const CounterSeparator(this.label, this.description);

  /// isTime is whether the value is a number of seconds rather than a
  /// quantity, which changes what the decimals mean and what counting by one
  /// looks like.
  bool get isTime => this == minutes || this == hours;

  static CounterSeparator fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => CounterSeparator.none,
      );
}

/// CounterSource is where a live counter's number comes from when the
/// keyframes are off.
///
/// Only when they are off: with keyframes on, the number is whatever the
/// timeline says at this frame and none of this applies.
enum CounterSource {
  /// run counts from the start value towards the end value at [rate] a
  /// second, which is a countdown, a stopwatch and a metronome depending on
  /// which way round the two ends are and how fast it goes.
  run("Counts", "From the start value to the end at a rate you set"),

  /// clock is the time of day, in seconds since midnight. Written with the
  /// Minutes or Hours separator it is a clock; written plain it is a number
  /// nobody wants, which is why choosing it sets the separator.
  clock("The time", "The time of day on the reader's own clock");

  final String label;
  final String description;
  const CounterSource(this.label, this.description);

  static CounterSource fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => CounterSource.run);
}

/// CounterButton is one of the controls a live counter can offer.
enum CounterButton {
  startStop("Start / stop", "Runs the counter and holds it"),
  reset("Reset", "Back to the start value"),
  input("Set", "Type a value for it to count from");

  final String label;
  final String description;
  const CounterButton(this.label, this.description);

  static CounterButton? fromName(String? name) {
    for (var b in values) {
      if (b.name == name) return b;
    }
    return null;
  }
}

/// CounterElement is the element itself.
class CounterElement extends CanvasElement {
  /// from and to are the two ends of the count.
  ///
  /// Either way round: 100 to 1 is a countdown, and a counter whose ends are
  /// the same is a number that sits still, which is a perfectly good thing to
  /// want from a clock.
  final double from;
  final double to;

  /// decimals is how many figures after the point, and [separator] is how the
  /// rest is punctuated.
  final int decimals;
  final CounterSeparator separator;

  /// before and after are the words either side of the number: a currency in
  /// front, a unit behind. Their own strings rather than part of the number's
  /// text because they do not count -- "£" stays put while the figures move.
  final String before;
  final String after;

  /// gap is the space between the number and the words either side of it, in
  /// the number's own ems.
  ///
  /// In ems rather than pixels so that it holds when the type is shrunk to
  /// fit: a fixed gap set for sixty-point figures is a chasm beside
  /// twenty-point ones. Nought is the words against the number, which is
  /// right for a currency in front and wrong for a unit behind -- so it is a
  /// setting rather than a rule.
  final double gap;

  /// loose lets the words be placed anywhere in the box instead of sitting on
  /// the number's line, and [beforeAt] and [afterAt] are where they go: a
  /// fraction of the box from its middle, so -0.5 is the left or top edge and
  /// 0.5 the right or bottom.
  ///
  /// Off is one line, which is what a counter is. On is for the designs that
  /// are not: a currency tucked into a corner, a unit hanging under the
  /// figures.
  final bool loose;
  final Offset beforeAt;
  final Offset afterAt;

  /// numberSpec is the number's own type and [affixSpec] is the words'.
  ///
  /// Two, because the point of putting "bpm" after a figure is that it is
  /// smaller and quieter than the figure. One spec for both made the unit as
  /// loud as the number, which is the one thing nobody wants.
  final TextSpec numberSpec;
  final TextSpec affixSpec;

  /// box is the background, border, radius and padding round the whole thing.
  final BoxSpec box;

  /// fit shrinks the type until the whole count fits the box.
  ///
  /// On by default, and this is the element that needs it: the width of the
  /// number changes as it counts. A counter set to look right at 42 clips at
  /// 1,234,567, and the first anybody knows about it is the frame where that
  /// happens. The size is chosen from the *widest* value the count will ever
  /// reach rather than from the one showing, so the figures do not change
  /// size as they go.
  final bool fit;

  /// keyed is whether the number is read off the timeline.
  ///
  /// On, the count is keyframes: the start value pinned at one frame, the end
  /// at another, and any number of points in between whose values may be
  /// higher or lower than either end. Off, the counter runs in real time and
  /// the buttons below mean something -- which is the whole reason this is a
  /// switch rather than two elements. A clock is a counter nobody keyframed.
  final bool keyed;

  /// source, rate and loop are the live counter's own settings.
  ///
  /// rate is in units a second: sixty on a counter written as minutes is a
  /// stopwatch, one is a seconds counter, and a hundred and twenty with a
  /// short loop is a metronome.
  final CounterSource source;
  final double rate;
  final bool loop;

  /// running is whether a live counter is counting before anybody presses
  /// anything. A clock on a page should be going when the page opens; a
  /// stopwatch should not.
  final bool running;

  /// buttons are the controls drawn under the number, in this order. Empty
  /// for the counters that are a display rather than an instrument.
  final List<CounterButton> buttons;

  /// buttonSpec and buttonBox are how those controls are drawn.
  final TextSpec buttonSpec;
  final BoxSpec buttonBox;

  /// looseButtons lets the buttons be placed anywhere in the box instead of
  /// sitting in a row along the bottom, and [buttonAt] is where each of them
  /// goes -- a fraction of the box from its middle, like [beforeAt].
  ///
  /// A row along the bottom is what a set of controls is, and a counter whose
  /// Start sits under the figures with its Reset out at the corner is a
  /// design decision the row cannot express.
  final bool looseButtons;
  final List<Offset> buttonAt;

  /// buttonSize is how big a freely placed button is, as a fraction of the
  /// box. Sitting in the row they share the width and take the height the
  /// label needs; placed by hand they have no row to take it from.
  final Size buttonSize;

  /// animation is how the whole element arrives and leaves, the same as every
  /// other element's.
  final ElementAnimation animation;

  const CounterElement(
    super.base, {
    this.from = 0,
    this.to = 100,
    this.decimals = 0,
    this.separator = CounterSeparator.none,
    this.before = "",
    this.after = "",
    this.gap = 0,
    this.loose = false,
    this.beforeAt = Offset.zero,
    this.afterAt = Offset.zero,
    this.numberSpec =
        const TextSpec(fontSize: 64, weight: 700, align: TextAlignSpec.center),
    this.affixSpec =
        const TextSpec(fontSize: 28, weight: 400, align: TextAlignSpec.center),
    this.box = const BoxSpec(padding: 16),
    this.fit = true,
    this.keyed = true,
    this.source = CounterSource.run,
    this.rate = 1,
    this.loop = false,
    this.running = false,
    this.buttons = const [],
    this.buttonSpec =
        const TextSpec(fontSize: 16, weight: 600, align: TextAlignSpec.center),
    this.looseButtons = false,
    this.buttonAt = const [],
    this.buttonSize = const Size(0.3, 0.18),
    this.buttonBox = const BoxSpec(
        fill: Color(0xFF223046),
        borderRadius: 6,
        padding: 8,
        borderWidth: 1,
        borderColor: Color(0x33FFFFFF)),
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.counter;

  /// span is how far the count travels, which is what a fraction of it means.
  double get span => to - from;

  /// valueAtFraction is the number [t] of the way through the count, for the
  /// callers that have a fraction rather than a keyframed value.
  double valueAtFraction(double t) => from + span * t.clamp(0.0, 1.0);

  /// format writes [value] the way this counter is set up to write it.
  String format(double value) => formatCounter(value, decimals, separator);

  /// text is the whole line: the words in front, the number, the words after.
  String textFor(double value) => "$before${format(value)}$after";

  /// placedButton is where button [i] sits when the buttons are placed by
  /// hand, as a fraction of the box from its middle.
  ///
  /// Spread down the middle for the ones nobody has placed yet, so switching
  /// the setting on gives three buttons in three different places rather than
  /// three stacked on one another.
  Offset placedButton(int i) {
    if (i < buttonAt.length) return buttonAt[i];
    var count = buttons.isEmpty ? 1 : buttons.length;
    return Offset(0, 0.3 - (count - 1 - i) * 0.18);
  }

  /// live is whether this counter runs in real time, which is what the
  /// buttons are for and what makes it an instrument rather than a picture.
  bool get live => !keyed;

  @override
  CanvasElement rebase(ElementBase base) => CounterElement(base,
      from: from,
      to: to,
      decimals: decimals,
      separator: separator,
      before: before,
      after: after,
      gap: gap,
      loose: loose,
      beforeAt: beforeAt,
      afterAt: afterAt,
      numberSpec: numberSpec,
      affixSpec: affixSpec,
      box: box,
      fit: fit,
      keyed: keyed,
      source: source,
      rate: rate,
      loop: loop,
      running: running,
      buttons: buttons,
      buttonSpec: buttonSpec,
      buttonBox: buttonBox,
      looseButtons: looseButtons,
      buttonAt: buttonAt,
      buttonSize: buttonSize,
      animation: animation);

  CounterElement copyWith({
    double? from,
    double? to,
    int? decimals,
    CounterSeparator? separator,
    String? before,
    String? after,
    double? gap,
    bool? loose,
    Offset? beforeAt,
    Offset? afterAt,
    TextSpec? numberSpec,
    TextSpec? affixSpec,
    BoxSpec? box,
    bool? fit,
    bool? keyed,
    CounterSource? source,
    double? rate,
    bool? loop,
    bool? running,
    List<CounterButton>? buttons,
    TextSpec? buttonSpec,
    BoxSpec? buttonBox,
    bool? looseButtons,
    List<Offset>? buttonAt,
    Size? buttonSize,
    ElementAnimation? animation,
  }) =>
      CounterElement(base,
          from: from ?? this.from,
          to: to ?? this.to,
          decimals: decimals ?? this.decimals,
          separator: separator ?? this.separator,
          before: before ?? this.before,
          after: after ?? this.after,
          gap: gap ?? this.gap,
          loose: loose ?? this.loose,
          beforeAt: beforeAt ?? this.beforeAt,
          afterAt: afterAt ?? this.afterAt,
          numberSpec: numberSpec ?? this.numberSpec,
          affixSpec: affixSpec ?? this.affixSpec,
          box: box ?? this.box,
          fit: fit ?? this.fit,
          keyed: keyed ?? this.keyed,
          source: source ?? this.source,
          rate: rate ?? this.rate,
          loop: loop ?? this.loop,
          running: running ?? this.running,
          buttons: buttons ?? this.buttons,
          buttonSpec: buttonSpec ?? this.buttonSpec,
          buttonBox: buttonBox ?? this.buttonBox,
          looseButtons: looseButtons ?? this.looseButtons,
          buttonAt: buttonAt ?? this.buttonAt,
          buttonSize: buttonSize ?? this.buttonSize,
          animation: animation ?? this.animation);

  @override
  Map<String, dynamic> props() => {
        "from": from,
        "to": to,
        if (decimals != 0) "decimals": decimals,
        if (separator != CounterSeparator.none) "sep": separator.name,
        if (before.isNotEmpty) "before": before,
        if (after.isNotEmpty) "after": after,
        if (gap != 0) "gap": gap,
        if (loose) "loose": true,
        if (loose) "beforeAt": [beforeAt.dx, beforeAt.dy],
        if (loose) "afterAt": [afterAt.dx, afterAt.dy],
        "numberSpec": numberSpec.toJson(),
        "affixSpec": affixSpec.toJson(),
        "box": box.toJson(),
        if (!fit) "noFit": true,
        if (!keyed) "live": true,
        if (source != CounterSource.run) "source": source.name,
        if (rate != 1) "rate": rate,
        if (loop) "loop": true,
        if (running) "running": true,
        if (buttons.isNotEmpty) "buttons": [for (var b in buttons) b.name],
        if (buttons.isNotEmpty) "buttonSpec": buttonSpec.toJson(),
        if (buttons.isNotEmpty) "buttonBox": buttonBox.toJson(),
        if (looseButtons) "looseButtons": true,
        if (looseButtons)
          "buttonAt": [
            for (var at in buttonAt) [at.dx, at.dy]
          ],
        if (looseButtons) "buttonSize": [buttonSize.width, buttonSize.height],
        "animation": animation.toJson(),
      };

  factory CounterElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var raw = json["buttons"];
    return CounterElement(b,
        from: jsonDouble(json["from"], 0),
        to: jsonDouble(json["to"], 100),
        decimals: jsonInt(json["decimals"], 0).clamp(0, 8),
        separator: CounterSeparator.fromName(json["sep"] as String?),
        before: jsonString(json["before"], ""),
        after: jsonString(json["after"], ""),
        gap: jsonDouble(json["gap"], 0),
        loose: jsonBool(json["loose"], false),
        beforeAt: _offsetFromJson(json["beforeAt"]),
        afterAt: _offsetFromJson(json["afterAt"]),
        numberSpec: jsonSpec(
            json["numberSpec"],
            TextSpec.fromJson,
            const TextSpec(
                fontSize: 64, weight: 700, align: TextAlignSpec.center)),
        affixSpec: jsonSpec(
            json["affixSpec"],
            TextSpec.fromJson,
            const TextSpec(
                fontSize: 28, weight: 400, align: TextAlignSpec.center)),
        box:
            jsonSpec(json["box"], BoxSpec.fromJson, const BoxSpec(padding: 16)),
        fit: !jsonBool(json["noFit"], false),
        keyed: !jsonBool(json["live"], false),
        source: CounterSource.fromName(json["source"] as String?),
        rate: jsonDouble(json["rate"], 1),
        loop: jsonBool(json["loop"], false),
        running: jsonBool(json["running"], false),
        buttons: raw is List
            ? [
                for (var name in raw)
                  if (CounterButton.fromName(name as String?) case var button?)
                    button,
              ]
            : const [],
        buttonSpec: jsonSpec(
            json["buttonSpec"],
            TextSpec.fromJson,
            const TextSpec(
                fontSize: 16, weight: 600, align: TextAlignSpec.center)),
        looseButtons: jsonBool(json["looseButtons"], false),
        buttonAt: json["buttonAt"] is List
            ? [for (var at in json["buttonAt"] as List) _offsetFromJson(at)]
            : const [],
        buttonSize: json["buttonSize"] is List &&
                (json["buttonSize"] as List).length == 2
            ? Size(jsonDouble((json["buttonSize"] as List)[0], 0.3),
                jsonDouble((json["buttonSize"] as List)[1], 0.18))
            : const Size(0.3, 0.18),
        buttonBox: jsonSpec(
            json["buttonBox"],
            BoxSpec.fromJson,
            const BoxSpec(
                fill: Color(0xFF223046),
                borderRadius: 6,
                padding: 8,
                borderWidth: 1,
                borderColor: Color(0x33FFFFFF))),
        animation: jsonSpec(json["animation"], ElementAnimation.fromJson,
            const ElementAnimation()));
  }
}

/// _offsetFromJson reads a placement, which is saved as a pair.
Offset _offsetFromJson(dynamic raw) => raw is List && raw.length == 2
    ? Offset(jsonDouble(raw[0], 0), jsonDouble(raw[1], 0))
    : Offset.zero;

/// formatCounter writes a number the way a counter writes it.
///
/// A free function rather than a method so that the settings panel can show
/// what a choice looks like without building an element to ask.
String formatCounter(double value, int decimals, CounterSeparator separator) {
  var places = decimals.clamp(0, 8);
  if (separator.isTime) return _asTime(value, places, separator);

  // Rounded once, here, and then taken apart as a string. Working out the
  // whole part and the fraction separately gets 1.999 at two places wrong:
  // the whole part is 1 and the fraction rounds to 00, which writes 1.00 for
  // a number that is two.
  var negative = value < 0;
  var text = value.abs().toStringAsFixed(places);
  var point = text.indexOf(".");
  var whole = point < 0 ? text : text.substring(0, point);
  var rest = point < 0 ? "" : text.substring(point + 1);

  var (group, dot) = switch (separator) {
    CounterSeparator.comma => (",", "."),
    CounterSeparator.dot => (".", ","),
    CounterSeparator.space => (" ", ","),
    _ => ("", "."),
  };

  if (group.isNotEmpty) whole = _grouped(whole, group);
  var out = rest.isEmpty ? whole : "$whole$dot$rest";
  return negative ? "-$out" : out;
}

/// _grouped puts [mark] between every three digits from the right.
String _grouped(String digits, String mark) {
  var out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(mark);
    out.write(digits[i]);
  }
  return out.toString();
}

/// _asTime writes a number of seconds as a clock reads it.
///
/// The minutes and the seconds are always two figures where something comes
/// before them and never padded where nothing does -- 1:57, not 01:57, and
/// 1:02:05 rather than 1:2:5. A clock that loses its leading nought once a
/// minute is a clock that flickers.
String _asTime(double value, int places, CounterSeparator separator) {
  var negative = value < 0;
  var total = value.abs();
  var whole = total.floor();
  var fraction = total - whole;

  var seconds = whole % 60;
  var minutes = (whole ~/ 60);
  var out = StringBuffer();
  if (separator == CounterSeparator.hours) {
    var hours = minutes ~/ 60;
    minutes = minutes % 60;
    out.write("$hours:");
    out.write(minutes.toString().padLeft(2, "0"));
  } else {
    out.write("$minutes");
  }
  out.write(":");
  out.write(seconds.toString().padLeft(2, "0"));
  if (places > 0) {
    var tail = fraction.toStringAsFixed(places);
    // toStringAsFixed can round a fraction up to "1.00"; the whole second it
    // carries has already been counted above, so only the figures after the
    // point are taken.
    out.write(".${tail.substring(2)}");
  }
  return negative ? "-$out" : out.toString();
}
