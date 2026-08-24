import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/element_model.dart';
import 'package:flutter/material.dart';

const ElementSpec headerSpec = ElementSpec(
  icon: Icons.view_day_outlined,
  name: "Header",
  tag: "header",
  shape: ElementShape.lines,
  about: "Header: the banner at the top of a page. At most two rows, at most "
      "two cells each -- copy the row block for a second. A row's settings "
      "go in its brackets in any order: a number is the height, flush runs "
      "it to the banner's edge, and group keeps its two cells together. "
      "Delete this note.",
  rows: [
    RowSpec(
      tag: "row",
      number: 1,
      cells: "left: ![](assets/logo.svg)\nright: # My Site",
      settings: [
        ElementSetting(
          key: "height1",
          label: "Height",
          description: "How tall the row is. Everything in it is sized to "
              "this, so a title comes out level with the logo beside it "
              "without either being told about the other.",
          options: [
            ElementOption("Short (44)", "44", note: "A bar of links"),
            ElementOption("Medium (96)", "96"),
            ElementOption("Tall (200)", "200", note: "A logo and a title"),
          ],
          defaultIndex: 1,
        ),
        ElementSetting(
          key: "layout1",
          label: "Layout",
          description: "Where the row's cells sit. Split pushes them to "
              "either end; left, centre and right hold them together at "
              "that side.",
          options: [
            ElementOption("Left", "left"),
            ElementOption("Centre", "center"),
            ElementOption("Right", "right"),
            ElementOption("Split", "split", note: "One at each end"),
          ],
        ),
        ElementSetting(
          key: "flush1",
          label: "Flush",
          description: "Runs the row to the banner's edge, giving up the "
              "inset it would otherwise keep. What a strip along the top "
              "or bottom of a banner wants.",
          options: [
            ElementOption("No", ""),
            ElementOption("Yes", "flush"),
          ],
        ),
        ElementSetting(
          key: "group1",
          label: "Group",
          description: "Keeps the row's two cells together as a pair "
              "rather than letting the second have the rest of the row -- "
              "a logo and a title beside it, sitting as one thing.",
          options: [
            ElementOption("No", ""),
            ElementOption("Yes", "group"),
          ],
        ),
      ],
    ),
    RowSpec(
      tag: "row",
      number: 2,
      cells: "--include[navigation]--",
      settings: [
        ElementSetting(
          key: "height2",
          label: "Height",
          description: "How tall the row is. Everything in it is sized to "
              "this, so a title comes out level with the logo beside it "
              "without either being told about the other.",
          options: [
            ElementOption("Short (44)", "44", note: "A bar of links"),
            ElementOption("Medium (96)", "96"),
            ElementOption("Tall (200)", "200", note: "A logo and a title"),
          ],
          defaultIndex: 0,
        ),
        ElementSetting(
          key: "layout2",
          label: "Layout",
          description: "Where the row's cells sit. Split pushes them to "
              "either end; left, centre and right hold them together at "
              "that side.",
          options: [
            ElementOption("Left", "left"),
            ElementOption("Centre", "center"),
            ElementOption("Right", "right"),
            ElementOption("Split", "split", note: "One at each end"),
          ],
        ),
        ElementSetting(
          key: "flush2",
          label: "Flush",
          description: "Runs the row to the banner's edge, giving up the "
              "inset it would otherwise keep. What a strip along the top "
              "or bottom of a banner wants.",
          options: [
            ElementOption("No", ""),
            ElementOption("Yes", "flush"),
          ],
        ),
        ElementSetting(
          key: "group2",
          label: "Group",
          description: "Keeps the row's two cells together as a pair "
              "rather than letting the second have the rest of the row -- "
              "a logo and a title beside it, sitting as one thing.",
          options: [
            ElementOption("No", ""),
            ElementOption("Yes", "group"),
          ],
        ),
      ],
    ),
  ],
  groups: [
    SettingGroup(
      label: "Title fill",
      description: "What the writing is filled with. One of these at a time: "
          "a picture is poured through the letters if there is one, then a "
          "gradient, and the colour is what is used otherwise.",
      exclusive: true,
      settings: [
        ElementSetting(
          key: "titlecolor",
          label: "Colour",
          description: "One colour for the writing.",
          kind: SettingKind.colour,
          options: hexColours,
        ),
        ElementSetting(
          key: "titlegradient",
          label: "Gradient",
          description: "Two or more colours, poured through the letters.",
          kind: SettingKind.colours,
          options: [
            ElementOption("None", ""),
            ElementOption("Two colours", "#f00,#00f"),
          ],
        ),
        ElementSetting(
          key: "titleimage",
          label: "Picture",
          description: "A picture poured through the letters, so the writing "
              "is cut out of it. Name one of the site's own pictures.",
          kind: SettingKind.text,
          options: [
            ElementOption("None", ""),
            ElementOption("A site picture", "![](assets/banner.jpg)",
                note: "Change the name to one of yours"),
          ],
        ),
      ],
    ),
    SettingGroup(
      label: "Title outline",
      description: "A line round each letter, which is what makes writing "
          "readable over a picture.",
      settings: [
        ElementSetting(
          key: "titleoutline",
          label: "Width",
          description: "How thick the line is.",
          options: [
            ElementOption("None", "0"),
            ElementOption("Thin", "2"),
            ElementOption("Medium", "5"),
            ElementOption("Thick", "10"),
          ],
        ),
        ElementSetting(
          key: "titleoutlinecolor",
          label: "Colour",
          description: "The colour of that line.",
          kind: SettingKind.colour,
          options: hexColours,
        ),
      ],
    ),
    SettingGroup(
      label: "Title panel and lettering",
      description: "The panel behind the writing, and how the words "
          "themselves are set.",
      settings: [
        ElementSetting(
          key: "titlebackground",
          label: "Panel colour",
          description: "A see-through colour keeps the picture visible while "
              "making the words readable.",
          kind: SettingKind.colour,
          options: hexColours,
        ),
        ElementSetting(
          key: "titlepadding",
          label: "Panel padding",
          description: "Room between the writing and the panel's edge.",
          options: [
            ElementOption("None", "0"),
            ElementOption("Tight", "8"),
            ElementOption("Roomy", "16"),
          ],
        ),
        ElementSetting(
          key: "titleradius",
          label: "Panel corners",
          description: "How rounded the panel's corners are.",
          options: [
            ElementOption("Square", "0"),
            ElementOption("Rounded", "8"),
            ElementOption("Very round", "24"),
          ],
        ),
        ElementSetting(
          key: "titleweight",
          label: "Weight",
          description: "Bold, or as the theme sets it.",
          options: [
            ElementOption("Regular", "regular"),
            ElementOption("Bold", "bold"),
          ],
        ),
        ElementSetting(
          key: "titleitalic",
          label: "Italic",
          description: "Slanted or upright.",
          options: [
            ElementOption("No", "no"),
            ElementOption("Yes", "yes"),
          ],
        ),
        ElementSetting(
          key: "titlecase",
          label: "Case",
          description: "Changes the words themselves rather than drawing "
              "them differently, so what a reader copies out is what they "
              "see.",
          options: [
            ElementOption("As written", ""),
            ElementOption("UPPER", "upper"),
            ElementOption("lower", "lower"),
          ],
        ),
        ElementSetting(
          key: "titletracking",
          label: "Tracking",
          description: "Space between the letters.",
          options: [
            ElementOption("Normal", "0"),
            ElementOption("Open", "0.5"),
            ElementOption("Wide", "2"),
          ],
        ),
      ],
    ),
  ],
  settings: [
    ElementSetting(
      key: "background",
      label: "Background picture",
      description: "A picture from the site's own Pictures, behind the "
          "whole banner. Add one with Add Picture and paste what it gives "
          "you in place of the name here.",
      kind: SettingKind.text,
      options: [
        ElementOption("None", ""),
        ElementOption("A site picture", "![](assets/banner.jpg)",
            note: "Change the name to one of yours"),
      ],
    ),
    ElementSetting(
      key: "titlesize",
      label: "Title size",
      description: "In pixels. Left alone, the writing is set to the height "
          "of the row it is in, which is usually what you want.",
      options: [
        ElementOption("Row height", ""),
        ElementOption("32", "32"),
        ElementOption("48", "48"),
        ElementOption("72", "72"),
      ],
    ),
  ],
);
