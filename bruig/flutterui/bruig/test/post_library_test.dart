import 'dart:io';

import 'package:bruig/post_library/post_library.dart';
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
    test("folders come before documents, each alphabetically", () async {
      await PostStorage.createFolder("Zebra");
      await PostStorage.createFolder("Apples");
      await PostStorage.write("", "beta", "b");
      await PostStorage.write("", "alpha", "a");

      var entries = await PostStorage.list();
      expect(entries.map((e) => e.name), ["Apples", "Zebra", "alpha", "beta"]);
      expect(entries.take(2).every((e) => e.isFolder), isTrue);
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

    test("saving the current post opens it for further edits", () async {
      editor.text = "# A draft\n\nSome text.";
      expect(await model.saveCurrentAs("A draft"), isTrue);

      expect(model.openName, "A draft");
      expect(await PostStorage.read("", "A draft"), "# A draft\n\nSome text.");
    });

    test("edits to the open document are written", () async {
      await model.saveCurrentAs("Note");
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

    // Inserting leaves the editor holding a mixture that belongs to no file,
    // so autosaving it back would destroy the document it came from.
    test("inserting does not adopt the document", () async {
      await PostStorage.write("", "Snippet", "INSERTED");
      await model.refresh();
      editor.value = const TextEditingValue(
        text: "before after",
        selection: TextSelection.collapsed(offset: 7),
      );

      await model.open(model.entries.single, replace: false);
      expect(editor.text, "before INSERTEDafter");
      expect(model.openName, isNull,
          reason: "autosaving a mixture over the source would destroy it");

      await model.flush();
      expect(await PostStorage.read("", "Snippet"), "INSERTED");
    });

    test("deleting the open document stops it being written back", () async {
      await model.saveCurrentAs("Doomed");
      await model.refresh();

      await model.delete(model.entries.single);
      expect(model.openName, isNull);

      editor.text = "typed after the delete";
      await model.flush();
      expect(await PostStorage.read("", "Doomed"), isNull,
          reason: "autosave recreated a document the user deleted");
    });

    test("renaming the open document keeps writing to it", () async {
      await model.saveCurrentAs("Before");
      await model.refresh();

      await model.rename(model.entries.single, "After");
      expect(model.openName, "After");

      editor.text = "still saving";
      await model.flush();
      expect(await PostStorage.read("", "After"), "still saving");
      expect(await PostStorage.read("", "Before"), isNull);
    });

    test("browsing a folder does not move the open document", () async {
      await PostStorage.createFolder("Drafts");
      await model.saveCurrentAs("At the top");
      await model.openFolderNamed("Drafts");

      expect(model.openFolder, "");
      editor.text = "edited while browsing elsewhere";
      await model.flush();
      expect(await PostStorage.read("", "At the top"),
          "edited while browsing elsewhere");
      expect(await PostStorage.read("Drafts", "At the top"), isNull);
    });
  });
}
