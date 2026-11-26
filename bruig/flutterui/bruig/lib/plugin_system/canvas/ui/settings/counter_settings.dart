import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart'
    show boxSummary;
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/type_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/box_group.dart';
import 'package:flutter/material.dart';

// counter_settings.dart is a counter's panel (see element_panel.dart): quick
// strip, Content (the number and its words; where the number comes from),
// Look (the number's and the words' type, the box) and More (a run's
// buttons). What it offers follows the counter's mode (CounterMode): a
// field a mode does not read is not offered, and the field stays as saved.
// A control in the quick strip and its twin in a section are built by one
// function (_end, _written), so the two cannot part; every range is the
// model's.

/// _Counter is a counter in its panel and how to write it: what each piece
/// of the panel is handed.
class _Counter {
  final CanvasController controller;
  final CounterElement e;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  const _Counter(this.controller, this.e, this.write, this.begin, this.commit);

  /// now writes [next] as one step: a choice made in one press.
  void now(CounterElement next) {
    begin();
    write(next);
    commit();
  }

  /// live writes [next] as a drag or a typed number goes; [commit] ends it.
  void live(CounterElement next) {
    begin();
    write(next);
  }

  /// shown is the number it shows on the frame in view.
  double get shown => e.shownValue(
      page: controller.document.pageNumber,
      pose: e.poseAt(controller.frame),
      live: controller.counterValue);
}

/// counterPanel is [e]'s panel (see element_panel.dart).
Widget counterPanel(
  BuildContext context,
  CanvasController controller,
  CounterElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  var c = _Counter(controller, e, write, begin, commit);
  return elementPanel(context, controller, e, write, begin, commit,
      quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
        if (e.mode.countsEnds) ...[
          panelRow([
            cell(_end(c, to: false, quick: true), flex: 1, min: 110),
            cell(_end(c, to: true, quick: true), flex: 1, min: 110),
          ]),
          const SizedBox(height: 8),
        ],
        panelRow([
          cell(
              CanvasColorButton(
                key: const ValueKey("quickCounterColour"),
                label: "Colour",
                color: e.numberSpec.color,
                onChanged: (v) => c.now(
                    e.copyWith(numberSpec: e.numberSpec.copyWith(color: v))),
              ),
              width: 104),
          cell(_written(c, quick: true), flex: 2, min: 110),
        ]),
      ]),
      bits: _bits(context, c));
}

/// _bits are the counter's sections' pieces, each shown where its mode
/// reads it.
List<PanelBit> _bits(BuildContext context, _Counter c) {
  var e = c.e;
  return [
    _numberBit(c),
    PanelBit(PanelSection.content,
        summary: _sourceSaid(c), children: [_countSection(c)]),
    PanelBit(PanelSection.look,
        summary: "Number ${e.numberSpec.fontSize.round()} · "
            "words ${e.affixSpec.fontSize.round()}",
        children: [_numberType(context, c), _wordsType(context, c)]),
    PanelBit(PanelSection.look,
        summary: [boxSummary(e.box), if (e.fit) "shrinks to fit"].join(" · "),
        children: _boxAndFit(context, c)),
    // A counter saved with buttons in another mode keeps them, unshown,
    // until it is a run again.
    if (e.mode.buttonsAct)
      PanelBit(PanelSection.more,
          summary: e.buttons.isEmpty
              ? "None"
              : e.buttons.map((b) => b.label).join(" · "),
          children: [_buttonsSection(c)]),
    // How it comes in, loops and goes is the Chain's Motion view.
  ];
}

