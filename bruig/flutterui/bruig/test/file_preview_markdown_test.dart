import 'dart:convert';
import 'dart:io';

import 'package:bruig/screens/manage_content/file_preview.dart';
import 'package:bruig/theming_system/model/area_style.dart';
import 'package:flutter_test/flutter_test.dart';

// file_preview_markdown_test.dart covers how a Markdown file is treated in
// the Files section.
//
// It was filed with .go and .sh and shown as its own source, which is right
// for a file you are inspecting and wrong for one you are reading. A
// document somebody bought or was sent is a thing to read.

void main() {
  group('what kind of file this is', () {
    test('markdown is read, not inspected', () {
      expect(fileKindOf("/x/guide.md"), FileKind.markdown);
      expect(fileKindOf("/x/GUIDE.MD"), FileKind.markdown);
      expect(fileKindOf("/x/guide.markdown"), FileKind.markdown);
    });

    test('source files are still source', () {
      // The distinction is the point: .go is a thing to look at.
      for (var p in ["/x/main.go", "/x/a.dart", "/x/n.txt", "/x/c.json"]) {
        expect(fileKindOf(p), FileKind.text, reason: p);
      }
    });

    test('the other kinds are unchanged', () {
      expect(fileKindOf("/x/a.pdf"), FileKind.pdf);
      expect(fileKindOf("/x/a.png"), FileKind.image);
      expect(fileKindOf("/x/a.mp4"), FileKind.video);
      expect(fileKindOf("/x/a.zip"), FileKind.other);
    });

    test('a name that only looks like one is not one', () {
      expect(fileKindOf("/x/notes.md.zip"), FileKind.other);
    });
  });

  group('reading the bytes', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp("preview"));
    tearDown(() async => dir.delete(recursive: true));

    test('a document is decoded as UTF-8, not as bytes', () async {
      // fromCharCodes reads each byte as a code unit, so every accented
      // letter, dash and quotation mark written on anything but an American
      // keyboard came out as two wrong characters.
      var f = File("${dir.path}/a.md");
      const text = "# Café — “quoted”\n\nnaïve\n";
      await f.writeAsBytes(utf8.encode(text));

      var bytes = await f.readAsBytes();
      expect(utf8.decode(bytes, allowMalformed: true), text);
      expect(String.fromCharCodes(bytes), isNot(text),
          reason: "if these agree the test is not testing anything");
    });

    test('bytes cut mid-character do not throw', () async {
      // The reader caps at 512 KB, and a cap lands where it lands.
      var bytes = utf8.encode("héllo");
      var cut = bytes.sublist(0, 2);
      expect(() => utf8.decode(cut, allowMalformed: true), returnsNormally);
    });
  });

  group('the reading preference', () {
    // A display choice, and it says so: the file is on this machine and the
    // source is a press away either way. What is worth pinning is that it
    // defaults to reading and survives being saved -- a setting that
    // silently reverts is worse than one not offered at all.
    test('defaults to reading the document', () {
      expect(const AreaStyle().readMarkdown, isTrue);
    });

    test('survives a round trip when turned off', () {
      var off = const AreaStyle().copyWith(readMarkdown: false);
      expect(AreaStyle.fromJson(off.toJson()).readMarkdown, isFalse);
    });

    test('and when left alone', () {
      var on = const AreaStyle();
      expect(AreaStyle.fromJson(on.toJson()).readMarkdown, isTrue);
      expect(on.toJson().containsKey("readMarkdown"), isFalse,
          reason: "the default is not worth writing down");
    });
  });
}
