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
// How it is built -- its layers and the rules between them, the document,
// the editor, storage, security and tests -- is in ARCHITECTURE.md beside
// this file.
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/plugin_system.dart';

export 'package:bruig/plugin_system/canvas/canvas_nav.dart';
export 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
export 'package:bruig/plugin_system/canvas/canvas_settings.dart';
export 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
// A canvas file played where Files previews one: see canvas_file_player.dart.
export 'package:bruig/plugin_system/canvas/ui/screen/canvas_file_player.dart'
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
