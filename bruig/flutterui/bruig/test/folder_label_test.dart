import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// folder_label_test.dart covers the fragments folder: what it is called, and
// moving a library that was made when it was called something else.
//
// "Partials" is templating jargon, and everywhere else in the app these are
// fragments -- the Pages section lists "Shared fragments" and offers "New
// fragment", and the block that pulls one in is "Shared fragment". The
// folder is a real directory a writer can see, so the two had to agree.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp("library");
    PostStorage.rootOverride = root.path;
  });
  tearDown(() async {
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Directory folder(String name) =>
      Directory(path.join(root.path, "my-posts", name));

  Future<void> write(String folderName, String file, String body) async {
    await folder(folderName).create(recursive: true);
    await File(path.join(folder(folderName).path, file)).writeAsString(body);
  }

  group('what the folder is called', () {
    test('is Fragments, in the app and on disk', () {
      expect(partialsFolderName, "Fragments");
      expect(folderLabel(partialsFolderName), "Fragments");
      expect(reservedFolderNames, contains("Fragments"));
    });

    test('and no longer Partials anywhere', () {
      expect(reservedFolderNames, isNot(contains("Partials")));
    });
  });

  group('a library made before the rename', () {
    test('is moved, with what is in it', () async {
      await write("Partials", "header.md", "# a banner");

      await PostStorage.libraryDir();

      expect(await folder("Fragments").exists(), isTrue);
      expect(await folder("Partials").exists(), isFalse);
      expect(
          await File(path.join(folder("Fragments").path, "header.md"))
              .readAsString(),
          "# a banner");
    });

    test('is left alone when there is nothing to move', () async {
      await PostStorage.libraryDir();
      expect(await folder("Partials").exists(), isFalse);
    });

    test('is left alone when both are there', () async {
      // A library in a state this cannot reason about. Merging could
      // overwrite a fragment with another of the same name, so both are
      // left where the writer can see them and sort it out.
      await write("Partials", "header.md", "the old one");
      await write("Fragments", "header.md", "the new one");

      await PostStorage.libraryDir();

      expect(await folder("Partials").exists(), isTrue);
      expect(
          await File(path.join(folder("Fragments").path, "header.md"))
              .readAsString(),
          "the new one");
      expect(
          await File(path.join(folder("Partials").path, "header.md"))
              .readAsString(),
          "the old one");
    });

    test('opening the library twice is not a problem', () async {
      await write("Partials", "footer.md", "the end");
      await PostStorage.libraryDir();
      await PostStorage.libraryDir();

      expect(await folder("Fragments").exists(), isTrue);
      expect(
          await File(path.join(folder("Fragments").path, "footer.md"))
              .readAsString(),
          "the end");
    });

    test('everything in it comes across, not just one file', () async {
      for (var name in ["header.md", "navigation.md", "footer.md"]) {
        await write("Partials", name, name);
      }

      await PostStorage.libraryDir();

      var moved = await folder("Fragments")
          .list()
          .map((e) => path.basename(e.path))
          .toList();
      expect(moved..sort(), ["footer.md", "header.md", "navigation.md"]);
    });
  });
}
