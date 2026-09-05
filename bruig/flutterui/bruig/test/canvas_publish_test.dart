import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/ui/publish_sheet.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_publish_test.dart is about the publish sheet saying what it means.
//
// The sheet's whole job is telling somebody what they are about to get before
// a slow render rather than after it, so a message it draws and cannot be read
// is worse than one it never draws: the Publish button goes dead and nothing
// explains why. That is exactly what happened -- the warning was drawn in
// colorScheme.tertiary, which in this app is the *background* of a settings
// panel and is near-black in the dark theme.

void main() {
  Future<void> open(WidgetTester tester,
      {CanvasDocument document = const CanvasDocument(frames: 12)}) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPublishSheet(context,
                  document: document, images: null, frame: 0, name: "Plan"),
              child: const Text("open"),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
  }

  group("with no encoder on the machine", () {
    setUp(() => useFfmpegForTest(null));
    tearDown(forgetFfmpegForTest);

    testWidgets("choosing a video says why it cannot be published",
        (tester) async {
      await open(tester);
      await tester.tap(find.text("Video"));
      await tester.pumpAndSettle();

      var warning = find.textContaining("needs ffmpeg");
      expect(warning, findsOneWidget);

      // Readable, which is the whole point of the message. Checked against the
      // surface it is drawn on rather than against a particular colour, so
      // this goes on meaning something whatever palette the reader has.
      // listen: false -- this is a look, not a build, and Provider refuses to
      // register a dependency outside one.
      var theme = ThemeNotifier.of(tester.element(find.byType(AlertDialog)),
          listen: false);
      var style = tester.widget<Text>(warning).style!;
      expect(style.color, isNot(theme.colors.surface));
      expect(style.color, isNot(theme.colors.tertiary),
          reason: "tertiary is a panel background in this app, not an accent");
      expect(style.color, theme.colors.onSurface);
    });

    testWidgets("and the button is dead rather than failing later",
        (tester) async {
      await open(tester);
      await tester.tap(find.text("Video"));
      await tester.pumpAndSettle();

      var publish = tester.widget<FilledButton>(find.ancestor(
          of: find.text("Publish"), matching: find.byType(FilledButton)));
      expect(publish.onPressed, isNull);
    });

    testWidgets("the other kinds are unaffected", (tester) async {
      await open(tester);
      expect(find.textContaining("needs ffmpeg"), findsNothing,
          reason: "an image has nothing to do with a video encoder");

      var publish = tester.widget<FilledButton>(find.ancestor(
          of: find.text("Publish"), matching: find.byType(FilledButton)));
      expect(publish.onPressed, isNotNull);
    });
  });

  group("with an encoder on the machine", () {
    setUp(() => useFfmpegForTest("/somewhere/ffmpeg"));
    tearDown(forgetFfmpegForTest);

    testWidgets("a video can be published like anything else", (tester) async {
      await open(tester);
      await tester.tap(find.text("Video"));
      await tester.pumpAndSettle();

      expect(find.textContaining("needs ffmpeg"), findsNothing);
      var publish = tester.widget<FilledButton>(find.ancestor(
          of: find.text("Publish"), matching: find.byType(FilledButton)));
      expect(publish.onPressed, isNotNull);
    });

    testWidgets("the format says where its file will and will not play",
        (tester) async {
      // The two differ in exactly the way somebody about to send a clip cares
      // about, and there is no way to find that out from the file afterwards.
      await open(tester);
      await tester.tap(find.text("Video"));
      await tester.pumpAndSettle();
      expect(find.textContaining(VideoFormat.mp4.note), findsOneWidget);

      await tester.tap(find.text("MP4"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("WebM").last);
      await tester.pumpAndSettle();

      expect(find.textContaining(VideoFormat.webm.note), findsOneWidget);
      expect(find.textContaining(VideoFormat.mp4.note), findsNothing);
    });
  });
}
