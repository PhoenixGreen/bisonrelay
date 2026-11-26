import 'dart:math' as math;

import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// counter_element.dart is a number in a box with words either side, which is
// one of five things (CounterMode): a count set by keyframes on the timeline
// (a figure animating up in a video), a count that runs in real time when
// started (a stopwatch or countdown), the time of day, one of a game's
// counts, or the number of the page it is drawn on. Each is the same
// formatted number; what differs is where the number comes from and which
// fields mean anything, which CounterElement.mode answers. It is a value,
// not text, so it formats as a time too.

/// CounterSeparator is how digits are grouped and pointed, one convention
/// (1.234,56 vs 1,234.56); the time formats are not grouping at all.
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

  /// isTime is whether the value is seconds rather than a quantity.
  bool get isTime => this == minutes || this == hours;

  static CounterSeparator fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => CounterSeparator.none,
      );
}

/// CounterSource is where a counter not counted by keyframes takes its
/// number from. A page number and a game's count take theirs from the page
/// and the game whatever [CounterElement.keyed] says (see CounterMode).
enum CounterSource {
  /// run counts from the start value towards the end at the element's rate
  /// a second: a countdown or stopwatch by the ends and rate.
  run("Counts", "From the start value to the end at a rate you set"),

  /// clock is the time of day in seconds since midnight; choosing it sets a
  /// time separator, since plain it means nothing.
  clock("The time", "The time of day on the reader's own clock"),

  /// page is the number of the page this is drawn on (see
  /// CanvasDocument.pageNumberAt): on the master canvas, every page wears it.
  page("The page number",
      "The number of the page it is drawn on, for a document of pages"),

  /// game is one of the numbers a game keeps (coins, lives), or its start
  /// value while the game is not played. See CounterElement.gameCount.
  game("A game count", "One of the numbers the game keeps: coins, lives");

  final String label;
  final String description;
  const CounterSource(this.label, this.description);

  static CounterSource fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => CounterSource.run);
}

/// CounterButton is one of the controls a run can offer (see
/// CounterMode.buttonsAct).
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

/// CounterPiece is a piece of a counter placed in its box that can be taken
/// on its own: its words before or after the number where they are placed
/// freely, or one of its buttons.
sealed class CounterPiece {
  const CounterPiece();
}

/// CounterWords is the words before the number, or with [after] after it.
final class CounterWords extends CounterPiece {
  final bool after;
  const CounterWords({required this.after});

  @override
  bool operator ==(Object other) =>
      other is CounterWords && other.after == after;

  @override
  int get hashCode => after.hashCode;
}

/// CounterButtonPiece is the counter's button [index], in its buttons'
/// order.
final class CounterButtonPiece extends CounterPiece {
  final int index;
  const CounterButtonPiece(this.index);

  @override
  bool operator ==(Object other) =>
      other is CounterButtonPiece && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// CounterMode is which of its five things a counter is. It is not saved:
/// [CounterElement.mode] answers it from the fields that are, so a file
/// reads and writes as it always has. What reads a counter asks its mode
/// and switches over it with no default, so a sixth mode is a case here
/// and the compiler names every reader that must say what it does.
///
/// Which fields mean anything in which mode ("all" is every mode):
///
/// | Field                        | keyed | run | clock | game | page |
/// |------------------------------|-------|-----|-------|------|------|
/// | from, to                     | ends  | ends| fit   | fit  | fit  |
/// | rate, loop                   |       | yes |       |      |      |
/// | running                      |       | yes |       |      |      |
/// | gameCount                    |       |     |       | yes  |      |
/// | mirrored                     |       |     |       |      | yes  |
/// | buttons and their look/place |       | yes |       |      |      |
/// | the count keys on its track  | yes   |     |       |      |      |
///
/// Everything else (how the number is written, the words, the type, the
/// box, fit, the arrival) means the same in all five. "fit" is From and To
/// read only to size the type (counterFitScale measures both ends); "ends"
/// is the two ends of the count, which a game's count also falls back to
/// when its game count is gone.
enum CounterMode {
  /// keyed reads the number off the count keys on its track.
  keyed("Keyframes"),

  /// run counts from From to To at its rate once started, by its buttons
  /// or by starting running.
  run("Counts"),

  /// clock shows the reader's time of day.
  clock("The time"),

  /// game shows one of the game's counts (CounterElement.gameCount).
  game("A game count"),

  /// page shows the number of the page it is drawn on.
  page("The page number");

  final String label;
  const CounterMode(this.label);

