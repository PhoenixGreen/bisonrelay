import 'dart:convert';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
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

  group("clearing out pictures nothing uses", () {
    test("a picture no saved canvas refers to is deleted", () async {
      // Nothing called sweep at all until now, so a picture dropped into a
      // canvas and then deleted stayed on disk for good -- invisible,
      // unreachable, and counted against nothing.
      var kept = (await CanvasAssets.save(List.filled(64, 7)))!;
      var dropped = (await CanvasAssets.save(List.filled(64, 9)))!;

      await CanvasStorage.save(
          "",
          "Used",
          CanvasDocument(elements: [
            ImageElement(const ElementBase(id: "i", width: 10, height: 10),
                assetId: kept),
          ]));

      expect(await CanvasAssets.load(dropped), isNotNull,
          reason: "still there before the sweep");
      await CanvasAssets.sweepUnused();

      expect(await CanvasAssets.load(kept), isNotNull,
          reason: "the one a canvas still shows");
      expect(await CanvasAssets.load(dropped), isNull,
          reason: "and the one nothing does");
    });

    test("a picture two canvases share survives either being deleted",
        () async {
      // One picture can be used by more than one canvas -- a document
      // duplicated, or an element copied between two of them -- and a sweep
      // that only looked at the open one would break the other.
      var shared = (await CanvasAssets.save(List.filled(64, 3)))!;

      CanvasDocument using() => CanvasDocument(elements: [
            ImageElement(const ElementBase(id: "i", width: 10, height: 10),
                assetId: shared),
          ]);

      await CanvasStorage.save("", "One", using());
      await CanvasStorage.save("", "Two", using());

      await CanvasStorage.delete("", "One");
      await CanvasAssets.sweepUnused();
      expect(await CanvasAssets.load(shared), isNotNull,
          reason: "the other canvas still shows it");

      await CanvasStorage.delete("", "Two");
      await CanvasAssets.sweepUnused();
      expect(await CanvasAssets.load(shared), isNull,
          reason: "and now nothing does");
    });

    test("a canvas inside a folder counts too", () async {
      // The library is one level deep, and a sweep that only walked the top
      // would delete every picture used by a filed canvas.
      var filed = (await CanvasAssets.save(List.filled(64, 5)))!;
      await CanvasStorage.createFolder("Match day");
      await CanvasStorage.save(
          "Match day",
          "Pitch",
          CanvasDocument(elements: [
            ImageElement(const ElementBase(id: "i", width: 10, height: 10),
                assetId: filed),
          ]));

      await CanvasAssets.sweepUnused();
      expect(await CanvasAssets.load(filed), isNotNull);
    });

    test("a background's picture is not forgotten", () async {
      var behind = (await CanvasAssets.save(List.filled(64, 11)))!;
      await CanvasStorage.save(
          "",
          "Backdrop",
          CanvasDocument(
              background: CanvasBackground(imageAssetId: behind)));

      await CanvasAssets.sweepUnused();
      expect(await CanvasAssets.load(behind), isNotNull,
          reason: "the canvas background uses one as much as an element does");
    });
  });

  group("the picture store", () {
    /// png and jpeg are just enough of a header to be recognised.
    List<int> png([int fill = 1]) =>
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(40, fill)];
    List<int> jpeg() => [0xFF, 0xD8, 0xFF, ...List.filled(40, 2)];

    test("the same picture twice is one file", () async {
      // Every import used to write a new random name for identical bytes, so
      // dropping the same photograph into two canvases stored it twice and
      // there was no way to reuse anything.
      var first = await CanvasAssets.save(png());
      var again = await CanvasAssets.save(png());

      expect(first, isNotNull);
      expect(again, first, reason: "the same bytes are the same picture");
    });

    test("different pictures are different files", () async {
      expect(await CanvasAssets.save(png(1)),
          isNot(await CanvasAssets.save(png(9))));
    });

    test("the id carries the format, so the file can be opened", () async {
      // Without one, every picture is a file the operating system cannot
      // preview, name or open.
      expect(await CanvasAssets.save(png()), endsWith(".png"));
      expect(await CanvasAssets.save(jpeg()), endsWith(".jpg"));
    });

    test("the format comes from the bytes, not from a name", () async {
      // A screenshot saved as ".jpg" that is really a PNG is common enough,
      // and the point of the extension is that the file opens.
      var id = await CanvasAssets.save(png());
      expect(id, endsWith(".png"));
    });

    test("a picture stored before any of this still loads", () async {
      // Old ids are random and have no extension, and every saved canvas
      // points at them by name.
      var library = await CanvasStorage.libraryDir();
      var pictures = Directory(path.join(library, "Pictures"));
      await pictures.create(recursive: true);
      await File(path.join(pictures.path, "abcdefghijklmnop"))
          .writeAsBytes(png());

      expect(await CanvasAssets.load("abcdefghijklmnop"), isNotNull);
    });

    test("a store left in the hidden folder is moved, names intact", () async {
      // The names inside are untouched, so every document still resolves.
      var library = await CanvasStorage.libraryDir();
      var old = Directory(path.join(library, ".assets"));
      await old.create(recursive: true);
      await File(path.join(old.path, "qrstuvwxyzabcdef")).writeAsBytes(png());

      // Asking for anything triggers the move.
      expect(await CanvasAssets.load("qrstuvwxyzabcdef"), isNotNull);
      expect(await Directory(path.join(library, "Pictures")).exists(), isTrue);
      expect(await old.exists(), isFalse);
    });

    test("the pictures folder is not offered as a canvas folder", () async {
      // It is a real, visible folder now so that it can be opened and looked
      // at -- which means the listing has to leave it out by name.
      await CanvasAssets.save(png());
      var entries = await CanvasStorage.list("");
      expect(entries.where((e) => e.name == "Pictures"), isEmpty);
    });
  });

  group("reusing a picture", () {
    List<int> png([int fill = 1]) => [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          ...List.filled(40, fill)
        ];

    test("the store can say what is in it, newest first", () async {
      // Without this there was no way to put the same badge on a second
      // canvas except to go and find the file again. The bytes were shared
      // from the beginning; nothing ever showed what was there.
      expect(await CanvasAssets.stored(), isEmpty);

      var first = (await CanvasAssets.save(png(1)))!;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var second = (await CanvasAssets.save(png(2)))!;

      var stored = await CanvasAssets.stored();
      expect(stored, hasLength(2));
      expect(stored.first, second, reason: "the one added most recently");
      expect(stored, contains(first));
    });

    test("the same picture added twice is listed once", () async {
      await CanvasAssets.save(png(3));
      await CanvasAssets.save(png(3));
      expect(await CanvasAssets.stored(), hasLength(1));
    });

    test("a stray file is not offered as a picture", () async {
      // The store is a visible folder now, so somebody may well drop something
      // in it -- and a name that is not one of ours is not one of ours.
      var library = await CanvasStorage.libraryDir();
      var pictures = Directory(path.join(library, "Pictures"));
      await pictures.create(recursive: true);
      await File(path.join(pictures.path, "notes.txt")).writeAsString("hello");

      expect(await CanvasAssets.stored(), isEmpty);
    });
  });
  group("what a stored picture is called", () {
    test("a vector is recognised by what it says, not by a magic number", () {
      // SVG is XML: there is no magic number, and a file routinely opens with
      // a declaration, a doctype and a comment before it gets to the tag.
      var svg = utf8.encode('<?xml version="1.0"?>\n<!-- a badge -->\n'
          '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>');
      expect(CanvasAssets.extensionForTest(svg), ".svg");

      expect(CanvasAssets.extensionForTest(utf8.encode("not a picture")), "");
    });

    test("the bitmaps still are", () {
      expect(
          CanvasAssets.extensionForTest(
              [0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
          ".png");
      expect(CanvasAssets.extensionForTest([0xFF, 0xD8, 0xFF]), ".jpg");
    });
  });
  group("which pictures a document is using", () {
    test("a table's cell pictures count", () {
      // The fault that ate them: the document knew a picture element has an
      // asset and that nothing else does, so when a table learnt to hold one
      // in a cell the sweep did not hear about it and deleted every badge on
      // the next restart.
      var table = TableElement(
        const ElementBase(id: "t"),
        rows: const [
          ["Team", "Badge"],
          ["Hull City", "img:abcdef1234567890"],
          ["Leeds", "img:0123456789abcdef"],
          ["Notes", "not a picture"],
        ],
      );

      expect(table.assetIds,
          {"abcdef1234567890", "0123456789abcdef"});
      expect(CanvasDocument(elements: [table]).assetIds,
          {"abcdef1234567890", "0123456789abcdef"});
    });

    test("a picture element's still does, and an empty one names nothing", () {
      var picture = const ImageElement(ElementBase(id: "i"),
          assetId: "abcdef1234567890");
      expect(picture.assetIds, {"abcdef1234567890"});
      expect(const ImageElement(ElementBase(id: "i")).assetIds, isEmpty);
    });

    test("an element with no pictures names none", () {
      // The default, so a new kind of element that holds no picture needs to
      // say nothing at all.
      expect(ShapeElement(const ElementBase(id: "s")).assetIds, isEmpty);
    });
  });
  group("a picture stored and read back", () {
    test("the id a save hands out is the id a load takes", () async {
      // The whole round trip a table cell depends on: the cell keeps the id
      // as text, and everything after that is the store finding the file
      // again. An id with an extension on it that load could not read would
      // look exactly like a cell that had never been given a picture.
      {
        // A one-pixel PNG, which is the smallest thing the sniffer will
        // recognise as one.
        var png = <int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
          for (var i = 0; i < 40; i++) i,
        ];

        var id = await CanvasAssets.save(png);
        expect(id, isNotNull);
        expect(id!.endsWith(".png"), isTrue,
            reason: "named for what it is, so the system can open it");

        expect(await CanvasAssets.load(id), png);
        expect(TableElement.pictureIn("img:$id"), id,
            reason: "and a cell holding it hands back exactly that");

        // And a sweep that knows about the table keeps it.
        var document = CanvasDocument(elements: [
          TableElement(const ElementBase(id: "t"), rows: [
            ["Badge"],
            ["img:$id"],
          ]),
        ]);
        expect(document.assetIds, {id});
        await CanvasAssets.sweep(document.assetIds);
        expect(await CanvasAssets.load(id), isNotNull,
            reason: "still there after the sweep");
      }
    });
  });
}
