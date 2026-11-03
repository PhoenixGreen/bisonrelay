import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_face.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/character_designs.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/ui/character_shape_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_studio_3d.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The new Character Studio: its steps, parts and settings, which are there
// before a character can be drawn, and the page before it can draw one -- no
// Flutter GPU, or the bodies still to fetch. Tests run without Flutter GPU,
// so the stage itself is checked in the app.

/// _NoDownloads fails every download, counting them.
class _NoDownloads extends StockClient {
  int tries = 0;
  @override
  Future<bool> download(String url, File to,
      {required int maxBytes,
      required bool allowFetching,
      required bool proxied}) async {
    tries++;
    return false;
  }
}

Future<void> _show(WidgetTester tester,
    {required bool gpu,
    void Function(CharacterDesign?, CharacterPerformance?)? onDone,
    CharacterPerformance? performance,
    CharacterDesign? design,
    double scale = 1}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
    create: (_) => ThemeNotifier(doLoad: false),
    child: MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(
          size: const Size(1280, 800), textScaler: TextScaler.linear(scale)),
      child: CharacterStudio3D(
          onDone: onDone ?? (_, __) {},
          design: design,
          performance: performance,
          gpuReady: Future.value(gpu)),
    )),
  ));
  await _settle(tester);
}

/// _settle lets real file reads finish, then draws what they changed: until
/// nothing is loading, or a second has gone.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    final busy = find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
        find
            .byKey(const ValueKey('characterBaseProgress'))
            .evaluate()
            .isNotEmpty;
    if (!busy) return;
  }
}

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('canvas_character_base');
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
  });
  tearDown(() {
    CanvasStorage.rootOverride = null;
    StockClient.instance = StockClient();
    proxiedForTest = null;
    root.deleteSync(recursive: true);
  });

  testWidgets('without Flutter GPU it says so, and offers no download',
      (tester) async {
    await _show(tester, gpu: false);
    expect(find.byKey(const ValueKey('characterBaseNoGpu')), findsOneWidget);
    expect(find.byKey(const ValueKey('characterBaseFetch')), findsNothing);
  });

  testWidgets('with the bodies still to fetch it offers them, and their size',
      (tester) async {
    await _show(tester, gpu: true);
    expect(find.byKey(const ValueKey('characterBaseDownload')), findsOneWidget);
    expect(find.textContaining('66 MB'), findsOneWidget);
    expect(find.byKey(const ValueKey('characterBaseFetch')), findsOneWidget);
  });

  testWidgets('fetching through a proxy is refused, and can be tried again',
      (tester) async {
    final client = _NoDownloads();
    StockClient.instance = client;
    proxiedForTest = true;
    await _show(tester, gpu: true);
    await tester.tap(find.byKey(const ValueKey('characterBaseFetch')));
    await _settle(tester);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('characterBaseError')))
            .data,
        contains('proxy'));
    expect(client.tries, 0, reason: 'nothing is fetched through a proxy');
    expect(
        tester
            .widget<StudioPill>(
                find.byKey(const ValueKey('characterBaseFetch')))
            .label,
        'Try again');
  });

  testWidgets('a failed fetch says which character', (tester) async {
    final client = _NoDownloads();
    StockClient.instance = client;
    proxiedForTest = false;
    await _show(tester, gpu: true);
    await tester.tap(find.byKey(const ValueKey('characterBaseFetch')));
    await _settle(tester);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('characterBaseError')))
            .data,
        contains('Vivi'));
    expect(client.tries, 3, reason: 'tried three times');
  });

  testWidgets(
      'the steps, the parts and their settings are there from the start',
      (tester) async {
    var done = 0;
    await _show(tester, gpu: false, onDone: (_, __) => done++);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('studioStep-$i')), findsOneWidget);
    }
    // Start from is open first, with the bodies to pick.
    expect(find.byKey(const ValueKey('studioPill-body-Vivi')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shapePart-eyes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shape-eyes.size')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studioPill-shapes.eyes-Big')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shapeChanged-eyes')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studioStartAgain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shapeChanged-eyes')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('studioDone')));
    expect(done, 1);
  });

  testWidgets('at every text size, the page fits', (tester) async {
    for (final scale in const [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
      await _show(tester, gpu: false, scale: scale);
      for (final part in [
        'start',
        'muscles',
        'wear-top',
        'style',
        'decals',
        'touchup'
      ]) {
        final tree = find.descendant(
            of: find.byType(CharacterShapeList),
            matching: find.byType(Scrollable));
        await tester.drag(tree, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
            find.byKey(ValueKey('shapePart-$part')), 80,
            scrollable: find.descendant(
                of: find.byType(CharacterShapeList),
                matching: find.byType(Scrollable)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('shapePart-$part')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$part at ${scale}x');
      }
    }
  });

  testWidgets(
      'Done keeps a changed character in the library, named, and it opens again',
      (tester) async {
    var done = 0;
    await _show(tester, gpu: false, onDone: (_, __) => done++);
    // Nothing changed: nothing kept.
    await tester.tap(find.byKey(const ValueKey('studioDone')));
    await _settle(tester);
    expect(done, 1);
    expect(await tester.runAsync(CharacterDesigns.list), isEmpty);
    await tester.enterText(find.byKey(const ValueKey('studioName')), 'Jess');
    await tester.tap(find.byKey(const ValueKey('shapePart-eyes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studioPill-shapes.eyes-Big')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studioDone')));
    // Kept before going back: wait for the going back.
    for (var k = 0; k < 100 && done < 2; k++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(done, 2);
    final kept = (await tester.runAsync(CharacterDesigns.list))!;
    expect((
      kept.single.name,
      kept.single.body,
      kept.single.shape.choice('shapes.eyes')
    ), (
      'Jess',
      'Vivi',
      'Big'
    ));
    // Opened again from Start from, as it was.
    await tester.tap(find.byKey(const ValueKey('studioStartAgain')));
    await tester.tap(find.byKey(const ValueKey('shapePart-start')));
    await _settle(tester);
    final pill = find.byKey(ValueKey('studioPill-design-${kept.single.id}'));
    for (var k = 0; k < 100 && pill.evaluate().isEmpty; k++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('studioName')))
            .controller!
            .text,
        'Jess');
    expect(find.byKey(const ValueKey('shapeChanged-eyes')), findsOneWidget);
  });

  testWidgets('the Face step opens its own parts, and its face is kept',
      (tester) async {
    CharacterDesign? kept;
    await _show(tester, gpu: false, onDone: (d, _) => kept = d);
    expect(find.byKey(const ValueKey('facePart-expressions')), findsNothing);
    // A part changed is put back by its mark.
    await tester.tap(find.byKey(const ValueKey('shapePart-eyes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studioPill-shapes.eyes-Big')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shapeChanged-eyes')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shapeChanged-eyes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shapeChanged-eyes')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('studioStep-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('facePart-expressions')), findsOneWidget);
    expect(find.byKey(const ValueKey('shapePart-eyes')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('studioPill-face-expr-Sad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studioDone')));
    for (var k = 0; k < 100 && kept == null; k++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(kept?.face.name, 'Sad');
    expect(kept?.face.mix, faceExpressions['Sad']);
    // Play and Stop, in the top bar for every step.
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studioPlay')));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    // The Move step: its own parts, and a stance kept with the character.
    await tester.tap(find.byKey(const ValueKey('studioStep-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('movePart-stance')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studioPill-move-stance-Hero')));
    await tester.pumpAndSettle();
    kept = null;
    await tester.tap(find.byKey(const ValueKey('studioDone')));
    for (var k = 0; k < 100 && kept == null; k++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(kept?.move.stance, 'Hero');
    expect(kept?.face.name, 'Sad', reason: 'the face kept as well');
    // And back to the Character base.
    await tester.tap(find.byKey(const ValueKey('studioStep-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shapePart-eyes')), findsOneWidget);
  });

  testWidgets(
      'the Test step tries a scene on a timeline, kept for the character it '
      'was opened for', (tester) async {
    CanvasSection.openAll = true;
    addTearDown(() => CanvasSection.openAll = false);
    CharacterPerformance? performed;
    var done = 0;
    await _show(tester,
        gpu: false,
        design: CharacterDesign(
            id: 'd1', name: 'Jess', body: 'Vivi', updated: DateTime(2026)),
        performance: const CharacterPerformance(stance: 'Hero'),
        onDone: (_, p) {
      performed = p;
      done++;
    });
    await tester.tap(find.byKey(const ValueKey('studioStep-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('studioTestNotes')), findsOneWidget);
    expect(find.byKey(const ValueKey('studioTestTimeline')), findsOneWidget);
    // The canvas's settings, without the way to the Studio or the box.
    expect(find.byKey(const ValueKey('character3dEdit')), findsNothing);
    expect(find.byKey(const ValueKey('character3dFraming')), findsNothing);
    expect(
        tester
            .widget<CanvasDropdown<String>>(
                find.byKey(const ValueKey('character3dStance')))
            .value,
        'Hero');
    // The timeline clicked halfway: the playhead there, and a motion added
    // at it.
    final line = find.byKey(const ValueKey('studioTestTimeline'));
    final box = tester.getRect(line);
    await tester
        .tapAt(Offset(box.left + 104 + (box.width - 116) / 2, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('5.0 / 10 s'), findsOneWidget);
    tester
        .widget<CanvasDropdown<String>>(
            find.byKey(const ValueKey('character3dMotionAdd')))
        .onChanged('Wave:0');
    await tester.pumpAndSettle();
    // Play and Stop play the scene here.
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studioPlay')));
    await tester.pumpAndSettle();
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studioDone')));
    for (var k = 0; k < 100 && done == 0; k++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(performed?.stance, 'Hero');
    expect(performed?.clips.single, const MotionClip3d(kind: 'Wave', start: 5));
  });

  testWidgets('opened for no character, the Test step keeps nothing',
      (tester) async {
    CanvasSection.openAll = true;
    addTearDown(() => CanvasSection.openAll = false);
    CharacterPerformance? performed;
    var done = 0;
    await _show(tester, gpu: false, onDone: (_, p) {
      performed = p;
      done++;
    });
    await tester.tap(find.byKey(const ValueKey('studioStep-3')));
    await tester.pumpAndSettle();
    tester
        .widget<CanvasDropdown<String>>(
            find.byKey(const ValueKey('character3dMotionAdd')))
        .onChanged('Nod:0');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studioDone')));
    await _settle(tester);
    expect((done, performed), (1, null));
  });

  testWidgets('at every text size, the Test step fits', (tester) async {
    // Every section open: the most there is to fit, and none remembered.
    CanvasSection.openAll = true;
    addTearDown(() => CanvasSection.openAll = false);
    for (final scale in const [0.65, 1.0, 1.25, 1.5]) {
      await _show(tester,
          gpu: false,
          scale: scale,
          performance: const CharacterPerformance(
              keys: [PoseKey(t: 1, stance: 'Shy')],
              clips: [MotionClip3d(kind: 'Walk', start: 0, dir: 1)]));
      await tester.tap(find.byKey(const ValueKey('studioStep-3')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${scale}x');
    }
  });

  test('a character is kept and read back the same', () {
    final d = CharacterDesign(
      id: 'abc',
      name: 'Jess',
      body: 'Vita',
      shape: const CharacterShape()
          .withValue('nose.size', 0.4)
          .withColour('colour.hair', 0xa01a52),
      outfit: CharacterOutfit.asDesigned.casual(male: false),
      lookName: 'Comic',
      look: characterLooks['Comic']!.withNumber('width', 0.3),
      decals: const [
        CharacterDecal(id: 'd', source: 'picture:rose.png'),
        CharacterDecal(id: 'e', source: 'vector:star.svg')
      ],
      updated: DateTime.utc(2026, 11, 3),
    );
    final back = CharacterDesign.fromJson(jsonDecode(jsonEncode(d.toJson())))!;
    expect((
      back.name,
      back.body,
      back.shape,
      back.outfit,
      back.lookName,
      back.look,
      back.updated
    ), (
      d.name,
      d.body,
      d.shape,
      d.outfit,
      d.lookName,
      d.look,
      d.updated
    ));
    expect(back.decals, d.decals);
    expect(back.pictureIds, {'rose.png'});
    expect(back.vectorIds, {'star.svg'});
    expect(CharacterDesign.fromJson({'id': 'x'}), isNull);
  });
}
