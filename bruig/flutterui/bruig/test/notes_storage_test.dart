import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/notes/notes.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// notes_storage_test.dart covers the two claims notes rest on.
//
// The first is that a note is an ordinary Markdown document in the post
// library, so anything that can read a folder can read your notes. That is
// checked against a real directory rather than a stub, because the claim is
// about what is actually on disk.
//
// The second is that a note stays attached to the thing it is about -- across
// a restart, across being renamed in the sidebar, and across another page
// happening to have the same title. That is what the hidden index does, and
// most of what is below is about the ways it has to cope with the library
// being edited underneath it.

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("bruig-notes-test");
    PostStorage.rootOverride = root.path;
  });

  tearDown(() async {
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  String notePath(String name) =>
      path.join(root.path, "my-posts", notesFolderName, "$name.md");

  group("a note is a Markdown document in the library", () {
    test("writing one leaves a .md file where posts are kept", () async {
      var target = NoteTarget.document("/downloads/Mastering Go.pdf");
      expect(await NoteStorage.write(target, "the bit about ports"), isTrue);

      // The name is the title, and the title is what the sidebar will show.
      var file = File(notePath("Document - Mastering Go"));
      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), "the bit about ports");
    });

    test("the title uses a dash, because a colon is not a filename", () async {
      // "Document: Mastering Go" reads better and cannot be a path on
      // Windows. One name that is both the row and the file is worth more
      // than the punctuation -- see NoteTarget.title.
      expect(NoteTarget.document("/x/Mastering Go").title,
          "Document - Mastering Go");
      expect(NoteTarget.chat("abc", "Trading", isGC: true).title,
          "Chat - Trading Group");
      expect(NoteTarget.global.title, "Global Notes");
    });

    test("a group already called a group is not called one twice", () {
      expect(NoteTarget.chat("abc", "Trading Group", isGC: true).title,
          "Chat - Trading Group");
    });

    test("it comes back through the library's own listing", () async {
      await NoteStorage.write(NoteTarget.global, "across everything");

      var entries = await PostStorage.list(notesFolderName);
      expect(entries.map((e) => e.name), contains("Global Notes"));
      expect(entries.single.isFolder, isFalse);
    });

    test("the index stays out of the listing", () async {
      await NoteStorage.write(NoteTarget.global, "x");
      var entries = await PostStorage.list(notesFolderName);
      // Hidden, so the listing already skips it -- the same trick .order uses.
      expect(entries.length, 1);
    });
  });

  group("a note stays attached to what it is about", () {
    test("reading it back finds the same note", () async {
      var target = NoteTarget.chat("uid-1", "Alice");
      await NoteStorage.write(target, "owes me a reply");
      expect(await NoteStorage.read(NoteTarget.chat("uid-1", "Alice")),
          "owes me a reply");
    });

    test("the chat can be renamed without losing the note", () async {
      var target = NoteTarget.chat("uid-1", "Alice");
      await NoteStorage.write(target, "owes me a reply");

      // Same person, new nick. The key did not change, so the note is still
      // theirs -- which is the whole reason the key is the id and not the
      // name.
      expect(await NoteStorage.read(NoteTarget.chat("uid-1", "Alicia")),
          "owes me a reply");
    });

    test("renaming the note in the sidebar keeps it attached", () async {
      var target = NoteTarget.document("/downloads/report.pdf");
      await NoteStorage.write(target, "page 4 is wrong");

      var renamed = await PostStorage.rename(
          PostEntry(
              name: "Document - report",
              folder: notesFolderName,
              isFolder: false),
          "Report notes");
      expect(renamed, "Report notes");
      await NoteStorage.noteRenamed("Document - report", "Report notes");

      // Without the index following the rename, the page would find nothing
      // under the old name and quietly start a second, empty note beside it.
      expect(await NoteStorage.read(target), "page 4 is wrong");
      await NoteStorage.write(target, "page 4 is wrong, and so is 9");
      expect(File(notePath("Report notes")).existsSync(), isTrue);
      expect(File(notePath("Document - report")).existsSync(), isFalse);
    });

    test("two things with the same title get two notes", () async {
      // Same filename, different folders. They are different documents, and
      // a shared note would put one's reading against the other.
      var a = NoteTarget.document("/downloads/notes.txt");
      var b = NoteTarget.document("/shared/notes.txt");
      await NoteStorage.write(a, "from Alice");
      await NoteStorage.write(b, "from Bob");

      expect(await NoteStorage.read(a), "from Alice");
      expect(await NoteStorage.read(b), "from Bob");
      expect(File(notePath("Document - notes")).existsSync(), isTrue);
      expect(File(notePath("Document - notes 2")).existsSync(), isTrue);
    });

    test("a note deleted from the sidebar does not come back", () async {
      var target = NoteTarget.page("/manage/downloads", "Downloads");
      await NoteStorage.write(target, "waiting on the second half");
      await PostStorage.delete(PostEntry(
          name: "Page - Downloads", folder: notesFolderName, isFolder: false));

      // The index still names it. Handing that name back would read an empty
      // string out of a file that is not there -- and then write it back into
      // existence on the next keystroke.
      expect(await NoteStorage.read(target), "");
      expect(await NoteStorage.hasNote(target), isFalse);
    });

    test("emptying a note removes the document rather than leaving a blank",
        () async {
      var target = NoteTarget.global;
      await NoteStorage.write(target, "temporary");
      expect(File(notePath("Global Notes")).existsSync(), isTrue);

      // The folder fills itself, without anyone choosing to file anything
      // into it, so a note cleared out has to leave no row behind.
      await NoteStorage.write(target, "   \n  ");
      expect(File(notePath("Global Notes")).existsSync(), isFalse);
      expect(await NoteStorage.hasNote(target), isFalse);
    });

    test("a damaged index costs the mapping, not the notes", () async {
      await NoteStorage.write(NoteTarget.global, "still here");
      await File(path.join(root.path, "my-posts", notesFolderName, ".targets"))
          .writeAsString("this is not an index\n\n\t\n");

      // The documents are on disk under their own names and are still
      // readable by anything; what is lost is which page each belongs to.
      var entries = await PostStorage.list(notesFolderName);
      expect(entries.map((e) => e.name), contains("Global Notes"));
      // ...and the next write rebuilds the one entry it needs.
      await NoteStorage.write(NoteTarget.global, "rebuilt");
      expect(await NoteStorage.read(NoteTarget.global), "rebuilt");
    });
  });

  group("the notes folder is reserved", () {
    test("it sits at the bottom of the top level", () async {
      await PostStorage.createFolder("Zebra");
      await PostStorage.createFolder("Apples");
      await PostStorage.write("", "A loose post", "x");
      await NoteStorage.ensureFolder();

      var names = (await PostStorage.list()).map((e) => e.name).toList();
      // Notes accumulate on their own; a folder that drifted up the list as
      // it grew would put itself between somebody and their writing.
      expect(names.last, notesFolderName);
      expect(names, containsAllInOrder(["Apples", "Zebra", notesFolderName]));
    });

    test("an order file cannot move it", () async {
      await PostStorage.createFolder("Apples");
      await NoteStorage.ensureFolder();
      await PostStorage.writeOrder("", [notesFolderName, "Apples"]);

      expect(
          (await PostStorage.list()).map((e) => e.name).last, notesFolderName);
    });

    test("it refuses to be renamed or deleted", () async {
      await NoteStorage.write(NoteTarget.global, "keep me");
      var entry = PostEntry(name: notesFolderName, folder: "", isFolder: true);

      expect(await PostStorage.rename(entry, "My Notes"), isNull);
      await PostStorage.delete(entry);

      // Both refused: notes are still being filed into this folder by name
      // from every page in the app.
      expect(await NoteStorage.read(NoteTarget.global), "keep me");
      expect((await PostStorage.list()).map((e) => e.name),
          contains(notesFolderName));
    });

    test("nothing else may take its name", () async {
      var made = await PostStorage.createFolder("Spare");
      expect(made, "Spare");
      expect(
          await PostStorage.rename(
              PostEntry(name: "Spare", folder: "", isFolder: true),
              notesFolderName),
          isNull);
    });

    test("it is not offered as somewhere to move a document", () async {
      await PostStorage.createFolder("Drafts");
      await NoteStorage.ensureFolder();

      // A document dropped in beside the notes would be about nothing, and
      // would sit there forever as a row no page ever opens.
      expect(await PostStorage.folderNames(), ["Drafts"]);
    });
  });
}
