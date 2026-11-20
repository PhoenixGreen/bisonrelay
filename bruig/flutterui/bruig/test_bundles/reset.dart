// A test helper kept beside the bundles rather than under test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/render/render_caches.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_editor_shell.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

// reset.dart is what a test file finds as it starts when it runs in a bundle
// after others (see generate.dart): what the app keeps for a whole run --
// sections left open, kept pictures, where the library is, saved settings,
// whether ffmpeg is here -- as a new run has it.

/// betweenFiles puts back what one test file could leave for the next.
void betweenFiles() {
  forgetSectionsForTest();
  forgetPanelsForTest();
  forgetDataEditorsForTest();
  clearRenderCaches();
  CanvasLibrary.resetForTest();
  CanvasStorage.rootOverride = null;
  // A read begun under one file's clock never finishes under the next's,
  // and a later load would wait on it forever: each file reads afresh.
  ElementPresetStore.instance.forget();
  for (var store in [
    SavedPresetStore.scenes,
    SavedPresetStore.canvases,
    SavedPresetStore.brushes,
    SavedPresetStore.pitchViews,
    SavedPresetStore.looks,
    SavedPresetStore.paintBrushes,
    SavedPresetStore.devices,
  ]) {
    store.forget();
  }
  forgetFfmpegForTest();
  SharedPreferences.setMockInitialValues({});
}
