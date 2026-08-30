import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

// canvas_document.dart is a whole canvas: its shape, its background, what is
// on it, and how long it runs for.
//
// Immutable, like the elements it holds. Every edit is a new document, which
// is what makes undo a list and makes the painter safe to hand a document to
// from a background isolate during export. A mutable scene graph would be the
// obvious thing and would put a "did this change under me" question into every
// one of those places.
//
// The file format is JSON with a version number on it, written to
// "<appDataDir>/canvas". Plain text on purpose: a document is a few kilobytes
// because every element is a description rather than a picture, and a format
// somebody can read in a text editor is a format they can still recover
// something from in ten years.

/// canvasFormatVersion is bumped when a saved document would be read wrongly
/// by an older build. Read on load and never used to refuse a document -- an
/// unknown future version is read as best it can be, since every field reader
/// already falls back when a field is missing or the wrong type.
const int canvasFormatVersion = 1;

/// defaultFrameRate is what a new document plays at.
///
/// Twelve rather than twenty-four or thirty. What gets made here is a tactics
/// diagram or a title moving into place, not film, and twelve is where a GIF
/// stops looking choppy while staying a quarter of the size of a 30fps one --
/// which matters when the result has to fit in a chat message.
const int defaultFrameRate = 12;

/// defaultFrameCount is one second at [defaultFrameRate]. A new document is
/// deliberately a still: one frame's worth of timeline, so the timeline is
/// visible and explains itself without a still picture having to be an
/// animation nobody asked for.
const int defaultFrameCount = 1;

const int maxFrameCount = 600;

/// CanvasBackground is what is behind everything, covering the whole document.
///
/// Either a picture or a generated pattern, never both -- an image wins when
/// there is one, and clearing it falls back to whatever the pattern was, so
/// trying a photograph behind a design and then changing your mind does not
/// lose the gradient that was there before.
class CanvasBackground {
  final ProceduralSpec spec;

  /// imageAssetId, when set, is drawn instead of the generator.
  final String imageAssetId;
  final ImageFit imageFit;

  const CanvasBackground({
    this.spec = const ProceduralSpec(),
    this.imageAssetId = "",
    this.imageFit = ImageFit.cover,
  });

  bool get isImage => imageAssetId.isNotEmpty;

  CanvasBackground copyWith({
    ProceduralSpec? spec,
    String? imageAssetId,
    ImageFit? imageFit,
  }) =>
      CanvasBackground(
        spec: spec ?? this.spec,
        imageAssetId: imageAssetId ?? this.imageAssetId,
        imageFit: imageFit ?? this.imageFit,
      );

  Map<String, dynamic> toJson() => {
        "spec": spec.toJson(),
        if (isImage) "image": imageAssetId,
        if (isImage) "fit": imageFit.name,
      };

  factory CanvasBackground.fromJson(Map<String, dynamic> json) =>
      CanvasBackground(
        spec: jsonSpec(
            json["spec"], ProceduralSpec.fromJson, const ProceduralSpec()),
        imageAssetId: jsonString(json["image"], ""),
        imageFit: ImageFit.fromName(json["fit"] as String?),
      );
}

/// CanvasDocument is the whole thing.
class CanvasDocument {
  /// title is what the document is called in the library. Not the filename --
  /// see storage/canvas_storage.dart, which sanitises one into the other.
  final String title;

  final CanvasSize size;
  final CanvasBackground background;

  /// elements are painted first to last, so the last one in the list is on
  /// top. That is the order the layer list shows reversed, since "on top"
  /// reads better at the top of a list.
  final List<CanvasElement> elements;

  /// frames is the document's length. One means a still.
  final int frames;
  final int frameRate;

  final List<TimelineAction> actions;

  const CanvasDocument({
    this.title = "Untitled canvas",
    this.size = const CanvasSize(),
    this.background = const CanvasBackground(),
    this.elements = const [],
    this.frames = defaultFrameCount,
    this.frameRate = defaultFrameRate,
    this.actions = const [],
  });

  bool get isAnimated => frames > 1;

  /// durationSeconds is what the timeline reports and what the GIF export
  /// uses to work out its frame delays.
  double get durationSeconds => frames / (frameRate <= 0 ? 1 : frameRate);

  /// lastAnimatedFrame is the furthest frame any element has a keyframe on.
  ///
  /// Asked so the timeline can point out a document whose length is shorter
  /// than the animation drawn on it -- keyframes past the end are not lost,
  /// they are simply never reached, and that is confusing enough to be worth
  /// saying out loud rather than silently trimming somebody's work.
  int get lastAnimatedFrame {
    var last = 0;
    for (var e in elements) {
      var f = e.track?.lastFrame ?? 0;
      if (f > last) last = f;
      // A team's movement is on its players, not on the team, so asking the
      // element alone would report a pitch full of runs as a still.
      if (e is TeamElement) {
        for (var p in e.players) {
          var pf = p.track?.lastFrame ?? 0;
          if (pf > last) last = pf;
        }
      }
    }
    for (var a in actions) {
      if (a.frame > last) last = a.frame;
    }
    return last;
  }

