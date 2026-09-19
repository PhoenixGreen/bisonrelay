import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// counter_settings.dart is a counter's settings.
//
// The order is the order somebody sets one up in: what it counts from and to,
// how the number is written, the words either side of it, and only then the
// type, the box and -- for a live one -- the buttons.
//
// The one section that is not a list of fields is Count, which has the two
// keyframe buttons in it. They are there rather than on the timeline because
// what they pin is this element's own number, and the timeline has no idea
// what a counter is.

List<Widget> counterSettings(
  BuildContext context,
  CanvasController controller,
  CounterElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(CounterElement next) {
    begin();
    write(next);
    commit();
  }

  // What the number is at this frame, which is what the sample under the
  // fields shows and what the Add point button pins.
  var here = e.keyed
      ? controller.valueAt(e, KeyframeChannel.count, e.from)
      : controller.counterValue(e);

  return [
    CanvasControlGroup(
        label: "Counts",
        hideCaption: true,
        rule: false,
        children: [
          CanvasNumberField(
            key: const ValueKey("counterFrom"),
            label: "From",
            value: e.from,
            min: -1000000000,
            max: 1000000000,
            decimals: e.decimals,
            width: 84,
            onChanged: (v) => write(e.copyWith(from: v)),
            onCommit: commit,
          ),
          CanvasNumberField(
            key: const ValueKey("counterTo"),
            label: "To",
            value: e.to,
            min: -1000000000,
            max: 1000000000,
            decimals: e.decimals,
            width: 84,
            onChanged: (v) => write(e.copyWith(to: v)),
            onCommit: commit,
          ),
          CanvasNumberField(
            key: const ValueKey("counterDecimals"),
            label: "Decimals",
            value: e.decimals.toDouble(),
            min: 0,
            max: 8,
            decimals: 0,
            width: 54,
            onChanged: (v) => write(e.copyWith(decimals: v.round())),
            onCommit: commit,
          ),
          // The grouping and the point are one choice rather than two: a number
          // written 1.234,56 is not 1,234.56 with a different point, it is a
          // different convention -- and the two time formats are not grouping at
          // all.
          CanvasDropdown<CounterSeparator>(
            key: const ValueKey("counterSeparator"),
            label: "Written",
            value: e.separator,
            width: 132,
            options: [
              for (var s in CounterSeparator.values)
                (s, s == CounterSeparator.none ? "Plain" : s.label)
            ],
            onChanged: (v) => now(e.copyWith(separator: v)),
          ),
          CanvasHint("Counts ${e.format(e.from)} to ${e.format(e.to)}"
              "${e.separator.isTime ? ", reading the value as seconds" : ""}."),
        ]),
    CanvasControlGroup(label: "Words", rule: false, children: [
      CanvasTextField(
        key: const ValueKey("counterBefore"),
        label: "Before",
        value: e.before,
        width: 96,
        onChanged: (v) => write(e.copyWith(before: v)),
        onCommit: commit,
      ),
      CanvasTextField(
        key: const ValueKey("counterAfter"),
        label: "After",
        value: e.after,
        width: 96,
        onChanged: (v) => write(e.copyWith(after: v)),
        onCommit: commit,
      ),
      CanvasHint("Now: ${e.textFor(here)}"),
    ]),
    boxed(context, _countSection(context, controller, e, write, begin, commit)),
    boxed(
      context,
      CanvasExpander(
        label: "Number type",
        remember: "counterNumberType",
        trailing: "${e.numberSpec.fontSize.round()}",
        children: [
          ...typeGroups(e.numberSpec,
              (spec) => write(e.copyWith(numberSpec: spec)), begin, commit,
              label: "Number type",
              hideCaption: true,
              remember: "counterNumber"),
          CanvasControlGroup(label: "Spacing", children: [
            CanvasNumberField(
              key: const ValueKey("counterGap"),
              label: "Words gap",
              value: e.gap,
              min: 0,
              max: 8,
              decimals: 2,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(gap: v));
              },
              onCommit: commit,
            ),
            const CanvasHint(
                "The space between the number and the words either side of "
                "it, in the number's own ems -- so it holds when the type is "
                "shrunk to fit. A gap set in pixels for sixty-point figures "
                "is a chasm beside twenty-point ones."),
          ]),
        ],
      ),
    ),
    boxed(
      context,
      CanvasExpander(
        label: "Words type",
        remember: "counterAffixType",
        trailing: "${e.affixSpec.fontSize.round()}",
        children: [
          ...typeGroups(e.affixSpec,
              (spec) => write(e.copyWith(affixSpec: spec)), begin, commit,
              label: "Words type", hideCaption: true, remember: "counterWords"),
          CanvasControlGroup(label: "Placing", children: [
            CanvasToggle(
              key: const ValueKey("counterLoose"),
              label: "Place freely",
              value: e.loose,
              onChanged: (v) => now(e.copyWith(loose: v)),
            ),
            if (e.loose) ...[
              ..._placing(
                  "Before",
                  e.beforeAt,
                  (at) => write(e.copyWith(beforeAt: at)),
                  begin,
                  commit,
                  "counterBeforeAt"),
              const CanvasLineBreak(),
              ..._placing(
                  "After",
                  e.afterAt,
                  (at) => write(e.copyWith(afterAt: at)),
                  begin,
                  commit,
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
    ),
    boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
        remember: "counter", rule: false),
    CanvasControlGroup(label: "Size", rule: false, children: [
      CanvasToggle(
        key: const ValueKey("counterFit"),
        label: "Shrink to fit",
        value: e.fit,
        onChanged: (v) => now(e.copyWith(fit: v)),
      ),
      const CanvasHint(
          "The width of a number changes as it counts. Left to itself, a "
          "counter set to look right at 42 is cut off at 1,234,567 -- so the "
          "type is sized to the widest value the count will ever reach, and "
          "then stays there. Turn it off to keep the type exactly as set."),
    ]),
    boxed(context, _buttonsSection(context, e, write, begin, commit, now)),
    boxed(
        context,
        elementAnimationSection(controller, e, e.animation,
            (a) => write(e.copyWith(animation: a)), begin, commit)),
  ];
}

/// _countSection is where the number comes from: the timeline, or a clock.
Widget _countSection(
  BuildContext context,
  CanvasController controller,
  CounterElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(CounterElement next) {
    begin();
    write(next);
    commit();
  }

  var frames = controller.document.frames;
  var at = controller.frame;
  var value = controller.valueAt(e, KeyframeChannel.count, e.from);

  return CanvasExpander(
    label: "Count",
    remember: "counterCount",
    trailing: e.keyed ? "Keyframes" : "Live",
    children: [
      CanvasControlGroup(label: "Count", hideCaption: true, children: [
        // The switch that makes this two elements in one. On, the number is
        // read off the timeline; off, it runs in real time and the buttons
        // below mean something.
        CanvasToggle(
          key: const ValueKey("counterKeyed"),
          label: "Keyframes",
          value: e.keyed,
          onChanged: (v) => now(e.copyWith(keyed: v)),
        ),
        if (e.keyed) ...[
          // The two ends, pinned where the playhead is. A button rather than
          // a frame field because the frame somebody means is the one they
          // are looking at, and because moving it afterwards is dragging the
          // keyframe -- which the timeline already does.
          CanvasIconButton(
            key: const ValueKey("counterPinFrom"),
            icon: Icons.first_page,
            tooltip: "Start the count here, at ${e.format(e.from)}",
            onPressed: frames <= 1
                ? null
                : () => controller.setValueKey(e, KeyframeChannel.count, e.from,
                    seed: false),
          ),
          CanvasIconButton(
            key: const ValueKey("counterPinTo"),
            icon: Icons.last_page,
            tooltip: "Finish the count here, at ${e.format(e.to)}",
            onPressed: frames <= 1
                ? null
                : () => controller.setValueKey(e, KeyframeChannel.count, e.to,
                    seed: false),
          ),
          // A point in the middle, whose value can be anything at all: a
          // count from 0 to 100 can go up past 140 and come back, which is
          // the whole reason the channel holds the number rather than a
          // fraction of the way through.
          CanvasIconButton(
            key: const ValueKey("counterAddPoint"),
            icon: Icons.add_location_alt_outlined,
            tooltip: "Add a point here, at ${e.format(value)}",
            onPressed: frames <= 1
                ? null
                : () => controller.setValueKey(e, KeyframeChannel.count, value,
                    seed: false),
          ),
          CanvasNumberField(
            key: const ValueKey("counterPointValue"),
            label: "Value here",
            value: value,
            min: -1000000000,
            max: 1000000000,
            decimals: e.decimals,
            width: 88,
            onChanged: (v) {
              begin();
              controller.setValueKey(e, KeyframeChannel.count, v, seed: false);
            },
            onCommit: commit,
          ),
          // How the number gets from this keyframe to the next one. The
          // keyframe's own easing, which is the same field the timeline's
          // panel shows -- one value, two places to reach it, rather than a
          // second kind of easing that only counters have.
          if (e.track?.keyAt(at) case var keyHere?)
            CanvasDropdown<KeyframeEasing>(
              key: const ValueKey("counterEasing"),
              label: "Easing",
              value: keyHere.easing,
              width: 132,
              options: [
                for (var easing in KeyframeEasing.values)
                  (
                    easing,
                    // Said in the counter's own words. "Hold" is what it is
                    // called everywhere else and what it does to a pose; on a
                    // number, what it does is leave it alone until the next
                    // keyframe, and that is worth saying where the number is.
                    easing == KeyframeEasing.hold
                        ? "Hold (stays the same)"
                        : easing.label
                  ),
              ],
              onChanged: (v) {
                begin();
                controller.setKeyframe(e.id, keyHere.copyWith(easing: v));
                commit();
              },
            ),
          // The same easing on every point of the count.
          //
          // A count is usually one movement in several hops, and setting each
          // hop by hand is the same choice made four times -- and getting one
          // of them wrong is a single point that slides while the rest step.
          // Only the points that carry a number: an element can have a move
          // keyframed on the same track, and that is not this setting's to
          // restyle.
          if (e.track?.keyAt(at) case var keyHere?)
            CanvasIconButton(
              key: const ValueKey("counterEasingAll"),
              icon: Icons.format_line_spacing,
              tooltip: "Give every point of the count this easing",
              onPressed: () {
                begin();
                controller.setKeyframeEasing(e, keyHere.easing,
                    all: true, channel: KeyframeChannel.count);
                commit();
              },
            ),
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
                controller.setValueKey(e, KeyframeChannel.count, value,
                    seed: false);
              }
              controller.endInteraction();
            },
          ),
          if (e.track?.keyAt(at) != null)
            const CanvasHint(
                "Easing is how the number travels from this point to the "
                "next one. Hold does not travel at all: the number stays as "
                "it is until the next keyframe and then changes to that, "
                "which is how a count goes up in steps rather than sliding."),
          CanvasHint(frames <= 1
              ? "Give the canvas more than one frame and the counter can "
                  "count across it. Until then it shows where it starts."
              : "Put the playhead where the count should start and press the "
                  "first button, then where it should finish and press the "
                  "second. Points in between can be any value at all, higher "
                  "or lower than either end, and every one of them is a "
                  "keyframe you can drag on the timeline."),
        ],
        if (!e.keyed) ...[
          CanvasDropdown<CounterSource>(
            key: const ValueKey("counterSource"),
            label: "Shows",
            value: e.source,
            width: 128,
            options: [for (var s in CounterSource.values) (s, s.label)],
            onChanged: (v) => now(e.copyWith(
                source: v,
                // A clock written plainly is a number of seconds since
                // midnight, which is not a thing anybody wants to read.
                separator: v == CounterSource.clock && !e.separator.isTime
                    ? CounterSeparator.hours
                    : e.separator)),
          ),
          if (e.source == CounterSource.run) ...[
            CanvasNumberField(
              key: const ValueKey("counterRate"),
              label: "Per second",
              value: e.rate,
              min: 0,
              max: 100000,
              decimals: 2,
              width: 72,
              onChanged: (v) {
                begin();
                write(e.copyWith(rate: v));
              },
              onCommit: commit,
            ),
            CanvasToggle(
              key: const ValueKey("counterLoop"),
              label: "Loop",
              value: e.loop,
              onChanged: (v) => now(e.copyWith(loop: v)),
            ),
            CanvasToggle(
              key: const ValueKey("counterRunning"),
              label: "Start running",
              value: e.running,
              onChanged: (v) => now(e.copyWith(running: v)),
            ),
          ],
          CanvasHint(e.source == CounterSource.clock
              ? "The reader's own clock, in seconds since midnight -- so the "
                  "Minutes or Hours way of writing it is the one that makes "
                  "a clock of it."
              : "Counts from ${e.format(e.from)} to ${e.format(e.to)} at "
                  "${e.rate} a second, which is "
                  "${(e.span / (e.rate <= 0 ? 1 : e.rate)).abs().round()} "
                  "seconds end to end. Turn Loop on and it starts again, "
                  "which is what makes a metronome."),
        ],
      ]),
    ],
  );
}