  /// buttonsAct is whether its Start, Reset and Set buttons do anything,
  /// and so whether they are offered, drawn and pressed: only a run has a
  /// count of its own for them to start, reset and set.
  bool get buttonsAct => switch (this) {
        CounterMode.run => true,
        CounterMode.keyed ||
        CounterMode.clock ||
        CounterMode.game ||
        CounterMode.page =>
          false,
      };

  /// countsEnds is whether From and To are the ends of the count it shows
  /// (see the table above), and so whether they are offered.
  bool get countsEnds => switch (this) {
        CounterMode.keyed || CounterMode.run => true,
        CounterMode.clock || CounterMode.game || CounterMode.page => false,
      };
}

class CounterElement extends CanvasElement {
  /// from and to are the two ends of the count, either way round.
  final double from;
  final double to;

  /// decimals is figures after the point; [separator] the punctuation.
  final int decimals;
  final CounterSeparator separator;

  /// before and after are the words either side of the number (a currency,
  /// a unit), kept apart because they do not count.
  final String before;
  final String after;

  /// gap is the space between the number and its words, in the number's ems
  /// so it holds when [fit] shrinks the type.
  final double gap;

  /// loose lets the words go anywhere in the box instead of on the number's
  /// line, at [beforeAt] and [afterAt]: fractions of the box from its middle
  /// (-0.5 the left or top edge, 0.5 the right or bottom).
  final bool loose;
  final Offset beforeAt;
  final Offset afterAt;

  /// numberSpec is the number's type, [affixSpec] the (smaller) words'.
  final TextSpec numberSpec;
  final TextSpec affixSpec;

  /// numberStyle and wordStyle are named document text styles (see
  /// CanvasDocument.textStyles), or empty for their own specs.
  final String numberStyle;
  final String wordStyle;

  final BoxSpec box;

  /// fit shrinks the type to fit the widest value the count reaches, so the
  /// figures keep their size as they count.
  final bool fit;

  /// keyed reads the number off the count keys on its track; off, it takes
  /// it from its [source]. Saved as "live", the other way round, for a
  /// counter that is not keyed. A page number and a game's count are what
  /// their source says whichever it is (see [mode]).
  final bool keyed;

  /// source is where the number comes from when it is not keyed; rate
  /// (units a second) and loop are a run's.
  final CounterSource source;
  final double rate;
  final bool loop;

  /// gameCount is the game count shown, by id, for [CounterSource.game].
  final String gameCount;

  /// mirrored puts a page number on the leaf's outside edge: on a left-hand
  /// leaf it is mirrored about the page's middle, so a spread's sides match
  /// and a centred number stays centred. See pageIsLeft in canvas_pages.dart.
  final bool mirrored;

  /// running is whether a run starts counting as the canvas opens, before
  /// anything is pressed: false for a stopwatch. Whether one is counting
  /// now is the controller's (counterRunning).
  final bool running;

  /// buttons are the controls drawn under the number, in this order.
  final List<CounterButton> buttons;

  final TextSpec buttonSpec;
  final BoxSpec buttonBox;

  /// looseButtons lets the buttons go anywhere in the box instead of in a
  /// row along the bottom, each at [buttonAt], placed like [beforeAt].
  final bool looseButtons;
  final List<Offset> buttonAt;

  /// buttonSize is a loose button's size as a fraction of the box; in the
  /// row, buttons share the width and size to their labels.
  final Size buttonSize;

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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = CounterElement(ElementBase(id: ""));

  /// maxGap and maxRate are the most its words' gap (in ems) and its rate
  /// (a second) are set to, and read with; minButtonSize and maxButtonSize
  /// bound a loose button's share of the box.
  static const maxGap = 8.0, maxRate = 100000.0;
  static const minButtonSize = 0.05, maxButtonSize = 1.0;

  /// maxEnd is the furthest from nought the panel sets From, To and a
  /// count key; maxDecimals the most figures after the point it writes.
  static const maxEnd = 1000000000.0;
  static const maxDecimals = 8;

  @override
  ElementKind get kind => ElementKind.counter;

  double get span => to - from;

  /// valueAtFraction is the number [t] of the way through the count.
  double valueAtFraction(double t) => from + span * t.clamp(0.0, 1.0);

  String format(double value) => formatCounter(value, decimals, separator);

  /// textFor is the whole line: words before, the number, words after.
  String textFor(double value) => "$before${format(value)}$after";

  /// placedButton is where loose button [i] sits, as a fraction of the box
  /// from its middle; unplaced ones spread down the middle, not stacked.
  Offset placedButton(int i) {
    if (i < buttonAt.length) return buttonAt[i];
    var count = buttons.isEmpty ? 1 : buttons.length;
    return Offset(0, 0.3 - (count - 1 - i) * 0.18);
  }