/// _numberBit is the number: its ends where the mode counts between
/// them, how it is written, and the words either side.
PanelBit _numberBit(_Counter c) {
  var e = c.e;
  var words = e.before.isNotEmpty || e.after.isNotEmpty;
  return PanelBit(PanelSection.content,
      summary: [_countSaid(c), if (words) e.textFor(c.shown)].join(" · "),
      children: [
        CanvasControlGroup(
            label: "Counts",
            hideCaption: true,
            rule: false,
            children: [
              if (e.mode.countsEnds) ...[
                _end(c, to: false, quick: false),
                _end(c, to: true, quick: false),
              ],
              CanvasNumberField(
                key: const ValueKey("counterDecimals"),
                label: "Decimals",
                value: e.decimals.toDouble(),
                min: 0,
                max: CounterElement.maxDecimals.toDouble(),
                decimals: 0,
                width: 54,
                onChanged: (v) => c.live(e.copyWith(decimals: v.round())),
                onCommit: c.commit,
              ),
              // Grouping and point are one choice: 1.234,56 is a convention,
              // not a different point, and the time formats are no grouping.
              _written(c, quick: false),
              if (_endsHint(c) case var hint?) CanvasHint(hint),
            ]),
        CanvasControlGroup(label: "Words", rule: false, children: [
          CanvasTextField(
            key: const ValueKey("counterBefore"),
            label: "Before",
            value: e.before,
            width: 96,
            onChanged: (v) => c.write(e.copyWith(before: v)),
            onCommit: c.commit,
          ),
          CanvasTextField(
            key: const ValueKey("counterAfter"),
            label: "After",
            value: e.after,
            width: 96,
            onChanged: (v) => c.write(e.copyWith(after: v)),
            onCommit: c.commit,
          ),
          CanvasHint("Now: ${e.textFor(c.shown)}"),
        ]),
      ]);
}

/// _end is From, or with [to] To: in the quick strip ([quick]) a stepper
/// as wide as its cell, elsewhere a number in its group. Set through
/// withEnds, so a keyed count's end keys follow while they hold the old
/// ends.
Widget _end(_Counter c, {required bool to, required bool quick}) {
  var e = c.e;
  var key = ValueKey(quick
      ? (to ? "quickCounterTo" : "quickCounterFrom")
      : (to ? "counterTo" : "counterFrom"));
  var label = to ? "To" : "From";
  var value = to ? e.to : e.from;
  void set(double v) => c.live(to ? e.withEnds(to: v) : e.withEnds(from: v));
  return quick
      ? CanvasStepper(
          key: key,
          label: label,
          value: value,
          min: -CounterElement.maxEnd,
          max: CounterElement.maxEnd,
          decimals: e.decimals,
          step: 1,
          fill: true,
          onChanged: set,
          onCommit: c.commit,
        )
      : CanvasNumberField(
          key: key,
          label: label,
          value: value,
          min: -CounterElement.maxEnd,
          max: CounterElement.maxEnd,
          decimals: e.decimals,
          width: 84,
          onChanged: set,
          onCommit: c.commit,
        );
}

/// _written is how the number is written: in the quick strip ([quick])
/// as wide as its cell, elsewhere in its group.
Widget _written(_Counter c, {required bool quick}) =>
    CanvasDropdown<CounterSeparator>(
      key: ValueKey(quick ? "quickCounterWritten" : "counterSeparator"),
      label: "Written",
      value: c.e.separator,
      // In the quick strip it fills its cell, from a dropdown's own least.
      width: quick ? 130 : 132,
      options: [
        for (var s in CounterSeparator.values)
          (s, s == CounterSeparator.none ? "Plain" : s.label)
      ],
      onChanged: (v) => c.now(c.e.copyWith(separator: v)),
    );

/// _countSaid is the number's heading: what it counts, or shows. A clock
/// is said by how it is written, not the time, which a heading kept for a
/// while would leave behind.
String _countSaid(_Counter c) {
  var e = c.e;
  return switch (e.mode) {
    CounterMode.keyed => switch (e.keyedEnds) {
        (var a, var b) => "${e.format(a)} to ${e.format(b)}",
        null => e.format(e.from),
      },
    CounterMode.run => "${e.format(e.from)} to ${e.format(e.to)}",
    CounterMode.clock => e.separator.description,
    CounterMode.game || CounterMode.page => e.format(c.shown),
  };
}

/// _endsHint is what From and To do, as true for the mode and the keys as
/// they are; null where they are not offered.
String? _endsHint(_Counter c) {
  var e = c.e;
  var seconds = e.separator.isTime ? ", reading the value as seconds" : "";
  String counts(double a, double b) =>
      "Counts ${e.format(a)} to ${e.format(b)}$seconds.";
  return switch (e.mode) {
    CounterMode.run => counts(e.from, e.to),
    CounterMode.keyed => switch (e.keyedEnds) {
        null => "It has no keyframes yet, so it shows "
            "${e.format(e.from)}. Pin From and To under Count to make "
            "it count.",
        (var a, var b) when a == e.from && b == e.to => counts(a, b),
        (var a, var b) => "Its keyframes count ${e.format(a)} to "
            "${e.format(b)}$seconds. From and To are what the pin "
            "buttons under Count put on a keyframe, and they move the "
            "first and last keyframes only while those still hold them.",
      },
    CounterMode.clock || CounterMode.game || CounterMode.page => null,
  };
}

