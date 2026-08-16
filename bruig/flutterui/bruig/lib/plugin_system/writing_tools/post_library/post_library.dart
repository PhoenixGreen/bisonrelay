// post_library.dart is the single entry point to the saved-post library.
// Everything outside lib/post_library/ imports this file and nothing
// beneath it.
//
// The library is plain Markdown files in plain folders under
// "<appDataDir>/my-posts", beside downloads, palettes, themes and logs. It
// is deliberately not a plugin capability: a plugin runs with no filesystem
// and no network, and that sandbox is the whole reason installing one is
// safe. It shares the composer's sidebar slot with the writing tools, which
// is the only thing the two have in common.
//
// Contents:
//
//   post_storage.dart        the files on disk, and the name sanitizing
//   post_library_model.dart  what the sidebar is showing, and autosave
//   post_sidebar.dart        the sidebar itself
export 'package:bruig/plugin_system/writing_tools/post_library/post_library_model.dart';
export 'package:bruig/plugin_system/writing_tools/post_library/post_sidebar.dart';
export 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
