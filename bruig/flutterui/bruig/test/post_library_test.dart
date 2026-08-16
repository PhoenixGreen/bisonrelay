import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// post_library_test.dart exercises the library against a real directory.
//
// A stubbed filesystem would agree with whatever the code did, and the one
// thing worth being sure of here is that a name typed into a text field
// cannot write outside the folder it is supposed to. That is a claim about
// actual paths, so these tests use actual paths.

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("bruig-posts-test");
    PostStorage.rootOverride = root.path;
  });

  tearDown(() async {
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  String libraryPath(String relative) =>
      path.join(root.path, "my-posts", relative);

  group("documents", () {
    test("a document round-trips as a .md file", () async {
      await PostStorage.write("", "Routing fees", "# Routing fees\n\nHello.");

      expect(File(libraryPath("Routing fees.md")).existsSync(), isTrue,
          reason: "the point of the format is that it is a plain .md file");
      expect(await PostStorage.read("", "Routing fees"),
          "# Routing fees\n\nHello.");
    });

    test("a document lands in its folder", () async {
      await PostStorage.createFolder("Drafts");
      await PostStorage.write("Drafts", "Note", "body");

      expect(File(libraryPath("Drafts/Note.md")).existsSync(), isTrue);
      expect(await PostStorage.read("Drafts", "Note"), "body");
    });

    test("reading something that is not there is not an error", () async {
      expect(await PostStorage.read("", "nothing"), isNull);
      expect(await PostStorage.read("Missing", "nothing"), isNull);
    });

    test("exists answers before an overwrite", () async {
      expect(await PostStorage.exists("", "Note"), isFalse);
      await PostStorage.write("", "Note", "body");
      expect(await PostStorage.exists("", "Note"), isTrue);
    });
  });

  // The security claim, checked against the filesystem rather than against
  // the sanitizer alone: whatever the name, the file lands inside the
  // library.
  group("nothing escapes the library", () {
    test("a traversing name writes inside, or not at all", () async {
      for (var name in ["../escaped", "../../escaped", "/tmp/escaped", ".."]) {
        await PostStorage.write("", name, "should not escape");
      }
      for (var folder in ["../escaped", "..", "/tmp"]) {
        await PostStorage.write(folder, "note", "should not escape");
        await PostStorage.createFolder(folder);
      }

      // Nothing at all outside the library directory.
      var stray = root
          .listSync(recursive: true)
          .where((e) => !path.isWithin(libraryPath(""), e.path))
          .where((e) => e.path != libraryPath(""))
          .toList();
      expect(stray, isEmpty,
          reason: "a name from a text field wrote outside the library");
    });

    test("a folder cannot nest", () async {
      await PostStorage.createFolder("Outer");
      await PostStorage.write("Outer", "Note", "body");

      // A folder inside a folder is never listed, so it could only ever be
      // written and then lost.
      await Directory(libraryPath("Outer/Inner")).create(recursive: true);
      var inFolder = await PostStorage.list("Outer");
      expect(inFolder.where((e) => e.isFolder), isEmpty);
      expect(inFolder.map((e) => e.name), ["Note"]);
    });
  });

  group("listing", () {
    test("documents come before folders, each alphabetically", () async {
      await PostStorage.createFolder("Zebra");
      await PostStorage.createFolder("Apples");
      await PostStorage.write("", "beta", "b");
      await PostStorage.write("", "alpha", "a");

      var entries = await PostStorage.list();
      expect(entries.map((e) => e.name), ["alpha", "beta", "Apples", "Zebra"]);
      expect(entries.take(2).every((e) => e.isFolder), isFalse,
          reason: "the writing is above the filing");
    });

    test("only .md files are listed", () async {
      await PostStorage.write("", "kept", "body");
      await File(libraryPath("notes.txt")).writeAsString("ignored");
      await File(libraryPath(".hidden.md")).writeAsString("ignored");

      expect((await PostStorage.list()).map((e) => e.name), ["kept"]);
    });

    test("a document reports its size and when it was saved", () async {
      await PostStorage.write("", "Note", "12345");
      var entry = (await PostStorage.list()).single;
      expect(entry.size, 5);
      expect(entry.modified, isNotNull);
      expect(DateTime.now().difference(entry.modified!).inMinutes, lessThan(1));
    });
  });

  group("rename and delete", () {
    test("a document keeps its contents through a rename", () async {
      await PostStorage.write("", "Old", "body");
      var entry = (await PostStorage.list()).single;

      expect(await PostStorage.rename(entry, "New"), "New");
      expect(await PostStorage.read("", "New"), "body");
      expect(await PostStorage.read("", "Old"), isNull);
    });

    // Renaming onto an existing document would destroy it, which is not what
    // anybody means by "rename".
    test("a rename onto an existing name is refused", () async {
      await PostStorage.write("", "One", "first");
      await PostStorage.write("", "Two", "second");
      var one = (await PostStorage.list()).firstWhere((e) => e.name == "One");

      expect(await PostStorage.rename(one, "Two"), isNull);
      expect(await PostStorage.read("", "Two"), "second");
      expect(await PostStorage.read("", "One"), "first");
    });

    test("deleting a folder takes what is in it", () async {
      await PostStorage.createFolder("Drafts");
      await PostStorage.write("Drafts", "Note", "body");
      var folder = (await PostStorage.list()).single;

      await PostStorage.delete(folder);
      expect(Directory(libraryPath("Drafts")).existsSync(), isFalse);
      expect(await PostStorage.list(), isEmpty);
    });
  });

  group("the model", () {
    late PostLibraryModel model;
    late TextEditingController editor;

    setUp(() {
      model = PostLibraryModel();
      editor = TextEditingController();
      model.watch(editor);
    });
    tearDown(() {
      model.dispose();
      editor.dispose();
    });

    // Deleting the open document left its text on screen belonging to no
    // document -- which is the state fileLooseText exists to rescue, so
    // opening anything else filed it straight back under a name taken from
    // its own first heading. That is the name it had just been deleted
    // under, so it reappeared in the folder it had just been removed from.
    test("a deleted document is not refiled out of the composer", () async {
      await PostStorage.createFolder("Drafts");
      await PostStorage.write("Drafts", "Routing fees", "# Routing fees\n\nx");
      await PostStorage.write("Drafts", "Other", "# Other\n\ny");
      await model.openFolderNamed("Drafts");

      await model.open(
          model.entries.firstWhere((e) => e.name == "Routing fees"));
      expect(editor.text, contains("Routing fees"));

      await model.delete(
          model.entries.firstWhere((e) => e.name == "Routing fees"));
      expect(await PostStorage.exists("Drafts", "Routing fees"), isFalse);

      // Opening another document is what used to bring it back.
      await model.open(model.entries.firstWhere((e) => e.name == "Other"));
      expect(await PostStorage.exists("Drafts", "Routing fees"), isFalse,
          reason: "the deleted document came back");

      await model.refresh();
      expect(model.entries.where((e) => e.name == "Routing fees"), isEmpty);
    });

    // What publishing relies on: it flushes, closes, then empties the
    // composer, and the empty text must not reach the document it just
    // published from.
    test("a closed document is not written to again", () async {
      await PostStorage.write("", "Published", "# Published\n\nbody");
      await model.refresh();
      await model.open(model.entries.firstWhere((e) => e.name == "Published"));

      await model.flush();
      model.closeDocument();
      editor.text = "";
      await Future.delayed(const Duration(seconds: 3));

      expect(await PostStorage.read("", "Published"), "# Published\n\nbody",
          reason: "clearing the composer emptied the document");
      expect(model.openName, isNull);
    });

    test("deleting the open document empties the composer", () async {
      await PostStorage.write("", "A draft", "# A draft\n\nbody");
      await model.refresh();
      await model.open(model.entries.firstWhere((e) => e.name == "A draft"));
      expect(editor.text, isNotEmpty);

      await model.delete(
          model.entries.firstWhere((e) => e.name == "A draft"));
      expect(editor.text, isEmpty,
          reason: "text with no document behind it gets refiled");
      expect(model.openName, isNull);
    });

    // Deleting something else must leave the writing alone.
    test("deleting another document leaves the composer alone", () async {
      await PostStorage.write("", "Keep", "# Keep\n\nbody");
      await PostStorage.write("", "Bin", "# Bin\n\nbody");
      await model.refresh();
      await model.open(model.entries.firstWhere((e) => e.name == "Keep"));

      await model.delete(model.entries.firstWhere((e) => e.name == "Bin"));
      expect(editor.text, contains("Keep"));
      expect(model.openName, "Keep");
    });

    test("saving the current post opens it for further edits", () async {
      editor.text = "# A draft\n\nSome text.";
      expect(await model.newDocument("A draft"), isTrue);

      expect(model.openName, "A draft");
      expect(await PostStorage.read("", "A draft"), "# A draft\n\nSome text.");
    });

    test("edits to the open document are written", () async {
      await model.newDocument("Note");
      editor.text = "changed";
      await model.flush();

      expect(await PostStorage.read("", "Note"), "changed");
    });

    // Nothing is written until a document is actually open, or every draft
    // anyone started would appear in the library uninvited.
    test("typing with nothing open writes nothing", () async {
      editor.text = "just a post, not a document";
      await model.flush();
      expect(await PostStorage.list(), isEmpty);
    });

    test("opening replaces the editor and follows the document", () async {
      await PostStorage.write("", "Saved", "saved body");
      await model.refresh();
      editor.text = "in progress";

      var entry = model.entries.single;
      expect(await model.open(entry), isTrue);
      expect(editor.text, "saved body");
      expect(model.openName, "Saved");
    });

    // With nothing open the editor's text belongs nowhere, so a new document
    // takes it. With one open that text is already saved, so a new document
    // starts blank -- neither loses anything.
    test("a new document takes the editor's text only when nothing is open",
        () async {
      editor.text = "an unfiled post";
      expect(model.adoptsEditorText, isTrue);
      await model.newDocument("Filed");
      expect(await PostStorage.read("", "Filed"), "an unfiled post");
      expect(editor.text, "an unfiled post");

      expect(model.adoptsEditorText, isFalse);
      await model.newDocument("Blank");
      expect(await PostStorage.read("", "Blank"), "");
      expect(editor.text, "");
      expect(await PostStorage.read("", "Filed"), "an unfiled post",
          reason: "the document being left must keep its contents");
    });

    test("a document can be moved into a folder", () async {
      await PostStorage.createFolder("Drafts");
      await model.newDocument("Note");
      editor.text = "body";
      await model.flush();
      await model.refresh();

      var note = model.entries.firstWhere((e) => !e.isFolder);
      expect(await model.move(note, "Drafts"), isTrue);

      expect(await PostStorage.read("Drafts", "Note"), "body");
      expect(await PostStorage.read("", "Note"), isNull);
      // The open document follows, so autosave keeps writing where it went.
      expect(model.openFolder, "Drafts");
      editor.text = "edited after the move";
      await model.flush();
      expect(await PostStorage.read("Drafts", "Note"), "edited after the move");
    });

    test("a move onto an existing name is refused", () async {
      await PostStorage.createFolder("Drafts");
      await PostStorage.write("Drafts", "Note", "theirs");
      await PostStorage.write("", "Note", "mine");
      await model.refresh();

      var mine = model.entries.firstWhere((e) => !e.isFolder);
      expect(await model.move(mine, "Drafts"), isFalse);
      expect(await PostStorage.read("Drafts", "Note"), "theirs");
      expect(await PostStorage.read("", "Note"), "mine");
    });

    // Reported: moving between documents "effectively creates a new document
    // each time". Opening used to ask whether to insert at the cursor, which
    // left the editor holding a mixture belonging to no file -- and the next
    // save then wrote it out under a new name. Switching now saves the one
    // being left and loads the one being opened, and creates nothing.
    test("switching documents saves the old and creates nothing", () async {
      await model.newDocument("First");
      editor.text = "first body";
      await model.newDocument("Second");
      editor.text = "second body";
      await model.refresh();

      var first = model.entries.firstWhere((e) => e.name == "First");
      await model.open(first);

      expect(editor.text, "first body",
          reason: "the editor should show the document that was opened");
      expect(model.openName, "First");

      // Exactly the two documents that were asked for.
      await model.refresh();
      expect(model.entries.map((e) => e.name), ["First", "Second"]);
      expect(await PostStorage.read("", "Second"), "second body",
          reason: "the document being left should have been written");
    });

    // A steady typist never pauses long enough for a debounce, so the longer
    // they write the more they would stand to lose.
    test("continuous typing is still written", () async {
      await model.newDocument("Long");
      var started = DateTime.now();
      // Edits with no gap between them, past the ceiling.
      while (DateTime.now().difference(started) < maxAutosaveInterval * 1.5) {
        editor.text = "${editor.text}x";
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      var onDisk = await PostStorage.read("", "Long");
      expect(onDisk, isNotNull);
      expect(onDisk!.length, greaterThan(1),
          reason: "nothing was written while the keys never stopped");
    });

    test("deleting the open document stops it being written back", () async {
      await model.newDocument("Doomed");
      await model.refresh();

      await model.delete(model.entries.single);
      expect(model.openName, isNull);

      editor.text = "typed after the delete";
      await model.flush();
      expect(await PostStorage.read("", "Doomed"), isNull,
          reason: "autosave recreated a document the user deleted");
    });

    test("renaming the open document keeps writing to it", () async {
      await model.newDocument("Before");
      await model.refresh();

      await model.rename(model.entries.single, "After");
      expect(model.openName, "After");

      editor.text = "still saving";
      await model.flush();
      expect(await PostStorage.read("", "After"), "still saving");
      expect(await PostStorage.read("", "Before"), isNull);
    });

    // Requested after the previous change discarded a draft: opening a
    // document replaces the editor, and text that belongs to no document
    // went with it.
    group("loose text", () {
      test("is filed before another document is opened", () async {
        await PostStorage.write("", "Saved", "saved body");
        await model.refresh();
        editor.text = "# Half a post\n\nnot filed anywhere";

        await model.open(model.entries.single);

        expect(editor.text, "saved body");
        expect(await PostStorage.read("", "Half a post"),
            "# Half a post\n\nnot filed anywhere",
            reason: "the draft was discarded instead of being filed");
      });

      test("does not take a name already in use", () async {
        await PostStorage.write("", "Notes", "theirs");
        await PostStorage.write("", "Other", "other");
        await model.refresh();
        editor.text = "# Notes\n\nmine";

        await model.open(model.entries.firstWhere((e) => e.name == "Other"));

        expect(await PostStorage.read("", "Notes"), "theirs",
            reason: "filing loose text overwrote somebody's document");
        expect(await PostStorage.read("", "Notes 2"), "# Notes\n\nmine");
      });

      test("an empty editor files nothing", () async {
        await PostStorage.write("", "Saved", "body");
        await model.refresh();
        editor.text = "   \n  ";

        await model.open(model.entries.single);
        expect((await PostStorage.list()).map((e) => e.name), ["Saved"]);
      });

      // With a document open there is no loose text: it is already in that
      // document, and filing a second copy is what the last change removed.
      test("an open document is not copied", () async {
        await model.newDocument("First");
        editor.text = "first body";
        await PostStorage.write("", "Second", "second body");
        await model.refresh();

        await model.open(model.entries.firstWhere((e) => e.name == "Second"));
        expect(
            (await PostStorage.list()).map((e) => e.name), ["First", "Second"]);
      });
    });

    // The composer's title box renames through this, which is also how an
    // unfiled post becomes a document.
    group("renameOpen", () {
      test("names an unfiled post, filing what is in the editor", () async {
        editor.text = "some writing";
        expect(await model.renameOpen("A name"), isTrue);

        expect(model.openName, "A name");
        expect(await PostStorage.read("", "A name"), "some writing");
      });

      test("renames the open document and keeps writing to it", () async {
        await model.newDocument("Before");
        editor.text = "body";

        expect(await model.renameOpen("After"), isTrue);
        expect(model.openName, "After");
        editor.text = "more";
        await model.flush();
        expect(await PostStorage.read("", "After"), "more");
        expect(await PostStorage.read("", "Before"), isNull);
      });

      test("an unusable name changes nothing", () async {
        await model.newDocument("Kept");
        expect(await model.renameOpen("   "), isFalse);
        expect(await model.renameOpen("..."), isFalse);
        expect(model.openName, "Kept");
      });
    });

    test("browsing a folder does not move the open document", () async {
      await PostStorage.createFolder("Drafts");
      await model.newDocument("At the top");
      await model.openFolderNamed("Drafts");

      expect(model.openFolder, "");
      editor.text = "edited while browsing elsewhere";
      await model.flush();
      expect(await PostStorage.read("", "At the top"),
          "edited while browsing elsewhere");
      expect(await PostStorage.read("Drafts", "At the top"), isNull);
    });
  });

  // The library is a directory listing, so its order was whatever the
  // filesystem's alphabet said. A post being worked on is worth having at the
  // top, and that is a decision the library has to remember for itself.
  group("the order things are shown in", () {
    Future<List<String>> names([String folder = ""]) async =>
        (await PostStorage.list(folder)).map((e) => e.name).toList();

    setUp(() async {
      for (var name in ["Beta", "Alpha", "Gamma"]) {
        await PostStorage.write("", name, "x");
      }
    });

    test("with nothing moved it is still alphabetical", () async {
      expect(await names(), ["Alpha", "Beta", "Gamma"]);
    });

    test("a recorded order is the order it is shown in", () async {
      await PostStorage.writeOrder("", ["Gamma", "Alpha", "Beta"]);
      expect(await names(), ["Gamma", "Alpha", "Beta"]);
    });

    // A document made on another machine, or before anything was moved, has
    // to appear somewhere -- at the end, in the order the library always
    // used, rather than not at all.
    test("what the order has never heard of comes after it", () async {
      await PostStorage.writeOrder("", ["Gamma"]);
      expect(await names(), ["Gamma", "Alpha", "Beta"]);
    });

    // Deleted outside the app, or renamed: the name simply drops out rather
    // than shifting everything after it.
    test("a name that is gone is skipped", () async {
      await PostStorage.writeOrder("", ["Missing", "Gamma", "Alpha", "Beta"]);
      expect(await names(), ["Gamma", "Alpha", "Beta"]);
    });

    // The order file is the library's own bookkeeping, and the listing skips
    // dotted names -- so it needs no special case to stay out of the library
    // it describes.
    test("the order file is not itself a document", () async {
      await PostStorage.writeOrder("", ["Gamma"]);
      expect(await names(), isNot(contains(".order")));
    });

    // Documents first: they are what the library is for, and a folder is
    // where some of them are kept.
    test("folders keep their own order, below the documents", () async {
      await PostStorage.createFolder("Later");
      await PostStorage.createFolder("Earlier");
      await PostStorage.writeOrder(
          "", ["Gamma", "Alpha", "Beta", "Later", "Earlier"]);
      expect(await names(), ["Gamma", "Alpha", "Beta", "Later", "Earlier"]);
    });

    test("each folder has an order of its own", () async {
      await PostStorage.createFolder("Outer");
      await PostStorage.write("Outer", "One", "x");
      await PostStorage.write("Outer", "Two", "x");
      await PostStorage.writeOrder("Outer", ["Two", "One"]);

      expect(await names("Outer"), ["Two", "One"]);
      expect(await names(), ["Alpha", "Beta", "Gamma", "Outer"],
          reason: "the top level is untouched by it");
    });
  });
}
