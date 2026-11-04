// canvas.dart is the entry point to Bison Relay's canvas: the section for
// composing pictures, charts, animations, video and music, and the code that
// turns one into something publishable. App code outside this directory is
// meant to import this file and nothing beneath it; tests reach straight into
// model/, render/ and export/.
//
// It sits under lib/plugin_system/ because it can be turned off entirely, but
// it is not the app's half of a plugin capability: it is app code behind a
// switch. See canvas_preferences.dart.
//
// Layout:
//
//   model/     the document and its elements; no Flutter beyond dart:ui
//   render/    document plus frame number, into a ui.Canvas
//   media/     sound, speech, MIDI and video playback; media/mix is the mix
//              engine an export and the editor share
//   storage/   documents, pictures, media and presets on disk
//   export/    a document, into files (images, video, audio, PDF, EPUB) and
//              the places they are published to
//   presets/   built-in canvases, element presets and background looks
//   ui/        the page: screen, controller, stage, timeline, settings
//
// The rule that keeps this readable: render/ and export/ know nothing about
// widgets, a BuildContext or the app's theme. The same code draws the editing
// stage and the exported file, and an export that read the theme would
// change with what the sender's app happened to look like.
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/plugin_system.dart';

export 'package:bruig/plugin_system/canvas/canvas_nav.dart';
export 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
export 'package:bruig/plugin_system/canvas/canvas_settings.dart';
export 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
// A canvas file played where Files previews one: see canvas_file_player.dart.
export 'package:bruig/plugin_system/canvas/ui/canvas_file_player.dart'
    show CanvasFilePlayer, openCanvasFile;
// The editing session and the empty document, so main() can provide one that
// outlives the page. Nothing else outside this directory should need either.
export 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart'
    show emptyCanvas;
export 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart'
    show CanvasController;
// For main() to call first thing: see its note.
export 'package:bruig/plugin_system/canvas/media/audio_engine.dart'
    show releaseAudioAfterHotRestart;

/// registerCanvas attaches this module to the plugin system, once at startup.
///
/// It registers a feature rather than a capability: the section appears when
/// a switch is turned on, not when a provider is installed, and the plugin
/// system stays unaware of Canvas. See canvas_preferences.dart.
void registerCanvas() {
  PluginSettingsRegistry.registerFeature(
    "canvas",
    (context, inPluginPanel) => const CanvasSettingsSection(),
  );
}
