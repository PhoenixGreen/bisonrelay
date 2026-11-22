import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/ui/controller/view_types.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_transform.dart';

// canvas_stage_view_unit_test.dart is where the stage puts the page, asked of
// StageTransform with no stage, controller or widget: sizes, the fit, the
// zoom and the spread are all it is made from. Each expected number is the
// stage's own sum worked by hand; the margin round the page is 24 pixels.

const _near = 1e-6;

/// _rect checks [actual] against left, top, width and height.
void _rect(Rect actual, double left, double top, double width, double height) {
  expect(actual.left, closeTo(left, _near), reason: "left of $actual");
  expect(actual.top, closeTo(top, _near), reason: "top of $actual");
  expect(actual.width, closeTo(width, _near), reason: "width of $actual");
  expect(actual.height, closeTo(height, _near), reason: "height of $actual");
}

/// _point checks [actual] against [x] and [y].
void _point(Offset actual, double x, double y) {
  expect(actual.dx, closeTo(x, _near), reason: "x of $actual");
  expect(actual.dy, closeTo(y, _near), reason: "y of $actual");
}

/// _laidOut is [view] with its viewport the content size it asks for, as the
/// stage's layout makes it.
StageTransform _laidOut(StageTransform view) => StageTransform(
      visible: view.visible,
      viewport: view.contentSize,
      page: view.page,
      fit: view.fit,
      zoom: view.zoom,
      spread: view.spread,
      facingOnLeft: view.facingOnLeft,
      overspill: view.overspill,
      level: view.level,
    );

