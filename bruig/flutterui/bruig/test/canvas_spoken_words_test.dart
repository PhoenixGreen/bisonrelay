import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/speech.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_cues.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_spoken_words_test.dart is a voice-over heard as words: cues named
// by what is said at them, and an element put on the word it belongs to.
//
// whisper itself is the reader's program and is not run here. What is
// checked is everything either side of it: reading what it writes, keeping
// the words, naming cues and tying elements to them.

/// _said is "First we need the hardware", one word every 10 frames from
/// frame 100, then "it costs $300" from frame 200.
List<SpokenWord> _said() => [
      for (var (i, t) in ["First,", "we", "need", "the", "hardware."].indexed)
        SpokenWord(text: t, frame: 100 + i * 10, end: 108 + i * 10),
      for (var (i, t) in ["It", "costs", "\$300."].indexed)
        SpokenWord(text: t, frame: 200 + i * 10, end: 208 + i * 10),
    ];

ShapeElement _arriving(String id, int from) => ShapeElement(ElementBase(
    id: id,
    track: ElementTrack([
      Keyframe(frame: from, values: const {KeyframeChannel.reveal: 0}),
      Keyframe(frame: from + 10, values: const {KeyframeChannel.reveal: 1}),
    ])));

CanvasDocument _doc() => CanvasDocument(
    scenes: [
      CanvasScene(id: "a", frames: 300, elements: [_arriving("price", 10)]),
    ],
    words: _said());

void main() {
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  test("whisper's words are read, commas and all", () {
    var words = parseHeardWords('start,end,text\n'
        '0,100,""\n'
        '100,310," We\'ve"\n'
        '38480,39100," 8,640"\n'
        '39100,39400," ""quoted"""\n');
    expect([for (var w in words) w.text], ["We've", "8,640", "\"quoted\""],
        reason: "a breath is no word, and a number keeps its comma");
    expect(words[1].start, 38.48);
    expect(words[1].end, 39.1);
  });

  test("a cue is named by what is said from it to the next", () {
    var said = _said();
    expect(saidBetween(said, 100, 200), "First, we need the hardware.");
    expect(saidBetween(said, 200, 1000), "It costs \$300.");
    expect(saidBetween(said, 100, 200, most: 14), "First, we need…");
    expect(saidBetween(said, 0, 90), "", reason: "nothing said there");
    // A cue found at a pause lands just after the voice starts again; the
    // word it lands a moment late for is still its first.
    expect(saidBetween(said, 205, 1000, lead: 8), "It costs \$300.");
    expect(saidBetween(said, 106, 205, lead: 8), "First, we need the hardware.",
        reason: "and the next line's first word is not this one's last");
  });

  test("the words are kept with the document", () {
    var back = CanvasDocument.fromJson(_doc().toJson());
    expect([for (var w in back.words) w.text],
        [for (var w in _said()) w.text]);
    expect(back.words.last.frame, 220);
    expect(const CanvasDocument().toJson().containsKey("words"), isFalse);
  });

  test("an element put on a word arrives as it is said", () {
    var c = CanvasController(_doc());
    addTearDown(c.dispose);
    var price = c.wordsMatching("300").single;
    c.cueOnWord("price", price);
    var cue = c.cues.single;
    expect(cue.name, "\$300.");
    expect(cue.frame, 220);
    var e = c.document.allScenes.single.elements.single;
    expect(e.base.cue, cue.id);
    expect(e.base.track!.keys.first.frame, 220);

    // A second element on the same word shares the cue rather than making
    // another on top of it.
    c.cueOnWord("price", price);
    expect(c.cues.length, 1);
  });

  test("a word is found whatever its case and punctuation", () {
    var c = CanvasController(_doc());
    addTearDown(c.dispose);
    expect([for (var w in c.wordsMatching("HARDWARE")) w.frame], [140]);
    expect(c.wordsMatching(""), isEmpty);
    expect(c.wordInContext(c.wordsMatching("need").single),
        "we need the");
  });

  testWidgets("the cue card finds a word and puts the element on it",
      (tester) async {
    var c = CanvasController(_doc());
    addTearDown(c.dispose);
    c.selectOnly("price");
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child:
          MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
    ));
    await tester.pumpAndSettle();

    var field = find.byKey(const ValueKey("elementCueWord"));
    expect(field, findsOneWidget, reason: "offered with no cues at all");
    tester.widget<CanvasTextField>(field).onChanged("300");
    await tester.pumpAndSettle();
    var match = find.byKey(const ValueKey("elementCueWord-220"));
    await tester.ensureVisible(match);
    await tester.pumpAndSettle();
    await tester.tap(match);
    await tester.pumpAndSettle();

    expect(c.cues.single.name, "\$300.");
    expect(
        c.document.allScenes.single.elements.single.base.track!.keys.first
            .frame,
        220);
    expect(c.wordQuery, isEmpty, reason: "the search is cleared after");
  });
}
