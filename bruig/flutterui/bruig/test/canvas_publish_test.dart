import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
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

  /// pick chooses [option] from the dropdown that is currently showing
  /// [showing]. Both are dropdowns now rather than rows of radio buttons, so
  /// the option has to be opened before it can be tapped.
  /// pick chooses [option] from the dropdown of type [T].
  ///
  /// Found by its type rather than by the text it is showing: a document with
  /// frames opens the sheet on Animation rather than Image, so what the
  /// button says depends on the fixture.
  Future<void> pick<T>(WidgetTester tester, String option) async {
    await tester.tap(find.byType(DropdownButton<T>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  group("with no encoder on the machine", () {
    setUp(() => useFfmpegForTest(null));
    tearDown(forgetFfmpegForTest);

    testWidgets("choosing a video says why it cannot be published",
        (tester) async {
      await open(tester);
      await pick<PublishAs>(tester, "Video");

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
      await pick<PublishAs>(tester, "Video");

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
      await pick<PublishAs>(tester, "Video");

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
      await pick<PublishAs>(tester, "Video");
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
      var one = estimateBytes(canvas.copyWith(frames: 1),
          const CanvasEstimate(format: EstimateAs.gif));
      var many = estimateBytes(canvas.copyWith(frames: 48),
          const CanvasEstimate(format: EstimateAs.gif));

      // More frames is more bytes, and a good deal more -- but not forty-
      // eight times more: a GIF's frames carry only the rectangle that
      // changed, so the first one is most of a mostly still animation. That
      // is why this is measured against a one-frame GIF rather than against
      // the still, whose weight the coefficient no longer tracks.
      expect(many, greaterThan(one * 4));
      expect(many, lessThan(one * 48));
      expect(still, greaterThan(0));

      // A video stores what changed rather than each frame whole, which is
      // most of why anybody publishes one.
      var video = estimateBytes(canvas.copyWith(frames: 48),
          const CanvasEstimate(format: EstimateAs.video, quality: 85));
      expect(video, lessThan(many * 2),
          reason: "a video is not dearer than the GIF of the same thing");
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

  group("the export width is a resolution", () {
    // The export width and the design's own space used to be one number, and
    // that made it mean two things at once: raising it gave the design more
    // room -- every element kept its coordinates and so covered less of a
    // larger page -- while a newly added element was sized from the canvas
    // and arrived at the new scale. The same chart was two sizes on one
    // canvas depending on when it was put there.

    test("raising it does not move anything in the design", () {
      var small = const CanvasSize(ratio: CanvasRatio.wide, width: 1280);
      var large = small.copyWith(exportWidth: 3840);

      expect(large.size, small.size, reason: "the design is where it was");
      expect(large.exportSize, const Size(3840, 2160));
      expect(large.exportScale, closeTo(3, 0.001));
    });

    test("and the file is the size it says", () {
      var canvas = const CanvasDocument(
              size: CanvasSize(ratio: CanvasRatio.wide, width: 1280))
          .copyWith(
              size: const CanvasSize(ratio: CanvasRatio.wide, width: 1280)
                  .copyWith(exportWidth: 2560));

      // Four times the pixels, so about four times the bytes -- the same
      // picture, sharper, rather than a small one in the corner of a big one.
      var once = estimateBytes(
          const CanvasDocument(
              size: CanvasSize(ratio: CanvasRatio.wide, width: 1280)),
          const CanvasEstimate());
      var twice = estimateBytes(canvas, const CanvasEstimate());
      expect(twice / once, closeTo(4, 0.5));
    });

    test("a page that grows keeps the design's scale instead", () {
      // Which is what this did before there was a choice, and is right when
      // what somebody wants is a bigger sheet rather than a sharper one.
      var page = const CanvasSize(
              ratio: CanvasRatio.wide, width: 1280, scalesDesign: false)
          .copyWith(exportWidth: 2560);

      expect(page.width, 2560, reason: "the design space grew with it");
      expect(page.exportScale, 1);
      expect(page.size, const Size(2560, 1440));
    });

    test("and switching to a page snaps the two together", () {
      var scaled = const CanvasSize(ratio: CanvasRatio.wide, width: 1280)
          .copyWith(exportWidth: 3840);
      expect(scaled.width, 1280);

      var page = scaled.copyWith(scalesDesign: false);
      expect(page.width, page.exportWidth,
          reason: "in page mode the design width is the published width");
    });

    test("a canvas saved before the two were told apart is unchanged", () {
      // Every canvas already made was laid out in the space it was published
      // at, so its design width is its width and nothing has moved.
      var old = {"ratio": "wide", "width": 1920};
      var size = CanvasSize.fromJson(old);
      expect(size.exportWidth, 1920);
      expect(size.exportScale, 1);
      expect(size.scalesDesign, isTrue);

      // And a canvas that has never been given a different export width does
      // not write one down.
      expect(size.toJson().containsKey("exportWidth"), isFalse);
    });

    test("the choice and the two widths survive being saved", () {
      var size = const CanvasSize(ratio: CanvasRatio.wide, width: 1280)
          .copyWith(exportWidth: 3840);
      var back = CanvasSize.fromJson(size.toJson());
      expect(back.exportWidth, 3840);
      expect(back.width, 1280);
      expect(back.exportScale, closeTo(3, 0.001));

      var page = size.copyWith(scalesDesign: false);
      expect(CanvasSize.fromJson(page.toJson()).scalesDesign, isFalse);
    });

    test("a new element is the same size as one already there", () {
      // The whole complaint: an element added after the canvas was resized
      // arrived at a different size from the identical element added before.
      var canvas = const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.wide, width: 1280));
      var first = newElement(ElementKind.chart, canvas);

      var bigger =
          canvas.copyWith(size: canvas.size.copyWith(exportWidth: 3840));
      var second = newElement(ElementKind.chart, bigger);

      expect(second.width, first.width);
      expect(second.height, first.height);
    });
  });

  // Publishing part of a document rather than all of it. The choice is made
  // here and comes out as a shorter document -- see CanvasDocument.scenesFrom
  // and canvas_publish_scenes_test.dart, which is the arithmetic. These are
  // about the control existing, appearing when it should and saying what it
  // will do.
  group("choosing which scenes go", () {
    CanvasDocument several() {
      var document = const CanvasDocument(frames: 4);
      for (var i = 1; i < 4; i++) {
        document = document.addScene(name: "Scene ${i + 1}");
      }
      return document;
    }

    testWidgets("a document with one canvas is not asked", (tester) async {
      // Three choices that all mean the same thing is a control somebody has
      // to read before they can ignore it.
      // Headings are set in capitals, like every other one in this sheet.
      await open(tester);
      expect(find.text("Scenes"), findsNothing);
    });

    testWidgets("a still asks which canvas the picture is of", (tester) async {
      // A PNG is one picture and always will be, so the only question worth
      // asking is which one -- not the three-way choice, two of whose answers
      // it cannot honour. It used to be asked nothing and always publish the
      // first, which is the wrong end of that.
      await open(tester, document: several());
      expect(find.text("Scenes"), findsNothing);
      expect(find.text("Scene"), findsOneWidget);
      expect(find.text("Which canvas the picture is of."), findsOneWidget);
    });

    testWidgets("and a still can be told to be a later one", (tester) async {
      await open(tester, document: several());
      expect(find.byType(DropdownButton<int>), findsOneWidget,
          reason: "one dropdown: which canvas");

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      // Named scenes are listed by their number and their name, so a
      // document whose scenes are named does not make anybody count rows.
      await tester.tap(find.textContaining("Scene 3").last);
      await tester.pumpAndSettle();
      expect(find.textContaining("Scene 3"), findsOneWidget,
          reason: "and the dropdown now shows it");
    });

    testWidgets(
        "a document with several is, once it is making something "
        "that can hold them", (tester) async {
      await open(tester, document: several());
      expect(find.text("Scenes"), findsNothing);
      await pick<PublishAs>(tester, "Animation");
      expect(find.text("Scenes"), findsOneWidget);
      // The chosen one shows on the dropdown; the rest are behind it.
      expect(find.text("All scenes"), findsOneWidget);
    });

    testWidgets("all of them, until something else is chosen", (tester) async {
      await open(tester, document: several());
      await pick<PublishAs>(tester, "Animation");
      // No dropdown while it is the whole thing: there is nothing to pick.
      expect(find.text("From"), findsNothing);
      expect(find.text("Scene"), findsNothing);
    });

    testWidgets("one scene offers one dropdown", (tester) async {
      await open(tester, document: several());
      await pick<PublishAs>(tester, "Animation");
      await pick<PublishScenes>(tester, "One scene");

      expect(find.text("Scene"), findsOneWidget);
      expect(find.text("To"), findsNothing, reason: "one scene has no far end");
    });

    testWidgets("a range offers both ends", (tester) async {
      await open(tester, document: several());
      await pick<PublishAs>(tester, "Animation");
      await pick<PublishScenes>(tester, "A range");

      expect(find.text("From"), findsOneWidget);
      expect(find.text("To"), findsOneWidget);
    });

    testWidgets("and the run it reports gets shorter with it", (tester) async {
      // The line under the animation settings says how long what is about to
      // be published runs for. It has to be about the scenes chosen, or it is
      // describing a different animation from the one the button will make.
      await open(tester, document: several());
      await pick<PublishAs>(tester, "Animation");
      var whole = find.textContaining("frames at");
      expect(whole, findsOneWidget);
      var before = tester.widget<Text>(whole).data!;

      await pick<PublishScenes>(tester, "One scene");
      var after = tester.widget<Text>(find.textContaining("frames at")).data!;
      expect(after, isNot(before),
          reason: "one scene is shorter than four of them");
    });
  });
}
