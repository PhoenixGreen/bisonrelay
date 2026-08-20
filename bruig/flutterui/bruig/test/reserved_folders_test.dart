import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:flutter_test/flutter_test.dart';

// reserved_folders_test.dart covers the folders the app keeps for itself.
//
// There used to be one, for notes, with its rules written as a check against
// that one name. There are three now -- notes, pages and store -- and all
// three rest on the same claim: something elsewhere in the app files into
// them by name, so a folder that could be renamed, moved or deleted would
// strand everything filed into it.
//
// Checked against a real directory rather than a stub, because the claim is
// about what is on disk.

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("bruig-reserved-test");
    PostStorage.rootOverride = root.path;
  });

  tearDown(() async {
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<PostEntry> folder(String name) async {
    await PostStorage.createFolder(name);
    return (await PostStorage.list()).firstWhere((e) => e.name == name);
  }

  test('all three are reserved, and an ordinary folder is not', () async {
    for (var name in reservedFolderNames) {
      expect((await folder(name)).isReservedFolder, isTrue, reason: name);
    }
    expect((await folder("Drafts")).isReservedFolder, isFalse);
  });

  test('they sit at the bottom, in a fixed order', () async {
    // Made out of order, and with ordinary folders around them.
    await folder(storeFolderName);
    await folder("Zebra");
    await folder(notesFolderName);
    await folder("Apple");
    await folder(pagesFolderName);

    var names = (await PostStorage.list()).map((e) => e.name).toList();
    expect(names.sublist(names.length - 3), reservedFolderNames,
        reason: "pinned last, and in reservedFolderNames' order rather than "
            "the order they happened to be read in");
  });

  test('none of them can be renamed', () async {
    for (var name in reservedFolderNames) {
      var f = await folder(name);
      expect(await PostStorage.rename(f, "Something else"), isNull,
          reason: name);
      expect((await PostStorage.list()).map((e) => e.name), contains(name));
    }
  });

  test('nothing else can be renamed onto one', () async {
    // Or there would be two folders claiming the same reserved name, and
    // whatever files by name would find whichever came first.
    var ordinary = await folder("Drafts");
    expect(await PostStorage.rename(ordinary, pagesFolderName), isNull);
    expect(await PostStorage.rename(ordinary, storeFolderName), isNull);
  });

  test('none of them can be deleted, but what is inside them can', () async {
    var f = await folder(pagesFolderName);
    await PostStorage.write(pagesFolderName, "about", "the about page");

    await PostStorage.delete(f);
    expect((await PostStorage.list()).map((e) => e.name),
        contains(pagesFolderName));

    // The way to clear one out is still there.
    var doc = (await PostStorage.list(pagesFolderName)).single;
    await PostStorage.delete(doc);
    expect(await PostStorage.list(pagesFolderName), isEmpty);
  });

  test('none of them are offered as a place to move something', () async {
    await folder("Drafts");
    for (var name in reservedFolderNames) {
      await folder(name);
    }
    expect(await PostStorage.folderNames(), ["Drafts"]);
  });
}
