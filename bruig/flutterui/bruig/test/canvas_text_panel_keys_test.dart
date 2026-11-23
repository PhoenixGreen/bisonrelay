import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show forgetSectionsForTest;
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';

import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';
import 'support/kept_lists.dart';

// canvas_text_panel_keys_test.dart is what a text element's settings show,
// in the real sidebar at the width it opens at, every section open, for
// each state a text is in: plain; with a part of its words set apart; on a
// line; showing a document's words; with pieces, one of each kind picked
// in turn (words, a picture, a picture not yet chosen); docked in a
// Layout's cell; with an arrival; set in a named style; and with looks on
// all of it and on its words. For each it
// holds the few keys and words the state is for.
//
// It also records, for each state, every key in the sidebar in order and
// every piece of text it shows in order, so that a change to how the panel
// is built can be shown to change nothing a person sees. Set TEXT_PANEL to
// a folder and run this file on the code as it is: each state's lists are
// written there. Make the change and run it again: a state whose lists
// differ fails, showing both where they part (kept_lists.dart). Without
// TEXT_PANEL nothing is kept, so the test is harmless in the whole suite.
// canvas_panel_keys_test.dart keeps the same lists for every other kind.

const _screen = Size(300, 9000);

/// _text is the text every state starts from.
const _text = TextElement(
  ElementBase(id: "t", x: 100, y: 100, width: 400, height: 200),
  text: "You come across an idea",
);

/// _pieces are one piece of each kind: words, a picture, and a picture not
/// yet chosen.
const _pieces = [
  TextItem(id: "w", text: "Small print", slot: TextSlot.bottomLeft),
  TextItem(
      id: "p",
      slot: TextSlot.topRight,
      icon: TextIcon(assetId: "asset1", size: 60)),
  TextItem(id: "i", slot: TextSlot.bottomRight, icon: TextIcon()),
];

/// _State is one state of a text: its name, the canvas it is on, what is
/// done to the controller before the panel is shown, the fold opened in it
/// (by the name it is remembered by), and what the panel must show.
typedef _State = ({
  String name,
  CanvasDocument document,
  void Function(CanvasController)? setUp,
  String? fold,
  List<String> keys,
  List<String> words,
});

