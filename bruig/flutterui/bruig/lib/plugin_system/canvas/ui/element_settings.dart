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
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
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
      LineElement e => _lineSettings(e, write, begin, commit),
      ImageElement e => _imageSettings(e, write, begin, commit),
      ChartElement e => _chartSettings(e, write, begin, commit),
      TableElement e => _tableSettings(e, write, begin, commit),
      ButtonElement e =>
        _buttonSettings(controller, e, write, begin, commit),
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

  Widget dot(String what) => CanvasKeyframeDot(
        on: hasKey,
        enabled: animated,
        tooltip: !animated
            ? "Give the canvas more than one frame to animate its $what"
            : hasKey
                ? "Remove the keyframe here — it holds this element's whole "
                    "pose, not just its $what"
                : "Add a keyframe here for this element's pose",
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

  return CanvasControlGroup(label: e.kind.label, children: [
    CanvasNumberField(
      key: const ValueKey("elementX"),
      label: "X",
      value: box.left,
      onChanged: (v) => moveTo(x: v),
      onCommit: commit,
    ),
    dot("position"),
    CanvasNumberField(
      key: const ValueKey("elementY"),
      label: "Y",
      value: box.top,
      onChanged: (v) => moveTo(y: v),
      onCommit: commit,
    ),
    dot("position"),
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
    dot("size"),
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
    dot("angle"),
    CanvasSlider(
      label: "Opacity",
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
                opacity: e.opacity == 0 ? v : (v / e.opacity).clamp(0.0, 1.0)))));
      },
      onCommit: commit,
    ),
    dot("opacity"),
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
    ..._typeGroups(e.textSpec, (spec) => write(e.copyWith(textSpec: spec)),
        begin, commit),
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
            : e.copyWith(curve: (e.curve ?? const TextOnCurve(elementId: ""))
                .copyWith(elementId: v))),
      ),
      if (e.curve != null) ...[
        CanvasSlider(
          label: "Slide",
          value: e.curve!.offset,
          min: -1,
          max: 1,
          onChanged: (v) {
            begin();
            write(e.copyWith(curve: e.curve!.copyWith(offset: v)));
          },
          onCommit: commit,
        ),
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
          onChanged: (v) =>
              now(e.copyWith(curve: e.curve!.copyWith(away: v))),
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
          CanvasSlider(
            label: "Depth",
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
      if (e.text.isNotEmpty)
        ..._typeGroups(e.textSpec, (spec) => write(e.copyWith(textSpec: spec)),
            begin, commit,
            label: "Label type"),
    ];

List<Widget> _lineSettings(LineElement e, _Write write, VoidCallback begin,
        VoidCallback commit) =>
    [
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
        CanvasDropdown<LineCapStyle>(
          label: "Ends",
          value: e.cap,
          width: 118,
          options: [for (var c in LineCapStyle.values) (c, c.label)],
          onChanged: (v) {
            begin();
            write(e.copyWith(cap: v));
            commit();
          },
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
        CanvasSlider(
          label: "Curve",
          value: e.curvature,
          min: -1,
          max: 1,
          onChanged: (v) {
            begin();
            write(e.copyWith(curvature: v));
          },
          onCommit: commit,
        ),
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

List<Widget> _imageSettings(ImageElement e, _Write write, VoidCallback begin,
        VoidCallback commit) =>
    [
      CanvasControlGroup(label: "Picture", children: [
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
        CanvasSlider(
          label: "Saturation",
          value: e.saturation,
          min: 0,
          max: 3,
          onChanged: (v) {
            begin();
            write(e.copyWith(saturation: v));
          },
          onCommit: commit,
        ),
        CanvasSlider(
          label: "Brightness",
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
          CanvasSlider(
            label: "Threshold",
            value: e.removal.threshold,
            onChanged: (v) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(threshold: v)));
            },
            onCommit: commit,
          ),
        if (e.removal.active) ...[
          CanvasSlider(
            label: "Tolerance",
            value: e.removal.tolerance,
            max: 0.7,
            onChanged: (v) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(tolerance: v)));
            },
            onCommit: commit,
          ),
          CanvasSlider(
            label: "Softness",
            value: e.removal.softness,
            max: 0.3,
            onChanged: (v) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(softness: v)));
            },
            onCommit: commit,
          ),
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
      _boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
          label: "Frame"),
    ];

