import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/element_model.dart';
import 'package:flutter/material.dart';

const ElementSpec panelSpec = ElementSpec(
  icon: Icons.crop_square,
  name: "Panel",
  tag: "panel",
  shape: ElementShape.attributes,
  body: "Anything at all, including other blocks.",
  about: "Panel: a box round a piece of the page. Borders take one number for "
      "all four sides, or four -- top, right, bottom, left -- so "
      "border=0 0 0 4 is a rule down the left. Delete this note.",
  tip: "Panel: a box round a piece of the page. Borders take one number for "
      "all four sides, or four -- top, right, bottom, left -- so "
      "border=0 0 0 4 is a rule down the left. Delete this note.",
  settings: [
    ElementSetting(
      key: "padding",
      label: "Padding",
      description: "Between the border and what is inside it.",
      options: spaces,
      defaultIndex: 2,
    ),
    ElementSetting(
      key: "margin",
      label: "Margin",
      description: "Between the panel and what is around it.",
      options: spaces,
      defaultIndex: 0,
    ),
    ElementSetting(
      key: "border",
      label: "Border",
      description: "One number for all four sides, or four for each side "
          "from the top going clockwise.",
      options: [
        ElementOption("None", ""),
        ElementOption("Hairline", "1"),
        ElementOption("Medium", "2"),
        ElementOption("Left rule", "0 0 0 4", note: "A line down one side"),
        ElementOption("Top rule", "4 0 0 0"),
      ],
      defaultIndex: 1,
    ),
    ElementSetting(
      key: "style",
      label: "Stroke",
      description: "How the border is drawn.",
      options: [
        ElementOption("Solid", "solid"),
        ElementOption("Dashed", "dashed"),
        ElementOption("Dotted", "dotted"),
        ElementOption("None", "none"),
      ],
    ),
    ElementSetting(
      key: "color",
      label: "Colour",
      description: "The border's colour, from the reader's palette.",
      options: roles,
    ),
    ElementSetting(
      key: "radius",
      label: "Corners",
      description: "How rounded the corners are. Corners round only when "
          "all four sides have the same thickness.",
      options: [
        ElementOption("Square", "0"),
        ElementOption("Slight", "4"),
        ElementOption("Rounded", "8"),
        ElementOption("Very round", "16"),
      ],
      defaultIndex: 2,
    ),
  ],
);