List<_State> _states() => [
      (
        name: "plain",
        document: const CanvasDocument().addElement(_text),
        setUp: null,
        fold: null,
        keys: [
          "textLayersList",
          "quickStrip",
          "quickStyle",
          "textWordsField",
          "textWords",
          "textWhere",
          "textLetters",
          "textMarks",
          "textLooksAll",
          "textLooksWords",
          "textColumns",
          "textMotionPick",
          "textPresets",
        ],
        words: ["Content", "Look", "Layout", "Motion", "More"],
      ),
      (
        name: "part",
        document: const CanvasDocument().addElement(_text.copyWith(
            parts: const [TextPart(from: 2, to: 3, color: Color(0xFFFF0000))])),
        setUp: null,
        fold: "textParts",
        keys: ["partBold0", "partItalic0"],
        words: ["Parts of the text"],
      ),
      (
        name: "on a line",
        document: const CanvasDocument()
            .addElement(const LineElement(ElementBase(
                id: "line", x: 100, y: 400, width: 600, height: 10)))
            .addElement(_text.copyWith(
                curve: const TextOnCurve(elementId: "line", offset: 0.25))),
        setUp: null,
        fold: null,
        keys: ["textCurveMask"],
        words: ["on a line", "Slide", "Hide line"],
      ),
      (
        name: "document",
        document: const CanvasDocument().addElement(_text.copyWith(
            document: const TextDocumentRef(
                folder: "Notes", name: "essay", markdown: true))),
        setUp: null,
        fold: null,
        keys: ["textDocumentPick"],
        words: ["Markdown"],
      ),
      for (var (piece, keys, words) in [
        ("w", ["pieceRemove", "quickPieceStyle", "pieceLetters"], ["Text"]),
        ("p", ["pieceRemove", "textItemPicture1", "textLooksPiece"], []),
        ("i", ["pieceRemove", "textItemPicture2"], ["No picture chosen"]),
      ])
        (
          name: "piece $piece picked",
          document:
              const CanvasDocument().addElement(_text.copyWith(items: _pieces)),
          setUp: (c) => c.pickTextLayer("t", piece),
          fold: null,
          keys: ["textLayersList", "quickSlot", ...keys],
          words: ["With the whole text", "Remove this piece", ...words],
        ),
      (
        name: "docked",
        document: const CanvasDocument()
            .addElement(const LayoutElement(
                ElementBase(id: "L", x: 600, y: 100, width: 800, height: 600),
                root: LayoutNode.cut(
                    vertical: true,
                    a: LayoutNode.leaf("a"),
                    b: LayoutNode.leaf("b")),
                cells: [LayoutCell(id: "a"), LayoutCell(id: "b")]))
            .addElement(_text.withBase(dock: "L:a")),
        setUp: null,
        fold: null,
        keys: ["dockCell"],
        words: [],
      ),
      (
        name: "arrival",
        document:
            const CanvasDocument(frames: 96, frameRate: 24).addElement(_text),
        setUp: (c) => c.applyTextAnimation(
            c.document.elementById("t") as TextElement,
            TextAnimationPreset.fadeUp),
        fold: null,
        keys: ["textArrival"],
        words: ["Fade up"],
      ),
      (
        name: "named style",
        document: const CanvasDocument(textStyles: [
          NamedTextStyle(
              "Heading",
              TextSpec(
                  fontSize: 30,
                  outlineWidth: 2,
                  outlineColor: Color(0xFF0000FF)))
        ]).addElement(_text.copyWith(style: "Heading")),
        setUp: null,
        fold: null,
        keys: ["quickStyle"],
        words: ["Heading"],
      ),
      (
        name: "looks",
        document: const CanvasDocument().addElement(_text.withBase(
            motion: const ElementBase(id: "t").motion.copyWith(
                    devices: withMotionDeviceIds(const [
                  MotionDevice(MotionDeviceKind.shadow),
                  MotionDevice(MotionDeviceKind.glow,
                      layer: MotionDevice.bodyLayer),
                ])))),
        setUp: null,
        fold: null,
        keys: ["textLooksAll", "textLooksWords"],
        // The Look heading names the looks on all of it and on its words.
        words: ["Shadow, Glow"],
      ),
    ];

void main() {
  // Each state from a panel as a new run has it, so that what the one
  // before opened does not show in the next, whichever run alone.
  setUp(() {
    forgetPanelsForTest();
    forgetSectionsForTest();
    CanvasSection.openAll = true;
  });
  tearDownAll(() => CanvasSection.openAll = false);

  for (var state in _states()) {
    testWidgets("a text's settings: ${state.name}", (tester) async {
      SharedPreferences.setMockInitialValues({});
      setTestScreen(tester, _screen);
      var c = CanvasController(state.document);
      addTearDown(c.dispose);
      c.selectOnly("t");
      state.setUp?.call(c);
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await tester.pumpAndSettle();
      if (state.fold case var fold?) {
        var head = find.byKey(ValueKey("expander-$fold"));
        await tester.ensureVisible(head);
        await tester.pumpAndSettle();
        await tester.tap(head);
        await tester.pumpAndSettle();
      }

      var (keys, words) = shownUnder(tester, find.byType(CanvasSidebarHost));
      for (var k in state.keys) {
        expect(keys, contains("[<'$k'>]"), reason: "${state.name}: $k");
      }
      for (var w in state.words) {
        expect(words.any((s) => s.contains(w)), isTrue,
            reason: "${state.name}: \"$w\"");
      }
      keepOrCompareLines("TEXT_PANEL", state.name, "keys", keys);
      keepOrCompareLines("TEXT_PANEL", state.name, "words", words);
    });
  }
}
