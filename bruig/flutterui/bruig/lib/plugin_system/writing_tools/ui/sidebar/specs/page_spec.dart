import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/element_model.dart';
import 'package:flutter/material.dart';

const ElementSpec pageSpec = ElementSpec(
  icon: Icons.web_outlined,
  name: "Page setup",
  tag: "page",
  shape: ElementShape.lines,
  about: "Page setup: how wide this page is, what it sits on, and the room "
      "it keeps around itself. Put it at the top. Delete this note.",
  tip: "Page setup: how wide this page is, what it sits on, and the room "
      "it keeps around itself. Put it at the top. Delete this note.",
  settings: [
    ElementSetting(
      key: "width",
      label: "Width",
      description: "How wide the writing is allowed to get. A banner row "
          "marked flush still runs the whole way across.",
      options: [
        ElementOption("Full window", ""),
        ElementOption("Narrow (600)", "600"),
        ElementOption("Readable (800)", "800", note: "A comfortable measure"),
        ElementOption("Wide (1000)", "1000"),
      ],
    ),
    ElementSetting(
      key: "background",
      label: "Background",
      description: "What the page sits on. Named from the reader's palette, "
          "so it is right in a dark theme and a light one.",
      options: [
        ElementOption("None", ""),
        ElementOption("Raised", "raised", note: "The surface a card sits on"),
        ElementOption("Quiet", "quiet"),
      ],
    ),
    ElementSetting(
      key: "padding",
      label: "Padding",
      description: "Inside the background.",
      options: spaces,
      defaultIndex: 2,
    ),
    ElementSetting(
      key: "margin",
      label: "Margin",
      description: "Outside the background. Set it to None to run the page "
          "right to the edge of the window.",
      options: spaces,
      defaultIndex: 2,
    ),
  ],
);
