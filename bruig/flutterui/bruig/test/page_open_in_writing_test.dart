import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// page_open_in_writing_test.dart covers handing a page to the Writing area.
//
// My Site asks for a document and then navigates, so at the moment of asking
// the composer does not exist yet and there is nothing to open the document
// into. Without the wait below, open() found no editor and quietly did
// nothing -- the reader arrived at the Writing page holding whatever was
// there before.

/// _settled waits for the model to stop changing.
///
/// The deferred open reads a file, which is several turns of the event loop
/// and real I/O -- a single microtask is not enough, and a fixed delay is a
/// race waiting to be flaky on a loaded machine.
Future<void> _settled(PostLibraryModel model,
    {Duration limit = const Duration(seconds: 2)}) async {
  var deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (model.openName != null) return;
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("bruig-open-test");
    PostStorage.rootOverride = root.path;
    await PostStorage.write(pagesFolderName, "about", "# About me");
  });

  tearDown(() async {
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('asked for before there is an editor, it waits and then opens',
      () async {
    var model = PostLibraryModel();
    await model.requestOpen(pagesFolderName, "about");

    // Nothing to open into yet, so nothing is open.
    expect(model.openName, isNull);
    // But the sidebar is already showing the folder it will arrive in.
    expect(model.folder, pagesFolderName);

    var editor = TextEditingController();
    model.watch(editor);
    await _settled(model);

    expect(model.openName, "about");
    expect(model.openFolder, pagesFolderName);
    expect(editor.text, "# About me");
  });

  test('asked for with an editor already there, it opens straight away',
      () async {
    var editor = TextEditingController();
    var model = PostLibraryModel()..watch(editor);

    await model.requestOpen(pagesFolderName, "about");
    await _settled(model);

    expect(model.openName, "about");
    expect(editor.text, "# About me");
  });

  test('a second editor does not reopen what was already handled', () async {
    var model = PostLibraryModel();
    await model.requestOpen(pagesFolderName, "about");

    model.watch(TextEditingController());
    await _settled(model);
    expect(model.openName, "about");

    // A rebuild hands over a fresh controller. The request is spent, so
    // this one is left empty rather than being filled with a page the
    // reader may have navigated away from.
    var second = TextEditingController();
    model.watch(second);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(second.text, isEmpty);
  });
}