/// _placing is the X and Y of one thing that has been placed by hand.
///
/// A fraction of the box from its middle rather than a position in document
/// units: the counter can be resized, and the words should stay where they
/// were put relative to it, which pixels cannot do.
List<Widget> _placing(
  String name,
  Offset at,
  ValueChanged<Offset> onChanged,
  VoidCallback begin,
  VoidCallback commit,
  String key,
) =>
    [
      CanvasNumberField(
        key: ValueKey("${key}X"),
        label: "$name X",
        value: at.dx,
        min: -1,
        max: 1,
        decimals: 2,
        width: 62,
        onChanged: (v) {
          begin();
          onChanged(Offset(v, at.dy));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        key: ValueKey("${key}Y"),
        label: "$name Y",
        value: at.dy,
        min: -1,
        max: 1,
        decimals: 2,
        width: 62,
        onChanged: (v) {
          begin();
          onChanged(Offset(at.dx, v));
        },
        onCommit: commit,
      ),
    ];

/// _buttonsSection is the controls a live counter offers the reader.
Widget _buttonsSection(
  BuildContext context,
  CounterElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
  void Function(CounterElement) now,
) =>
    CanvasExpander(
      label: "Buttons",
      remember: "counterButtons",
      trailing: e.buttons.isEmpty ? "None" : "${e.buttons.length}",
      children: [
        CanvasControlGroup(label: "Buttons", hideCaption: true, children: [
          for (var button in CounterButton.values)
            CanvasToggle(
              key: ValueKey("counterButton-${button.name}"),
              label: button.label,
              value: e.buttons.contains(button),
              onChanged: (v) => now(e.copyWith(buttons: [
                // Kept in the order they are declared in rather than the
                // order they were switched on, so a counter set up twice
                // comes out the same way round both times.
                for (var b in CounterButton.values)
                  if (b == button ? v : e.buttons.contains(b)) b,
              ])),
            ),
          CanvasHint(e.keyed
              ? "Buttons are for a counter that runs in real time. Turn "
                  "Keyframes off under Count and these become a stopwatch's "
                  "controls; on a keyframed counter they are drawn and do "
                  "nothing."
              : "Drawn in a row under the number. Set asks the reader for a "
                  "value to carry on from."),
        ]),
        if (e.buttons.isNotEmpty) ...[
          CanvasControlGroup(label: "Placing", children: [
            CanvasToggle(
              key: const ValueKey("counterLooseButtons"),
              label: "Place freely",
              value: e.looseButtons,
              onChanged: (v) => now(e.copyWith(looseButtons: v)),
            ),
            if (e.looseButtons) ...[
              CanvasNumberField(
                key: const ValueKey("counterButtonWidth"),
                label: "Width",
                value: e.buttonSize.width,
                min: 0.05,
                max: 1,
                decimals: 2,
                width: 56,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(buttonSize: Size(v, e.buttonSize.height)));
                },
                onCommit: commit,
              ),
              CanvasNumberField(
                key: const ValueKey("counterButtonHeight"),
                label: "Height",
                value: e.buttonSize.height,
                min: 0.05,
                max: 1,
                decimals: 2,
                width: 56,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(buttonSize: Size(e.buttonSize.width, v)));
                },
                onCommit: commit,
              ),
              for (var i = 0; i < e.buttons.length; i++) ...[
                const CanvasLineBreak(),
                ..._placing(
                    e.buttons[i].label,
                    e.placedButton(i),
                    (at) => write(e.copyWith(buttonAt: [
                          for (var j = 0; j < e.buttons.length; j++)
                            j == i ? at : e.placedButton(j),
                        ])),
                    begin,
                    commit,
                    "counterButtonAt$i"),
              ],
            ],
            CanvasHint(e.looseButtons
                ? "Each button sits where it is put, and can be dragged on "
                    "the canvas."
                : "The buttons share a row along the bottom of the box. Turn "
                    "this on to put each of them where you like."),
          ]),
          CanvasExpander(
            label: "Button type",
            remember: "counterButtonType",
            trailing: "${e.buttonSpec.fontSize.round()}",
            children: typeGroups(e.buttonSpec,
                (spec) => write(e.copyWith(buttonSpec: spec)), begin, commit,
                label: "Button type",
                hideCaption: true,
                remember: "counterButton"),
          ),
          boxGroup(e.buttonBox, (box) => write(e.copyWith(buttonBox: box)),
              begin, commit,
              label: "Button box", remember: "counterButton"),
        ],
      ],
    );
