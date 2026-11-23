import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_fields.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/document_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/text_documents.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/recent_pictures.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/preset_pair.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/text_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/type_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/position_group.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/box_group.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/fill_controls.dart';

part 'text_settings_piece.dart';
part 'text_settings_words.dart';
part 'text_settings_parts.dart';

// text_settings.dart is a text element's settings.

/// textPanel is a text element's settings: its layers over the panel every
/// element shares, filled with the text's own bits (see elementPanel); a
/// picked piece has a small panel of its own in the same frame instead.
Widget textPanel(
    BuildContext context,
    CanvasController controller,
    TextElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var w = _TextWrites(e, write, begin, commit);
  var layers = TextLayersList(
      key: const ValueKey("textLayersList"),
      controller: controller,
      element: e,
      onChanged: w.now);
  if (controller.textLayer(e) case var layer?) {
    return _piecePanel(context, controller, e, e.items.indexOf(layer), layer,
        write, begin, commit,
        layers: layers);
  }
  return elementPanel(context, controller, e, write, begin, commit,
      parts: layers,
      quick: _bodyQuick(controller, e, write, begin, commit),
      position: e.wordsSetIn(controller.document) == WordsSet.onLine
          ? _placedByLine(controller, e, write, begin, commit)
          : null,
      // A look on all of it and one on its words, each a layer of its own.
      looks: PanelLooks(
          said: _looksSaid(e, {"", MotionDevice.bodyLayer}),
          groups: [
            LooksGroup(
                key: const ValueKey("textLooksAll"),
                controller: controller,
                element: e,
                title: "Looks on the whole text"),
            LooksGroup(
                key: const ValueKey("textLooksWords"),
                controller: controller,
                element: e,
                layer: MotionDevice.bodyLayer,
                title: "Looks on the words"),
          ]),
      bits: _bodyBits(context, controller, e, write, begin, commit));
}

/// _placedByLine stands for the position group while the words ride a line:
/// they take their place and angle from the line, so the group's fields
/// would move them off it, and only their opacity is their own.
Widget _placedByLine(CanvasController controller, TextElement e,
        SettingsWrite write, VoidCallback begin, VoidCallback commit) =>
    CanvasControlGroup(label: e.kind.label, children: [
      const Padding(
        padding: EdgeInsets.only(top: controlLabelHeight, right: 6),
        child: SizedBox(
          height: controlHeight,
          child: Center(
            child: Txt.S("Placed by the line it follows"),
          ),
        ),
      ),
      opacityField(controller, e, write, begin, commit),
    ]);

/// _TextWrites is how the text panel writes [e]: [now] as one undo step,
/// [live] as one step of typing or a drag, kept until commit, and [piece]
/// either way for one of its pieces.
class _TextWrites {
  final TextElement e;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  const _TextWrites(this.e, this.write, this.begin, this.commit);

  void now(TextElement next) {
    begin();
    write(next);
    commit();
  }

  void live(TextElement next) {
    begin();
    write(next);
  }

  /// piece writes [next] in place of piece [at].
  void piece(int at, TextItem next, {bool live = false}) {
    var whole = e.copyWith(items: [
      for (var (i, it) in e.items.indexed) i == at ? next : it,
    ]);
    live ? this.live(whole) : now(whole);
  }
}

/// _bodyEdit changes the words' type: a size typed while fitted stops the
/// fitting, or it would do nothing.
TypeEdit _bodyEdit(TextElement e, SettingsWrite write, VoidCallback begin,
        VoidCallback commit) =>
    TypeEdit(
        e.textSpec,
        (spec) => write(e.copyWith(
            textSpec: spec,
            autoSize: e.autoSize && spec.fontSize == e.textSpec.fontSize)),
        begin,
        commit);

/// _bodyQuick is the element's own words' face, size, colour, alignment
/// and style: what a text is changed by most.
Widget _bodyQuick(CanvasController controller, TextElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var t = _bodyEdit(e, write, begin, commit);
  var styles = controller.textStyles;
  var fitted = e.fittedIn(controller.document);
  // Face and size, then colour and alignment, then style.
  return CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
    panelRow([
      cell(typeFont(t), flex: 3, min: 120),
      cell(typeSize(t, fitted: fitted), width: 132),
    ]),
    const SizedBox(height: 8),
    panelRow([
      cell(typeColour(t), width: 104),
      cell(typeAlign(t), width: 116),
      cell(CanvasDropdown<String>(
        key: const ValueKey("quickStyle"),
        label: "Style",
        value: styles.any((s) => s.name == e.style) ? e.style : "",
        width: 80,
        options: [
          ("", "Its own"),
          for (var s in styles) (s.name, s.name),
        ],
        onChanged: (v) => controller.useTextStyle(e.id, v),
      )),
    ]),
    const SizedBox(height: 8),
    if (fitted)
      CanvasStateNote(
          "Its size follows the box. Set a size and the fitting "
          "turns off.",
          action: "Stop fitting", onAction: () {
        begin();
        write(e.copyWith(autoSize: false));
        commit();
      }),
  ]);
}

