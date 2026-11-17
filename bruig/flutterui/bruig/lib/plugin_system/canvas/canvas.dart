// canvas.dart is the entry point to Bison Relay's canvas: composing
// pictures, charts, animations, video and music, and publishing them. App
// code outside this directory imports this file and nothing beneath it. It
// is app code behind a switch (canvas_preferences.dart), not a plugin
// capability. ARCHITECTURE.md covers its layers, storage, security, tests.
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/plugin_system.dart';

export 'package:bruig/plugin_system/canvas/canvas_nav.dart';
export 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
export 'package:bruig/plugin_system/canvas/canvas_settings.dart';
export 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
// A canvas file played where Files previews one: see canvas_file_player.dart.
export 'package:bruig/plugin_system/canvas/ui/screen/canvas_file_player.dart'
    show CanvasFilePlayer, openCanvasFile;
// The editing session and empty document, for main() to keep past the page.
export 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart'
    show emptyCanvas;
export 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart'
    show CanvasController;
// For main() to call first thing: see its note.
export 'package:bruig/plugin_system/canvas/media/audio_engine.dart'
    show releaseAudioAfterHotRestart;

/// registerCanvas attaches this module to the plugin system, once at startup.
/// It registers a feature, not a capability: the section appears when a
/// switch is on, and the plugin system stays unaware of Canvas.
void registerCanvas() {
  PluginSettingsRegistry.registerFeature(
    "canvas",
    (context, inPluginPanel) => const CanvasSettingsSection(),
  );
}