/// _sourceSaid is the Count section's heading: where the number comes
/// from.
String _sourceSaid(_Counter c) {
  var e = c.e;
  return switch (e.mode) {
    CounterMode.keyed => "Keyframes on the timeline",
    CounterMode.run => "Counts ${shortNumber(e.rate)} a second",
    CounterMode.clock => "The time",
    CounterMode.game => [
        "A game count",
        for (var g in c.controller.document.counts)
          if (g.id == e.gameCount) g.name,
      ].join(": "),
    CounterMode.page => "The page number",
  };
}

/// _countSection is where the number comes from, and what that one mode
/// is set by.
Widget _countSection(_Counter c) {
  var e = c.e;
  var document = c.controller.document;
  return CanvasExpander(
    label: "Count",
    remember: "counterCount",
    // In its own section, which is its heading.
    flat: true,
    trailing: e.mode.label,
    children: [
      CanvasControlGroup(label: "Count", hideCaption: true, children: [
        // The page number is set here alone: where the number comes from.
        if (document.isPages || e.mode == CounterMode.page) _pageNumber(c),
        ...switch (e.mode) {
          CounterMode.page => _pageControls(c),
          CounterMode.keyed => [_keyedSwitch(c), ..._keyedControls(c)],
          CounterMode.run => [
              _keyedSwitch(c),
              _sourcePick(c),
              ..._runControls(c),
            ],
          CounterMode.clock => [
              _keyedSwitch(c),
              _sourcePick(c),
              const CanvasHint(
                  "The reader's own clock, in seconds since midnight -- so "
                  "the Minutes or Hours way of writing it is the one that "
                  "makes a clock of it."),
            ],
          CounterMode.game => [
              _keyedSwitch(c),
              _sourcePick(c),
              _gameCountPick(c),
              const CanvasHint(
                  "Where the game has got this count to while it is played "
                  "-- coins taken, lives left -- and where it starts while "
                  "it is not. The counts are in the Game panel."),
            ],
        },
      ]),
    ],
  );
}

/// _keyedSwitch reads the number off the timeline, or, off, from where
/// Shows says. A game's count or a page number is turned into a keyed
/// count by it: theirs is the number whatever keying says.
Widget _keyedSwitch(_Counter c) {
  var e = c.e;
  return CanvasToggle(
    key: const ValueKey("counterKeyed"),
    label: "Keyframes",
    value: e.mode == CounterMode.keyed,
    onChanged: (v) => c.now(e.copyWith(
        keyed: v,
        source: v &&
                (e.source == CounterSource.game ||
                    e.source == CounterSource.page)
            ? CounterSource.run
            : null)),
  );
}

/// _sourcePick is where a counter not keyed takes its number from. The
/// page number is its own switch (_pageNumber).
Widget _sourcePick(_Counter c) {
  var e = c.e;
  var document = c.controller.document;
  return CanvasDropdown<CounterSource>(
    key: const ValueKey("counterSource"),
    label: "Shows",
    value: e.source,
    width: 128,
    options: [
      for (var s in CounterSource.values)
        if (s != CounterSource.page &&
            // A game count only in a game, or where it already is one.
            (s != CounterSource.game ||
                document.game ||
                e.source == CounterSource.game))
          (s, s.label),
    ],
    onChanged: (v) => c.now(e.copyWith(
        keyed: false,
        source: v,
        gameCount: v == CounterSource.game &&
                e.gameCount.isEmpty &&
                document.counts.isNotEmpty
            ? document.counts.first.id
            : null,
        // A clock written plainly is seconds since midnight, which nobody
        // wants to read.
        separator: v == CounterSource.clock && !e.separator.isTime
            ? CounterSeparator.hours
            : e.separator)),
  );
}

