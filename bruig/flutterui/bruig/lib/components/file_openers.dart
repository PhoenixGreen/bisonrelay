import 'package:flutter/widgets.dart';

// file_openers.dart lets a feature open a kind of file the app itself knows
// nothing about, when it is opened from Files or Downloads -- a style
// profile sent by a friend, say -- instead of handing it to the computer.
//
// The screens ask; the feature answers. A feature registers from its own
// start-up, and the screens never name it, so turning it off (or taking it
// out) leaves them opening files as they always did.

/// FileOpener opens [path] and says true, or says false to leave it alone.
typedef FileOpener = bool Function(BuildContext context, String path);

class FileOpeners {
  FileOpeners._();

  static final Map<String, FileOpener> _openers = {};

  /// register adds [opener] under [name], replacing one of that name.
  static void register(String name, FileOpener opener) =>
      _openers[name] = opener;

  /// open lets the first feature that wants [path] open it. False when none
  /// does, and the caller opens it the usual way.
  static bool open(BuildContext context, String path) {
    for (var opener in _openers.values) {
      if (opener(context, path)) return true;
    }
    return false;
  }
}
