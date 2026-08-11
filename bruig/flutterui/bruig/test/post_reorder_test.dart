import 'dart:io';

import 'package:bruig/post_library/post_library.dart';
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

  // Shown before it is saved: a row that snaps back while the disk write
  // finishes reads as the drag having failed.
  test("the list is rearranged before the write completes", () async {
    var pending = library.reorder(2, 0);
    expect(names().first, "Three");
    await pending;
  });
}
