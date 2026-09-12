import 'package:bruig/storage_manager.dart';
import 'package:flutter/material.dart';

// saved_colors.dart is the colours somebody has kept.
//
// One list for the whole app. A colour saved while setting a canvas
// background is the same colour wanted five minutes later on a shape, on a
// chart series, in the palette editor -- keeping a separate list per picker
// would mean saving it again in each of them.
//
// It is small on purpose: two rows of swatches under the picker, and no
// names, folders or ordering. A palette that needs managing is a feature of
// its own; this is the row of colours a person is working with today.

/// savedColorsPerRow is how many swatches fit across the picker.
const int savedColorsPerRow = 10;

/// savedColorsLimit is two rows of them, which is the whole of the room this
/// is allowed to take under the picker.
const int savedColorsLimit = savedColorsPerRow * 2;

/// SavedColors is that list, kept on disk and shared by every picker.
///
/// A singleton rather than something provided: a colour added in a dialog
/// over the canvas must appear in the palette editor's picker without either
/// of them knowing the other exists, and there is exactly one list.
class SavedColors extends ChangeNotifier {
  SavedColors._();

  static final SavedColors instance = SavedColors._();

  final List<Color> _colors = [];
  bool _loaded = false;

  /// colors is what is saved, oldest first.
  List<Color> get colors => List.unmodifiable(_colors);

  bool get isFull => _colors.length >= savedColorsLimit;

  /// has is whether this exact colour is already saved -- alpha included, so
  /// a half-transparent black and an opaque one are two colours.
  bool has(Color color) => _colors.any((c) => _same(c, color));

  /// load reads the list once. Called by every picker as it opens; the ones
  /// after the first are free.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    var saved = await StorageManager.readString(StorageManager.savedColorsKey);
    if (saved.isEmpty) return;
    for (var part in saved.split(",")) {
      var value = int.tryParse(part.trim(), radix: 16);
      if (value == null) continue;
      _colors.add(Color(value));
      if (isFull) break;
    }
    notifyListeners();
  }

  /// add keeps [color], unless it is already there or there is no room.
  Future<void> add(Color color) async {
    if (isFull || has(color)) return;
    _colors.add(color);
    notifyListeners();
    await _write();
  }

  /// remove drops it. Nothing happens if it was never saved, which is what
  /// pressing remove on a colour that came off the wheel should do.
  Future<void> remove(Color color) async {
    var before = _colors.length;
    _colors.removeWhere((c) => _same(c, color));
    if (_colors.length == before) return;
    notifyListeners();
    await _write();
  }

  Future<void> _write() => StorageManager.saveString(
        StorageManager.savedColorsKey,
        _colors.map((c) => c.toARGB32().toRadixString(16)).join(","),
      );

  /// _same compares the pixels rather than the objects. Two Colors built the
  /// same way are equal, but one that has been through a hex field and back
  /// may carry a different colour space, and == takes that into account.
  static bool _same(Color a, Color b) => a.toARGB32() == b.toARGB32();

  /// forget is for tests: the store outlives a widget, so one test's saved
  /// colours would otherwise be the next one's.
  @visibleForTesting
  void forget() {
    _colors.clear();
    _loaded = false;
  }
}