List<Widget> _chartSettings(ChartElement e, _Write write, VoidCallback begin,
        VoidCallback commit) =>
    [
      CanvasControlGroup(label: "Chart", children: [
        CanvasDropdown<ChartType>(
          label: "Type",
          value: e.type,
          width: 132,
          options: [for (var t in ChartType.values) (t, t.label)],
          onChanged: (v) {
            begin();
            write(e.copyWith(type: v));
            commit();
          },
        ),
        CanvasTextField(
          label: "Title",
          value: e.title,
          width: 160,
          onChanged: (v) => write(e.copyWith(title: v)),
          onCommit: commit,
        ),
        CanvasTextField(
          label: "Description",
          value: e.description,
          width: 160,
          onChanged: (v) => write(e.copyWith(description: v)),
          onCommit: commit,
        ),
      ]),
      CanvasControlGroup(label: "Data", children: [
        // The whole table as one editable block, in the same tab or comma
        // separated form a spreadsheet copies. Pasting a table in and having a
        // chart is the fastest path there is, and it is the reason there is no
        // row-by-row editor here.
        CanvasTextField(
          label: "Rows (paste a table)",
          value: e.data.asText(),
          width: 260,
          maxLines: 2,
          hint: "Name\tSeries\nWeek 1\t120",
          onChanged: (v) => write(e.copyWith(data: ChartData.parse(v))),
          onCommit: commit,
        ),
      ]),
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
        CanvasToggle(
          label: "Grid",
          value: e.showGrid,
          onChanged: (v) {
            begin();
            write(e.copyWith(showGrid: v));
            commit();
          },
        ),
        CanvasToggle(
          label: "Axes",
          value: e.showAxes,
          onChanged: (v) {
            begin();
            write(e.copyWith(showAxes: v));
            commit();
          },
        ),
        CanvasToggle(
          label: "Legend",
          value: e.showLegend,
          onChanged: (v) {
            begin();
            write(e.copyWith(showLegend: v));
            commit();
          },
        ),
        CanvasToggle(
          label: "Values",
          value: e.showValues,
          onChanged: (v) {
            begin();
            write(e.copyWith(showValues: v));
            commit();
          },
        ),
      ]),
      CanvasControlGroup(label: "Style", children: [
        for (var i = 0; i < e.data.series.length && i < 6; i++)
          CanvasColorButton(
            label: e.data.series[i].name.isEmpty
                ? "Series ${i + 1}"
                : e.data.series[i].name,
            color: e.data.series[i].color,
            onChanged: (c) {
              begin();
              var series = [...e.data.series];
              series[i] = series[i].copyWith(color: c);
              write(e.copyWith(
                  data: ChartData(
                      categories: e.data.categories, series: series)));
              commit();
            },
          ),
        CanvasColorButton(
          label: "Grid",
          color: e.gridColor,
          onChanged: (c) {
            begin();
            write(e.copyWith(gridColor: c));
            commit();
          },
        ),
        CanvasSlider(
          label: "Bar gap",
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
        CanvasToggle(
          label: "Smooth",
          value: e.smooth,
          onChanged: (v) {
            begin();
            write(e.copyWith(smooth: v));
            commit();
          },
        ),
      ]),
    ];

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
      ..._typeGroups(
          e.headerSpec, (spec) => write(e.copyWith(headerSpec: spec)), begin,
          commit,
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
List<Widget> _teamSettings(TeamElement e, _Write write, VoidCallback begin,
    VoidCallback commit) {
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
        onChanged: (v) => now(e
            .copyWith(sport: v)
            .withFormation(v.formations.first)),
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
      CanvasSlider(
        label: "Opacity",
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
          onPressed: () => now(
              team.withPlayer(index, spot.copyWith(locked: !spot.locked))),
        ),
        CanvasIconButton(
          icon: spot.hidden ? Icons.visibility_off : Icons.visibility,
          tooltip: spot.hidden ? "Show" : "Hide",
          active: spot.hidden,
          onPressed: () => now(
              team.withPlayer(index, spot.copyWith(hidden: !spot.hidden))),
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
      CanvasDropdown<LineCapStyle>(
        label: "Ends",
        value: e.cap,
        width: 116,
        options: [for (var c in LineCapStyle.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(cap: v)),
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
        onChanged: (v) =>
            relink(e.spreadFrames(v.round(), e.lastFrame)),
      ),
      CanvasNumberField(
        key: const ValueKey("pathEndFrame"),
        label: "End",
        value: e.lastFrame.toDouble(),
        min: 0,
        max: (controller.document.frames - 1).toDouble(),
        width: 54,
        onChanged: (v) =>
            relink(e.spreadFrames(e.firstFrame, v.round())),
      ),
      CanvasIconButton(
        icon: Icons.horizontal_distribute,
        tooltip: "Space the points evenly over the run",
        onPressed: () =>
            relink(e.spreadFrames(e.firstFrame, e.lastFrame)),
      ),
      CanvasIconButton(
        icon: Icons.sync,
        tooltip: "Re-apply this route to ${controller.followerLabel(e.follow)}",
        onPressed: e.follow == null ? null : () => relink(e),
      ),
      CanvasIconButton(
        icon: Icons.add,
        tooltip: "Carry the path on past its last point",
        onPressed: () => relink(
            e.appendNode(maxFrame: controller.document.frames - 1)),
      ),
    ]),
    _pathNodeList(controller, e, relink),
  ];
}

/// _followKey encodes a follower as a dropdown value, since a dropdown wants
/// one comparable thing and a follower is an id and maybe an index.
String _followKey(PathFollow? follow) => follow == null
    ? ""
    : "${follow.elementId}/${follow.playerIndex ?? -1}";

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
                    e.nodes[i].copyWith(
                        x: e.width == 0 ? 0 : (v - e.x) / e.width))),
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
                onPressed: e.nodes.length <= 2
                    ? null
                    : () => relink(e.withoutNode(i)),
              ),
            ]),
          ),
      ],
    );
