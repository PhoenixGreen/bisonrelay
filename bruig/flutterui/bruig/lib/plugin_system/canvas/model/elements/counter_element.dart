import 'dart:math' as math;

import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// counter_element.dart is a number that counts: either across the timeline
// (a figure animating up in a video) or, with [CounterElement.keyed] off, in
// real time (a clock, stopwatch, countdown or metronome). One element because
// both are a formatted number with words either side in a box; only where the
// number comes from differs. The number is a value, not text, so it can be
// formatted with separators or as a time.

/// CounterSeparator is how the digits are grouped and punctuated. Grouping
/// and decimal point are one setting because they are one convention
/// (1.234,56 vs 1,234.56), and the time formats are not grouping at all.
enum CounterSeparator {
  none("1234.5", "None"),
  comma("1,234.5", "Thousands in commas"),
  dot("1.234,5", "Thousands in points"),
  space("1 234,5", "Thousands in spaces"),

  /// minutes and hours write the value as a duration in seconds.
  minutes("1:57", "Minutes and seconds"),
  hours("1:57:03", "Hours, minutes and seconds");

  final String label;
  final String description;
  const CounterSeparator(this.label, this.description);

  /// isTime is whether the value is a number of seconds rather than a
  /// quantity.
  bool get isTime => this == minutes || this == hours;

  static CounterSeparator fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => CounterSeparator.none,
      );
}

/// CounterSource is where a live counter's number comes from. A keyed
/// counter (see [CounterElement.keyed]) reads the timeline instead, except
/// for [game], which is always live.
enum CounterSource {
  /// run counts from the start value towards the end at the element's rate
  /// a second: a countdown, stopwatch or metronome depending on the ends and
  /// the rate.
  run("Counts", "From the start value to the end at a rate you set"),

  /// clock is the time of day in seconds since midnight; choosing it sets a
  /// time separator, since plain it is meaningless.
  clock("The time", "The time of day on the reader's own clock"),

  /// page is the number of the page this is drawn on, for a document of
  /// pages (see CanvasDocument.pageNumberAt). Put one on the master canvas
  /// and every page wears it.
  page("The page number",
      "The number of the page it is drawn on, for a document of pages"),

  /// game is one of the numbers a game keeps (coins, lives), or its start
  /// value while the game is not being played. See CounterElement.gameCount
  /// and GameCount.
  game("A game count", "One of the numbers the game keeps: coins, lives");

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
  /// from and to are the two ends of the count, either way round.
  final double from;
  final double to;

  /// decimals is how many figures after the point, and [separator] is how the
  /// rest is punctuated.
  final int decimals;
  final CounterSeparator separator;

  /// before and after are the words either side of the number (a currency,
  /// a unit), kept apart because they do not count.
  final String before;
  final String after;

  /// gap is the space between the number and the words either side, in the
  /// number's ems so it holds when [fit] shrinks the type.
  final double gap;

  /// loose lets the words be placed anywhere in the box instead of on the
  /// number's line, at [beforeAt] and [afterAt]: fractions of the box from
  /// its middle, so -0.5 is the left or top edge and 0.5 the right or bottom.
  final bool loose;
  final Offset beforeAt;
  final Offset afterAt;

  /// numberSpec is the number's type and [affixSpec] the words', usually
  /// smaller.
  final TextSpec numberSpec;
  final TextSpec affixSpec;

  /// numberStyle and wordStyle are the document's named text styles (see
  /// CanvasDocument.textStyles) the number and words are set in, or empty
  /// for their own specs.
  final String numberStyle;
  final String wordStyle;

  /// box is the background, border, radius and padding round the whole thing.
  final BoxSpec box;

  /// fit shrinks the type until the whole count fits the box. The size is
  /// chosen from the widest value the count will reach, not the one showing,
  /// so the figures do not change size as they count.
  final bool fit;

  /// keyed is whether the number is read off the timeline (its count clips,
  /// or a legacy track's keys). Off, the counter runs in real time and the
  /// buttons work.
  final bool keyed;

  /// source, rate and loop are the live counter's settings; rate is in
  /// units a second.
  final CounterSource source;
  final double rate;
  final bool loop;

  /// gameCount is the game count shown, by id, for [CounterSource.game].
  final String gameCount;

  /// mirrored puts a page number on the outside edge of the leaf: on a
  /// left-hand leaf it is drawn mirrored about the page's middle, so both
  /// sides of a spread match and a centred number stays centred. Only read
  /// for a page number on a left-hand leaf; see pageIsLeft in
  /// canvas_pages.dart.
  final bool mirrored;

  /// running is whether a live counter is counting before anything is
  /// pressed: true for a clock, false for a stopwatch.
  final bool running;

  /// buttons are the controls drawn under the number, in this order.
  final List<CounterButton> buttons;

  /// buttonSpec and buttonBox are how those controls are drawn.
  final TextSpec buttonSpec;
  final BoxSpec buttonBox;

  /// looseButtons lets the buttons be placed anywhere in the box instead of
  /// in a row along the bottom, each at [buttonAt]: a fraction of the box
  /// from its middle, like [beforeAt].
  final bool looseButtons;
  final List<Offset> buttonAt;

  /// buttonSize is a loose button's size as a fraction of the box; in the
  /// row, buttons share the width and size to their labels.
  final Size buttonSize;

