import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// text settings.dart is a text element's settings.

List<Widget> textSettings(CanvasController controller, TextElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void now(TextElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    // No Content field. The words are typed on the canvas, in the box they
    // will appear in, at the size and face they will appear at -- see
    // CanvasTextEditor. A two-line box in a settings panel could show neither,
    // so writing a headline meant typing it here and looking over there.
    // No caption: the panel header says "Text settings" already, and a
    // group called Text directly under it was the word twice.
    CanvasControlGroup(label: "Text", hideCaption: true, children: [
      CanvasToggle(
        label: "Fit to box",
        value: e.autoSize,
        onChanged: (v) => now(e.copyWith(autoSize: v)),
      ),
    ]),
    ...typeGroups(
        e.textSpec, (spec) => write(e.copyWith(textSpec: spec)), begin, commit),
    CanvasControlGroup(label: "Columns", children: [
      CanvasNumberField(
        key: const ValueKey("textColumns"),
        label: "Columns",
        value: e.columns.count.toDouble(),
        min: 1,
        max: 12,
        width: 54,
        onChanged: (v) {
          begin();
          write(e.copyWith(columns: e.columns.copyWith(count: v.round())));
        },
        onCommit: commit,
      ),
      // The rest only means something once there is a gutter to put it in.
      if (!e.columns.isSingle) ...[
        CanvasNumberField(
          label: "Gap",
          value: e.columns.gap,
          min: 0,
          max: 400,
          width: 54,
          onChanged: (v) {
            begin();
            write(e.copyWith(columns: e.columns.copyWith(gap: v)));
          },
          onCommit: commit,
        ),
        CanvasDropdown<ColumnRuleStyle>(
          label: "Rule",
          value: e.columns.ruleStyle,
          width: 92,
          options: [for (var v in ColumnRuleStyle.values) (v, v.label)],
          onChanged: (v) =>
              now(e.copyWith(columns: e.columns.copyWith(ruleStyle: v))),
        ),
        if (e.columns.ruleStyle != ColumnRuleStyle.none) ...[
          CanvasNumberField(
            label: "Width",
            value: e.columns.ruleWidth,
            min: 0,
            max: 40,
            decimals: 1,
            width: 54,
            onChanged: (v) {
              begin();
              write(e.copyWith(columns: e.columns.copyWith(ruleWidth: v)));
            },
            onCommit: commit,
          ),
          CanvasColorButton(
            label: "Colour",
            color: e.columns.ruleColor,
            onChanged: (c) =>
                now(e.copyWith(columns: e.columns.copyWith(ruleColor: c))),
          ),
        ],
      ],
    ]),
    CanvasControlGroup(label: "On a line", children: [
      CanvasDropdown<String>(
        label: "Follow",
        value: e.curve?.elementId ?? "",
        width: 156,
        options: curveOptions(controller),
        onChanged: (v) => now(v.isEmpty
            ? e.copyWith(clearCurve: true)
            : e.copyWith(
                curve: (e.curve ?? const TextOnCurve(elementId: ""))
                    .copyWith(elementId: v))),
      ),
      if (e.curve != null) ...[
        CanvasNumberField(
          label: "Slide",
          decimals: 2,
          width: 62,
          value: controller.valueAt(e, KeyframeChannel.slide, e.curve!.offset),
          min: -1,
          max: 1,
          onChanged: (v) {
            begin();
            // Written as a keyframe once this frame has one, so dragging the
            // slider while animating retimes the caption's travel rather than
            // moving the whole run.
            if (controller.hasValueKey(e, KeyframeChannel.slide)) {
              controller.setValueKey(e, KeyframeChannel.slide, v);
              return;
            }
            write(e.copyWith(curve: e.curve!.copyWith(offset: v)));
          },
          onCommit: commit,
        ),
        valueDot(
            controller,
            e,
            KeyframeChannel.slide,
            "the slide along the "
            "line",
            e.curve!.offset),
        CanvasNumberField(
          label: "Spacing",
          value: e.curve!.spacing,
          min: -20,
          max: 60,
          decimals: 1,
          width: 58,
          onChanged: (v) {
            begin();
            write(e.copyWith(curve: e.curve!.copyWith(spacing: v)));
          },
          onCommit: commit,
        ),
        CanvasToggle(
          label: "Below",
          value: e.curve!.away,
          onChanged: (v) => now(e.copyWith(curve: e.curve!.copyWith(away: v))),
        ),
        CanvasToggle(
          // Not the line element's own Hide: a hidden element is skipped
          // everywhere, this one included, so the text would go with it.
          label: "Hide line",
          value: e.curve!.hideHost,
          onChanged: (v) =>
              now(e.copyWith(curve: e.curve!.copyWith(hideHost: v))),
        ),
      ],
    ]),
    boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit),
  ];
}

/// valueDot is the diamond beside one animatable property.
///
/// Its own control rather than part of the pose diamond, because these are
/// real channels: a keyframe can pin a caption's slide without pinning where
/// its box sits, and the two are asked for at different moments.
