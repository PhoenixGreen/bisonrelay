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
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
// ignore: depend_on_referenced_packages
import 'package:xml/xml.dart';

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

    // The play button is aimed at the page's playhead.
    var play = page.findAllElements("button").single;
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
        for (var (i, b) in page.findAllElements("button").indexed)
          {
            "id": "b$i",
            "act": b.getAttribute("data-act"),
            "target": b.getAttribute("data-target"),
            "frame": b.getAttribute("data-frame"),
            "bit": b.getAttribute("data-bit"),
          },
      ];
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
          })});
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
  m.paused = true; m.currentTime = 0; m.duration = 3; m.src = "";
  m.play = function () { m.paused = false; };
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
    return players.filter(function (m) { return m.id === id; })[0] || null;
  },
  querySelectorAll: function (s) {
    if (s === ".layer") return layers;
    if (s === "[data-kf]") return animated;
    if (s === "[data-list]") return players.filter(function (m) { return m.id !== "soundtrack"; });
    if (s === "[data-act]") return buttons;
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
    media: players.map(function (m) { return { id: m.id, src: m.src, t: m.currentTime, paused: m.paused }; })
  }));
}
function wait(ms) {
  for (var s = 0; s < ms; s += 16) {
    now += 16;
    anims.forEach(function (a) { if (a.playing) a.currentTime += 16; });
    players.forEach(function (m) { if (!m.paused) m.currentTime += 0.016; });
    var q = queue; queue = [];
    q.forEach(function (f) { f(now); });
  }
}
function press(id) {
  var b = buttons.filter(function (b) { return b.id === id; })[0];
  var e = { preventDefault: function () {}, stopPropagation: function () {} };
  b.on.click.forEach(function (f) { f(e); });
}
report();
${steps.map((s) {
        var p = s.split(" ");
        return p[0] == "wait"
            ? "wait(${p[1]}); report();"
            : "press('${p[1]}'); report();";
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
        for (var (i, b) in pageOf(bytes, 0).findAllElements("button").indexed)
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

    testWidgets("with nothing to press, it starts by itself and obeys a stop",
        (tester) async {
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var bytes = await publish(
          tester,
          book([
            sliding()
          ], marks: const [
            TimelineAction(frame: 5, kind: TimelineActionKind.stop),
          ]));
      var seen = await tester.runAsync(() => drive(bytes, ["wait 2000"]));
      expect(seen![0]["playing"], isTrue);
      expect(t(seen[1]), closeTo(5 / 12, 0.001));
      expect(seen[1]["playing"], isFalse);
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
