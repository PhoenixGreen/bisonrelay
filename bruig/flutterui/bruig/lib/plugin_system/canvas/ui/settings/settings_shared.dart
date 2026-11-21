import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show cameraOf;
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/procedural_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/recent_pictures.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:flutter/material.dart';

/// freshOf is [e] as the document has it now, or null: after an await the
/// old read may be stale, and writing it back would undo changes.
T? freshOf<T extends CanvasElement>(CanvasController controller, T e) {
  var now = controller.document.elementById(e.id);
  return now is T ? now : null;
}

// settings_shared.dart is the controls every element shares (place, type,
// box), kept once so copies cannot drift.

typedef SettingsWrite = void Function(CanvasElement);

/// positionGroup is what every element has: place, size, turn, and whether
/// it can be touched. Its keyframes are the Chain's to make and ease.
Widget positionGroup(CanvasController controller, CanvasElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  // No lock, hide or bring-to-front here: they belong to the layer, and the
  // layers list shows them on the element's row, usable unselected.

  var frame = controller.frame;
  var pose = e.poseAt(frame);
  var box = e.boundsAt(frame);

  /// posing is whether these fields edit a keyframe, not the resting place:
  /// the stage's question for a drag, so typing and dragging agree.
  var posing = controller.posesRatherThanMoves(e);

  /// moveTo writes a position, as a pose while animating, else the resting
  /// position; the fields show the posed value, where the element is seen.
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

  /// resize writes width or height, keeping proportions where asked
  /// (ElementBase.lockAspect) by scaling the other side. Fields show the
  /// posed size but edit the resting one: a pose scales evenly.
  void resize({double? width, double? height}) {
    // The undo step, as moveTo opens one.
    begin();
    var scale = pose.scale == 0 ? 1.0 : pose.scale;
    if (!e.base.lockAspect) {
      write(e.withBase(
        width: width == null ? null : width / scale,
        height: height == null ? null : height / scale,
      ));
      return;
    }

    // The edited side's factor applied to both, guarding a zero side.
    var by = width != null
        ? (box.width <= 0 ? 1 : width / box.width)
        : (box.height <= 0 ? 1 : height! / box.height);
    if (!by.isFinite || by <= 0) return;

    write(e.withBase(
      width: box.width * by / scale,
      height: box.height * by / scale,
    ));
  }

  var xField = CanvasStepper(
    key: const ValueKey("elementX"),
    label: "X",
    // Two to a line (across beside down, wide beside high), held so by the
    // breaks, not the width, which only leaves the arrows room.
    width: 104,
    value: box.left,
    onChanged: (v) => moveTo(x: v),
    onCommit: commit,
  );
  var yField = CanvasStepper(
    key: const ValueKey("elementY"),
    label: "Y",
    width: 104,
    value: box.top,
    onChanged: (v) => moveTo(y: v),
    onCommit: commit,
  );
  var wField = CanvasStepper(
    key: const ValueKey("elementW"),
    label: "W",
    width: 104,
    value: box.width,
    min: 1,
    onChanged: (v) => resize(width: v),
    onCommit: commit,
  );
  var hField = CanvasStepper(
    key: const ValueKey("elementH"),
    label: "H",
    width: 104,
    value: box.height,
    min: 1,
    onChanged: (v) => resize(height: v),
    onCommit: commit,
  );
  var turnField = CanvasStepper(
    key: const ValueKey("elementAngle"),
    label: "Angle",
    value: e.rotationAt(frame),
    min: -3600,
    max: 3600,
    // X's least width, so Angle and Opacity line up under X and Y.
    width: 104,
    step: 15,
    dragStep: 1,
    defaultValue: 0,
    suffix: "°",
    onChanged: (v) {
      begin();
      if (!posing) {
        // About its anchor, which stays where it is.
        write(e.turnedTo(v));
        return;
      }
      var track = (e.track ?? ElementTrack.empty).seededFor(frame);
      write(e.withBase(
          track: track.withKey(
              track.at(frame).copyWith(frame: frame, rotate: v - e.rotation))));
    },
    onCommit: commit,
  );
  var opacityField = CanvasStepper(
    key: const ValueKey("elementOpacity"),
    label: "Opacity",
    min: 0,
    max: 100,
    step: 5,
    dragStep: 1,
    suffix: "%",
    defaultValue: 100,
    width: 104,
    value: e.opacityAt(frame) * 100,
    onChanged: (percent) {
      var v = percent / 100;
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
  );

  // Text riding a line takes its place and angle from the line, so the
  // fields would move the words off it; without the line, its own box.
  if (e is TextElement &&
      e.curve != null &&
      controller.document.elementById(e.curve!.elementId) != null) {
    return CanvasControlGroup(label: e.kind.label, children: [
      const Padding(
        padding: EdgeInsets.only(top: controlLabelHeight, right: 6),
        child: SizedBox(
          height: controlHeight,
          child: Center(
            child: Txt.S("Placed by the line it follows"),
          ),
        ),
      ),
      opacityField,
    ]);
  }
  var lockButton = CanvasIconButton(
    icon: e.base.lockAspect ? Icons.link : Icons.link_off,
    tooltip: e.base.lockAspect
        ? "Proportions are held — the width and the height move together"
        : "Width and height are free of each other",
    active: e.base.lockAspect,
    onPressed: () {
      begin();
      // A picture let go squashes (ImageElement.withProportionsKept).
      write(e is ImageElement
          ? e.withProportionsKept(!e.base.lockAspect)
          : e.withBase(lockAspect: !e.base.lockAspect));
      commit();
    },
  );

  return CanvasControlGroup(
      label: e.kind.label,
      // The settings are already headed with the element's name.
      hideCaption: true,
      children: [
        // Place and turn on one line, size and opacity on the next.
        panelRow([cell(xField), cell(yField), cell(turnField)]),
        panelRow([cell(wField), cell(hField), cell(opacityField)]),
        lockButton,
        anchorButtons(controller, e, write, begin, commit),
        // Slant after turn, and the switch making side handles slant it, for
        // a screen with no keys to hold.
        const CanvasLineBreak(),
        for (var (key, label, value, across) in [
          ("elementSkewX", "Skew X", e.base.skewX, true),
          ("elementSkewY", "Skew Y", e.base.skewY, false),
        ])
          CanvasStepper(
            key: ValueKey(key),
            label: label,
            value: value,
            min: -maxSkew,
            max: maxSkew,
            width: 104,
            step: 5,
            dragStep: 1,
            defaultValue: 0,
            suffix: "°",
            onChanged: (v) {
              begin();
              write(across ? e.withBase(skewX: v) : e.withBase(skewY: v));
            },
            onCommit: commit,
          ),
        CanvasToggle(
          key: const ValueKey("elementSkewHandles"),
          label: "Skew",
          value: controller.skewHandles,
          onChanged: (v) => controller.skewHandles = v,
        ),
        const CanvasHint("Skew X leans the sides, Skew Y the top and bottom. "
            "On the canvas, hold Command and drag a side handle -- or switch "
            "Skew on and drag one without a key."),
        // Distance from the scene's Camera, for depth of field and parallax.
        if (e is! CameraElement && cameraOf(controller.document) != null) ...[
          const CanvasLineBreak(gap: 8),
          CanvasStepper(
            key: const ValueKey("elementDepth"),
            label: "Depth",
            value: e.base.depth * 100,
            min: -100,
            max: 100,
            width: 104,
            step: 10,
            dragStep: 1,
            defaultValue: 0,
            onChanged: (v) {
              begin();
              write(e.withBase(depth: v / 100));
            },
            onCommit: commit,
          ),
          const CanvasHint("Depth is how far behind the page it is, to 100, or "
              "in front of it, to -100, as the Camera sees it: its depth of "
              "field blurs what is away from its focus, and its parallax moves "
              "the far less and the near more."),
        ],
        // A counter in a document of pages can be the page number, offered
        // beside "Own on A4": both are what it does on its leaf.
        if (e is CounterElement && controller.document.isPages) ...[
          const CanvasLineBreak(gap: 8),
          CanvasToggle(
            key: const ValueKey("counterIsPageNumber"),
            label: "Page number",
            value: e.isPageNumber,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  source: v ? CounterSource.page : CounterSource.run));
              commit();
            },
          ),
          // And which edge it sits against, for a page number on the leaf's
          // outside. See CounterElement.mirrored.
          if (e.isPageNumber)
            CanvasToggle(
              key: const ValueKey("counterMirrored"),
              label: "Mirror on left pages",
              value: e.mirrored,
              onChanged: (v) {
                begin();
                write(e.copyWith(mirrored: v));
                commit();
              },
            ),
          CanvasHint(e.isPageNumber
              ? "The number of the page it is drawn on. On the master canvas "
                  "it gives every page its own number, and shows the first "
                  "number the document prints so that there is something "
                  "there to place. Mirrored, it moves to the matching place "
                  "on the other edge for a left-hand page, so the number sits "
                  "on the outside of the leaf on both sides of a spread — "
                  "something already centred stays where it is, because the "
                  "mirror of the middle is the middle. You place it here as a "
                  "right-hand page; open a left-hand one to see it mirrored."
              : "Turn this on and the counter shows the number of the page "
                  "it is drawn on instead of counting. Put one on the master "
                  "canvas and every page wears it."),
        ],
        // What this element does on this page shape, for a document laid out
        // for several; a canvas made for one shape has one design.
        if (controller.document.targets.length > 1) ...[
          // Air, not just a break: what follows is about this ratio.
          const CanvasLineBreak(gap: 8),
          // How big the contents are on this shape: the box stays and type,
          // spacing and padding scale, as a banner headline is a feed line
          // (ElementBase.typeScale). Pictures, shapes and charts scale already.
          if (e.scalesInside) ...[
            CanvasStepper(
              key: const ValueKey("elementTypeScale"),
              label: "Scale inside",
              value: e.base.typeScale,
              min: 0.05,
              max: 10,
              decimals: 2,
              step: 0.05,
              defaultValue: 1,
              width: 104,
              onChanged: (v) {
                if (v <= 0 || e.base.typeScale <= 0) return;
                begin();
                write(e.scaledBy(v / e.base.typeScale).withBase(
                      x: e.x,
                      y: e.y,
                      width: e.width,
                      height: e.height,
                      typeScale: v,
                    ));
              },
              onCommit: commit,
            ),
            const CanvasHint(
                "Everything inside the box at once, on the shape of page you "
                "are on: the type, the line spacing, the padding, the corners "
                "and the rules. The box itself stays where you put it. Type "
                "size on its own is the Type group's Size — this is that and "
                "the room round it together, which is what keeps a design "
                "looking like itself at another size."),
          ],
          // And the way out of sharing, for an element it cannot carry.
          CanvasToggle(
            key: const ValueKey("elementOwnDesign"),
            label: "Own on ${shapeShort(shapeKey(controller.document.size))}",
            value: e.base.ownDesign,
            onChanged: (v) {
              begin();
              // The shared design is kept aside while detached.
              write(v ? detachedHere(e) : sharedAgain(e));
              commit();
            },
          ),
          CanvasHint(e.base.ownDesign
              ? "This element is its own on ${shapeLabel(shapeKey(controller.document.size))}: "
                  "nothing done to it on another ratio reaches it here, and "
                  "nothing done here reaches them. Switch it off and it goes "
                  "back to the design the ratios share, laid out for this one."
              : "Give this element its own settings on "
                  "${shapeLabel(shapeKey(controller.document.size))} alone. "
                  "Everything an element *is* — its words, its colours, its "
                  "data, its settings — is shared by every ratio; only where "
                  "it sits and how big it is belong to one. Switch this on "
                  "and this ratio gets a copy of the element to change "
                  "freely, and the shared one is kept for the others."),
        ],
      ]);
}

