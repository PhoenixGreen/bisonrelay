import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';

// settings_shared.dart is what every element's settings are made of: where it
// is, what type it is set in, and the box round it.
//
// Shared because they really are the same controls. Position is the same six
// numbers for a picture as for a pitch, and the type controls are the same
// dozen wherever words are drawn -- written per element they would be nine
// copies to keep in step, and the first setting added to one of them would be
// the first setting missing from the other eight.

typedef SettingsWrite = void Function(CanvasElement);

/// positionGroup is what every element has: where it is, how big, how turned,
/// and whether it can be touched.

/// positionGroup is what every element has: where it is, how big, how turned,
/// and whether it can be touched.
Widget positionGroup(CanvasController controller, CanvasElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  // No lock, hide, or bring-to-front here. Every one of them is a property of
  // the *layer* rather than of the thing on it, and the layer list already
  // shows all four on the row that names the element -- where they can be used
  // without selecting it first, and where hiding something does not make the
  // panel you are hiding it from disappear. Having them in both places meant
  // two controls for one switch that could disagree about which icon meant on.

  var frame = controller.frame;
  var pose = e.poseAt(frame);
  var box = e.boundsAt(frame);
  var animated = controller.document.isAnimated;

  /// posing is whether these fields are editing a keyframe rather than the
  /// element's resting position. The same question the stage asks of a drag,
  /// so a number typed here and a pixel dragged there mean the same thing.
  var posing = controller.posesRatherThanMoves(e);

  /// onKey is what the little diamonds do: add the pose at this frame, or take
  /// it away. One keyframe holds every animated property at once, so all of
  /// them light up together -- see CanvasKeyframeDot.
  var hasKey = e.track?.keyAt(frame) != null;
  void toggleKey() {
    begin();
    if (hasKey) {
      controller.removeKeyframe(e.id, frame);
    } else {
      controller.setKeyframe(e.id, pose.copyWith(frame: frame));
    }
    commit();
  }

  // One diamond for the group, not one per field. A keyframe here is a whole
  // pose -- position, size, angle and fade together -- so six of them lit up
  // and went out in unison and pressing any one did the same thing. Six
  // controls for one switch is six chances to think they are separate.
  var poseDot = CanvasKeyframeDot(
    on: hasKey,
    enabled: animated,
    tooltip: !animated
        ? "Give the canvas more than one frame to animate this element"
        : hasKey
            ? "Remove this element's keyframe here — one keyframe holds its "
                "position, size, angle and fade together"
            : "Add a keyframe here for this element's position, size, angle "
                "and fade",
    onPressed: toggleKey,
  );

  /// moveTo writes a position, as a pose while animating and as the resting
  /// position otherwise.
  ///
  /// Showing and editing the *posed* value is the point. The fields used to
  /// show where an element rests, so scrubbing to the middle of a move left X
  /// and Y reading the start of it -- two numbers describing somewhere the
  /// element visibly was not.
  void moveTo({double? x, double? y}) {
    begin();
    if (!posing) {
      write(e.withBase(x: x, y: y));
      return;
    }
    var track = (e.track ?? ElementTrack.empty).seededFor(frame);
    var at = track.at(frame);
    write(e.withBase(
      track: track.withKey(at.copyWith(
        frame: frame,
        dx: x == null ? at.dx : x - e.x,
        dy: y == null ? at.dy : y - e.y,
      )),
    ));
  }

  // Text riding a line has no position or angle of its own: where it is and
  // how it is turned are the line's to decide. The fields were still there and
  // still writable, so nudging them moved the words off the line they were
  // attached to -- which is the one thing attaching them is meant to prevent.
  if (e is TextElement && e.curve != null) {
    return CanvasControlGroup(label: e.kind.label, children: [
      Padding(
        padding: const EdgeInsets.only(top: controlLabelHeight, right: 6),
        child: SizedBox(
          height: controlHeight,
          child: Center(
            child: const Txt.S("Placed by the line it follows"),
          ),
        ),
      ),
      CanvasNumberField(
        label: "Opacity",
        min: 0,
        max: 1,
        decimals: 2,
        width: 62,
        value: e.opacityAt(frame),
        onChanged: (v) {
          begin();
          write(e.withBase(opacity: v));
        },
        onCommit: commit,
      ),
      poseDot,
    ]);
  }

  return CanvasControlGroup(
      label: e.kind.label,
      // The settings are already headed with the element's own name, so this
      // caption said "Chart" directly under a heading saying "Chart".
      bandOnlyLabel: true,
      children: [
        CanvasNumberField(
          key: const ValueKey("elementX"),
          label: "X",
          value: box.left,
          onChanged: (v) => moveTo(x: v),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: const ValueKey("elementY"),
          label: "Y",
          value: box.top,
          onChanged: (v) => moveTo(y: v),
          onCommit: commit,
        ),
        // Width and height show what is on screen -- the resting size times the
        // pose's scale -- but always edit the resting size. A pose scales evenly,
        // so there is no keyframe that could hold a width without also holding a
        // height, and pretending otherwise would give two fields one number.
        CanvasNumberField(
          label: "W",
          value: box.width,
          min: 1,
          onChanged: (v) =>
              write(e.withBase(width: pose.scale == 0 ? v : v / pose.scale)),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "H",
          value: box.height,
          min: 1,
          onChanged: (v) =>
              write(e.withBase(height: pose.scale == 0 ? v : v / pose.scale)),
          onCommit: commit,
        ),
        // Where it is and how big it is, then how it is turned and how solid.
        // Two different questions, and left to the Wrap the line fell between W
        // and H or after Angle depending on how wide the sidebar happened to be.
        const CanvasLineBreak(),
        CanvasNumberField(
          key: const ValueKey("elementAngle"),
          label: "Angle",
          value: e.rotationAt(frame),
          min: -3600,
          max: 3600,
          width: 56,
          suffix: "°",
          onChanged: (v) {
            begin();
            if (!posing) {
              write(e.withBase(rotation: v));
              return;
            }
            var track = (e.track ?? ElementTrack.empty).seededFor(frame);
            write(e.withBase(
                track: track.withKey(track
                    .at(frame)
                    .copyWith(frame: frame, rotate: v - e.rotation))));
          },
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Opacity",
          min: 0,
          max: 1,
          decimals: 2,
          width: 62,
          value: e.opacityAt(frame),
          onChanged: (v) {
            begin();
            if (!posing) {
              write(e.withBase(opacity: v));
              return;
            }
            var track = (e.track ?? ElementTrack.empty).seededFor(frame);
            write(e.withBase(
                track: track.withKey(track.at(frame).copyWith(
                    frame: frame,
                    opacity: e.opacity == 0
                        ? v
                        : (v / e.opacity).clamp(0.0, 1.0)))));
          },
          onCommit: commit,
        ),
        poseDot,
      ]);
}

