import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_doll.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_draw_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_doll_test.dart is the doll a sketch is posed and drawn
// over: built from its rig, drawn in the editor for the sketch picked --
// under one drawn from nothing, faintly over any other -- and never in
// anything made from the canvas. See character_doll.dart.

CharacterElement _empty({String id = "c", double x = 20}) => CharacterElement(
    ElementBase(id: id, x: x, y: 20, width: 160, height: 340),
    dna: CharacterType.empty.dna);

Future<List<int>> _pixels(CharacterElement e, {bool editing = true}) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0, editing: editing);
  var img = await rec.endRecording().toImage(200, 380);
  return (await img.toByteData())!.buffer.asUint8List();
}

int _opaque(List<int> px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 0) n++;
  }
  return n;
}

void main() {
  test("drawn for the sketch picked, in the editor alone", () async {
    var c = CanvasController(CanvasDocument(frames: 24)
        .addElement(_empty())
        .addElement(_empty(id: "d", x: 300))
        .addElement(CharacterElement(
            const ElementBase(id: "b", x: 500, y: 20, width: 160, height: 340),
            dna: characterCast.first.dna)));
    CharacterElement el(String id) => c.document.elementById(id) as CharacterElement;
    c.selectOnly("c");
    expect(_opaque(await _pixels(el("c"))), 0, reason: "no doll until it is asked for");
    c.showPuppet = true;
    c.puppet3D = true;
    expect(c.dollShown, isTrue);
    expect(characterDollOf?.call(el("c")), DollGuide.under);
    expect(characterDollOf?.call(el("d")), DollGuide.none, reason: "not picked");
    var shown = _opaque(await _pixels(el("c")));
    expect(shown, greaterThan(2000), reason: "a body's worth");
    expect(_opaque(await _pixels(el("c"), editing: false)), 0, reason: "never exported");
    c.selectOnly("b");
    expect(characterDollOf?.call(el("b")), DollGuide.over, reason: "faint, over a drawn one");
    c.puppet3D = false;
    expect(characterDollOf, isNull);
    c.puppet3D = true;
    c.dispose();
    expect(characterDollOf, isNull, reason: "put away with its editor");
  });

  test("posed as the character is, its proportions the character's", () async {
    DollGuide under(CharacterElement e) => DollGuide.under;
    characterDollOf = under;
    addTearDown(() => characterDollOf = null);
    var rest = await _pixels(_empty());
    var waving = await _pixels(_empty().copyWith(pose: posePresets[1].pose));
    expect(waving, isNot(rest));
    var child = _empty().copyWith(dna: CharacterType.empty.dna.copyWith(headsTall: 3.5));
    expect(await _pixels(child), isNot(rest), reason: "a bigger head on a shorter body");
  });

  test("its guide lines and its lens", () async {
    DollGuide under(CharacterElement e) => DollGuide.under;
    characterDollOf = under;
    addTearDown(() {
      characterDollOf = null;
      characterDollLook = const DollLook();
    });
    var e = _empty().copyWith(pose: posePresets[1].pose.withTurn(30));
    int orange(List<int> px) {
      var n = 0;
      for (var i = 0; i < px.length; i += 4) {
        if (px[i + 3] > 200 && px[i] > 180 && px[i + 2] < 120) n++;
      }
      return n;
    }

    characterDollLook = const DollLook(lines: false);
    var plain = await _pixels(e);
    expect(orange(plain), 0);
    characterDollLook = const DollLook();
    var lined = await _pixels(e);
    expect(orange(lined), greaterThan(150), reason: "the middle drawn down it");
    characterDollLook = const DollLook(lens: 0.9);
    var close = await _pixels(e);
    expect(close, isNot(lined), reason: "what is nearer, bigger");
  });

  testWidgets("the bar's puppet is flat or a doll", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(CanvasDocument(frames: 24).addElement(_empty()));
    addTearDown(c.dispose);
    c.selectOnly("c");
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: CharacterDrawBar(controller: c))),
    ));
    await tester.pumpAndSettle();
    var doll = find.byKey(const ValueKey("characterDrawPuppet3D"));
    expect(doll, findsNothing, reason: "only with the puppet out");
    await tester.tap(find.byKey(const ValueKey("characterDrawPuppet")));
    await tester.pumpAndSettle();
    await tester.tap(doll);
    await tester.pumpAndSettle();
    expect(c.dollShown, isTrue);
    // Its lines and its lens, while it is out.
    await tester.tap(find.byKey(const ValueKey("characterDollLines")));
    await tester.pumpAndSettle();
    expect(c.dollLines, isFalse);
    expect(characterDollLook.lines, isFalse);
    expect(find.byKey(const ValueKey("characterDollLens")), findsOneWidget);
    c.dollLens = 0.65;
    expect(characterDollLook.lens, 0.65);
    await tester.tap(doll);
    await tester.pumpAndSettle();
    expect(c.dollShown, isFalse);
    expect(c.showPuppet, isTrue, reason: "the flat puppet back");
  });

  test("a puppet's form is saved with the character", () {
    var form = PuppetForm.of(CharacterType.woman).copyWith(headsTall: 5, feminine: 0.7);
    var e = _empty().copyWith(puppet: form);
    var back = CharacterElement.fromJson(e.props(), e.base);
    expect(back.puppet?.body, CharacterType.woman);
    expect(back.puppet?.headsTall, 5);
    expect(back.puppet?.feminine, 0.7);
    expect(back.puppet?.look[Look.chest], form.look[Look.chest]);
    expect(e.copyWith(ownPuppet: true).puppet, isNull);
    expect(PuppetForm.of(CharacterType.man).isAsMade, isTrue);
    expect(form.isAsMade, isFalse);
  });

  group("the Puppet section", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    Future<CanvasController> open(WidgetTester tester, CharacterElement e) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets("there while the puppet is out; a body picked shapes the doll and an empty one",
        (tester) async {
      var c = await open(tester, _empty());
      expect(find.byKey(const ValueKey("elementSection-puppet")), findsNothing);
      c.showPuppet = true;
      c.puppet3D = true;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("elementSection-puppet")), findsOneWidget);
      var woman = find.byKey(const ValueKey("puppetBody-woman"));
      await tester.ensureVisible(woman);
      await tester.tap(woman);
      await tester.pumpAndSettle();
      var e = c.document.elementById("c") as CharacterElement;
      expect(e.puppet?.body, CharacterType.woman);
      expect(e.dna.kind, CharacterType.empty, reason: "still drawn from nothing");
      expect(e.dna.headsTall, CharacterType.woman.dna.headsTall, reason: "its body the doll's");
      // Shaped, a step at a time.
      expect(find.byKey(const ValueKey("puppetHeadsTall")), findsOneWidget);
      for (var l in puppetLooks) {
        expect(find.byKey(ValueKey("puppetLook-${l.name}")), findsOneWidget);
      }
      // Back to the character's own.
      var own = find.byKey(const ValueKey("puppetBody-character"));
      await tester.ensureVisible(own);
      await tester.tap(own);
      await tester.pumpAndSettle();
      expect((c.document.elementById("c") as CharacterElement).puppet, isNull);
      // How it is shown.
      expect(find.byKey(const ValueKey("puppetLens")), findsOneWidget);
      var lines = find.byKey(const ValueKey("puppetLines"));
      await tester.ensureVisible(lines);
      await tester.tap(lines);
      await tester.pumpAndSettle();
      expect(c.dollLines, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  test("a woman's doll is not a man's, nor a child's", () async {
    DollGuide under(CharacterElement e) => DollGuide.under;
    characterDollOf = under;
    addTearDown(() => characterDollOf = null);
    Future<List<int>> as(CharacterType t) =>
        _pixels(_empty().copyWith(puppet: PuppetForm.of(t)));
    var woman = await as(CharacterType.woman), man = await as(CharacterType.man);
    expect(woman, isNot(man));
    expect(await as(CharacterType.girl), isNot(woman));
  });
}