/// _gameCountPick is which of the game's counts it shows.
Widget _gameCountPick(_Counter c) {
  var e = c.e;
  var counts = c.controller.document.counts;
  var known = counts.any((g) => g.id == e.gameCount);
  return CanvasDropdown<String>(
    key: const ValueKey("counterGameCount"),
    label: "Count",
    value: known ? e.gameCount : "",
    width: 128,
    options: [
      if (!known) ("", "—"),
      for (var g in counts) (g.id, g.name),
    ],
    onChanged: (id) => c.now(e.copyWith(gameCount: id)),
  );
}

/// _runControls are a run's: how fast, whether it goes round again, and
/// whether it is going as the canvas opens.
List<Widget> _runControls(_Counter c) {
  var e = c.e;
  return [
    CanvasNumberField(
      key: const ValueKey("counterRate"),
      label: "Per second",
      value: e.rate,
      min: 0,
      max: CounterElement.maxRate,
      decimals: 2,
      width: 72,
      onChanged: (v) => c.live(e.copyWith(rate: v)),
      onCommit: c.commit,
    ),
    CanvasToggle(
      key: const ValueKey("counterLoop"),
      label: "Loop",
      value: e.loop,
      onChanged: (v) => c.now(e.copyWith(loop: v)),
    ),
    CanvasToggle(
      key: const ValueKey("counterRunning"),
      label: "Start running",
      value: e.running,
      onChanged: (v) => c.now(e.copyWith(running: v)),
    ),
    CanvasHint("Counts from ${e.format(e.from)} to ${e.format(e.to)} at "
        "${e.rate} a second, which is "
        "${(e.span / (e.rate <= 0 ? 1 : e.rate)).abs().round()} seconds end "
        "to end. Turn Loop on and it starts again from the beginning each "
        "time it gets to the end."),
  ];
}

/// _pageNumber makes a counter the number of the page it is drawn on.
Widget _pageNumber(_Counter c) {
  var e = c.e;
  return CanvasToggle(
    key: const ValueKey("counterIsPageNumber"),
    label: "Page number",
    value: e.mode == CounterMode.page,
    onChanged: (v) =>
        c.now(e.copyWith(source: v ? CounterSource.page : CounterSource.run)),
  );
}

/// _pageControls are a page number's: which edge it keeps to on a
/// left-hand page.
List<Widget> _pageControls(_Counter c) {
  var e = c.e;
  return [
    // For a page number on the leaf's outside. See CounterElement.mirrored.
    CanvasToggle(
      key: const ValueKey("counterMirrored"),
      label: "Mirror on left pages",
      value: e.mirrored,
      onChanged: (v) => c.now(e.copyWith(mirrored: v)),
    ),
    const CanvasHint(
        "The number of the page it is drawn on. On the master canvas it "
        "gives every page its own number, and shows the first number the "
        "document prints so that there is something there to place. "
        "Covers are not numbered, and where the numbering starts is in the "
        "canvas settings. Mirrored, it moves to the matching place on the "
        "other edge for a left-hand page, so the number sits on the "
        "outside of the leaf on both sides of a spread — something already "
        "centred stays where it is, because the mirror of the middle is the "
        "middle. You place it here as a right-hand page; open a left-hand "
        "one to see it mirrored."),
  ];
}

