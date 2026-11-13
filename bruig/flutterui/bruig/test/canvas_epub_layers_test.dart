import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/export/epub_media.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_arrival_fixture.dart';
import 'package:path/path.dart' as path;
// ignore: depend_on_referenced_packages
import 'package:xml/xml.dart';
import 'package:bruig/plugin_system/canvas/model/motion_convert.dart';

// canvas_epub_layers_test.dart is a page of an interactive EPUB laid out as
// its elements, each animated by the reader: that nothing is a film of the
// page or a run of pictures, that an element's own motion becomes CSS
// keyframes that put it back where the canvas draws it at every frame, that
// what CSS cannot do is a video of that element alone, and -- run under node
// against a stand-in for the page -- that the page's clock plays them as the
// canvas would.

Map<String, Uint8List> files(Uint8List bytes) => {
      for (var f in ZipDecoder().decodeBytes(bytes).files)
        if (f.isFile) f.name: Uint8List.fromList(f.content),
    };

XmlDocument pageOf(Uint8List book, int index) =>
    XmlDocument.parse(utf8.decode(files(book)["OEBPS/page$index.xhtml"]!));

XmlElement? byId(XmlDocument page, String id) {
  for (var e in page.descendantElements) {
    if (e.getAttribute("id") == id) return e;
  }
  return null;
}

/// parts are a layer's pictures, each in the frame that clips it.
List<XmlElement> parts(XmlElement layer) => [
      for (var e in layer.childElements)
        if (e.getAttribute("class") == "cw") e,
    ];

List<Map<String, dynamic>> keyframes(XmlElement e) {
  var kf = e.getAttribute("data-kf");
  if (kf == null) return const [];
  return (jsonDecode(kf) as List).cast<Map<String, dynamic>>();
}

ButtonElement button(String id, double x, ButtonAction action,
        {ElementTrack? track}) =>
    ButtonElement(
        ElementBase(id: id, x: x, y: 150, width: 50, height: 20, track: track),
        action: action);

/// sliding is a dot that crosses 200 units over a page of twelve frames.
ShapeElement sliding() => ShapeElement(
    ElementBase(
        id: "dot",
        x: 10,
        y: 10,
        width: 40,
        height: 40,
        track: ElementTrack(const [
          Keyframe(frame: 0),
          Keyframe(frame: 11, dx: 200),
        ])),
    fill: const Color(0xFFFF0000));

/// arriving is a keyframed arrival over frames [from] to [to].
ElementTrack arriving(int from, int to) => ElementTrack([
      Keyframe(frame: from, values: const {KeyframeChannel.reveal: 0}),
      Keyframe(frame: to, values: const {KeyframeChannel.reveal: 1}),
    ]);

CanvasDocument book(List<CanvasElement> elements,
        {List<TimelineAction> marks = const [],
        CanvasBackground? background}) =>
    CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
      frameRate: 12,
      scenes: [
        CanvasScene(
            id: "one",
            frames: 12,
            actions: marks,
            elements: elements,
            background: background),
        const CanvasScene(id: "two"),
      ],
    );

Future<Uint8List> publish(WidgetTester tester, CanvasDocument doc) async {
  Uint8List? bytes;
  await tester.runAsync(() async {
    bytes = (await renderDocument(doc, as: DocumentAs.interactiveEpub))!.data;
  });
  return bytes!;
}

/// cssAt is what [keys] say at [frame]: every frame where anything changes
/// is a key, so between two it holds.
Map<String, String> cssAt(List<EpubKey> keys, int frame) {
  var at = keys.first.css;
  for (var k in keys) {
    if (k.frame <= frame) at = k.css;
  }
  return at;
}

