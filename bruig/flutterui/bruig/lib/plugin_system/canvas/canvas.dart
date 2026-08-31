// canvas.dart is the single entry point to Bison Relay's canvas: the page for
// composing pictures, charts, diagrams and short animations, and the machinery
// that turns one into something publishable. App code outside this directory
// imports this file and nothing beneath it. Tests are the exception and reach
// straight into model/, render/ and export/, which is the point of those being
// separable at all.
//
// It sits under lib/plugin_system/ for the same reason writing_tools/ does:
// it is a feature that can be turned off entirely, and everything that can be
// turned off is gathered in one place. It is still its own module -- it
// imports the plugin machinery and the machinery imports nothing from here.
//
// Unlike the writing tools, Canvas is not the app's half of a plugin
// capability. It provides nothing and consumes nothing; it is app code behind
// a switch, like notes. See canvas_preferences.dart, which is the whole of the
// difference.
//
// Layout:
//
//   model/             no Flutter beyond dart:ui; testable on its own
//     canvas_geometry.dart   the two sizes a document has, and the ratios
//     canvas_element.dart    what every element has, and nothing else
//     canvas_animation.dart  keyframes, easing and the timeline's markers
//     canvas_document.dart   a whole canvas, and its file format
//     procedural_spec.dart   the recipe for a generated background
//     text_spec.dart         how text looks, wherever it appears
//     elements/              one file per kind of element
//
//   render/            document plus frame number, into a ui.Canvas
//     scene_renderer.dart    the one place a canvas becomes pixels
//     paint_util.dart        text layout, boxes and shape paths
//     chart_painter.dart     eleven chart types, drawn from scratch
//     table_painter.dart     a grid of text, sized to its contents
//     image_store.dart       decoding, and the three ways to cut a
//                            background out
//     procedural/            the fifteen background generators, the noise
//                            they draw from, and the sports pitches
//
//   storage/           documents and pictures on disk
//     canvas_storage.dart    the library: folders and .bcanvas documents
//     canvas_assets.dart     the pictures those documents refer to
//
//   export/            a document, into bytes somebody can be sent
//     canvas_export.dart     PNG, JPEG and GIF, and the size estimates
//     gif_encoder.dart       GIF89a, written out: palette, dither, LZW
//     publish_targets.dart   the four places a canvas can go
//     publish_record.dart    where it has already gone, so it can be updated
//
//   presets/           the canvases the Presets tab starts you from
//
//   ui/                the page
//     canvas_screen.dart     the section itself
//     canvas_controller.dart the editing session: selection, undo, playback
//     canvas_stage.dart      the canvas you can touch
//     canvas_settings_bar.dart  the band above it
//     canvas_timeline.dart   the strip below it
//     element_settings.dart  the controls for whichever element is selected
//     procedural_settings.dart  the controls for a generated background
//     element_factory.dart   a new element of each kind
//     controls.dart          the small controls the band is built from
//     publish_sheet.dart     what to make, and where to send it
//     sidebar/               files, presets and design elements
//
// The one rule that keeps this readable: render/ and export/ know nothing
// about widgets, a BuildContext or a theme. The same code draws the editing
// stage and the exported file, and an export that reached for the app's theme
// would produce a picture that changed depending on what the sender's app
// happened to look like.
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/plugin_system.dart';

export 'package:bruig/plugin_system/canvas/canvas_nav.dart';
export 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
export 'package:bruig/plugin_system/canvas/canvas_settings.dart';
export 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
// The editing session and the empty document, so main() can provide one that
// outlives the page. Nothing else outside this directory should need either.
export 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart'
    show emptyCanvas;
export 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart'
    show CanvasController;

/// registerCanvas attaches this module to the plugin system.
///
/// Called once at startup, before the settings page can be reached. It is the
/// only line of the app that says Canvas has a section on Settings > Plugins,
/// and it says it from this side of the boundary -- so the plugin system stays
/// unaware that a canvas is a thing anyone might want to switch on.
///
/// Registered as a feature rather than against a capability, because Canvas
/// has neither: PluginSettingsRegistry.register is for a section that appears
/// when a provider is installed, and this one appears when a switch is turned
/// on. See canvas_preferences.dart.
void registerCanvas() {
  PluginSettingsRegistry.registerFeature(
    "canvas",
    (context, inPluginPanel) => const CanvasSettingsSection(),
  );
}
