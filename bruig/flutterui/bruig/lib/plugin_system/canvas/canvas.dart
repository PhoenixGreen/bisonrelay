// canvas.dart is the entry point to Bison Relay's canvas: composing
// pictures, charts, animations, video and music, and publishing them. App
// code outside this directory imports this file and nothing beneath it. It
// is app code behind a switch (canvas_preferences.dart), not a plugin
// capability. ARCHITECTURE.md covers its layers, storage, security, tests.
import 'package:bruig/components/file_openers.dart';
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/canvas/model/image_action_file.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_actions.dart';
import 'package:bruig/plugin_system/plugin_system.dart';

export 'package:bruig/plugin_system/canvas/canvas_nav.dart' show CanvasNavModel;
export 'package:bruig/plugin_system/canvas/canvas_preferences.dart'
    show CanvasPreferences;
export 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart'
    show CanvasScreen;
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
export 'package:bruig/plugin_system/canvas/media/midi_input.dart'
    show MidiInput;
// For a feature outside Canvas to add a sidebar of its own, and to read and
// change the open canvas as JSON (an assistant, a script): see each file.
export 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_extras.dart'
    show CanvasSidebarExtra, CanvasSidebarExtras;
export 'package:bruig/plugin_system/canvas/ui/scripting/canvas_scripting.dart'
    show CanvasScripting;
export 'package:bruig/plugin_system/canvas/model/canvas_document.dart'
    show CanvasDocument;
// For the app to hand the Canvas the Writing library a text reads from and
// a canvas is published into: see writing_library.dart.
export 'package:bruig/plugin_system/canvas/storage/writing_library.dart'
    show WritingLibrary;
export 'package:bruig/plugin_system/canvas/model/text_document.dart'
    show TextDocumentRef;

/// registerCanvas attaches this module to the plugin system, once at startup.
/// It registers a feature, not a capability: the section appears when a
/// switch is on, and the plugin system stays unaware of Canvas.
void registerCanvas() {
  PluginSettingsRegistry.registerFeature(
    "canvas",
    (context, inPluginPanel) => const CanvasSettingsSection(),
  );
  // An image action sent by a friend opens into a picture's Actions.
  FileOpeners.register("canvas", (context, file) {
    if (!file.toLowerCase().endsWith(imageActionExtension)) return false;
    importImageActionFile(context, file);
    return true;
  });
}
