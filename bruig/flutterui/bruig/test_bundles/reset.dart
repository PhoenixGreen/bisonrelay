// A test helper kept beside the bundles rather than under test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:bruig/components/file_openers.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/presets/drawn_styles.dart';
import 'package:bruig/plugin_system/canvas/render/render_caches.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/font_files.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/writing_library.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_editor_shell.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/effects_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets/presets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/settings_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_extras.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/stock_panel.dart';
import 'package:bruig/plugin_system/plugin_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

// reset.dart is what a test file finds as it starts when it runs in a bundle
// after others (see generate.dart): what the app keeps for a whole run --
// sections left open, kept pictures, where the library is, saved settings,
// whether ffmpeg is here -- as a new run has it.

/// betweenFiles puts back what one test file could leave for the next.
void betweenFiles() {
  forgetSectionsForTest();
  forgetPanelsForTest();
  forgetLooksForTest();
  forgetEffectsForTest();
  forgetDataEditorsForTest();
  // The sidebar's panels: the Presets chip pressed, where each element's
  // settings were scrolled to, the layer last clicked.
  CanvasPresetsPanel.forgetForTest();
  SettingsPanelBody.forgetForTest();
  forgetLayerPickForTest();
  // The asset thumbnails kept for the session, and the decoder of stock
  // video previews a test may have swapped for a fake.
  AssetThumb.forgetForTest();
  StockPanel.videoFrames = FfmpegFrames(ffmpegPath);
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
  DrawnStyles.forgetForTest();
  FontFiles.forgetForTest();
  // The Writing library a test handed the Canvas, over its own folder.
  WritingLibrary.forgetForTest();
  forgetFfmpegForTest();
  // What a feature registers as the app starts, and a test registers to
  // stand in for that: left behind, the next file's Settings page builds a
  // section it has given no provider for.
  PluginSettingsRegistry.forgetForTest();
  CanvasSidebarExtras.forgetForTest();
  FileOpeners.forgetForTest();
  SharedPreferences.setMockInitialValues({});
}