/// typeGroups is the shared type controls, used by every element that draws
/// words.

/// typeGroups is the shared type controls, used by every element that draws
/// words.
List<Widget> typeGroups(
  TextSpec spec,
  ValueChanged<TextSpec> onChanged,
  VoidCallback begin,
  VoidCallback commit, {
  String label = "Type",
  bool includeCase = true,

  /// bandOnlyLabel drops the first group's caption in a sidebar, for the
  /// callers that have already headed a section with the same word.
  bool bandOnlyLabel = false,
}) =>
    [
      CanvasControlGroup(label: label, bandOnlyLabel: bandOnlyLabel, children: [
        CanvasDropdown<String>(
          label: "Font",
          value: spec.fontFamily,
          width: 118,
          options: [for (var f in canvasFonts) (f, f)],
          onChanged: (v) {
            begin();
            onChanged(spec.copyWith(fontFamily: v));
            commit();
          },
        ),
        CanvasNumberField(
          label: "Size",
          value: spec.fontSize,
          min: 1,
          max: 800,
          width: 54,
          onChanged: (v) => onChanged(spec.copyWith(fontSize: v)),
          onCommit: commit,
        ),
        CanvasDropdown<int>(
          label: "Weight",
          value: spec.weight,
          width: 82,
          options: const [
            (100, "Thin"),
            (300, "Light"),
            (400, "Regular"),
            (500, "Medium"),
            (600, "Semibold"),
            (700, "Bold"),
            (800, "Extrabold"),
            (900, "Black"),
          ],
          onChanged: (v) {
            begin();
            onChanged(spec.copyWith(weight: v));
            commit();
          },
        ),
        CanvasIconButton(
          icon: Icons.format_italic,
          tooltip: "Italic",
          active: spec.italic,
          onPressed: () {
            begin();
            onChanged(spec.copyWith(italic: !spec.italic));
            commit();
          },
        ),
        CanvasIconButton(
          icon: Icons.format_underlined,
          tooltip: "Underline",
          active: spec.underline,
          onPressed: () {
            begin();
            onChanged(spec.copyWith(underline: !spec.underline));
            commit();
          },
        ),
      ]),
      CanvasControlGroup(label: "Spacing", children: [
        CanvasNumberField(
          label: "Letter",
          value: spec.letterSpacing,
          min: -50,
          max: 200,
          decimals: 1,
          width: 54,
          onChanged: (v) => onChanged(spec.copyWith(letterSpacing: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Line",
          value: spec.lineHeight,
          min: 0.5,
          max: 5,
          decimals: 2,
          width: 54,
          onChanged: (v) => onChanged(spec.copyWith(lineHeight: v)),
          onCommit: commit,
        ),
        CanvasDropdown<TextAlignSpec>(
          label: "Align",
          value: spec.align,
          width: 92,
          options: [for (var a in TextAlignSpec.values) (a, a.label)],
          onChanged: (v) {
            begin();
            onChanged(spec.copyWith(align: v));
            commit();
          },
        ),
        CanvasDropdown<VerticalAlignSpec>(
          label: "Vertical",
          value: spec.verticalAlign,
          width: 86,
          options: [for (var a in VerticalAlignSpec.values) (a, a.label)],
          onChanged: (v) {
            begin();
            onChanged(spec.copyWith(verticalAlign: v));
            commit();
          },
        ),
        if (includeCase)
          CanvasDropdown<TextCase>(
            label: "Case",
            value: spec.textCase,
            width: 96,
            options: [for (var c in TextCase.values) (c, c.label)],
            onChanged: (v) {
              begin();
              onChanged(spec.copyWith(textCase: v));
              commit();
            },
          ),
      ]),
      CanvasControlGroup(label: "Colour", children: [
        CanvasColorButton(
          label: "Text",
          color: spec.color,
          onChanged: (c) {
            begin();
            onChanged(spec.copyWith(color: c));
            commit();
          },
        ),
        CanvasNumberField(
          label: "Outline",
          value: spec.outlineWidth,
          min: 0,
          max: 60,
          decimals: 1,
          width: 54,
          onChanged: (v) => onChanged(spec.copyWith(outlineWidth: v)),
          onCommit: commit,
        ),
        CanvasColorButton(
          label: "Line",
          color: spec.outlineColor,
          onChanged: (c) {
            begin();
            onChanged(spec.copyWith(outlineColor: c));
            commit();
          },
        ),
        CanvasNumberField(
          label: "Shadow",
          value: spec.shadowBlur,
          min: 0,
          max: 120,
          width: 54,
          onChanged: (v) => onChanged(spec.copyWith(shadowBlur: v)),
          onCommit: commit,
        ),
        CanvasColorButton(
          label: "Colour",
          color: spec.shadowColor,
          onChanged: (c) {
            begin();
            onChanged(spec.copyWith(shadowColor: c));
            commit();
          },
        ),
      ]),
    ];

/// boxGroup is the shared frame controls: fill, border and padding.

/// boxGroup is the shared frame controls: fill, border and padding.
Widget boxGroup(BoxSpec box, ValueChanged<BoxSpec> onChanged,
        VoidCallback begin, VoidCallback commit,
        {String label = "Box"}) =>
    CanvasControlGroup(label: label, children: [
      CanvasColorButton(
        label: "Fill",
        color: box.fill,
        onChanged: (c) {
          begin();
          onChanged(box.copyWith(fill: c));
          commit();
        },
      ),
      CanvasNumberField(
        label: "Border",
        value: box.borderWidth,
        min: 0,
        max: 200,
        decimals: 1,
        width: 54,
        onChanged: (v) => onChanged(box.copyWith(borderWidth: v)),
        onCommit: commit,
      ),
      CanvasColorButton(
        label: "Colour",
        color: box.borderColor,
        onChanged: (c) {
          begin();
          onChanged(box.copyWith(borderColor: c));
          commit();
        },
      ),
      CanvasNumberField(
        label: "Radius",
        value: box.borderRadius,
        min: 0,
        max: 400,
        width: 54,
        onChanged: (v) => onChanged(box.copyWith(borderRadius: v)),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Padding",
        value: box.padding,
        min: 0,
        max: 400,
        width: 54,
        onChanged: (v) => onChanged(box.copyWith(padding: v)),
        onCommit: commit,
      ),
    ]);

/// valueDot is the diamond beside one animatable property.
///
/// Its own control rather than part of the pose diamond, because these are
/// real channels: a keyframe can pin a caption's slide without pinning where
/// its box sits, and the two are asked for at different moments.
Widget valueDot(CanvasController controller, CanvasElement e, String channel,
    String what, double value) {
  var animated = controller.document.isAnimated;
  var on = controller.hasValueKey(e, channel);
  return CanvasKeyframeDot(
    on: on,
    enabled: animated,
    tooltip: !animated
        ? "Give the canvas more than one frame to animate $what"
        : on
            ? "Remove the keyframe for $what here"
            : "Add a keyframe for $what here",
    onPressed: () {
      controller.beginInteraction();
      if (on) {
        controller.clearValueKey(e, channel);
      } else {
        controller.setValueKey(e, channel, value);
      }
      controller.endInteraction();
    },
  );
}

/// curveOptions is every line and path on the canvas, for text to ride.
///
/// Both kinds, because both are lines as far as a reader is concerned: a line
/// element is the straight or gently bowed one and a path is the drawn one,
/// and which of the two somebody reached for is not a distinction worth making
/// them remember when attaching a label to it.
List<(String, String)> curveOptions(CanvasController controller) => [
      ("", "Nothing"),
      for (var element in controller.document.elements)
        if (element is LineElement || element is PathElement)
          (element.id, element.name),
    ];

/// boxed draws a rule around a section and leaves a gap after it.
///
/// For the one section that is a panel rather than a row of controls. The rest
/// of these settings are captioned clusters that read as a list; a table with
/// its own scrollbars sitting in the middle of that list needs an edge, or
/// what follows it looks like part of it.
Widget boxed(BuildContext context, Widget child) {
  var theme = ThemeNotifier.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 14, top: 2),
    // Builder, because the context these settings are built with comes from
    // *above* the CanvasControlScope that says whether this is a column or a
    // band -- so asking it directly always answered "band".
    child: Builder(
      builder: (context) => Container(
        // The full width of the column, open or closed. The settings are a
        // Column of start-aligned children, so a box left to size itself
        // shrank to fit its heading -- and a closed section narrower than the
        // one above it does not read as a section, it reads as a button
        // somebody has left lying there.
        //
        // Only in a column. The band above the canvas scrolls sideways, where
        // there is no width to fill and asking for all of it is an error.
        width: CanvasControlScope.isStacked(context) ? double.infinity : null,
        padding: const EdgeInsets.fromLTRB(7, 2, 7, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colors.outlineVariant),
          color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.25),
        ),
        child: child,
      ),
    ),
  );
}
