import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/element_model.dart';
import 'package:flutter/material.dart';

const ElementSpec navSpec = ElementSpec(
  icon: Icons.menu_open,
  name: "Navigation bar",
  tag: "nav",
  shape: ElementShape.valueBlock,
  body: "[Home](index.md)\n[About](about.md)\n[Store](store)",
  about: "Navigation bar: one link a line, between the markers. Link a page "
      "with [About](about.md) and your store with [Store](store). What is "
      "not set here comes from the reader's Markdown theme, which is where "
      "the colours live. Delete this note.",
  tip: "Navigation bar: one link a line, between the markers. Link a page "
      "with [About](about.md) and your store with [Store](store). What is "
      "not set here comes from the reader's Markdown theme, which is where "
      "the colours live. Delete this note.",
  settings: [
    ElementSetting(
      key: "style",
      label: "Shape",
      description: "How each link is drawn. Its colours come from the "
          "reader's Markdown theme.",
      options: [
        ElementOption("Plain", "plain", note: "Words with space between"),
        ElementOption("Pills", "pills"),
        ElementOption("Underline", "underline"),
        ElementOption("Boxed", "boxed"),
      ],
    ),
  ],
  groups: [
    SettingGroup(
      label: "Background",
      description: "What the bar itself sits on, behind the links, and how "
          "tall that is.",
      settings: [
        ElementSetting(
          key: "background",
          label: "Colour",
          description: "A colour from the reader's palette, or one of your "
              "own. A bar on a page belongs to the reader's theme like "
              "everything else; one in a banner sits over a picture you "
              "chose, and only you know what will read against it -- which "
              "is why both are offered. A see-through colour keeps the "
              "picture visible.",
          kind: SettingKind.colour,
          options: [
            ElementOption("Theme default", ""),
            ElementOption("None", "none", note: "No background at all"),
            ElementOption("Raised surface", "raised", note: "From the palette"),
            ElementOption("Half-black", "#00000080", note: "See-through"),
            ElementOption("White", "#ffffff"),
          ],
        ),
        ElementSetting(
          key: "height",
          label: "Height",
          description: "How tall the bar is, with the links held in the "
              "middle of it. Left alone, it is as tall as the links need.",
          options: [
            ElementOption("As tall as the links", ""),
            ElementOption("Short (36)", "36"),
            ElementOption("Medium (44)", "44"),
            ElementOption("Tall (64)", "64"),
          ],
        ),
      ],
    ),
    SettingGroup(
      label: "Placement",
      description: "Where the bar sits and how much room it keeps. Left "
          "alone, a bar follows the row it is in and the reader's theme.",
      settings: [
        ElementSetting(
          key: "align",
          label: "Align",
          description: "Which way the links run. Left alone, a bar in a "
              "banner row follows that row, and a bar on the page runs "
              "from the left.",
          options: [
            ElementOption("As the row", ""),
            ElementOption("Left", "left"),
            ElementOption("Middle", "center"),
            ElementOption("Right", "right"),
          ],
        ),
        ElementSetting(
          key: "width",
          label: "Width",
          description: "Whether the bar's background runs the whole way "
              "across or only under the links. Only visible once the bar "
              "has a background, which the theme sets.",
          options: [
            ElementOption("Theme default", ""),
            ElementOption("Under the links", "fit"),
            ElementOption("Full width", "full"),
          ],
        ),
        ElementSetting(
          key: "gap",
          label: "Space between links",
          description: "How far apart the links are.",
          options: [
            ElementOption("Theme default", ""),
            ElementOption("Tight", "6"),
            ElementOption("Normal", "12"),
            ElementOption("Wide", "24"),
          ],
        ),
        ElementSetting(
          key: "radius",
          label: "Corners on each link",
          description: "How rounded a pill or a box is. Nothing to see on a "
              "plain bar, where the links are just words.",
          options: [
            ElementOption("Theme default", ""),
            ElementOption("Square", "0"),
            ElementOption("Slight", "4"),
            ElementOption("Rounded", "10"),
            ElementOption("Fully round", "40"),
          ],
        ),
        ElementSetting(
          key: "padding",
          label: "Padding in each link",
          description: "Room inside a link, which is what gives a pill or "
              "a box its size. Nothing to see on a plain bar, where the "
              "links are just words.",
          options: [
            ElementOption("Theme default", ""),
            ElementOption("None", "0"),
            ElementOption("Tight", "6"),
            ElementOption("Roomy", "14"),
          ],
        ),
        ElementSetting(
          key: "margin",
          label: "Margin",
          description: "Room around the bar. One number for all four sides, "
              "or four for each side from the top going clockwise.\n\n"
              "In a banner row the row holds the bar in its middle, so room "
              "added evenly on both sides moves nothing -- it makes the bar "
              "taller and the middle is still the middle. Use one of the "
              "one-sided answers to shift it.",
          options: [
            ElementOption("None", ""),
            ElementOption("Push down", "16 0 0 0", note: "Room above only"),
            ElementOption("Push up", "0 0 16 0", note: "Room below only"),
            ElementOption("Indent", "0 0 0 24", note: "Room at the left only"),
            ElementOption("All round", "16", note: "Not in a banner row"),
          ],
        ),
      ],
    ),
  ],
);
