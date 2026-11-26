import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/fill_controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';

// box_group.dart is a box's controls: its fill, its border, its corners and
// the room inside it, for every element drawn in a box, and the corner and
// side fields a shape's or a text piece's own box uses alone.

/// BoxParts is which of a box's parts its group offers: every one for a box
/// drawn as a BoxSpec draws one, fewer for one drawn with fewer, so a panel
/// never offers what is not drawn.
class BoxParts {
  /// splitSides and splitCorners offer the border's four sides and the four
  /// corners one by one; without them each is one number, the border drawn
  /// at its widest side and the corners at their shared radius.
  final bool splitSides, splitCorners;

  /// padding is the room inside the box; inset the border drawn inside its
  /// edge.
  final bool padding, inset;

  const BoxParts(
      {this.splitSides = true,
      this.splitCorners = true,
      this.padding = true,
      this.inset = true});

  /// whole is every part.
  static const whole = BoxParts();

  /// outline is a box drawn as an outline cut to a shape, as a Layout's
  /// cell is: one border width all round, one radius, nothing inside it.
  static const outline = BoxParts(
      splitSides: false, splitCorners: false, padding: false, inset: false);
}

/// boxGroup is the shared frame controls: background, border, corners and
/// padding, or those of them [parts] names. [fillLabel] names the
/// background swatch; [onPadding] takes padding for an element that does
/// more than store it (a picture grows).
Widget boxGroup(BoxSpec box, ValueChanged<BoxSpec> onChanged,
        VoidCallback begin, VoidCallback commit,
        {String label = "Box",
        String fillLabel = "Fill",
        String remember = "box",
        bool rule = true,
        BoxParts parts = BoxParts.whole,
        ValueChanged<BoxSpec>? onPadding,

        /// fillPickedIn offers a picture or pattern behind the box, as for
        /// letters, picked in this context; without it the box is a colour.
        BuildContext? fillPickedIn,

        /// compact lays it out as element panels do: fill and border colour
        /// side by side with their codes, the corners called Corners.
        bool compact = false}) =>
    // The colours and one number each for border, corners and room inside,
    // each splitting into four by its link: see CanvasSidesField.
    CanvasMoreGroup(
        label: label,
        rule: rule,
        remember: "${remember}Box",
        tooltip: switch ((fillPickedIn != null, parts.inset)) {
          (true, true) =>
            "What the box is painted with, and its border's inset",
          (true, false) => "What the box is painted with",
          _ => "The border's inset",
        },
        row: [
          ..._boxColours(box, onChanged, begin, commit,
              fillLabel: fillLabel, compact: compact),
          ..._boxSides(box, onChanged, commit,
              remember: remember,
              parts: parts,
              onPadding: onPadding,
              compact: compact),
        ],
        more: _boxMore(box, onChanged, begin, commit,
            remember: remember,
            parts: parts,
            compact: compact,
            fillPickedIn: fillPickedIn));

/// _boxColours are the box's fill, where it is painted a colour (a picture
/// or pattern covers it), and its border's colour: side by side with their
/// codes when [compact].
List<Widget> _boxColours(BoxSpec box, ValueChanged<BoxSpec> onChanged,
    VoidCallback begin, VoidCallback commit,
    {required String fillLabel, required bool compact}) {
  void now(BoxSpec next) {
    begin();
    onChanged(next);
    commit();
  }

  var painted = box.painted.kind == TextFillKind.color;
  var fill = CanvasColorButton(
    label: fillLabel,
    color: box.fill,
    gradient: box.fillFade,
    onChanged: (c) => now(box.copyWith(fill: c)),
    onGradientChanged: (g) => now(
        g == null ? box.copyWith(flatFill: true) : box.copyWith(fillFade: g)),
  );
  var border = CanvasColorButton(
    label: compact ? "Border colour" : "Colour",
    color: box.borderColor,
    gradient: box.borderFade,
    onChanged: (c) => now(box.copyWith(borderColor: c)),
    onGradientChanged: (g) => now(g == null
        ? box.copyWith(flatBorder: true)
        : box.copyWith(borderFade: g)),
  );
  if (compact) {
    return [
      panelRow([
        if (painted) cell(fill),
        cell(border),
      ]),
    ];
  }
  return [if (painted) fill, border];
}

/// _boxSides are one number each for the border, the corners and the room
/// inside, each splitting into four by its link where [parts] offers it.
/// They are named by the box ([remember]), so that two boxes in one panel
/// are split apart and found apart.
List<Widget> _boxSides(
        BoxSpec box, ValueChanged<BoxSpec> onChanged, VoidCallback commit,
        {required String remember,
        required BoxParts parts,
        required ValueChanged<BoxSpec>? onPadding,
        required bool compact}) =>
    [
      ...roomFields(
          parts.splitSides ? box.borders : Room(all: box.borders.widest),
          (r) => onChanged(box.withBorders(r)),
          commit,
          label: "Border",
          prefix: "${remember}Box",
          allKey: "Border",
          sideKey: "Border",
          splits: parts.splitSides),
      ...cornerFields(
          parts.splitCorners ? box.corners : Corners(all: box.corners.all),
          (c) => onChanged(box.withCorners(c)),
          commit,
          label: compact ? "Corners" : "Radius",
          prefix: "${remember}Box",
          splits: parts.splitCorners),
      if (parts.padding)
        ...roomFields(
            box.pad, (r) => (onPadding ?? onChanged)(box.withRoom(r)), commit,
            prefix: "${remember}Box"),
      if (parts.splitSides || parts.splitCorners)
        const CanvasHint(
            "Border, Radius and Padding set all four sides or corners at "
            "once; the link beside each splits it into one each. Sides of "
            "different weights are drawn square where they meet, since two "
            "weights cannot round the same corner."),
    ];

