import 'dart:io';

import 'package:bruig/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  var home = homeDir();
  var sep = p.separator;

  group('displayPath', () {
    test('hides the home directory, which carries the account name', () {
      var full =
          p.join(home, "Library", "Application Support", "bruig", "pages");
      expect(displayPath(full),
          "~${sep}Library${sep}Application Support${sep}bruig${sep}pages");
      // The point of the exercise: no account name left in what is shown.
      expect(displayPath(full), isNot(contains(home)));
    });

    test('home itself is just ~', () {
      expect(displayPath(home), "~");
    });

    test('a sibling that merely shares the prefix is left alone', () {
      // The naive startsWith(home) turns "/Users/kim2/x" into "~2/x" for
      // user "kim" -- a path that does not exist and cannot be pasted back.
      var sibling = "$home${2}${sep}pages";
      expect(displayPath(sibling), sibling);
    });

    test('a path outside home is shown in full', () {
      var outside = Platform.isWindows ? r"D:\srv\pages" : "/srv/pages";
      expect(displayPath(outside), outside);
    });

    test('empty stays empty', () {
      expect(displayPath(""), "");
    });

    test('round-trips through cleanAndExpandPath', () {
      // What is shown has to still mean the same directory, or the reader
      // cannot paste it back into the config file.
      var full = p.join(home, "Library", "bruig", "pages");
      expect(cleanAndExpandPath(displayPath(full)), p.canonicalize(full));
    });
  });
}
