import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';

// element_settings.dart is the controls for whichever element is selected.
//
// One function per element kind, each returning the groups that go into the
// settings bar. They are grouped by what somebody is thinking about rather
// than by which class the field is declared on -- so a text element's colour
// sits with its outline and its shadow under "Colour", not with its font size
// under "Type", even though all four are fields of the same TextSpec.
//
// Every control writes a transient edit and commits on release, so dragging a
// slider updates the canvas continuously and lands as one undo step. That
// pairing is why almost every control here passes both onChanged and
// onCommit; a control that only did the first would make an undo history
// forty steps long for one adjustment.

/// elementSettings is the groups for [element].
List<Widget> elementSettings(
  BuildContext context,
  CanvasController controller,
  CanvasElement element,
) {
  // Opening the undo step here rather than leaving it to each control.
  // beginInteraction is idempotent, and forgetting it is silent: a transient
  // edit made outside an interaction is never pushed onto the history, so the
  // control works and is simply not undoable. With forty controls in this
  // file, doing it once is the only way it stays true.
  void write(CanvasElement next) {
    controller.beginInteraction();
    controller.replaceElement(next, transient: true);
  }

  void commit() => controller.endInteraction();
  void begin() => controller.beginInteraction();

  return [
    _positionGroup(controller, element, write, begin, commit),
    ...switch (element) {
      TextElement e => _textSettings(controller, e, write, begin, commit),
      ShapeElement e => _shapeSettings(e, write, begin, commit),
      LineElement e => _lineSettings(controller, e, write, begin, commit),
      ImageElement e =>
        _imageSettings(context, controller, e, write, begin, commit),
      ChartElement e =>
        _chartSettings(context, controller, e, write, begin, commit),
      TableElement e => _tableSettings(e, write, begin, commit),
      ButtonElement e => _buttonSettings(controller, e, write, begin, commit),
      BackgroundElement e => [
          ProceduralSettings(
            spec: e.spec,
            onChanged: (spec) => write(e.copyWith(spec: spec)),
            onBegin: begin,
            onCommit: commit,
          ),
          CanvasControlGroup(label: "Panel", children: [
            CanvasNumberField(
              label: "Radius",
              value: e.cornerRadius,
              min: 0,
              max: 400,
              onChanged: (v) => write(e.copyWith(cornerRadius: v)),
              onCommit: commit,
            ),
          ]),
        ],
      TeamElement e => _teamSettings(e, write, begin, commit),
      PathElement e => _pathSettings(controller, e, write, begin, commit),
      _ => const <Widget>[],
    },
  ];
}

typedef _Write = void Function(CanvasElement);

/// _positionGroup is what every element has: where it is, how big, how turned,
/// and whether it can be touched.
Widget _positionGroup(CanvasController controller, CanvasElement e,
    _Write write, VoidCallback begin, VoidCallback commit) {
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
                opacity:
                    e.opacity == 0 ? v : (v / e.opacity).clamp(0.0, 1.0)))));
      },
      onCommit: commit,
    ),
    poseDot,
  ]);
}

