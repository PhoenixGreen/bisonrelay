import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:flutter_test/flutter_test.dart';

// post_storage_test.dart covers the part of the saved-post library that has
// to be right: what happens to a name on its way to the filesystem.
//
// Every folder and document name comes from a text field, and each one is
// used as a path segment. A name with a separator in it, or one made of dots,
// would write outside the library -- so the rule is a known-safe set of
// characters rather than a list of dangerous ones, and these tests are the
// evidence that the set holds.

void main() {
  group("sanitizeName keeps names inside the library", () {
    // The traversal cases. None of these may survive as anything that could
    // still climb out of the folder it is joined to.
    test("path traversal cannot survive", () {
      for (var attempt in [
        "../../config",
        "..",
        "../",
        "..\\..\\windows",
        "/etc/passwd",
        r"C:\Windows\system32",
        "foo/../bar",
        "./hidden",
      ]) {
        var safe = PostStorage.sanitizeName(attempt);
        if (safe == null) continue;
        expect(safe, isNot(contains("/")), reason: attempt);
        expect(safe, isNot(contains(r"\")), reason: attempt);
        expect(safe, isNot(startsWith(".")), reason: attempt);
        expect(safe, isNot(".."), reason: attempt);
      }
    });

    // A leading dot hides the file on every unix, and the listing skips
    // dotfiles -- so a name that kept one would save something the library
    // could never show again.
    test("a name cannot start with a dot", () {
      expect(PostStorage.sanitizeName(".bashrc"), isNot(startsWith(".")));
      expect(PostStorage.sanitizeName("..."), isNull);
    });

    test("a name of nothing usable is refused outright", () {
      for (var attempt in ["", "   ", "///", "..", "---", "\n\t"]) {
        expect(PostStorage.sanitizeName(attempt), isNull, reason: attempt);
      }
    });

    test("ordinary names come through unchanged", () {
      for (var name in [
        "Draft on routing fees",
        "release-notes",
        "notes_2026",
        "Post (final)",
        "v2",
      ]) {
        expect(PostStorage.sanitizeName(name), name, reason: name);
      }
    });

    test("what is replaced does not pile up", () {
      // A run of rejected characters becomes one dash, not one each.
      expect(PostStorage.sanitizeName("a???b"), "a-b");
      expect(PostStorage.sanitizeName("what: now"), "what- now");
    });

    test("a name is bounded", () {
      var long = PostStorage.sanitizeName("a" * 400);
      expect(long, isNotNull);
      expect(long!.length, lessThanOrEqualTo(maxNameLength));
    });

    // The name is what the user typed and what they will look for in a file
    // manager, so the folding must not quietly change the letters.
    test("letters, digits and spaces are preserved", () {
      expect(PostStorage.sanitizeName("Chapter 12 draft"), "Chapter 12 draft");
    });
  });

  group("suggestName", () {
    test("uses the first heading, without its hashes", () {
      expect(PostStorage.suggestName("# Routing fees\n\nSome text"),
          "Routing fees");
      expect(PostStorage.suggestName("### Deep heading"), "Deep heading");
    });

    test("falls back to the first words when there is no heading", () {
      expect(
          PostStorage.suggestName("Some thoughts about fees and how they "
              "are computed across the network"),
          "Some thoughts about fees and how they are");
    });

    test("skips blank lines to find something", () {
      expect(PostStorage.suggestName("\n\n\n  \n# Later heading"),
          "Later heading");
    });

    // A name is needed even for an empty editor: the dialog has to prefill
    // with something, and refusing to open it would be worse.
    test("empty text still yields a name", () {
      expect(PostStorage.suggestName(""), "Untitled");
      expect(PostStorage.suggestName("   \n  "), "Untitled");
    });

    // The suggestion goes straight into the name field, so it has to already
    // be a name.
    test("the suggestion is itself safe", () {
      var suggested = PostStorage.suggestName("# ../../etc/passwd");
      expect(PostStorage.sanitizeName(suggested), suggested);
      expect(suggested, isNot(contains("/")));
    });
  });
}
