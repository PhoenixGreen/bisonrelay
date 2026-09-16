import 'dart:async';
import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// post_reorder_test.dart covers dragging a document or a folder to a new
// place in the library sidebar.
//
// Two things about it are easy to get wrong and invisible when they are.
// ReorderableListView reports where a row was dropped counting the row being
// moved as still in its old place, so a downward drag lands one short unless
// that is corrected. And documents and folders are separate runs -- a drag
// that ends past the boundary has to stop at it rather than file a post among
// the folders.

void main() {
  late Directory root;
  late PostLibraryModel library;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = await Directory.systemTemp.createTemp("bruig-reorder-test");
    PostStorage.rootOverride = root.path;

    for (var name in ["One", "Two", "Three"]) {
      await PostStorage.write("", name, "x");
    }
    await PostStorage.createFolder("Archive");
    await PostStorage.createFolder("Drafts");
    // Alphabetical to begin with, documents first.
    await PostStorage.writeOrder(
        "", ["One", "Two", "Three", "Archive", "Drafts"]);

    library = PostLibraryModel();
    await library.refresh();
  });

  tearDown(() async {
    library.dispose();
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  List<String> names() => library.entries.map((e) => e.name).toList();

  test("the library opens with the documents above the folders", () {
    expect(names(), ["One", "Two", "Three", "Archive", "Drafts"]);
  });

  test("a document dragged upwards lands where it was dropped", () async {
    await library.reorder(2, 0);
    expect(names(), ["Three", "One", "Two", "Archive", "Drafts"]);
  });

  // The one the index correction is for: dropping below counts the row being
  // moved as still occupying its old place.
  test("a document dragged downwards lands where it was dropped", () async {
    await library.reorder(0, 3);
    expect(names(), ["Two", "Three", "One", "Archive", "Drafts"]);
  });

  test("a folder moves among the folders", () async {
    await library.reorder(4, 3);
    expect(names(), ["One", "Two", "Three", "Drafts", "Archive"]);
  });

  // Documents and folders are separate runs. A drag that ends past the
  // boundary stops at it rather than crossing it.
  test("a document dropped among the folders stops at the boundary", () async {
    await library.reorder(0, 5);
    expect(names(), ["Two", "Three", "One", "Archive", "Drafts"]);
  });

  test("a folder dropped among the documents stops at the boundary", () async {
    await library.reorder(4, 0);
    expect(names(), ["One", "Two", "Three", "Drafts", "Archive"]);
  });

  // The indices are where the row starts and where it ends up, which is
  // what ReorderableListView's onReorderItem reports -- its older onReorder
  // counted the row as still occupying its old place and had to be corrected
  // by every caller.
  test("a drag that ends where it began changes nothing", () async {
    expect(await library.reorder(1, 1), isFalse);
    expect(names(), ["One", "Two", "Three", "Archive", "Drafts"]);
  });

  // The order outlives the app, which is the whole point of recording it.
  test("the new order is on disk", () async {
    await library.reorder(2, 0);
    expect(await PostStorage.readOrder(""),
        ["Three", "One", "Two", "Archive", "Drafts"]);

    var fresh = PostLibraryModel();
    addTearDown(fresh.dispose);
    await fresh.refresh();
    expect(fresh.entries.map((e) => e.name),
        ["Three", "One", "Two", "Archive", "Drafts"]);
  });

  // The fault this file grew a whole group for: the sidebar showed a drag
  // landing in one place and the next listing put it in another.
  //
  // The listing pins rows -- the reserved folders at the bottom, the front
  // page at the top of Pages -- however the rest has been arranged. The drag
  // knew only about the notes folder, so a folder dropped at the very bottom
  // appeared below Pages, Partials and Store, sat there, and jumped back
  // above them the moment the folder was read again.
  group("the rows the listing pins", () {
    setUp(() async {
      await PostStorage.createFolder(pagesFolderName);
      await PostStorage.createFolder(partialsFolderName);
      await PostStorage.createFolder(notesFolderName);
      await library.refresh();
    });

    test("sit at the bottom, below the folders anyone can move", () {
      expect(names().sublist(3), [
        "Archive",
        "Drafts",
        notesFolderName,
        pagesFolderName,
        partialsFolderName
      ]);
    });

    test("a folder dropped past them lands against them, and stays there",
        () async {
      var drafts = names().indexOf("Drafts");
      await library.reorder(names().indexOf("Archive"), names().length - 1);
      var shown = names();
      expect(shown.indexOf("Archive"), drafts,
          reason: "against the boundary, not past it");

      // And the same thing comes back off disk. Showing one arrangement and
      // storing another is the glitch itself.
      await library.refresh();
      expect(names(), shown);
    });

    test("and cannot be dragged themselves", () async {
      var before = names();
      expect(
          await library.reorder(names().indexOf(pagesFolderName), 3), isFalse);
      expect(names(), before);
    });
  });

  group("the front page in Pages", () {
    setUp(() async {
      await PostStorage.createFolder(pagesFolderName);
      for (var name in ["index", "About", "Contact"]) {
        await PostStorage.write(pagesFolderName, name, "x");
      }
      await library.openFolderNamed(pagesFolderName);
    });

    test("is first, whatever the order says", () {
      expect(names().first, "index");
    });

    test("cannot be dragged off the top", () async {
      var before = names();
      expect(await library.reorder(0, 2), isFalse);
      expect(names(), before);
    });

    test("and nothing can be dropped above it", () async {
      await library.reorder(names().indexOf("Contact"), 0);
      var shown = names();
      expect(shown.first, "index");
      await library.refresh();
      expect(names(), shown, reason: "shown is what comes back");
    });
  });

  // Shown at once, and held against anything that reads the folder before the
  // write lands.
  //
  // A row that does not move until a disk write finishes is a drag that looks
  // like it failed -- and one that never moves at all if the write is slow.
  test("the list is rearranged before the write completes", () async {
    var held = Completer<void>();
    PostStorage.slowOrderWriteForTest = () => held.future;
    addTearDown(() => PostStorage.slowOrderWriteForTest = null);

    var dragging = library.reorder(2, 0);
    await pumpEventQueue();
    expect(names(), ["Three", "One", "Two", "Archive", "Drafts"],
        reason: "at once, not when the disk says so");

    held.complete();
    await dragging;
    expect(names(), ["Three", "One", "Two", "Archive", "Drafts"]);
  });

  // Reported: a document dragged down a few places hopped somewhere else a
  // moment after being let go, with no reserved folder anywhere near it.
  //
  // A drag is shown before it is saved, deliberately -- a row that snaps back
  // while the disk write finishes reads as the drag having failed. That
  // leaves a window where the list on screen and the list on disk disagree,
  // and anything that re-read the folder inside it put the row back where it
  // came from. Autosave is what was doing it: it fires eight hundred
  // milliseconds after typing stops and re-lists the folder when it is done,
  // so this happened to anybody dragging a row while a document was open --
  // which is to say, while working.
  group("a re-read that lands mid-drag", () {
    /// held keeps the order write open until it is let go, so a listing can
    /// be made to happen inside the window a drag leaves between being shown
    /// and being saved. On a temp directory the write always wins otherwise,
    /// and the window never opens.
    late Completer<void> held;

    setUp(() {
      held = Completer<void>();
      PostStorage.slowOrderWriteForTest = () => held.future;
    });

    tearDown(() => PostStorage.slowOrderWriteForTest = null);

    test("autosave does not undo a drag", () async {
      var editor = TextEditingController();
      addTearDown(editor.dispose);
      library.watch(editor);
      await library.open(library.entries.firstWhere((e) => e.name == "One"));
      // Typed into after opening: text in an editor with nothing open is
      // loose writing, and opening a document files it as a document of its
      // own -- which would be a sixth row and not what this is about.
      editor.text = "One, edited";

      // The drag, still writing. Autosave lands in the middle of it and
      // re-reads the folder when it is done.
      var dragging = library.reorder(2, 0);
      await pumpEventQueue();
      var saving = library.flush();
      await pumpEventQueue();

      held.complete();
      await Future.wait([dragging, saving]);
      expect(names(), ["Three", "One", "Two", "Archive", "Drafts"],
          reason: "the row anybody had just dropped hopped back");

      await library.refresh();
      expect(names(), ["Three", "One", "Two", "Archive", "Drafts"]);
    });

    test("and neither does a refresh", () async {
      var dragging = library.reorder(0, 2);
      await pumpEventQueue();
      var reading = library.refresh();
      await pumpEventQueue();

      held.complete();
      await Future.wait([dragging, reading]);
      expect(names(), ["Two", "Three", "One", "Archive", "Drafts"]);

      await library.refresh();
      expect(names(), ["Two", "Three", "One", "Archive", "Drafts"]);
    });
  });
}
