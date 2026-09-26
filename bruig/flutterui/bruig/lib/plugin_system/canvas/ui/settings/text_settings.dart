import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/ui/document_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/text_documents.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// text settings.dart is a text element's settings.

List<Widget> textSettings(
    BuildContext context,
    CanvasController controller,
    TextElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  void now(TextElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    // No section round the type settings. They were behind a heading that was
    // open every time anybody looked, which is a chevron and a word standing
    // between the panel and the first thing it is for.
    //
    // No Content field either. The words are typed on the canvas, in the box
    // they will appear in, at the size and face they will appear at -- see
    // CanvasTextEditor. A two-line box in a settings panel could show
    // neither, so writing a headline meant typing it here and looking over
    // there.
    //
    // Where the words come from and how they are set: the switches on one
    // line, with whatever each of them needs underneath. Wrap was a group of
    // its own with a heading, for one switch and the two questions it brings
    // with it.
    //
    // Icons rather than words, alone among the panel's switches, because
    // there are five of them and a sidebar narrow enough to be worth having
    // put them on three lines. Each says what it is on the way past -- the
    // tooltip is the sentence the label never had room for.
    CanvasControlGroup(label: "Text", hideCaption: true, children: [
      CanvasIconButton(
        key: const ValueKey("textFitToBox"),
        icon: Icons.fit_screen_outlined,
        tooltip: "Fit to box — the type is sized so that the words fill the "
            "box, however many of them there are. The Size setting then says "
            "what it is sized from rather than what it is drawn at.",
        active: e.autoSize,
        onPressed: () => now(e.copyWith(autoSize: !e.autoSize)),
      ),
      // Words of this shape's own, for a document being laid out for several.
      //
      // The one thing scaling cannot do: type half the size still wraps where
      // the page is narrow, so a headline that takes two lines across a
      // banner takes four down a feed and the answer is fewer words rather
      // than smaller ones. Off, this element says the same thing everywhere
      // and a typo is still fixed once.
      if (controller.document.targets.length > 1)
        CanvasIconButton(
          key: const ValueKey("textOwnWordsHere"),
          icon: Icons.call_split,
          tooltip: "Own words on "
              "${shapeShort(shapeKey(controller.document.size))} — this ratio "
              "gets wording of its own, and typing here changes nothing on "
              "the others. For the headline that is four words across a "
              "banner and two down a feed: type half the size still wraps "
              "where the page is narrow, so the answer is fewer words rather "
              "than smaller ones. Off, the element says the same thing "
              "everywhere and a typo is fixed once.",
          active: e.base.ownText,
          onPressed: () =>
              now(e.withBase(ownText: !e.base.ownText) as TextElement),
        ),
      // Words from the Writing library rather than typed on the canvas.
      // Beside Fit to box because it is the same kind of question --
      // where the words and their size come from -- and because it is
      // the first thing to decide about a text element that is a
      // document.
      //
      // Not offered at all on a box that is being flowed into: its
      // words belong to the box in front of it, so a document chosen
      // here would be read, stored and never seen -- and the most
      // confusing version of that is a chain that is already carrying a
      // document, where every box in it looks like somewhere to attach
      // another one.
      if (flowSourceOf(e, controller.document) == null)
        CanvasIconButton(
          key: const ValueKey("textFromDocument"),
          icon: Icons.description_outlined,
          tooltip: "From document — the words come from a document in the "
              "Writing library instead of being typed on the canvas, and are "
              "read again as it is edited.",
          active: e.document.on,
          onPressed: () async {
            var v = !e.document.on;
            if (!v) {
              // Back to what was typed here before the document took the
              // words over. Left showing the document's words, the switch
              // would be off and the element would still say what the
              // document says, with no way back to what was there.
              now(e.copyWith(
                  text:
                      e.document.wasText.isEmpty ? e.text : e.document.wasText,
                  document: const TextDocumentRef(),
                  documentParts: const []));
              return;
            }
            var picked = await pickLibraryDocument(context);
            if (picked == null) return;
            now(e.copyWith(
                document: picked.copyWith(wasText: e.text),
                documentParts: const []));
            await refreshTextDocuments(controller);
          },
        ),
      if (e.document.on) ...[
        CanvasIconButton(
          key: const ValueKey("textDocumentPick"),
          // Not the document icon: that one is the switch two along, and two
          // buttons on one line with the same picture are one button drawn
          // twice.
          icon: Icons.folder_open_outlined,
          tooltip: "Choose another document",
          onPressed: () async {
            var picked = await pickLibraryDocument(context);
            if (picked == null) return;
            // The remembered words are the element's own, not the last
            // document's, so changing which document is read leaves
            // them alone.
            now(e.copyWith(
                document: e.document
                    .copyWith(folder: picked.folder, name: picked.name),
                documentParts: const []));
            await refreshTextDocuments(controller);
          },
        ),
        CanvasReadout(label: "Document", value: e.document.says),
        CanvasIconButton(
          key: const ValueKey("textDocumentMarkdown"),
          icon: Icons.format_quote_outlined,
          tooltip: "Markdown — honour the marks in the document. Off, the "
              "words arrive as plain text with every mark stripped.",
          active: e.document.markdown,
          onPressed: () async {
            now(e.copyWith(
                document: e.document
                    .copyWith(markdown: !e.document.markdown)));
            await refreshTextDocuments(controller);
          },
        ),
        const CanvasHint(
            "The words come from the library and are read again every "
            "few seconds, so editing the document changes the canvas. "
            "With Markdown off they arrive as plain text — every mark "
            "stripped, all of the styling from the settings here. With "
            "it on, only the pieces switched on are honoured; the rest "
            "are still stripped, because a headline reading \"## Title\" "
            "is not markdown being ignored, it is markdown showing."),
      ],
      // Words set around whatever overlaps the box. On the line with the
      // other two because it is the same kind of question -- how these
      // words are laid out -- and it brings two of its own with it.
      CanvasIconButton(
        key: const ValueKey("textWrap"),
        icon: Icons.wrap_text,
        tooltip: "Wrap text — the words are set around whatever overlaps the "
            "box rather than running under it.",
        active: e.wrap.on,
        onPressed: () => now(e.copyWith(wrap: e.wrap.copyWith(on: !e.wrap.on))),
      ),
      if (e.wrap.on) ...[
        const CanvasLineBreak(),
        CanvasNumberField(
          label: "Space",
          value: e.wrap.gap,
          min: 0,
          max: 400,
          decimals: 0,
          width: 62,
          onChanged: (v) {
            begin();
            write(e.copyWith(wrap: e.wrap.copyWith(gap: v)));
          },
          onCommit: commit,
        ),
        CanvasDropdown<WrapSide>(
          key: const ValueKey("textWrapSide"),
          label: "Words go",
          value: e.wrap.side,
          width: 132,
          options: [for (var s in WrapSide.values) (s, s.label)],
          onChanged: (v) => now(e.copyWith(wrap: e.wrap.copyWith(side: v))),
        ),
        const CanvasHint("The words are set line by line around every visible "
            "element that overlaps this box, leaving Space between "
            "them. Both sides fills the room either side of something "
            "narrow; Left or Right keeps the words in one block beside "
            "it. Anything that covers the box from top to bottom is "
            "left out — that is a background, and a paragraph cannot go "
            "around it."),
      ],
    ]),
    // The face, the size and the weight on one line; how the words are spaced
    // and where they sit behind the button, along with the element's own
    // marks -- a band behind all of the words, a line under all of them. Here
    // rather than only on a part, because highlighting a whole headline
    // should not mean first making a part that covers it.
    ...typeGroups(
        e.textSpec, (spec) => write(e.copyWith(textSpec: spec)), begin, commit,
        // Captioned with what the element is called, once it carries pieces:
        // a run of captioned rows with an uncaptioned one at the top of it
        // reads as the pieces belonging to something unnamed. On its own the
        // panel's header has already said it.
        label: e.name,
        hideCaption: e.items.isEmpty,
        // The element's own name, which is what the layer list shows.
        onRename: (v) => now(e.withBase(name: v) as TextElement),
        fill: true,
        context: context,
        remember: "text",
        // Everything about one piece of writing on one line and behind one
        // button, because this is the element that has several pieces of
        // writing in it -- see the items below.
        colourInMore: true,
        // The words carry a drawn underline of their own -- see the marks
        // behind this button -- so the face's own underline switch would be
        // the second one called Underline on this panel.
        includeUnderline: false,
        // No lines through this run. The face, the colour, the box, the
        // columns and the line it rides are all one question -- how do these
        // words look -- and a rule between each pair of them made five
        // answers to five different questions out of it.
        rule: false,
        extraMore: [
          const CanvasLineBreak(),
          // Where the element's own words go. "Fills the box" is what a text
          // element has always been; a slot makes them a block like a piece,
          // which is what lets a title and the paragraph under it stack
          // rather than being drawn over each other.
          CanvasDropdown<String>(
            key: const ValueKey("textBodySlot"),
            label: "Where",
            value: e.slot?.name ?? "",
            width: 116,
            options: [
              ("", "Fills the box"),
              for (var s in TextSlot.values) (s.name, s.label),
            ],
            onChanged: (v) => now(v.isEmpty
                ? e.copyWith(clearSlot: true)
                : e.copyWith(slot: TextSlot.fromName(v))),
          ),
          if (e.slot != null && (!e.columns.isSingle || e.flowTo.isNotEmpty))
            const CanvasHint(
                "Columns and a chain of boxes are arrangements of the whole "
                "box, so the words fill it while either is on and the slot "
                "waits."),
          if (e.slot?.down == VerticalAlignSpec.middle) _middleSlotHint,
          const CanvasLineBreak(),
          ..._markBits(
            highlight: e.highlight,
            underline: e.underline,
            textColor: e.textSpec.color,
            keyPrefix: "text",
            setHighlight: (h) => now(h == null
                ? e.copyWith(clearHighlight: true)
                : e.copyWith(highlight: h)),
            setUnderline: (u) => now(u == null
                ? e.copyWith(clearUnderline: true)
                : e.copyWith(underline: u)),
            liveHighlight: (h) {
              begin();
              write(e.copyWith(highlight: h));
            },
            liveUnderline: (u) {
              begin();
              write(e.copyWith(underline: u));
            },
            done: commit,
          ),
        ]),
    ..._itemRows(context, e, write, begin, commit),
    boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
        remember: "text", rule: false, fill: true, context: context),
    // One line, so no section round it. A heading with a chevron on it, for
    // a number and a switch, is more furniture than setting -- and what is
    // behind it only grows to five controls on a box that has been given
    // columns and a rule between them.
    CanvasControlGroup(label: "Columns", rule: false, children: [
      CanvasNumberField(
        key: const ValueKey("textColumns"),
        // "Count", not "Columns": the caption over the line already says
        // which settings these are, and saying it twice on one line is how a
        // panel comes to read as a list of words rather than of controls.
        label: "Count",
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
      // The gap between two paragraphs is a line like any other, and
      // whatever starts on one -- a column, or the next box in a chain --
      // starts with an empty row and its words sitting lower than its
      // neighbour's. Offered whether or not this box has columns of its
      // own, because a chain of boxes asks the same question of boxes;
      // and only on the box the words belong to, since the rest of a
      // chain follows what it says.
      if (flowSourceOf(e, controller.document) == null)
        CanvasToggle(
          key: const ValueKey("textColumnsNoBlankStart"),
          label: "No blank first line",
          value: e.columns.noBlankStart,
          onChanged: (v) =>
              now(e.copyWith(columns: e.columns.copyWith(noBlankStart: v))),
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
    // Under the columns rather than in a section of its own, and still its own
    // group: a text element is either riding a line or it is not, and the two
    // questions have nothing to say to each other.
    //
    // Which line, how far along it and how far apart the letters stand are
    // what anybody sets; which side of the line the words fall on and whether
    // it is a window are set once. The button is only there once a line has
    // been chosen, because until then there is nothing behind it.
    CanvasMoreGroup(
      label: "On a line",
      rule: false,
      remember: "textOnALineMore",
      tooltip: "Which side of the line, and what is cut off",
      row: [
        CanvasDropdown<String>(
          label: "Follow",
          value: e.curve?.elementId ?? "",
          width: 156,
          options: curveOptions(controller),
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
            value:
                controller.valueAt(e, KeyframeChannel.slide, e.curve!.offset),
            // Far enough either way to carry the words right off the end
            // of the line and back on again, which is what a caption
            // sliding in and out of a shot is.
            min: -2,
            max: 2,
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
          valueDot(
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
        ],
      ],
      more: [
        if (e.curve != null) ...[
          CanvasToggle(
            label: "Below",
            value: e.curve!.away,
            onChanged: (v) =>
                now(e.copyWith(curve: e.curve!.copyWith(away: v))),
          ),
          CanvasToggle(
            key: const ValueKey("textCurveMask"),
            label: "Mask",
            value: e.curve!.mask,
            onChanged: (v) =>
                now(e.copyWith(curve: e.curve!.copyWith(mask: v))),
          ),
          CanvasToggle(
            // Not the line element's own Hide: a hidden element is skipped
            // everywhere, this one included, so the text would go with it.
            label: "Hide line",
            value: e.curve!.hideHost,
            onChanged: (v) =>
                now(e.copyWith(curve: e.curve!.copyWith(hideHost: v))),
          ),
          const CanvasHint(
              "Slide carries the words along the line, and past either "
              "end of it — far enough to take them right off and back on "
              "again. Mask makes the line a window: whatever has slid off "
              "an end is cut off there rather than carrying on across the "
              "canvas."),
        ],
      ],
    ),
    // Markdown's own section, with a look per piece. It only exists while
    // the words come from a document and the marks are being honoured: a
    // section of settings for something switched off is a section that says
    // nothing.
    if (e.document.on && e.document.markdown)
      boxed(context, _markdownSection(controller, e, write, begin, commit)),
    boxed(context, _partsSection(e, write, begin, commit)),
    // Boxed like every other section: a bare expander among boxed ones reads
    // as something that has come loose.
    boxed(context, _animationSection(controller, e, write, begin, commit)),
  ];
}

/// _markdownSection is how each piece of a document's markdown is drawn.
///
/// A look per piece rather than a switch per piece: a poster's heading is a
/// different size, weight, face and colour from a report's, and with only a
/// switch they could only ever look like the one thing this code happened to
/// choose. Everything is an override -- left alone, a piece follows the
/// element's own type settings and picks up a change to them.
Widget _markdownSection(CanvasController controller, TextElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var allow = e.document.allow;

  Future<void> set(MarkdownKind kind, MarkdownLook look) async {
    begin();
    write(e.copyWith(
        document: e.document.copyWith(allow: allow.withLook(kind, look))));
    commit();
    // The document is read again, because what the marks mean has changed.
    await refreshTextDocuments(controller);
  }

  var on = [
    for (var k in MarkdownKind.values)
      if (allow.allows(k)) k.label
  ];

  return CanvasExpander(
    label: "Markdown",
    remember: "textMarkdown",
    trailing: on.isEmpty ? "None" : "${on.length}",
    children: [
      const CanvasHint(
          "Each piece of markdown the document uses, and how it is drawn "
          "here. Switched on and left alone, a piece follows the type "
          "settings above — so changing the face or the colour of the "
          "element changes its headings with it. Anything switched off is "
          "stripped rather than shown: a headline reading \"## Title\" is not "
          "markdown being ignored, it is markdown showing."),
      for (var kind in MarkdownKind.values)
        CanvasControlGroup(label: kind.label, children: [
          CanvasToggle(
            key: ValueKey("markdown${kind.name}"),
            label: "Honour it",
            value: allow.allows(kind),
            onChanged: (v) => set(kind, allow.lookFor(kind).copyWith(on: v)),
          ),
          if (allow.allows(kind)) ...[
            CanvasNumberField(
              label: "Size",
              value: allow.lookFor(kind).scale ?? kind.scale,
              min: 0.1,
              max: 8,
              decimals: 2,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    document: e.document.copyWith(
                        allow: allow.withLook(
                            kind, allow.lookFor(kind).copyWith(scale: v)))));
              },
              onCommit: () {
                commit();
                refreshTextDocuments(controller);
              },
            ),
            CanvasColorButton(
              label: "Colour",
              color:
                  allow.lookFor(kind).color ?? kind.color ?? e.textSpec.color,
              onChanged: (c) =>
                  set(kind, allow.lookFor(kind).copyWith(color: c)),
            ),
            CanvasNumberField(
              label: "Weight",
              value: (allow.lookFor(kind).weight ??
                      kind.weight ??
                      e.textSpec.weight)
                  .toDouble(),
              min: 100,
              max: 900,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    document: e.document.copyWith(
                        allow: allow.withLook(
                            kind,
                            allow
                                .lookFor(kind)
                                .copyWith(weight: (v / 100).round() * 100)))));
              },
              onCommit: () {
                commit();
                refreshTextDocuments(controller);
              },
            ),
            CanvasToggle(
              label: "Italic",
              value: allow.lookFor(kind).italic ?? kind.slanted,
              onChanged: (v) =>
                  set(kind, allow.lookFor(kind).copyWith(italic: v)),
            ),
            CanvasToggle(
              label: "Underline",
              value: allow.lookFor(kind).underline ?? kind.underlined,
              onChanged: (v) =>
                  set(kind, allow.lookFor(kind).copyWith(underline: v)),
            ),
            CanvasDropdown<String>(
              label: "Face",
              value: allow.lookFor(kind).family ?? "",
              width: 132,
              options: [
                ("", "Same as the text"),
                for (var f in canvasFonts) (f, f),
              ],
              onChanged: (v) => set(
                  kind,
                  v.isEmpty
                      ? allow.lookFor(kind).copyWith(clearFamily: true)
                      : allow.lookFor(kind).copyWith(family: v)),
            ),
          ],
        ]),
    ],
  );
}