/// _keyedControls are a keyed count's: its ends and points pinned at the
/// playhead, and how the number travels from each.
List<Widget> _keyedControls(_Counter c) {
  var e = c.e;
  var controller = c.controller;
  var frames = controller.document.frames;
  var at = controller.frame;
  var value = controller.valueAt(e, KeyframeChannel.count, e.from);
  void pin(double v) =>
      controller.setValueKey(e, KeyframeChannel.count, v, seed: false);
  var keyHere = e.track?.keyAt(at);
  return [
    // The two ends, pinned at the playhead: the frame meant is the one in
    // view; moving it later is a timeline drag.
    CanvasIconButton(
      key: const ValueKey("counterPinFrom"),
      icon: Icons.first_page,
      tooltip: "Start the count here, at ${e.format(e.from)}",
      onPressed: frames <= 1 ? null : () => pin(e.from),
    ),
    CanvasIconButton(
      key: const ValueKey("counterPinTo"),
      icon: Icons.last_page,
      tooltip: "Finish the count here, at ${e.format(e.to)}",
      onPressed: frames <= 1 ? null : () => pin(e.to),
    ),
    // A middle point of any value: a 0-to-100 count can pass 140 and come
    // back, so the channel holds the number, not a fraction.
    CanvasIconButton(
      key: const ValueKey("counterAddPoint"),
      icon: Icons.add_location_alt_outlined,
      tooltip: "Add a point here, at ${e.format(value)}",
      onPressed: frames <= 1 ? null : () => pin(value),
    ),
    CanvasNumberField(
      key: const ValueKey("counterPointValue"),
      label: "Value here",
      value: value,
      min: -CounterElement.maxEnd,
      max: CounterElement.maxEnd,
      decimals: e.decimals,
      width: 88,
      onChanged: (v) {
        c.begin();
        pin(v);
      },
      onCommit: c.commit,
    ),
    // How the number reaches the next key: the key's own easing, as the
    // timeline's panel shows it, not a counter-only kind.
    if (keyHere != null) ...[
      CanvasDropdown<KeyframeEasing>(
        key: const ValueKey("counterEasing"),
        label: "Easing",
        value: keyHere.easing,
        width: 132,
        options: [
          for (var easing in KeyframeEasing.values)
            (
              easing,
              // In the counter's words: on a number, Hold leaves it until
              // the next key.
              easing == KeyframeEasing.hold
                  ? "Hold (stays the same)"
                  : easing.label
            ),
        ],
        onChanged: (v) {
          c.begin();
          controller.setKeyframe(e.id, keyHere.copyWith(easing: v));
          c.commit();
        },
      ),
      // One easing for every count point, so no hop slides while the rest
      // step; only points carrying a number, not keyed moves.
      CanvasIconButton(
        key: const ValueKey("counterEasingAll"),
        icon: Icons.format_line_spacing,
        tooltip: "Give every point of the count this easing",
        onPressed: () {
          c.begin();
          controller.setKeyframeEasing(e, keyHere.easing,
              all: true, channel: KeyframeChannel.count);
          c.commit();
        },
      ),
    ],
    CanvasKeyframeDot(
      on: controller.hasValueKey(e, KeyframeChannel.count),
      enabled: frames > 1,
      tooltip: controller.hasValueKey(e, KeyframeChannel.count)
          ? "Take the point off frame $at"
          : "Pin this number on frame $at",
      onPressed: () {
        controller.beginInteraction();
        if (controller.hasValueKey(e, KeyframeChannel.count)) {
          controller.clearValueKey(e, KeyframeChannel.count);
        } else {
          pin(value);
        }
        controller.endInteraction();
      },
    ),
    ..._keyedHints(frames, keyHere != null),
  ];
}

/// _keyedHints say how a keyed count is made, and what easing is where a
/// key is [onKey].
List<Widget> _keyedHints(int frames, bool onKey) => [
      if (onKey)
        const CanvasHint(
            "Easing is how the number travels from this point to the next "
            "one. Hold does not travel at all: the number stays as it is "
            "until the next keyframe and then changes to that, which is how "
            "a count goes up in steps rather than sliding."),
      CanvasHint(frames <= 1
          ? "Give the canvas more than one frame and the counter can count "
              "across it. Until then it shows where it starts."
          : "Put the playhead where the count should start and press the "
              "first button, then where it should finish and press the "
              "second. Points in between can be any value at all, higher or "
              "lower than either end, and every one of them is a keyframe "
              "you can drag on the timeline."),
    ];

/// _numberType is the number's type, and the gap to its words.
Widget _numberType(BuildContext context, _Counter c) {
  var e = c.e;
  return boxed(
    context,
    CanvasExpander(
      label: "Number type",
      remember: "counterNumberType",
      trailing: "${e.numberSpec.fontSize.round()}",
      children: [
        _styleRow(c.controller, e, words: false),
        labelType(
            TypeEdit(
                e.numberSpec,
                (spec) => c.write(e.copyWith(numberSpec: spec)),
                c.begin,
                c.commit),
            label: "Number type",
            remember: "counterNumber"),
        CanvasControlGroup(label: "Spacing", children: [
          CanvasNumberField(
            key: const ValueKey("counterGap"),
            label: "Words gap",
            value: e.gap,
            min: 0,
            max: CounterElement.maxGap,
            decimals: 2,
            width: 62,
            onChanged: (v) => c.live(e.copyWith(gap: v)),
            onCommit: c.commit,
          ),
          const CanvasHint(
              "The space between the number and the words either side of "
              "it, in the number's own ems -- so it holds when the type is "
              "shrunk to fit. A gap set in pixels for sixty-point figures "
              "is a chasm beside twenty-point ones."),
        ]),
      ],
    ),
  );
}

