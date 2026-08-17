import 'dart:convert';
import 'dart:io';

// reading_position.dart remembers how far into one of their files a reader
// had got, without changing the file itself.
//
// It is kept in a sidecar written beside the document -- "report.pdf" gets
// "report.pdf.brnotes" -- rather than in the app's own storage. That means
// the bookmark follows the file when it is moved, copied or backed up along
// with everything else in the folder, and a file deleted from disk takes its
// bookmark with it instead of leaving an orphaned row in a database keyed by
// a path that no longer resolves. The cost is a second file in the reader's
// download folder, which is why nothing is written until there is actually
// something to record (see ReadingPositionStore.save).
//
// This file used to hold the reader's notes as well, in the same sidecar.
// Notes have moved to the writing tools, where they are Markdown documents in
// the post library rather than a JSON field (see
// plugin_system/writing_tools/notes/). The position stayed behind, because it
// is not a note: it is a property of this file on this disk, it is written by
// the preview rather than typed by anyone, and "continue from page 12" has to
// keep working whether or not the Writing Tools plugin is enabled. A sidecar
// written by an older build still holds a "notes" key; it is simply not read,
// and is gone after the next write.

/// ReadingPosition is one file's sidecar contents.
class ReadingPosition {
  /// position is how far into the file the reader had got, measured in
  /// whatever unit that kind of file counts in -- the page number of a PDF,
  /// the scroll offset in pixels of a text file, seconds into a video or a
  /// recording. Zero means nothing has been recorded.
  ///
  /// One field rather than one per kind because a file only ever has one
  /// kind, and [positionKind] records which unit was written so a file that
  /// somehow changes type (a ".dat" renamed to ".pdf") can't be sent to page
  /// 4,000 by a scroll offset left behind by the text view.
  final double position;
  final String positionKind;

  const ReadingPosition({this.position = 0, this.positionKind = ""});

  static const empty = ReadingPosition();

  bool get isEmpty => position <= 0;

  /// positionFor is [position], but only when it was written by the same kind
  /// of view that is now asking for it.
  double? positionFor(String kind) =>
      position > 0 && positionKind == kind ? position : null;

  ReadingPosition copyWith({double? position, String? positionKind}) =>
      ReadingPosition(
        position: position ?? this.position,
        positionKind: positionKind ?? this.positionKind,
      );

  Map<String, dynamic> toJson() => {
        if (position > 0) "position": position,
        if (position > 0) "positionKind": positionKind,
      };

  factory ReadingPosition.fromJson(Map<String, dynamic> j) => ReadingPosition(
        position: (j["position"] as num?)?.toDouble() ?? 0,
        positionKind: j["positionKind"] as String? ?? "",
      );
}

class ReadingPositionStore {
  static const suffix = ".brnotes";

  static String sidecarFor(String filePath) => "$filePath$suffix";

  /// load reads a file's sidecar, or returns an empty one.
  ///
  /// Never throws: a sidecar that has been hand-edited into invalid JSON, or
  /// sits in a folder that has since become unreadable, must not stop the
  /// file it belongs to from being opened. An unreadable one reads as "no
  /// bookmark yet", and writing over it is how it gets fixed.
  static Future<ReadingPosition> load(String filePath) async {
    try {
      var file = File(sidecarFor(filePath));
      if (!await file.exists()) return ReadingPosition.empty;
      var decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return ReadingPosition.empty;
      return ReadingPosition.fromJson(decoded);
    } catch (_) {
      return ReadingPosition.empty;
    }
  }

  /// save writes a file's sidecar, removing it when there is nothing left to
  /// remember -- a file read back to its first page should leave the folder as
  /// it was found, not leave an empty file behind.
  ///
  /// Returns false if the write failed, which is a real possibility here and
  /// not an exceptional one: a file can perfectly well be sitting on a
  /// read-only volume or a share the reader can read but not write to.
  static Future<bool> save(String filePath, ReadingPosition at) async {
    try {
      var file = File(sidecarFor(filePath));
      if (at.isEmpty) {
        if (await file.exists()) await file.delete();
        return true;
      }
      await file.writeAsString(jsonEncode(at.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }
}