/// typeGroups is the shared type controls for elements that draw words.
List<Widget> typeGroups(
  TextSpec spec,
  ValueChanged<TextSpec> onChanged,
  VoidCallback begin,
  VoidCallback commit, {
  String label = "Type",
  bool includeCase = true,

  /// hideCaption drops the first caption where the section says it already.
  bool hideCaption = false,

  /// fill offers a picture or pattern through the letters (text elements
  /// only); [context] is then required to choose it.
  bool fill = false,
  BuildContext? context,

  /// remember prefixes the two buttons' open state, so a panel with three
  /// sets (a counter's number, words and buttons) does not open all three.
  String remember = "type",

  /// rule draws the line under each group; off where they run on into what
  /// follows as one subject (a text element's face, colour and box).
  bool rule = true,

  /// extraMore goes behind the first button: a text element's marks.
  List<Widget> extraMore = const [],

  /// fitted is whether the size comes from the box (Fit to box), so the
  /// field says so; the caller stops fitting when a size is typed.
  bool fitted = false,

  /// colourInMore puts colour behind the type button, so a text piece is
  /// one line and one button; elsewhere the swatch keeps its row.
  bool colourInMore = false,

  /// rowBefore goes at the front of the type row: what tells rows apart (a
  /// text item's slot and remove button).
  List<Widget> rowBefore = const [],

  /// captions draws the controls' captions: off for the second and later of
  /// a run of these. The room is kept, so rows line up. See _labelled.
  bool captions = true,

  /// includeAlign offers the two alignment dropdowns behind the button: off
  /// for a piece placed by its slot.
  bool includeAlign = true,

  /// includeUnderline offers the underline switch: off where a drawn
  /// underline (a text's marks) does it, so there are not two.
  bool includeUnderline = true,

  /// onRename makes the caption a typable name, for callers whose caption
  /// is a name: a text element's pieces, and the element itself.
  ValueChanged<String>? onRename,

  /// looks offers the type's outline, shadow and glow: off for a text
  /// element, whose looks live in the Chain (see text_looks.dart).
  bool looks = true,
}) {
  String cap(String name) => captions ? name : "";
  // The colour settings, for their own row or behind the type button; the
  // swatch stays on the row either way, as colour is changed first.
  var swatch = CanvasColorButton(
    label: "Colour",
    color: spec.color,
    gradient: spec.fade,
    onChanged: (c) {
      begin();
      onChanged(spec.copyWith(color: c));
      commit();
    },
    onGradientChanged: (g) {
      begin();
      onChanged(
          g == null ? spec.copyWith(flatText: true) : spec.copyWith(fade: g));
      commit();
    },
  );

  // Italic and underline: on the row where colour is not, behind the button
  // where it is.
  var slanted = <Widget>[
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
    if (includeUnderline)
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
  ];

  var colourRow = <Widget>[
    // What the letters are painted with: colour first, or a picture or
    // pattern, under which outline and shadow keep their meaning.
    if (fill && context != null) ...[
      CanvasDropdown<TextFillKind>(
        key: const ValueKey("textFillKind"),
        label: "Painted with",
        value: spec.fill.kind,
        width: 118,
        options: [for (var k in TextFillKind.values) (k, k.label)],
        onChanged: (v) {
          begin();
          onChanged(spec.copyWith(fill: spec.fill.copyWith(kind: v)));
          commit();
        },
      ),
      // What that answer needs, on its line: choosing a picture is next.
      if (spec.fill.kind != TextFillKind.color)
        ...fillBits(context, spec.fill,
            (f) => onChanged(spec.copyWith(fill: f)), begin, commit),
      // The outline always starts its own line, so the first line is always
      // "what are these letters painted with".
      const CanvasLineBreak(),
    ],
    // The swatch can fade the words between two colours across their box,
    // unless outlined or filled with a picture or pattern. See TextSpec.fade.
    if (!colourInMore) swatch,
    if (looks) ...[
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
      // No caption: it is the outline's colour, beside its thickness.
      CanvasColorButton(
        color: spec.outlineColor,
        onChanged: (c) {
          begin();
          onChanged(spec.copyWith(outlineColor: c));
          commit();
        },
      ),
      // The shadow's amount and colour with them: two of each in the same
      // shape read as one line rather than four things.
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
        color: spec.shadowColor,
        onChanged: (c) {
          begin();
          onChanged(spec.copyWith(shadowColor: c));
          commit();
        },
      ),
    ],
  ];
  var colourMore = <Widget>[
    if (looks) ...[
      // Where the light is, not where the shadow goes: one light for a scene,
      // the same two numbers on every element in it.
      CanvasNumberField(
        key: const ValueKey("textShadowAngle"),
        label: "Direction",
        value: spec.shadowAngle,
        min: 0,
        max: 360,
        width: 60,
        onChanged: (v) => onChanged(spec.copyWith(shadowAngle: v)),
        onCommit: commit,
      ),
      CanvasNumberField(
        key: const ValueKey("textShadowDistance"),
        label: "Distance",
        value: spec.shadowDistance,
        min: 0,
        max: 400,
        decimals: 1,
        width: 60,
        onChanged: (v) => onChanged(spec.copyWith(shadowDistance: v)),
        onCommit: commit,
      ),
      CanvasNumberField(
        key: const ValueKey("textGlow"),
        label: "Glow",
        value: spec.glowBlur,
        min: 0,
        max: 200,
        width: 54,
        onChanged: (v) => onChanged(spec.copyWith(glowBlur: v)),
        onCommit: commit,
      ),
      CanvasColorButton(
        label: "Light",
        color: spec.glowColor,
        onChanged: (c) {
          begin();
          onChanged(spec.copyWith(glowColor: c));
          commit();
        },
      ),
      if (spec.shadowDistance > 0 || spec.shadowBlur > 0)
        const CanvasHint(
            "Direction is where the light is, read like a compass: 0 is "
            "straight up, 90 to the right. The shadow falls the other way, "
            "Distance away from the words. At a distance of 0 it sits "
            "directly underneath them, which is a shadow that reads as a "
            "glow in its own colour."),
      if (spec.glowBlur > 0)
        const CanvasHint(
            "Glow is light all round the letters, in its own colour, and it "
            "is drawn behind them — so a picture or a pattern showing "
            "through the words cannot cut it up, and an outline sits over "
            "it rather than under it."),
    ],
  ];

  return [
    CanvasMoreGroup(
        label: label,
        hideCaption: hideCaption,
        rule: rule,
        onRename: onRename,
        remember: "${remember}Type",
        tooltip: "Spacing, alignment and case",
        row: [
          ...rowBefore,
          CanvasDropdown<String>(
            label: cap("Font"),
            value: spec.fontFamily,
            // Least widths, not widths: six things share the line, and
            // wider minimums push the switches down in a narrow sidebar.
            width: 60,
            options: [for (var f in canvasFonts) (f, f)],
            onChanged: (v) {
              begin();
              onChanged(spec.copyWith(fontFamily: v));
              commit();
            },
          ),
          CanvasNumberField(
            key: const ValueKey("typeSize"),
            label: cap(fitted ? "Size (fitted)" : "Size"),
            value: spec.fontSize,
            min: 1,
            max: 800,
            width: 44,
            onChanged: (v) => onChanged(spec.copyWith(fontSize: v)),
            onCommit: commit,
          ),
          CanvasDropdown<int>(
            label: cap("Weight"),
            value: spec.weight,
            width: 56,
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
          // The colour, where folded in: it belongs on the line with the
          // face and size, not behind anything.
          if (colourInMore) swatch,
          if (!colourInMore) ...slanted,
        ],
        more: [
          // The colour first, as it is most of what is back here.
          if (colourInMore) ...[
            ...colourRow,
            // Shadow and glow on their own line, under colour and outline.
            if (colourMore.isNotEmpty) ...[
              const CanvasLineBreak(),
              ...colourMore,
            ],
            const CanvasLineBreak(),
          ],
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
          if (includeAlign)
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
          if (includeAlign)
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
          // The two switches end the spacing line, where the colour took
          // their place on the row above.
          if (colourInMore) ...slanted,
          ...extraMore,
        ]),
    if (!colourInMore)
      CanvasMoreGroup(
          label: "Colour",
          rule: rule,
          remember: "${remember}Colour",
          tooltip: "The shadow, the glow, and what shows through the letters",
          row: colourRow,
          more: colourMore),
  ];
}