/// _partsSection is "these words, not the others": a list of ranges, each
/// with what is different about it.
///
/// Its own section because it is not an animation and not type: it is a fact
/// about some of the words -- the sixth one is white, the first five are
/// bold -- and the same ranges are what an echo or an animation will be
/// pointed at.
Widget _partsSection(TextElement e, SettingsWrite write, VoidCallback begin,
    VoidCallback commit) {
  void set(List<TextPart> parts) {
    begin();
    write(e.copyWith(parts: parts));
    commit();
  }

  // The row is there before anything has been added, in its own default
  // state, and setting anything on it is what adds it. Pressing a plus to be
  // shown the controls, and only then being able to use them, is a step that
  // exists because the list is empty -- which is not a thing the reader did.
  var shown = e.parts.isEmpty ? const [TextPart()] : e.parts;

  List<TextPart> replacing(int index, TextPart part) => [
        for (var i = 0; i < shown.length; i++) i == index ? part : shown[i],
      ];

  return CanvasExpander(
    label: "Parts of the text",
    remember: "textParts",
    trailing: e.parts.isEmpty ? null : "${e.parts.length}",
    children: [
      const CanvasHint(
          "A part is some of the words — the sixth one, the first five, the "
          "tenth to the end — and what is different about them. Counted from "
          "one, and \"to\" left at nothing means to the end, so a part still "
          "means what it said after the words are edited."),
      for (var (i, part) in shown.indexed)
        CanvasControlGroup(label: part.says, children: [
          CanvasDropdown<TextUnit>(
            label: "Counting",
            value: part.unit,
            width: 118,
            options: [for (var u in TextUnit.values) (u, u.label)],
            onChanged: (v) => set(replacing(i, part.copyWith(unit: v))),
          ),
          CanvasNumberField(
            label: "From",
            value: part.from.toDouble(),
            min: 1,
            max: 9999,
            decimals: 0,
            width: 56,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  parts: replacing(i, part.copyWith(from: v.round()))));
            },
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "To",
            value: part.to.toDouble(),
            min: 0,
            max: 9999,
            decimals: 0,
            width: 56,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  parts: replacing(i, part.copyWith(to: v.round()))));
            },
            onCommit: commit,
          ),
          CanvasColorButton(
            label: "Colour",
            color: part.color ?? e.textSpec.color,
            onChanged: (c) => set(replacing(i, part.copyWith(color: c))),
          ),
          // Icons, not switches with words: a part carries five of them --
          // bold, italic, an outline, and the two marks -- and five words in
          // a column is a column. The words are on the tooltips.
          CanvasIconButton(
            key: ValueKey("partBold$i"),
            icon: Icons.format_bold,
            tooltip: "Bold",
            active: (part.weight ?? e.textSpec.weight) >= 600,
            onPressed: () => set(replacing(
                i,
                part.copyWith(
                    weight: (part.weight ?? e.textSpec.weight) >= 600
                        ? 400
                        : 700))),
          ),
          CanvasIconButton(
            key: ValueKey("partItalic$i"),
            icon: Icons.format_italic,
            tooltip: "Italic",
            active: part.italic ?? e.textSpec.italic,
            onPressed: () => set(replacing(
                i, part.copyWith(italic: !(part.italic ?? e.textSpec.italic)))),
          ),
          // An outline on these words alone: a heavier one than the rest of
          // the headline has, a different colour, or -- at nothing -- none at
          // all inside a headline that otherwise has one.
          CanvasIconButton(
            key: ValueKey("partOutline$i"),
            icon: Icons.font_download_outlined,
            tooltip: "Outline these words",
            active: part.outlineWidth != null,
            onPressed: () => set(replacing(
                i,
                part.outlineWidth == null
                    ? part.copyWith(
                        outlineWidth: e.textSpec.outlineWidth > 0
                            ? e.textSpec.outlineWidth
                            : 2)
                    : part.copyWith(clearOutline: true))),
          ),
          if (part.outlineWidth != null) ...[
            CanvasNumberField(
              label: "Amount",
              value: part.outlineWidth!,
              min: 0,
              max: 40,
              decimals: 1,
              width: 58,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(i, part.copyWith(outlineWidth: v))));
              },
              onCommit: commit,
            ),
            CanvasColorButton(
              label: "Outline colour",
              color: part.outlineColor ?? e.textSpec.outlineColor,
              onChanged: (c) =>
                  set(replacing(i, part.copyWith(outlineColor: c))),
            ),
          ],
          // The two marks, which a part has and the element has as well --
          // written once, in _markBits, so they cannot drift apart.
          ..._markBits(
            highlight: part.highlight,
            underline: part.underline,
            textColor: part.color ?? e.textSpec.color,
            keyPrefix: "part$i",
            icons: true,
            setHighlight: (h) => set(replacing(
                i,
                h == null
                    ? part.copyWith(clearHighlight: true)
                    : part.copyWith(highlight: h))),
            setUnderline: (u) => set(replacing(
                i,
                u == null
                    ? part.copyWith(clearUnderline: true)
                    : part.copyWith(underline: u))),
            liveHighlight: (h) {
              begin();
              write(
                  e.copyWith(parts: replacing(i, part.copyWith(highlight: h))));
            },
            liveUnderline: (u) {
              begin();
              write(
                  e.copyWith(parts: replacing(i, part.copyWith(underline: u))));
            },
            done: commit,
          ),
          // This part's own arrival, at its own moment. Not the element's
          // animation pointed here: the rest of the sentence has an arrival
          // of its own, and the point of animating one word is that it lands
          // after the line it is in rather than with it.
          const CanvasLineBreak(),
          CanvasDropdown<TextAnimationFamily?>(
            key: ValueKey("partAnimationFamily$i"),
            label: "Arrives",
            value: part.animation.on ? part.animation.preset.family : null,
            width: 128,
            options: [
              (null, "With the rest"),
              for (var family in TextAnimationFamily.values)
                (family, family.label),
            ],
            onChanged: (family) => set(replacing(
                i,
                part.copyWith(
                    animation: _partPreset(
                        part.animation,
                        family == null
                            ? TextAnimationPreset.none
                            : TextAnimationPreset.inFamily(family).first)))),
          ),
          if (part.animation.on) ...[
            CanvasDropdown<TextAnimationPreset>(
              key: ValueKey("partAnimationPreset$i"),
              label: "Which",
              value: part.animation.preset,
              width: 168,
              options: [
                for (var preset in TextAnimationPreset.inFamily(
                    part.animation.preset.family))
                  (preset, preset.label),
              ],
              onChanged: (v) => set(replacing(
                  i, part.copyWith(animation: _partPreset(part.animation, v)))),
            ),
            CanvasNumberField(
              label: "Offset",
              value: part.animation.offset.toDouble(),
              min: -600,
              max: 600,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation:
                                part.animation.copyWith(offset: v.round())))));
              },
              onCommit: commit,
            ),
            CanvasNumberField(
              label: "Length",
              value: part.animation.length.toDouble(),
              min: 0,
              max: 3600,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation:
                                part.animation.copyWith(length: v.round())))));
              },
              onCommit: commit,
            ),
            const CanvasHint(
                "Offset is how many frames after the element's own arrival "
                "this one starts — nothing lands them together, a few frames "
                "makes the word land after the line it is in, and a negative "
                "number brings it forward. Length is how long it takes; "
                "nothing means as long as the arrival."),
          ],
          // The mark's own timing, on a line of its own: it is a second
          // arrival -- the word lands and *then* gets underlined -- and run
          // on from the offset and length above it read as more of those.
          if (part.highlight != null || part.underline != null) ...[
            const CanvasLineBreak(),
            CanvasNumberField(
              label: "Mark offset",
              value: part.animation.markOffset.toDouble(),
              min: -600,
              max: 600,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation: part.animation
                                .copyWith(markOffset: v.round())))));
              },
              onCommit: commit,
            ),
            CanvasNumberField(
              label: "Mark length",
              value: part.animation.markLength.toDouble(),
              min: 0,
              max: 3600,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation: part.animation
                                .copyWith(markLength: v.round())))));
              },
              onCommit: commit,
            ),
            // After the two numbers it turns on, so it does not move about
            // between one state and the other -- and last, because it is the
            // switch on the end of the row rather than the heading of it.
            CanvasToggle(
              label: "Draw the mark on",
              value: part.animation.marks,
              onChanged: (v) => set(replacing(i,
                  part.copyWith(animation: part.animation.copyWith(marks: v)))),
            ),
            const CanvasHint(
                "Off, the highlight or underline is simply there. On, it is "
                "drawn across the words — after them by whatever the mark's "
                "own offset says, since the usual thing is a word that "
                "arrives and then gets underlined."),
          ],
          // The rest of the animation settings, which are the paragraph's own
          // — the copies of an echo, the look of a drawn mark, the timing.
          // The same ones rather than a chosen few: a part whose echo could
          // not be told to resolve is a part with half an animation.
          if (part.animation.on)
            ..._animationBits(
              part.animation.asAnimation,
              textColor: part.color ?? e.textSpec.color,
              live: (next) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation: part.animation.fromAnimation(next)))));
              },
              done: commit,
            ),
          const CanvasLineBreak(),
          if (e.parts.isNotEmpty)
            CanvasIconButton(
              icon: Icons.delete_outline,
              tooltip: "Remove this part",
              onPressed: () => set([
                for (var j = 0; j < e.parts.length; j++)
                  if (j != i) e.parts[j],
              ]),
            ),
        ]),
      CanvasControlGroup(label: "Add", hideCaption: true, children: [
        CanvasIconButton(
          key: const ValueKey("addTextPart"),
          icon: Icons.add,
          tooltip: "Pick out some of the words",
          onPressed: () => set([...e.parts, const TextPart()]),
        ),
      ]),
    ],
  );
}

