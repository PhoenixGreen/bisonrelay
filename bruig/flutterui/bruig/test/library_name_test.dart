import 'package:bruig/plugin_system/writing_tools/composer_sidebar.dart';
import 'package:flutter_test/flutter_test.dart';

// library_name_test.dart pins what the writing library is called.
//
// "My Posts" was right when posts were all it held. It now holds the pages
// of a site, the fragments those pages share, notes, and whatever folders
// somebody has made -- so the name described a quarter of it and quietly
// suggested the rest did not belong.
//
// "Library" rather than "Files and Folders", which was the other candidate:
// the app already has a File Manager, listed as plain "Files" under at least
// one shipped theme, and that is downloads and shared content. Two sections
// wearing nearly the same name is worse than one wearing a slightly abstract
// one -- and Library is what the code has always called it.

void main() {
  test('the writing library is the Library', () {
    expect(ComposerPanel.posts.label, "Library");
  });

  test('and does not borrow the File Manager\'s name', () {
    var label = ComposerPanel.posts.label.toLowerCase();
    expect(label, isNot(contains("file")));
  });
}