  CanvasElement? elementById(String id) {
    for (var e in elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  int indexOf(String id) => elements.indexWhere((e) => e.id == id);

  CanvasDocument copyWith({
    String? title,
    CanvasSize? size,
    CanvasBackground? background,
    List<CanvasElement>? elements,
    int? frames,
    int? frameRate,
    List<TimelineAction>? actions,
  }) =>
      CanvasDocument(
        title: title ?? this.title,
        size: size ?? this.size,
        background: background ?? this.background,
        elements: elements ?? this.elements,
        frames: (frames ?? this.frames).clamp(1, maxFrameCount),
        frameRate: (frameRate ?? this.frameRate).clamp(1, 60),
        actions: actions ?? this.actions,
      );

  /// withElement replaces the element sharing [element]'s id, or does nothing
  /// if it has since been deleted.
  ///
  /// Doing nothing is deliberate. A settings control that is still holding a
  /// deleted element -- which happens, because a panel is torn down one frame
  /// after the delete -- must not put it back.
  CanvasDocument withElement(CanvasElement element) {
    var i = indexOf(element.id);
    if (i < 0) return this;
    var next = [...elements];
    next[i] = element;
    return copyWith(elements: next);
  }

  CanvasDocument addElement(CanvasElement element) =>
      copyWith(elements: [...elements, element]);

  CanvasDocument removeElement(String id) =>
      copyWith(elements: elements.where((e) => e.id != id).toList());

  /// reorder moves the element at [from] to [to] in paint order.
  CanvasDocument reorder(int from, int to) {
    if (from < 0 || from >= elements.length) return this;
    var next = [...elements];
    var moved = next.removeAt(from);
    next.insert(to.clamp(0, next.length), moved);
    return copyWith(elements: next);
  }

  /// bringToFront and sendToBack are reorder under the names the layer menu
  /// uses, since "move to index elements.length - 1" is not what anybody is
  /// thinking when they reach for it.
  CanvasDocument bringToFront(String id) {
    var i = indexOf(id);
    return i < 0 ? this : reorder(i, elements.length - 1);
  }

  CanvasDocument sendToBack(String id) {
    var i = indexOf(id);
    return i < 0 ? this : reorder(i, 0);
  }

  Map<String, dynamic> toJson() => {
        "version": canvasFormatVersion,
        "title": title,
        "size": size.toJson(),
        "background": background.toJson(),
        "frames": frames,
        "frameRate": frameRate,
        if (actions.isNotEmpty)
          "actions": actions.map((a) => a.toJson()).toList(),
        "elements": elements.map((e) => e.toJson()).toList(),
      };

  String encode() => const JsonEncoder.withIndent("  ").convert(toJson());

  factory CanvasDocument.fromJson(Map<String, dynamic> json) {
    var raw = json["elements"];
    var acts = json["actions"];
    return CanvasDocument(
      title: jsonString(json["title"], "Untitled canvas"),
      size: jsonSpec(json["size"], CanvasSize.fromJson, const CanvasSize()),
      background: jsonSpec(json["background"], CanvasBackground.fromJson,
          const CanvasBackground()),
      elements: raw is List
          ? [
              for (var e in raw)
                if (e is Map<String, dynamic>) elementFromJson(e),
            ]
          : const [],
      frames: jsonInt(json["frames"], defaultFrameCount)
          .clamp(1, maxFrameCount),
      frameRate: jsonInt(json["frameRate"], defaultFrameRate).clamp(1, 60),
      actions: acts is List
          ? [
              for (var a in acts)
                if (a is Map<String, dynamic>) TimelineAction.fromJson(a),
            ]
          : const [],
    );
  }

  /// decode reads a saved file, returning null rather than throwing.
  ///
  /// A document that will not parse is a document the user still has on disk,
  /// and the right response is to say so and leave the file alone -- not to
  /// crash the page it was opened from, and certainly not to overwrite it with
  /// an empty canvas.
  static CanvasDocument? decode(String text) {
    try {
      var json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      return CanvasDocument.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

/// elementFromJson turns one saved element back into the right subclass.
///
/// An unknown kind becomes a plain rectangle rather than being dropped. A
/// document written by a newer build and opened here has an element in it
/// somewhere; leaving a visible placeholder where it was is recoverable, and
/// silently deleting it is not.
CanvasElement elementFromJson(Map<String, dynamic> json) {
  var kind = ElementKind.values.firstWhere(
    (k) => k.name == json["kind"],
    orElse: () => ElementKind.shape,
  );
  var base = ElementBase.fromJson(json, kind.label);
  switch (kind) {
    case ElementKind.text:
      return TextElement.fromJson(json, base);
    case ElementKind.image:
      return ImageElement.fromJson(json, base);
    case ElementKind.shape:
      return ShapeElement.fromJson(json, base);
    case ElementKind.line:
      return LineElement.fromJson(json, base);
    case ElementKind.chart:
      return ChartElement.fromJson(json, base);
    case ElementKind.table:
      return TableElement.fromJson(json, base);
    case ElementKind.button:
      return ButtonElement.fromJson(json, base);
    case ElementKind.background:
      return BackgroundElement.fromJson(json, base);
    case ElementKind.player:
      return TeamElement.fromJson(json, base);
  }
}
