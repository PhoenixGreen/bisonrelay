import 'dart:io';

import 'package:bruig/post_library/embed_store.dart';
import 'package:bruig/post_library/post_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// embed_store_test.dart covers where a draft's pictures live.
//
// Reported: a saved post with an image in it came back after a restart
// showing "missing embed image", and the image was gone. It had never been
// written anywhere -- the draft text holds only a reference, and the data
// behind it sat in a map in memory that closing the app emptied.
//
// A real directory rather than a stubbed filesystem, for the same reason
// post_storage_test uses one: what is being checked is that an id out of a
// file on disk cannot write outside the library, and a fake would happily
// agree with whatever the code did.

late Directory root;

Future<String> _embedsDir() async =>
    path.join(await PostStorage.libraryDir(), ".embeds");

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp("embeds_test");
    PostStorage.rootOverride = root.path;
  });

  tearDown(() async {
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test("what is saved can be read back", () async {
    await EmbedStore.save("abc123def456", "somebase64data");
    expect(await EmbedStore.load("abc123def456"), "somebase64data");
  });

  test("an id that was never saved reads as nothing", () async {
    expect(await EmbedStore.load("zzzzzzzzzzzz"), isNull);
  });

  group("finding the references in a draft", () {
    test("one embed", () {
      var ids = EmbedStore.idsIn(
          "before --embed[type=image/png,data=[content abc123def456]]-- after");
      expect(ids, {"abc123def456"});
    });

    test("several, without repeats", () {
      var ids = EmbedStore.idsIn("data=[content aaaaaaaaaaaa] "
          "data=[content bbbbbbbbbbbb] data=[content aaaaaaaaaaaa]");
      expect(ids, {"aaaaaaaaaaaa", "bbbbbbbbbbbb"});
    });

    test("a bracketed id that is not an embed's data is ignored", () {
      expect(
          EmbedStore.idsIn("see [content aaaaaaaaaaaa] for details"), isEmpty);
    });

    test("a post with no pictures in it", () {
      expect(EmbedStore.idsIn("just some words"), isEmpty);
    });

    // The published form carries the data itself rather than a reference,
    // and there is nothing to look up.
    test("an embed holding its own data is not a reference", () {
      expect(EmbedStore.idsIn("--embed[type=image/png,data=iVBORw0KGgo=]--"),
          isEmpty);
    });
  });

  test("loadFor returns what a draft needs and skips what is gone", () async {
    await EmbedStore.save("aaaaaaaaaaaa", "first");
    var got = EmbedStore.loadFor(
        "data=[content aaaaaaaaaaaa] data=[content bbbbbbbbbbbb]");
    expect(await got, {"aaaaaaaaaaaa": "first"},
        reason: "a draft written before pictures were stored refers to ones "
            "that were never saved, and saying so is better than failing");
  });

  group("an id from a file cannot escape the library", () {
    // These ids come out of text on disk, and text on disk becoming part of
    // a path is the shape of a mistake worth refusing to make.
    test("a traversal is refused", () async {
      await EmbedStore.save("../../escaped", "data");
      expect(await File(path.join(root.path, "escaped")).exists(), isFalse);
      expect(await EmbedStore.load("../../escaped"), isNull);
    });

    test("a separator is refused", () async {
      await EmbedStore.save("aaa/bbb/ccc", "data");
      expect(await EmbedStore.load("aaa/bbb/ccc"), isNull);
    });

    test("the wrong length is refused", () async {
      await EmbedStore.save("short", "data");
      expect(await EmbedStore.load("short"), isNull);
    });
  });

  group("sweeping up after a deleted draft", () {
    test("what nothing refers to is deleted", () async {
      await EmbedStore.save("aaaaaaaaaaaa", "kept");
      await EmbedStore.save("bbbbbbbbbbbb", "orphaned");

      expect(await EmbedStore.sweep({"aaaaaaaaaaaa"}), 1);
      expect(await EmbedStore.load("aaaaaaaaaaaa"), "kept");
      expect(await EmbedStore.load("bbbbbbbbbbbb"), isNull);
    });

    // One picture can be referred to from two drafts -- a post duplicated,
    // or text pasted between them -- and tidying up after one must not
    // break the other.
    test("what is still referred to is kept", () async {
      await EmbedStore.save("aaaaaaaaaaaa", "shared");
      expect(await EmbedStore.sweep({"aaaaaaaaaaaa", "cccccccccccc"}), 0);
      expect(await EmbedStore.load("aaaaaaaaaaaa"), "shared");
    });

    test("sweeping an empty library is not an error", () async {
      expect(await EmbedStore.sweep({}), 0);
    });
  });

  // The library shows folders and documents. The pictures sit beside them
  // and must not appear as either.
  test("the store is invisible to the library", () async {
    await EmbedStore.save("aaaaaaaaaaaa", "data");
    expect(await Directory(await _embedsDir()).exists(), isTrue);
    expect(await PostStorage.list(), isEmpty);
  });
}
