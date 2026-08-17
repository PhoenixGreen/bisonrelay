// notes.dart is the single entry point to notes. App code outside this
// directory imports the writing tools' own barrel (writing_tools.dart) and
// never reaches in here directly; tests are the exception.
//
// A note is somewhere to write about what is in front of you without leaving
// it. There is one button, at the foot of the content area, and what it opens
// depends on where you are: the file being previewed, the chat being read, the
// post being looked at. Behind that sits one app-wide note, which is both the
// fallback for a page that has nothing of its own and the place for writing
// that spans several pages.
//
// Two decisions shape everything here and are worth reading before changing
// anything:
//
//   Notes are documents. They are Markdown files in the post library, in a
//   reserved "Bison Relay Notes" folder, written through the same PostStorage
//   as every draft. So they are openable in the composer, spell-checked,
//   greppable, and readable by anything that reads text -- and a note that
//   turns out to be a post needs no conversion, only moving. The alternative
//   this replaced was a private JSON sidecar per file, which could do none of
//   that and could only ever describe files.
//
//   Pages declare, the host draws. A page says what its note is about by
//   wrapping itself in a NoteTargetScope; it does not draw a button, own a
//   panel, or know that notes exist beyond that one line. Everything visible
//   is drawn once, by NotesHost, around the content area.
//
// Layout:
//
//   note_target.dart    what "the page you are on" is: kind, key, label
//   note_targets.dart   how a page declares its target, and why upward
//   note_storage.dart   notes as .md, and the index that finds them by target
//   notes_model.dart    open/closed, local/global, height, autosave
//   notes_settings.dart the on/off switch and where the button sits
//
//   ui/
//     notes_button.dart  the three button forms
//     notes_panel.dart   the note, its Local/Global switch and its drag handle
//     notes_host.dart    the only place any of it is drawn
export 'package:bruig/plugin_system/writing_tools/notes/note_storage.dart';
export 'package:bruig/plugin_system/writing_tools/notes/note_target.dart';
export 'package:bruig/plugin_system/writing_tools/notes/note_targets.dart';
export 'package:bruig/plugin_system/writing_tools/notes/notes_model.dart';
export 'package:bruig/plugin_system/writing_tools/notes/notes_settings.dart';
export 'package:bruig/plugin_system/writing_tools/notes/ui/notes_host.dart';