  /// animation is how the whole element arrives and leaves.
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
    this.numberStyle = "",
    this.wordStyle = "",
    this.box = const BoxSpec(padding: 16),
    this.fit = true,
    this.keyed = true,
    this.source = CounterSource.run,
    this.gameCount = "",
    this.mirrored = false,
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

  /// span is how far the count travels.
  double get span => to - from;

  /// valueAtFraction is the number [t] of the way through the count.
  double valueAtFraction(double t) => from + span * t.clamp(0.0, 1.0);

  /// format writes [value] with this counter's decimals and separator.
  String format(double value) => formatCounter(value, decimals, separator);

  /// textFor is the whole line: words before, the number, words after.
  String textFor(double value) => "$before${format(value)}$after";

  /// placedButton is where loose button [i] sits, as a fraction of the box
  /// from its middle. Unplaced ones are spread down the middle so they do not
  /// stack on one another.
  Offset placedButton(int i) {
    if (i < buttonAt.length) return buttonAt[i];
    var count = buttons.isEmpty ? 1 : buttons.length;
    return Offset(0, 0.3 - (count - 1 - i) * 0.18);
  }

  /// live is whether this counter runs in real time. A page number never
  /// does (it is read off its page); a game count always does, whatever
  /// [keyed] says, since a new counter starts keyed.
  bool get live =>
      source == CounterSource.game || (!keyed && source != CounterSource.page);

  /// isPageNumber is whether this shows the number of its page.
  bool get isPageNumber => source == CounterSource.page;

  @override
  Set<String> get assetIds => {...box.assetIds, ...buttonBox.assetIds};

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
      numberStyle: numberStyle,
      wordStyle: wordStyle,
      box: box,
      fit: fit,
      keyed: keyed,
      source: source,
      gameCount: gameCount,
      // Every move and resize comes through rebase, so every field must too.
      mirrored: mirrored,
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
    String? numberStyle,
    String? wordStyle,
    BoxSpec? box,
    bool? fit,
    bool? keyed,
    CounterSource? source,
    String? gameCount,
    bool? mirrored,
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
          numberStyle: numberStyle ?? this.numberStyle,
          wordStyle: wordStyle ?? this.wordStyle,
          box: box ?? this.box,
          fit: fit ?? this.fit,
          keyed: keyed ?? this.keyed,
          source: source ?? this.source,
          gameCount: gameCount ?? this.gameCount,
          mirrored: mirrored ?? this.mirrored,
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
        if (numberStyle.isNotEmpty) "numberStyle": numberStyle,
        if (wordStyle.isNotEmpty) "wordStyle": wordStyle,
        "box": box.toJson(),
        if (!fit) "noFit": true,
        if (!keyed) "live": true,
        if (source != CounterSource.run) "source": source.name,
        if (gameCount.isNotEmpty) "gameCount": gameCount,
        if (mirrored) "mirrored": true,
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
        separator: CounterSeparator.fromName(jsonStr(json["sep"])),
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
        numberStyle: jsonString(json["numberStyle"], ""),
        wordStyle: jsonString(json["wordStyle"], ""),
        box:
            jsonSpec(json["box"], BoxSpec.fromJson, const BoxSpec(padding: 16)),
        fit: !jsonBool(json["noFit"], false),
        keyed: !jsonBool(json["live"], false),
        source: CounterSource.fromName(jsonStr(json["source"])),
        gameCount:
            json["gameCount"] is String ? json["gameCount"] as String : "",
        mirrored: jsonBool(json["mirrored"], false),
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

Offset _offsetFromJson(dynamic raw) => raw is List && raw.length == 2
    ? Offset(jsonDouble(raw[0], 0), jsonDouble(raw[1], 0))
    : Offset.zero;

/// formatCounter writes a number the way a counter writes it. A free
/// function so the settings panel can preview a choice without an element.
String formatCounter(double value, int decimals, CounterSeparator separator) {
  var places = decimals.clamp(0, 8);
  if (separator.isTime) return _asTime(value, places, separator);

  // Rounded once, then taken apart as a string: rounding the whole part and
  // fraction separately writes 1.999 at two places as 1.00.
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

/// _asTime writes a number of seconds as a clock reads it: a field is
/// padded to two figures only when something comes before it (1:57, 1:02:05).
String _asTime(double value, int places, CounterSeparator separator) {
  var negative = value < 0;
  // Whole seconds as a clock shows them; with figures after the point,
  // rounded to those first, so 59.999 to two places is 1:00.00, not 0:59.00.
  var scale = math.pow(10, places).toInt();
  var ticks =
      places > 0 ? (value.abs() * scale).round() : value.abs().floor() * scale;
  var whole = ticks ~/ scale;
  var fraction = ticks % scale;

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
  if (places > 0) out.write(".${fraction.toString().padLeft(places, "0")}");
  return negative ? "-$out" : out.toString();
}

/// stackedWithMaster is a page's elements with the master's under them,
/// except its page numbers, which go over so a full-page picture cannot hide
/// them. Both the renderer and the EPUB layers use this order. With [over],
/// all of the master goes over the page (a game's HUD).
List<CanvasElement> stackedWithMaster(
        List<CanvasElement> master, List<CanvasElement> page,
        {bool over = false}) =>
    over
        ? [...page, ...master]
        : [
            for (var e in master)
              if (!(e is CounterElement && e.isPageNumber)) e,
            ...page,
            for (var e in master)
              if (e is CounterElement && e.isPageNumber) e,
          ];
