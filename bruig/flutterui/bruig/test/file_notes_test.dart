import 'dart:convert';
import 'dart:io';

import 'package:bruig/screens/manage_content/file_notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// file_notes_test.dart covers the sidecar a file's notes and reading
// position live in -- that it is written beside the file, that it is not
// written at all until there is something to say, and that a position is
// only handed back to the kind of view that recorded it.

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
    expect(FileNotesStore.sidecarFor(doc), '$doc.brnotes');
    // The extension is kept, not replaced: "report.pdf" and "report.txt" in
    // one folder are two files and must not share one set of notes.
    expect(path.basename(FileNotesStore.sidecarFor(doc)), 'report.pdf.brnotes');
  });

  test('a file with nothing recorded reads as empty and writes nothing',
      () async {
    expect((await FileNotesStore.load(doc)).isEmpty, isTrue);
    expect(FileNotesStore.hasNotesSync(doc), isFalse);

    await FileNotesStore.save(doc, FileNotes.empty);
    expect(File(FileNotesStore.sidecarFor(doc)).existsSync(), isFalse);
  });

  test('notes and a position round-trip', () async {
    await FileNotesStore.save(
        doc,
        const FileNotes(
            notes: 'the bit about ports', position: 12, positionKind: 'pdf'));

    var back = await FileNotesStore.load(doc);
    expect(back.notes, 'the bit about ports');
    expect(back.position, 12);
    expect(back.positionKind, 'pdf');
    expect(FileNotesStore.hasNotesSync(doc), isTrue);
  });

  test('a position is only given back to the view that recorded it', () async {
    const notes =
        FileNotes(position: 12, positionKind: 'pdf', notes: 'somewhere');
    expect(notes.positionFor('pdf'), 12);
    // A page number would send the text view 12 pixels down, and a scroll
    // offset would send the PDF thousands of pages in -- neither is a
    // position in the other's units, so neither is offered.
    expect(notes.positionFor('text'), isNull);
    expect(const FileNotes(notes: 'x').positionFor('pdf'), isNull);
  });

  test('clearing the notes and the position removes the sidecar', () async {
    await FileNotesStore.save(doc, const FileNotes(notes: 'temporary'));
    expect(File(FileNotesStore.sidecarFor(doc)).existsSync(), isTrue);

    // Emptying the notes should leave the folder as it was found rather
    // than an empty file behind.
    await FileNotesStore.save(doc, const FileNotes(notes: ''));
    expect(File(FileNotesStore.sidecarFor(doc)).existsSync(), isFalse);
    expect(FileNotesStore.hasNotesSync(doc), isFalse);
  });

  test('a position outlives the notes it was saved with', () async {
    await FileNotesStore.save(
        doc, const FileNotes(notes: 'x', position: 4, positionKind: 'pdf'));
    var existing = await FileNotesStore.load(doc);
    await FileNotesStore.save(doc, existing.copyWith(notes: ''));

    var back = await FileNotesStore.load(doc);
    expect(back.notes, '');
    expect(back.position, 4);
    // Still a file, because there is still a place to go back to.
    expect(File(FileNotesStore.sidecarFor(doc)).existsSync(), isTrue);
  });

  test('a damaged sidecar reads as empty rather than throwing', () async {
    await File(FileNotesStore.sidecarFor(doc)).writeAsString('{not json');
    expect((await FileNotesStore.load(doc)).isEmpty, isTrue);

    // Valid JSON of the wrong shape is the same story.
    await File(FileNotesStore.sidecarFor(doc))
        .writeAsString(jsonEncode([1, 2]));
    expect((await FileNotesStore.load(doc)).isEmpty, isTrue);
  });

  test('a file that does not exist has no notes and does not throw', () async {
    var missing = path.join(dir.path, 'gone', 'nothing.pdf');
    expect((await FileNotesStore.load(missing)).isEmpty, isTrue);
    expect(FileNotesStore.hasNotesSync(missing), isFalse);
    // Saving into a folder that isn't there fails, and says so rather than
    // throwing out of the notes panel.
    expect(await FileNotesStore.save(missing, const FileNotes(notes: 'x')),
        isFalse);
  });
}