/// _typeGroups is the shared type controls, used by every element that draws
/// words.
List<Widget> _typeGroups(
  TextSpec spec,
  ValueChanged<TextSpec> onChanged,
  VoidCallback begin,
  VoidCallback commit, {
  String label = "Type",
  bool includeCase = true,
}) =>
    [
      CanvasControlGroup(label: label, children: [
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

/// _boxGroup is the shared frame controls: fill, border and padding.
Widget _boxGroup(BoxSpec box, ValueChanged<BoxSpec> onChanged,
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

List<Widget> _textSettings(CanvasController controller, TextElement e,
    _Write write, VoidCallback begin, VoidCallback commit) {
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
    CanvasControlGroup(label: "Text", children: [
      CanvasToggle(
        label: "Fit to box",
        value: e.autoSize,
        onChanged: (v) => now(e.copyWith(autoSize: v)),
      ),
    ]),
    ..._typeGroups(
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
        options: _curveOptions(controller),
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
        _valueDot(
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
    _boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit),
  ];
}

/// _valueDot is the diamond beside one animatable property.
///
/// Its own control rather than part of the pose diamond, because these are
/// real channels: a keyframe can pin a caption's slide without pinning where
/// its box sits, and the two are asked for at different moments.
Widget _valueDot(CanvasController controller, CanvasElement e, String channel,
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

/// _curveOptions is every line and path on the canvas, for text to ride.
///
/// Both kinds, because both are lines as far as a reader is concerned: a line
/// element is the straight or gently bowed one and a path is the drawn one,
/// and which of the two somebody reached for is not a distinction worth making
/// them remember when attaching a label to it.
List<(String, String)> _curveOptions(CanvasController controller) => [
      ("", "Nothing"),
      for (var element in controller.document.elements)
        if (element is LineElement || element is PathElement)
          (element.id, element.name),
    ];

List<Widget> _shapeSettings(ShapeElement e, _Write write, VoidCallback begin,
        VoidCallback commit) =>
    [
      CanvasControlGroup(label: "Shape", children: [
        CanvasDropdown<ShapeKind>(
          label: "Shape",
          value: e.shape,
          width: 128,
          options: [for (var s in ShapeKind.values) (s, s.label)],
          onChanged: (v) {
            begin();
            write(e.copyWith(shape: v));
            commit();
          },
        ),
        CanvasColorButton(
          label: "Fill",
          color: e.fill,
          onChanged: (c) {
            begin();
            write(e.copyWith(fill: c));
            commit();
          },
        ),
        CanvasNumberField(
          label: "Stroke",
          value: e.strokeWidth,
          min: 0,
          max: 200,
          decimals: 1,
          width: 54,
          onChanged: (v) => write(e.copyWith(strokeWidth: v)),
          onCommit: commit,
        ),
        CanvasColorButton(
          label: "Colour",
          color: e.strokeColor,
          onChanged: (c) {
            begin();
            write(e.copyWith(strokeColor: c));
            commit();
          },
        ),
        CanvasNumberField(
          label: "Radius",
          value: e.cornerRadius,
          min: 0,
          max: 400,
          width: 54,
          onChanged: (v) => write(e.copyWith(cornerRadius: v)),
          onCommit: commit,
        ),
        if (e.shape.hasPoints) ...[
          CanvasNumberField(
            label: "Points",
            value: e.points.toDouble(),
            min: 3,
            max: 24,
            width: 50,
            onChanged: (v) => write(e.copyWith(points: v.round())),
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Depth",
            decimals: 2,
            width: 62,
            value: e.innerRatio,
            min: 0.05,
            max: 0.95,
            onChanged: (v) {
              begin();
              write(e.copyWith(innerRatio: v));
            },
            onCommit: commit,
          ),
        ],
      ]),
      CanvasControlGroup(label: "Label", children: [
        CanvasTextField(
          label: "Text inside",
          value: e.text,
          width: 150,
          onChanged: (v) => write(e.copyWith(text: v)),
          onCommit: commit,
        ),
      ]),
      // Only when it is a bubble: every one of these is meaningless on a star.
      if (e.shape == ShapeKind.speechBubble)
        CanvasControlGroup(label: "Bubble", children: [
          CanvasDropdown<BubbleBody>(
            label: "Body",
            value: e.bubble.body,
            width: 104,
            options: [for (var b in BubbleBody.values) (b, b.label)],
            onChanged: (v) {
              begin();
              write(e.copyWith(bubble: e.bubble.copyWith(body: v)));
              commit();
            },
          ),
          CanvasDropdown<BubbleTail>(
            label: "Tail",
            value: e.bubble.tail,
            width: 104,
            options: [for (var t in BubbleTail.values) (t, t.label)],
            onChanged: (v) {
              begin();
              write(e.copyWith(bubble: e.bubble.copyWith(tail: v)));
              commit();
            },
          ),
          if (e.bubble.tail != BubbleTail.none) ...[
            // All the way round, rather than the bottom-left corner it used
            // to be nailed to.
            CanvasNumberField(
              key: const ValueKey("bubbleTailAngle"),
              label: "Points",
              value: e.bubble.tailAngle,
              min: -360,
              max: 360,
              width: 58,
              suffix: "°",
              onChanged: (v) {
                begin();
                write(e.copyWith(bubble: e.bubble.copyWith(tailAngle: v)));
              },
              onCommit: commit,
            ),
            CanvasNumberField(
              label: "Length",
              decimals: 2,
              width: 62,
              value: e.bubble.tailLength,
              min: 0.05,
              max: 1.2,
              onChanged: (v) {
                begin();
                write(e.copyWith(bubble: e.bubble.copyWith(tailLength: v)));
              },
              onCommit: commit,
            ),
            CanvasNumberField(
              label: "Width",
              decimals: 2,
              width: 62,
              value: e.bubble.tailWidth,
              min: 0.05,
              max: 1,
              onChanged: (v) {
                begin();
                write(e.copyWith(bubble: e.bubble.copyWith(tailWidth: v)));
              },
              onCommit: commit,
            ),
            if (e.bubble.tail == BubbleTail.curved)
              CanvasNumberField(
                label: "Curl",
                decimals: 2,
                width: 62,
                value: e.bubble.curl,
                min: -1.5,
                max: 1.5,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(bubble: e.bubble.copyWith(curl: v)));
                },
                onCommit: commit,
              ),
          ],
        ]),
      // The label's type, and only when there is a label to set.
      if (e.text.isNotEmpty)
        ..._typeGroups(e.textSpec, (spec) => write(e.copyWith(textSpec: spec)),
            begin, commit,
            label: "Label type"),
    ];

List<Widget> _lineSettings(CanvasController controller, LineElement e,
    _Write write, VoidCallback begin, VoidCallback commit) {
  void now(LineElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    CanvasControlGroup(label: "Line", children: [
      CanvasColorButton(
        label: "Colour",
        color: e.color,
        onChanged: (c) {
          begin();
          write(e.copyWith(color: c));
          commit();
        },
      ),
      CanvasNumberField(
        label: "Width",
        value: e.strokeWidth,
        min: 0.2,
        max: 200,
        decimals: 1,
        width: 54,
        onChanged: (v) => write(e.copyWith(strokeWidth: v)),
        onCommit: commit,
      ),
      CanvasDropdown<LineStrokeCap>(
        label: "Stroke end",
        value: e.cap,
        width: 92,
        options: [for (var c in LineStrokeCap.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(cap: v)),
      ),
      CanvasDropdown<LineEnd>(
        label: "Start",
        value: e.startEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(startEnd: v)),
      ),
      CanvasDropdown<LineEnd>(
        label: "End",
        value: e.endEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(endEnd: v)),
      ),
      CanvasNumberField(
        label: "End size",
        value: e.endSize,
        min: 0.2,
        max: 8,
        decimals: 1,
        width: 58,
        onChanged: (v) {
          begin();
          write(e.copyWith(endSize: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Dash",
        value: e.dash,
        min: 0,
        max: 400,
        width: 50,
        onChanged: (v) => write(e.copyWith(dash: v)),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Curve",
        decimals: 2,
        width: 62,
        value: controller.valueAt(e, KeyframeChannel.bow, e.curvature),
        min: -1,
        max: 1,
        onChanged: (v) {
          begin();
          if (controller.hasValueKey(e, KeyframeChannel.bow)) {
            controller.setValueKey(e, KeyframeChannel.bow, v);
            return;
          }
          write(e.copyWith(curvature: v));
        },
        onCommit: commit,
      ),
      _valueDot(
          controller, e, KeyframeChannel.bow, "the line's curve", e.curvature),
      CanvasIconButton(
        icon: Icons.swap_vert,
        tooltip: "Flip which way the line runs",
        active: e.flipped,
        onPressed: () {
          begin();
          write(e.copyWith(flipped: !e.flipped));
          commit();
        },
      ),
    ]),
  ];
}

List<Widget> _imageSettings(BuildContext context, CanvasController controller,
    ImageElement e, _Write write, VoidCallback begin, VoidCallback commit) {
  void now(ImageElement next) {
    begin();
    write(next);
    commit();
  }

  // Putting a picture in also gives the box the picture's proportions. A
  // photograph dropped into whatever rectangle happened to be there is either
  // cropped by the fit or squashed by it, and the first thing anybody did was
  // drag the handles until it looked right -- which is arithmetic the picture
  // itself already knows the answer to. It only ever shrinks the box: growing
  // one could push it off the canvas, and the reader asked for a picture, not
  // for the layout to move.
  Future<void> use(String id) async {
    var next = e.copyWith(assetId: id);
    var size = await pictureSize(id);
    if (size != null) next = fitToPicture(next, size);
    now(next);
  }

  return [
    CanvasControlGroup(label: "Picture", children: [
      // The one control this element did not have, and without which it does
      // nothing at all: somewhere to put a picture in it.
      CanvasIconButton(
        icon: e.hasImage ? Icons.image_outlined : Icons.add_photo_alternate,
        tooltip: e.hasImage ? "Replace this picture" : "Add a picture",
        onPressed: () async {
          var id = await pickCanvasImage(context);
          if (id != null) await use(id);
        },
      ),
      // The other half of a shared picture store: the bytes have always been
      // shared between canvases, but nothing ever showed what was in there, so
      // the only way to put the same badge on a second canvas was to go and
      // find the file again.
      CanvasIconButton(
        icon: Icons.photo_library_outlined,
        tooltip: "Use a picture you have already added",
        onPressed: () async {
          var id = await showRecentPictures(context);
          if (id != null) await use(id);
        },
      ),
      // The size controls are offered on the way in, but only above half a
      // megabyte -- so anybody who wanted them for a smaller picture, or who
      // took a size on the way in and thought better of it, had nowhere to
      // go. This is that door, and it is the app's own width, quality and
      // format controls, the same ones an embedded picture goes through.
      if (e.hasImage)
        CanvasIconButton(
          icon: Icons.compress,
          tooltip: "Change this picture's size and quality",
          onPressed: () async {
            var id = await compressCanvasPicture(context, e.assetId);
            if (id != null) await use(id);
          },
        ),
      if (e.hasImage)
        CanvasIconButton(
          icon: Icons.hide_image_outlined,
          tooltip: "Take the picture out",
          onPressed: () => now(e.copyWith(assetId: "")),
        ),
      CanvasIconButton(
        icon: e.lockAspect ? Icons.link : Icons.link_off,
        tooltip: e.lockAspect
            ? "Proportions are held while it is resized — Shift to stretch"
            : "It can be stretched — Shift to hold its proportions",
        active: e.lockAspect,
        onPressed: () {
          begin();
          write(e.copyWith(lockAspect: !e.lockAspect));
          commit();
        },
      ),
      CanvasDropdown<ImageFit>(
        label: "Fit",
        value: e.fit,
        width: 106,
        options: [for (var f in ImageFit.values) (f, f.label)],
        onChanged: (v) {
          begin();
          write(e.copyWith(fit: v));
          commit();
        },
      ),
      CanvasNumberField(
        label: "Saturation",
        decimals: 2,
        width: 62,
        value: e.saturation,
        min: 0,
        max: 3,
        onChanged: (v) {
          begin();
          write(e.copyWith(saturation: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Brightness",
        decimals: 2,
        width: 62,
        value: e.brightness,
        min: 0,
        max: 3,
        onChanged: (v) {
          begin();
          write(e.copyWith(brightness: v));
        },
        onCommit: commit,
      ),
    ]),
    CanvasControlGroup(label: "Remove background", children: [
      // The brush comes before the method, and outside the check for whether
      // anything is being removed yet.
      //
      // It used to be inside it, which made it unreachable on exactly the
      // picture it is for: a fresh image has no method chosen and no strokes,
      // so nothing was being removed, so the brushes were hidden -- and the
      // only way to reach the tool that needs no method was to choose a
      // method first.
      //
      // It is first because it is the tool. Every automatic method has
      // photographs it cannot do, and on those this is not a refinement.
      CanvasIconButton(
        icon: Icons.auto_fix_high,
        tooltip: controller.retouch == RetouchBrush.erase
            ? "Stop rubbing out"
            : "Rub the background out by hand",
        active: controller.retouch == RetouchBrush.erase,
        onPressed: () => controller.retouch =
            controller.retouch == RetouchBrush.erase
                ? RetouchBrush.off
                : RetouchBrush.erase,
      ),
      // The tool for the job the brush is bad at: a large, awkward,
      // many-coloured area. Draw a rough line around what is being kept, let
      // go, and everything the picture's own edge can reach without crossing
      // that line goes -- whatever colour any of it is.
      CanvasIconButton(
        icon: Icons.content_cut,
        tooltip: controller.retouch == RetouchBrush.cutAround
            ? "Stop cutting around"
            : "Cut around — draw a line around what you are keeping",
        active: controller.retouch == RetouchBrush.cutAround,
        onPressed: () => controller.retouch =
            controller.retouch == RetouchBrush.cutAround
                ? RetouchBrush.off
                : RetouchBrush.cutAround,
      ),
      CanvasIconButton(
        icon: Icons.healing,
        tooltip: controller.retouch == RetouchBrush.restore
            ? "Stop putting back"
            : "Put back what was taken by mistake",
        active: controller.retouch == RetouchBrush.restore,
        onPressed: () => controller.retouch =
            controller.retouch == RetouchBrush.restore
                ? RetouchBrush.off
                : RetouchBrush.restore,
      ),
      // A drawn stroke waits here until it is applied, so the settings above
      // can be adjusted against it and the result watched on the canvas.
      if (controller.hasPendingStroke) ...[
        Padding(
          padding: const EdgeInsets.only(top: controlLabelHeight, right: 6),
          child: SizedBox(
            height: controlHeight,
            child: Center(
              child: Txt.S(controller.pendingTeaches
                  ? "Mark drawn — adjust the brush, then keep it"
                  : "Stroke drawn — adjust the brush, then apply it"),
            ),
          ),
        ),
        CanvasIconButton(
          icon: Icons.check,
          tooltip: "Apply this stroke",
          active: true,
          onPressed: controller.applyStroke,
        ),
        CanvasIconButton(
          icon: Icons.close,
          tooltip: "Throw this stroke away",
          onPressed: controller.discardStroke,
        ),
      ],
      if (controller.retouch.on) ...[
        CanvasNumberField(
          label: "Brush",
          min: 0.005,
          max: 0.6,
          decimals: 3,
          width: 62,
          value: controller.brushSize,
          onChanged: (v) => controller.brushSize = v,
        ),
        // Only for the brushes that mark the picture. A hint is a sample
        // and is taken exactly where it was drawn.
        if (!controller.retouch.teaches) ...[
          CanvasNumberField(
            label: "Hardness",
            min: 0.05,
            max: 1,
            decimals: 2,
            width: 62,
            value: controller.brushHardness,
            onChanged: (v) => controller.brushHardness = v,
          ),
          // Not for putting back: clinging finds the edge of a background,
          // and what is being put back is the subject, which is every colour
          // there is.
          // Neither for putting back nor for cutting around. Clinging finds
          // the edge of a background by colour; what is being put back is the
          // subject, and a boundary does not care what colour anything is.
          if (!controller.retouch.keeps && !controller.retouch.fills)
          CanvasNumberField(
            label: "Cling",
            min: 0,
            max: 0.6,
            decimals: 3,
            width: 62,
            value: controller.brushSnap,
            onChanged: (v) => controller.brushSnap = v,
          ),
          // Which side of the boundary goes. Read when the stroke is
          // applied rather than when it was drawn, so it can be turned over
          // with a stroke still held and the preview redraws.
          if (controller.retouch.fills)
            CanvasIconButton(
              icon: controller.cutInside
                  ? Icons.flip_to_back
                  : Icons.flip_to_front,
              tooltip: controller.cutInside
                  ? "Taking what is inside the line — press to take what is "
                      "outside"
                  : "Taking what is outside the line — press to take what is "
                      "inside",
              active: controller.cutInside,
              onPressed: () => controller.cutInside = !controller.cutInside,
            ),
          // The magnet. Cling wants a number nobody can read off a
          // photograph, so this reads it off the picture instead -- see
          // CanvasController.magnetiseCling.
          if (!controller.retouch.keeps &&
              !controller.retouch.fills &&
              controller.hasPendingStroke)
            CanvasIconButton(
              icon: Icons.my_location,
              tooltip: "Find the edge this stroke crossed and cling to it",
              onPressed: () async {
                var found = await controller.magnetiseCling();
                if (!found) {
                  // Nothing to say it wrongly: a stroke drawn entirely on the
                  // background has no edge in it, and pretending otherwise
                  // would cut the background in half.
                  controller.brushSnap = 0;
                }
              },
            ),
        ],
      ],
      if (e.removal.strokes.isNotEmpty) ...[
        CanvasIconButton(
          icon: Icons.undo,
          tooltip: "Undo the last brush stroke",
          onPressed: () {
            begin();
            write(e.copyWith(
                removal: e.removal.copyWith(
                    strokes: e.removal.strokes
                        .sublist(0, e.removal.strokes.length - 1))));
            commit();
          },
        ),
        CanvasIconButton(
          icon: Icons.layers_clear_outlined,
          tooltip: "Clear every brush stroke",
          onPressed: () {
            begin();
            write(e.copyWith(removal: e.removal.copyWith(strokes: const [])));
            commit();
          },
        ),
      ],
      CanvasDropdown<RemovalMode>(
        label: "Method",
        value: e.removal.mode,
        width: 140,
        options: [for (var m in RemovalMode.values) (m, m.label)],
        onChanged: (v) {
          begin();
          write(e.copyWith(removal: e.removal.copyWith(mode: v)));
          commit();
        },
      ),
      if (e.removal.mode == RemovalMode.chromaKey)
        CanvasColorButton(
          label: "Key",
          color: e.removal.keyColor,
          allowAlpha: false,
          onChanged: (c) {
            begin();
            write(e.copyWith(removal: e.removal.copyWith(keyColor: c)));
            commit();
          },
        ),
      if (e.removal.mode == RemovalMode.luminance)
        CanvasNumberField(
          label: "Threshold",
          min: 0,
          max: 1,
          decimals: 2,
          width: 62,
          value: e.removal.threshold,
          onChanged: (v) {
            begin();
            write(e.copyWith(removal: e.removal.copyWith(threshold: v)));
          },
          onCommit: commit,
        ),
      // A method's own settings, and only while one is chosen. They were
      // shown whenever anything was being removed -- which includes a
      // picture the brush alone has been used on -- so somebody working by
      // hand was offered a tolerance and a softness that nothing reads.
      if (e.removal.mode != RemovalMode.none) ...[
        // Edge first, because on a photograph it is the control that does
        // the work: it says how sharply the picture has to change for the
        // flood to treat it as the end of the background. Tolerance is the
        // runaway guard behind it.
        if (e.removal.mode == RemovalMode.cornerFlood)
          CanvasNumberField(
            label: "Edge",
            min: 0.005,
            max: 0.5,
            decimals: 3,
            width: 62,
            value: e.removal.edge,
            onChanged: (v) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(edge: v)));
            },
            onCommit: commit,
          ),
        // Every method but the brightness one, which cuts at a threshold
        // and has no use for it.
        if (e.removal.mode != RemovalMode.luminance)
          CanvasNumberField(
            label: e.removal.mode == RemovalMode.cornerFlood
                ? "Spread"
                : "Tolerance",
            min: 0,
            decimals: 2,
            width: 62,
            value: e.removal.tolerance,
            max: 1,
            onChanged: (v) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(tolerance: v)));
            },
            onCommit: commit,
          ),
        CanvasNumberField(
          label: "Softness",
          min: 0,
          decimals: 2,
          width: 62,
          value: e.removal.softness,
          max: 0.3,
          onChanged: (v) {
            begin();
            write(e.copyWith(removal: e.removal.copyWith(softness: v)));
          },
          onCommit: commit,
        ),
        // Marking, when the method is the one that learns from it. These
        // two are the whole interface to it: mark some background, mark
        // some subject, and the numbers below are a fine adjustment rather
        // than the way in.
        if (e.removal.mode == RemovalMode.learn) ...[
          CanvasIconButton(
            icon: Icons.format_paint_outlined,
            tooltip: controller.retouch == RetouchBrush.markBackground
                ? "Stop marking background"
                : "Mark some background — draw over a few parts that should "
                    "go",
            active: controller.retouch == RetouchBrush.markBackground,
            onPressed: () => controller.retouch =
                controller.retouch == RetouchBrush.markBackground
                    ? RetouchBrush.off
                    : RetouchBrush.markBackground,
          ),
          CanvasIconButton(
            icon: Icons.person_outline,
            tooltip: controller.retouch == RetouchBrush.markSubject
                ? "Stop marking the subject"
                : "Mark the subject — draw over a few parts that should "
                    "stay",
            active: controller.retouch == RetouchBrush.markSubject,
            onPressed: () => controller.retouch =
                controller.retouch == RetouchBrush.markSubject
                    ? RetouchBrush.off
                    : RetouchBrush.markSubject,
          ),
          if (e.removal.hints.isNotEmpty)
            CanvasIconButton(
              icon: Icons.layers_clear_outlined,
              tooltip: "Forget the marks and start again",
              onPressed: () {
                begin();
                write(e.copyWith(removal: e.removal.copyWith(hints: const [])));
                commit();
              },
            ),
          Padding(
            padding: const EdgeInsets.only(top: controlLabelHeight, right: 6),
            child: SizedBox(
              height: controlHeight,
              child: Center(
                child: Txt.S(e.removal.backgroundHints.isEmpty ||
                        e.removal.subjectHints.isEmpty
                    ? "Mark both, then it can compare them"
                    : "${e.removal.hints.length} marks"),
              ),
            ),
          ),
        ],
        CanvasToggle(
          label: "Invert",
          value: e.removal.invert,
          onChanged: (v) {
            begin();
            write(e.copyWith(removal: e.removal.copyWith(invert: v)));
            commit();
          },
        ),
      ],
    ]),
    if (e.hasImage)
      CanvasControlGroup(label: "Frame", children: [
        CanvasDropdown<String>(
          label: "Cut to",
          value: e.frame?.name ?? "",
          width: 128,
          options: [
            ("", "Rectangle"),
            for (var k in ShapeKind.values) (k.name, k.label),
          ],
          onChanged: (v) => now(v.isEmpty
              ? e.copyWith(clearFrame: true)
              : e.copyWith(frame: ShapeKind.fromName(v))),
        ),
      ]),
    if (e.hasImage)
      CanvasControlGroup(label: "Crop", children: [
        for (var (label, value, apply)
            in <(String, double, ImageCrop Function(double))>[
          ("Left", e.crop.left, (v) => e.crop.copyWith(left: v)),
          ("Top", e.crop.top, (v) => e.crop.copyWith(top: v)),
          ("Right", e.crop.right, (v) => e.crop.copyWith(right: v)),
          ("Bottom", e.crop.bottom, (v) => e.crop.copyWith(bottom: v)),
        ])
          CanvasNumberField(
            label: label,
            min: 0,
            max: 1,
            decimals: 2,
            width: 62,
            value: value,
            onChanged: (v) {
              begin();
              write(e.copyWith(crop: apply(v)));
            },
            onCommit: commit,
          ),
        CanvasIconButton(
          icon: Icons.crop_free,
          tooltip: "Show the whole picture again",
          onPressed: () => now(e.copyWith(crop: const ImageCrop())),
        ),
      ]),
    if (e.hasImage)
      CanvasControlGroup(label: "Look", children: [
        CanvasDropdown<ImageFilterPreset>(
          label: "Filter",
          value: e.filter,
          width: 116,
          options: [for (var f in ImageFilterPreset.values) (f, f.label)],
          onChanged: (v) => now(e.copyWith(filter: v)),
        ),
        CanvasDropdown<OverlayBlend>(
          label: "Overlay",
          value: e.blend,
          width: 116,
          options: [for (var b in OverlayBlend.values) (b, b.label)],
          onChanged: (v) => now(e.copyWith(blend: v)),
        ),
        if (e.blend != OverlayBlend.none)
          CanvasColorButton(
            key: const ValueKey("imageOverlayColour"),
            label: "Colour",
            color: e.overlay,
            onChanged: (c) => now(e.copyWith(overlay: c)),
          ),
      ]),
    // Not part of "Remove background", though that is what it is for. It
    // traces the alpha channel and does not care how the alpha got there, so
    // it works just as well on a picture that arrived with one -- and burying
    // it in the removal group would say otherwise.
    if (e.hasImage)
      CanvasControlGroup(label: "Outline", children: [
        CanvasNumberField(
          label: "Width",
          min: 0,
          max: 60,
          decimals: 1,
          width: 62,
          value: e.outline.width,
          onChanged: (v) {
            begin();
            write(e.copyWith(outline: e.outline.copyWith(width: v)));
          },
          onCommit: commit,
        ),
        if (e.outline.width > 0) ...[
          CanvasColorButton(
            key: const ValueKey("imageOutlineColour"),
            label: "Colour",
            color: e.outline.color,
            onChanged: (c) => now(e.copyWith(outline: e.outline.copyWith(
                color: c))),
          ),
          CanvasDropdown<OutlineStyle>(
            label: "Style",
            value: e.outline.style,
            width: 116,
            options: [for (var o in OutlineStyle.values) (o, o.label)],
            onChanged: (v) =>
                now(e.copyWith(outline: e.outline.copyWith(style: v))),
          ),
          CanvasNumberField(
            label: "Feather",
            min: 0,
            max: 1,
            decimals: 2,
            width: 62,
            value: e.outline.feather,
            onChanged: (v) {
              begin();
              write(e.copyWith(outline: e.outline.copyWith(feather: v)));
            },
            onCommit: commit,
          ),
        ],
      ]),
    // "Border", not "Frame". Frame is now the shape the picture is cut to,
    // and one word for the outline round a rectangle and for the rectangle
    // being a circle is a word doing two jobs.
    _boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
        label: "Border"),
  ];
}

/// _boxed draws a rule around a section and leaves a gap after it.
///
/// For the one section that is a panel rather than a row of controls. The rest
/// of these settings are captioned clusters that read as a list; a table with
/// its own scrollbars sitting in the middle of that list needs an edge, or
/// what follows it looks like part of it.
Widget _boxed(BuildContext context, Widget child) {
  var theme = ThemeNotifier.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 14, top: 2),
    child: Container(
      padding: const EdgeInsets.fromLTRB(7, 2, 7, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colors.outlineVariant),
        color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.25),
      ),
      child: child,
    ),
  );
}