/// _partPreset chooses a preset for a part, and the curve it was designed
/// around with it. See TextAnimationPreset.wants: a bounce played with the
/// ordinary ease-out is a slide with a misleading name.
TextPartAnimation _partPreset(
        TextPartAnimation animation, TextAnimationPreset preset) =>
    animation.copyWith(preset: preset, ease: preset.wants);

/// _animationSection is how the words arrive, and how they leave.
///
/// Its own section, like a chart's, and for the same reason: it is a handful
/// of choices made once and then left alone, and open by default it would be
/// half a screen of names between the type settings and the box.
///
/// The presets are grouped by family because the flat list is thirty long.
/// Grouped, the question is "what kind of arrival" and then "which one",
/// which is how somebody actually chooses.
Widget _animationSection(CanvasController controller, TextElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void now(TextElement next) {
    begin();
    write(next);
    commit();
  }

  var animation = e.animation;
  return CanvasExpander(
    label: "Animation",
    remember: "textAnimation",
    trailing: animation.on
        ? (animation.closes
            ? "${animation.preset.label} · ${animation.exit.label}"
            : animation.preset.label)
        : (animation.closes ? animation.exit.label : null),
    children: [
      // The same group every other element's animation section carries: the
      // easing belongs to the keyframe, and a caption's keyframes are
      // keyframes like any other.
      keyframeEasingGroup(controller, e, begin, commit),
      const CanvasHint(
          "Choosing one draws the words on over two seconds and puts a "
          "keyframe at each end of it on the timeline. Drag those to decide "
          "how long it takes and when it happens — the same two keyframes a "
          "chart's animation uses, so a headline and a chart can arrive "
          "together."),
      // The family first, then the animation. Thirty names in one list is a
      // wall of text nobody reads to the end of; asked in two steps the
      // question is "what kind of arrival" and then "which one", which is how
      // somebody actually chooses.
      //
      // Choosing a family applies the first of its presets rather than
      // waiting for a second choice, so the canvas shows something
      // immediately and the second box refines it.
      CanvasControlGroup(label: "Arriving", children: [
        CanvasDropdown<TextAnimationFamily?>(
          key: const ValueKey("textAnimationFamily"),
          label: "Kind",
          value: animation.on ? animation.preset.family : null,
          width: 132,
          options: [
            (null, "None"),
            for (var family in TextAnimationFamily.values)
              (family, family.label),
          ],
          onChanged: (family) => controller.applyTextAnimation(
              e,
              family == null
                  ? TextAnimationPreset.none
                  : TextAnimationPreset.inFamily(family).first),
        ),
        if (animation.on)
          CanvasDropdown<TextAnimationPreset>(
            key: const ValueKey("textAnimationPreset"),
            label: "Which",
            value: animation.preset,
            width: 168,
            options: [
              for (var preset
                  in TextAnimationPreset.inFamily(animation.preset.family))
                (preset, preset.label),
            ],
            onChanged: (v) => controller.applyTextAnimation(e, v),
          ),
      ]),
      if (animation.on || animation.closes)
        CanvasControlGroup(label: "Leaving", children: [
          CanvasDropdown<TextAnimationFamily?>(
            key: const ValueKey("textAnimationExitFamily"),
            label: "Kind",
            value: animation.closes ? animation.exit.family : null,
            width: 132,
            options: [
              (null, "None"),
              for (var family in TextAnimationFamily.values)
                (family, family.label),
            ],
            onChanged: (family) => controller.applyTextExit(
                e,
                family == null
                    ? TextAnimationPreset.none
                    : TextAnimationPreset.inFamily(family).first),
          ),
          if (animation.closes) ...[
            CanvasDropdown<TextAnimationPreset>(
              key: const ValueKey("textAnimationExit"),
              label: "Which",
              value: animation.exit,
              width: 168,
              options: [
                for (var preset
                    in TextAnimationPreset.inFamily(animation.exit.family))
                  (preset, "${preset.label}, reversed"),
              ],
              onChanged: (v) => controller.applyTextExit(e, v),
            ),
            CanvasToggle(
              label: "In the same order",
              value: animation.exitInOrder,
              onChanged: (v) => now(
                  e.copyWith(animation: animation.copyWith(exitInOrder: v))),
            ),
          ],
        ]),
      ..._animationBits(
        animation,
        textColor: e.textSpec.color,
        live: (next) {
          begin();
          write(e.copyWith(animation: next));
        },
        done: commit,
        timingFirst: [
          // How long an arrival or an exit is laid down with, in frames. A
          // setting rather than a reading of the timeline: the default is
          // rarely the length wanted, and dragging a keyframe is a poor way
          // to ask for twelve frames.
          CanvasNumberField(
            key: const ValueKey("textAnimationLength"),
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
              write(
                  e.copyWith(animation: animation.copyWith(length: v.round())));
            },
            onCommit: commit,
          ),
          const CanvasHint(
              "How many frames a new arrival or exit is laid down with. Once "
              "it is on the timeline the keyframes are where it is: changing "
              "this does not move them, and neither does trying another "
              "preset. Delete a keyframe and the animation is gone — the next "
              "one chosen is laid down at this length again."),
        ],
      ),
    ],
  );
}

