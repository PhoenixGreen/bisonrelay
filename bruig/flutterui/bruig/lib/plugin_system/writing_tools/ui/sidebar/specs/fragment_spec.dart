import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/element_model.dart';
import 'package:flutter/material.dart';

const ElementSpec fragmentSpec = ElementSpec(
  icon: Icons.extension_outlined,
  name: "Shared fragment",
  tag: "include",
  shape: ElementShape.single,
  about: "Shared fragment: a piece several pages share -- a banner, a "
      "navigation bar, a footer. Write it once in Writing > Library > "
      "Fragments, then name it here and it appears in its place. It is "
      "filled in before the page is sent, so a reader gets one page. "
      "Delete this note.",
  tip: "Shared fragment: a piece several pages share -- a banner, a "
      "navigation bar, a footer. Write it once in Writing > Library > "
      "Fragments, then name it here and it appears in its place. It is "
      "filled in before the page is sent, so a reader gets one page. "
      "Delete this note.",
  settings: [
    ElementSetting(
      key: "name",
      label: "Which fragment",
      description: "The fragment's name, as it is called in Fragments. "
          "Letters, numbers and dashes.",
      options: [
        ElementOption("header", "header"),
        ElementOption("navigation", "navigation"),
        ElementOption("footer", "footer"),
      ],
    ),
  ],
);
