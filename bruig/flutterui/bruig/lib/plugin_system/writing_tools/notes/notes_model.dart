import 'dart:async';

import 'package:bruig/plugin_system/writing_tools/notes/note_storage.dart';
import 'package:bruig/plugin_system/writing_tools/notes/note_target.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_library_model.dart';
import 'package:bruig/storage_manager.dart';
import 'package:flutter/material.dart';

// notes_model.dart is the notes panel: whether it is open, which note it is
// showing, and getting what is typed onto disk.
//
// It holds the editor's controller itself rather than being handed one, which
// is the opposite of how PostLibraryModel works next door and is right for the
// same reason that one is right. The composer's text belongs to the composer
// and the library merely watches it; the note's text belongs to nothing else
// on screen, and the panel showing it is created and destroyed as it opens and
// closes. Something has to hold the text across that, and it is this.

/// minPanelHeight is the panel closed down to a single line of writing, plus
/// its own header.
///
/// It doubles as the point below which dragging closes the panel: a note you
/// cannot read one line of is not a smaller note, it is a note you are trying
/// to put away, and making the drag do that is cheaper than making somebody
/// find the button again.
const double minNotesPanelHeight = 116;

const double defaultNotesPanelHeight = 220;

class NotesModel extends ChangeNotifier {
  static const _heightKey = "notesPanelHeight";

  bool get open => _open;
  bool _open = false;

  /// scope is which of the two notes is on screen. Kept across opens: someone
  /// working out of the global note wants it still there on the next page.
  NoteScope get scope => _scope;
  NoteScope _scope = NoteScope.local;

  double get height => _height;
  double _height = defaultNotesPanelHeight;

  /// target is the page the panel is looking at, pushed in from
  /// NoteTargetModel. Null on a page with nothing of its own.
  NoteTarget? get target => _target;
  NoteTarget? _target;

  /// showing is the note actually open -- the page's, or the app-wide one
  /// when that is what was asked for or when there is nothing else.
  ///
  /// This is the single place the "falls back to global" rule lives, so
  /// nothing above has to ask whether a page has a note of its own before
  /// drawing anything.
  NoteTarget get showing => _scope == NoteScope.global || _target == null
      ? NoteTarget.global
      : _target!;

  /// hasLocal is whether the Local half of the switch means anything here.
  bool get hasLocal => _target != null;

  final TextEditingController editor = TextEditingController();

  /// loading is true between opening a note and having its text, so the panel
  /// shows nothing rather than an empty box somebody might start typing into
  /// before the file arrives and replaces it.
  bool get loading => _loading;
  bool _loading = false;

  /// saveFailed is shown rather than swallowed. Somebody typing into a box
  /// that is quietly discarding every word is the one outcome this must not
  /// have.
  bool get saveFailed => _saveFailed;
  bool _saveFailed = false;

  Timer? _debounce;
  DateTime? _dirtySince;
  bool _deferredNotify = false;

  /// _loaded is the note the editor's text belongs to, which is not always
  /// [showing] -- for the moment between switching notes and the new one
  /// arriving, it is still the old one, and a save in that window must write
  /// to where the text came from.
  NoteTarget? _loaded;
  bool _disposed = false;

  NotesModel() {
    editor.addListener(_onEdited);
    _loadHeight();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    editor.removeListener(_onEdited);
    editor.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// _deferNotify is [_notify] for the one caller that arrives mid-build.
  ///
  /// [setTarget] is driven from a ChangeNotifierProxyProvider, which updates
  /// during the build of the widget above -- and notifying listeners from
  /// inside a build is what Flutter refuses. Everything else here is a button
  /// press or the far side of an await and notifies straight away, because a
  /// panel that opened one frame late would be felt.
  void _deferNotify() {
    if (_deferredNotify || _disposed) return;
    _deferredNotify = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferredNotify = false;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _loadHeight() async {
    var saved = await StorageManager.readData(_heightKey);
    if (saved is num && saved >= minNotesPanelHeight) {
      _height = saved.toDouble();
      _notify();
    }
  }

  // --- opening and closing ---

  /// toggle is the notes button. Pressing it a second time puts the panel
  /// away, which is why it is one button rather than an open and a close.
  ///
  /// Returns when the note is on disk, so a caller that wants to ask whether
  /// there is one -- the button, deciding whether to draw itself filled in --
  /// is not asking a question the pending write has not answered yet.
  Future<void> toggle() => _open ? close() : openPanel();

  Future<void> openPanel() {
    if (_open) return Future.value();
    _open = true;
    _notify();
    return _reload();
  }

  Future<void> close() async {
    if (!_open) return;
    _open = false;
    _notify();
    // Written out before the panel goes, so closing it is not a way to lose
    // the last thing typed into it.
    await flush();
  }

  void setScope(NoteScope scope) {
    if (scope == _scope) return;
    // The note being left is written before the new one is read: they are
    // different files, and the pending edit belongs to the old one.
    unawaited(flush().then((_) {
      _scope = scope;
      _notify();
      return _reload();
    }));
  }

  /// setTarget is the page changing under an open panel.
  ///
  /// A local note follows you: walking from a file to a chat with the panel
  /// open swaps the note, because "the note for what I am looking at" is what
  /// the panel is. The global note does not, because it is not about anything.
  void setTarget(NoteTarget? target) {
    if (target == _target) return;
    _target = target;
    _deferNotify();
    if (!_open || _scope == NoteScope.global) return;
    unawaited(flush().then((_) => _reload()));
  }

  Future<void> _reload() async {
    var wanted = showing;
    _loading = true;
    _notify();

    var text = await NoteStorage.read(wanted);
    // Somewhere else moved on while this read was in flight -- a fast walk
    // between two pages. That read's result belongs to a note nobody is
    // looking at any more, and writing it into the editor would put one
    // page's note under another page's title.
    if (_disposed || showing != wanted) return;

    editor.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _loaded = wanted;
    _dirtySince = null;
    _debounce?.cancel();
    _loading = false;
    _saveFailed = false;
    _notify();
  }

  // --- the height ---

  /// setHeight is the drag handle. Not persisted until the drag ends, so one
  /// gesture is one write rather than one per frame.
  void setHeight(double height) {
    if (height == _height) return;
    _height = height;
    _notify();
  }

  void saveHeight() => StorageManager.saveData(_heightKey, _height);

  // --- saving ---

  void _onEdited() {
    // Nothing is saved until a note has actually been loaded. Without this,
    // the controller being filled in by _reload would itself look like an
    // edit and write the note straight back.
    if (!_open || _loading || _loaded == null) return;

    // The ceiling, checked before the debounce is renewed: renewing it is
    // exactly what a steady typist does forever. Same two timers as the post
    // library, and deliberately the same numbers -- a note and a draft are
    // the same kind of writing and should not lose different amounts of it.
    var since = _dirtySince;
    if (since == null) {
      _dirtySince = DateTime.now();
    } else if (DateTime.now().difference(since) >= maxAutosaveInterval) {
      _debounce?.cancel();
      unawaited(_save());
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(autosaveDelay, () => unawaited(_save()));
  }

  /// flush writes any pending edit now, for a caller about to close the panel
  /// or load something else over the top.
  Future<void> flush() async {
    if (_debounce?.isActive != true && _dirtySince == null) return;
    _debounce?.cancel();
    await _save();
  }

  Future<void> _save() async {
    var to = _loaded;
    if (to == null) return;
    _dirtySince = null;
    var ok = await NoteStorage.write(to, editor.text);
    if (_disposed || _saveFailed == !ok) return;
    _saveFailed = !ok;
    _notify();
  }
}