/// valueDot is the diamond beside one animatable property.
///
/// Its own control rather than part of the pose diamond, because these are
/// real channels: a keyframe can pin a caption's slide without pinning where
/// its box sits, and the two are asked for at different moments.

/// _animationBits are the settings that depend on which preset was chosen:
/// what a drawn mark looks like, how an echo's copies are arranged, and the
/// timing.
///
/// Shared by the element's own arrival and by every part that arrives on its
/// own account, because they are the same animation -- a part offering half
/// the settings was a part whose echo could not be told to resolve. [live] is
/// handed the edited animation and writes it wherever it belongs; [done]
/// commits, so a number field can be dragged without filling the undo stack.
List<Widget> _animationBits(
  TextAnimation a, {
  required Color textColor,
  required void Function(TextAnimation) live,
  required VoidCallback done,
  List<Widget> timingFirst = const [],
}) {
  void now(TextAnimation next) {
    live(next);
    done();
  }

  return [
    // A destruction is an exit. Said here for the same reason it is said in
    // a shape's panel: somebody looking for one will be looking in the
    // arrival list, and the two are one cut run in opposite directions.
    if (a.cuts)
      const CanvasHint(
          "Break apart and Build up are the same cut run in opposite "
          "directions. Set one as the way *out* and the words come apart and "
          "leave; set it as the way in and they assemble."),
    if (a.cuts)
      ...effectBits(a.effect, a.scatters,
          (next) => now(a.copyWith(effect: next)), done, done,
          live: (next) => live(a.copyWith(effect: next))),
    // Draw the outline writes what is on the page and makes nothing up, so
    // it is worth saying what it will write: a stroke where the type has one,
    // and the words themselves where it has not. Without this the preset
    // looks broken on type with no outline -- it does something, but not the
    // thing the name led somebody to expect.
    if (a.preset == TextAnimationPreset.strokeOn ||
        a.exit == TextAnimationPreset.strokeOn)
      const CanvasHint(
          "Draw the outline draws a stroke onto words that are already "
          "there, line by line, the way a pen would. It draws the type's own "
          "Outline where it has one; where it has not, give the mark a "
          "colour below and it draws one in that. With neither there is "
          "nothing for it to draw."),
    // What a drawn mark looks like: an underline's line, a highlight's
    // band. Only where something is drawn -- on a fade there is no mark to
    // colour.
    if (a.draws)
      CanvasControlGroup(label: "The mark", children: [
        CanvasColorButton(
          label: "Colour",
          color: a.draw.color ?? textColor,
          onChanged: (c) => now(a.copyWith(draw: a.draw.copyWith(color: c))),
        ),
        CanvasDropdown<TextDrawStart>(
          key: const ValueKey("textDrawStart"),
          label: "The words are",
          value: a.draw.start,
          width: 148,
          options: [for (var s in TextDrawStart.values) (s, s.label)],
          onChanged: (v) => now(a.copyWith(draw: a.draw.copyWith(start: v))),
        ),
        const CanvasLineBreak(),
        // The room round the words is a band's and a line's; a stroke follows
        // the letterform and has nowhere to put it.
        if (a.preset != TextAnimationPreset.strokeOn) ...[
          // One field for all four sides, and the four on their own under it.
          // A band tight around the letters reads as a mistake; one with a
          // little air reads as a highlighter.
          CanvasNumberField(
            label: "Padding",
            value: a.draw.evenPad ?? 0,
            min: 0,
            max: 200,
            decimals: 0,
            width: 62,
            onChanged: (v) {
              live(a.copyWith(draw: a.draw.withEvenPad(v)));
            },
            onCommit: done,
          ),
          for (var (name, at, set)
              in <(String, double, TextDrawSpec Function(double))>[
            ("Left", a.draw.padLeft, (v) => a.draw.copyWith(padLeft: v)),
            ("Top", a.draw.padTop, (v) => a.draw.copyWith(padTop: v)),
            ("Right", a.draw.padRight, (v) => a.draw.copyWith(padRight: v)),
            ("Bottom", a.draw.padBottom, (v) => a.draw.copyWith(padBottom: v)),
          ])
            CanvasNumberField(
              label: name,
              value: at,
              min: 0,
              max: 200,
              decimals: 0,
              width: 56,
              onChanged: (v) {
                live(a.copyWith(draw: set(v)));
              },
              onCommit: done,
            ),
          // A band's corners, the same setting a part's own highlight has.
          // Drawn square while the other one could be rounded, the same mark
          // looked like two different marks.
          if (a.preset == TextAnimationPreset.highlight)
            CanvasNumberField(
              key: const ValueKey("textMarkRadius"),
              label: "Corners",
              value: a.draw.radius,
              min: 0,
              max: 200,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                live(a.copyWith(draw: a.draw.copyWith(radius: v)));
              },
              onCommit: done,
            ),
          const CanvasHint(
              "Padding is the room around the words the mark takes in: none "
              "of it for an underline tight under the letters, a few pixels "
              "for a highlighter. The one field sets all four sides; the four "
              "under it set one each."),
        ],
      ]),
    // How the copies of an echo are arranged: how many, how far apart, how
    // much quieter each one is, and whether they shrink away.
    if (a.echoes)
      CanvasControlGroup(label: "The copies", children: [
        CanvasNumberField(
          label: "How many",
          value: a.echo.copies.toDouble(),
          min: 1,
          max: 24,
          decimals: 0,
          width: 56,
          onChanged: (v) {
            live(a.copyWith(echo: a.echo.copyWith(copies: v.round())));
          },
          onCommit: done,
        ),
        CanvasNumberField(
          label: "Apart",
          value: a.echo.spacing,
          min: 0.05,
          max: 8,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            live(a.copyWith(echo: a.echo.copyWith(spacing: v)));
          },
          onCommit: done,
        ),
        CanvasNumberField(
          label: "Fade",
          value: a.echo.fade,
          min: 0.05,
          max: 1,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            live(a.copyWith(echo: a.echo.copyWith(fade: v)));
          },
          onCommit: done,
        ),
        CanvasNumberField(
          label: "Shrink",
          value: a.echo.shrink,
          min: 0.2,
          max: 1,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            live(a.copyWith(echo: a.echo.copyWith(shrink: v)));
          },
          onCommit: done,
        ),
        CanvasToggle(
          label: "Resolves",
          value: a.echo.resolve,
          onChanged: (v) => now(a.copyWith(echo: a.echo.copyWith(resolve: v))),
        ),
        const CanvasHint(
            "Resolves sends the copies on their way instead of leaving them "
            "there: they fan out, carry on in the direction they were "
            "headed, and are gone by the end — which turns the echo from a "
            "look into a way in."),
        const CanvasHint(
            "Apart is measured in line heights, so the same setting reads "
            "the same on a headline and on a caption. Fade is how much of "
            "one copy's strength the next one keeps — a little over half is "
            "a trail, 1 is a stack. The copies stay when the animation is "
            "over: it is a look as much as an arrival."),
      ]),
    if (a.on || a.closes)
      CanvasControlGroup(label: "Timing", children: [
        // Whatever the caller wants first in here -- the element's own
        // Length, which a part has no use for: a part has an offset and a
        // length of its own, measured against that one.
        ...timingFirst,
        if (a.preset.staggers || a.exit.staggers)
          CanvasNumberField(
            label: "Gap",
            min: 0,
            max: 4,
            decimals: 2,
            width: 62,
            value: a.gap,
            onChanged: (v) {
              live(a.copyWith(gap: v));
            },
            onCommit: done,
          ),
        if (a.preset.staggers || a.exit.staggers)
          const CanvasHint(
              "How long after one letter, word or line starts before the "
              "next does, as a share of one piece's own movement. 1 is "
              "strictly one after another; below 1 they overlap; above 1 "
              "leaves a pause between them."),
        // Where a scaling preset starts from, and on the way out where it
        // goes: above 1 it carries the words off the screen, at 0 it
        // shrinks them to nothing.
        if (a.scales)
          CanvasNumberField(
            label: "From size",
            min: 0,
            max: 8,
            decimals: 2,
            width: 66,
            value: a.scale > 0 ? a.scale : a.preset.from,
            onChanged: (v) {
              live(a.copyWith(scale: v));
            },
            onCommit: done,
          ),
        if (a.scales)
          const CanvasHint(
              "1 is full size. Below it the words grow into place; above it "
              "they arrive too large and settle. On the way out it is where "
              "they go — 2 and above carries them off the screen, 0 shrinks "
              "them to nothing."),
        CanvasDropdown<ChartEase>(
          label: "End curve",
          value: a.ease,
          width: 118,
          options: [for (var c in ChartEase.values) (c, c.label)],
          onChanged: (v) {
            now(a.copyWith(ease: v));
          },
        ),
      ]),
  ];
}

