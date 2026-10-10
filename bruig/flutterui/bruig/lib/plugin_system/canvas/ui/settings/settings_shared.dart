import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
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
  ///
  /// Lit by a keyframe that actually *poses* the element, not by any keyframe
  /// standing on this frame. A counter's count, a chart's arrival and a
  /// caption's slide are keyframes that say nothing about where the element
  /// is, and lighting the pose diamond for those told the reader that the
  /// position, size, angle and fade were pinned here when they were not --
  /// and pressing it then took the count away with the pose. The same rule
  /// ElementTrack.posesAnything uses, asked of one keyframe: a rest key laid
  /// deliberately is a pose, because holding something still is posing it.
  var here = e.track?.keyAt(frame);
  var hasKey = here != null && (here.posesElement || here.values.isEmpty);
  void toggleKey() {
    begin();
    if (hasKey) {
      // The pose only: whatever else that frame pinned -- a counter's number,
      // a chart's arrival -- is not this diamond's to take away.
      controller.clearPose(e.id, frame);
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

  /// resize writes a new width or height, holding the proportions when the
  /// element has asked for that -- see ElementBase.lockAspect.
  ///
  /// Held by scaling the other side by the same factor, rather than by
  /// refusing the edit. The lock is about the shape, not about the size: it
  /// must not stop a resize, only stop a resize from changing the proportions.
  ///
  /// Both numbers show what is on screen -- the resting size times the pose's
  /// scale -- but always edit the resting size. A pose scales evenly, so there
  /// is no keyframe that could hold a width without also holding a height, and
  /// pretending otherwise would give two fields one number.
  void resize({double? width, double? height}) {
    // The undo step, as moveTo opens one. Typing into a field is an edit like
    // any other, and without this a resize is not undoable.
    begin();
    var scale = pose.scale == 0 ? 1.0 : pose.scale;
    if (!e.base.lockAspect) {
      write(e.withBase(
        width: width == null ? null : width / scale,
        height: height == null ? null : height / scale,
      ));
      return;
    }

    // The factor the edited side has moved by, applied to both. Guarded
    // against a zero on either side: an element with no width has no
    // proportions to keep, and dividing by it would put every element on the
    // canvas at nothing.
    var by = width != null
        ? (box.width <= 0 ? 1 : width / box.width)
        : (box.height <= 0 ? 1 : height! / box.height);
    if (!by.isFinite || by <= 0) return;

    write(e.withBase(
      width: box.width * by / scale,
      height: box.height * by / scale,
    ));
  }

  // Text riding a line has no position or angle of its own: where it is and
  // how it is turned are the line's to decide. The fields were still there and
  // still writable, so nudging them moved the words off the line they were
  // attached to -- which is the one thing attaching them is meant to prevent.
  // The line has to still be there. A text element whose line has been
  // deleted falls back to its own box on the canvas -- see _curveFor -- so a
  // panel that went on saying otherwise was describing something that was no
  // longer true, and hiding the fields for the box it had gone back to.
  if (e is TextElement &&
      e.curve != null &&
      controller.document.elementById(e.curve!.elementId) != null) {
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
      hideCaption: true,
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
          key: const ValueKey("elementW"),
          label: "W",
          value: box.width,
          min: 1,
          onChanged: (v) => resize(width: v),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: const ValueKey("elementH"),
          label: "H",
          value: box.height,
          min: 1,
          onChanged: (v) => resize(height: v),
          onCommit: commit,
        ),
        // The lock beside the two numbers it holds together, rather than
        // somewhere else describing them. It was a picture's own setting; a
        // picture is only the most obvious thing with proportions worth
        // keeping.
        CanvasIconButton(
          icon: e.base.lockAspect ? Icons.link : Icons.link_off,
          tooltip: e.base.lockAspect
              ? "Proportions are held — the width and the height move together"
              : "Width and height are free of each other",
          active: e.base.lockAspect,
          onPressed: () {
            begin();
            write(e.withBase(lockAspect: !e.base.lockAspect));
            commit();
          },
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
          // The same least width as X above it. The fields share out what is
          // left of the line evenly, so equal minimums put Angle in X's
          // column and Opacity in Y's -- which is the only reason the second
          // line of this group reads as a second line rather than as a
          // different group.
          width: 62,
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
        anchorButtons(controller, e, write, begin, commit),
        poseDot,
        // A counter on a document of pages can be the page number, and this
        // is where it is said. Beside what the element *is* on this page
        // rather than three controls into the counter's own settings, which
        // is where it was and where nobody found it -- and next to "Own on
        // A4", because the two are the same sort of question: what does this
        // element do on the leaf it is drawn on.
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
          // And which edge it sits against, for the page number that belongs
          // on the outside of the leaf. See CounterElement.mirrored.
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
        // What this element does on this shape of page, for a document being
        // laid out for several. Only then: on a canvas made for one shape
        // there is one design and nothing to say about it.
        if (controller.document.targets.length > 1) ...[
          // Air, not just a break: what follows is about this ratio rather
          // than about the element, and with the ordinary break it read as a
          // third line of the position group.
          const CanvasLineBreak(gap: 8),
          // How big everything inside the box is on this shape. It leaves the
          // box where it is and scales what it holds -- the type, the
          // spacing, the padding, the room in a chip -- which is what a
          // headline that carries a banner on a screen and is a word on a
          // line on a feed actually needs. See ElementBase.typeScale.
          //
          // Only where it does something. On a picture, a shape or a chart
          // scaledBy changes nothing -- the contents are already fractions of
          // the box -- so the field was a number that moved while the canvas
          // stayed still, which is what was reported.
          if (e.scalesInside) ...[
            CanvasNumberField(
              key: const ValueKey("elementTypeScale"),
              label: "Scale inside",
              value: e.base.typeScale,
              min: 0.05,
              max: 10,
              decimals: 2,
              width: 84,
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
            CanvasHint(
                "Everything inside the box at once, on the shape of page you "
                "are on: the type, the line spacing, the padding, the corners "
                "and the rules. The box itself stays where you put it. Type "
                "size on its own is the Type group's Size — this is that and "
                "the room round it together, which is what keeps a design "
                "looking like itself at another size."),
          ],
          // And the way out of sharing altogether, for the element the one
          // design cannot carry.
          CanvasToggle(
            key: const ValueKey("elementOwnDesign"),
            label: "Own on ${shapeShort(shapeKey(controller.document.size))}",
            value: e.base.ownDesign,
            onChanged: (v) {
              begin();
              // The shared design is kept aside as this one is detached, and
              // put back the moment it is not -- see detachedHere.
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

  /// hideCaption drops the first group's caption in a sidebar, for the
  /// callers that have already headed a section with the same word.
  bool hideCaption = false,

  /// fill offers a picture or a pattern showing through the letters.
  ///
  /// A text element's, and nothing else's: the words on a chart's axis or in
  /// a table cell are labels, and a flame pattern inside a column heading is
  /// not a thing anybody is going to want. [context] is what a picture is
  /// chosen with, so it is required wherever this is on.
  bool fill = false,
  BuildContext? context,

  /// remember prefixes the two buttons' open state, so that a panel carrying
  /// three sets of these -- a counter has one for the number, one for the
  /// words and one for the buttons -- does not open all three at once.
  String remember = "type",

  /// rule draws the line under each of these groups.
  ///
  /// Off where they are one run with what comes after them rather than two
  /// subjects: on a text element the face, the colour and the box are all
  /// "how do these words look", and three lines through that run made it read
  /// as three answers to three different questions.
  bool rule = true,

  /// extraMore is put behind the first button, under the spacing settings.
  /// For the element that has something of its own to hide there: a text
  /// element's marks, which belong with how the words are set rather than
  /// with what they say.
  List<Widget> extraMore = const [],

  /// colourInMore puts the colour settings behind the type button instead of
  /// on a row of their own, so that everything about one piece of writing is
  /// one line and one button.
  ///
  /// For the element that has *several* pieces of writing in it: a text
  /// element's items are a row each, and a row each plus a colour row each is
  /// a panel where nothing can be found. Everywhere else the colour keeps its
  /// own row, because there is only one thing on the element to colour and
  /// the swatch is worth seeing.
  bool colourInMore = false,

  /// rowBefore is put at the front of the type row, before the face.
  ///
  /// For the caller that has something of its own to say about *which* piece
  /// of writing this row is: a text element's items each carry the slot they
  /// sit in and a button to take them away, and they are the first thing on
  /// the line because they are what tells one row from the next.
  List<Widget> rowBefore = const [],

  /// captions draws the controls' own captions. Off for the second and later
  /// of a run of these -- a list of items is a column of the same controls,
  /// and the words Font, Size and Weight written over every row is the same
  /// three words four times.
  ///
  /// The room is still reserved, so the rows line up. See _labelled.
  bool captions = true,

  /// includeAlign offers the two alignment dropdowns behind the button.
  ///
  /// Off for a piece of writing whose place is decided for it: a text
  /// element's item is held to the corner of the box its slot names, so an
  /// Align dropdown on its row was a control that did nothing -- which is
  /// worse than no control at all.
  bool includeAlign = true,

  /// includeUnderline offers the underline switch.
  ///
  /// Off for the element that has a *drawn* underline as well -- a text
  /// element's marks, which can be a colour, a width and a distance under the
  /// words rather than whatever the face does. Two switches called Underline
  /// in one panel is one of them too many, and the one that can do more is
  /// the one to keep.
  bool includeUnderline = true,

  /// onRename makes the group's caption a name that can be typed into, for
  /// the callers whose caption is a name rather than a heading: a text
  /// element's pieces, and the element itself.
  ValueChanged<String>? onRename,
}) {
  String cap(String name) => captions ? name : "";
  // The colour settings, as a row and as what is behind its button. Built
  // here rather than written twice: they are the same controls whether
  // they stand as a group of their own or go behind the type button.
  // The swatch alone. Where the colour has been folded in behind the type
  // button it goes on the *row* instead: what colour the words are is the
  // first thing anybody changes about them and the last thing that should be
  // behind a button, and a swatch is small enough to sit on a full line.
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

  // Italic and underline. On the row where the colour is not -- there is room
  // for two switches there -- and behind the button where it is, since the
  // colour has taken their place and they are set once where a colour is
  // changed again and again.
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
    // What the letters are painted with. The colour is the usual answer
    // and stays first; a picture or a pattern replaces it, and the
    // outline and shadow settings under it go on meaning what they mean.
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
      // What that answer needs, on the line with the answer: choosing a
      // picture is the next thing anybody does after saying "a picture", and
      // it was two lines further down under the outline.
      if (spec.fill.kind != TextFillKind.color)
        ...fillBits(context, spec.fill,
            (f) => onChanged(spec.copyWith(fill: f)), begin, commit),
      // The outline starts a line of its own either way, so that what is on
      // the first line is always "what are these letters painted with".
      const CanvasLineBreak(),
    ],
    // The words can fade from one colour to another, across the box they are
    // drawn in. Not where they are outlined rather than filled, or where a
    // picture or a pattern is showing through them: each of those already
    // decides what the letters are painted with. See TextSpec.fade.
    if (!colourInMore) swatch,
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
    // No caption of its own: it is the outline's colour, and it sits against
    // the number that says how thick the outline is. "Outline" and "Line" on
    // two controls in a row reads as two settings about two different lines.
    CanvasColorButton(
      color: spec.outlineColor,
      onChanged: (c) {
        begin();
        onChanged(spec.copyWith(outlineColor: c));
        commit();
      },
    ),
    // The shadow's amount and colour with them: four controls, two of each,
    // and the same shape twice reads as one line rather than as four things.
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
  ];
  var colourMore = <Widget>[
    // Where the light is, not where the shadow goes: one light for a
    // scene, and the same two numbers on every element in it.
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
            // The least these three will be, not the width they are. Six
            // things share this line -- the face, the size, the weight, two
            // switches and the button -- and the three boxes between them
            // were asking for two hundred and fifty-four pixels, which is
            // what pushed the switches onto a line of their own the moment
            // anybody pulled the sidebar in. They grow back into a wide one.
            // Trimmed again when the gap after a captioned control went from
            // five pixels to eight.
            width: 60,
            options: [for (var f in canvasFonts) (f, f)],
            onChanged: (v) {
              begin();
              onChanged(spec.copyWith(fontFamily: v));
              commit();
            },
          ),
          CanvasNumberField(
            label: cap("Size"),
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
          // The colour, where it has been folded in behind the button: what
          // colour the words are belongs on the line with the face and the
          // size, not behind anything.
          if (colourInMore) swatch,
          if (!colourInMore) ...slanted,
        ],
        more: [
          // The colour first, because it is the most of what is back here.
          if (colourInMore) ...[
            ...colourRow,
            // The shadow and the glow on a line of their own, under the
            // colour and the outline: six controls run on from four is one
            // row of ten that wraps wherever it happens to fill up.
            const CanvasLineBreak(),
            ...colourMore,
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
          // The two switches at the end of the line the spacing is on, where
          // the colour has taken their place on the row above.
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

/// boxGroup is the shared frame controls: the background, the border, the
/// corners and the room inside.
///
/// [fillLabel] names the background swatch. "Fill" is right for a box drawn
/// round words; a picture's is the colour that shows *behind* the picture,
/// and calling that a fill had somebody asking for a background colour that
/// was already there.
/// [onPadding] is where a change to the room inside goes, for an element that
/// wants to do something besides store it -- a picture grows its own box
/// rather than shrinking the picture inside a box that stays put. Left out,
/// padding is written like everything else.
Widget boxGroup(BoxSpec box, ValueChanged<BoxSpec> onChanged,
        VoidCallback begin, VoidCallback commit,
        {String label = "Box",
        String fillLabel = "Fill",
        String remember = "box",
        bool rule = true,
        ValueChanged<BoxSpec>? onPadding,

        /// fill offers a picture or a pattern behind the box instead of a
        /// colour, the same three answers the letters have. [context] is what
        /// a picture is chosen with, so it is required wherever this is on.
        bool fill = false,
        BuildContext? context}) =>
    // The colours and one number each for the border, the corners and the
    // room inside; the twelve that set a side or a corner on its own are
    // behind the button. Laid out flat this was three lines of five numbers,
    // and the three anybody actually sets were the first of each line.
    CanvasMoreGroup(
        label: label,
        rule: rule,
        remember: "${remember}Box",
        tooltip: "Each side and each corner on its own",
        row: [
          // Only where the box is painted with a colour. A picture or a
          // pattern is drawn over the whole of it, so the swatch sat there
          // doing nothing visible -- and a colour control that changes
          // nothing is worse than no colour control.
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
          ...roomFields(
              box.borders, (r) => onChanged(box.withBorders(r)), commit,
              label: "Border",
              allKey: "Border",
              sideKey: "Border",
              part: SidePart.all),
          ...cornerFields(
              box.corners, (c) => onChanged(box.withCorners(c)), commit,
              part: SidePart.all),
          ...roomFields(
              box.pad, (r) => (onPadding ?? onChanged)(box.withRoom(r)), commit,
              part: SidePart.all),
        ],
        more: [
          // What the box is painted with, where the caller offers the choice:
          // the same three answers the letters have, because it is the same
          // question of a different shape. Behind the button like the
          // letters' own, and for the same reason -- it is chosen once, where
          // the row in front is the things that are changed again and again.
          // The colour keeps its swatch out there either way: a picture
          // behind a box is drawn over whatever colour is under it.
          if (fill && context != null) ...[
            CanvasDropdown<TextFillKind>(
              key: ValueKey("${remember}BoxFillKind"),
              label: "Painted with",
              value: box.painted.kind,
              width: 118,
              options: [for (var k in TextFillKind.values) (k, k.label)],
              onChanged: (v) {
                begin();
                onChanged(box.copyWith(painted: box.painted.copyWith(kind: v)));
                commit();
              },
            ),
            // Asked by the *kind*, not by whether the fill is on: a picture
            // is not on until one has been chosen, and the buttons that
            // choose one are these. Guarded by `on`, saying "a picture" hid
            // the only way to name it.
            if (box.painted.kind != TextFillKind.color)
              ...fillBits(context, box.painted,
                  (f) => onChanged(box.copyWith(painted: f)), begin, commit,
                  keyPrefix: "${remember}Box"),
            const CanvasLineBreak(),
          ],
          // A line each for the border, the corners and the sides. Wrapped into
          // whatever room the panel had, they came out as one row of unrelated
          // numbers with a corner on the end of the border's line.
          ...roomFields(
              box.borders, (r) => onChanged(box.withBorders(r)), commit,
              label: "Border",
              allKey: "Border",
              sideKey: "Border",
              part: SidePart.sides),
          const CanvasLineBreak(),
          ...cornerFields(
              box.corners, (c) => onChanged(box.withCorners(c)), commit,
              part: SidePart.sides),
          const CanvasLineBreak(),
          ...roomFields(
              box.pad, (r) => (onPadding ?? onChanged)(box.withRoom(r)), commit,
              part: SidePart.sides),
          const CanvasHint(
              "Border, Radius and Padding on the line above set all four sides or "
              "corners at once; these set one each, and the one above shows blank "
              "when the four no longer agree. Sides of different weights are drawn "
              "square where they meet, since two weights cannot round the same "
              "corner."),
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
    // The same gap a group leaves under itself, so a boxed section and a
    // captioned group are the same distance from what follows them.
    padding: const EdgeInsets.only(bottom: canvasGroupGap),
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
        width: double.infinity,
        // The same above and below. It was 2 and 8, which nobody notices on a
        // section that is open -- and on a closed one carrying a button in its
        // heading it put the button hard against the top edge with six pixels
        // of nothing under it.
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

/// _fillBits are the controls for a picture or a pattern inside the letters.
///
/// The pattern is an ordinary generated background -- the same styles, the
/// same colours, the same sliders -- because it is exactly the same thing
/// drawn in a different shape. Writing a second set of patterns for text
/// would be two lists of styles to keep level with each other.
/// fillBits are the controls one kind of fill needs: the two buttons that
/// choose a picture, or the pattern's own style and colours.
///
/// Public, because three things can be painted with one now -- the letters, a
/// box and a shape -- and a second copy of these is a second copy to keep
/// level with the first.
List<Widget> fillBits(
  BuildContext context,
  TextFill fill,
  ValueChanged<TextFill> onChanged,
  VoidCallback begin,
  VoidCallback commit, {
  /// keyPrefix names the controls, since a panel can now carry two sets of
  /// them: what the letters are painted with and what their box is.
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
        // What a picture element calls its Look, on the picture that is
        // showing through something else: the named filter and the overlay,
        // with the same names and in the same order, because it is the same
        // picture and the same question about it. The two sliders a picture
        // element keeps beside its Fit follow them.
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
            // And two colours to fade between, like every other swatch: an
            // overlay that runs from one colour to another across the
            // picture is how a photograph is faded into a ground.
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
    if (fill.kind == TextFillKind.pattern)
      CanvasDropdown<ProceduralStyle>(
        key: ValueKey("${keyPrefix}FillPattern"),
        label: "Pattern",
        value: fill.pattern.style,
        width: 150,
        options: [
          for (var s in ProceduralStyle.values)
            if (!s.hidden || s == fill.pattern.style) (s, s.label),
        ],
        onChanged: (v) =>
            now(fill.copyWith(pattern: fill.pattern.copyWith(style: v))),
      ),
    if (fill.kind == TextFillKind.pattern) ...[
      // The same colour a generated background's "Base" is, so the second
      // colour it fades to is chosen in the same picker and the pattern
      // behind a word can fade the way the one behind a whole canvas does.
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
      // Back to the settings the style arrives with, keeping the style
      // itself: a pattern nobody likes any more is quicker to start again
      // than to put back a colour, a density, a size and a turn at a time.
      CanvasIconButton(
        key: ValueKey("${keyPrefix}FillReset"),
        icon: Icons.restart_alt,
        tooltip: "Put this pattern back to how it started",
        onPressed: () => now(
            fill.copyWith(pattern: ProceduralSpec(style: fill.pattern.style))),
      ),
    ],
    // How much of it lands, for both kinds: a picture or a pattern knocked
    // back is a ground rather than a thing competing with the words. A
    // colour needs none of this -- its own alpha is in the picker.
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
          "at twice the size."),
    if (fill.on && fill.locked)
      const CanvasHint(
          "Locked, the picture travels with the words while they arrive, so "
          "the same bit of it shows through the same letter from the first "
          "frame to the last. Unlocked it stays pinned to the box and the "
          "words sweep across it. It follows a whole-paragraph arrival; "
          "letter by letter there is no single movement to follow."),
  ];
}

/// elementAnimationSection is how a shape or a picture arrives and leaves.
///
/// The text element's animation section for the kinds that have no words. One
/// function shared by both panels rather than one each, because they are the
/// same question with the same answers: a shape flying in and a photograph
/// flying in are the same animation, and two sections would be two places for
/// a preset to go missing.
///
/// [write] is only for the settings that are not the preset itself. Choosing a
/// preset goes through the controller, because it lays keyframes as well as
/// setting a name -- see CanvasController.applyElementAnimation.
Widget elementAnimationSection(
  CanvasController controller,
  CanvasElement element,
  ElementAnimation animation,
  void Function(ElementAnimation) write,
  VoidCallback begin,
  VoidCallback commit, {
  void Function(ElementAnimationPreset)? arrive,
  void Function(ElementAnimationPreset)? leave,
  List<Widget> heading = const [],
  bool timing = true,
  bool preview = true,
}) {
  void now(ElementAnimation next) {
    begin();
    write(next);
    commit();
  }

  var keyed = timing
      ? keyframeEasingControls(controller, element, begin, commit,
          label: "Keyframe")
      : const <Widget>[];

  // Choosing an arrival or an exit lays its keyframes as well as naming it
  // -- unless whoever is showing this says otherwise: a drawing's shape
  // takes its own, on the drawing's keyframes.
  var arriveWith =
      arrive ?? (p) => controller.applyElementAnimation(element, p);
  var leaveWith = leave ?? (p) => controller.applyElementExit(element, p);

  // Which way it comes in, and how far -- and, apart from that, which way
  // it goes out, and how far.
  void live(ElementAnimation next) {
    begin();
    write(next);
  }

  return CanvasExpander(
    label: "Animation",
    remember: "elementAnimation",
    // Preview in the heading, where it works open or shut -- or, for a
    // drawing, in its playlist's.
    action:
        preview && animation.any ? previewButton(controller, element) : null,
    trailing: animation.any
        ? [
            if (animation.on) presetName(animation.preset),
            if (animation.closes) presetName(animation.exit),
            if (animation.loop.on) "${animation.loop.preset.label} loop",
          ].join(" · ")
        : null,
    children: [
      ...heading,
      CanvasControlGroup(label: "Arriving", children: [
        CanvasDropdown<ElementAnimationFamily?>(
          key: const ValueKey("elementAnimationFamily"),
          label: "Kind",
          value: animation.on ? animation.preset.family : null,
          // The same as Which beside it: the two share the line evenly.
          width: 110,
          options: [
            (null, "None"),
            for (var family in ElementAnimationFamily.values)
              (family, family.label),
          ],
          onChanged: (family) => arriveWith(family == null
              ? ElementAnimationPreset.none
              : ElementAnimationPreset.inFamily(family).first),
        ),
        if (animation.on && !oneOfAKind(animation.preset))
          CanvasDropdown<ElementAnimationPreset>(
            key: const ValueKey("elementAnimationPreset"),
            label: "Which",
            value: animation.preset,
            width: 110,
            options: [
              for (var preset
                  in ElementAnimationPreset.inFamily(animation.preset.family))
                (preset, preset.label),
            ],
            onChanged: arriveWith,
          ),
        // Kind and Which share their line; the motion has the next.
        if (animation.on &&
            (animation.arrivalDirected || animation.arrivalStrengthens)) ...[
          const CanvasLineBreak(),
          ...motionControls(animation, now, live, commit),
        ],
      ]),
      if (animation.on || animation.closes)
        CanvasControlGroup(label: "Leaving", children: [
          CanvasDropdown<ElementAnimationFamily?>(
            key: const ValueKey("elementAnimationExitFamily"),
            label: "Kind",
            value: animation.closes ? animation.exit.family : null,
            width: 110,
            options: [
              (null, "None"),
              for (var family in ElementAnimationFamily.values)
                (family, family.label),
            ],
            onChanged: (family) => leaveWith(family == null
                ? ElementAnimationPreset.none
                : ElementAnimationPreset.inFamily(family).first),
          ),
          if (animation.closes && !oneOfAKind(animation.exit))
            CanvasDropdown<ElementAnimationPreset>(
              key: const ValueKey("elementAnimationExit"),
              label: "Which",
              value: animation.exit,
              width: 110,
              options: [
                for (var preset
                    in ElementAnimationPreset.inFamily(animation.exit.family))
                  (preset, "${preset.label}, reversed"),
              ],
              onChanged: leaveWith,
            ),
          if (animation.closes &&
              (animation.exitDirected || animation.exitStrengthens)) ...[
            const CanvasLineBreak(),
            ...motionControls(animation, now, live, commit, leaving: true),
          ],
        ]),
      loopGroup(controller, animation.loop,
          (loop) => now(animation.copyWith(loop: loop)), (loop) {
        begin();
        write(animation.copyWith(loop: loop));
      }, commit),
      if (animation.cuts)
        ...effectBits(
            animation.effect,
            animation.scatters,
            (next) => now(animation.copyWith(effect: next)),
            begin,
            commit, live: (next) {
          begin();
          write(animation.copyWith(effect: next));
        }),
      // When it comes in and how it is paced, and -- on the line below --
      // how it travels out of the keyframe the playhead is on: the two
      // questions about time, in one place.
      if (timing && ((animation.on || animation.closes) || keyed.isNotEmpty))
        CanvasControlGroup(label: "Timing / Keyframe", children: [
          if (animation.on || animation.closes) ...[
            // Where the arrival is on the timeline, typed: the same two
            // keyframes dragging moves. Before there is one, how long the
            // next is laid down.
            if (controller.elementAnimationSpan(element)
                case (var at?, var span?)) ...[
              CanvasNumberField(
                key: const ValueKey("elementAnimationDelay"),
                label: "Delay",
                min: 0,
                max: 100000,
                decimals: 0,
                width: 62,
                value: at.toDouble(),
                onChanged: (v) {
                  begin();
                  controller.setElementArrivalTiming(
                      controller.document.elementById(element.id) ?? element,
                      delay: v.round());
                },
                onCommit: commit,
              ),
              CanvasNumberField(
                key: const ValueKey("elementAnimationLength"),
                label: "Length",
                min: 1,
                max: 100000,
                decimals: 0,
                width: 62,
                value: span.toDouble(),
                onChanged: (v) {
                  begin();
                  controller.setElementArrivalTiming(
                      controller.document.elementById(element.id) ?? element,
                      length: v.round());
                },
                onCommit: commit,
              ),
            ] else
              CanvasNumberField(
                key: const ValueKey("elementAnimationLength"),
                label: "Length",
                min: 1,
                max: 3600,
                decimals: 0,
                width: 62,
                value: (animation.length > 0
                        ? animation.length
                        : controller.defaultAnimationFrames)
                    .toDouble(),
                onChanged: (v) {
                  begin();
                  write(animation.copyWith(length: v.round()));
                },
                onCommit: commit,
              ),
            easeDropdown<ChartEase>(
              key: const ValueKey("elementAnimationEase"),
              value: animation.ease,
              values: ChartEase.values,
              name: (c) => c.label,
              curve: (c) => c.apply,
              onChanged: (v) => now(animation.copyWith(ease: v)),
            ),
            if (animation.scales)
              CanvasNumberField(
                key: const ValueKey("elementAnimationScale"),
                label: "From",
                min: 0,
                max: 8,
                decimals: 2,
                width: 62,
                value: animation.scale > 0
                    ? animation.scale
                    : animation.preset.from,
                onChanged: (v) {
                  begin();
                  write(animation.copyWith(scale: v));
                },
                onCommit: commit,
              ),
          ],
          if (keyed.isNotEmpty) ...[
            if (animation.on || animation.closes) const CanvasLineBreak(),
            ...keyed,
          ],
        ]),
    ],
  );
}

/// anchorButtons are an element's anchor point: shown on the stage, where
/// it can be dragged, or hidden and so left where it is; and, while it is
/// shown, locked there, or put back in the middle. See ElementBase.anchorX.
Widget anchorButtons(CanvasController controller, CanvasElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var shown = controller.anchorShown(e.id);
  var locked = e.base.anchorLocked;
  // One cluster: three buttons about one thing, kept together on the line.
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

/// presetName is what an arrival is called where it is summed up: a slide
/// is one choice now, its way round being the Direction's.
String presetName(ElementAnimationPreset p) =>
    p.family == ElementAnimationFamily.slide ? "Slide" : p.label;

/// oneOfAKind is whether [p]'s family is one choice, with nothing to pick
/// between -- the slides, which differ only in their direction.
bool oneOfAKind(ElementAnimationPreset p) =>
    p.family == ElementAnimationFamily.slide;

/// motionControls are an arrival's direction and strength, where they mean
/// something for what is chosen. [now] writes a change as one step; [live]
/// and [commit] are for a slider being dragged. [keys] starts their keys.
List<Widget> motionControls(
    ElementAnimation animation,
    void Function(ElementAnimation) now,
    void Function(ElementAnimation) live,
    VoidCallback commit,
    {String keys = "element",
    bool leaving = false}) {
  var preset = leaving ? animation.exit : animation.preset;
  return directionStrength(
    keys: keys,
    leaving: leaving,
    directed: leaving ? animation.exitDirected : animation.arrivalDirected,
    strengthens:
        leaving ? animation.exitStrengthens : animation.arrivalStrengthens,
    direction: (leaving ? animation.exitDirection : animation.direction) ??
        (preset.motion == TextMotion.wipe
            ? AnimationDirection.left
            : AnimationDirection.of(preset.dx, preset.dy)) ??
        AnimationDirection.left,
    strength: leaving ? animation.exitStrength : animation.strength,
    onDirection: (d) => now(leaving
        ? animation.copyWith(exitDirection: d)
        : animation.copyWith(direction: d)),
    onStrength: (v) => live(leaving
        ? animation.copyWith(exitStrength: v)
        : animation.copyWith(strength: v)),
    commit: commit,
  );
}

/// directionStrength is a way in's -- or, [leaving], a way out's -- Direction
/// and Strength, where they mean something: the one control set every kind
/// of element's animation uses, whatever it keeps them in.
List<Widget> directionStrength({
  required String keys,
  required bool leaving,
  required bool directed,
  required bool strengthens,
  required AnimationDirection direction,
  required double strength,
  required ValueChanged<AnimationDirection> onDirection,
  required ValueChanged<double> onStrength,
  required VoidCallback commit,
}) {
  var side = leaving ? "Exit" : "";
  return [
    if (directed)
      CanvasDropdown<AnimationDirection>(
        key: ValueKey("${keys}Animation${side}Direction"),
        label: "Direction",
        value: direction,
        width: 148,
        options: [
          for (var d in AnimationDirection.values)
            (d, leaving ? _goingTo(d) : d.label),
        ],
        onChanged: onDirection,
      ),
    if (strengthens)
      CanvasSlider(
        key: ValueKey("${keys}Animation${side}Strength"),
        label: "Strength",
        value: strength,
        max: 3,
        width: 90,
        onChanged: onStrength,
        onCommit: commit,
      ),
  ];
}

/// _goingTo is [d] said as where a thing goes out to.
String _goingTo(AnimationDirection d) => switch (d) {
      AnimationDirection.left => "To the left",
      AnimationDirection.right => "To the right",
      AnimationDirection.above => "Up",
      AnimationDirection.below => "Down",
      AnimationDirection.aboveLeft => "To top left",
      AnimationDirection.aboveRight => "To top right",
      AnimationDirection.belowLeft => "To bottom left",
      AnimationDirection.belowRight => "To bottom right",
    };

/// previewButton plays [element]'s animation alone, once -- or, while it
/// is, stops it. See CanvasController.previewElement.
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

/// loopGroup is an element's loop: which, how long each go round takes and
/// rests, how many times, how strongly, and from when until when. [now]
/// writes a change as one step; [live] and [commit] are for a number being
/// typed. [keys] starts its controls' keys, so that two can be shown at
/// once -- a drawing's and one of its shapes'. See ElementLoop.
Widget loopGroup(
    CanvasController controller,
    ElementLoop loop,
    void Function(ElementLoop) now,
    void Function(ElementLoop) live,
    VoidCallback commit,
    {String keys = "element",
    String label = "Looping"}) {
  Widget frames(String key, String label, int value, int least,
          ElementLoop Function(int) set) =>
      CanvasNumberField(
        key: ValueKey(key),
        label: label,
        min: least.toDouble(),
        max: 100000,
        decimals: 0,
        width: 58,
        value: value.toDouble(),
        onChanged: (v) => live(set(v.round())),
        onCommit: commit,
      );
  return CanvasControlGroup(label: label, children: [
    CanvasDropdown<LoopFamily?>(
      key: ValueKey("${keys}LoopFamily"),
      label: "Kind",
      value: loop.on ? loop.preset.family : null,
      width: 132,
      options: [
        (null, "None"),
        for (var family in LoopFamily.values) (family, family.label),
      ],
      onChanged: (family) => now(loop.copyWith(
          preset: family == null
              ? LoopPreset.none
              : LoopPreset.inFamily(family).first)),
    ),
    if (loop.on) ...[
      CanvasDropdown<LoopPreset>(
        key: ValueKey("${keys}LoopPreset"),
        label: "Which",
        value: loop.preset,
        width: 132,
        options: [
          for (var preset in LoopPreset.inFamily(loop.preset.family))
            (preset, preset.label),
        ],
        onChanged: (v) => now(loop.copyWith(preset: v)),
      ),
      frames("${keys}LoopCycle", "Cycle", loop.cycle, 1,
          (v) => loop.copyWith(cycle: v)),
      frames(
          "${keys}LoopGap", "Gap", loop.gap, 0, (v) => loop.copyWith(gap: v)),
      frames("${keys}LoopRepeats", "Repeats", loop.repeats, 0,
          (v) => loop.copyWith(repeats: v)),
      // How each go round is paced. Only the curves that stay inside it: a
      // round's phase stops at its ends, so an overshoot would be a pause.
      easeDropdown<ChartEase>(
        key: ValueKey("${keys}LoopEase"),
        value: loop.ease,
        values: const [
          ChartEase.linear,
          ChartEase.easeIn,
          ChartEase.easeOut,
          ChartEase.easeInOut,
        ],
        name: (c) => c.label,
        curve: (c) => c.apply,
        onChanged: (c) => now(loop.copyWith(ease: c)),
      ),
      // The colour it draws with, for the loops that draw -- a gradient for
      // a colour wave, whose band is the gradient -- and the band's width
      // and lean, for the loops that sweep one.
      if (loop.preset.coloured)
        CanvasColorButton(
          key: ValueKey("${keys}LoopColour"),
          label: "Colour",
          color: loop.colour.color,
          gradient: loop.preset == LoopPreset.colourWave
              ? loop.colour.gradient
              : null,
          onGradientChanged: loop.preset == LoopPreset.colourWave
              ? (g) => now(loop.copyWith(
                  colour: g == null
                      ? loop.colour.copyWith(plain: true)
                      : loop.colour.copyWith(gradient: g)))
              : null,
          onChanged: (c) =>
              now(loop.copyWith(colour: loop.colour.copyWith(color: c))),
        ),
      if (loop.preset.banded) ...[
        CanvasSlider(
          key: ValueKey("${keys}LoopBand"),
          label: "Band",
          value: loop.band,
          min: 0.05,
          max: 1,
          width: 80,
          onChanged: (v) => live(loop.copyWith(band: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: ValueKey("${keys}LoopAngle"),
          label: "Angle",
          min: -90,
          max: 90,
          decimals: 0,
          width: 52,
          value: loop.angle,
          onChanged: (v) => live(loop.copyWith(angle: v)),
          onCommit: commit,
        ),
      ],
      CanvasSlider(
        key: ValueKey("${keys}LoopStrength"),
        label: "Strength",
        value: loop.strength,
        max: 3,
        width: 90,
        onChanged: (v) => live(loop.copyWith(strength: v)),
        onCommit: commit,
      ),
      CanvasDropdown<bool>(
        key: ValueKey("${keys}LoopStarts"),
        label: "Starts",
        value: loop.from == null,
        width: 120,
        options: const [(true, "After arriving"), (false, "At a frame")],
        onChanged: (after) => now(after
            ? loop.copyWith(clearFrom: true)
            : loop.copyWith(from: controller.frame)),
      ),
      if (loop.from case var from?)
        frames("${keys}LoopFrom", "Frame", from + 1, 1,
            (v) => loop.copyWith(from: v - 1)),
      CanvasDropdown<bool>(
        key: ValueKey("${keys}LoopEnds"),
        label: "Ends",
        value: loop.to == null,
        width: 120,
        options: const [(true, "Scene end"), (false, "At a frame")],
        onChanged: (end) => now(end
            ? loop.copyWith(clearTo: true)
            : loop.copyWith(
                to: math.max(loop.from ?? 0, controller.document.frames - 1))),
      ),
      if (loop.to case var to?)
        frames("${keys}LoopTo", "Frame", to + 1, 1,
            (v) => loop.copyWith(to: v - 1)),
    ],
  ]);
}

/// keyframeEasingGroup is how the element travels *out of* the keyframe the
/// playhead is on.
///
/// Its own group, shown by every kind of element's animation section rather
/// than by the one shared between some of them: a text element and a chart
/// have animation sections of their own, and "the easing of this keyframe" is
/// not a question about what kind of element it is.
///
/// Shown whenever the element has keyframes at all, rather than only when the
/// playhead is standing on one. Hidden the rest of the time it was a control
/// nobody could find: there is no way to tell a setting that does not exist
/// from one that is waiting for the playhead to be somewhere else.
Widget keyframeEasingGroup(CanvasController controller, CanvasElement element,
    VoidCallback begin, VoidCallback commit) {
  var controls = keyframeEasingControls(controller, element, begin, commit);
  if (controls.isEmpty) return const SizedBox.shrink();
  return CanvasControlGroup(label: "This keyframe", children: controls);
}

/// keyframeEasingControls are the keyframe's easing and the button that
/// gives every keyframe the same -- nothing, for an element with no
/// keyframes. See keyframeEasingGroup.
List<Widget> keyframeEasingControls(CanvasController controller,
    CanvasElement element, VoidCallback begin, VoidCallback commit,
    {String label = "Easing"}) {
  var keys = element.track?.keys ?? const <Keyframe>[];
  if (keys.isEmpty) return const [];
  var here = element.track?.keyAt(controller.frame);

  return [
    easeDropdown<KeyframeEasing>(
      key: const ValueKey("elementKeyframeEasing"),
      label: label,
      value: here?.easing ?? KeyframeEasing.linear,
      width: 160,
      enabled: here != null,
      values: KeyframeEasing.values,
      name: (easing) => easing == KeyframeEasing.hold
          ? "Hold (stays the same)"
          : easing.label,
      // A hold stays where it was until the next keyframe, then jumps.
      curve: (easing) => easing == KeyframeEasing.hold
          ? (t) => t >= 1 ? 1.0 : 0.0
          : easing.apply,
      onChanged: (v) {
        begin();
        controller.setKeyframeEasing(element, v);
        commit();
      },
    ),
    CanvasIconButton(
      key: const ValueKey("elementKeyframeEasingAll"),
      icon: Icons.restart_alt,
      tooltip: "Apply to all",
      onPressed: here == null
          ? null
          : () {
              begin();
              controller.setKeyframeEasing(element, here.easing, all: true);
              commit();
            },
    ),
  ];
}

/// effectBits are the settings a cutting preset has: how many pieces, how far
/// they are thrown, how much they turn.
///
/// Shared by the element's animation section and the text element's, because
/// a mosaic over a photograph and a mosaic over a headline are cut by the
/// same numbers. [scatters] is false for the ones whose pieces stay where
/// they are -- a mosaic's blocks and a glitch's slices -- so the two
/// throwing settings are not offered where they would do nothing.
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

/// cornerFields is the "all corners" number and the four corners beside it.
///
/// Its own function because two things have corners -- the frame round an
/// element and a rectangle shape -- and the controls for them had better be
/// the same controls. The "all" field shows blank once they differ, so it
/// never claims a number that is not true of every corner.
/// SidePart is which half of one of these to build: the one number that sets
/// all of them, the four that set one each, or both.
///
/// The two halves live on different lines now -- the one number on the row, the
/// four behind the button at the end of it -- and they are still one function
/// because they are still one control split in two. Written as two functions
/// they would be two places to keep the range, the width and the keys in step.
enum SidePart { all, sides, both }

List<Widget> cornerFields(
        Corners corners, ValueChanged<Corners> onChanged, VoidCallback commit,
        {String label = "Radius",
        String prefix = "box",
        SidePart part = SidePart.both}) =>
    [
      if (part != SidePart.sides)
        CanvasNumberField(
          key: ValueKey("${prefix}Radius"),
          label: label,
          value: corners.even ?? 0,
          min: 0,
          max: 400,
          width: 54,
          onChanged: (v) => onChanged(corners.withEven(v)),
          onCommit: commit,
        ),
      if (part != SidePart.all)
        for (var (name, at, set)
            in <(String, double, Corners Function(double))>[
          ("↖", corners.topLeft, (v) => corners.copyWith(tl: v)),
          ("↗", corners.topRight, (v) => corners.copyWith(tr: v)),
          ("↘", corners.bottomRight, (v) => corners.copyWith(br: v)),
          ("↙", corners.bottomLeft, (v) => corners.copyWith(bl: v)),
        ])
          CanvasNumberField(
            key: ValueKey("${prefix}Radius$name"),
            label: name,
            value: at,
            min: 0,
            max: 400,
            // The same least width as a side's, so that the four corners line
            // up under the four sides. They were fifty against fifty-six,
            // which is six pixels a column and a row of four visibly out of
            // step with the rows above and below it.
            width: 56,
            onChanged: (v) => onChanged(set(v)),
            onCommit: commit,
          ),
    ];

/// roomFields is the "all sides" number and the four sides beside it. See
/// cornerFields, which is the same idea for the corners.
List<Widget> roomFields(
        Room room, ValueChanged<Room> onChanged, VoidCallback commit,
        {String label = "Padding",
        String prefix = "box",
        // What the keys are called, so that a second set of these in the same
        // panel -- the border's, beside the padding's -- is findable by what
        // it is rather than by which one came first.
        String allKey = "Padding",
        String sideKey = "Pad",
        SidePart part = SidePart.both}) =>
    [
      if (part != SidePart.sides)
        CanvasNumberField(
          key: ValueKey("$prefix$allKey"),
          label: label,
          value: room.even ?? 0,
          min: 0,
          max: 400,
          width: 54,
          onChanged: (v) => onChanged(room.withEven(v)),
          onCommit: commit,
        ),
      if (part != SidePart.all)
        for (var (name, at, set) in <(String, double, Room Function(double))>[
          ("Left", room.left, (v) => room.copyWith(l: v)),
          ("Top", room.top, (v) => room.copyWith(t: v)),
          ("Right", room.right, (v) => room.copyWith(r: v)),
          ("Bottom", room.bottom, (v) => room.copyWith(b: v)),
        ])
          CanvasNumberField(
            key: ValueKey("$prefix$sideKey$name"),
            label: name,
            value: at,
            min: 0,
            max: 400,
            width: 56,
            onChanged: (v) => onChanged(set(v)),
            onCommit: commit,
          ),
    ];

/// easeDropdown is a choice of easing, each drawn as its curve beside its
/// name -- what it does to a thing over its time, seen before it is picked.
/// [curve] is the easing as a function of 0..1.
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

/// EaseCurve is a small drawing of an easing: time along, progress up, with
/// the start and the end level marked, so an overshoot is seen to overshoot.
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