/// boxGroup is the shared frame controls: background, border, corners and
/// padding. [fillLabel] names the background swatch; [onPadding] takes
/// padding for an element that does more than store it (a picture grows).
Widget boxGroup(BoxSpec box, ValueChanged<BoxSpec> onChanged,
        VoidCallback begin, VoidCallback commit,
        {String label = "Box",
        String fillLabel = "Fill",
        String remember = "box",
        bool rule = true,
        ValueChanged<BoxSpec>? onPadding,

        /// fill offers a picture or pattern behind the box, as for letters;
        /// [context] is then required.
        bool fill = false,
        BuildContext? context,

        /// compact lays it out as element panels do: fill and border colour
        /// side by side with their codes, the corners called Corners.
        bool compact = false}) =>
    // The colours and one number each for border, corners and room inside,
    // each splitting into four by its link: see CanvasSidesField.
    CanvasMoreGroup(
        label: label,
        rule: rule,
        remember: "${remember}Box",
        tooltip: "Each side and each corner on its own",
        row: [
          // Only where the box is painted a colour: a picture or pattern
          // covers it.
          if (compact)
            panelRow([
              if (box.painted.kind == TextFillKind.color)
                cell(CanvasColorButton(
                  label: fillLabel,
                  color: box.fill,
                  gradient: box.fillFade,
                  onChanged: (c) {
                    begin();
                    onChanged(box.copyWith(fill: c));
                    commit();
                  },
                  onGradientChanged: (g) {
                    begin();
                    onChanged(g == null
                        ? box.copyWith(flatFill: true)
                        : box.copyWith(fillFade: g));
                    commit();
                  },
                )),
              cell(CanvasColorButton(
                label: "Border colour",
                color: box.borderColor,
                gradient: box.borderFade,
                onChanged: (c) {
                  begin();
                  onChanged(box.copyWith(borderColor: c));
                  commit();
                },
                onGradientChanged: (g) {
                  begin();
                  onChanged(g == null
                      ? box.copyWith(flatBorder: true)
                      : box.copyWith(borderFade: g));
                  commit();
                },
              )),
            ])
          else ...[
            if (box.painted.kind == TextFillKind.color)
              CanvasColorButton(
                label: fillLabel,
                color: box.fill,
                gradient: box.fillFade,
                onChanged: (c) {
                  begin();
                  onChanged(box.copyWith(fill: c));
                  commit();
                },
                onGradientChanged: (g) {
                  begin();
                  onChanged(g == null
                      ? box.copyWith(flatFill: true)
                      : box.copyWith(fillFade: g));
                  commit();
                },
              ),
            CanvasColorButton(
              label: "Colour",
              color: box.borderColor,
              gradient: box.borderFade,
              onChanged: (c) {
                begin();
                onChanged(box.copyWith(borderColor: c));
                commit();
              },
              onGradientChanged: (g) {
                begin();
                onChanged(g == null
                    ? box.copyWith(flatBorder: true)
                    : box.copyWith(borderFade: g));
                commit();
              },
            ),
          ],
          ...roomFields(
              box.borders, (r) => onChanged(box.withBorders(r)), commit,
              label: "Border",
              allKey: "Border",
              sideKey: "Border",
              part: SidePart.all),
          ...cornerFields(
              box.corners, (c) => onChanged(box.withCorners(c)), commit,
              label: compact ? "Corners" : "Radius", part: SidePart.all),
          ...roomFields(
              box.pad, (r) => (onPadding ?? onChanged)(box.withRoom(r)), commit,
              part: SidePart.all),
          const CanvasHint(
              "Border, Radius and Padding set all four sides or corners at once; "
              "the link beside each splits it into one each. Sides of different "
              "weights are drawn square where they meet, since two weights "
              "cannot round the same corner."),
        ],
        more: [
          // The box's paint where offered, as the letters' is; the colour
          // keeps its swatch, as a picture is drawn over it.
          if (fill && context != null) ...[
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
              ...fillBits(context, box.painted,
                  (f) => onChanged(box.copyWith(painted: f)), begin, commit,
                  keyPrefix: "${remember}Box"),
            const CanvasLineBreak(),
          ],
          // Nothing for each side and corner alone: the row's fields split
          // into four (see SidePart).
          ...roomFields(
              box.borders, (r) => onChanged(box.withBorders(r)), commit,
              label: "Border",
              allKey: "Border",
              sideKey: "Border",
              part: SidePart.sides),
          // The border drawn inside the edge, a frame within the frame.
          if (box.hasBorder)
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
          const CanvasLineBreak(),
          ...cornerFields(
              box.corners, (c) => onChanged(box.withCorners(c)), commit,
              part: SidePart.sides),
          const CanvasLineBreak(),
          ...roomFields(
              box.pad, (r) => (onPadding ?? onChanged)(box.withRoom(r)), commit,
              part: SidePart.sides),
        ]);