/// _markBits are a highlight and an underline: the two marks that are simply
/// *there* on some words, as opposed to one an animation draws on.
///
/// Written once and shown twice -- for the element, where they apply to every
/// word, and for a part, where they apply to a few. They were the part's
/// alone, so highlighting a whole headline meant first making a part that
/// covered it.
List<Widget> _markBits({
  required PartHighlight? highlight,
  required PartUnderline? underline,
  required Color textColor,
  required String keyPrefix,
  required void Function(PartHighlight?) setHighlight,
  required void Function(PartUnderline?) setUnderline,
  required void Function(PartHighlight) liveHighlight,
  required void Function(PartUnderline) liveUnderline,
  required VoidCallback done,

  /// icons draws the two switches as buttons rather than as words.
  ///
  /// For the row that carries five of them -- a part of the text -- where
  /// five words is a column rather than a line. The element's own marks have
  /// room for the words.
  bool icons = false,
}) {
  return [
    // A mark that is simply there, as opposed to one being drawn on by
    // an animation. Off until it is asked for: most parts are a colour
    // and nothing else, and two rows of padding fields under every one
    // of them would bury that.
    if (icons)
      CanvasIconButton(
        key: ValueKey("${keyPrefix}HighlightOn"),
        icon: Icons.format_color_fill,
        tooltip: "Highlight these words",
        active: highlight != null,
        onPressed: () =>
            setHighlight(highlight == null ? const PartHighlight() : null),
      )
    else
      CanvasToggle(
        label: "Highlight",
        value: highlight != null,
        onChanged: (v) => setHighlight(v ? const PartHighlight() : null),
      ),
    if (icons)
      CanvasIconButton(
        key: ValueKey("${keyPrefix}UnderlineOn"),
        icon: Icons.format_underlined,
        tooltip: "Underline these words",
        active: underline != null,
        onPressed: () =>
            setUnderline(underline == null ? const PartUnderline() : null),
      )
    else
      CanvasToggle(
        label: "Underline",
        value: underline != null,
        onChanged: (v) => setUnderline(v ? const PartUnderline() : null),
      ),
    if (highlight != null) ...[
      const CanvasLineBreak(),
      CanvasColorButton(
        label: "Highlight",
        color: highlight.color,
        gradient: highlight.fade,
        onChanged: (c) => setHighlight(highlight.copyWith(color: c)),
        onGradientChanged: (g) => setHighlight(g == null
            ? highlight.copyWith(flat: true)
            : highlight.copyWith(fade: g)),
      ),
      // One field for all four sides, and the four on their own under
      // it -- the same shape the drawn mark's padding takes, because it
      // is the same question about the same kind of band.
      CanvasNumberField(
        label: "Padding",
        value: highlight.evenPad ?? 0,
        min: 0,
        max: 200,
        decimals: 0,
        width: 62,
        onChanged: (v) {
          liveHighlight(highlight.withEvenPad(v));
        },
        onCommit: done,
      ),
      for (var (name, at, make)
          in <(String, double, PartHighlight Function(double))>[
        ("Left", highlight.padLeft, (v) => highlight.copyWith(padLeft: v)),
        ("Top", highlight.padTop, (v) => highlight.copyWith(padTop: v)),
        ("Right", highlight.padRight, (v) => highlight.copyWith(padRight: v)),
        (
          "Bottom",
          highlight.padBottom,
          (v) => highlight.copyWith(padBottom: v)
        ),
      ])
        CanvasNumberField(
          label: name,
          value: at,
          min: 0,
          max: 200,
          decimals: 0,
          width: 56,
          onChanged: (v) {
            liveHighlight(make(v));
          },
          onCommit: done,
        ),
      CanvasNumberField(
        label: "Corners",
        value: highlight.radius,
        min: 0,
        max: 200,
        decimals: 0,
        width: 62,
        onChanged: (v) {
          liveHighlight(highlight.copyWith(radius: v));
        },
        onCommit: done,
      ),
    ],
    if (underline != null) ...[
      const CanvasLineBreak(),
      CanvasDropdown<PartLineStyle>(
        key: ValueKey("${keyPrefix}UnderlineStyle"),
        label: "Line",
        value: underline.style,
        width: 130,
        options: [for (var v in PartLineStyle.values) (v, v.label)],
        onChanged: (v) => setUnderline(underline.copyWith(style: v)),
      ),
      CanvasColorButton(
        label: "Line colour",
        color: underline.color ?? textColor,
        gradient: underline.fade,
        onChanged: (c) => setUnderline(underline.copyWith(color: c)),
        onGradientChanged: (g) => setUnderline(g == null
            ? underline.copyWith(flat: true)
            : underline.copyWith(fade: g)),
      ),
      CanvasNumberField(
        label: "Width",
        value: underline.width,
        min: 0.5,
        max: 60,
        decimals: 1,
        width: 58,
        onChanged: (v) {
          liveUnderline(underline.copyWith(width: v));
        },
        onCommit: done,
      ),
      CanvasNumberField(
        label: "Away",
        value: underline.away,
        min: -40,
        max: 120,
        decimals: 0,
        width: 58,
        onChanged: (v) {
          liveUnderline(underline.copyWith(away: v));
        },
        onCommit: done,
      ),
      const CanvasHint(
          "The last four line styles are drawn rather than ruled: they "
          "wander, lean and overshoot the last letter the way a line "
          "drawn by hand does. Marker is a brush — thick in the middle "
          "and tapered at both ends. Width sets how heavy the line is, "
          "and Away how far under the letters it sits."),
    ],
  ];
}

