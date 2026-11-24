import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';

import 'support/canvas_app.dart';

// canvas_recent_pictures_test.dart is the "use one already added" dialog: it
// offers what the Library lists, by name, and not every file in the stores,
// which also hold a video's poster frame and the pictures that came inside a
// canvas somebody shared.

/// Two single pixels as PNGs, one clear and one red: two different files.
final _clear = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==");
final _red = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==");

List<int> _drawing(String fill) =>
    utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect width="10" height="10" fill="$fill"/></svg>');

void main() {
  late Directory root;
  late String listed, stray, listedDrawing, strayDrawing;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp("canvas_recent_pictures");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    AssetThumb.forgetForTest();
    listed = (await CanvasAssets.save(_clear))!;
    await CanvasLibrary.add(LibraryAsset(
        id: listed,
        kind: AssetKind.picture,
        name: "Club badge",
        added: DateTime(2026, 11, 20)));
    listedDrawing = (await CanvasMedia.saveVector(_drawing("red")))!;
    await CanvasLibrary.addVector(listedDrawing, "Logo");
    // Stored once the library is written, so they are files in the stores
    // that the library does not list.
    stray = (await CanvasAssets.save(_red))!;
    strayDrawing = (await CanvasMedia.saveVector(_drawing("blue")))!;
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// idle lets the library's reads -- real files -- finish.
  Future<void> idle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 4)));
      await tester.pump();
    }
  }

  /// open shows the dialog, asking for drawings or pictures, and returns
  /// what it will answer with.
  Future<Future<String?>> open(WidgetTester tester,
      {bool drawings = false, bool both = false}) async {
    setTestScreen(tester, const Size(1000, 800));
    late BuildContext context;
    await tester.pumpWidget(canvasApp(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    var chosen = showRecentPictures(context, drawings: drawings, both: both);
    await idle(tester);
    return chosen;
  }

  testWidgets("pictures: what the library lists, by name, and no other file",
      (tester) async {
    var chosen = await open(tester);
    expect(find.byKey(ValueKey(listed)), findsOneWidget);
    expect(find.byKey(ValueKey(stray)), findsNothing,
        reason: "a file in the store that is not in the library");
    expect(find.text("Club badge"), findsOneWidget);
    // Drawings are asked for on their own.
    expect(find.byKey(ValueKey(listedDrawing)), findsNothing);

    await tester.tap(find.byKey(ValueKey(listed)));
    await idle(tester);
    expect(await chosen, listed);
  });

  testWidgets("drawings: the library's drawings, and no other file",
      (tester) async {
    var chosen = await open(tester, drawings: true);
    expect(find.byKey(ValueKey(listedDrawing)), findsOneWidget);
    expect(find.byKey(ValueKey(strayDrawing)), findsNothing);
    expect(find.text("Logo"), findsOneWidget);
    expect(find.byKey(ValueKey(listed)), findsNothing);

    await tester.tap(find.byKey(ValueKey(listedDrawing)));
    await idle(tester);
    expect(await chosen, listedDrawing);
  });

  testWidgets("both: pictures first, the vectors a switch away",
      (tester) async {
    // Ken, 2026-11-24: a text's picture piece draws a vector as well as a
    // picture, but only the pictures were offered.
    var chosen = await open(tester, both: true);
    expect(find.byKey(ValueKey(listed)), findsOneWidget);
    expect(find.byKey(ValueKey(listedDrawing)), findsNothing);
    await tester.tap(find.text("Vectors"));
    await idle(tester);
    expect(find.byKey(ValueKey(listedDrawing)), findsOneWidget);
    expect(find.byKey(ValueKey(strayDrawing)), findsNothing);
    expect(find.byKey(ValueKey(listed)), findsNothing);

    await tester.tap(find.byKey(ValueKey(listedDrawing)));
    await idle(tester);
    expect(await chosen, listedDrawing);
  });

  testWidgets("an empty library says so", (tester) async {
    await tester.runAsync(() async {
      await CanvasLibrary.unlist(listed);
      await CanvasLibrary.unlist(listedDrawing);
    });
    await open(tester);
    expect(find.textContaining("No pictures yet"), findsOneWidget);
  });
}