/// valueDot is the diamond beside an animatable property: a real channel,
/// so a key can pin a caption's slide without pinning its box.
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

/// curveOptions is every line and path on the canvas for text to ride: to
/// a reader both are lines.
List<(String, String)> curveOptions(CanvasController controller) => [
      ("", "Nothing"),
      for (var element in controller.document.elements)
        if (element is LineElement || element is PathElement)
          (element.id, element.name),
    ];

/// boxed draws a rule and a gap round a section that is a panel (a table
/// with scrollbars), giving it an edge among captioned groups.
Widget boxed(BuildContext context, Widget child) => Builder(
    // Asked where drawn, not of [context], which is above any section: in a
    // section the box is the card the expander draws itself as.
    builder: (context) =>
        CanvasCards.on(context) ? child : _boxed(context, child));

Widget _boxed(BuildContext context, Widget child) {
  var theme = ThemeNotifier.of(context);
  return Padding(
    // A group's own gap below, so boxed sections and captioned groups space
    // alike.
    padding: const EdgeInsets.only(bottom: canvasGroupGap),
    // Builder, because the settings' context is above the CanvasControlScope
    // that says column or band, so asking it directly always says "band".
    child: Builder(
      builder: (context) => Container(
        // Full column width, open or shut: sized to itself, a shut section
        // shrinks to its heading and reads as a stray button.
        width: double.infinity,
        // Equal above and below, so a heading's button is not hard against
        // the top.
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
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

/// fillBits are one fill kind's controls: picture buttons, or a pattern's
/// style and colours. For letters, boxes and shapes.
List<Widget> fillBits(
  BuildContext context,
  TextFill fill,
  ValueChanged<TextFill> onChanged,
  VoidCallback begin,
  VoidCallback commit, {
  /// keyPrefix names the controls, as a panel can carry two sets: the
  /// letters' paint and their box's.
  String keyPrefix = "text",
}) {
  void now(TextFill next) {
    begin();
    onChanged(next);
    commit();
  }

  return [
    if (fill.kind == TextFillKind.image) ...[
      CanvasIconButton(
        key: ValueKey("${keyPrefix}FillPicture"),
        icon: fill.assetId.isEmpty
            ? Icons.add_photo_alternate
            : Icons.image_outlined,
        tooltip: fill.assetId.isEmpty
            ? "Choose a picture to show through the letters"
            : "Replace this picture",
        onPressed: () async {
          var id = await pickCanvasImage(context);
          if (id != null) now(fill.copyWith(assetId: id));
        },
      ),
      CanvasIconButton(
        key: ValueKey("${keyPrefix}FillLibrary"),
        icon: Icons.photo_library_outlined,
        tooltip: "Use a picture you have already added",
        onPressed: () async {
          var id = await showRecentPictures(context);
          if (id != null) now(fill.copyWith(assetId: id));
        },
      ),
      if (fill.assetId.isNotEmpty) ...[
        CanvasToggle(
          label: "Tile",
          value: fill.tile,
          onChanged: (v) => now(fill.copyWith(tile: v)),
        ),
        // A picture element's Look (filter, overlay), same names and order;
        // then the two sliders a picture keeps beside Fit.
        CanvasDropdown<ImageFilterPreset>(
          key: ValueKey("${keyPrefix}FillLook"),
          label: "Filter",
          value: fill.filter,
          width: 106,
          options: [for (var f in ImageFilterPreset.values) (f, f.label)],
          onChanged: (v) => now(fill.copyWith(filter: v)),
        ),
        CanvasDropdown<OverlayBlend>(
          key: ValueKey("${keyPrefix}FillBlend"),
          label: "Overlay",
          value: fill.blend,
          width: 106,
          options: [for (var b in OverlayBlend.values) (b, b.label)],
          onChanged: (v) => now(fill.copyWith(blend: v)),
        ),
        if (fill.blend != OverlayBlend.none)
          CanvasColorButton(
            key: ValueKey("${keyPrefix}FillOverlay"),
            label: "Colour",
            color: fill.overlay,
            // And two colours to fade between, as every swatch has: how a
            // photograph fades into a ground.
            gradient: fill.overlayFade,
            onChanged: (c) => now(fill.copyWith(overlay: c)),
            onGradientChanged: (g) => now(g == null
                ? fill.copyWith(flatOverlay: true)
                : fill.copyWith(overlayFade: g)),
          ),
        CanvasNumberField(
          key: ValueKey("${keyPrefix}FillSaturation"),
          label: "Saturation",
          value: fill.saturation,
          min: 0,
          max: 3,
          decimals: 2,
          width: 62,
          onChanged: (v) => onChanged(fill.copyWith(saturation: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: ValueKey("${keyPrefix}FillBrightness"),
          label: "Brightness",
          value: fill.brightness,
          min: 0,
          max: 3,
          decimals: 2,
          width: 62,
          onChanged: (v) => onChanged(fill.copyWith(brightness: v)),
          onCommit: commit,
        ),
      ],
    ],
    if (fill.kind == TextFillKind.pattern) ...[
      // The three choices a background starts from (style, look, colours):
      // a pattern in a word is the same pattern.
      patternStyleDropdown(
        key: ValueKey("${keyPrefix}FillPattern"),
        width: 138,
        label: "Pattern",
        spec: fill.pattern,
        onChanged: (p) => now(fill.copyWith(pattern: p)),
      ),
      patternLookDropdown(
        key: ValueKey("${keyPrefix}FillPatternLook"),
        width: 138,
        spec: fill.pattern,
        onChanged: (p) => now(fill.copyWith(pattern: p)),
      ),
      patternPaletteDropdown(
        context,
        key: ValueKey("${keyPrefix}FillPalette"),
        width: 138,
        spec: fill.pattern,
        onChanged: (p) => now(fill.copyWith(pattern: p)),
      ),
      const CanvasLineBreak(),
      // The same colour as a generated background's Base, so the pattern
      // behind a word can fade as a canvas's does.
      CanvasColorButton(
        label: "Behind",
        color: fill.pattern.background,
        gradient: fill.pattern.gradient,
        onChanged: (c) =>
            now(fill.copyWith(pattern: fill.pattern.copyWith(background: c))),
        onGradientChanged: (g) => now(fill.copyWith(
            pattern: g == null
                ? fill.pattern.copyWith(flatBackground: true)
                : fill.pattern.copyWith(gradient: g))),
      ),
      CanvasColorButton(
        label: "Ink",
        color: fill.pattern.foreground,
        onChanged: (c) =>
            now(fill.copyWith(pattern: fill.pattern.copyWith(foreground: c))),
      ),
      CanvasColorButton(
        label: "Second",
        color: fill.pattern.accent,
        onChanged: (c) =>
            now(fill.copyWith(pattern: fill.pattern.copyWith(accent: c))),
      ),
      CanvasNumberField(
        label: "How much",
        value: fill.pattern.density,
        min: 0,
        max: 1,
        decimals: 2,
        width: 58,
        onChanged: (v) => onChanged(
            (fill.copyWith(pattern: fill.pattern.copyWith(density: v)))),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Size",
        value: fill.pattern.scale,
        min: 0.005,
        max: 0.4,
        decimals: 3,
        width: 62,
        onChanged: (v) => onChanged(
            (fill.copyWith(pattern: fill.pattern.copyWith(scale: v)))),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Turn",
        value: fill.pattern.rotation,
        min: -180,
        max: 180,
        decimals: 0,
        width: 58,
        onChanged: (v) => onChanged(
            (fill.copyWith(pattern: fill.pattern.copyWith(rotation: v)))),
        onCommit: commit,
      ),
      CanvasIconButton(
        key: ValueKey("${keyPrefix}FillSeed"),
        icon: Icons.casino_outlined,
        tooltip: "Another one like it",
        onPressed: () => now(fill.copyWith(
            pattern: fill.pattern.copyWith(seed: fill.pattern.seed + 1))),
      ),
      // Back to the style's own settings, keeping the style.
      CanvasIconButton(
        key: ValueKey("${keyPrefix}FillReset"),
        icon: Icons.restart_alt,
        tooltip: "Put this pattern back to how it started",
        onPressed: () => now(fill.copyWith(
            pattern: switch (looksFor(fill.pattern.style).firstOrNull) {
          var first? => withLook(fill.pattern, first),
          null => ProceduralSpec(style: fill.pattern.style),
        })),
      ),
    ],
    // How much of it lands, for both kinds: knocked back, it is a ground, not
    // competing with the words. A colour has its own alpha.
    if (fill.on)
      CanvasNumberField(
        key: ValueKey("${keyPrefix}FillOpacity"),
        label: "Opacity",
        value: fill.opacity,
        min: 0,
        max: 1,
        decimals: 2,
        width: 58,
        onChanged: (v) => onChanged(fill.copyWith(opacity: v)),
        onCommit: commit,
      ),
    if (fill.on)
      CanvasNumberField(
        label: "Zoom",
        value: fill.zoom,
        min: 0.05,
        max: 20,
        decimals: 2,
        width: 58,
        onChanged: (v) => onChanged(fill.copyWith(zoom: v)),
        onCommit: commit,
      ),
    // Slid inside its frame, as a share of it: a face put in the middle of
    // a Layout cell, a flame moved to the word it should rise from.
    if (fill.on)
      CanvasNumberField(
        key: ValueKey("${keyPrefix}FillPanX"),
        label: "Across",
        value: fill.panX * 100,
        min: -200,
        max: 200,
        decimals: 0,
        suffix: "%",
        width: 58,
        onChanged: (v) => onChanged(fill.copyWith(panX: v / 100)),
        onCommit: commit,
      ),
    if (fill.on)
      CanvasNumberField(
        key: ValueKey("${keyPrefix}FillPanY"),
        label: "Down",
        value: fill.panY * 100,
        min: -200,
        max: 200,
        decimals: 0,
        suffix: "%",
        width: 58,
        onChanged: (v) => onChanged(fill.copyWith(panY: v / 100)),
        onCommit: commit,
      ),
    if (fill.on && (fill.panX != 0 || fill.panY != 0))
      CanvasIconButton(
        key: ValueKey("${keyPrefix}FillPanReset"),
        icon: Icons.filter_center_focus,
        tooltip: "Back to the middle",
        onPressed: () => now(fill.copyWith(panX: 0, panY: 0)),
      ),
    if (fill.on)
      CanvasToggle(
        key: ValueKey("${keyPrefix}FillLocked"),
        label: "Lock to the words",
        value: fill.locked,
        onChanged: (v) => now(fill.copyWith(locked: v)),
      ),
    if (fill.on)
      const CanvasHint(
          "Whatever is chosen is drawn across the whole line and then cut to "
          "the shape of the letters — so a flame or a splatter runs through "
          "the words rather than restarting inside each one. Zoom sizes it "
          "against them: 1 fits it across the words, 2 shows a quarter of it "
          "at twice the size. Across and Down slide it inside its frame."),
    // The rest of the pattern style's settings and effects, behind a
    // heading: a background's controls less those on the row above.
    if (fill.kind == TextFillKind.pattern) ...[
      const CanvasLineBreak(),
      CanvasFill(
        child: SizedBox(
          width: 200,
          child: CanvasExpander(
            key: ValueKey("${keyPrefix}FillPatternMore"),
            label: "Pattern settings",
            remember: "$keyPrefix.patternMore",
            children: [
              ProceduralSettings(
                fill: true,
                spec: fill.pattern,
                onChanged: (p) => onChanged(fill.copyWith(pattern: p)),
                onBegin: begin,
                onCommit: commit,
              ),
            ],
          ),
        ),
      ),
    ],
    if (fill.on && fill.locked)
      const CanvasHint(
          "Locked, the picture travels with the words while they arrive, so "
          "the same bit of it shows through the same letter from the first "
          "frame to the last. Unlocked it stays pinned to the box and the "
          "words sweep across it. It follows a whole-paragraph arrival; "
          "letter by letter there is no single movement to follow."),
  ];
}

/// anchorButtons are the anchor point: shown on stage to drag, or hidden;
/// while shown, locked or re-centred. See ElementBase.anchorX.
Widget anchorButtons(CanvasController controller, CanvasElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var shown = controller.anchorShown(e.id);
  var locked = e.base.anchorLocked;
  // One cluster: three buttons about one thing, kept together.
  return Row(
      key: const ValueKey("elementAnchor"),
      mainAxisSize: MainAxisSize.min,
      children: [
        CanvasIconButton(
          key: const ValueKey("elementAnchorShow"),
          icon: shown ? Icons.gps_fixed : Icons.gps_not_fixed,
          tooltip: shown ? "Hide anchor" : "Show anchor",
          active: shown,
          onPressed: () => controller.showAnchor(e.id, !shown),
        ),
        if (shown) ...[
          CanvasIconButton(
            key: const ValueKey("elementAnchorLock"),
            icon: locked ? Icons.lock_outline : Icons.lock_open,
            tooltip: locked ? "Unlock anchor" : "Lock anchor",
            active: locked,
            onPressed: () {
              begin();
              write(e.withBase(anchorLocked: !locked));
              commit();
            },
          ),
          CanvasIconButton(
            key: const ValueKey("elementAnchorReset"),
            icon: Icons.center_focus_strong_outlined,
            tooltip: "Centre anchor",
            onPressed: e.anchorCentred
                ? null
                : () {
                    begin();
                    write(e.withBase(anchorX: 0.5, anchorY: 0.5));
                    commit();
                  },
          ),
        ],
      ]);
}

/// previewButton plays [element]'s animation alone, once, or stops it while
/// playing. See CanvasController.previewElement.
Widget previewButton(CanvasController controller, CanvasElement element) {
  var going = controller.previewing?.id == element.id;
  return CanvasIconButton(
    key: const ValueKey("elementAnimationPreview"),
    // In a section's heading, beside its words, not below them.
    tight: true,
    icon: going ? Icons.stop_circle_outlined : Icons.play_circle_outline,
    tooltip: going ? "Stop" : "Preview",
    active: going,
    onPressed: () =>
        going ? controller.pause() : controller.previewElement(element.id),
  );
}

/// effectBits are a cutting preset's settings (pieces, throw, turn), for
/// element and text animations; [scatters] false hides throwing where
/// pieces stay put (mosaic, glitch).
List<Widget> effectBits(
  EffectSpec effect,
  bool scatters,
  void Function(EffectSpec) now,
  VoidCallback begin,
  VoidCallback commit, {
  required void Function(EffectSpec) live,
}) =>
    [
      CanvasControlGroup(label: "The pieces", children: [
        CanvasNumberField(
          key: const ValueKey("effectPieces"),
          label: "Across",
          min: 1,
          max: 64,
          decimals: 0,
          width: 62,
          value: effect.pieces.toDouble(),
          onChanged: (v) => live(effect.copyWith(pieces: v.round())),
          onCommit: commit,
        ),
        if (scatters) ...[
          CanvasNumberField(
            key: const ValueKey("effectScatter"),
            label: "Thrown",
            min: 0,
            max: 8,
            decimals: 2,
            width: 62,
            value: effect.scatter,
            onChanged: (v) => live(effect.copyWith(scatter: v)),
            onCommit: commit,
          ),
          CanvasNumberField(
            key: const ValueKey("effectSpin"),
            label: "Turn",
            min: -4,
            max: 4,
            decimals: 2,
            width: 62,
            value: effect.spin,
            onChanged: (v) => live(effect.copyWith(spin: v)),
            onCommit: commit,
          ),
        ],
        CanvasNumberField(
          key: const ValueKey("effectStagger"),
          label: "Spread",
          min: 0,
          max: 1,
          decimals: 2,
          width: 62,
          value: effect.stagger,
          onChanged: (v) => live(effect.copyWith(stagger: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: const ValueKey("effectSeed"),
          label: "Shuffle",
          min: 1,
          max: 9999,
          decimals: 0,
          width: 62,
          value: effect.seed.toDouble(),
          onChanged: (v) => live(effect.copyWith(seed: v.round())),
          onCommit: commit,
        ),
        CanvasHint(scatters
            ? "Across is how many pieces the element is cut into along its "
                "width; the rows follow, so a piece stays roughly square. "
                "Thrown is how far a piece travels to get to its place, as a "
                "fraction of the element — 0 leaves every piece where it "
                "belongs and the effect becomes a fade in tiles. Spread is "
                "how much later the last piece moves than the first: 0 moves "
                "them all together."
            : "Across is how coarse the cut is: the blocks of a mosaic, the "
                "slices of a glitch. Spread is how much later the last one "
                "settles than the first."),
      ]),
    ];

/// SidePart is which half to build: the all-sides number, the four, or
/// both. One CanvasSidesField holds the four, so [SidePart.sides] is empty.
enum SidePart { all, sides, both }

/// cornerFields is the corners as one control (a number for all four and a
/// splitting link), shared by an element's frame and a rectangle shape.
List<Widget> cornerFields(
        Corners corners, ValueChanged<Corners> onChanged, VoidCallback commit,
        {String label = "Radius",
        String prefix = "box",
        SidePart part = SidePart.both}) =>
    // One control for the four (see CanvasSidesField). Asked for the sides
    // alone, there is nothing more: they are in it.
    part == SidePart.sides
        ? const []
        : [
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
        String prefix = "box",
        // The keys' name, so a second set in one panel (border beside
        // padding) is findable by what it is.
        String allKey = "Padding",
        String sideKey = "Pad",
        SidePart part = SidePart.both}) =>
    part == SidePart.sides
        ? const []
        : [
            CanvasSidesField(
              name: "$prefix$allKey",
              label: label,
              max: 400,
              values: [room.top, room.right, room.bottom, room.left],
              parts: const ["Top", "Right", "Bottom", "Left"],
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

/// easeDropdown is a choice of easing, each drawn as its curve; [curve] is
/// the easing over 0..1.
Widget easeDropdown<T>({
  Key? key,
  String label = "Curve",
  required T value,
  required List<T> values,
  required String Function(T) name,
  required double Function(double) Function(T) curve,
  required ValueChanged<T> onChanged,
  double width = 148,
  bool enabled = true,
}) =>
    CanvasDropdown<T>(
      key: key,
      label: label,
      value: value,
      width: width,
      enabled: enabled,
      options: [for (var v in values) (v, name(v))],
      leading: (v) => EaseCurve(curve(v)),
      onChanged: onChanged,
    );

/// EaseCurve is a small drawing of an easing: time along, progress up, the
/// start and end levels marked so an overshoot shows.
class EaseCurve extends StatelessWidget {
  final double Function(double) curve;
  const EaseCurve(this.curve, {super.key});

  @override
  Widget build(BuildContext context) {
    var colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 22,
      height: 14,
      child: CustomPaint(
          painter: _EaseCurvePainter(
              curve, colors.primary, colors.outline.withValues(alpha: 0.35))),
    );
  }
}

class _EaseCurvePainter extends CustomPainter {
  final double Function(double) curve;
  final Color ink;
  final Color guide;
  _EaseCurvePainter(this.curve, this.ink, this.guide);

  @override
  void paint(Canvas canvas, Size size) {
    // Room above and below for a curve that goes past either end.
    var top = size.height * 0.22, bottom = size.height * 0.85;
    double y(double v) => bottom - (bottom - top) * v;
    var lines = Paint()
      ..color = guide
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), lines);
    canvas.drawLine(Offset(0, y(1)), Offset(size.width, y(1)), lines);
    var path = Path();
    const steps = 40;
    for (var i = 0; i <= steps; i++) {
      var t = i / steps;
      var at = Offset(size.width * t, y(curve(t)).clamp(0.0, size.height));
      i == 0 ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_EaseCurvePainter old) =>
      old.curve != curve || old.ink != ink || old.guide != guide;
}

/// shortNumber is [v] as a summary writes it: whole where whole, else to
/// one place.
String shortNumber(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
