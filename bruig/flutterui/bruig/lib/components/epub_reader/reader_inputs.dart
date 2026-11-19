import 'package:flutter/foundation.dart';

// reader_inputs.dart is what the reader can hand a book that asks to hear
// the reader play: a MIDI keyboard's keys. Apple's web engine and Android's
// web view have no Web MIDI, so a book asks Bison Relay for them through
// `window.bisonReader.midi(onKey)` (reader_shell.dart). The host supplies
// the keyboard -- Files, from the app's MIDI connection -- so the reader
// knows nothing of where keys come from. The microphone needs no bridge: a
// book asks for it the standard way, and the reader asks the person first.

abstract class ReaderInputs {
  /// listenToKeys hands [onKey] each key pressed (its MIDI note number and
  /// how hard, 1 to 127) and let go (velocity 0) on the keyboard,
  /// connecting the first one found if none is; it answers how to stop, or
  /// null where there is no keyboard. While a book listens, the keyboard is
  /// the book's alone: a canvas's instrument is not played by it too.
  Future<VoidCallback?> listenToKeys(
      void Function(int key, int velocity) onKey);
}
