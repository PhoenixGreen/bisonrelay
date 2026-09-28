import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/double_click.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_audio_fake.dart';

// canvas_assets_panel_test.dart is the Assets sidebar: its three sections, a
// click that puts an asset on the canvas the shape it is, a remove that says
// who is using it first, and a sound dragged onto the timeline -- into a
// channel, or below the channels for a new one.

const picture = "0123456789abcdef.png";
const film = "0f1e2d3c4b5a6978.mp4";
const song = "a1b2c3d4e5f60718.mp3";

void main() {
  late Directory root;

  setUp(() async {
    // The test clock is not the wall clock the second click is timed on.
    DoubleClick.window = const Duration(days: 1);
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp("canvas_assets_panel");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    var when = DateTime(2026, 9, 28);
    await CanvasLibrary.add(LibraryAsset(
        id: picture,
        kind: AssetKind.picture,
        name: "Club badge",
        added: when,
        width: 200,
        height: 100));
    await CanvasLibrary.add(LibraryAsset(
        id: film,
        kind: AssetKind.video,
        name: "Goal",
        added: when,
        width: 1920,
        height: 1080,
        length: 4));
    await CanvasLibrary.add(LibraryAsset(
        id: song, kind: AssetKind.audio, name: "Anthem", added: when));
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// idle lets the library's reads and writes -- real files -- finish.
  Future<void> idle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 4)));
      await tester.pump();
    }
  }

  Future<CanvasController> show(
      WidgetTester tester, Widget Function(CanvasController) body,
      {CanvasDocument document = const CanvasDocument(frames: 100)}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = CanvasController(document, audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: body(c))),
    ));
    await idle(tester);
    return c;
  }

  Widget sidebar(CanvasController c) =>
      SizedBox(width: 280, child: CanvasAssetsPanel(controller: c));

  testWidgets("three sections, each with what is in the library",
      (tester) async {
    await show(tester, sidebar);
    for (var label in ["PICTURES", "VIDEOS", "AUDIO"]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text("Club badge"), findsOneWidget);
    expect(find.text("Goal"), findsOneWidget);
    expect(find.text("Anthem"), findsOneWidget);
    expect(find.byKey(const ValueKey("addAsset-picture")), findsOneWidget);
  });

  // Put in one row, the three sections are tabs. Unkeyed, one section was
  // handed each tab's kind in turn and kept what it had loaded first: the
  // Audio tab showed the pictures, and Pictures showed nothing.
  testWidgets("as tabs in one row, each section shows its own", (tester) async {
    SharedPreferences.setMockInitialValues({
      "canvasAssets.order": "picture+video+audio",
      "canvasAssets.tab": "picture",
    });
    await show(tester, sidebar);
    await idle(tester);
    expect(find.text("Club badge"), findsOneWidget);
    expect(find.text("Anthem"), findsNothing);

    await tester.tap(find.text("AUDIO"));
    await idle(tester);
    expect(find.text("Anthem"), findsOneWidget);
    expect(find.text("Club badge"), findsNothing,
        reason: "the pictures stay in Pictures");

    await tester.tap(find.text("PICTURES"));
    await idle(tester);
    expect(find.text("Club badge"), findsOneWidget);
  });

  testWidgets("a click puts it on the canvas, the shape it is", (tester) async {
    var c = await show(tester, sidebar);
    await tester.tap(find.byKey(const ValueKey("asset-$picture")));
    await tester.pump();
    var image = c.document.elements.single as ImageElement;
    expect(image.assetId, picture);
    expect(image.name, "Club badge");
    expect(image.width / image.height, closeTo(2, 0.01));

    await tester.tap(find.byKey(const ValueKey("asset-$film")));
    await tester.pump();
    var video = c.document.elements.last as VideoElement;
    expect(video.clip.playlist.single.assetId, film);
    expect(video.width / video.height, closeTo(16 / 9, 0.01));
  });

  testWidgets("removing asks first, naming the canvases that use it",
      (tester) async {
    await tester.runAsync(() => CanvasStorage.save(
        "",
        "Match day",
        CanvasDocument(elements: [
          elementForAsset(
              LibraryAsset(
                  id: song,
                  kind: AssetKind.audio,
                  name: "Anthem",
                  added: DateTime(2026)),
              const CanvasDocument()),
        ])));
    await show(tester, sidebar);
    var row = find.text("Anthem");
    var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(row));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("removeAsset-$song")));
    await idle(tester);
    expect(find.textContaining("“Match day”"), findsOneWidget);
    await tester.tap(find.text("Remove"));
    // Reading the list, writing it back, deleting the file and reading the
    // list again: a real file operation a frame, several times over. Asking
    // the library directly here would wait behind that on the test's clock.
    for (var i = 0; i < 4; i++) {
      await idle(tester);
    }
    expect(find.text("Anthem"), findsNothing);
    expect(find.text("Club badge"), findsOneWidget,
        reason: "only the one that was removed");
  });

  // A sound carried from the sidebar onto the timeline: into the empty
  // channel it is dropped on, and below the channels, a channel of its own.
  testWidgets("a sound dropped on the timeline fills a channel or makes one",
      (tester) async {
    var c = await show(
        tester,
        (c) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              sidebar(c),
              Expanded(
                child:
                    CanvasTimeline(controller: c, height: timelineHeight + 120),
              ),
            ]));
    c.addElement(audioChannel(c.document, 0), select: false);
    await tester.pumpAndSettle();
    var channel = c.document.elements.single as AudioElement;
    var lane = find.byKey(ValueKey("lane-${channel.id}"));
    expect(lane, findsOneWidget);

    Future<void> carry(Offset to) async {
      var drag =
          await tester.startGesture(tester.getCenter(find.text("Anthem")));
      await tester.pump(const Duration(milliseconds: 50));
      await drag.moveBy(const Offset(20, 0));
      await tester.pump();
      await drag.moveTo(to);
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
    }

    await carry(tester.getCenter(lane));
    var filled = c.document.elements.single as AudioElement;
    expect(filled.clip.playlist.single.assetId, song,
        reason: "the empty channel took the sound");

    // Below the lanes, three quarters of the way along: a new channel,
    // starting at the frame it was dropped on.
    var box = tester.getRect(lane);
    await carry(Offset(box.left + box.width * 0.75, box.bottom + 40));
    var channels = c.document.elements.whereType<AudioElement>().toList();
    expect(channels, hasLength(2));
    var made = channels.last;
    expect(made.visible, isFalse);
    expect(made.clip.timed, isTrue);
    expect(made.name, "Anthem");
    expect(made.clip.at, closeTo(75, 3));
  });

  test("a sound becomes a speaker; a clip keeps what the asset knows", () {
    var e = elementForAsset(
        LibraryAsset(
            id: film,
            kind: AssetKind.video,
            name: "Goal",
            added: DateTime(2026),
            poster: "p.png",
            sound: "s.flac",
            length: 4,
            fps: 25),
        const CanvasDocument()) as VideoElement;
    var s = e.clip.playlist.single;
    expect(
        [s.posterId, s.soundId, s.length, s.fps], ["p.png", "s.flac", 4, 25]);
    var a = elementForAsset(
        LibraryAsset(
            id: song,
            kind: AssetKind.audio,
            name: "Anthem",
            added: DateTime(2026)),
        const CanvasDocument()) as AudioElement;
    expect(a.visible, isTrue);
    expect(a.clip.timed, isFalse);
    expect(a.clip, isA<MediaClip>());
  });

  // A double-click on a name renames the asset, and a click on a name never
  // puts it on the canvas -- else renaming would add it twice first.
  testWidgets("a double-clicked name is renamed in place", (tester) async {
    var c = await show(tester, sidebar);
    var name = find.byKey(const ValueKey("assetName-$picture"));
    await tester.tap(name);
    await tester.tap(name);
    await tester.pumpAndSettle();
    expect(c.document.elements, isEmpty, reason: "the name is not a button");
    var field = find.byKey(const ValueKey("assetRename-$picture"));
    expect(field, findsOneWidget);
    await tester.enterText(field, "  Crest  ");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 3; i++) {
      await idle(tester);
    }
    expect(find.text("Crest"), findsOneWidget);
    expect(find.text("Club badge"), findsNothing);
    expect(c.document.elements, isEmpty);
  });

  // A name shorter than its tile: the rest of the line is still the name's,
  // so a double-click just past the end of the word renames rather than adds.
  testWidgets("past the end of a short name is still the name", (tester) async {
    var c = await show(tester, sidebar);
    var line =
        tester.getRect(find.byKey(const ValueKey("assetNameLine-$film")));
    expect(line.width, 96, reason: "as wide as the tile, not the word");
    var past = Offset(line.right - 6, line.center.dy);
    await tester.tapAt(past);
    await tester.pump();
    // The second click as a hand makes it: frames drawn while the button is
    // down. Opening the field then took the name out from under the press,
    // and letting go was a click on the tile -- which used the asset.
    var press = await tester.startGesture(past);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await press.up();
    await tester.pump();
    await tester.pump();
    expect(c.document.elements, isEmpty);
    expect(find.byKey(const ValueKey("assetRename-$film")), findsOneWidget);
  });

  testWidgets("icons or a list, each section its own, and remembered",
      (tester) async {
    await show(tester, sidebar);
    Finder still(String id) => find.descendant(
        of: find.byKey(ValueKey("asset-$id")),
        matching: find.byType(AssetThumb));
    // Pictures start as icons: a 96-wide picture above the name.
    expect(tester.getSize(still(picture)).width, 96);
    await tester.tap(find.byKey(const ValueKey("assetList-picture")));
    await idle(tester);
    var small = tester.getRect(still(picture));
    expect(small.width, lessThan(50));
    expect(small.right,
        lessThanOrEqualTo(tester.getRect(find.text("Club badge")).left),
        reason: "the picture sits left of the name");
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString("canvasAssets.view.picture"), "list");
    expect(prefs.getString("canvasAssets.view.video"), isNull);

    // Shown again, it is still a list.
    await tester.pumpWidget(const SizedBox());
    await show(tester, sidebar);
    expect(tester.getSize(still(picture)).width, lessThan(50));
  });
}