/// _wordsType is the words' type, and where they sit.
Widget _wordsType(BuildContext context, _Counter c) {
  var e = c.e;
  return boxed(
    context,
    CanvasExpander(
      label: "Words type",
      remember: "counterAffixType",
      trailing: "${e.affixSpec.fontSize.round()}",
      children: [
        _styleRow(c.controller, e, words: true),
        labelType(
            TypeEdit(
                e.affixSpec,
                (spec) => c.write(e.copyWith(affixSpec: spec)),
                c.begin,
                c.commit),
            label: "Words type",
            remember: "counterWords"),
        CanvasControlGroup(label: "Placing", children: [
          CanvasToggle(
            key: const ValueKey("counterLoose"),
            label: "Place freely",
            value: e.loose,
            onChanged: (v) => c.now(e.copyWith(loose: v)),
          ),
          if (e.loose) ...[
            ..._placing(c, "Before", e.beforeAt,
                (at) => e.copyWith(beforeAt: at), "counterBeforeAt"),
            const CanvasLineBreak(),
            ..._placing(c, "After", e.afterAt, (at) => e.copyWith(afterAt: at),
                "counterAfterAt"),
          ],
          CanvasHint(e.loose
              ? "Each word sits where it is put, as a fraction of the box "
                  "from its middle: nought is the middle and half is the "
                  "edge. They can be dragged on the canvas as well."
              : "The words sit on the number's own line. Turn this on to "
                  "put them anywhere in the box -- a currency in a corner, "
                  "a unit under the figures."),
        ]),
      ],
    ),
  );
}

/// _boxAndFit is the counter's box, and whether its type shrinks to fit.
List<Widget> _boxAndFit(BuildContext context, _Counter c) {
  var e = c.e;
  return [
    boxGroup(e.box, (box) => c.write(e.copyWith(box: box)), c.begin, c.commit,
        remember: "counter", rule: false, fillPickedIn: context, compact: true),
    CanvasControlGroup(label: "Size", rule: false, children: [
      CanvasToggle(
        key: const ValueKey("counterFit"),
        label: "Shrink to fit",
        value: e.fit,
        onChanged: (v) => c.now(e.copyWith(fit: v)),
      ),
      const CanvasHint(
          "The width of a number changes as it counts. Left to itself, a "
          "counter set to look right at 42 is cut off at 1,234,567 -- so the "
          "type is sized to the widest value the count will ever reach, and "
          "then stays there. Turn it off to keep the type exactly as set."),
    ]),
  ];
}

/// _placing is the X and Y of one hand-placed thing: a fraction of the box
/// from its middle, so it keeps its place when the counter is resized.
List<Widget> _placing(_Counter c, String name, Offset at,
    CounterElement Function(Offset) placed, String key) {
  Widget axis(bool x) => CanvasNumberField(
        key: ValueKey("$key${x ? "X" : "Y"}"),
        label: "$name ${x ? "X" : "Y"}",
        value: x ? at.dx : at.dy,
        min: -1,
        max: 1,
        decimals: 2,
        width: 62,
        onChanged: (v) =>
            c.live(placed(x ? Offset(v, at.dy) : Offset(at.dx, v))),
        onCommit: c.commit,
      );
  return [axis(true), axis(false)];
}