void main() {
  test("a page fitted whole in a window wider than it is held by its height",
      () {
    // 800x600 in 1200x700: by width (1200-48)/800 = 1.44, by height
    // (700-48)/600; the smaller wins.
    var view = const StageTransform(
        visible: Size(1200, 700),
        viewport: Size(1200, 700),
        page: Size(800, 600));
    expect(view.fitScale, closeTo(652 / 600, _near));
    expect(view.scale, closeTo(652 / 600, _near));
    _rect(view.pageRect, 600 - 800 * 652 / 600 / 2, 24, 800 * 652 / 600, 652);
    _point(view.origin, view.pageRect.left, 24);
    expect(view.contentSize, const Size(1200, 700));
    expect(view.viewRect, view.pageRect);
  });

  test("a page fitted whole in a window taller than it is held by its width",
      () {
    // 800x600 in 900x1000: by width (900-48)/800 = 1.065.
    var view = const StageTransform(
        visible: Size(900, 1000),
        viewport: Size(900, 1000),
        page: Size(800, 600));
    expect(view.scale, closeTo(1.065, _near));
    _rect(view.pageRect, 24, 500 - 639 / 2, 852, 639);
  });

  test("fitted to width, a tall page is as wide as the window and scrolls", () {
    // 600x1200 in 1000x700: (1000-48)/600, the height ignored, so the content
    // is 1904 tall plus the margins and the viewport scrolls down it.
    var view = _laidOut(const StageTransform(
        visible: Size(1000, 700),
        viewport: Size.zero,
        page: Size(600, 1200),
        fit: CanvasFit.width));
    expect(view.scale, closeTo(952 / 600, _near));
    expect(view.viewport.width, closeTo(1000, _near));
    expect(view.viewport.height, closeTo(1952, _near));
    _rect(view.pageRect, 24, 24, 952, 1904);
    // Centred: the page's middle is (500, 976), the window's (500, 350).
    _point(view.scrollFor(Offset.zero), 0, 626);
    _point(view.panAt(const Offset(0, 626)), 0, 0);
    _point(view.panScrolledTo(const Offset(0, 626)), 0, 0);
    // Past its range, the scroll stops at the end.
    _point(view.scrollFor(const Offset(0, -5000)), 0, 1952 - 700);
  });

  test("zoomed in, the content is larger than the window, with room to move",
      () {
    // The 800x600 page at twice its fit is 1738.67 x 1304; zoomed, half a
    // window more each way: max(w, 2*visible - w) + visible.
    var view = _laidOut(const StageTransform(
        visible: Size(1200, 700),
        viewport: Size.zero,
        page: Size(800, 600),
        zoom: 2));
    var s = 2 * 652 / 600;
    expect(view.scale, closeTo(s, _near));
    var wide = 800 * s + 48;
    var tall = 600 * s + 48;
    expect(view.contentSize.width, closeTo(wide + 1200, _near));
    expect(view.contentSize.height, closeTo(tall + 700, _near));
    _rect(view.pageRect, (wide + 1200) / 2 - 400 * s,
        (tall + 700) / 2 - 300 * s, 800 * s, 600 * s);
  });

  test("a stage point to the document and back is the same point", () {
    for (var fit in CanvasFit.values) {
      for (var zoom in [0.25, 0.5, 1.0, 1.7, 3.0, 8.0]) {
        var view = _laidOut(StageTransform(
            visible: const Size(1100, 640),
            viewport: Size.zero,
            page: const Size(1920, 1080),
            fit: fit,
            zoom: zoom));
        for (var p in const [
          Offset(0, 0),
          Offset(123.5, 456.25),
          Offset(-40, 900),
          Offset(1100, 640),
        ]) {
          var back = view.toStage(view.toDocument(p));
          _point(back, p.dx, p.dy);
        }
        // And a document point to the stage and back.
        var doc = const Offset(960, 540);
        _point(view.toDocument(view.toStage(doc)), 960, 540);
        expect(
            view.toDocumentLength(view.toStageLength(37)), closeTo(37, _near));
      }
    }
  });

  test("a document rect on the stage moves its corner and scales its size", () {
    // The 800x600 page in 1200x700: origin (165.33, 24), scale 652/600.
    var view = const StageTransform(
        visible: Size(1200, 700),
        viewport: Size(1200, 700),
        page: Size(800, 600));
    var s = 652 / 600;
    var left = 600 - 400 * s;
    var r = view.toStageRect(const Rect.fromLTWH(100, 50, 200, 100));
    _rect(r, left + 100 * s, 24 + 50 * s, 200 * s, 100 * s);
    _rect(view.toDocumentRect(r), 100, 50, 200, 100);
    expect(view.toDocumentLength(s * 10), closeTo(10, _near));
  });

  test("with no scale yet, a stage length is divided by one", () {
    // A zoom of nothing: the guard keeps the sums finite.
    var view = const StageTransform(
        visible: Size(1200, 700),
        viewport: Size(1200, 700),
        page: Size(800, 600),
        zoom: 0);
    expect(view.scale, 0);
    expect(view.scaleOrOne, 1);
    expect(view.toDocumentLength(5), 5);
    // Before layout the window is empty: the fit falls back to 1.
    var unlaid = const StageTransform(
        visible: Size.zero, viewport: Size.zero, page: Size(800, 600));
    expect(unlaid.fitScale, 1);
    expect(unlaid.contentSize, Size.zero);
  });

  test("a spread with this page on the left keeps its half, the leaf beside",
      () {
    // Two 400x600 leaves across 1200x700: (1200-48)/800 by width, the height
    // the smaller, 652/600; the pair centred, this page its left half.
    var view = const StageTransform(
        visible: Size(1200, 700),
        viewport: Size(1200, 700),
        page: Size(400, 600),
        spread: true,
        facingOnLeft: true);
    var s = 652 / 600;
    expect(view.scale, closeTo(s, _near));
    _rect(view.pageRect, 600 - 400 * s, 24, 400 * s, 652);
    _rect(view.viewRect, 600 - 400 * s, 24, 800 * s, 652);
    expect(view.onFacingPage(const Offset(700, 350)), isTrue);
    expect(view.onFacingPage(const Offset(500, 350)), isFalse);
    // Above the page is not on the leaf.
    expect(view.onFacingPage(const Offset(700, 10)), isFalse);
  });

  test("a spread with this page on the right has the leaf to its left", () {
    var view = const StageTransform(
        visible: Size(1200, 700),
        viewport: Size(1200, 700),
        page: Size(400, 600),
        spread: true);
    var s = 652 / 600;
    _rect(view.pageRect, 600, 24, 400 * s, 652);
    _rect(view.viewRect, 600 - 400 * s, 24, 800 * s, 652);
    expect(view.onFacingPage(const Offset(500, 350)), isTrue);
    expect(view.onFacingPage(const Offset(700, 350)), isFalse);
    // No spread, no leaf.
    var alone = const StageTransform(
        visible: Size(1200, 700),
        viewport: Size(1200, 700),
        page: Size(400, 600));
    expect(alone.onFacingPage(const Offset(100, 350)), isFalse);
  });

  test("the overspill shrinks the page to leave the world past it in view", () {
    // The fit is divided by 1 + 2 * 0.12, so the page and its spill fill
    // what the page alone did.
    var view = const StageTransform(
        visible: Size(1200, 700),
        viewport: Size(1200, 700),
        page: Size(800, 600),
        overspill: true);
    var s = 652 / 600 / 1.24;
    expect(view.scale, closeTo(s, _near));
    _rect(view.pageRect, 600 - 400 * s, 350 - 300 * s, 800 * s, 600 * s);
    _rect(view.viewRect, 600 - 400 * s * 1.24, 24, 800 * s * 1.24, 652);
  });

  test("a game's level past the page widens the content and what is drawn", () {
    // The level reaches 400 past the right edge and 100 above: each side
    // gets as much room as the far side, so the page stays centred.
    var level = const Rect.fromLTRB(-200, -100, 1200, 600);
    var view = _laidOut(StageTransform(
        visible: const Size(1200, 700),
        viewport: Size.zero,
        page: const Size(800, 600),
        level: level));
    var s = 652 / 600;
    expect(view.levelShown, isTrue);
    var wide = 800 * s + 400 * s * 2 + 48;
    var tall = 600 * s + 100 * s * 2 + 48;
    expect(view.contentSize.width, closeTo(wide, _near));
    expect(view.contentSize.height, closeTo(tall, _near));
    var origin = Offset(wide / 2 - 400 * s, tall / 2 - 300 * s);
    _point(view.origin, origin.dx, origin.dy);
    _rect(view.viewRect, origin.dx - 200 * s, origin.dy - 100 * s, 1400 * s,
        700 * s);
  });

  test("made from a document, a lone scene has no spread and its own size", () {
    var document = CanvasDocument(frames: 10, elements: const []);
    var view = StageTransform.of(document,
        fit: CanvasFit.whole,
        zoom: 1.5,
        overspill: false,
        previewing: true,
        visible: const Size(1000, 800),
        viewport: const Size(1000, 800));
    expect(view.page, document.size.size);
    expect(view.spread, isFalse);
    expect(view.facingOnLeft, isFalse);
    expect(view.zoom, 1.5);
    expect(view.level, isNull);
  });
}
