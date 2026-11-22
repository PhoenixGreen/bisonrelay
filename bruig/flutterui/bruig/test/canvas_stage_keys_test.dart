import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_keys.dart';

// canvas_stage_keys_test.dart checks the table of the Canvas page's keys as
// a table: that each line can be reached, says what it does, and that every
// tool's letter is in it. What the keys do on the canvas is checked where
// the canvas is: the keyboard groups of canvas_stage_view_test.dart and the
// letters' tests in the picture, drawing and 3D stage tests.

void main() {
  /// covers is whether an earlier line [a] takes every press of [b]'s key
  /// [key] wherever [b] is heard: [a] always applies, has the key, needs no
  /// modifier [b] does not, and is heard wherever [b] is.
  bool covers(CanvasShortcut a, CanvasShortcut b, LogicalKeyboardKey key) =>
      identical(a.when, always) &&
      a.keys.contains(key) &&
      (a.command == null || a.command == b.command) &&
      (a.shift == null || a.shift == b.shift) &&
      (a.alt == null || a.alt == b.alt) &&
      (a.reach == b.reach || a.reach == ShortcutReach.page);

  test("no line is hidden behind an earlier one that always applies", () {
    for (var (i, line) in canvasShortcuts.indexed) {
      for (var key in line.keys) {
        var before = canvasShortcuts.take(i).where((a) => covers(a, line, key));
        expect(before, isEmpty,
            reason: "\"${line.does}\" can never be reached by ${key.keyLabel}");
      }
    }
  });

  test("every line says what it does, and has a key", () {
    for (var line in canvasShortcuts) {
      expect(line.does.trim(), isNotEmpty);
      expect(line.keys, isNotEmpty, reason: line.does);
    }
  });

  test("the page's lines come after the canvas's and the transport's", () {
    // So that the canvas, play bar or timeline has the first say when it
    // has the keyboard, as the page's handler only hears what they leave.
    var firstPage =
        canvasShortcuts.indexWhere((line) => line.reach == ShortcutReach.page);
    expect(firstPage, greaterThan(0));
    expect(
        canvasShortcuts
            .skip(firstPage)
            .where((line) => line.reach != ShortcutReach.page),
        isEmpty);
  });

  group("the tools' letters", () {
    LogicalKeyboardKey letter(String key) =>
        LogicalKeyboardKey.findKeyByKeyId(key.toLowerCase().codeUnitAt(0))!;

    /// linesFor is the canvas's lines for [key] that say [does].
    Iterable<CanvasShortcut> linesFor(String key, String does) =>
        canvasShortcuts.where((line) =>
            line.reach == ShortcutReach.canvas &&
            line.keys.contains(letter(key)) &&
            line.does == does);

    test("every tool with a letter has its line", () {
      for (var t in ImageTool.values) {
        expect(linesFor(t.key, "Picture: ${t.label}"), hasLength(1),
            reason: t.label);
      }
      for (var t in StageTool.values) {
        expect(linesFor(t.key, "3D stage: ${t.label}"), hasLength(1),
            reason: t.label);
      }
      for (var t in VectorTool.values) {
        if (t.key case var key?) {
          expect(linesFor(key, "Drawing: ${t.label}"), hasLength(1),
              reason: t.label);
        }
      }
    });

    test("no two tools of one kind share a letter", () {
      Iterable<String> letters(Iterable<String?> keys) => keys.nonNulls;
      for (var keys in [
        letters(ImageTool.values.map((t) => t.key)),
        letters(StageTool.values.map((t) => t.key)),
        letters(VectorTool.values.map((t) => t.key)),
      ]) {
        expect(keys.toSet(), hasLength(keys.length), reason: "$keys");
        for (var k in keys) {
          expect(k, matches(RegExp(r"^[A-Z]$")), reason: "one letter");
        }
      }
    });
  });
}
