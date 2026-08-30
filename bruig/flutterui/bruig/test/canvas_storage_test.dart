import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// canvas_storage_test.dart is about the security boundary and the file
// handling behind it.
//
// Every name that reaches the filesystem here came out of a text field, so the
// sanitiser is the whole defence and is checked against a real directory
// rather than a stub -- a stubbed filesystem would happily agree with whatever
// the code did, including writing outside the library.

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_storage_test");
    CanvasStorage.rootOverride = root.path;
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  group("sanitizeName", () {
    test("keeps ordinary names", () {
      expect(CanvasStorage.sanitizeName("Match plan"), "Match plan");
      expect(CanvasStorage.sanitizeName("Week 3 (final)"), "Week 3 (final)");
      expect(CanvasStorage.sanitizeName("chart_2026-01"), "chart_2026-01");
    });

    test("cannot escape the library", () {
      // The one that matters. A name is a single path segment or it is
      // nothing; separators and dot-dot are removed rather than blacklisted,
      // because there are always more forms of the latter.
      for (var attack in [
        "../../config",
        "..",
        "../secrets",
        "a/b",
        r"a\b",
        "/etc/passwd",
        "....//....//x",
      ]) {
        var clean = CanvasStorage.sanitizeName(attack);
        if (clean == null) continue;
        expect(clean.contains("/"), isFalse, reason: attack);
        expect(clean.contains(r"\"), isFalse, reason: attack);
        expect(clean.startsWith("."), isFalse, reason: attack);
        expect(clean, isNot(".."), reason: attack);
      }
    });

    test("refuses names with nothing usable left", () {
      expect(CanvasStorage.sanitizeName(""), isNull);
      expect(CanvasStorage.sanitizeName("   "), isNull);
      expect(CanvasStorage.sanitizeName("..."), isNull);
      expect(CanvasStorage.sanitizeName("///"), isNull);
    });

    test("bounds the length", () {
      var long = CanvasStorage.sanitizeName("a" * 500);
      expect(long!.length, lessThanOrEqualTo(maxNameLength));
    });

    test("collapses the runs substitution creates", () {
      // "a???b" should be "a-b" rather than "a---b", or every name with
      // punctuation in it becomes a row of dashes.
      expect(CanvasStorage.sanitizeName("a???b"), "a-b");
    });
  });

  test("a saved canvas comes back", () async {
    var document = const CanvasDocument(title: "Plan", frames: 12);
    expect(await CanvasStorage.save("", "Plan", document), isTrue);

    var back = await CanvasStorage.load("", "Plan");
    expect(back, isNotNull);
    expect(back!.title, "Plan");
    expect(back.frames, 12);
  });

  test("a canvas is written into the folder it was given", () async {
    await CanvasStorage.createFolder("Matches");
    expect(await CanvasStorage.save("Matches", "One", const CanvasDocument()),
        isTrue);
    expect(
        File(path.join(root.path, "Canvas", "Matches", "One$canvasExtension"))
            .existsSync(),
        isTrue);

    var top = await CanvasStorage.list("");
    expect(top.where((e) => e.isFolder).map((e) => e.name), contains("Matches"));
    // The document is inside the folder, not loose at the top level.
    expect(top.where((e) => !e.isFolder), isEmpty);

    var inside = await CanvasStorage.list("Matches");
    expect(inside.single.name, "One");
  });

  test("a save refuses a name the sanitiser would have changed", () async {
    // Refuses rather than corrects, so a save that would have gone somewhere
    // unexpected does not silently go somewhere else instead.
    expect(await CanvasStorage.save("", "../escape", const CanvasDocument()),
        isFalse);
    expect(await CanvasStorage.save("../up", "ok", const CanvasDocument()),
        isFalse);
  });

  test("a half-written file never replaces a good one", () async {
    // The save goes to a temporary file and is renamed, which is atomic within
    // a directory. What this checks is the observable consequence: no stray
    // temporary is left behind for the listing to show.
    await CanvasStorage.save("", "Doc", const CanvasDocument(title: "Doc"));
    var files = Directory(path.join(root.path, "Canvas"))
        .listSync()
        .whereType<File>()
        .map((f) => path.basename(f.path));
    expect(files, ["Doc$canvasExtension"]);
  });

  test("renaming refuses to write over an existing canvas", () async {
    await CanvasStorage.save("", "A", const CanvasDocument(title: "A"));
    await CanvasStorage.save("", "B", const CanvasDocument(title: "B"));

    expect(await CanvasStorage.rename("", "A", "B"), isFalse);
    expect((await CanvasStorage.load("", "B"))!.title, "B");

    expect(await CanvasStorage.rename("", "A", "C"), isTrue);
    expect(await CanvasStorage.exists("", "A"), isFalse);
    expect((await CanvasStorage.load("", "C"))!.title, "A");
  });

  test("uniqueName walks past the names in use", () async {
    await CanvasStorage.save("", "Plan", const CanvasDocument());
    expect(await CanvasStorage.uniqueName("", "Plan"), "Plan 2");
    await CanvasStorage.save("", "Plan 2", const CanvasDocument());
    expect(await CanvasStorage.uniqueName("", "Plan"), "Plan 3");
  });

  test("a folder with canvases in it is not deleted by accident", () async {
    await CanvasStorage.createFolder("Keep");
    await CanvasStorage.save("Keep", "Important", const CanvasDocument());

    expect(await CanvasStorage.deleteFolder("Keep"), isFalse);
    expect(await CanvasStorage.exists("Keep", "Important"), isTrue);
  });

  test("an empty folder deletes", () async {
    await CanvasStorage.createFolder("Empty");
    expect(await CanvasStorage.deleteFolder("Empty"), isTrue);
    expect((await CanvasStorage.list("")).where((e) => e.isFolder), isEmpty);
  });

  test("a damaged file loads as null and stays on disk", () async {
    var file = File(path.join(
        root.path, "Canvas", "Broken$canvasExtension"));
    await file.parent.create(recursive: true);
    await file.writeAsString("{ this is not json");

    expect(await CanvasStorage.load("", "Broken"), isNull);
    // Still listed and still there. Whatever the reader had is not thrown away
    // because this build could not read it.
    expect(await file.exists(), isTrue);
    expect((await CanvasStorage.list("")).map((e) => e.name),
        contains("Broken"));
  });

  test("dotted files stay out of the listing", () async {
    await CanvasStorage.save("", "Real", const CanvasDocument());
    await File(path.join(root.path, "Canvas", ".hidden$canvasExtension"))
        .writeAsString("{}");
    expect((await CanvasStorage.list("")).map((e) => e.name), ["Real"]);
  });

  test("a saved order is honoured, and forgives what has gone", () async {
    for (var name in ["A", "B", "C"]) {
      await CanvasStorage.save("", name, const CanvasDocument());
    }
    await CanvasStorage.saveOrder("", ["C", "A", "B"]);
    expect((await CanvasStorage.list("")).map((e) => e.name), ["C", "A", "B"]);

    // A file deleted outside the app drops out of the order rather than
    // shifting everything after it.
    await CanvasStorage.delete("", "A");
    expect((await CanvasStorage.list("")).map((e) => e.name), ["C", "B"]);

    // Anything the order does not mention follows what it does.
    await CanvasStorage.save("", "D", const CanvasDocument());
    expect((await CanvasStorage.list("")).map((e) => e.name), ["C", "B", "D"]);
  });
}