List<double> numbers(String css) => [
      for (var m in RegExp(r"-?[\d.]+(?:e-?\d+)?").allMatches(css))
        double.parse(m.group(0)!),
    ];

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_epub_layers");
    CanvasStorage.rootOverride = root.path;
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets("a page that moves is its elements, animated by the reader",
      (tester) async {
    var bytes = await publish(
        tester,
        book([
          sliding(),
          button("p", 10, const ButtonAction(kind: ButtonActionKind.play)),
        ]));
    var all = files(bytes);
    expect(all.keys.where((n) => n.endsWith(".mp4")), isEmpty,
        reason: "nothing on it is a film");

    var page = pageOf(bytes, 0);
    var stage = byId(page, "stage")!;
    expect(stage.getAttribute("data-frames"), "12");
    expect(stage.getAttribute("data-rate"), "12");
    expect(stage.getAttribute("data-autoplay"), "false",
        reason: "it has a button of its own to start it");

    // One picture of the dot, and its pose as keyframes the reader plays.
    var dot = byId(page, "l-dot")!;
    expect(parts(dot), hasLength(1));
    expect(
        parts(dot)
            .single
            .descendantElements
            .where((e) => e.name.local == "img"),
        hasLength(1));
    var poses = keyframes(dot);
    expect(poses.length, greaterThan(2));
    expect(poses.first["offset"], 0);
    expect(poses.last["offset"], 1);
    var last = numbers(poses.last["transform"] as String).first;
    var pixels = last / 200;
    expect(pixels, greaterThan(0));
    var six = poses.firstWhere((k) => ((k["offset"] as num) * 11).round() == 6);
    expect(numbers(six["transform"] as String).first,
        closeTo(200 * 6 / 11 * pixels, 0.1));

    // Everything that does not move is flattened: the backdrop, and the
    // button over the dot.
    expect(
        stage.childElements.where((e) => e.getAttribute("class") == "pic slab"),
        hasLength(2));
    var opf = utf8.decode(all["OEBPS/content.opf"]!);
    for (var img
        in stage.descendantElements.where((e) => e.name.local == "img")) {
      var href = img.getAttribute("src")!;
      expect(all, contains("OEBPS/$href"));
      expect(opf, contains('href="$href"'),
          reason: "a reader opens nothing its manifest does not list");
    }

    // The play button is aimed at the page's playhead. (The start's own
    // Play, over the page until it is pressed, is the page's, not its.)
    var play = page
        .findAllElements("button")
        .where((b) => b.getAttribute("id") != "start")
        .single;
    expect(play.getAttribute("data-target"), filmTarget);
    expect(play.getAttribute("data-act"), "play");

    // The still page is still a picture.
    expect(byId(pageOf(bytes, 1), "stage"), isNull);
  });

  testWidgets("an arrival is the element's own motion, not a run of pictures",
      (tester) async {
    var wiping = ShapeElement(
      ElementBase(
          id: "w",
          x: 100,
          y: 40,
          width: 120,
          height: 80,
          track: arriving(0, 6)),
      fill: const Color(0xFF00AA00),
      animation: const ElementAnimation(preset: ElementAnimationPreset.wipe),
    );
    var popping = ShapeElement(
      ElementBase(
          id: "p", x: 20, y: 100, width: 60, height: 60, track: arriving(2, 8)),
      fill: const Color(0xFF0000AA),
      // As the editor sets it when Pop is chosen.
      animation: const ElementAnimation(
          preset: ElementAnimationPreset.pop, ease: ChartEase.overshoot),
    );
    var bytes = await publish(tester, book([wiping, popping]));
    var page = pageOf(bytes, 0);
    expect(byId(page, "stage")!.getAttribute("data-autoplay"), "true",
        reason: "nothing on it could start it otherwise");
    expect(files(bytes).keys.where((n) => n.endsWith(".mp4")), isEmpty);

    // The wipe: one picture, uncovered by a clip that grows across it.
    var wipe = parts(byId(page, "l-w")!).single;
    var clips = keyframes(wipe);
    expect(clips, isNotEmpty);
    var widths = [
      for (var k in clips)
        if (k["clipPath"] case String c when !c.contains("100000"))
          numbers(c)[2] - numbers(c)[0],
    ];
    expect(widths.length, greaterThan(3));
    for (var i = 1; i < widths.length; i++) {
      expect(widths[i], greaterThanOrEqualTo(widths[i - 1]));
    }

    // The pop: one picture, grown from small past its size and back, faded
    // in -- the preset's own overshoot, frame by frame.
    var pop = parts(byId(page, "l-p")!).single;
    var moves = keyframes(pop.childElements.single);
    var scales = [
      for (var k in moves) numbers(k["transform"] as String).first,
    ];
    expect(scales.first, 1, reason: "not there yet: hidden, not moved");
    expect(moves.first["opacity"], "0");
    expect(scales.reduce(math.max), greaterThan(1),
        reason: "it overshoots, as Pop does on the canvas");
    expect(scales.where((s) => s < 0.9), isNotEmpty, reason: "it starts small");
    expect(moves.last["opacity"], "1");
  });

  // A canvas opened in this build has clips where it had keyframes, and an
  // arrival chosen now is a clip from the start: the book moves them all
  // the same.
  testWidgets("moved and arriving by clips, it is animated just the same",
      (tester) async {
    CanvasElement clipped(CanvasElement e) => convertElement(e, 12)!;
    var wiping = arrivingOver(
        ShapeElement(
          const ElementBase(id: "w", x: 100, y: 40, width: 120, height: 80),
          fill: const Color(0xFF00AA00),
          animation:
              const ElementAnimation(preset: ElementAnimationPreset.wipe),
        ),
        from: 0,
        to: 6,
        rate: 12);
    var bytes = await publish(tester, book([clipped(sliding()), wiping]));
    var page = pageOf(bytes, 0);
    expect(keyframes(byId(page, "l-dot")!).length, greaterThan(2),
        reason: "the slide is played by the reader");
    expect(keyframes(parts(byId(page, "l-w")!).single), isNotEmpty,
        reason: "and the wipe uncovers it");
  });

  testWidgets("word by word, each word is its own picture on its own time",
      (tester) async {
    var words = TextElement(
      ElementBase(
          id: "t",
          x: 10,
          y: 10,
          width: 300,
          height: 60,
          track: arriving(0, 10)),
      text: "one two three",
      textSpec: const TextSpec(fontSize: 14),
      animation: const TextAnimation(preset: TextAnimationPreset.pop),
    );
    var bytes = await publish(tester, book([words]));
    var layer = byId(pageOf(bytes, 0), "l-t")!;
    var pieces = parts(layer);
    expect(pieces, hasLength(3), reason: "a picture a word");
    // Each starts at its own moment: the frame each is first seen differs.
    int firstSeen(XmlElement part) {
      var keys = keyframes(part.childElements.single);
      var k = keys.firstWhere((k) => k["opacity"] != "0");
      return ((k["offset"] as num) * 11).round();
    }

    var starts = pieces.map(firstSeen).toList();
    expect(starts.toSet(), hasLength(3), reason: "staggered, as on the canvas");
    expect(starts, orderedEquals([...starts]..sort()));
  });

  // Ken, 2026-11-13: the mixer's "2.00 DCR" chips, arriving word by word,
  // had their outline cut up with the words -- slices of it, popping in.
  testWidgets("a box behind words arriving one by one is a picture of its own",
      (tester) async {
    var chip = TextElement(
      ElementBase(
          id: "t",
          x: 10,
          y: 10,
          width: 200,
          height: 40,
          track: arriving(2, 10)),
      text: "two words",
      textSpec: const TextSpec(fontSize: 14),
      box: const BoxSpec(
          fill: Color(0xFF101418),
          borderWidth: 2,
          borderColor: Color(0xFFFFFFFF),
          borderRadius: 20,
          padding: 6),
      animation: const TextAnimation(preset: TextAnimationPreset.pop),
    );
    var bytes = await publish(tester, book([chip]));
    var pieces = parts(byId(pageOf(bytes, 0), "l-t")!);
    expect(pieces, hasLength(3), reason: "its box, and a picture a word");
    // The box: hidden until its arrival starts, then there whole.
    var box = pieces.first;
    var keys = keyframes(box.childElements.single);
    expect(keys.first["opacity"], "0");
    var shown = keys.firstWhere((k) => k["opacity"] == "1");
    expect(((shown["offset"] as num) * 11).round(), 2,
        reason: "from when it starts to arrive");
    // And still there at the end: a last key short of it ran back to the
    // hidden style written inline.
    expect(keys.last["offset"], 1);
    expect(keys.last["opacity"], "1");
  });

  testWidgets("a hidden element a button shows is a layer, hidden",
      (tester) async {
    var secret = ShapeElement(
        const ElementBase(
            id: "secret", x: 200, y: 20, width: 60, height: 60, visible: false),
        fill: const Color(0xFF0000FF));
    var bytes = await publish(
        tester,
        book([
          secret,
          button(
              "s",
              10,
              const ButtonAction(
                  kind: ButtonActionKind.toggleElement, elementId: "secret")),
        ]));
    var page = pageOf(bytes, 0);
    var layer = byId(page, "l-secret")!;
    expect(layer.getAttribute("style"), contains("display:none"));
    expect(byId(page, "stage")!.getAttribute("data-autoplay"), "false",
        reason: "nothing on it moves");
    var press = page.findAllElements("button").single;
    expect(press.getAttribute("data-act"), "showhide");
    expect(press.getAttribute("data-target"), "secret");
  });

  testWidgets("a button that moves takes its press with it", (tester) async {
    var bytes = await publish(
        tester,
        book([
          button(
              "next",
              10,
              const ButtonAction(
                  kind: ButtonActionKind.goToScene, elementId: "two"),
              track: ElementTrack(const [
                Keyframe(frame: 0, dx: -100),
                Keyframe(frame: 6),
              ])),
        ]));
    var page = pageOf(bytes, 0);
    var layer = byId(page, "l-next")!;
    var link = layer.findElements("a").single;
    expect(link.getAttribute("href"), "page1.xhtml");
    expect(page.findAllElements("a"), hasLength(1),
        reason: "inside the layer and nowhere else");
  });

  testWidgets("a moving background holds still, and a still page is a picture",
      (tester) async {
    var bytes = await publish(
        tester,
        book([
          BackgroundElement(
              const ElementBase(id: "bg", x: 0, y: 0, width: 320, height: 180),
              spec: const ProceduralSpec(
                  style: ProceduralStyle.rings, animated: true)),
          ShapeElement(
              const ElementBase(id: "s", x: 20, y: 20, width: 40, height: 40),
              fill: const Color(0xFFFFFFFF)),
        ],
            background: const CanvasBackground(
                spec: ProceduralSpec(
                    style: ProceduralStyle.rings, animated: true))));
    expect(byId(pageOf(bytes, 0), "stage"), isNull,
        reason: "a background going round is not something a book does");
    expect(files(bytes).keys.where((n) => n.endsWith(".mp4")), isEmpty);
  });

  // The one that says the layers are right: put back together the way CSS
  // puts them together -- each layer's pose about its centre, each picture's
  // clip, transform and opacity at the frame -- they are the page the canvas
  // draws, at every frame.
  testWidgets("played by CSS, the layers are the page at every frame",
      (tester) async {
    var doc = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
      frameRate: 12,
      scenes: [
        CanvasScene(id: "one", frames: 12, elements: [
          TextElement(
            ElementBase(
                id: "letters",
                x: 10,
                y: 10,
                width: 200,
                height: 50,
                track: arriving(0, 8)),
            text: "Hello world",
            // Inside its box: text that overflows is clipped to the box at
            // rest and not while it arrives, and the pictures are cut from it
            // at rest.
            textSpec: const TextSpec(fontSize: 14),
            animation: const TextAnimation(preset: TextAnimationPreset.letters),
          ),
          TextElement(
            ElementBase(
                id: "words",
                x: 10,
                y: 120,
                width: 200,
                height: 40,
                track: arriving(3, 11)),
            text: "pop the words",
            textSpec: const TextSpec(fontSize: 12),
            animation: const TextAnimation(
                preset: TextAnimationPreset.pop, ease: ChartEase.overshoot),
          ),
          ShapeElement(
              ElementBase(
                  id: "box",
                  x: 40,
                  y: 70,
                  width: 60,
                  height: 40,
                  rotation: 15,
                  opacity: 0.8,
                  track: ElementTrack(const [
                    Keyframe(
                        frame: 0,
                        scale: 0.5,
                        opacity: 0.3,
                        values: {KeyframeChannel.reveal: 0}),
                    Keyframe(
                        frame: 11,
                        dx: 120,
                        dy: 20,
                        scale: 1.4,
                        rotate: 90,
                        easing: KeyframeEasing.easeInOut,
                        values: {KeyframeChannel.reveal: 1}),
                  ])),
              fill: const Color(0xFF3366FF),
              animation: const ElementAnimation(
                  preset: ElementAnimationPreset.spinIn)),
          ShapeElement(
              ElementBase(
                  id: "wipe",
                  x: 220,
                  y: 20,
                  width: 80,
                  height: 60,
                  track: arriving(2, 9)),
              fill: const Color(0xFF22AA44),
              animation:
                  const ElementAnimation(preset: ElementAnimationPreset.wipe)),
          ShapeElement(
              const ElementBase(
                  id: "over", x: 150, y: 100, width: 40, height: 40),
              fill: const Color(0xFFFFAA00)),
        ]),
      ],
    );
    const pixels = 2.0, width = 640, height = 360;

    await tester.runAsync(() async {
      var built = (await buildEpubStage(doc, 0,
          pixels: pixels, width: width, height: height))!;
      expect(built.files.where((f) => f.mime != "image/png"), isEmpty);
      var decoded = <String, ui.Image>{};
      for (var f in built.files) {
        var codec = await ui.instantiateImageCodec(f.bytes);
        decoded[f.href] = (await codec.getNextFrame()).image;
      }
      var page = doc
          .goToScene(0)
          .copyWith(onMaster: false, background: doc.backgroundOf(0));

      Future<Uint8List> pixelsOf(void Function(Canvas) paint) async {
        var recorder = ui.PictureRecorder();
        paint(Canvas(recorder));
        var image = await recorder.endRecording().toImage(width, height);
        var raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return raw!.buffer.asUint8List();
      }

      void draw(Canvas canvas, EpubSprite s) {
        canvas.drawImageRect(
            decoded[s.href]!,
            Rect.fromLTWH(s.sx, s.sy, s.width, s.height),
            Rect.fromLTWH(s.x, s.y, s.width, s.height),
            Paint()..filterQuality = FilterQuality.medium);
      }

      void faded(Canvas canvas, String? opacity, void Function() then) {
        var o = opacity == null ? 1.0 : double.parse(opacity);
        if (o >= 0.999) return then();
        canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, o));
        then();
        canvas.restore();
      }

      for (var frame in [0, 2, 4, 6, 9, 11]) {
        var want = await pixelsOf((canvas) {
          canvas.scale(pixels);
          paintCanvasDocument(canvas, page, frame: frame);
        });
        var got = await pixelsOf((canvas) {
          for (var item in built.stage.items) {
            switch (item) {
              case EpubSlab slab:
                draw(canvas, slab.sprite);
              case EpubLayer layer:
                if (!layer.visible) continue;
                var pose = layer.pose.isEmpty ? null : cssAt(layer.pose, frame);
                canvas.save();
                if (pose != null) {
                  var n = numbers(pose["transform"]!);
                  canvas.translate(layer.originX, layer.originY);
                  canvas.translate(n[0], n[1]);
                  canvas.rotate(n[2] * math.pi / 180);
                  canvas.scale(n[3]);
                  canvas.translate(-layer.originX, -layer.originY);
                }
                faded(canvas, pose?["opacity"], () {
                  for (var part in layer.parts) {
                    var s = part.sprite;
                    canvas.save();
                    if (part.clipKeys.isNotEmpty) {
                      var c =
                          numbers(cssAt(part.clipKeys, frame)["clip-path"]!);
                      canvas.clipPath(Path()
                        ..addPolygon([
                          for (var i = 0; i + 1 < c.length; i += 2)
                            Offset(c[i] + s.x, c[i + 1] + s.y),
                        ], true));
                    }
                    var css =
                        part.keys.isEmpty ? null : cssAt(part.keys, frame);
                    if (css != null) {
                      var m = numbers(css["transform"]!);
                      canvas.transform(Float64List.fromList([
                        m[0], m[1], 0, 0, m[2], m[3], 0, 0, //
                        0, 0, 1, 0, m[4], m[5], 0, 1,
                      ]));
                    }
                    faded(canvas, css?["opacity"], () => draw(canvas, s));
                    canvas.restore();
                  }
                });
                canvas.restore();
            }
          }
        });
        var off = 0, total = 0;
        for (var i = 0; i < want.length; i++) {
          var d = (want[i] - got[i]).abs();
          total += d;
          if (d > 64) off++;
        }
        expect(total / want.length, lessThan(0.5),
            reason: "frame $frame: mean difference");
        expect(off / want.length, lessThan(0.003),
            reason: "frame $frame: channels far out");
      }
      for (var image in decoded.values) {
        image.dispose();
      }
      expect(built.stage.layers.map((l) => l.id),
          ["letters", "words", "box", "wipe"]);
      expect(
          built.stage.layers.firstWhere((l) => l.id == "letters").parts.length,
          greaterThan(8),
          reason: "letter by letter is a picture a letter");
    });
  });

  testWidgets("a growing chart is a video of the chart alone", (tester) async {
    var ffmpeg = await tester.runAsync(ffmpegPath);
    if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
    var chart = ChartElement(
      ElementBase(
          id: "c",
          x: 20,
          y: 20,
          width: 200,
          height: 120,
          track: arriving(2, 8)),
      data: const ChartData(categories: [
        "a",
        "b",
        "c"
      ], series: [
        ChartSeries(name: "x", color: Color(0xFF3366FF), values: [3, 5, 2]),
      ]),
    );
    var bytes = await publish(tester, book([chart]));
    var all = files(bytes);
    var films = all.keys.where((n) => n.endsWith(".mp4")).toList();
    expect(films, ["OEBPS/media/p0-c.mp4"],
        reason: "the chart on its own, and nothing else filmed");
    var layer = byId(pageOf(bytes, 0), "l-c")!;
    var video = layer.findElements("video").single;
    expect(video.getAttribute("data-at"), "2",
        reason: "from where it starts to change");
    expect(video.getAttribute("data-n"), "7");
    expect(
        layer.childElements.where((e) => e.getAttribute("class") == "pic ca"),
        hasLength(1),
        reason: "and the chart as it ends, after");
    // Over nothing, as HEVC with alpha -- and nothing in it half-clear: a
    // half-clear pixel is solid, in the colour it makes over the page, so the
    // video looks the same however a reader takes its alpha. Apple Books took
    // it as premultiplied and showed half-clear parts too bright.
    var out = File(path.join(root.path, "chart.mp4"));
    await tester.runAsync(() async {
      await out.writeAsBytes(all[films.single]!);
      var probe = await Process.run(ffmpeg, ["-hide_banner", "-i", out.path]);
      expect(probe.stderr.toString(), contains("hevc"));
      var run = await Process.run(
          ffmpeg,
          [
            "-hide_banner", "-loglevel", "error", "-i", out.path, //
            "-vf", "select=eq(n\\,6)", "-frames:v", "1",
            "-f", "rawvideo", "-pix_fmt", "rgba", "-",
          ],
          stdoutEncoding: null);
      var rgba = run.stdout as List<int>;
      expect(rgba, isNotEmpty);
      var clear = 0, solid = 0, half = 0;
      for (var i = 3; i < rgba.length; i += 4) {
        var alpha = rgba[i];
        if (alpha < 16) {
          clear++;
        } else if (alpha > 239) {
          solid++;
        } else {
          half++;
        }
      }
      var total = rgba.length ~/ 4;
      expect(clear, greaterThan(total ~/ 10), reason: "the page shows through");
      expect(solid, greaterThan(total ~/ 20), reason: "the chart is there");
      expect(half / total, lessThan(0.01),
          reason: "half-clear only where the encoder rounds an edge");
      // Marked as sRGB, which is what the renderer drew: unmarked, a reader
      // shows video on the television curve, and the chart changed colour
      // the moment it stopped growing and its still picture took over.
      var colour = await Process.run(
          ffmpeg.replaceFirst(RegExp(r"ffmpeg$"), "ffprobe"), [
        "-v", "error", "-show_entries", "stream=color_transfer", //
        "-of", "csv=p=0", out.path,
      ]);
      expect(colour.stdout.toString().trim(), "iec61966-2-1");
    });
  });

  ChartElement twoSeries() => const ChartElement(
        ElementBase(id: "c", x: 20, y: 20, width: 240, height: 140),
        showLegend: true,
        data: ChartData(categories: [
          "a",
          "b",
          "c"
        ], series: [
          ChartSeries(name: "x", color: Color(0xFF3366FF), values: [3, 5, 2]),
          ChartSeries(name: "y", color: Color(0xFFFF6633), values: [4, 2, 5]),
        ]),
      );

  // A chart's key switches its series on and off on the canvas, and does in
  // the book: the chart for each set of them switched, and an entry to press
  // for each -- on a page that does not otherwise move at all.
  testWidgets("a chart's key switches its series", (tester) async {
    var bytes = await publish(tester, book([twoSeries()]));
    var layer = byId(pageOf(bytes, 0), "l-c")!;
    var switched = layer.childElements
        .where((e) => e.getAttribute("class") == "pic sw")
        .map((e) => e.getAttribute("data-mask"))
        .toList();
    expect(switched, ["1", "2", "3"], reason: "either series off, and both");
    var presses = layer.findElements("button").toList();
    expect(
        presses.map((b) => b.getAttribute("data-act")), ["series", "series"]);
    expect(presses.map((b) => b.getAttribute("data-bit")), ["0", "1"]);
    expect(presses.every((b) => b.getAttribute("data-target") == "c"), isTrue);
  });

  // A button with a hover colour changes under the pointer on a page that
  // does not move at all: the page is laid out for it, the button is a layer
  // with the look it changes to, and the press is inside it -- a button that
  // does nothing a book can do still gets something to be pointed at.
  testWidgets("a button's hover look is there on a page that does not move",
      (tester) async {
    ButtonElement hovering(String id, double x, ButtonAction action) =>
        ButtonElement(ElementBase(id: id, x: x, y: 150, width: 60, height: 24),
            action: action, hoverFill: const Color(0xFFFF8800));
    var doc = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
      scenes: [
        CanvasScene(id: "one", elements: [
          hovering(
              "next",
              10,
              const ButtonAction(
                  kind: ButtonActionKind.goToScene, elementId: "two")),
          hovering("idle", 100,
              const ButtonAction(kind: ButtonActionKind.goToFrame)),
        ]),
        const CanvasScene(id: "two"),
      ],
    );
    var bytes = await publish(tester, doc);
    var page = pageOf(bytes, 0);
    expect(byId(page, "stage")!.getAttribute("data-autoplay"), "false");
    for (var id in ["next", "idle"]) {
      var layer = byId(page, "l-$id")!;
      expect(layer.getAttribute("class"), contains("hovers"));
      var hover = layer.childElements
          .where((e) => e.getAttribute("class") == "pic h")
          .single;
      expect(hover.getAttribute("style"), contains("visibility:hidden"),
          reason: "only under the pointer");
    }
    expect(byId(page, "l-next")!.findElements("a").single.getAttribute("href"),
        "page1.xhtml");
    expect(
        byId(page, "l-idle")!
            .childElements
            .where((e) => e.getAttribute("class") == "hit idle"),
        hasLength(1));
  });

  testWidgets(
      "Apple Books is told the book is fixed, and the cover stands alone",
      (tester) async {
    var doc = CanvasDocument(
      kind: CanvasKind.pages,
      pages: const PagesSpec(facing: true),
      size: const CanvasSize(ratio: CanvasRatio.a4, width: 320),
      scenes: [
        const CanvasScene(id: "cover", cover: PageCover.front),
        const CanvasScene(id: "one"),
        const CanvasScene(id: "two"),
      ],
    );
    var bytes = await publish(tester, doc);
    var all = files(bytes);
    var options =
        utf8.decode(all["META-INF/com.apple.ibooks.display-options.xml"]!);
    XmlDocument.parse(options);
    expect(options, contains('<option name="fixed-layout">true</option>'));
    var opf = utf8.decode(all["OEBPS/content.opf"]!);
    expect(
        opf,
        contains(
            '<itemref idref="page0" properties="rendition:page-spread-center"/>'));
  });

  // Ken, 2026-11-13: a clip started by a click, or by another clip ending,
  // was left out of the book -- "is there a way to fix this export
  // limitation that also complies with the epub3 format?" EPUB 3 lets a page
  // run script when the package says so; the clips go in as keyframes.
  testWidgets("a clip started by a click, and one after it, are in the book",
      (tester) async {
    var jump = presetNamed("Jump")!.clip("jump").copyWith(
        triggers: const [ClipTrigger(ClipTriggerKind.clicked, target: "dot")]);
    var shake = presetNamed("Shake")!.clip("shake").copyWith(triggers: const [
      ClipTrigger(ClipTriggerKind.clipEnds, target: "jump")
    ]);
    var dot = ShapeElement(
        ElementBase(
            id: "dot",
            x: 10,
            y: 10,
            width: 40,
            height: 40,
            motion: ElementMotion(clips: [jump]).inSlot(0, "jump")),
        fill: const Color(0xFFFF0000));
    var box = ShapeElement(
        ElementBase(
            id: "box",
            x: 120,
            y: 60,
            width: 40,
            height: 40,
            motion: ElementMotion(clips: [shake]).inSlot(0, "shake")),
        fill: const Color(0xFF0000FF));
    var bytes = await publish(tester, book([dot, box]));
    var page = pageOf(bytes, 0);
    List<Map<String, dynamic>> reactionsOf(String id) {
      var rx = byId(page, "l-$id")!
          .childElements
          .firstWhere((e) => e.getAttribute("class") == "rx");
      return (jsonDecode(rx.getAttribute("data-rx")!) as List)
          .cast<Map<String, dynamic>>();
    }

    // Each a layer, still on the timeline, with its reaction on it.
    var r = reactionsOf("dot").single;
    expect(r["on"], "click:dot");
    expect(r["c"], "jump");
    expect(r["ms"], greaterThan(0));
    var moved = (r["kf"] as List).any((k) =>
        (k["transform"] as String).contains("translate(") &&
        !(k["transform"] as String).startsWith("translate(0px,0px)"));
    expect(moved, isTrue, reason: "a jump moves it");
    expect(reactionsOf("box").single["on"], "end:jump",
        reason: "the shake waits on the jump");
    // Where a click lands: over the dot, in the page's pixels.
    var hits = [
      for (var b in page.findAllElements("button"))
        if (b.getAttribute("data-act") == "react") b,
    ];
    expect(hits.single.getAttribute("data-target"), "dot");
    // And the package says the page runs its script, as EPUB 3 asks.
    var opf = utf8.decode(files(bytes)["OEBPS/content.opf"]!);
    expect(opf, contains('properties="scripted"'));
    expect(
        utf8.decode(files(bytes)["OEBPS/media.js"]!), contains("media.react"));
  });

  // Ken, 2026-11-13: the book opened on a blank page -- frame 0, nothing
  // arrived, its Play not there yet -- and slowly.
  testWidgets(
      "a page that plays starts behind its start: the page, a Play, a bar",
      (tester) async {
    var bytes = await publish(tester, book([sliding()]));
    var page = pageOf(bytes, 0);
    var stage = byId(page, "stage")!;
    expect(stage.getAttribute("data-intro"), "true");
    var intro = byId(page, "intro")!;
    // A reader that runs no script shows the page as it ends up, and only
    // that: the Play and the bar are the script's to show.
    expect(intro.findElements("img").single.getAttribute("src"), "page0.png");
    expect(
        byId(page, "start")!.getAttribute("style"), startsWith("display:none"));
    expect(
        byId(page, "bar")!.getAttribute("style"), startsWith("display:none"));
    var css = utf8.decode(files(bytes)["OEBPS/page0.xhtml"]!);
    expect(css, contains("width: 0;"), reason: "a layer as big as it paints");
  });

  // Ken, 2026-11-13: "Move the play button to the first scene" -- a title
  // page whose Play goes to the page that builds, so the book has its Play
  // and the video does not. The press that went there was the press to play.
  testWidgets("a Play on a title page plays the page it goes to",
      (tester) async {
    var doc = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
      frameRate: 12,
      scenes: [
        CanvasScene(id: "title", elements: [
          button(
              "go",
              10,
              const ButtonAction(
                  kind: ButtonActionKind.goToScene, elementId: "page")),
          button(
              "still",
              100,
              const ButtonAction(
                  kind: ButtonActionKind.goToScene, elementId: "end")),
        ]),
        CanvasScene(id: "page", frames: 12, elements: [sliding()]),
        const CanvasScene(id: "end"),
      ],
    );
    var bytes = await publish(tester, doc);
    var hrefs = {
      for (var a in pageOf(bytes, 0).findAllElements("a"))
        a.getAttribute("href"): a.getAttribute("data-go"),
    };
    expect(hrefs, {"page1.xhtml#play": "page", "page2.xhtml": "page"},
        reason: "#play only to a page that moves; both followed on a touch");
    for (var i = 0; i < 3; i++) {
      expect(byId(pageOf(bytes, i), "play"), isNotNull,
          reason: "page $i: the fragment names something there");
    }
    var js = utf8.decode(files(bytes)["OEBPS/media.js"]!);
    expect(js, contains('window.location.hash === "#play"'));
  });

  // Ken, 2026-11-13: in Apple Books the title's Play went to the page, which
  // asked for a Play again -- a press on one page cannot start the next
  // one's sound -- and was pressed before that page had loaded.
  testWidgets("a title page is folded into the page it plays", (tester) async {
    var doc = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
      frameRate: 12,
      scenes: [
        CanvasScene(id: "title", elements: [
          ShapeElement(
              const ElementBase(
                  id: "logo", x: 20, y: 20, width: 80, height: 40),
              fill: const Color(0xFF00FF00)),
          button(
              "go",
              120,
              const ButtonAction(
                  kind: ButtonActionKind.goToScene, elementId: "page")),
        ]),
        CanvasScene(id: "page", frames: 12, elements: [sliding()]),
      ],
    );
    var bytes = await publish(tester, doc);
    var all = files(bytes);
    expect(all.containsKey("OEBPS/page1.xhtml"), isFalse,
        reason: "one page: the title is its start");
    var page = pageOf(bytes, 0);
    var intro = byId(page, "intro")!;
    expect(intro.findElements("img").first.getAttribute("src"), "start0.png");
    var start = byId(page, "start")!;
    expect(start.getAttribute("class"), "start title");
    expect(start.findElements("img").single.getAttribute("src"),
        "start0-play.png");
    // The bar where the Play is: the button at x 120, y 150, 50 by 20.
    double px(String style, String key) =>
        double.parse(RegExp("$key:([0-9.]+)px").firstMatch(style)!.group(1)!);
    var pixels = imageWidth(all["OEBPS/page0.png"]!) / 320;
    var bar = byId(page, "bar")!.getAttribute("style")!;
    var middle = px(bar, "left") + px(bar, "width") / 2;
    expect(middle, closeTo((120 + 25) * pixels, 2));
    var opf = utf8.decode(all["OEBPS/content.opf"]!);
    expect(opf, contains('href="start0.png"'));
    expect(opf, contains('href="start0-play.png"'));
    expect(all["OEBPS/start0.png"], isNotNull);
    expect(all["OEBPS/start0-play.png"], isNotNull);
  });

  // Ken, 2026-11-13: Apple Books showed no cover at first.
  testWidgets("the cover is a picture of its own, and a landmark",
      (tester) async {
    var bytes = await publish(tester, book([sliding()]));
    var all = files(bytes);
    var cover = all["OEBPS/cover.png"]!;
    expect(cover[25], 2, reason: "a PNG of red, green and blue: no alpha");
    var opf = utf8.decode(all["OEBPS/content.opf"]!);
    expect(
        opf,
        contains('<item id="cover" href="cover.png" '
            'media-type="image/png" properties="cover-image"/>'));
    expect(opf, contains('<meta name="cover" content="cover"/>'));
    expect('properties="cover-image"'.allMatches(opf), hasLength(1));
    expect(
        opf,
        contains('<reference type="cover" title="Cover" '
            'href="page0.xhtml"/>'));
    var nav = utf8.decode(all["OEBPS/nav.xhtml"]!);
    expect(nav, contains('<a epub:type="cover" href="page0.xhtml">'));
    expect(imageWidth(cover), greaterThan(100));
  });

  // Ken, 2026-11-13: "the rain video and background audio is still very
  // glitchy" -- a page of video blended over the page, every frame.
  // Each blend at an opacity where getting ffmpeg's inputs the wrong way
  // round shows: the background (0.125, 0.25, 0.375) and white --
  // screened at half, about (143, 160, 175); laid on at a quarter, about
  // (88, 112, 136).
  for (var (blend, opacity, want) in [
    (LayerBlend.screen, 0.5, [143, 160, 175]),
    (LayerBlend.normal, 0.25, [88, 112, 136]),
  ]) {
    testWidgets(
        "a video washed over the page is drawn into its background: "
        "${blend.name}", (tester) async {
      var ffmpeg = await tester.runAsync(ffmpegPath);
      if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
      Uint8List? bytes;
      List<int>? rgb;
      String? duration;
      await tester.runAsync(() async {
        var white = path.join(root.path, "white.mp4");
        await Process.run(ffmpeg, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-f", "lavfi", "-i", "color=c=white:size=320x180:rate=12",
          "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", white,
        ]);
        var id = (await CanvasMedia.saveFile(MediaKind.video, white))!;
        var doc = CanvasDocument(
          size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
          frameRate: 12,
          scenes: [
            CanvasScene(
                id: "one",
                frames: 24,
                background: const CanvasBackground(
                    spec: ProceduralSpec(background: Color(0xFF204060))),
                elements: [
                  VideoElement(
                      ElementBase(
                          id: "w",
                          width: 320,
                          height: 180,
                          opacity: opacity,
                          blend: blend),
                      clip: MediaClip(
                          playlist: [
                            MediaSource(
                                assetId: id,
                                length: 2,
                                width: 320,
                                height: 180,
                                fps: 12),
                          ],
                          timed: true,
                          muted: true,
                          loop: MediaLoop.one,
                          speed: 0.5)),
                  sliding(),
                ]),
          ],
        );
        bytes =
            (await renderDocument(doc, as: DocumentAs.interactiveEpub))!.data;
        var wash = files(bytes!)["OEBPS/media/page0-wash.mp4"];
        if (wash == null) return;
        var file = File(path.join(root.path, "wash.mp4"));
        await file.writeAsBytes(wash);
        var probe =
            await Process.run(ffmpeg, ["-hide_banner", "-i", file.path]);
        duration = RegExp(r"Duration: (\S+),")
            .firstMatch(probe.stderr.toString())
            ?.group(1);
        var frame = await Process.run(
            ffmpeg,
            [
              "-hide_banner", "-loglevel", "error", "-i", file.path, //
              "-frames:v", "1", "-vf", "crop=2:2:100:60", "-f", "rawvideo",
              "-pix_fmt", "rgb24", "-",
            ],
            stdoutEncoding: null);
        rgb = frame.stdout as List<int>;
      });
      expect(rgb, isNotNull, reason: "the wash is in the book");
      var page = pageOf(bytes!, 0);
      expect(
          byId(page, "backdrop")!.getAttribute("src"), "media/page0-wash.mp4");
      expect(byId(page, "l-w"), isNull, reason: "not a layer of its own too");
      expect(byId(page, "m-w"), isNull);
      expect(duration, startsWith("00:00:04.0"),
          reason: "once round, at half speed");
      for (var i = 0; i < 3; i++) {
        expect(rgb![i], closeTo(want[i], 6), reason: "channel $i");
      }
    });
  }

  // A book exported at full size had its rain as a 2480 by 3508 video,
  // too big to play smoothly: the reader scales it to the page anyway.
  testWidgets("a baked background is written no wider than washWidth",
      (tester) async {
    var ffmpeg = await tester.runAsync(ffmpegPath);
    if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
    String? size;
    await tester.runAsync(() async {
      var white = path.join(root.path, "wide.mp4");
      await Process.run(ffmpeg, [
        "-hide_banner", "-loglevel", "error", "-y", //
        "-f", "lavfi", "-i", "color=c=white:size=320x180:rate=12",
        "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", white,
      ]);
      var id = (await CanvasMedia.saveFile(MediaKind.video, white))!;
      var doc = CanvasDocument(
        size: const CanvasSize(
            ratio: CanvasRatio.wide, width: 320, exportWidth: 2560),
        frameRate: 12,
        scenes: [
          CanvasScene(id: "one", frames: 12, elements: [
            VideoElement(
                const ElementBase(
                    id: "w",
                    width: 320,
                    height: 180,
                    opacity: 0.2,
                    blend: LayerBlend.screen),
                clip: MediaClip(playlist: [
                  MediaSource(assetId: id, length: 1, width: 320, height: 180),
                ], timed: true, muted: true, loop: MediaLoop.one)),
            sliding(),
          ]),
        ],
      );
      var bytes =
          (await renderDocument(doc, as: DocumentAs.interactiveEpub))!.data;
      var wash = files(bytes)["OEBPS/media/page0-wash.mp4"];
      if (wash == null) return;
      var file = File(path.join(root.path, "wide-wash.mp4"));
      await file.writeAsBytes(wash);
      var probe = await Process.run(ffmpeg, ["-hide_banner", "-i", file.path]);
      size = RegExp(r"Video: .*?, (\d+x\d+)")
          .firstMatch(probe.stderr.toString())
          ?.group(1);
    });
    expect(size, "${washWidth}x720");
  });

  // Ken, 2026-11-14: the Decred infographic's camera zooms in on each panel
  // as it builds -- the book showed the whole page throughout.
  testWidgets("the camera frames the book's page as it frames the canvas",
      (tester) async {
    var doc = book([
      CameraElement(ElementBase(
          id: "cam",
          width: 320,
          height: 180,
          track: ElementTrack(const [
            Keyframe(frame: 0),
            Keyframe(frame: 4),
            Keyframe(frame: 8, scale: 2, dx: -60, dy: -30),
            Keyframe(frame: 11, scale: 2, dx: -60, dy: -30),
          ]))),
      sliding(),
    ]);
    var bytes = await publish(tester, doc);
    var page = pageOf(bytes, 0);
    var cam = page.findAllElements("div").firstWhere(
        (d) => d.getAttribute("class") == "cam",
        orElse: () => throw "no camera");
    var keys = (jsonDecode(cam.getAttribute("data-kf")!) as List)
        .cast<Map<String, dynamic>>();
    var pixels = imageWidth(files(bytes)["OEBPS/page0.png"]!) / 320;
    expect(keys.first["transform"], "translate(0.00px,0.00px) scale(1.00000)");
    // Twice as close, looking at (100, 60): that point in the middle.
    var tx = (160 * pixels - 100 * pixels * 2).toStringAsFixed(2);
    var ty = (90 * pixels - 60 * pixels * 2).toStringAsFixed(2);
    expect(keys.last["transform"], "translate(${tx}px,${ty}px) scale(2.00000)");
    expect(keys.last["offset"], 1);
    // A key for each frame it moves on, and none in its holds.
    expect(keys.map((k) => k["offset"]).length, lessThan(12));
    expect(byId(page, "l-cam"), isNull, reason: "the camera is not drawn");
    // Inside it, what moves; outside it, the start screen.
    expect(
        cam.findAllElements("div").any((d) => d.getAttribute("id") == "l-dot"),
        isTrue);
    expect(
        cam.findAllElements("div").any((d) => d.getAttribute("id") == "intro"),
        isFalse);
  });

  // Ken, 2026-11-14: the camera's lens in the book as in the video --
  // roll, depth of field, parallax and a vignette (motion blur is the
  // video's alone).
  testWidgets("the camera's lens: roll, depth of field, parallax, vignette",
      (tester) async {
    var doc = book([
      ShapeElement(
          const ElementBase(id: "near", x: 20, y: 40, width: 60, height: 60),
          fill: const Color(0xFF00FF00)),
      ShapeElement(
          const ElementBase(
              id: "far", x: 200, y: 40, width: 60, height: 60, depth: 1),
          fill: const Color(0xFF0000FF)),
      const CameraElement(
          ElementBase(
              id: "cam", x: 80, y: 45, width: 160, height: 90, rotation: 10),
          blur: 4,
          parallax: 0.5,
          vignette: 0.6),
    ]);
    var bytes = await publish(tester, doc);
    var page = pageOf(bytes, 0);
    var pixels = imageWidth(files(bytes)["OEBPS/page0.png"]!) / 320;
    var cam = page
        .findAllElements("div")
        .firstWhere((d) => d.getAttribute("class") == "cam");
    expect(cam.getAttribute("style"), contains("rotate(-10.000deg)"),
        reason: "rolled, the picture turned back");
    // The far square: blurred and moved on a wrapper round its layer.
    var lens = byId(page, "l-far")!.parentElement!;
    expect(lens.getAttribute("class"), "lens");
    var style = lens.getAttribute("style")!;
    expect(style, contains("blur(${(4 * pixels).toStringAsFixed(2)}px)"));
    expect(style, contains("scale("));
    // The near one, on the focus and the page: as it was.
    expect(byId(page, "l-near"), isNull,
        reason: "nothing done to it, so still flattened");
    var vignette = page
        .findAllElements("div")
        .firstWhere((d) => d.getAttribute("class") == "vignette");
    expect(vignette.getAttribute("style"), contains("opacity:0.600"));
    expect(vignette.getAttribute("style"), contains("radial-gradient"));
  });

  // Ken, 2026-11-13: the Rain, screened at a tenth on the canvas, played
  // full and black over the book's page.
  test("a video's opacity and blend go with it into the book", () {
    var m = EpubMedia(
        id: "v",
        video: true,
        width: 10,
        height: 10,
        sources: const ["a.mp4"],
        ranges: const [(0, 0)],
        opacity: 0.1,
        blend: cssBlend(LayerBlend.screen));
    expect(m.blend, "screen");
    expect(cssBlend(LayerBlend.normal), isNull);
    expect(cssBlend(LayerBlend.colorDodge), "color-dodge");
  });

  group("the script", () {
    late String node;
    setUp(() {
      node = Process.runSync("which", ["node"]).stdout.toString().trim();
    });

    /// drive runs media.js from [bytes] against page 0 as a stand-in -- its
    /// animations, its layers, its players, its buttons -- then the [steps],
    /// "wait <ms>" or "press <button id>", reporting after each where the
    /// animations have got to and what the players are doing.
    Future<List<Map<String, dynamic>>> drive(
        Uint8List bytes, List<String> steps) async {
      var all = files(bytes);
      var page = pageOf(bytes, 0);
      var stage = byId(page, "stage")!;
      var animated = [
        for (var e in page.descendantElements)
          if (e.getAttribute("data-kf") != null) e.getAttribute("data-kf"),
      ];
      var layers = [
        for (var l in page.findAllElements("div"))
          if (l.getAttribute("class")?.startsWith("layer") == true)
            {
              "id": l.getAttribute("id"),
              "hidden": l.getAttribute("style")!.contains("display:none"),
              "switched": [
                for (var e in l.childElements)
                  if (e.getAttribute("class") == "pic sw")
                    e.getAttribute("data-mask"),
              ],
            },
      ];
      var players = [
        for (var m in page.descendantElements)
          if ((m.name.local == "video" || m.name.local == "audio") &&
              (m.getAttribute("data-at") != null ||
                  m.getAttribute("id") == "soundtrack"))
            {
              for (var a in m.attributes) a.name.local: a.value,
            },
      ];
      var buttons = [
        for (var (i, b) in page
            .findAllElements("button")
            .where((b) => b.getAttribute("id") != "start")
            .indexed)
          {
            "id": "b$i",
            "act": b.getAttribute("data-act"),
            "target": b.getAttribute("data-target"),
            "frame": b.getAttribute("data-frame"),
            "bit": b.getAttribute("data-bit"),
          },
      ];
      var hasBackdrop = byId(page, "backdrop") != null;
      var hasIntro = byId(page, "intro") != null;
      var dir = await Directory.systemTemp.createTemp("epub_clock");
      addTearDown(() => dir.delete(recursive: true));
      var harness = File(path.join(dir.path, "run.js"));
      await harness.writeAsString('''
var now = 0, queue = [], anims = [];
function El(tag, attrs) {
  this.tagName = tag; this.attrs = attrs || {}; this.style = {}; this.kids = [];
  this.on = {}; this.id = this.attrs.id || ""; this.parentNode = null;
  var classes = {};
  this.classes = classes;
  this.classList = { add: function (c) { classes[c] = true; }, remove: function (c) { delete classes[c]; } };
}
El.prototype.setAttribute = function (n, v) { this.attrs[n] = v; };
El.prototype.getAttribute = function (n) { return n in this.attrs ? this.attrs[n] : null; };
El.prototype.addEventListener = function (t, f) { (this.on[t] = this.on[t] || []).push(f); };
El.prototype.getElementsByTagName = function (t) { return this.kids.filter(function (k) { return k.tagName === t; }); };
El.prototype.getElementsByClassName = function (c) {
  return this.kids.filter(function (k) { return (k.attrs["class"] || "").split(" ").indexOf(c) >= 0; });
};
// An element the reader animates: the animation keeps its own time, moving
// on by itself while it plays, as a real one does.
El.prototype.animate = function (kf, options) {
  var a = { currentTime: 0, playing: false, duration: options.duration,
    play: function () { a.playing = true; }, pause: function () { a.playing = false; } };
  anims.push(a);
  return a;
};
var stage = new El("div", ${jsonEncode({
            "id": "stage",
            "data-frames": stage.getAttribute("data-frames"),
            "data-rate": stage.getAttribute("data-rate"),
            "data-marks": stage.getAttribute("data-marks"),
            "data-autoplay": stage.getAttribute("data-autoplay"),
            "data-intro": stage.getAttribute("data-intro"),
          })});
// The page's background video, where it has one: load() stops it, as a
// reader's does, and it is ready as soon as it has loaded.
var backdrop = null;
if ($hasBackdrop) {
  backdrop = new El("video", { id: "backdrop" });
  backdrop.paused = true; backdrop.readyState = 0;
  backdrop.play = function () { backdrop.paused = false; };
  backdrop.pause = function () { backdrop.paused = true; };
  backdrop.load = function () {
    backdrop.paused = true; backdrop.readyState = 4;
    (backdrop.on.canplaythrough || []).slice().forEach(function (f) { f(); });
  };
}
// The start screen, where it has one.
var intro = null, start = null, bar = null, fill = null;
if ($hasIntro) {
  intro = new El("div", { id: "intro" });
  start = new El("button", { id: "start" });
  bar = new El("div", { id: "bar" });
  fill = new El("span", { id: "barFill" });
}
var animated = ${jsonEncode(animated)}.map(function (kf) { return new El("div", { "data-kf": kf }); });
var layers = ${jsonEncode(layers)}.map(function (d) {
  var l = new El("div", { id: d.id });
  if (d.hidden) l.style.display = "none";
  d.switched.forEach(function (m) {
    var s = new El("span", { "class": "pic sw", "data-mask": m });
    s.style.visibility = "hidden";
    l.kids.push(s);
  });
  return l;
});
var players = ${jsonEncode(players)}.map(function (d) {
  var m = new El(d.id === "soundtrack" ? "audio" : "video", d);
  m.paused = true; m.currentTime = 0; m.duration = 3; m.src = ""; m.readyState = 4;
  m.playbackRate = 1;
  // As a reader's does: "playing" once it has started.
  m.play = function () { m.paused = false; (m.on.playing || []).slice().forEach(function (f) { f(); }); };
  m.pause = function () { m.paused = true; };
  m.load = function () {};
  return m;
});
var buttons = ${jsonEncode(buttons)}.map(function (d) {
  return new El("button", { id: d.id, "data-act": d.act, "data-target": d.target, "data-frame": d.frame, "data-bit": d.bit });
});
global.performance = { now: function () { return now; } };
global.window = { requestAnimationFrame: function (f) { queue.push(f); }, location: {}, performance: global.performance };
global.setTimeout = function (f, ms) { var at = now + ms; queue.push(function wake(t) { if (t >= at) f(); else queue.push(wake); }); };
global.document = {
  getElementById: function (id) {
    if (id === "stage") return stage;
    if (id === "backdrop") return backdrop;
    if (id === "intro") return intro;
    if (id === "start") return start;
    if (id === "bar") return bar;
    if (id === "barFill") return fill;
    return players.filter(function (m) { return m.id === id; })[0] || null;
  },
  querySelectorAll: function (s) {
    if (s === ".layer") return layers;
    if (s === "[data-kf]") return animated;
    if (s === "[data-list]") return players.filter(function (m) { return m.id !== "soundtrack"; });
    if (s === "[data-act]") return buttons;
    if (s === ".stage video, .stage audio") return players.concat(backdrop ? [backdrop] : []);
    return [];
  }
};
${utf8.decode(all["OEBPS/media.js"]!)}
function report() {
  console.log(JSON.stringify({
    t: anims.length ? anims[0].currentTime / 1000 : null,
    playing: anims.length ? anims[0].playing : null,
    same: anims.every(function (a) { return a.currentTime === anims[0].currentTime; }),
    layers: layers.map(function (l) {
      return { id: l.id, display: l.style.display || "", switched: !!l.classes.switched,
        showing: l.kids.filter(function (k) { return k.style.visibility === "visible"; })
          .map(function (k) { return k.attrs["data-mask"]; }) };
    }),
    media: players.map(function (m) { return { id: m.id, src: m.src, t: m.currentTime, paused: m.paused, rate: m.playbackRate }; }),
    backdrop: backdrop ? (backdrop.paused ? "paused" : "playing") : null,
    intro: intro ? (intro.style.display || "shown") : null,
    start: start ? (start.style.visibility || "shown") : null
  }));
}
function wait(ms) {
  for (var s = 0; s < ms; s += 16) {
    now += 16;
    anims.forEach(function (a) { if (a.playing) a.currentTime += 16; });
    players.forEach(function (m) { if (!m.paused) m.currentTime += 0.016 * (m.playbackRate || 1); });
    var q = queue; queue = [];
    q.forEach(function (f) { f(now); });
  }
}
// The sound held back, as a reader's may be, by [ms].
function lag(ms) {
  players.forEach(function (m) { if (m.id === "soundtrack") m.currentTime -= ms / 1000; });
}
// The start screen's Play, pressed.
function begin() {
  var e = { preventDefault: function () {}, stopPropagation: function () {} };
  start.on.click.forEach(function (f) { f(e); });
}
function press(id) {
  var b = buttons.filter(function (b) { return b.id === id; })[0];
  var e = { preventDefault: function () {}, stopPropagation: function () {} };
  b.on.click.forEach(function (f) { f(e); });
}
report();
${steps.map((s) {
        var p = s.split(" ");
        return switch (p[0]) {
          "wait" => "wait(${p[1]}); report();",
          "lag" => "lag(${p[1]}); report();",
          "begin" => "begin(); report();",
          _ => "press('${p[1]}'); report();",
        };
      }).join("\n")}
''');
      var run = await Process.run(node, [harness.path]);
      expect(run.exitCode, 0, reason: "${run.stderr}");
      return [
        for (var line in (run.stdout as String).trim().split("\n"))
          jsonDecode(line) as Map<String, dynamic>,
      ];
    }

    double t(Map<String, dynamic> seen) => (seen["t"] as num).toDouble();

    testWidgets("its own buttons drive it, and it plays through once",
        (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var bytes = await publish(
          tester,
          book([
            sliding(),
            button(
                "t", 10, const ButtonAction(kind: ButtonActionKind.togglePlay)),
            button("g", 70,
                const ButtonAction(kind: ButtonActionKind.goToFrame, frame: 6)),
            button(
                "u",
                130,
                const ButtonAction(
                    kind: ButtonActionKind.playToFrame, frame: 9)),
          ]));
      var ids = {
        for (var (i, b) in pageOf(bytes, 0)
            .findAllElements("button")
            .where((b) => b.getAttribute("id") != "start")
            .indexed)
          b.getAttribute("data-act"): "b$i",
      };
      var seen = await tester.runAsync(() => drive(bytes, [
            "wait 1000",
            "press ${ids["goto"]}",
            "press ${ids["toggle"]}",
            "wait 3000",
            "press ${ids["playto"]}",
            "wait 3000",
          ]));
      expect(t(seen![0]), 0, reason: "opens on frame 0");
      expect(t(seen[1]), 0, reason: "it waits for its buttons");
      expect(t(seen[2]), closeTo(6 / 12, 0.001), reason: "Go to frame 6");
      expect(seen[3]["playing"], isTrue, reason: "Play or pause played");
      // Three seconds is three times round a one-second page: it stops at
      // the end rather than going round.
      expect(t(seen[4]), closeTo(11 / 12, 0.001));
      expect(seen[4]["playing"], isFalse);
      expect(t(seen[6]), closeTo(9 / 12, 0.001),
          reason: "Play to frame 9, from the start again");
      expect(seen.every((s) => s["same"] == true), isTrue,
          reason: "every animation on the page keeps the same time");
    });

    // With nothing of its own to press, it waits on its start screen's Play
    // (a reader lets sound start only on a press), then plays to the stop.
    testWidgets("with nothing to press, its start plays it and it obeys a stop",
        (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var bytes = await publish(
          tester,
          book([
            sliding()
          ], marks: const [
            TimelineAction(frame: 5, kind: TimelineActionKind.stop),
          ]));
      var seen = await tester
          .runAsync(() => drive(bytes, ["wait 100", "begin", "wait 2000"]));
      expect(seen![1]["playing"], isFalse, reason: "waiting on its Play");
      expect(seen[1]["start"], "shown");
      expect(seen[2]["playing"], isTrue);
      expect(t(seen[3]), closeTo(5 / 12, 0.001));
      expect(seen[3]["playing"], isFalse);
    });

    // A tone on the timeline and a video on it: the tone is mixed into the
    // page's soundtrack, which runs with the playhead, and the video follows
    // the playhead from its frame -- waiting on its first picture before,
    // playing in step during, and both stopping when the playhead does.
    testWidgets("sound and video on the timeline follow the playhead",
        (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var ffmpeg = await tester.runAsync(ffmpegPath);
      if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
      Uint8List? bytes;
      String? duration;
      await tester.runAsync(() async {
        var tone = path.join(root.path, "tone.flac");
        var talk = path.join(root.path, "talk.mp4");
        await Process.run(ffmpeg, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
          "-t", "2", tone,
        ]);
        await Process.run(ffmpeg, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-f", "lavfi", "-i", "testsrc=size=160x120:rate=25",
          "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", talk,
        ]);
        var toneId = (await CanvasMedia.saveFile(MediaKind.audio, tone))!;
        var talkId = (await CanvasMedia.saveFile(MediaKind.video, talk))!;
        var doc = CanvasDocument(
          size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
          frameRate: 12,
          scenes: [
            CanvasScene(id: "one", frames: 36, elements: [
              AudioElement(
                  const ElementBase(
                      id: "s",
                      x: 10,
                      y: 10,
                      width: 40,
                      height: 40,
                      visible: false),
                  clip: MediaClip(
                      playlist: [MediaSource(assetId: toneId, length: 2)],
                      timed: true,
                      at: 6)),
              VideoElement(
                  const ElementBase(
                      id: "v", x: 100, y: 20, width: 160, height: 90),
                  clip: MediaClip(playlist: [
                    MediaSource(
                        assetId: talkId,
                        length: 1,
                        width: 160,
                        height: 120,
                        fps: 25),
                  ], timed: true, at: 12)),
              button("t", 10,
                  const ButtonAction(kind: ButtonActionKind.togglePlay)),
            ]),
          ],
        );
        bytes =
            (await renderDocument(doc, as: DocumentAs.interactiveEpub))!.data;
        var track = files(bytes!)["OEBPS/media/page0-sound.m4a"];
        expect(track, isNotNull, reason: "the page's soundtrack is carried");
        var out = File(path.join(root.path, "sound.m4a"));
        await out.writeAsBytes(track!);
        var probe = await Process.run(ffmpeg, ["-hide_banner", "-i", out.path]);
        duration = RegExp(r"Duration: (\S+),")
            .firstMatch(probe.stderr.toString())
            ?.group(1);
      });
      expect(duration, startsWith("00:00:03.0"),
          reason: "as long as the page: 36 frames at 12 a second");

      var page = pageOf(bytes!, 0);
      expect(byId(page, "soundtrack")!.getAttribute("src"),
          "media/page0-sound.m4a");
      expect(byId(page, "m-s"), isNull,
          reason: "the tone is in the soundtrack, not a player of its own");
      var video = byId(page, "l-v")!.findElements("video").single;
      expect(video.getAttribute("data-at"), "12");

      var seen = await tester.runAsync(() => drive(bytes!, [
            "press b0",
            "wait 900",
            "wait 600",
            "press b0",
          ]));
      Map<String, dynamic> player(Map<String, dynamic> s, String id) =>
          (s["media"] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((m) => m["id"] == id);
      var early = seen![2], later = seen[3], paused = seen[4];
      expect(player(early, "soundtrack")["paused"], isFalse);
      expect((player(early, "soundtrack")["t"] as num).toDouble(),
          closeTo(0.9, 0.1));
      expect(player(early, "m-v")["paused"], isTrue,
          reason: "its frame is not reached until a second in");
      expect(player(later, "m-v")["paused"], isFalse);
      expect((player(later, "m-v")["t"] as num).toDouble(), closeTo(0.5, 0.1),
          reason: "half a second into its file, a second and a half in");
      expect(player(paused, "m-v")["paused"], isTrue);
      expect(player(paused, "soundtrack")["paused"], isTrue);
    });

    // Ken, 2026-11-13: the book's music stuttered -- the script moved the
    // sound to its own clock whenever they drifted, each move a gap.
    testWidgets("the sound is the clock: held back, the page waits for it",
        (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var ffmpeg = await tester.runAsync(ffmpegPath);
      if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
      Uint8List? bytes;
      await tester.runAsync(() async {
        var tone = path.join(root.path, "tone.flac");
        await Process.run(ffmpeg, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
          "-t", "3", tone,
        ]);
        var toneId = (await CanvasMedia.saveFile(MediaKind.audio, tone))!;
        var doc = CanvasDocument(
          size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
          frameRate: 12,
          scenes: [
            CanvasScene(id: "one", frames: 36, elements: [
              sliding(),
              AudioElement(
                  const ElementBase(
                      id: "s", width: 40, height: 40, visible: false),
                  clip: MediaClip(
                      playlist: [MediaSource(assetId: toneId, length: 3)],
                      timed: true)),
              button("t", 10,
                  const ButtonAction(kind: ButtonActionKind.togglePlay)),
            ]),
          ],
        );
        bytes =
            (await renderDocument(doc, as: DocumentAs.interactiveEpub))!.data;
      });
      var seen = await tester.runAsync(() => drive(bytes!, [
            "press b0",
            "wait 500",
            "lag 300",
            "wait 100",
          ]));
      var sound = (seen![4]["media"] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((m) => m["id"] == "soundtrack");
      expect((sound["t"] as num).toDouble(), closeTo(0.3, 0.05),
          reason: "left where it was, not put back to the page's time");
      expect(t(seen[4]), closeTo((sound["t"] as num).toDouble(), 0.05),
          reason: "the page gone back to the sound");
    });

    // The Rain, at half speed on the canvas, went round twice as fast in
    // the book.
    testWidgets("a video at half speed plays at half speed", (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var ffmpeg = await tester.runAsync(ffmpegPath);
      if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
      Uint8List? bytes;
      await tester.runAsync(() async {
        var talk = path.join(root.path, "slow.mp4");
        await Process.run(ffmpeg, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-f", "lavfi", "-i", "testsrc=size=160x120:rate=25",
          "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", talk,
        ]);
        var talkId = (await CanvasMedia.saveFile(MediaKind.video, talk))!;
        var doc = CanvasDocument(
          size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
          frameRate: 12,
          scenes: [
            CanvasScene(id: "one", frames: 36, elements: [
              VideoElement(
                  const ElementBase(
                      id: "v", x: 100, y: 20, width: 160, height: 90),
                  clip: MediaClip(playlist: [
                    MediaSource(
                        assetId: talkId,
                        length: 2,
                        width: 160,
                        height: 120,
                        fps: 25),
                  ], timed: true, speed: 0.5)),
              button("t", 10,
                  const ButtonAction(kind: ButtonActionKind.togglePlay)),
            ]),
          ],
        );
        bytes =
            (await renderDocument(doc, as: DocumentAs.interactiveEpub))!.data;
      });
      var video = byId(pageOf(bytes!, 0), "l-v")!.findElements("video").single;
      expect(video.getAttribute("data-speed"), "0.5");
      var seen = await tester.runAsync(() => drive(bytes!, [
            "press b0",
            "wait 1000",
          ]));
      var v = (seen![2]["media"] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((m) => m["id"] == "m-v");
      expect(v["rate"], 0.5);
      expect((v["t"] as num).toDouble(), closeTo(0.5, 0.06),
          reason: "half a second into its file a second in");
    });

    // The book's baked rain stood still: its start screen loaded it again
    // after it had been started, which stops a video.
    testWidgets("behind a start screen, the background goes round on Play",
        (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var ffmpeg = await tester.runAsync(ffmpegPath);
      if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
      Uint8List? bytes;
      await tester.runAsync(() async {
        var white = path.join(root.path, "white.mp4");
        await Process.run(ffmpeg, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-f", "lavfi", "-i", "color=c=white:size=320x180:rate=12",
          "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", white,
        ]);
        var id = (await CanvasMedia.saveFile(MediaKind.video, white))!;
        var doc = CanvasDocument(
          size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
          frameRate: 12,
          scenes: [
            CanvasScene(id: "one", frames: 24, elements: [
              VideoElement(
                  const ElementBase(
                      id: "w",
                      width: 320,
                      height: 180,
                      opacity: 0.2,
                      blend: LayerBlend.screen),
                  clip: MediaClip(playlist: [
                    MediaSource(
                        assetId: id, length: 1, width: 320, height: 180),
                  ], timed: true, muted: true, loop: MediaLoop.one)),
              sliding(),
            ]),
          ],
        );
        bytes =
            (await renderDocument(doc, as: DocumentAs.interactiveEpub))!.data;
      });
      expect(byId(pageOf(bytes!, 0), "backdrop"), isNotNull);
      var seen = await tester.runAsync(() => drive(bytes!, [
            "wait 100",
            "begin",
            "wait 500",
          ]));
      expect(seen![1]["start"], "shown", reason: "loaded: its Play shows");
      expect(seen[1]["backdrop"], "paused", reason: "not before the Play");
      expect(seen[2]["intro"], "none");
      expect(seen[2]["backdrop"], "playing");
      expect(seen[3]["backdrop"], "playing");
      expect(t(seen[3]), closeTo(0.5, 0.05));
    });

    testWidgets("pressing the key shows the chart with that series off",
        (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var bytes = await publish(tester, book([twoSeries()]));
      var ids = [
        for (var (i, b) in pageOf(bytes, 0).findAllElements("button").indexed)
          if (b.getAttribute("data-act") == "series") "b$i",
      ];
      var seen = await tester.runAsync(() => drive(bytes, [
            "press ${ids[0]}",
            "press ${ids[1]}",
            "press ${ids[0]}",
            "press ${ids[1]}"
          ]));
      Map<String, dynamic> chart(Map<String, dynamic> s) =>
          (s["layers"] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((l) => l["id"] == "l-c");
      expect(seen!.map((s) => chart(s)["showing"]), [
        <String>[],
        ["1"],
        ["3"],
        ["2"],
        <String>[],
      ]);
      expect(seen.map((s) => chart(s)["switched"]),
          [false, true, true, true, false],
          reason: "the chart as it plays is back once none are switched");
    });

    testWidgets("Show or hide flips the layer", (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var bytes = await publish(
          tester,
          book([
            ShapeElement(
                const ElementBase(
                    id: "secret",
                    x: 200,
                    y: 20,
                    width: 60,
                    height: 60,
                    visible: false),
                fill: const Color(0xFF0000FF)),
            button(
                "s",
                10,
                const ButtonAction(
                    kind: ButtonActionKind.toggleElement, elementId: "secret")),
          ]));
      var seen =
          await tester.runAsync(() => drive(bytes, ["press b0", "press b0"]));
      String display(Map<String, dynamic> s) =>
          ((s["layers"] as List).single as Map)["display"] as String;
      expect(seen!.map(display), ["none", "", "none"]);
    });
  });
}

/// imageWidth is how wide a PNG is, from its header.
int imageWidth(List<int> b) =>
    (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