List<Widget> _chartSettings(BuildContext context, CanvasController controller,
    ChartElement e, _Write write, VoidCallback begin, VoidCallback commit) {
  void now(ChartElement next) {
    begin();
    write(next);
    commit();
  }

  void writeData(ChartData data) => write(e.copyWith(data: data));

  /// labelControls is the shared shape of the title's and the description's
  /// settings: the words, a switch, and -- once it has been moved off the
  /// chart's own arrangement -- where it sits.
  ///
  /// Placing is a button rather than a mode. A chart lays its title out at the
  /// top and gives the rest to the plot, which is right until somebody wants
  /// it somewhere else, and there is no set of automatic rules that covers
  /// both. So the label is either the chart's to place or the reader's, and
  /// the button says which.
  List<Widget> labelControls(
    String text,
    ChartLabel box,
    ChartLabel whenPlaced,
    double size,
    ChartElement Function(String) withText,
    ChartElement Function(ChartLabel) withBox,
    ChartElement Function(double) withSize,
  ) =>
      [
        // No caption of its own: the group above it is already called Title.
        CanvasTextField(
          label: "",
          value: text,
          width: 160,
          onChanged: (v) => write(withText(v)),
          onCommit: commit,
        ),
        CanvasToggle(
          label: "Show",
          value: box.show,
          onChanged: (v) => now(withBox(box.copyWith(show: v))),
        ),
        if (box.show)
          CanvasNumberField(
            label: "Size",
            min: 4,
            max: 400,
            decimals: 1,
            width: 58,
            value: size,
            onChanged: (v) {
              begin();
              write(withSize(v));
            },
            onCommit: commit,
          ),
        if (box.show && text.isNotEmpty)
          CanvasIconButton(
            icon: box.placed ? Icons.push_pin : Icons.auto_awesome_mosaic,
            tooltip: box.placed
                ? "Put it back where the chart wants it"
                : "Place it yourself — then drag it on the canvas",
            active: box.placed,
            // Placed where the chart would have put it rather than in the
            // corner. Both labels used to land on 0.02, 0.02 -- so placing
            // the second put it exactly over the first, and since the
            // description is drawn last it looked as though the description
            // had gone above the title.
            onPressed: () => now(withBox(
                box.placed ? box.copyWith(unplace: true) : whenPlaced)),
          ),
        // The words and the switches, then where it sits. Four coordinates
        // sharing a line with a text field and two buttons is four numbers
        // nobody can scan.
        if (box.show && box.placed) const CanvasLineBreak(),
        if (box.show && box.placed)
          for (var (label, value, apply)
              in <(String, double, ChartLabel Function(double))>[
            ("X", box.x, (v) => box.copyWith(x: v)),
            ("Y", box.y, (v) => box.copyWith(y: v)),
            ("W", box.width, (v) => box.copyWith(width: v)),
            ("H", box.height, (v) => box.copyWith(height: v)),
          ])
            CanvasNumberField(
              label: label,
              min: -1,
              max: 2,
              decimals: 3,
              width: 58,
              value: value,
              onChanged: (v) {
                begin();
                write(withBox(apply(v)));
              },
              onCommit: commit,
            ),
      ];

  // Whether Smooth means anything here: the chart's own type, or any series
  // that has overridden it. Offered otherwise, it was a switch that did
  // nothing on a bar chart, which is indistinguishable from a broken one.
  var smoothable = e.type.usesSmooth ||
      e.data.series.any((s) => s.typeIn(e.type).usesSmooth);

  return [
    // "Type", not "Chart". The settings are already headed with the element's
    // own name, so a group called Chart under a heading called Chart said the
    // word twice and the dropdown under it said a third.
    CanvasControlGroup(label: "Type", children: [
      CanvasDropdown<ChartType>(
        label: "",
        value: e.type,
        width: 132,
        options: [for (var t in ChartType.values) (t, t.label)],
        onChanged: (v) => now(e.copyWith(type: v)),
      ),
      // Said here rather than left to be discovered. Grouped and stacked bars
      // draw exactly what plain bars draw until there is a second series to
      // group or stack, so choosing one on a one-series chart looks like the
      // setting doing nothing at all.
      if (e.type.needsMultipleSeries && e.data.series.length < 2)
        const CanvasHint(
            "Grouped and stacked bars need more than one series -- with one "
            "they draw exactly what plain bars draw. Add a second series "
            "under Series below."),
    ]),
    CanvasControlGroup(label: "Title", children: [
      ...labelControls(
          e.title,
          e.titleBox,
          defaultTitlePlacement,
          e.titleSpec.fontSize,
          (v) => e.copyWith(title: v),
          (b) => e.copyWith(titleBox: b),
          (v) => e.copyWith(titleSpec: e.titleSpec.copyWith(fontSize: v))),
    ]),
    CanvasControlGroup(label: "Description", children: [
      // Under the title, not on top of it. A description above a title is
      // almost never what anybody means, and two labels placed at the same
      // corner is what that looked like.
      // Its own size, not the label size it starts at. Sharing meant making
      // the description bigger made the numbers up the side of the chart
      // bigger with it.
      ...labelControls(
          e.description,
          e.descriptionBox,
          defaultDescriptionPlacement(e.titleBox, e.title.isNotEmpty),
          e.descriptionText.fontSize,
          (v) => e.copyWith(description: v),
          (b) => e.copyWith(descriptionBox: b),
          (v) => e.copyWith(
              descriptionSpec: e.descriptionText.copyWith(fontSize: v))),
    ]),
    // Its own section, opened and closed. The numbers are the longest thing in
    // these settings and the least often changed once they are right, so they
    // were pushing everything else off the bottom of the panel.
    // Boxed, and with room after it. Open, it is a table and three rows of
    // series settings in the middle of a column of ordinary controls, and
    // without an edge of its own it ran straight into the axis settings under
    // it -- so the first thing under the table looked like part of the table.
    _boxed(
      context,
      CanvasExpander(
        label: "Data",
        trailing: "${e.data.categories.length} rows, "
            "${e.data.series.length} series",
        initiallyOpen: true,
        children: [
          ChartDataEditor(
            data: e.data,
            onChanged: (data) {
              begin();
              writeData(data);
            },
            onCommit: commit,
          ),
        ],
      ),
    ),
    // Its own section, like the data. An animation is a handful of choices
    // made once and then left alone, and open by default they were four more
    // rows between the numbers and the axes.
    _boxed(
      context,
      CanvasExpander(
        label: "Animation",
        trailing: e.animation.on ? e.animation.preset.label : null,
        children: [
          CanvasControlGroup(label: "Preset", children: [
            const CanvasHint(
                "Choosing one draws the chart on over two seconds and puts a "
                "keyframe at each end of it on the timeline. Drag those to "
                "decide how long it takes and when it happens."),
            const CanvasLineBreak(),
            for (var preset in ChartAnimationPreset.values)
              if (e.type.isCircular
                  ? preset.suitsCircular
                  : preset.suitsCartesian)
                CanvasToggle(
                  label: preset.label,
                  value: e.animation.preset == preset,
                  // A press applies it and lays the keyframes together: a
                  // preset with nothing pinning the reveal channel draws
                  // exactly what a still chart draws.
                  onChanged: (_) =>
                      controller.applyChartAnimation(e, preset),
                ),
          ]),
          if (e.animation.on)
            CanvasControlGroup(label: "Timing", children: [
              // Only where there is more than one thing to space out. A wipe
              // and a sweep are one edge crossing everything at once.
              if (e.animation.preset.staggers)
                CanvasNumberField(
                  label: "Gap",
                  min: 0,
                  max: 4,
                  decimals: 2,
                  width: 62,
                  value: e.animation.gap,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(
                        animation: e.animation.copyWith(gap: v)));
                  },
                  onCommit: commit,
                ),
              if (e.animation.preset.staggers)
                const CanvasHint(
                    "How long after one starts before the next does, as a "
                    "share of one item's own movement. 1 is strictly one "
                    "after another; below 1 they overlap; above 1 leaves a "
                    "pause between them."),
              CanvasDropdown<ChartEase>(
                label: "End curve",
                value: e.animation.ease,
                width: 118,
                options: [for (var c in ChartEase.values) (c, c.label)],
                onChanged: (v) {
                  begin();
                  write(e.copyWith(animation: e.animation.copyWith(ease: v)));
                  commit();
                },
              ),
            ]),
        ],
      ),
    ),
    // A pie has no axes, so it is not offered any. The four switches below are
    // its own group for the same reason: a group called Axes holding nothing
    // but Legend and Values is a heading that lies.
    if (!e.type.isCircular)
      CanvasControlGroup(label: "Axes", children: [
        CanvasTextField(
          label: "X label",
          value: e.xAxisLabel,
          width: 108,
          onChanged: (v) => write(e.copyWith(xAxisLabel: v)),
          onCommit: commit,
        ),
        CanvasTextField(
          label: "Y label",
          value: e.yAxisLabel,
          width: 108,
          onChanged: (v) => write(e.copyWith(yAxisLabel: v)),
          onCommit: commit,
        ),
        // The two axis titles are text, and the switches below are switches.
        // On one line the first switch sat on the end of the Y label's row
        // and read as part of it.
        const CanvasLineBreak(),
        CanvasToggle(
          label: "Grid",
          value: e.showGrid,
          onChanged: (v) => now(e.copyWith(showGrid: v)),
        ),
        CanvasToggle(
          label: "Axes",
          value: e.showAxes,
          onChanged: (v) => now(e.copyWith(showAxes: v)),
        ),
      ]),
    CanvasControlGroup(label: "Values", children: [
      CanvasToggle(
        label: "On the chart",
        value: e.showValues,
        onChanged: (v) => now(e.copyWith(showValues: v)),
      ),
      // Rings a few pixels thick have nowhere to write a number and no axis to
      // read one against, so theirs go in the key -- which is no use with the
      // key switched off.
      if (e.type == ChartType.radialBar && !(e.showLegend && e.legend.values))
        const CanvasHint(
            "A radial bar has no room to write a number on and no axis to "
            "read one against, so its values go in the legend. Switch the "
            "legend on, and its values with it, to see them."),
    ]),
    _boxed(
      context,
      CanvasExpander(
        label: "Legend",
        trailing: e.showLegend ? e.legend.placement.label : "off",
        children: [
          CanvasControlGroup(label: "Legend", bandOnlyLabel: true, children: [
            CanvasToggle(
              label: "Show",
              value: e.showLegend,
              onChanged: (v) => now(e.copyWith(showLegend: v)),
            ),
            if (e.showLegend) ...[
              // Its own switch, not the chart's. A bar chart may want numbers
              // on its bars and a key without them, and a radial bar has
              // nowhere to put a number except the key.
              CanvasToggle(
                label: "Values",
                value: e.legend.values,
                onChanged: (v) =>
                    now(e.copyWith(legend: e.legend.copyWith(values: v))),
              ),
              const CanvasLineBreak(),
              CanvasDropdown<LegendPlacement>(
                label: "Place",
                value: e.legend.placement,
                width: 104,
                options: [for (var p in LegendPlacement.values) (p, p.label)],
                onChanged: (v) =>
                    now(e.copyWith(legend: e.legend.copyWith(placement: v))),
              ),
              CanvasDropdown<bool>(
                label: "Along",
                value: e.legend.vertical,
                width: 104,
                options: const [(false, "A row"), (true, "A column")],
                onChanged: (v) =>
                    now(e.copyWith(legend: e.legend.copyWith(vertical: v))),
              ),
              const CanvasLineBreak(),
              CanvasNumberField(
                label: "Size",
                min: 0.3,
                max: 4,
                decimals: 2,
                width: 58,
                value: e.legend.scale,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(legend: e.legend.copyWith(scale: v)));
                },
                onCommit: commit,
              ),
              CanvasNumberField(
                label: "Spacing",
                min: 0,
                max: 6,
                decimals: 2,
                width: 62,
                value: e.legend.spacing,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(legend: e.legend.copyWith(spacing: v)));
                },
                onCommit: commit,
              ),
              const CanvasHint(
                  "Size is measured against the chart's own label size, so "
                  "the key stays in proportion when those are changed. "
                  "Spacing is the gap between one entry and the next."),
            ],
          ]),
        ],
      ),
    ),
    CanvasControlGroup(label: "Style", children: [
      CanvasColorButton(
        label: "Grid",
        color: e.gridColor,
        onChanged: (c) => now(e.copyWith(gridColor: c)),
      ),
      CanvasNumberField(
        label: "Bar gap",
        min: 0,
        decimals: 2,
        width: 62,
        value: e.barGap,
        max: 0.9,
        onChanged: (v) {
          begin();
          write(e.copyWith(barGap: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Bar radius",
        value: e.barRadius,
        min: 0,
        max: 100,
        width: 54,
        onChanged: (v) => write(e.copyWith(barRadius: v)),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Stroke",
        value: e.strokeWidth,
        min: 0.5,
        max: 40,
        decimals: 1,
        width: 54,
        onChanged: (v) => write(e.copyWith(strokeWidth: v)),
        onCommit: commit,
      ),
      // Only where there is a line to curve. Bars have nothing to curve and a
      // scatter is unconnected by definition.
      if (smoothable)
        CanvasToggle(
          label: "Smooth",
          value: e.smooth,
          onChanged: (v) => now(e.copyWith(smooth: v)),
        ),
    ]),
  ];
}

List<Widget> _tableSettings(TableElement e, _Write write, VoidCallback begin,
        VoidCallback commit) =>
    [
      CanvasControlGroup(label: "Table", children: [
        CanvasTextField(
          label: "Rows (paste a table)",
          value: e.asText(),
          width: 280,
          maxLines: 2,
          onChanged: (v) => write(e.copyWith(rows: TableElement.parseRows(v))),
          onCommit: commit,
        ),
        CanvasToggle(
          label: "Header row",
          value: e.headerRow,
          onChanged: (v) {
            begin();
            write(e.copyWith(headerRow: v));
            commit();
          },
        ),
        CanvasToggle(
          label: "Header column",
          value: e.headerColumn,
          onChanged: (v) {
            begin();
            write(e.copyWith(headerColumn: v));
            commit();
          },
        ),
      ]),
      CanvasControlGroup(label: "Look", children: [
        CanvasDropdown<TableGrid>(
          label: "Rules",
          value: e.grid,
          width: 108,
          options: [for (var g in TableGrid.values) (g, g.label)],
          onChanged: (v) {
            begin();
            write(e.copyWith(grid: v));
            commit();
          },
        ),
        CanvasColorButton(
          label: "Rules",
          color: e.gridColor,
          onChanged: (c) {
            begin();
            write(e.copyWith(gridColor: c));
            commit();
          },
        ),
        CanvasColorButton(
          label: "Header",
          color: e.headerFill,
          onChanged: (c) {
            begin();
            write(e.copyWith(headerFill: c));
            commit();
          },
        ),
        CanvasColorButton(
          label: "Cells",
          color: e.cellFill,
          onChanged: (c) {
            begin();
            write(e.copyWith(cellFill: c));
            commit();
          },
        ),
        CanvasToggle(
          label: "Zebra",
          value: e.zebra,
          onChanged: (v) {
            begin();
            write(e.copyWith(zebra: v));
            commit();
          },
        ),
        CanvasColorButton(
          label: "Zebra",
          color: e.zebraFill,
          onChanged: (c) {
            begin();
            write(e.copyWith(zebraFill: c));
            commit();
          },
        ),
        CanvasNumberField(
          label: "Padding",
          value: e.cellPadding,
          min: 0,
          max: 120,
          width: 54,
          onChanged: (v) => write(e.copyWith(cellPadding: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Radius",
          value: e.cornerRadius,
          min: 0,
          max: 120,
          width: 54,
          onChanged: (v) => write(e.copyWith(cornerRadius: v)),
          onCommit: commit,
        ),
      ]),
      ..._typeGroups(e.cellSpec, (spec) => write(e.copyWith(cellSpec: spec)),
          begin, commit,
          label: "Cell type"),
      ..._typeGroups(e.headerSpec,
          (spec) => write(e.copyWith(headerSpec: spec)), begin, commit,
          label: "Header type"),
    ];

List<Widget> _buttonSettings(CanvasController controller, ButtonElement e,
    _Write write, VoidCallback begin, VoidCallback commit) {
  var action = e.action;
  return [
    CanvasControlGroup(label: "Button", children: [
      CanvasTextField(
        label: "Label",
        value: e.label,
        width: 150,
        onChanged: (v) => write(e.copyWith(label: v)),
        onCommit: commit,
      ),
      CanvasColorButton(
        label: "Hover fill",
        color: e.hoverFill,
        onChanged: (c) {
          begin();
          write(e.copyWith(hoverFill: c));
          commit();
        },
      ),
      CanvasColorButton(
        label: "Hover text",
        color: e.hoverTextColor,
        onChanged: (c) {
          begin();
          write(e.copyWith(hoverTextColor: c));
          commit();
        },
      ),
    ]),
    CanvasControlGroup(label: "Action", children: [
      CanvasDropdown<ButtonActionKind>(
        label: "Does",
        value: action.kind,
        width: 150,
        options: [for (var k in ButtonActionKind.values) (k, k.label)],
        onChanged: (v) {
          begin();
          write(e.copyWith(action: action.copyWith(kind: v)));
          commit();
        },
      ),
      if (action.kind.needsFrame)
        CanvasNumberField(
          label: "Frame",
          value: action.frame.toDouble(),
          min: 0,
          max: (controller.document.frames - 1).toDouble(),
          width: 54,
          onChanged: (v) =>
              write(e.copyWith(action: action.copyWith(frame: v.round()))),
          onCommit: commit,
        ),
      if (action.kind.needsElement)
        CanvasDropdown<String>(
          label: "Element",
          value: action.elementId,
          width: 150,
          options: [
            ("", "Nothing"),
            for (var other in controller.document.elements)
              if (other.id != e.id) (other.id, other.name),
          ],
          onChanged: (v) {
            begin();
            write(e.copyWith(action: action.copyWith(elementId: v)));
            commit();
          },
        ),
      if (action.kind.needsUrl)
        CanvasTextField(
          label: "Link",
          value: action.url,
          width: 220,
          hint: "https://",
          onChanged: (v) => write(e.copyWith(action: action.copyWith(url: v))),
          onCommit: commit,
        ),
    ]),
    ..._typeGroups(
        e.textSpec, (spec) => write(e.copyWith(textSpec: spec)), begin, commit,
        label: "Label type"),
    _boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit),
  ];
}

/// _teamSettings is a whole team's controls.
///
/// Ordered the way a team is actually set up: which game, what shape, who is
/// in it, what colour they are, and how big the dots are. The squad list is
/// behind an expander because eleven rows of four fields is more than every
/// other element's settings put together, and somebody opening a team is
/// usually there for the formation or the kit.
List<Widget> _teamSettings(
    TeamElement e, _Write write, VoidCallback begin, VoidCallback commit) {
  /// now is a change made in one go -- a dropdown, a colour, a switch -- which
  /// is its own undo step.
  void now(TeamElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    CanvasControlGroup(label: "Team", children: [
      CanvasDropdown<TeamSport>(
        label: "Sport",
        value: e.sport,
        width: 104,
        options: [for (var s in TeamSport.values) (s, s.label)],
        // Changing the sport re-lays the squad out, since a formation belongs
        // to one game and the squad size changes with it.
        onChanged: (v) =>
            now(e.copyWith(sport: v).withFormation(v.formations.first)),
      ),
      CanvasDropdown<TeamFormation>(
        label: "Formation",
        value: e.sport.formations.contains(e.formation)
            ? e.formation
            : e.sport.formations.first,
        width: 118,
        options: [for (var f in e.sport.formations) (f, f.label)],
        onChanged: (v) => now(e.withFormation(v)),
      ),
      CanvasDropdown<FormationSpread>(
        label: "Spread",
        value: e.spread,
        width: 108,
        options: [for (var v in FormationSpread.values) (v, v.label)],
        // The same eleven positions, two pictures: the shape at kick-off sits
        // inside its own half, the shape in possession has its forwards over
        // the halfway line. See FormationSpread.
        onChanged: (v) => now(e.withFormation(e.formation, spread: v)),
      ),
      CanvasToggle(
        label: "Attack left",
        value: e.mirrored,
        // Turning the team round re-lays it out, which is how the away side
        // faces the home side rather than both running at the same goal.
        onChanged: (v) => now(e.withFormation(e.formation, mirror: v)),
      ),
      CanvasIconButton(
        icon: e.frameLocked ? Icons.lock : Icons.lock_open,
        tooltip: e.frameLocked
            ? "The team's box is pinned — players still move"
            : "Pin the team's box so only players move",
        active: e.frameLocked,
        onPressed: () => now(e.copyWith(frameLocked: !e.frameLocked)),
      ),
      CanvasIconButton(
        icon: Icons.refresh,
        tooltip: "Put everybody back in formation",
        onPressed: () => now(e.withFormation(e.formation)),
      ),
    ]),
    _squadList(e, write, begin, commit, now),
    CanvasControlGroup(label: "Colours", children: [
      CanvasColorButton(
        label: "Keeper",
        color: e.keeperColor,
        onChanged: (c) => now(e.copyWith(keeperColor: c)),
      ),
      CanvasColorButton(
        label: "Players",
        color: e.playerColor,
        onChanged: (c) => now(e.copyWith(playerColor: c)),
      ),
      CanvasColorButton(
        label: "Outline",
        color: e.outlineColor,
        onChanged: (c) => now(e.copyWith(outlineColor: c)),
      ),
      // The element's own opacity rather than a second one of the team's. Two
      // opacities multiplying together is a control that appears not to work
      // whenever the other one is down.
      CanvasNumberField(
        label: "Opacity",
        decimals: 2,
        width: 62,
        value: e.opacity,
        min: 0,
        max: 1,
        onChanged: (v) {
          begin();
          write(e.withBase(opacity: v));
        },
        onCommit: commit,
      ),
    ]),
    CanvasControlGroup(label: "Dots", children: [
      CanvasNumberField(
        key: const ValueKey("teamDotWidth"),
        label: "Width",
        value: e.dotWidth,
        min: 4,
        max: 400,
        width: 56,
        onChanged: (v) {
          begin();
          // Locked, the two move together, which is what keeps a player marker
          // a circle. An oval is almost always somebody having dragged one
          // field without meaning to.
          write(e.copyWith(
              dotWidth: v, dotHeight: e.lockDotAspect ? v : e.dotHeight));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        key: const ValueKey("teamDotHeight"),
        label: "Height",
        value: e.dotHeight,
        min: 4,
        max: 400,
        width: 56,
        onChanged: (v) {
          begin();
          write(e.copyWith(
              dotHeight: v, dotWidth: e.lockDotAspect ? v : e.dotWidth));
        },
        onCommit: commit,
      ),
      CanvasIconButton(
        icon: e.lockDotAspect ? Icons.link : Icons.link_off,
        tooltip: e.lockDotAspect
            ? "Width and height move together"
            : "Width and height are independent",
        active: e.lockDotAspect,
        onPressed: () => now(e.copyWith(
            lockDotAspect: !e.lockDotAspect,
            dotHeight: e.lockDotAspect ? e.dotHeight : e.dotWidth)),
      ),
      CanvasNumberField(
        label: "Ring",
        value: e.ringWidth,
        min: 0,
        max: 40,
        decimals: 1,
        width: 54,
        onChanged: (v) {
          begin();
          write(e.copyWith(ringWidth: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Angle",
        value: e.rotation,
        min: -180,
        max: 180,
        width: 56,
        suffix: "°",
        onChanged: (v) {
          begin();
          write(e.withBase(rotation: v));
        },
        onCommit: commit,
      ),
    ]),
    // One set of type for the number and the name. They were two identical
    // panels, and the two drifted -- a team's names ended up in a different
    // face from its numbers without anybody having chosen that.
    ..._typeGroups(
      e.labelSpec,
      (spec) {
        begin();
        write(e.copyWith(labelSpec: spec));
      },
      begin,
      commit,
      label: "Numbers and names",
    ),
    CanvasControlGroup(label: "Labels", children: [
      CanvasToggle(
        label: "Numbers",
        value: e.showNumbers,
        onChanged: (v) => now(e.copyWith(showNumbers: v)),
      ),
      CanvasToggle(
        label: "Names",
        value: e.showNames,
        onChanged: (v) => now(e.copyWith(showNames: v)),
      ),
      CanvasDropdown<LabelPosition>(
        label: "Name at",
        value: e.namePosition,
        width: 92,
        options: [for (var p in LabelPosition.values) (p, p.label)],
        onChanged: (v) => now(e.copyWith(namePosition: v)),
      ),
      CanvasNumberField(
        label: "Gap",
        value: e.nameGap,
        min: 0,
        max: 80,
        decimals: 1,
        width: 50,
        onChanged: (v) {
          begin();
          write(e.copyWith(nameGap: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Turn",
        value: e.labelRotation,
        min: -180,
        max: 180,
        width: 56,
        suffix: "°",
        onChanged: (v) {
          begin();
          write(e.copyWith(labelRotation: v));
        },
        onCommit: commit,
      ),
    ]),
  ];
}

/// _squadList is the team sheet: one row per player, goalkeeper first.
///
/// The coordinates are shown and edited in canvas units rather than as the
/// fractions they are stored as, because "where is he" is a question about the
/// pitch, not about the element's box.
Widget _squadList(TeamElement e, _Write write, VoidCallback begin,
        VoidCallback commit, void Function(TeamElement) now) =>
    CanvasExpander(
      label: "Players",
      trailing: "${e.players.length}",
      children: [
        for (var i = 0; i < e.players.length; i++)
          _PlayerRow(
            key: ValueKey("player-$i-${e.id}"),
            team: e,
            index: i,
            write: write,
            begin: begin,
            commit: commit,
            now: now,
          ),
      ],
    );

/// _PlayerRow is one line of the team sheet.
///
/// A widget rather than a function so each row's fields keep their own state
/// across the rebuild that every keystroke causes; as plain builders, typing
/// in one player's name rebuilt all eleven and moved the caret.
class _PlayerRow extends StatelessWidget {
  final TeamElement team;
  final int index;
  final _Write write;
  final VoidCallback begin;
  final VoidCallback commit;
  final void Function(TeamElement) now;

  const _PlayerRow({
    required this.team,
    required this.index,
    required this.write,
    required this.begin,
    required this.commit,
    required this.now,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var spot = team.players[index];
    var centre = team.centreOf(spot);

    void set(PlayerSpot next) {
      begin();
      write(team.withPlayer(index, next));
    }

    /// moveTo writes a canvas coordinate back as the fraction it is stored as.
    void moveTo({double? x, double? y}) {
      var w = team.width == 0 ? 1 : team.width;
      var h = team.height == 0 ? 1 : team.height;
      set(spot.copyWith(
        dx: x == null ? spot.dx : (x - team.x) / w,
        dy: y == null ? spot.dy : (y - team.y) / h,
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        CanvasTextField(
          key: ValueKey("num-$index-${team.id}"),
          label: index == 0 ? "GK" : "No.",
          value: spot.number,
          width: 42,
          onChanged: (v) => set(spot.copyWith(number: v)),
          onCommit: commit,
        ),
        CanvasTextField(
          key: ValueKey("name-$index-${team.id}"),
          label: "Name",
          value: spot.name,
          width: 104,
          onChanged: (v) => set(spot.copyWith(name: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: ValueKey("x-$index-${team.id}"),
          label: "X",
          value: centre.dx,
          min: -100000,
          max: 100000,
          width: 54,
          onChanged: (v) => moveTo(x: v),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: ValueKey("y-$index-${team.id}"),
          label: "Y",
          value: centre.dy,
          min: -100000,
          max: 100000,
          width: 54,
          onChanged: (v) => moveTo(y: v),
          onCommit: commit,
        ),
        CanvasIconButton(
          icon: spot.locked ? Icons.lock : Icons.lock_open,
          tooltip: spot.locked ? "Unlock" : "Lock in place",
          active: spot.locked,
          onPressed: () =>
              now(team.withPlayer(index, spot.copyWith(locked: !spot.locked))),
        ),
        CanvasIconButton(
          icon: spot.hidden ? Icons.visibility_off : Icons.visibility,
          tooltip: spot.hidden ? "Show" : "Hide",
          active: spot.hidden,
          onPressed: () =>
              now(team.withPlayer(index, spot.copyWith(hidden: !spot.hidden))),
        ),
        CanvasIconButton(
          icon: Icons.arrow_upward,
          tooltip: "Bring forward",
          onPressed: index >= team.players.length - 1
              ? null
              : () => now(team.movePlayer(index, index + 1)),
        ),
        CanvasIconButton(
          icon: Icons.arrow_downward,
          tooltip: "Send to back",
          onPressed:
              index <= 0 ? null : () => now(team.movePlayer(index, index - 1)),
        ),
      ]),
    );
  }
}

/// _pathSettings is a curve, and what travels along it.
///
/// The follower is chosen from a flat list of everything on the canvas plus
/// every player of every team, because "which player runs this" is the
/// question this feature exists to answer and making it a two-step choice --
/// pick a team, then pick a row -- would be two dropdowns for one decision.
List<Widget> _pathSettings(CanvasController controller, PathElement e,
    _Write write, VoidCallback begin, VoidCallback commit) {
  void now(PathElement next) {
    begin();
    write(next);
    commit();
  }

  /// relink rewrites the follower's keyframes from the curve. Called after
  /// anything that changes the route or its timing, since the movement is
  /// baked rather than evaluated -- see CanvasController.applyPathFollow.
  void relink(PathElement next) {
    now(next);
    controller.applyPathFollow(next);
  }

  return [
    CanvasControlGroup(label: "Path", children: [
      CanvasColorButton(
        label: "Colour",
        color: e.color,
        onChanged: (c) => now(e.copyWith(color: c)),
      ),
      CanvasNumberField(
        label: "Width",
        value: e.strokeWidth,
        min: 0.5,
        max: 60,
        decimals: 1,
        width: 54,
        onChanged: (v) {
          begin();
          write(e.copyWith(strokeWidth: v));
        },
        onCommit: commit,
      ),
      CanvasDropdown<LineStrokeCap>(
        label: "Stroke end",
        value: e.cap,
        width: 92,
        options: [for (var c in LineStrokeCap.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(cap: v)),
      ),
      CanvasDropdown<LineEnd>(
        label: "Start",
        value: e.startEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(startEnd: v)),
      ),
      CanvasDropdown<LineEnd>(
        label: "End",
        value: e.endEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(endEnd: v)),
      ),
      CanvasNumberField(
        label: "End size",
        value: e.endSize,
        min: 0.2,
        max: 8,
        decimals: 1,
        width: 58,
        onChanged: (v) {
          begin();
          write(e.copyWith(endSize: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Dash",
        value: e.dash,
        min: 0,
        max: 200,
        decimals: 1,
        width: 54,
        onChanged: (v) {
          begin();
          write(e.copyWith(dash: v));
        },
        onCommit: commit,
      ),
      CanvasToggle(
        label: "Closed",
        value: e.closed,
        onChanged: (v) => now(e.copyWith(closed: v)),
      ),
      CanvasToggle(
        // A route is scaffolding: the line showing where a player runs helps
        // while the move is being worked out and ruins the picture that comes
        // out of it.
        label: "Guide only",
        value: e.guide,
        onChanged: (v) => now(e.copyWith(guide: v)),
      ),
    ]),
    CanvasControlGroup(label: "Follow", children: [
      CanvasDropdown<String>(
        label: "Who follows",
        value: _followKey(e.follow),
        width: 176,
        options: _followOptions(controller),
        onChanged: (v) {
          var follow = _followFromKey(v);
          if (follow == null) {
            controller.clearPathFollow(e);
            now(e.copyWith(clearFollow: true));
            return;
          }
          // Detaching the old follower first, or its baked keyframes are left
          // behind and it goes on running a route nothing is attached to.
          controller.clearPathFollow(e);
          relink(e.copyWith(follow: follow, guide: true));
        },
      ),
      CanvasNumberField(
        key: const ValueKey("pathStartFrame"),
        label: "Start",
        value: e.firstFrame.toDouble(),
        min: 0,
        max: (controller.document.frames - 1).toDouble(),
        width: 54,
        onChanged: (v) => relink(e.spreadFrames(v.round(), e.lastFrame)),
      ),
      CanvasNumberField(
        key: const ValueKey("pathEndFrame"),
        label: "End",
        value: e.lastFrame.toDouble(),
        min: 0,
        max: (controller.document.frames - 1).toDouble(),
        width: 54,
        onChanged: (v) => relink(e.spreadFrames(e.firstFrame, v.round())),
      ),
      CanvasIconButton(
        icon: Icons.horizontal_distribute,
        tooltip: "Space the points evenly over the run",
        onPressed: () => relink(e.spreadFrames(e.firstFrame, e.lastFrame)),
      ),
      CanvasIconButton(
        icon: Icons.sync,
        tooltip: "Re-apply this route to ${controller.followerLabel(e.follow)}",
        onPressed: e.follow == null ? null : () => relink(e),
      ),
      CanvasIconButton(
        icon: Icons.add,
        tooltip: "Carry the path on past its last point",
        onPressed: () =>
            relink(e.appendNode(maxFrame: controller.document.frames - 1)),
      ),
    ]),
    _pathNodeList(controller, e, relink),
  ];
}

/// _followKey encodes a follower as a dropdown value, since a dropdown wants
/// one comparable thing and a follower is an id and maybe an index.
String _followKey(PathFollow? follow) =>
    follow == null ? "" : "${follow.elementId}/${follow.playerIndex ?? -1}";

PathFollow? _followFromKey(String key) {
  if (key.isEmpty) return null;
  var at = key.lastIndexOf("/");
  if (at < 0) return PathFollow(elementId: key);
  var index = int.tryParse(key.substring(at + 1)) ?? -1;
  return PathFollow(
    elementId: key.substring(0, at),
    playerIndex: index < 0 ? null : index,
  );
}

/// _followOptions is everything on the canvas that could follow a path,
/// players included and paths excluded -- a path following a path is a knot.
List<(String, String)> _followOptions(CanvasController controller) {
  var out = <(String, String)>[("", "Nothing")];
  for (var element in controller.document.elements) {
    if (element is PathElement) continue;
    if (element is TeamElement) {
      for (var i = 0; i < element.players.length; i++) {
        var spot = element.players[i];
        var who = spot.name.isNotEmpty ? spot.name : "#${spot.number}";
        out.add(("${element.id}/$i", "$who — ${element.name}"));
      }
      continue;
    }
    out.add(("${element.id}/-1", element.name));
  }
  return out;
}

/// _pathNodeList is one row per point: when the follower reaches it, and where
/// it is.
///
/// The frame is the interesting column. Retiming a point is how the movement
/// is made to look right -- fast out of the turn, slow into the box -- and
/// doing it by dragging the marks on the timeline is the other half of the
/// same control.
Widget _pathNodeList(CanvasController controller, PathElement e,
        void Function(PathElement) relink) =>
    CanvasExpander(
      label: "Points",
      trailing: "${e.nodes.length}",
      children: [
        for (var i = 0; i < e.nodes.length; i++)
          Padding(
            key: ValueKey("path-node-$i-${e.id}"),
            padding: const EdgeInsets.only(bottom: 2),
            child:
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              CanvasNumberField(
                key: ValueKey("node-frame-$i-${e.id}"),
                // The two ends are named, because they are what the run is
                // timed against and what the Start and End fields above set.
                label: i == 0
                    ? "Start"
                    : i == e.nodes.length - 1
                        ? "End"
                        : "Frame",
                value: e.nodes[i].frame.toDouble(),
                min: 0,
                max: (controller.document.frames - 1).toDouble(),
                width: 54,
                onChanged: (v) => relink(
                    e.withNode(i, e.nodes[i].copyWith(frame: v.round()))),
              ),
              CanvasNumberField(
                key: ValueKey("node-x-$i-${e.id}"),
                label: "X",
                value: e.pointOf(e.nodes[i]).dx,
                min: -100000,
                max: 100000,
                width: 54,
                onChanged: (v) => relink(e.withNode(
                    i,
                    e.nodes[i]
                        .copyWith(x: e.width == 0 ? 0 : (v - e.x) / e.width))),
              ),
              CanvasNumberField(
                key: ValueKey("node-y-$i-${e.id}"),
                label: "Y",
                value: e.pointOf(e.nodes[i]).dy,
                min: -100000,
                max: 100000,
                width: 54,
                onChanged: (v) => relink(e.withNode(
                    i,
                    e.nodes[i].copyWith(
                        y: e.height == 0 ? 0 : (v - e.y) / e.height))),
              ),
              CanvasIconButton(
                icon: Icons.add,
                tooltip: "Add a point after this one",
                // Only between two points -- past the last one there is no
                // segment to halve, and that is what the Add button on the
                // Follow row is for.
                onPressed: i >= e.nodes.length - 1
                    ? null
                    : () => relink(e.insertAfter(i,
                        maxFrame: controller.document.frames - 1)),
              ),
              CanvasIconButton(
                icon: Icons.close,
                tooltip: "Remove this point",
                onPressed:
                    e.nodes.length <= 2 ? null : () => relink(e.withoutNode(i)),
              ),
            ]),
          ),
      ],
    );
