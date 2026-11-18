import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/panel_video.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/panel_reading.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/panel_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'support/canvas_app.dart';

// canvas_panel_reading_test.dart is Panel mode (panel_reading.dart,
// panel_reader.dart): a comic read panel by panel, each page whole and then
// its Layouts' cells in their reading order. Ken, 2026-11-18: "if you build
// a comic ebook a user can go into panel mode and use the page back and
// forward buttons to move through the panels and pages"; the rest of the
// page dimmed, not hidden.

const _page = CanvasSize(ratio: CanvasRatio.a4, width: 1240);

/// _comic is three panels, a over b|c, filling an A4 page.
LayoutElement _comic(String id,
        {List<String> order = const [], List<String> unread = const []}) =>
    LayoutElement(ElementBase(id: id, x: 20, y: 20, width: 1200, height: 1714),
        root: const LayoutNode.cut(
            vertical: false,
            a: LayoutNode.leaf("a"),
            b: LayoutNode.cut(
                vertical: true,
                a: LayoutNode.leaf("b"),
                b: LayoutNode.leaf("c"))),
        cells: const [
          LayoutCell(id: "a"),
          LayoutCell(id: "b"),
          LayoutCell(id: "c")
        ],
        order: order,
        unread: unread);

/// _book is two comic pages and a page with no layout.
CanvasDocument _book() {
  var doc = const CanvasDocument(size: _page);
  return doc.withScenes([
    CanvasScene(id: "p1", name: "One", elements: [_comic("L1")]),
    CanvasScene(id: "p2", name: "Two", elements: [
      _comic("L2", order: ["c", "b"], unread: ["a"])
    ]),
    const CanvasScene(id: "p3", name: "Three"),
  ], at: 0);
}

