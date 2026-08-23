import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// folder_label_test.dart covers the one folder whose stored name and shown
// name differ.
//
// "Partials" is what the directory has always been called, on disk and in
// what the pages provider serves. It is also templating jargon that means
// nothing to somebody writing a page, and everywhere else in the app these
// are fragments -- the Pages section lists "Shared fragments" and offers
// "New fragment", and the block that pulls one in is "Shared fragment".

void main() {
  group('what a folder is called on screen', () {
    test('partials are fragments', () {
      expect(folderLabel(partialsFolderName), "Fragments");
    });

    test('every other folder is called what it is called', () {
      expect(folderLabel(pagesFolderName), pagesFolderName);
      expect(folderLabel(storeFolderName), storeFolderName);
      expect(folderLabel("Drafts"), "Drafts");
      expect(folderLabel(""), "");
    });

    test('the stored name is untouched', () {
      // The label moves and the directory does not. Renaming the directory
      // would mean moving a writer's own documents on startup, which is a
      // real risk to their work in exchange for a word.
      expect(partialsFolderName, "Partials");
      expect(reservedFolderNames, contains("Partials"));
    });

    test('a folder is not found by its label', () {
      // The label is for reading, never for looking a folder up. Something
      // asking storage for "Fragments" is asking for a folder that is not
      // there, and would quietly create it.
      expect(reservedFolderNames, isNot(contains("Fragments")));
    });
  });
}
