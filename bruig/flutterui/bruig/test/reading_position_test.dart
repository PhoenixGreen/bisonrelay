import 'dart:convert';
import 'dart:io';

import 'package:bruig/screens/manage_content/reading_position.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// reading_position_test.dart covers the sidecar a file's reading position
// lives in -- that it is written beside the file, that it is not written at
// all until there is something to say, and that a position is only handed
// back to the kind of view that recorded it.

void main() {
  late Directory dir;
  late String doc;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('brnotes');
    doc = path.join(dir.path, 'report.pdf');
    await File(doc).writeAsString('not really a pdf');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('the sidecar sits beside the file it belongs to', () {
    expect(ReadingPositionStore.sidecarFor(doc), '$doc.brnotes');
    // The extension is kept, not replaced: "report.pdf" and "report.txt" in
    // one folder are two files and must not share one bookmark.
    expect(path.basename(ReadingPositionStore.sidecarFor(doc)),
        'report.pdf.brnotes');
  });

  test('a file with nothing recorded reads as empty and writes nothing',
      () async {
    expect((await ReadingPositionStore.load(doc)).isEmpty, isTrue);

    await ReadingPositionStore.save(doc, ReadingPosition.empty);
    expect(File(ReadingPositionStore.sidecarFor(doc)).existsSync(), isFalse);
  });

  test('a position round-trips', () async {
    await ReadingPositionStore.save(
        doc, const ReadingPosition(position: 12, positionKind: 'pdf'));

    var back = await ReadingPositionStore.load(doc);
    expect(back.position, 12);
    expect(back.positionKind, 'pdf');
  });

  test('a position is only given back to the view that recorded it', () {
    const at = ReadingPosition(position: 12, positionKind: 'pdf');
    expect(at.positionFor('pdf'), 12);
    // A page number would send the text view 12 pixels down, and a scroll
    // offset would send the PDF thousands of pages in -- neither is a
    // position in the other's units, so neither is offered.
    expect(at.positionFor('text'), isNull);
    expect(ReadingPosition.empty.positionFor('pdf'), isNull);
  });

  test('going back to the start removes the sidecar', () async {
    await ReadingPositionStore.save(
        doc, const ReadingPosition(position: 12, positionKind: 'pdf'));
    expect(File(ReadingPositionStore.sidecarFor(doc)).existsSync(), isTrue);

    // Nothing left to remember should leave the folder as it was found
    // rather than an empty file behind.
    await ReadingPositionStore.save(doc, ReadingPosition.empty);
    expect(File(ReadingPositionStore.sidecarFor(doc)).existsSync(), isFalse);
  });

  test('a sidecar written by an older build still gives up its position',
      () async {
    // Notes used to share this file. The key is no longer read, and the
    // position beside it has to survive that -- somebody upgrading should not
    // lose their place in a book.
    await File(ReadingPositionStore.sidecarFor(doc)).writeAsString(jsonEncode({
      'notes': 'the bit about ports',
      'position': 12,
      'positionKind': 'pdf'
    }));

    var back = await ReadingPositionStore.load(doc);
    expect(back.position, 12);
    expect(back.positionKind, 'pdf');

    // ...and the next write drops the key rather than carrying it forever.
    await ReadingPositionStore.save(doc, back);
    var raw = jsonDecode(
        await File(ReadingPositionStore.sidecarFor(doc)).readAsString());
    expect((raw as Map).containsKey('notes'), isFalse);
  });

  test('a damaged sidecar reads as empty rather than throwing', () async {
    await File(ReadingPositionStore.sidecarFor(doc)).writeAsString('{not json');
    expect((await ReadingPositionStore.load(doc)).isEmpty, isTrue);

    // Valid JSON of the wrong shape is the same story.
    await File(ReadingPositionStore.sidecarFor(doc))
        .writeAsString(jsonEncode([1, 2]));
    expect((await ReadingPositionStore.load(doc)).isEmpty, isTrue);
  });

  test('a file that does not exist has no position and does not throw',
      () async {
    var missing = path.join(dir.path, 'gone', 'nothing.pdf');
    expect((await ReadingPositionStore.load(missing)).isEmpty, isTrue);
    // Saving into a folder that isn't there fails, and says so rather than
    // throwing out of the preview.
    expect(
        await ReadingPositionStore.save(
            missing, const ReadingPosition(position: 1, positionKind: 'pdf')),
        isFalse);
  });
}