/// _itemRows are the element's extra pieces of writing: one row each, in the
/// same control the element's own words get, with the slot it sits in at the
/// front of the line and its own button at the end.
///
/// The same control on purpose. An item is a piece of writing like any other
/// -- it has a face, a size, a weight and a colour -- so a second set of
/// controls that happened to do the same things would be a second set to
/// learn and a second one to keep in step.
List<Widget> _itemRows(BuildContext context, TextElement e, SettingsWrite write,
    VoidCallback begin, VoidCallback commit) {
  void now(List<TextItem> items) {
    begin();
    write(e.copyWith(items: items));
    commit();
  }

  List<TextItem> withItem(int at, TextItem next) => [
        for (var (i, item) in e.items.indexed) i == at ? next : item,
      ];

  return [
    // The pieces themselves, directly under the element's own row, because
    // they are the same thing: another piece of writing in the same box.
    // Same row, same button, and nothing on the line that the element's own
    // row does not have -- where it sits and the button that takes it away
    // are behind the button with everything else about it.
    for (var (i, item) in e.items.indexed)
      if (item.isIcon)
        _pictureRow(context, e, i, item, write, begin, commit)
      else
        ...typeGroups(
          item.spec,
          (spec) =>
              write(e.copyWith(items: withItem(i, item.copyWith(spec: spec)))),
          begin,
          commit,
          // What it says, so a column of rows says which is which -- and a
          // name of its own where one has been typed over it.
          label: item.says,
          onRename: (v) => now(withItem(i, item.copyWith(name: v))),
          remember: "textItem${item.id}",
          colourInMore: true,
          rule: false,
          // The captions are written once, over the element's own row above.
          captions: false,
          // Its place is its slot's to decide, so the two alignment dropdowns
          // would be controls that do nothing.
          includeAlign: false,
          extraMore: [
            const CanvasLineBreak(),
            ..._placeBits(e, i, item, write, begin, commit),
            const CanvasLineBreak(),
            CanvasIconButton(
              key: ValueKey("textItemRemove$i"),
              icon: Icons.delete_outline,
              tooltip: "Take this piece away",
              onPressed: () => now([
                for (var (n, it) in e.items.indexed)
                  if (n != i) it,
              ]),
            ),
          ],
        ),
    // And the line that adds one, under the pieces it adds to. No caption:
    // the rows above it are captioned with what each of them says, and a
    // heading over a line of two buttons is a word doing nothing. The gap
    // above it is the one every group leaves under itself.
    CanvasControlGroup(
        label: "Items",
        hideCaption: true,
        rule: false,
        children: [
          CanvasIconButton(
            key: const ValueKey("textAddItem"),
            icon: Icons.add,
            tooltip:
                "Another piece of writing in this box, in a place of its own",
            onPressed: () => now([
              ...e.items,
              TextItem.fresh(_freeSlot(e), e.textSpec),
            ]),
          ),
          // A picture is a piece like any other: the same list, the same slots,
          // the same row and button. It was a section of its own with a place, an
          // alignment and a gap that were nobody else's.
          CanvasIconButton(
            key: const ValueKey("textAddPicture"),
            icon: Icons.add_photo_alternate_outlined,
            tooltip: "A picture in this box, in a place of its own",
            onPressed: () =>
                now([...e.items, TextItem.freshIcon(_freeSlot(e))]),
          ),
          if (e.items.isEmpty)
            const CanvasHint(
                "A card is one element: a number over a title, a line of small "
                "print under it, a name against the right-hand edge. Each piece "
                "keeps its own type, and the words are typed on the canvas -- "
                "click the piece and type.\n\nTwo pieces in different slots are "
                "held to different corners, so the space between them is the "
                "box's to decide. Two in the same slot are a stack: one under "
                "the other, as far apart as their Gap says however big the box "
                "is."),
        ]),
  ];
}