void main() {
  group("the steps", () {
    test("each page whole, then its panels as they are read", () {
      var steps = panelSteps(_book());
      expect([
        for (var s in steps) (s.scene, s.cell)
      ], [
        (0, null), (0, "a"), (0, "b"), (0, "c"), //
        (1, null), (1, "c"), (1, "b"), // a left out
        (2, null), // no layout: the page alone
      ]);
      expect(hasPanels(_book()), isTrue);
    });

    test("not a layout hidden, docked in a cell, or most of the page", () {
      var doc = const CanvasDocument(size: _page)
          .addElement(_comic("hidden").withBase(visible: false))
          .addElement(_comic("docked").withBase(dock: "x:y"))
          .addElement(LayoutElement(const ElementBase(
              id: "one", x: 10, y: 10, width: 1220, height: 1734)));
      expect(panelSteps(doc).length, 1);
      expect(hasPanels(doc), isFalse);
    });

    test("a panel's view is the page's shape, round it, and on the page", () {
      var size = _page.size;
      for (var s in panelSteps(_book())) {
        var v = panelView(s, size);
        expect(v.width / v.height, closeTo(size.width / size.height, 1e-6));
        expect(v.inflate(0.5).contains(s.focus.topLeft), isTrue);
        expect(v.inflate(0.5).contains(s.focus.bottomRight), isTrue);
        if (v.width <= size.width) {
          expect(v.left, greaterThanOrEqualTo(-1e-6));
          expect(v.right, lessThanOrEqualTo(size.width + 1e-6));
        }
        if (s.whole) expect(v, Offset.zero & size);
      }
      // A lower panel is zoomed in on: smaller than the page.
      var b = panelSteps(_book()).firstWhere((s) => s.cell == "b");
      expect(panelView(b, size).width, lessThan(size.width * 0.8));
    });
  });

  group("the book, panel by panel", () {
    Archive made(List<int> bytes) => ZipDecoder().decodeBytes(bytes);
    String text(Archive a, String name) => utf8
        .decode(a.files.firstWhere((f) => f.name == name).content as List<int>);

    testWidgets("each page followed by its panels, one at a time",
        (tester) async {
      var book = _book().copyWith(
          kind: CanvasKind.pages, pages: const PagesSpec(facing: true));
      var out = await tester.runAsync(
          () => renderDocument(book, as: DocumentAs.epub, panelPages: true));
      var a = made(out!.data);
      var pages = [
        for (var f in a.files)
          if (RegExp(r"^OEBPS/page\d+\.xhtml$").hasMatch(f.name)) f.name
      ];
      // One, its three; Two, its two (one left out); Three alone.
      expect(pages.length, 3 + 3 + 2);
      var nav = text(a, "OEBPS/nav.xhtml");
      expect(nav, contains("One · panel 1 of 3"));
      expect(nav, contains("Two · panel 2 of 2"));
      var opf = text(a, "OEBPS/content.opf");
      expect(opf, isNot(contains("page-spread-left")),
          reason: "no spreads: a panel page stands alone");

      var plain = await tester
          .runAsync(() => renderDocument(book, as: DocumentAs.epub));
      expect(
          made(plain!.data)
              .files
              .where(
                  (f) => f.name.endsWith(".xhtml") && f.name.contains("page"))
              .length,
          3,
          reason: "off, as before");
    });

    testWidgets("a button to a page still goes to that page", (tester) async {
      var doc = _book();
      var scenes = [...doc.allScenes];
      scenes[2] = scenes[2].copyWith(elements: [
        ButtonElement(
            const ElementBase(id: "go", x: 100, y: 100, width: 200, height: 80),
            label: "Back to two",
            action: const ButtonAction(
                kind: ButtonActionKind.goToScene, elementId: "p2")),
      ]);
      doc = doc.withScenes(scenes, at: 0);
      var out = await tester.runAsync(() => renderDocument(doc,
          as: DocumentAs.interactiveEpub, panelPages: true));
      var a = made(out!.data);
      // Page Two is the fifth file: One and its three panels come first.
      expect(text(a, "OEBPS/page7.xhtml"), contains('href="page4.xhtml"'));
    });
  });

  // Ken, 2026-11-18: "can you also use the panel view when exporting a
  // comic as a video file?"
  group("as a video", () {
    test("each page held whole, then a glide to each panel and a hold", () {
      var t = PanelTimeline(panelSteps(_book()), 24, PanelPace.quick);
      // Three pages at 1.5 s, five panels at 2 s, seven moves of 0.5 s.
      expect(t.frames, 3 * 36 + 5 * 48 + 7 * 12);
      expect(t.at(0), (at: 0, from: -1, t: 1.0));
      expect(t.at(35).from, -1, reason: "still the page whole");
      var m = t.at(36);
      expect((m.at, m.from), (1, 0), reason: "on its way to panel one");
      expect(m.t, inExclusiveRange(0, 1));
      expect(t.at(36 + 12).from, -1, reason: "there, and holding");
      expect(t.still(10), isTrue);
      expect(t.still(36), isFalse);
      expect(t.at(t.frames + 50).at, t.steps.length - 1);
    });

    test("its frames are cut from each page, the panel lit", () async {
      var doc = _book();
      var t = PanelTimeline(panelSteps(doc), 24, PanelPace.quick);
      var frames = PanelFrames(doc, t, scale: 0.1);
      addTearDown(frames.dispose);
      var whole = await frames.frame(0);
      var panel = await frames.frame(36 + 12);
      expect((whole.width, whole.height), (frames.width, frames.height));
      var a = await whole.toByteData();
      var b = await panel.toByteData();
      expect(a!.buffer.asUint8List(), isNot(b!.buffer.asUint8List()));
      whole.dispose();
      panel.dispose();
    });

    group("through ffmpeg", () {
      late Directory scratch;
      late File log;
      setUp(() async {
        scratch = await Directory.systemTemp.createTemp("bruig-panel-video");
        log = File(path.join(scratch.path, "args.txt"));
        var script = File(path.join(scratch.path, "ffmpeg"));
        await script.writeAsString("""#!/bin/sh
printf '%s\\n' "\$@" > "${log.path}"
for a in "\$@"; do out="\$a"; done
bytes=\$(cat | wc -c)
printf 'bytes=%s\\n' "\$bytes" >> "${log.path}"
printf '\\x00\\x00\\x00\\x18ftypisom' > "\$out"
""");
        await Process.run("chmod", ["+x", script.path]);
        useFfmpegForTest(script.path);
      });
      tearDown(() async {
        forgetFfmpegForTest();
        await scratch.delete(recursive: true);
      });

      test("every frame of the reading arrives, and no sound", () async {
        var doc = _book().copyWith(frameRate: 1);
        var out = await renderVideo(doc, scale: 0.1, panels: PanelPace.quick);
        expect(out, isNotNull);
        var args = await log.readAsLines();
        expect(args[args.indexOf("-framerate") + 1], "24",
            reason: "a book at a frame a second, read at 24");
        var t = PanelTimeline(panelSteps(doc), 24, PanelPace.quick);
        var sent = args.firstWhere((a) => a.startsWith("bytes="));
        // The frames as drawn: the size reported is made even for the
        // encoder (175 tall here, 174 in the file).
        var f = PanelFrames(doc, t, scale: 0.1);
        expect(out!.height, f.height - 1);
        expect(int.parse(sent.split("=")[1].trim()),
            t.frames * f.width * f.height * 4);
        expect(args, isNot(contains("-map")), reason: "silent");
      });

      test("a canvas with no panels plays as it always has", () async {
        var doc = const CanvasDocument(size: _page, frames: 3);
        var out = await renderVideo(doc, scale: 0.1, panels: PanelPace.quick);
        var sent =
            (await log.readAsLines()).firstWhere((a) => a.startsWith("bytes="));
        expect(out, isNotNull);
        var w = (doc.size.exportSize.width * 0.1).round(),
            h = (doc.size.exportSize.height * 0.1).round();
        expect(
            int.parse(sent.split("=")[1].trim()), doc.playFrames * w * h * 4);
      });
    });
  });

  group("the reader", () {
    Future<PanelReaderState> open(WidgetTester tester,
        {VoidCallback? onClose, int scene = 0}) async {
      setTestScreen(tester, const Size(900, 1000));
      var key = GlobalKey<PanelReaderState>();
      await tester.pumpWidget(canvasApp(PanelReader(
          key: key,
          document: _book(),
          images: CanvasImageStore(),
          scene: scene,
          onClose: onClose)));
      await tester.pumpAndSettle();
      return key.currentState!;
    }

    String where(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey("panelReaderWhere")))
        .data!;

    testWidgets("forward steps through the panels and on to the next page",
        (tester) async {
      var r = await open(tester);
      expect(where(tester), "One · whole page");
      await tester.tap(find.byKey(const ValueKey("panelReaderForward")));
      await tester.pumpAndSettle();
      expect(where(tester), "One · panel 1 of 3");
      for (var _ in [1, 2, 3]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(r.steps[r.at].scene, 1, reason: "on to page two, whole");
      expect(where(tester), "Two · whole page");
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(r.steps[r.at].cell, "c", reason: "in the order set");
      await tester.tap(find.byKey(const ValueKey("panelReaderBack")));
      await tester.pumpAndSettle();
      expect(where(tester), "Two · whole page");
    });

    testWidgets("mid-glide it draws, and a click on the left goes back",
        (tester) async {
      var r = await open(tester, scene: 1);
      expect(r.steps[r.at].scene, 1, reason: "opened on the page asked");
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      var view = tester.getRect(find.byKey(const ValueKey("panelReaderView")));
      await tester.tapAt(view.centerLeft + const Offset(20, 0));
      await tester.pumpAndSettle();
      expect(where(tester), "Two · whole page");
    });

    testWidgets("Escape closes it", (tester) async {
      var closed = 0;
      await open(tester, onClose: () => closed++);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
    });

    testWidgets("the editor's bar opens it on the page being edited",
        (tester) async {
      var c = CanvasController(_book().goToScene(1));
      addTearDown(c.dispose);
      setTestScreen(tester, const Size(1400, 900));
      await tester.pumpWidget(canvasApp(CanvasSettingsBar(
        controller: c,
        onPublish: () {},
        canvasSettingsOpen: false,
        onToggleCanvasSettings: () {},
        guidesOpen: false,
        onToggleGuides: () {},
        timelineOpen: true,
        onToggleTimeline: () {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("readPanels")));
      await tester.pumpAndSettle();
      var r = tester.state<PanelReaderState>(find.byType(PanelReader));
      expect(r.steps[r.at].scene, 1);
      await tester.tap(find.byKey(const ValueKey("panelReaderClose")));
      await tester.pumpAndSettle();
      expect(find.byType(PanelReader), findsNothing);
    });
  });
}
