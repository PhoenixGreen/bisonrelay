import 'package:bruig/models/feed.dart' show NewPostModel;
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// composer_resume_test.dart covers coming back to a half-written post.
//
// The Feed screen is built fresh by its route, so its State -- the tab that
// is open, the caret, the writing sidebar's page -- goes when the route
// does. Stepping away to read a message in Chat and coming back landed on
// the post list with the composer apparently gone. The draft was never lost;
// the way back to it was.
//
// The pieces below are the ones that had to move somewhere longer-lived, and
// these tests are about them surviving rather than about the widgets that
// read them.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // FeedModel.lastTab is not covered here: constructing a FeedModel loads
  // golib.dylib, which a unit test has no way to provide, and the field
  // itself is an int with no behaviour to get wrong. What it feeds -- the
  // Feed screen reading it in initState -- needs the running client too.

  group("the composer remembers where the caret was", () {
    test("a new post starts at the beginning", () {
      expect(NewPostModel().caret, 0);
    });

    test("clearing the post forgets the position with the text", () {
      var post = NewPostModel()
        ..content = "half a sentence"
        ..caret = 9;
      post.clear();
      expect(post.content, isEmpty);
      expect(post.caret, 0,
          reason: "a caret kept past the text it pointed into would put the "
              "cursor into the middle of the next post");
    });

    // The text can be changed from elsewhere -- a draft opened from the
    // library -- while the remembered position stays where it was.
    test("a position past the end is clamped by the caller", () {
      var post = NewPostModel()
        ..content = "short"
        ..caret = 400;
      expect(post.caret.clamp(0, post.content.length), 5);
    });
  });

  group("the composer remembers how far down it was scrolled", () {
    test("a new post starts at the top", () {
      expect(NewPostModel().scrollOffset, 0);
    });

    test("clearing the post scrolls back to the top", () {
      var post = NewPostModel()
        ..content = "many paragraphs"
        ..scrollOffset = 1840;
      post.clear();
      expect(post.scrollOffset, 0,
          reason: "an emptied composer left scrolled down shows nothing");
    });

    // Separate from the caret because the two genuinely differ: reading
    // back over what you have written moves the page without moving the
    // cursor.
    test("it is kept apart from the caret", () {
      var post = NewPostModel()
        ..caret = 4
        ..scrollOffset = 900;
      expect(post.caret, 4);
      expect(post.scrollOffset, 900);
    });
  });

  group("the writing sidebar remembers its page", () {
    test("it starts on the first page", () {
      expect(WritingPreferences().sidebarPage, 0);
    });

    // Held as an index because the enum lives in a file that imports this
    // one. A page removed from the enum has to land somewhere real rather
    // than out of range.
    test("an index past the end falls back to the first page", () {
      var prefs = WritingPreferences()..sidebarPage = 99;
      var at = prefs.sidebarPage;
      var page = at >= 0 && at < WritingSidebarPage.values.length
          ? WritingSidebarPage.values[at]
          : WritingSidebarPage.mistakes;
      expect(page, WritingSidebarPage.mistakes);
    });

    test("a page that was opened is the one returned to", () {
      var prefs = WritingPreferences()
        ..sidebarPage = WritingSidebarPage.document.index;
      expect(WritingSidebarPage.values[prefs.sidebarPage],
          WritingSidebarPage.document);
    });
  });
}
