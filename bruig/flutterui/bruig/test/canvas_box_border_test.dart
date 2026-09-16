import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_box_border_test.dart is a box's border, one side at a time.
//
// The same shape the padding and the corners already had, and for the same
// reason: a rule under a heading, a bar down the left of a quote, a box open
// on one side. All four even is what almost every box wants and is the one
// field; the rest are there for the boxes that are not boxes.

const int _w = 120, _h = 100;
const Rect _rect = Rect.fromLTWH(10, 10, 100, 80);

/// _edges is how much border ink lands on each side of the box.
Future<({int left, int top, int right, int bottom})> _edges(BoxSpec box) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 100),
      Paint()..color = const Color(0xFF000000));
  paintBox(canvas, _rect, box);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();

  int ink(Rect strip) {
    var n = 0;
    for (var y = strip.top.round(); y < strip.bottom.round(); y++) {
      for (var x = strip.left.round(); x < strip.right.round(); x++) {
        var p = bytes.getUint32((y * _w + x) * 4);
        if (((p >> 24) & 0xFF) > 120) n++;
      }
    }
    return n;
  }

  // Strips inside each edge, clear of the corners so that one side's ink is
  // not counted as another's.
  return (
    left: ink(const Rect.fromLTWH(10, 30, 8, 40)),
    top: ink(const Rect.fromLTWH(30, 10, 60, 8)),
    right: ink(const Rect.fromLTWH(102, 30, 8, 40)),
    bottom: ink(const Rect.fromLTWH(30, 82, 60, 8)),
  );
}

void main() {
  testWidgets("an even border is drawn on all four sides", (tester) async {
    late ({int left, int top, int right, int bottom}) e;
    await tester.runAsync(() async {
      e = await _edges(const BoxSpec(
          borderWidth: 4, borderColor: Color(0xFFFFFFFF), padding: 0));
    });
    expect(e.left, greaterThan(100));
    expect(e.top, greaterThan(150));
    expect(e.right, greaterThan(100));
    expect(e.bottom, greaterThan(150));
  });

  testWidgets("and a side on its own is drawn on that side alone",
      (tester) async {
    // A rule under a heading: the bottom and nothing else.
    late ({int left, int top, int right, int bottom}) e;
    await tester.runAsync(() async {
      e = await _edges(const BoxSpec(
          borderWidth: 0, bwB: 4, borderColor: Color(0xFFFFFFFF), padding: 0));
    });
    expect(e.bottom, greaterThan(150));
    expect(e.left, 0);
    expect(e.top, 0);
    expect(e.right, 0);
  });

  testWidgets("and the sides can differ from one another", (tester) async {
    late ({int left, int top, int right, int bottom}) e;
    await tester.runAsync(() async {
      e = await _edges(const BoxSpec(
          borderWidth: 1, bwL: 8, borderColor: Color(0xFFFFFFFF), padding: 0));
    });
    expect(e.left, greaterThan(e.right * 4),
        reason: "a bar down the left of a quote");
    expect(e.right, greaterThan(0), reason: "and a hairline round the rest");
  });

  testWidgets("a border of nothing is no border at all", (tester) async {
    late ({int left, int top, int right, int bottom}) e;
    await tester.runAsync(() async {
      e = await _edges(const BoxSpec(padding: 0));
    });
    expect(e.left + e.top + e.right + e.bottom, 0);
  });

  test("a side that is not set takes the one figure", () {
    const box = BoxSpec(borderWidth: 3);
    expect(box.borders.left, 3);
    expect(box.borders.bottom, 3);
    expect(box.evenBorder, 3);
    expect(box.hasBorder, isTrue);

    // Held as nothing rather than as a copy, so a box with an even border
    // stays even when the one figure changes.
    expect(box.copyWith(borderWidth: 9).borders.top, 9);
  });

  test("and stops taking it once it has its own", () {
    const box = BoxSpec(borderWidth: 3, bwT: 0);
    expect(box.borders.top, 0);
    expect(box.borders.left, 3);
    expect(box.evenBorder, isNull, reason: "so the one field shows blank");
  });

  test("withBorders replaces all four, overrides and all", () {
    // Not copyWith: setting all four sides to one number means forgetting the
    // ones that had their own, and through copyWith they would survive it.
    const box = BoxSpec(borderWidth: 3, bwT: 12);
    var even = box.withBorders(box.borders.withEven(2));
    expect(even.borders.top, 2);
    expect(even.evenBorder, 2);
    expect(even.padding, box.padding, reason: "and nothing else is touched");
  });

  test("a saved box carries the sides only where they were asked for", () {
    expect(const BoxSpec(borderWidth: 2).toJson().containsKey("bwT"), isFalse);

    var sided = const BoxSpec(borderWidth: 2, bwT: 0, bwL: 9);
    var back = BoxSpec.fromJson(sided.toJson());
    expect(back.borders.top, 0);
    expect(back.borders.left, 9);
    expect(back.borders.right, 2, reason: "the two nobody set still follow");
    expect(back.bwR, isNull);
  });

  test("a box with only one side still saves its colour", () {
    // The colour was written only where the one width was above nought, so a
    // box whose border is all on one side saved a width and no colour to draw
    // it in.
    const rule =
        BoxSpec(borderWidth: 0, bwB: 3, borderColor: Color(0xFF00FF00));
    var back = BoxSpec.fromJson(rule.toJson());
    expect(back.borderColor, const Color(0xFF00FF00));
  });
}