/// _placeBits are the controls every piece has behind its button, whether it
/// is words or a picture: where it sits, and how much room it keeps.
///
/// One list rather than two, because "where does this go" is the same
/// question of both and answering it twice is how the two drift apart.
/// _middleSlotHint is why a block in a middle slot seems to move as its
/// words change.
///
/// Reported as the gap growing when text was taken out: a middle slot centres
/// the stack, so half of whatever the words lose is given back at the top.
/// It is doing what it says; what the person wanted was the block held under
/// the words above it, which is what a slot shared with them does.
const _middleSlotHint = CanvasHint(
    "A middle slot keeps this block centred, and the gap moves the whole "
    "stack from there — so taking words out lets it settle back down, which "
    "reads as the gap growing. For a fixed distance under the words above "
    "it, give it the same slot as them: blocks in one slot stack, each held "
    "its own gap below the one before.");

List<Widget> _placeBits(TextElement e, int at, TextItem item,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void put(TextItem next, {bool live = false}) {
    begin();
    write(e.copyWith(items: [
      for (var (i, it) in e.items.indexed) i == at ? next : it,
    ]));
    if (!live) commit();
  }

  return [
    // What to call this row. The caption says what the piece says otherwise,
    // which names a picture "Picture" however many of them there are.
    CanvasTextField(
      key: ValueKey("textItemName$at"),
      label: "Called",
      value: item.name,
      hint: item.isIcon ? "Picture" : "the words",
      width: 96,
      onChanged: (v) => put(item.copyWith(name: v), live: true),
      onCommit: commit,
    ),
    CanvasDropdown<TextSlot>(
      key: ValueKey("textItemSlot$at"),
      label: "Where",
      value: item.slot,
      width: 104,
      options: [for (var s in TextSlot.values) (s, s.label)],
      onChanged: (v) => put(item.copyWith(slot: v)),
    ),
    CanvasNumberField(
      key: ValueKey("textItemGap$at"),
      label: "Gap",
      value: item.gap,
      min: -400,
      max: 400,
      width: 56,
      onChanged: (v) => put(item.copyWith(gap: v), live: true),
      onCommit: commit,
    ),
    CanvasNumberField(
      key: ValueKey("textItemSide$at"),
      // Both ways round from one number: away from the edge the slot holds
      // it to, or back past it. Two fields here, not four -- see
      // TextItem.side.
      label: "Left/right",
      value: item.side,
      min: -2000,
      max: 2000,
      width: 66,
      onChanged: (v) => put(item.copyWith(side: v), live: true),
      onCommit: commit,
    ),
    if (!item.isIcon && item.slot.down == VerticalAlignSpec.middle)
      _middleSlotHint,
    const CanvasLineBreak(),
    // What is behind the piece. The colour is the switch: with nothing
    // painted there is no shape to round and no room to keep inside it, so
    // the rest waits until there is one.
    CanvasColorButton(
      key: ValueKey("textItemFill$at"),
      label: "Background",
      color: item.box.fill,
      gradient: item.box.fillFade,
      onChanged: (c) => put(item.copyWith(box: item.box.copyWith(fill: c))),
      onGradientChanged: (g) => put(item.copyWith(
          box: g == null
              ? item.box.copyWith(flatFill: true)
              : item.box.copyWith(fillFade: g))),
    ),
    if (item.box.fill.a > 0) ...[
      // The same two controls every other box gets, from the same place: one
      // number for all four corners and the four beside it, then the same
      // again for the room inside. Written out by hand here they were a
      // second set to keep level with the first -- and the second set had
      // "TL" where the first has an arrow, and an even number that could not
      // forget a corner that had been set on its own.
      // The two even numbers beside the colour they belong to, and the four
      // corners and the four sides on lines of their own under it -- which is
      // the shape these controls take everywhere else on the panel.
      ...cornerFields(
          item.box.corners,
          (c) => put(item.copyWith(box: item.box.withCorners(c)), live: true),
          commit,
          label: "Round",
          prefix: "textItem$at",
          part: SidePart.all),
      ...roomFields(
          item.box.pad,
          (r) => put(item.copyWith(box: item.box.withRoom(r)), live: true),
          commit,
          label: "Inside",
          prefix: "textItem$at",
          part: SidePart.all),
      const CanvasLineBreak(),
      ...cornerFields(
          item.box.corners,
          (c) => put(item.copyWith(box: item.box.withCorners(c)), live: true),
          commit,
          prefix: "textItem$at",
          part: SidePart.sides),
      const CanvasLineBreak(),
      ...roomFields(
          item.box.pad,
          (r) => put(item.copyWith(box: item.box.withRoom(r)), live: true),
          commit,
          prefix: "textItem$at",
          part: SidePart.sides),
    ],
  ];
}