/// _boxMore is what is set once: the box's paint where it is offered (see
/// boxGroup's fillPickedIn), as the letters' is, and the border's inset.
List<Widget> _boxMore(BoxSpec box, ValueChanged<BoxSpec> onChanged,
        VoidCallback begin, VoidCallback commit,
        {required String remember,
        required BoxParts parts,
        required bool compact,
        required BuildContext? fillPickedIn}) =>
    [
      // The colour keeps its swatch, as a picture is drawn over it.
      if (fillPickedIn != null) ...[
        CanvasDropdown<TextFillKind>(
          key: ValueKey("${remember}BoxFillKind"),
          // Beside the letters' own in a dense panel: say which.
          label: compact ? "Box painted with" : "Painted with",
          value: box.painted.kind,
          width: 118,
          options: [for (var k in TextFillKind.values) (k, k.label)],
          onChanged: (v) {
            begin();
            onChanged(box.copyWith(painted: box.painted.copyWith(kind: v)));
            commit();
          },
        ),
        // By the kind, not whether the fill is on: a picture is not on
        // until chosen, and these buttons choose it.
        if (box.painted.kind != TextFillKind.color)
          ...fillBits(fillPickedIn, box.painted,
              (f) => onChanged(box.copyWith(painted: f)), begin, commit,
              keyPrefix: "${remember}Box"),
      ],
      // A break only between the two, never after them: with nothing to set
      // once the list is empty, and the group shows no button for it.
      if (fillPickedIn != null && parts.inset && box.hasBorder)
        const CanvasLineBreak(),
      // The border drawn inside the edge, a frame within the frame.
      if (parts.inset && box.hasBorder)
        CanvasNumberField(
          key: ValueKey("${remember}BorderInset"),
          label: "Inset",
          value: box.borderInset,
          min: 0,
          max: 400,
          width: 54,
          onChanged: (v) {
            begin();
            onChanged(box.copyWith(borderInset: v));
          },
          onCommit: commit,
        ),
    ];

/// cornerFields is the corners as one control (a number for all four and a
/// splitting link), shared by an element's box, a piece of a text's box and
/// a shape whose corners can be rounded (ShapeElement.hasCorners). Without
/// [splits] it is one number only.
List<Widget> cornerFields(
        Corners corners, ValueChanged<Corners> onChanged, VoidCallback commit,
        {String label = "Radius",
        required String prefix,
        bool splits = true}) =>
    // One control for the four (see CanvasSidesField).
    [
      CanvasSidesField(
        name: "${prefix}Radius",
        label: label,
        max: 400,
        values: [
          corners.topLeft,
          corners.topRight,
          corners.bottomRight,
          corners.bottomLeft
        ],
        parts: const ["↖", "↗", "↘", "↙"],
        splits: splits,
        partKeys: [
          for (var g in const ["↖", "↗", "↘", "↙"]) "${prefix}Radius$g"
        ],
        onChanged: (side, v) => onChanged(switch (side) {
          null => corners.withEven(v),
          0 => corners.copyWith(tl: v),
          1 => corners.copyWith(tr: v),
          2 => corners.copyWith(br: v),
          _ => corners.copyWith(bl: v),
        }),
        onCommit: commit,
      ),
    ];

/// roomFields is a room's four sides (a border, a padding) as one control,
/// as cornerFields is for corners.
List<Widget> roomFields(
        Room room, ValueChanged<Room> onChanged, VoidCallback commit,
        {String label = "Padding",
        required String prefix,
        // The keys' name, so a second set in one panel (border beside
        // padding) is findable by what it is.
        String allKey = "Padding",
        String sideKey = "Pad",
        bool splits = true}) =>
    [
      CanvasSidesField(
        name: "$prefix$allKey",
        label: label,
        max: 400,
        values: [room.top, room.right, room.bottom, room.left],
        parts: const ["Top", "Right", "Bottom", "Left"],
        splits: splits,
        partKeys: [
          for (var n in const ["Top", "Right", "Bottom", "Left"])
            "$prefix$sideKey$n"
        ],
        onChanged: (side, v) => onChanged(switch (side) {
          null => room.withEven(v),
          0 => room.copyWith(t: v),
          1 => room.copyWith(r: v),
          2 => room.copyWith(b: v),
          _ => room.copyWith(l: v),
        }),
        onCommit: commit,
      ),
    ];
