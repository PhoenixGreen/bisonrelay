import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_media.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
// ignore: depend_on_referenced_packages
import 'package:xml/xml.dart';

// canvas_epub_media_test.dart is sound and video in an interactive EPUB: what
// the pages say, that they are well-formed -- an EPUB reader is an XHTML
// parser, and one stray bracket is a blank page -- that the script parses,
// and, with a real ffmpeg, a book that carries its sound and its film.

Uint8List png() => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

Map<String, String> unzip(Uint8List bytes) {
  var archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (var f in archive.files)
      if (f.isFile &&
          !f.name.endsWith(".png") &&
          !f.name.startsWith("OEBPS/media/"))
        f.name: utf8.decode(f.content, allowMalformed: true),
  };
}

Set<String> names(Uint8List bytes) => {
      for (var f in ZipDecoder().decodeBytes(bytes).files) f.name,
    };

void main() {
  group("the pages", () {
    var sound = const EpubMedia(
        id: "s",
        video: false,
        x: 10,
        y: 20,
        width: 40,
        height: 40,
        sources: ["media/a.m4a", "media/b.m4a"],
        ranges: [(1.5, 4), (0, 0)],
        loop: "all",
        fadeIn: 0.5,
        pressable: true);
    var clipOnPage = const EpubMedia(
        id: "v",
        video: true,
        x: 100,
        y: 100,
        width: 320,
        height: 180,
        rotation: 5,
        sources: ["media/v.mp4"],
        ranges: [(0, 0)],
        controls: true,
        poster: "media/p.png");
    var files = [
      EpubFile("media/a.m4a", Uint8List(4), "audio/mp4"),
      EpubFile("media/b.m4a", Uint8List(4), "audio/mp4"),
      EpubFile("media/v.mp4", Uint8List(4), "video/mp4"),
    ];

    Uint8List book({bool interactive = true}) => writeEpub(
          title: "Sound",
          interactive: interactive,
          pages: [
            EpubPage(
              png: png(),
              width: 800,
              height: 600,
              title: "One",
              media: [sound, clipOnPage],
              actions: const [
                EpubAction(
                    x: 5,
                    y: 5,
                    width: 30,
                    height: 10,
                    act: "mute",
                    target: "s"),
              ],
              files: files,
            ),
            // The same song again: carried once.
            EpubPage(
              png: png(),
              width: 800,
              height: 600,
              title: "Two",
              media: [sound],
              files: files.take(2).toList(),
            ),
            EpubPage(png: png(), width: 800, height: 600, title: "Three"),
          ],
        );

    test("every page is well-formed XHTML", () {
      for (var entry in unzip(book()).entries) {
        if (!entry.key.endsWith(".xhtml") && !entry.key.endsWith(".opf")) {
          continue;
        }
        expect(() => XmlDocument.parse(entry.value), returnsNormally,
            reason: entry.key);
      }
    });

    test("a sound says how it plays, and can be pressed", () {
      var page = unzip(book())["OEBPS/page0.xhtml"]!;
      expect(page, contains('<audio id="m-s"'));
      expect(page, contains('data-list="media/a.m4a|media/b.m4a"'));
      expect(page, contains('data-ranges="1.5,4.0|0.0,0.0"'));
      expect(page, contains('data-loop="all"'));
      expect(page, contains('data-act="toggle" data-target="s"'));
      expect(page, contains('data-act="mute" data-target="s"'),
          reason: "a button's press");
      expect(page, contains('<script src="media.js">'));
    });

    // Apple Books showed the playing ring over a video's press area as an
    // oval: the ring was a speaker's, with half-round corners, and a
    // rectangle given those is an ellipse. Only a speaker is ringed now, and
    // to its own corners.
    test("only a speaker is ringed while it plays, never a video", () {
      var page = unzip(writeEpub(title: "Ring", interactive: true, pages: [
        EpubPage(
          png: png(),
          width: 800,
          height: 600,
          title: "One",
          media: const [
            EpubMedia(
                id: "s",
                video: false,
                width: 40,
                height: 40,
                radius: 20,
                sources: ["media/a.m4a"],
                ranges: [(0, 0)],
                pressable: true),
            EpubMedia(
                id: "v",
                video: true,
                width: 320,
                height: 180,
                sources: ["media/v.mp4"],
                ranges: [(0, 0)],
                pressable: true),
          ],
        ),
      ]))["OEBPS/page0.xhtml"]!;
      var hits = XmlDocument.parse(page).findAllElements("button").toList();
      var speaker =
          hits.firstWhere((a) => a.getAttribute("data-target") == "s");
      var film = hits.firstWhere((a) => a.getAttribute("data-target") == "v");
      expect(speaker.getAttribute("class"), "hit speaker");
      expect(speaker.getAttribute("style"), contains("border-radius:20.00px"));
      expect(film.getAttribute("class"), "hit");
      expect(film.getAttribute("style"), isNot(contains("border-radius")));
      // The ring is a speaker's alone: no rule rings every press that plays.
      expect(page, isNot(contains(".hit.on {")));
      expect(RegExp(r"box-shadow").allMatches(page), hasLength(1));
      expect(page, contains(".hit.speaker.on"));
    });

    // In Apple Books a second press on a speaker stopped it and turned the
    // page: the press was a link going nowhere, and the tap reached the page.
    test("a press is a button that keeps its touch to itself", () async {
      var bytes = book();
      var page = XmlDocument.parse(unzip(bytes)["OEBPS/page0.xhtml"]!);
      expect(
          page
              .findAllElements("a")
              .where((a) => a.getAttribute("data-act") != null),
          isEmpty,
          reason: "no link that goes nowhere");
      var press = page.findAllElements("button").first;
      expect(press.getAttribute("type"), "button");
      var script = utf8.decode(ZipDecoder()
          .decodeBytes(bytes)
          .files
          .firstWhere((f) => f.name == "OEBPS/media.js")
          .content);
      expect(script, contains('addEventListener("touchend"'));
      expect(script, contains("e.stopPropagation()"));
      expect(script, contains("e.preventDefault()"));
    });

    // The canvas draws a video's big play button into the page's picture,
    // and the video laid over the picture covered it.
    test("a video without controls draws its own play button, if it has one",
        () {
      EpubMedia film({required bool button}) => EpubMedia(
          id: "v",
          video: true,
          width: 400,
          height: 200,
          sources: const ["media/v.mp4"],
          ranges: const [(0, 0)],
          pressable: true,
          playButton: button);
      String pageWith(EpubMedia m) =>
          unzip(writeEpub(title: "Play", interactive: true, pages: [
            EpubPage(
                png: png(), width: 800, height: 600, title: "One", media: [m]),
          ]))["OEBPS/page0.xhtml"]!;

      var shown = XmlDocument.parse(pageWith(film(button: true)));
      var disc = shown
          .findAllElements("span")
          .firstWhere((s) => s.getAttribute("class") == "play");
      expect(disc.getAttribute("style"), contains("width:48.00px"),
          reason: "a quarter of the shorter side, as on the canvas");
      expect(pageWith(film(button: true)), contains(".hit.on .play"),
          reason: "and gone while it plays");

      var none = XmlDocument.parse(pageWith(film(button: false)));
      expect(
          none
              .findAllElements("span")
              .where((s) => s.getAttribute("class") == "play"),
          isEmpty);
    });

    test("a video sits where it was, turned as it was, with its controls", () {
      var page = unzip(book())["OEBPS/page0.xhtml"]!;
      var video = XmlDocument.parse(page)
          .findAllElements("video")
          .firstWhere((v) => v.getAttribute("id") == "m-v");
      expect(video.getAttribute("style"), contains("left:100.00px"));
      expect(video.getAttribute("style"), contains("rotate(5.00deg)"));
      expect(video.getAttribute("controls"), "controls");
      expect(video.getAttribute("poster"), "media/p.png");
    });

    test("files are carried once and listed, and only playing pages script",
        () {
      var bytes = book();
      var all = names(bytes);
      expect(all.where((n) => n == "OEBPS/media/a.m4a"), hasLength(1));
      var opf = unzip(bytes)["OEBPS/content.opf"]!;
      expect(opf, contains('href="media/a.m4a" media-type="audio/mp4"'));
      expect(
          opf, contains('href="media.js" media-type="application/javascript"'));
      expect(
          opf,
          contains('id="page0" href="page0.xhtml" '
              'media-type="application/xhtml+xml" properties="scripted"'));
      expect(
          opf,
          contains('id="page2" href="page2.xhtml" '
              'media-type="application/xhtml+xml"/>'));
      expect(unzip(bytes)["OEBPS/page2.xhtml"], isNot(contains("media.js")));
    });

    test("a plain EPUB carries none of it", () {
      var all = names(book(interactive: false));
      expect(all.where((n) => n.startsWith("OEBPS/media")), isEmpty);
      expect(all, isNot(contains("OEBPS/media.js")));
    });

    // Readers run old engines, and a syntax error in the script is silence
    // on every page. Node parses it where Node is here.
    test("the script parses", () async {
      var node = Process.runSync("which", ["node"]).stdout.toString().trim();
      if (node.isEmpty) return markTestSkipped("node is not installed");
      var dir = await Directory.systemTemp.createTemp("epub_script");
      addTearDown(() => dir.delete(recursive: true));
      var script = ZipDecoder()
          .decodeBytes(book())
          .files
          .firstWhere((f) => f.name == "OEBPS/media.js");
      var file = File(path.join(dir.path, "media.js"));
      await file.writeAsBytes(script.content);
      var run = await Process.run(node, ["--check", file.path]);
      expect(run.exitCode, 0, reason: "${run.stderr}");
    });
  });

  test("Play or pause is one button, in the editor and saved", () {
    var c = CanvasController(const CanvasDocument(frames: 24));
    addTearDown(c.dispose);
    const press = ButtonAction(kind: ButtonActionKind.togglePlay);
    c.runButtonAction(press);
    expect(c.playing, isTrue);
    c.runButtonAction(press);
    expect(c.playing, isFalse);
    expect(ButtonAction.fromJson(press.toJson()).kind,
        ButtonActionKind.togglePlay);
  });

  test("a Go-to-a-scene button still knows its scene after a restart", () {
    // The scene was left out of the saved action -- only an element target
    // was written -- so every such button came back pointing nowhere.
    var doc = CanvasDocument(scenes: [
      const CanvasScene(id: "front", name: "Front cover"),
      CanvasScene(id: "inside", name: "Inside", elements: [
        ButtonElement(
            const ElementBase(id: "b", x: 10, y: 10, width: 80, height: 20),
            action: const ButtonAction(
                kind: ButtonActionKind.goToScene, elementId: "front")),
      ]),
    ]);
    var back = CanvasDocument.fromJson(
        jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
    var button = back.scenes[1].elements.single as ButtonElement;
    expect(button.action.kind, ButtonActionKind.goToScene);
    expect(button.action.elementId, "front");
    expect(back.sceneIndexNamed(button.action.elementId), 0);
  });

  test("a video a reader can show as it is, and one it cannot", () {
    var plain = VideoElement(const ElementBase(id: "v"));
    expect(plainVideo(plain), isTrue);
    expect(plainVideo(plain.copyWith(key: const ChromaKey(on: true))), isFalse,
        reason: "a green screen is the renderer's to take out");
    expect(
        plainVideo(plain.copyWith(look: plain.look.copyWith(saturation: 0.2))),
        isFalse);
  });

  group("the book", () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas_epub_media");
      CanvasStorage.rootOverride = root.path;
    });

    tearDown(() async {
      CanvasStorage.rootOverride = null;
      if (await root.exists()) await root.delete(recursive: true);
    });

    // The hotspots were placed in design units, and the page picture is in
    // export pixels. On a canvas exported at twice its design size, a link
    // sat over the top-left quarter of the button it belonged to.
    testWidgets("a link sits over its button whatever size the page is",
        (tester) async {
      await tester.runAsync(() async {
        var doc = CanvasDocument(
          size: const CanvasSize(
              ratio: CanvasRatio.wide, width: 400, exportWidth: 800),
          scenes: [
            CanvasScene(id: "one", elements: [
              ButtonElement(
                  const ElementBase(
                      id: "b", x: 100, y: 50, width: 80, height: 20),
                  action: const ButtonAction(
                      kind: ButtonActionKind.openLink,
                      url: "https://example.com")),
            ]),
          ],
        );
        var export =
            (await renderDocument(doc, as: DocumentAs.interactiveEpub))!;
        var page = unzip(export.data)["OEBPS/page0.xhtml"]!;
        expect(
            page,
            contains("left:200.00px;top:100.00px;"
                "width:160.00px;height:40.00px"));
      });
    });

    // A book's navigation lives on the master, and the master's buttons were
    // left out: drawn on every page, pressable on none.
    testWidgets("a master's Go to a scene button works on every page",
        (tester) async {
      await tester.runAsync(() async {
        var doc = CanvasDocument(
          size: const CanvasSize(ratio: CanvasRatio.wide, width: 400),
          scenes: const [
            CanvasScene(id: "one"),
            CanvasScene(id: "two"),
            CanvasScene(id: "end", name: "The end"),
          ],
          master: CanvasScene(id: "m", elements: [
            ButtonElement(
                const ElementBase(
                    id: "b", x: 300, y: 10, width: 80, height: 20),
                action: const ButtonAction(
                    kind: ButtonActionKind.goToScene, elementId: "end")),
          ]),
          masterOn: true,
        );
        var export =
            (await renderDocument(doc, as: DocumentAs.interactiveEpub))!;
        var text = unzip(export.data);
        for (var i in [0, 1]) {
          var page = XmlDocument.parse(text["OEBPS/page$i.xhtml"]!);
          var link = page
              .findAllElements("a")
              .firstWhere((a) => a.getAttribute("href") == "page2.xhtml");
          expect(link.getAttribute("data-go"), "page",
              reason: "followed on the touch, not left to the reader");
          expect(link.findElements("span"), isNotEmpty,
              reason: "something in it to tap");
          expect(
              text["OEBPS/page$i.xhtml"], contains('<script src="media.js">'),
              reason: "the script that follows it, on a page with no media");
        }
        expect(
            XmlDocument.parse(text["OEBPS/page2.xhtml"]!)
                .findAllElements("a")
                .where((a) => a.getAttribute("href") == "page2.xhtml"),
            isEmpty,
            reason: "no link from a page to itself");
      });
    });

    // The real thing, with a real ffmpeg: a speaker to press on the first
    // page, a video on the timeline of the second.
    testWidgets("carries its sound, and plays a timeline video in step",
        (tester) async {
      // Looked up inside runAsync: it runs a process, and real I/O outside it
      // never finishes in a widget test. It only ever worked here because an
      // earlier test in the file had looked it up already.
      var ffmpeg = await tester.runAsync(ffmpegPath);
      if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
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
          frameRate: 25,
          scenes: [
            CanvasScene(id: "one", frames: 25, elements: [
              AudioElement(
                  const ElementBase(
                      id: "s", x: 10, y: 10, width: 40, height: 40),
                  clip: MediaClip(
                      playlist: [MediaSource(assetId: toneId, length: 2)])),
            ]),
            CanvasScene(id: "two", frames: 25, elements: [
              VideoElement(const ElementBase(id: "v", width: 160, height: 90),
                  clip: MediaClip(playlist: [
                    MediaSource(
                        assetId: talkId,
                        length: 1,
                        width: 160,
                        height: 120,
                        fps: 25),
                  ], timed: true)),
            ]),
          ],
        );
        var export =
            (await renderDocument(doc, as: DocumentAs.interactiveEpub))!;
        var all = names(export.data);
        var stem = path.basenameWithoutExtension(toneId);
        expect(all, contains("OEBPS/media/$stem.m4a"),
            reason: "the tone, as AAC a reader plays");
        expect(all, isNot(contains("OEBPS/media/page1.mp4")),
            reason: "the page with a timeline is laid out, not filmed");
        var clip = path.basenameWithoutExtension(talkId);
        expect(all, contains("OEBPS/media/$clip.mp4"),
            reason: "the video itself, as H.264 a reader plays");
        var text = unzip(export.data);
        expect(text["OEBPS/page0.xhtml"], contains('<audio id="m-s"'));
        for (var entry in text.entries) {
          if (entry.key.endsWith(".xhtml")) {
            expect(() => XmlDocument.parse(entry.value), returnsNormally,
                reason: entry.key);
          }
        }
        // The video is the reader's own, in its layer, following the page's
        // playhead from frame 0 -- silent, with no controls of its own.
        var page = XmlDocument.parse(text["OEBPS/page1.xhtml"]!);
        var layer = page.descendantElements
            .firstWhere((e) => e.getAttribute("id") == "l-v");
        var video = layer.findElements("video").single;
        expect(video.getAttribute("data-at"), "0");
        expect(video.getAttribute("data-spans"), "1.0");
        expect(video.getAttribute("muted"), "muted");
        expect(video.getAttribute("controls"), isNull);
        var stage = page.descendantElements
            .firstWhere((e) => e.getAttribute("id") == "stage");
        expect(stage.getAttribute("data-autoplay"), "true");
      });
    });
  });
}
