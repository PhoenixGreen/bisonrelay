import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// file_notes.dart is what a reader can add to one of their files without
// changing the file itself: notes of their own, and where in it they had got
// to.
//
// Both are kept in a sidecar written beside the document -- "report.pdf"
// gets "report.pdf.brnotes" -- rather than in the app's own storage. That
// means notes follow the file when it is moved, copied or backed up along
// with everything else in the folder, and a file deleted from disk takes its
// notes with it instead of leaving an orphaned row in a database keyed by a
// path that no longer resolves. The cost is a second file in the reader's
// download folder, which is why nothing is written until there is actually
// something to record (see FileNotesStore.save).

/// FileNotes is one file's sidecar contents.
@immutable
class FileNotes {
  /// notes is the reader's own text. Free-form and never parsed.
  final String notes;

  /// position is how far into the file they had got, measured in whatever
  /// unit that kind of file counts in -- the page number of a PDF, the
  /// scroll offset in pixels of a text file, seconds into a video or a
  /// recording. Zero means nothing has been recorded.
  ///
  /// One field rather than one per kind because a file only ever has one
  /// kind, and [positionKind] records which unit was written so a file that
  /// somehow changes type (a ".dat" renamed to ".pdf") can't be sent to
  /// page 4,000 by a scroll offset left behind by the text view.
  final double position;
  final String positionKind;

  const FileNotes({
    this.notes = "",
    this.position = 0,
    this.positionKind = "",
  });

  static const empty = FileNotes();

  bool get hasNotes => notes.trim().isNotEmpty;
  bool get hasPosition => position > 0;
  bool get isEmpty => !hasNotes && !hasPosition;

  /// positionFor is [position], but only when it was written by the same
  /// kind of view that is now asking for it.
  double? positionFor(String kind) =>
      hasPosition && positionKind == kind ? position : null;

  FileNotes copyWith({String? notes, double? position, String? positionKind}) =>
      FileNotes(
        notes: notes ?? this.notes,
        position: position ?? this.position,
        positionKind: positionKind ?? this.positionKind,
      );

  Map<String, dynamic> toJson() => {
        if (notes != "") "notes": notes,
        if (position > 0) "position": position,
        if (position > 0) "positionKind": positionKind,
      };

  factory FileNotes.fromJson(Map<String, dynamic> j) => FileNotes(
        notes: j["notes"] as String? ?? "",
        position: (j["position"] as num?)?.toDouble() ?? 0,
        positionKind: j["positionKind"] as String? ?? "",
      );
}

class FileNotesStore {
  static const suffix = ".brnotes";

  static String sidecarFor(String filePath) => "$filePath$suffix";

  /// load reads a file's sidecar, or returns an empty one.
  ///
  /// Never throws: a sidecar that has been hand-edited into invalid JSON, or
  /// sits in a folder that has since become unreadable, must not stop the
  /// file it belongs to from being opened. An unreadable one reads as "no
  /// notes yet", and writing over it is how it gets fixed.
  static Future<FileNotes> load(String filePath) async {
    try {
      var file = File(sidecarFor(filePath));
      if (!await file.exists()) return FileNotes.empty;
      var decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return FileNotes.empty;
      return FileNotes.fromJson(decoded);
    } catch (_) {
      return FileNotes.empty;
    }
  }