/// _looksSaid is the looks on [layers] of [e] switched on, by name.
String _looksSaid(TextElement e, Set<String> layers) {
  var names = [
    for (var d in e.base.motion.devices)
      if (d.on && d.side == MotionDeviceSide.look && layers.contains(d.layer))
        d.kind.label
  ];
  return names.isEmpty ? "" : names.join(", ");
}

/// _bodyBits are what the text's own words put in each section of the
/// panel, past what every element has there.
List<PanelBit> _bodyBits(
    BuildContext context,
    CanvasController controller,
    TextElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var w = _TextWrites(e, write, begin, commit);
  var t = _bodyEdit(e, write, begin, commit);
  var spec = e.textSpec;
  var words = e.displayText.replaceAll("\n", " ");
  return [
    PanelBit(PanelSection.content,
        summary: [
          "\u201c${words.length > 28 ? "${words.substring(0, 28)}…" : words}\u201d",
          if (e.fittedIn(controller.document)) "fitted to the box",
        ].join(" · "),
        children: [
          CanvasControlGroup(
              key: const ValueKey("textWordsTyped"),
              label: "Words",
              hideCaption: true,
              rule: false,
              children: [
                // Typed here as well as on the canvas where the words are the
                // element's own; a document's are read, not typed.
                if (!e.wordsFromDocument)
                  CanvasTextField(
                    key: const ValueKey("textWordsField"),
                    label: "Words",
                    value: e.text,
                    maxLines: 3,
                    width: 200,
                    onChanged: (v) => w.live(e.copyWith(text: v)),
                    onCommit: commit,
                  ),
                typeCaseButtons(t,
                    key: const ValueKey("textCase"),
                    keyOf: (c) => "textCase-${c.name}"),
              ]),
          _textWordsCard(context, controller, e, write, begin, commit),
          CanvasControlGroup(
              key: const ValueKey("textWhere"),
              label: "In the box",
              rule: false,
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("textBodySlot"),
                  label: "Where",
                  value: e.slot?.name ?? "",
                  width: 116,
                  options: [
                    ("", "Fills the box"),
                    for (var s in TextSlot.values) (s.name, s.label),
                  ],
                  onChanged: (v) => w.now(v.isEmpty
                      ? e.copyWith(clearSlot: true)
                      : e.copyWith(slot: TextSlot.fromName(v))),
                ),
                if (e.slot != null &&
                    e.text.isNotEmpty &&
                    e.bodySlotIn(controller.document) == null)
                  const CanvasHint(
                      "A line, columns and a chain of boxes are arrangements of "
                      "the whole text, so the words ride the line or fill the box "
                      "while one is on and the slot waits."),
                if (e.slot?.down == VerticalAlignSpec.middle) _middleSlotHint,
                // How the lines sit in the box: vertically, and justified
                // across it (Align, in the strip above, is the rest).
                panelRow([cell(typeVertical(t))]),
                typeJustify(t),
              ]),
        ]),
    PanelBit(PanelSection.look, summary: typeSummary(spec), children: [
      CanvasControlGroup(
          key: const ValueKey("textLetters"),
          label: "Letters",
          rule: false,
          children: [
            ...typeLetters(t,
                underline: false,
                vertical: false,
                justify: false,
                textCase: false),
            const CanvasLineBreak(),
            // What the letters are painted with: their colour (in the
            // strip above), a picture or a pattern.
            CanvasDropdown<TextFillKind>(
              key: const ValueKey("textFillKind"),
              label: "Painted with",
              value: spec.fill.kind,
              width: 118,
              options: [for (var k in TextFillKind.values) (k, k.label)],
              onChanged: (v) =>
                  t.now(spec.copyWith(fill: spec.fill.copyWith(kind: v))),
            ),
            if (spec.fill.kind != TextFillKind.color)
              ...fillBits(context, spec.fill,
                  (f) => t.onChanged(spec.copyWith(fill: f)), begin, commit),
          ]),
      CanvasControlGroup(
          key: const ValueKey("textMarks"),
          label: "Marks",
          rule: false,
          children: [
            ..._markBits(
              highlight: e.highlight,
              underline: e.underline,
              textColor: e.textSpec.color,
              keyPrefix: "text",
              setHighlight: (h) => w.now(h == null
                  ? e.copyWith(clearHighlight: true)
                  : e.copyWith(highlight: h)),
              setUnderline: (u) => w.now(u == null
                  ? e.copyWith(clearUnderline: true)
                  : e.copyWith(underline: u)),
              liveHighlight: (h) => w.live(e.copyWith(highlight: h)),
              liveUnderline: (u) => w.live(e.copyWith(underline: u)),
              done: commit,
            ),
          ]),
      boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
          label: "Box behind the words",
          remember: "text",
          rule: false,
          fillPickedIn: context,
          compact: true),
    ]),
    PanelBit(PanelSection.layout,
        summary: switch (e.wordsSetIn(controller.document)) {
          WordsSet.onLine => "on a line",
          WordsSet.wrapped ||
          WordsSet.inColumns ||
          WordsSet.inBox =>
            e.columns.count > 1 ? "${e.columns.count} columns" : "",
        },
        children: [
          CanvasControlGroup(label: "Columns", rule: false, children: [
            CanvasNumberField(
              key: const ValueKey("textColumns"),
              // "Count", not "Columns": the caption already says it.
              label: "Count",
              value: e.columns.count.toDouble(),
              min: 1,
              max: 12,
              width: 54,
              onChanged: (v) {
                begin();
                write(
                    e.copyWith(columns: e.columns.copyWith(count: v.round())));
              },
              onCommit: commit,
            ),
            // A paragraph gap is a line, so a new column or chained box can
            // start with an empty row. Only on the box owning the words.
            if (flowSourceOf(e, controller.document) == null)
              CanvasToggle(
                key: const ValueKey("textColumnsNoBlankStart"),
                label: "No blank first line",
                value: e.columns.noBlankStart,
                onChanged: (v) => w.now(
                    e.copyWith(columns: e.columns.copyWith(noBlankStart: v))),
              ),
            // The rest means something only once there is a gutter.
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
                onChanged: (v) => w
                    .now(e.copyWith(columns: e.columns.copyWith(ruleStyle: v))),
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
                    write(
                        e.copyWith(columns: e.columns.copyWith(ruleWidth: v)));
                  },
                  onCommit: commit,
                ),
                CanvasColorButton(
                  label: "Colour",
                  color: e.columns.ruleColor,
                  onChanged: (c) => w.now(
                      e.copyWith(columns: e.columns.copyWith(ruleColor: c))),
                ),
              ],
            ],
          ]),
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
                options: _curveOptions(controller),
                onChanged: (v) => w.now(v.isEmpty
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
                  value: controller.valueAt(
                      e, KeyframeChannel.slide, e.curve!.offset),
                  // Far enough to carry the words off the line's end and back,
                  // as a caption slides in and out of a shot.
                  min: -2,
                  max: 2,
                  onChanged: (v) {
                    begin();
                    // A keyframe once this frame has one, so dragging while
                    // animating retimes the travel rather than moving it all.
                    if (controller.hasValueKey(e, KeyframeChannel.slide)) {
                      controller.setValueKey(e, KeyframeChannel.slide, v);
                      return;
                    }
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
              ],
            ],
            more: [
              if (e.curve != null) ...[
                CanvasToggle(
                  label: "Below",
                  value: e.curve!.away,
                  onChanged: (v) =>
                      w.now(e.copyWith(curve: e.curve!.copyWith(away: v))),
                ),
                CanvasToggle(
                  key: const ValueKey("textCurveMask"),
                  label: "Mask",
                  value: e.curve!.mask,
                  onChanged: (v) =>
                      w.now(e.copyWith(curve: e.curve!.copyWith(mask: v))),
                ),
                CanvasToggle(
                  // Not the line element's Hide: a hidden element is skipped
                  // everywhere, here too, so the text would go with it.
                  label: "Hide line",
                  value: e.curve!.hideHost,
                  onChanged: (v) =>
                      w.now(e.copyWith(curve: e.curve!.copyWith(hideHost: v))),
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
        ]),
    PanelBit(PanelSection.motion, children: [
      // Its arrival and way out, its own text presets, chosen here as in
      // its Chain (see OwnStyle).
      CanvasControlGroup(
          key: const ValueKey("textMotionPick"),
          label: "Arrival and leaving",
          hideCaption: true,
          rule: false,
          children: [
            // Each in two, as in the Chain: its family, then which.
            panelRow([
              for (var w in canvasPresetPair<TextAnimationPreset>(
                  key: "textArrival",
                  familyLabel: "Arrival",
                  pair: PresetPair(textPresetOptions(), e.animation.preset,
                      TextAnimationPreset.none),
                  onChanged: (v) => controller.applyTextAnimation(e, v)))
                cell(w),
            ]),
            panelRow([
              for (var w in canvasPresetPair<TextAnimationPreset>(
                  key: "textLeaving",
                  familyLabel: "Leaving",
                  pair: PresetPair(textPresetOptions(), e.animation.exit,
                      TextAnimationPreset.none),
                  onChanged: (v) => controller.applyTextExit(e, v)))
                cell(w),
            ]),
          ]),
    ]),
    PanelBit(PanelSection.more,
        summary: [
          if (e.wordsFromDocument && e.document.markdown) "Markdown",
          e.parts.isEmpty
              ? "Parts of the text"
              : "${e.parts.length} part${e.parts.length == 1 ? "" : "s"}",
        ].join(", "),
        children: [
          if (e.wordsFromDocument && e.document.markdown)
            _markdownSection(controller, e, write, begin, commit),
          _partsSection(e, write, begin, commit),
        ]),
    // Its named style, after the presets every element has.
    PanelBit(PanelSection.more,
        summary: "styles",
        last: true,
        children: [_textStyleCard(controller, e)]),
  ];
}

/// _curveOptions is every line and path on the canvas for text to ride: to
/// a reader both are lines.
List<(String, String)> _curveOptions(CanvasController controller) => [
      ("", "Nothing"),
      for (var element in controller.document.elements)
        if (element is LineElement || element is PathElement)
          (element.id, element.name),
    ];
