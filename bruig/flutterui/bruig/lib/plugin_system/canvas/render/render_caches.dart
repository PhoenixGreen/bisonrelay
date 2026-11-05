import 'package:bruig/plugin_system/canvas/render/adjust_painter.dart';
import 'package:bruig/plugin_system/canvas/render/brush_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_mask_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/layer_effects.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/parallax_painter.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:bruig/plugin_system/canvas/render/video_key.dart';

// render_caches.dart is every cache the renderer keeps across frames in
// one call: kept app-wide, they would otherwise hold their pictures -- up to
// hundreds of megabytes of them -- for the rest of the session, after the
// canvas they were drawn for has been left.

/// clearRenderCaches lets go of everything the renderer has kept. Drawn
/// again, each is made again as it is needed.
void clearRenderCaches() {
  RasterCache.instance.clear();
  clearPaintLayers();
  clearMaskRasters();
  VideoKey.clear();
  clearParallaxPatterns();
  clearEffectRasters();
  clearAdjustedRasters();
  clearWorkingPixels();
  clearTextLayouts();
  clearGlyphs();
}