/// _buttonsSection is the controls a run offers the reader.
Widget _buttonsSection(_Counter c) {
  var e = c.e;
  return CanvasExpander(
    label: "Buttons",
    remember: "counterButtons",
    flat: true,
    trailing: e.buttons.isEmpty ? "None" : "${e.buttons.length}",
    children: [
      CanvasControlGroup(label: "Buttons", hideCaption: true, children: [
        for (var button in CounterButton.values)
          CanvasToggle(
            key: ValueKey("counterButton-${button.name}"),
            label: button.label,
            value: e.buttons.contains(button),
            onChanged: (v) => c.now(e.copyWith(buttons: [
              // In declaration order, not switch-on order, so a counter set
              // up twice comes out the same.
              for (var b in CounterButton.values)
                if (b == button ? v : e.buttons.contains(b)) b,
            ])),
          ),
        const CanvasHint("Drawn in a row under the number. Set asks the "
            "reader for a value to carry on from."),
      ]),
      if (e.buttons.isNotEmpty) ...[
        _buttonsPlacing(c),
        CanvasExpander(
          label: "Button type",
          remember: "counterButtonType",
          trailing: "${e.buttonSpec.fontSize.round()}",
          children: typeGroups(
              e.buttonSpec,
              (spec) => c.write(e.copyWith(buttonSpec: spec)),
              c.begin,
              c.commit,
              label: "Button type",
              hideCaption: true,
              remember: "counterButton"),
        ),
        boxGroup(e.buttonBox, (box) => c.write(e.copyWith(buttonBox: box)),
            c.begin, c.commit,
            label: "Button box", remember: "counterButton"),
      ],
    ],
  );
}

/// _buttonsPlacing is whether the buttons share a row, or each sits where
/// it is put, and at what size.
Widget _buttonsPlacing(_Counter c) {
  var e = c.e;
  Widget side(bool width) => CanvasNumberField(
        key: ValueKey(width ? "counterButtonWidth" : "counterButtonHeight"),
        label: width ? "Width" : "Height",
        value: width ? e.buttonSize.width : e.buttonSize.height,
        min: CounterElement.minButtonSize,
        max: CounterElement.maxButtonSize,
        decimals: 2,
        width: 56,
        onChanged: (v) => c.live(e.copyWith(
            buttonSize: width
                ? Size(v, e.buttonSize.height)
                : Size(e.buttonSize.width, v))),
        onCommit: c.commit,
      );
  return CanvasControlGroup(label: "Placing", children: [
    CanvasToggle(
      key: const ValueKey("counterLooseButtons"),
      label: "Place freely",
      value: e.looseButtons,
      onChanged: (v) => c.now(e.copyWith(looseButtons: v)),
    ),
    if (e.looseButtons) ...[
      side(true),
      side(false),
      for (var i = 0; i < e.buttons.length; i++) ...[
        const CanvasLineBreak(),
        ..._placing(
            c,
            e.buttons[i].label,
            e.placedButton(i),
            (at) => e.copyWith(buttonAt: [
                  for (var j = 0; j < e.buttons.length; j++)
                    j == i ? at : e.placedButton(j),
                ]),
            "counterButtonAt$i"),
      ],
    ],
    CanvasHint(e.looseButtons
        ? "Each button sits where it is put, and can be dragged on the "
            "canvas."
        : "The buttons share a row along the bottom of the box. Turn this "
            "on to put each of them where you like."),
  ]);
}

/// _styleRow puts the number (or [words]) in a document text style, makes
/// one from its type, or changes it (see CanvasDocument.textStyles).
Widget _styleRow(CanvasController controller, CounterElement e,
    {required bool words}) {
  var styles = controller.textStyles;
  var linked = words ? e.wordStyle : e.numberStyle;
  var styled = styles.any((t) => t.name == linked);
  var which = words ? "Words" : "Number";
  return CanvasControlGroup(
    key: ValueKey("counter${which}Style"),
    label: "Style",
    hideCaption: true,
    rule: false,
    children: [
      if (styles.isNotEmpty)
        CanvasDropdown<String>(
          key: ValueKey("counter${which}StylePick"),
          label: "Style",
          value: styled ? linked : "",
          width: 120,
          options: [
            ("", "Its own"),
            for (var t in styles) (t.name, t.name),
          ],
          onChanged: (v) => controller.useCounterStyle(e.id, v, words: words),
        ),
      CanvasIconButton(
        key: ValueKey("counter${which}StyleSave"),
        icon: Icons.bookmark_add_outlined,
        tooltip: "Make this type a style",
        onPressed: () => controller.saveCounterStyle(e, words: words),
      ),
      if (styled)
        CanvasIconButton(
          key: ValueKey("counter${which}StyleUpdate"),
          icon: Icons.sync,
          tooltip: "Change the style to this type -- everything in "
              "\"$linked\" not changed by hand changes with it",
          onPressed: () => controller.updateTextStyle(
              linked, words ? e.affixSpec : e.numberSpec),
        ),
    ],
  );
}