  /// mode is which of its five things this is (see CounterMode). A page
  /// number and a game's count are so whatever [keyed] says: a new counter
  /// starts keyed, and choosing either does not turn keying off.
  CounterMode get mode => switch (source) {
        CounterSource.page => CounterMode.page,
        CounterSource.game => CounterMode.game,
        _ when keyed => CounterMode.keyed,
        CounterSource.run => CounterMode.run,
        CounterSource.clock => CounterMode.clock,
      };

  /// withPieceAt is this with [piece] placed at [at], a fraction of the box
  /// from its middle (see [beforeAt]).
  CounterElement withPieceAt(CounterPiece piece, Offset at) => switch (piece) {
        CounterWords(after: false) => copyWith(beforeAt: at),
        CounterWords(after: true) => copyWith(afterAt: at),
        CounterButtonPiece(:var index) => copyWith(buttonAt: [
            for (var i = 0; i < buttons.length; i++)
              i == index ? at : placedButton(i),
          ]),
      };

  /// mirroredOn is whether it is drawn mirrored across the page: a page
  /// number set to mirror, on a left-hand page ([leftHand]).
  bool mirroredOn({required bool leftHand}) =>
      leftHand && mirrored && mode == CounterMode.page;

  /// drawnBox is where its box [box] is drawn on a page [page] wide: across
  /// the page's middle where it is [mirroredOn] it, so a spread's sides
  /// match and a centred number stays centred. The renderer draws it there,
  /// and the stage shows and presses it there.
  Rect drawnBox(Rect box, {required Rect page, required bool leftHand}) =>
      mirroredOn(leftHand: leftHand)
          ? Rect.fromLTWH(page.left + page.right - box.right, box.top,
              box.width, box.height)
          : box;

  /// countKeys are the keys on its track that hold a count, in frame order.
  List<Keyframe> get countKeys => [
        for (var k in track?.keys ?? const <Keyframe>[])
          if (k.values.containsKey(KeyframeChannel.count)) k,
      ];

  /// keyedEnds is the first and last number its count keys hold, or null
  /// for none: what a keyed counter counts between, which From and To are
  /// only while the keys follow them (see withEnds).
  (double, double)? get keyedEnds {
    var keys = countKeys;
    if (keys.isEmpty) return null;
    return (
      keys.first.values[KeyframeChannel.count]!,
      keys.last.values[KeyframeChannel.count]!
    );
  }

  /// withEnds is this with From set to [from] and To to [to], and its first
  /// count key moved with From and its last with To while each still holds
  /// the old end: a new counter's count is laid out from From to To, so
  /// setting To 500 counts to 500. A key changed by hand to some other
  /// number is the person's own, and stays as it is. With one count key
  /// it is the first.
  CounterElement withEnds({double? from, double? to}) {
    var next = copyWith(from: from, to: to);
    var keys = countKeys;
    if (keys.isEmpty) return next;
    var track = this.track!;
    Keyframe moved(Keyframe k, double was, double? now) =>
        now != null && k.values[KeyframeChannel.count] == was
            ? k.withValue(KeyframeChannel.count, now)
            : k;
    var first = moved(keys.first, this.from, from);
    track = track.withKey(first);
    if (keys.length > 1) track = track.withKey(moved(keys.last, this.to, to));
    return next.withBase(track: track) as CounterElement;
  }

  /// isPageNumber is whether this shows the number of its page.
  bool get isPageNumber => mode == CounterMode.page;

  /// shownValue is the number it shows: a page number the page's [page]
  /// (none on a cover), a keyed one what its [pose] holds, and a run, a
  /// clock or a game's count what [live] says (the controller's
  /// counterValue), or its start where nothing runs it (an export). The
  /// renderer, the stage and the panel all ask this.
  double shownValue({
    required int? page,
    required Keyframe pose,
    double Function(CounterElement)? live,
  }) =>
      switch (mode) {
        CounterMode.page => (page ?? 0).toDouble(),
        CounterMode.keyed => pose.values[KeyframeChannel.count] ?? from,
        CounterMode.run ||
        CounterMode.clock ||
        CounterMode.game =>
          live?.call(this) ?? from,
      };

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

  /// mapOwnColours maps the number's and words' type, the box, the buttons'
  /// type and box (hidden with no buttons, as they are saved) and the
  /// arrival.
  @override
  CounterElement mapOwnColours(ColourMap f) {
    var g = f.shownOnlyIf(buttons.isNotEmpty);
    var p = ColourPass(f);
    var numberSpec = p.part(this.numberSpec, (s) => s.mapColours(f));
    var affixSpec = p.part(this.affixSpec, (s) => s.mapColours(f));
    var box = p.part(this.box, (b) => b.mapColours(f));
    var buttonSpec = p.part(this.buttonSpec, (s) => s.mapColours(g));
    var buttonBox = p.part(this.buttonBox, (b) => b.mapColours(g));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      numberSpec: numberSpec,
      affixSpec: affixSpec,
      box: box,
      buttonSpec: buttonSpec,
      buttonBox: buttonBox,
      animation: animation,
    );
  }