  /// save writes a file's sidecar, removing it when there is nothing left to
  /// remember -- clearing your notes should leave the folder as it was
  /// found, not leave an empty file behind.
  ///
  /// Returns false if the write failed, which is a real possibility here and
  /// not an exceptional one: a file can perfectly well be sitting on a
  /// read-only volume or a share the reader can read but not write to.
  static Future<bool> save(String filePath, FileNotes notes) async {
    try {
      var file = File(sidecarFor(filePath));
      if (notes.isEmpty) {
        if (await file.exists()) await file.delete();
        return true;
      }
      await file.writeAsString(jsonEncode(notes.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// hasNotes is the cheap check a file row makes to decide whether to show
  /// its note button as filled in. Synchronous because it is called from
  /// build, and it only stats a path.
  static bool hasNotesSync(String filePath) {
    try {
      return File(sidecarFor(filePath)).existsSync();
    } catch (_) {
      return false;
    }
  }
}

/// FileNotesPanel is the notes editor: a panel at the foot of whatever page
/// it is opened from, so the file stays visible above it while notes are
/// written about it. That is the whole point of it being a panel rather than
/// a dialog -- notes taken while reading, watching or listening are taken
/// *about* what is on screen.
class FileNotesPanel extends StatefulWidget {
  final String filePath;
  final VoidCallback onClose;

  /// height is how much of the page the panel takes. The preview page gives
  /// it less than the list pages do, having more worth keeping visible.
  final double height;

  const FileNotesPanel({
    required this.filePath,
    required this.onClose,
    this.height = 220,
    super.key,
  });

  @override
  State<FileNotesPanel> createState() => _FileNotesPanelState();
}

class _FileNotesPanelState extends State<FileNotesPanel> {
  final TextEditingController ctrl = TextEditingController();
  Timer? _debounce;
  bool loaded = false;
  // saveFailed is shown rather than swallowed: a reader typing into a box
  // that is quietly discarding every word is the one outcome this must not
  // have.
  bool saveFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FileNotesPanel old) {
    super.didUpdateWidget(old);
    // The panel stays put while the row it was opened from changes -- on the
    // Downloads page the list rebuilds on every progress tick. Only a
    // genuinely different file needs re-reading, and the pending edit for
    // the old one has to go out first.
    if (old.filePath != widget.filePath) {
      _flush(old.filePath);
      setState(() => loaded = false);
      _load();
    }
  }

  Future<void> _load() async {
    var notes = await FileNotesStore.load(widget.filePath);
    if (!mounted) return;
    setState(() {
      ctrl.text = notes.notes;
      loaded = true;
    });
  }

  /// _save merges the typed text into whatever else the sidecar holds,
  /// re-reading it first: the reading position is written to the same file
  /// by the preview above, and a save that started from this panel's own
  /// stale copy would put the reader back where they were an hour ago.
  Future<void> _flush(String filePath) async {
    _debounce?.cancel();
    var text = ctrl.text;
    var existing = await FileNotesStore.load(filePath);
    if (existing.notes == text) return;
    var ok =
        await FileNotesStore.save(filePath, existing.copyWith(notes: text));
    if (mounted) setState(() => saveFailed = !ok);
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 600), () => _flush(widget.filePath));
  }

  @override
  void dispose() {
    // Written out before the panel goes, so closing it is not a way to lose
    // the last thing typed into it.
    _flush(widget.filePath);
    _debounce?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.sticky_note_2_outlined, size: 18, color: cs.onSurface),
          const SizedBox(width: 8),
          const Expanded(child: Txt.M("Notes")),
          if (saveFailed)
            Txt.S("Could not save notes beside this file",
                color: TextColor.onErrorContainer),
          IconButton(
            iconSize: 18,
            icon: const Icon(Icons.close),
            tooltip: "Close notes",
            onPressed: widget.onClose,
          ),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: loaded
              // No Save button: the notes are saved as they are written,
              // like the post composer's drafts are. A button here would be
              // one more thing to forget to press.
              ? TextField(
                  controller: ctrl,
                  onChanged: _onChanged,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "Notes about this file. Saved as you type.",
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ]),
    );
  }
}

/// FileNotesButton is the note button a file row or a preview carries.
///
/// It shows whether there is anything to come back to -- a filled note icon
/// once the file has a sidecar -- so notes taken earlier are findable
/// without opening every file in the list to check.
class FileNotesButton extends StatelessWidget {
  final String filePath;
  final bool open;
  final VoidCallback onPressed;
  const FileNotesButton({
    required this.filePath,
    required this.onPressed,
    this.open = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var has = FileNotesStore.hasNotesSync(filePath);
    return IconButton(
      iconSize: 18,
      icon: Icon(has ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined),
      color: open ? Theme.of(context).colorScheme.primary : null,
      tooltip: has ? "Notes for this file" : "Add notes",
      onPressed: onPressed,
    );
  }
}
