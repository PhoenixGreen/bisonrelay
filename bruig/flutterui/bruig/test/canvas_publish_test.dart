import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
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

  testWidgets("a PDF asks what size of paper, and the others do not",
      (tester) async {
    // The page is the one question a PDF raises that a picture does not: a
    // canvas has a size in pixels and a sheet has one in inches, and nothing
    // about the canvas answers which sheet it belongs on.
    // A still canvas, so the sheet opens on Image -- an animated one opens on
    // Animation, which is its own small piece of behaviour and not this one.
    await open(tester, document: const CanvasDocument(frames: 1));
    expect(find.text("Page"), findsNothing);

    await tester.tap(find.text("PNG (lossless)"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("PDF (a page)").last);
    await tester.pumpAndSettle();

    expect(find.text("Page"), findsOneWidget);
    expect(find.textContaining("inches"), findsOneWidget,
        reason: "a 1280-pixel canvas is a thirteen-inch page, which surprises "
            "people");
    // The JPEG quality slider belongs to a JPEG and nothing else.
    expect(find.text("Quality"), findsNothing);
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

  group("what the estimate is for", () {
    // An estimate that does not name a format is not an estimate of
    // anything: the same canvas is four hundred kilobytes as a PNG and forty
    // as a JPEG, and which of those matters depends on what somebody is about
    // to do with it.

    var canvas = const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.wide, width: 1920));

    test("a lossy file is smaller than a lossless one", () {
      var png =
          estimateBytes(canvas, const CanvasEstimate(format: EstimateAs.png));
      var jpeg = estimateBytes(
          canvas, const CanvasEstimate(format: EstimateAs.jpeg, quality: 85));
      var webp = estimateBytes(
          canvas, const CanvasEstimate(format: EstimateAs.webp, quality: 85));

      expect(jpeg, lessThan(png));
      expect(webp, lessThan(jpeg), reason: "which is what WebP is for");
    });

    test("and quality costs what quality costs", () {
      int at(int quality) => estimateBytes(
          canvas, CanvasEstimate(format: EstimateAs.jpeg, quality: quality));

      expect(at(100), greaterThan(at(85)));
      expect(at(85), greaterThan(at(50)));
      expect(at(50), greaterThan(at(20)));
      // The curve, not a straight line: the top of the range costs a great
      // deal and shows almost nothing, and the bottom saves very little more.
      expect(at(100) - at(85), greaterThan(at(50) - at(35)));
    });

    test("quality does nothing to a lossless file", () {
      // PNG packs harder or less hard and never looks different, so a quality
      // setting on one would change the answer to a question nobody asked.
      expect(EstimateAs.png.lossy, isFalse);
      expect(
          estimateBytes(canvas,
              const CanvasEstimate(format: EstimateAs.png, quality: 10)),
          estimateBytes(canvas,
              const CanvasEstimate(format: EstimateAs.png, quality: 100)));
    });

    test("an animation is priced by its frames", () {
      var still = estimateBytes(canvas, const CanvasEstimate());
      var moving = estimateBytes(canvas.copyWith(frames: 48),
          const CanvasEstimate(format: EstimateAs.gif));
      expect(moving, greaterThan(still * 5));

      // A video stores what changed rather than each frame whole, which is
      // most of why anybody publishes one.
      var video = estimateBytes(canvas.copyWith(frames: 48),
          const CanvasEstimate(format: EstimateAs.video, quality: 85));
      expect(video, lessThan(moving));
    });

    test("which formats suit what", () {
      expect(EstimateAs.gif.moving, isTrue);
      expect(EstimateAs.video.moving, isTrue);
      for (var format in [EstimateAs.png, EstimateAs.jpeg, EstimateAs.webp]) {
        expect(format.moving, isFalse, reason: format.name);
      }
    });

    test("the choice is saved with the canvas", () {
      var document = canvas.copyWith(
          estimate: const CanvasEstimate(format: EstimateAs.jpeg, quality: 60));
      var back = CanvasDocument.fromJson(document.toJson());
      expect(back.estimate.format, EstimateAs.jpeg);
      expect(back.estimate.quality, 60);

      // And a canvas saved before there was a choice is a PNG, which is what
      // it was being estimated as.
      expect(CanvasDocument.fromJson(canvas.toJson()).estimate.format,
          EstimateAs.png);
    });
  });

  group("a named size names a shape as well as a width", () {
    test("every preset is the size its name claims", () {
      // 1080p is 1920 by 1080 and nothing else. The arithmetic is the
      // canvas's own, so a preset whose width does not come out at the name's
      // height is a preset in the wrong list.
      var known = {
        ("1080p", CanvasRatio.wide): (1920, 1080),
        ("720p", CanvasRatio.wide): (1280, 720),
        ("4K", CanvasRatio.wide): (3840, 2160),
        ("Square post", CanvasRatio.square): (1080, 1080),
      };
      for (var preset in canvasSizePresets) {
        var wanted = known[(preset.label, preset.ratio)];
        if (wanted == null) continue;
        expect([preset.width, preset.height], [wanted.$1, wanted.$2],
            reason: preset.label);
      }
    });

    test("A4 at 150dpi is a sheet of A4", () {
      var a4 = canvasSizePresets.firstWhere(
          (p) => p.ratio == CanvasRatio.a4 && p.label == "A4 at 150dpi");
      // 210mm by 297mm at 150 dots to the inch.
      expect(a4.width, closeTo(210 / 25.4 * 150, 12));
      expect(a4.height, closeTo(297 / 25.4 * 150, 16));
    });

    test("and turning the paper turns the size", () {
      var portrait = canvasSizePresets.firstWhere(
          (p) => p.ratio == CanvasRatio.a4 && p.label == "A4 at 150dpi");
      var landscape = canvasSizePresets.firstWhere(
          (p) => p.ratio == CanvasRatio.a4Wide && p.label == "A4 at 150dpi");
      expect(landscape.width, portrait.height,
          reason: "the long edge is the width now");
      expect(landscape.height, closeTo(portrait.width, 2));
    });

    test("every preset fits inside what a canvas may be", () {
      for (var preset in canvasSizePresets) {
        expect(preset.width, lessThanOrEqualTo(maxCanvasWidth),
            reason: preset.label);
        expect(preset.width, greaterThanOrEqualTo(minCanvasWidth));
      }
    });

    test("a shape people have no word for has no list", () {
      expect(sizePresetsFor(CanvasRatio.custom), isEmpty);
      expect(sizePresetsFor(CanvasRatio.wide), isNotEmpty);
      // And every preset in a list really belongs to that shape.
      for (var ratio in CanvasRatio.values) {
        for (var preset in sizePresetsFor(ratio)) {
          expect(preset.ratio, ratio);
        }
      }
    });
  });
}