  @override
  Map<String, dynamic> props() => {
        "from": from,
        "to": to,
        if (decimals != _defaults.decimals) "decimals": decimals,
        if (separator != _defaults.separator) "sep": separator.name,
        if (before.isNotEmpty) "before": before,
        if (after.isNotEmpty) "after": after,
        if (gap != _defaults.gap) "gap": gap,
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
        if (source != _defaults.source) "source": source.name,
        if (gameCount.isNotEmpty) "gameCount": gameCount,
        if (mirrored) "mirrored": true,
        if (rate != _defaults.rate) "rate": rate,
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
    var size = json["buttonSize"];
    double side(Object? v, double fallback) =>
        jsonDouble(v, fallback).clamp(minButtonSize, maxButtonSize);
    return CounterElement(b,
        from: jsonDouble(json["from"], _defaults.from),
        to: jsonDouble(json["to"], _defaults.to),
        decimals:
            jsonInt(json["decimals"], _defaults.decimals).clamp(0, maxDecimals),
        separator: CounterSeparator.fromName(jsonStr(json["sep"])),
        before: jsonString(json["before"], _defaults.before),
        after: jsonString(json["after"], _defaults.after),
        gap: jsonDouble(json["gap"], _defaults.gap).clamp(0.0, maxGap),
        loose: jsonBool(json["loose"], false),
        beforeAt: _offsetFromJson(json["beforeAt"]),
        afterAt: _offsetFromJson(json["afterAt"]),
        numberSpec: jsonSpec(
            json["numberSpec"], TextSpec.fromJson, _defaults.numberSpec),
        affixSpec:
            jsonSpec(json["affixSpec"], TextSpec.fromJson, _defaults.affixSpec),
        numberStyle: jsonString(json["numberStyle"], _defaults.numberStyle),
        wordStyle: jsonString(json["wordStyle"], _defaults.wordStyle),
        box: jsonSpec(json["box"], BoxSpec.fromJson, _defaults.box),
        fit: !jsonBool(json["noFit"], false),
        keyed: !jsonBool(json["live"], false),
        source: CounterSource.fromName(jsonStr(json["source"])),
        gameCount: jsonId(json["gameCount"], _defaults.gameCount),
        mirrored: jsonBool(json["mirrored"], false),
        rate: jsonDouble(json["rate"], _defaults.rate).clamp(0.0, maxRate),
        loop: jsonBool(json["loop"], false),
        running: jsonBool(json["running"], false),
        // Each kind once, in the order first given: a button twice is the
        // same button drawn twice.
        buttons: {
          ...jsonList(
              json["buttons"], (n) => CounterButton.fromName(jsonStr(n)))
        }.toList(),
        buttonSpec: jsonSpec(
            json["buttonSpec"], TextSpec.fromJson, _defaults.buttonSpec),
        looseButtons: jsonBool(json["looseButtons"], false),
        buttonAt: jsonList(json["buttonAt"], _offsetFromJson,
            most: CounterButton.values.length),
        buttonSize: size is List && size.length == 2
            ? Size(side(size[0], _defaults.buttonSize.width),
                side(size[1], _defaults.buttonSize.height))
            : _defaults.buttonSize,
        buttonBox:
            jsonSpec(json["buttonBox"], BoxSpec.fromJson, _defaults.buttonBox),
        animation: jsonSpec(
            json["animation"], ElementAnimation.fromJson, _defaults.animation));
  }
}

/// _offsetFromJson reads a loose piece's place: a share of the box from its
/// middle, no further out than the panel and the stage can put it.
Offset _offsetFromJson(Object? raw) => raw is List && raw.length == 2
    ? Offset(jsonDouble(raw[0], 0).clamp(-1.0, 1.0),
        jsonDouble(raw[1], 0).clamp(-1.0, 1.0))
    : Offset.zero;

/// formatCounter writes a number as a counter writes it, at [decimals]
/// figures after the point and grouped by [separator].
String formatCounter(double value, int decimals, CounterSeparator separator) {
  var places = decimals.clamp(0, CounterElement.maxDecimals);
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
/// padded to two figures only after another (1:57, 1:02:05).
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
/// except its page numbers, which go over so a full-page picture cannot
/// hide them; the renderer and the EPUB layers share this order. With
/// [over], all of the master goes over the page (a game's HUD).
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