/// _pictureRow is a picture piece's row: the same shape a words piece has --
/// what it is on the line, everything else behind the button.
///
/// Everything the Icon section used to hold is here except the three things
/// a slot has taken over: where it goes, how it lines up along that edge, and
/// the room it kept beside the words.
Widget _pictureRow(BuildContext context, TextElement e, int at, TextItem item,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var icon = item.icon ?? const TextIcon();

  void put(TextItem next) {
    begin();
    write(e.copyWith(items: [
      for (var (i, it) in e.items.indexed) i == at ? next : it,
    ]));
    commit();
  }

  void live(TextIcon next) {
    begin();
    write(e.copyWith(items: [
      for (var (i, it) in e.items.indexed)
        i == at ? item.copyWith(icon: next) : it,
    ]));
  }

  void now(TextIcon next) => put(item.copyWith(icon: next));

  return CanvasMoreGroup(
    label: item.says,
    onRename: (v) => put(item.copyWith(name: v)),
    rule: false,
    remember: "textItem${item.id}",
    tooltip: "Where it sits, its colour, its box and its line",
    row: [
      CanvasIconButton(
        key: ValueKey("textItemPicture$at"),
        icon: icon.on ? Icons.image_outlined : Icons.add_photo_alternate,
        tooltip: icon.on ? "Replace this picture" : "Choose a picture",
        onPressed: () async {
          var id = await pickCanvasImage(context);
          if (id != null) now(icon.copyWith(assetId: id));
        },
      ),
      // The other half of a shared picture store: one used on one canvas is
      // usually wanted on the next, and going back to find the file again is
      // the long way round to a picture the app already has.
      CanvasIconButton(
        key: ValueKey("textItemLibrary$at"),
        icon: Icons.photo_library_outlined,
        tooltip: "Use a picture you have already added",
        onPressed: () async {
          var id = await showRecentPictures(context);
          if (id != null) now(icon.copyWith(assetId: id));
        },
      ),
      CanvasNumberField(
        key: ValueKey("textItemSize$at"),
        label: "Size",
        value: icon.size,
        min: 1,
        max: 2000,
        width: 56,
        onChanged: (v) => live(icon.copyWith(size: v)),
        onCommit: commit,
      ),
      CanvasColorButton(
        label: "Tint",
        color: icon.color ?? e.textSpec.color,
        onChanged: (c) => now(icon.copyWith(color: c)),
      ),
      if (icon.color != null)
        CanvasIconButton(
          icon: Icons.format_color_reset_outlined,
          tooltip: "Draw it in its own colours",
          onPressed: () => now(icon.copyWith(clearColor: true)),
        ),
    ],
    more: [
      ..._placeBits(e, at, item, write, begin, commit),
      const CanvasLineBreak(),
      CanvasNumberField(
        label: "Outline",
        value: icon.outlineWidth,
        min: 0,
        max: 60,
        decimals: 1,
        width: 54,
        onChanged: (v) => live(icon.copyWith(outlineWidth: v)),
        onCommit: commit,
      ),
      if (icon.outlineWidth > 0)
        CanvasColorButton(
          label: "Line",
          color: icon.outlineColor,
          onChanged: (c) => now(icon.copyWith(outlineColor: c)),
        ),
      const CanvasLineBreak(),
      CanvasColorButton(
        label: "Fill",
        color: icon.box.fill,
        onChanged: (c) => now(icon.copyWith(box: icon.box.copyWith(fill: c))),
      ),
      CanvasColorButton(
        label: "Border",
        color: icon.box.borderColor,
        onChanged: (c) =>
            now(icon.copyWith(box: icon.box.copyWith(borderColor: c))),
      ),
      CanvasNumberField(
        label: "Width",
        value: icon.box.borderWidth,
        min: 0,
        max: 40,
        decimals: 1,
        width: 54,
        onChanged: (v) =>
            live(icon.copyWith(box: icon.box.copyWith(borderWidth: v))),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Round",
        value: icon.box.borderRadius,
        min: 0,
        max: 400,
        width: 54,
        onChanged: (v) =>
            live(icon.copyWith(box: icon.box.copyWith(borderRadius: v))),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Inside",
        value: icon.box.padding,
        min: 0,
        max: 400,
        width: 54,
        onChanged: (v) =>
            live(icon.copyWith(box: icon.box.copyWith(padding: v))),
        onCommit: commit,
      ),
      const CanvasLineBreak(),
      CanvasToggle(
        label: "Underline",
        value: icon.underline != null,
        onChanged: (v) => now(v
            ? icon.copyWith(underline: const PartUnderline())
            : icon.copyWith(clearUnderline: true)),
      ),
      if (icon.underline != null) ...[
        CanvasDropdown<PartLineStyle>(
          label: "Line",
          value: icon.underline!.style,
          width: 118,
          options: [for (var v in PartLineStyle.values) (v, v.label)],
          onChanged: (v) =>
              now(icon.copyWith(underline: icon.underline!.copyWith(style: v))),
        ),
        CanvasColorButton(
          label: "Colour",
          color: icon.underline!.color ?? icon.color ?? e.textSpec.color,
          onChanged: (c) =>
              now(icon.copyWith(underline: icon.underline!.copyWith(color: c))),
        ),
        CanvasNumberField(
          label: "Width",
          value: icon.underline!.width,
          min: 0.5,
          max: 60,
          decimals: 1,
          width: 54,
          onChanged: (v) => live(
              icon.copyWith(underline: icon.underline!.copyWith(width: v))),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Away",
          value: icon.underline!.away,
          min: -40,
          max: 120,
          width: 54,
          onChanged: (v) =>
              live(icon.copyWith(underline: icon.underline!.copyWith(away: v))),
          onCommit: commit,
        ),
      ],
      const CanvasLineBreak(),
      CanvasIconButton(
        key: ValueKey("textItemRemove$at"),
        icon: Icons.delete_outline,
        tooltip: "Take this piece away",
        onPressed: () {
          begin();
          write(e.copyWith(items: [
            for (var (i, it) in e.items.indexed)
              if (i != at) it,
          ]));
          commit();
        },
      ),
    ],
  );
}

/// _freeSlot is where the next piece goes: the first slot nothing is in, so
/// two pieces added one after another do not land on top of each other.
TextSlot _freeSlot(TextElement e) {
  var taken = {for (var item in e.items) item.slot};
  for (var slot in const [
    TextSlot.topLeft,
    TextSlot.bottomLeft,
    TextSlot.middleRight,
    TextSlot.topRight,
    TextSlot.bottomRight,
    TextSlot.topCentre,
    TextSlot.bottomCentre,
    TextSlot.middleLeft,
    TextSlot.middleCentre,
  ]) {
    if (!taken.contains(slot)) return slot;
  }
  return TextSlot.topLeft;
}
