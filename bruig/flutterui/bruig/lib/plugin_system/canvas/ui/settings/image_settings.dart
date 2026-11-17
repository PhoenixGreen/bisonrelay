import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_sections.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// image_settings.dart is a picture's settings.

/// imageSettings is a picture's settings (see image_sections.dart); a
/// backdrop's picture, with no layers, box or arrival, keeps plain groups.
List<Widget> imageSettings(
    BuildContext context,
    CanvasController controller,
    ImageElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit,
    {bool background = false}) {
  if (background) {
    return _pictureSettings(context, controller, e, write, begin, commit);
  }
  return imagePanel(context, controller, e, write, begin, commit);
}

List<Widget> _pictureSettings(
    BuildContext context,
    CanvasController controller,
    ImageElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit,
    {Rect? layerFrame,
    ValueChanged<ImageElement?>? tryLook}) {
  // A picture layer, not the element's own picture: placed in a frame, and
  // without removal brushes, which paint on the base picture only.
  var layer = layerFrame != null;

  return [
    // No caption: the panel header already says "Picture settings".
    CanvasControlGroup(
        label: "Picture",
        hideCaption: true,
        // No rule: the picture and what is removed from it are one question.
        rule: false,
        children: [
          ...pictureSourceButtons(context, e, write, begin, commit,
              layerFrame: layerFrame),
          CanvasDropdown<ImageFit>(
            label: "Fills its box",
            value: e.fit,
            width: 106,
            options: [for (var f in ImageFit.values) (f, f.label)],
            onChanged: (v) {
              begin();
              write(e.copyWith(fit: v));
              commit();
            },
          ),
          CanvasNumberField(
            label: "Saturation",
            decimals: 2,
            width: 62,
            value: e.saturation,
            min: 0,
            max: 3,
            onChanged: (v) {
              begin();
              write(e.copyWith(saturation: v));
            },
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Brightness",
            decimals: 2,
            width: 62,
            value: e.brightness,
            min: 0,
            max: 3,
            onChanged: (v) {
              begin();
              write(e.copyWith(brightness: v));
            },
            onCommit: commit,
          ),
        ]),
    pictureRemovalGroup(controller, e, write, begin, commit, layer: layer),
    ...pictureLookGroups(e, write, begin, commit,
        shown: e.hasImage, tryLook: tryLook),
  ];
}

/// pictureRemovalGroup keys out a flat colour or paper (logos, scans); a
/// photo's subject is the mask's. [layer]: methods only, as the brushes
/// paint the base picture.
Widget pictureRemovalGroup(CanvasController controller, ImageElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit,
    {required bool layer}) {
  return CanvasControlGroup(
      label: "Logos and scans",
      help: "Take out a flat colour or the paper behind a drawing: A colour "
          "keys out one colour, Edges floods in from the sides, Brightness "
          "cuts at a level. A photograph's subject is the Mask tools' work.",
      rule: false,
      children: [
        // The brush before the method and outside its check: a fresh picture
        // has neither, and the brush does photographs no method can.
        if (!layer) ...[
          // Brushing is the mask tools' job on every layer (see
          // image_layer_settings.dart); this serves pictures painted with the
          // old brushes. A drawn stroke waits here until applied, so the
          // settings above can be tuned against it.
          if (controller.hasPendingStroke) ...[
            Padding(
              padding: const EdgeInsets.only(top: controlLabelHeight, right: 6),
              child: SizedBox(
                height: controlHeight,
                child: Center(
                  child: Txt.S(controller.pendingTeaches
                      ? "Mark drawn — adjust the brush, then keep it"
                      : "Stroke drawn — adjust the brush, then apply it"),
                ),
              ),
            ),
            CanvasIconButton(
              icon: Icons.check,
              tooltip: "Apply this stroke",
              active: true,
              onPressed: controller.applyStroke,
            ),
            CanvasIconButton(
              icon: Icons.close,
              tooltip: "Throw this stroke away",
              onPressed: controller.discardStroke,
            ),
          ],
          if (controller.retouch.on) ...[
            CanvasNumberField(
              label: "Brush",
              min: 0.005,
              max: 0.6,
              decimals: 3,
              width: 62,
              value: controller.brushSize,
              onChanged: (v) => controller.brushSize = v,
            ),
            // Only for brushes that mark the picture. A hint is a sample,
            // taken exactly where drawn.
            if (!controller.retouch.teaches) ...[
              CanvasNumberField(
                label: "Hardness",
                min: 0.05,
                max: 1,
                decimals: 2,
                width: 62,
                value: controller.brushHardness,
                onChanged: (v) => controller.brushHardness = v,
              ),
              // Not for putting back or cutting around: clinging finds a
              // background's edge by colour, and a subject is every colour.
              if (!controller.retouch.keeps && !controller.retouch.fills)
                CanvasNumberField(
                  label: "Cling",
                  min: 0,
                  max: 0.6,
                  decimals: 3,
                  width: 62,
                  value: controller.brushSnap,
                  onChanged: (v) => controller.brushSnap = v,
                ),
              // Which side goes, read when the stroke is applied, so it can be
              // flipped with a stroke held.
              if (controller.retouch.fills)
                CanvasIconButton(
                  icon: controller.cutInside
                      ? Icons.flip_to_back
                      : Icons.flip_to_front,
                  tooltip: controller.cutInside
                      ? "Taking what is inside the line — press to take what is "
                          "outside"
                      : "Taking what is outside the line — press to take what is "
                          "inside",
                  active: controller.cutInside,
                  onPressed: () => controller.cutInside = !controller.cutInside,
                ),
              // The magnet reads Cling off the picture, as nobody can read it
              // off a photograph (CanvasController.magnetiseCling).
              if (!controller.retouch.keeps &&
                  !controller.retouch.fills &&
                  controller.hasPendingStroke)
                CanvasIconButton(
                  icon: Icons.my_location,
                  tooltip: "Find the edge this stroke crossed and cling to it",
                  onPressed: () async {
                    var found = await controller.magnetiseCling();
                    if (!found) {
                      // A stroke wholly on the background has no edge; finding
                      // one would cut the background in half.
                      controller.brushSnap = 0;
                    }
                  },
                ),
            ],
          ],
          if (e.removal.strokes.isNotEmpty) ...[
            CanvasIconButton(
              icon: Icons.undo,
              tooltip: "Undo the last brush stroke",
              onPressed: () {
                begin();
                write(e.copyWith(
                    removal: e.removal.copyWith(
                        strokes: e.removal.strokes
                            .sublist(0, e.removal.strokes.length - 1))));
                commit();
              },
            ),
            CanvasIconButton(
              icon: Icons.layers_clear_outlined,
              tooltip: "Clear every brush stroke",
              onPressed: () {
                begin();
                write(
                    e.copyWith(removal: e.removal.copyWith(strokes: const [])));
                commit();
              },
            ),
          ],
        ],
        CanvasDropdown<RemovalMode>(
          key: const ValueKey("removalMethod"),
          label: "Take out",
          width: 120,
          options: [
            (RemovalMode.none, "Off"),
            (RemovalMode.chromaKey, "A colour"),
            (RemovalMode.cornerFlood, "Edges"),
            (RemovalMode.luminance, "Brightness"),
            // Select subject does this better; kept for pictures already
            // using it.
            if (e.removal.mode == RemovalMode.learn)
              (RemovalMode.learn, "Marks"),
          ],
          value: e.removal.mode,
          onChanged: (v) {
            begin();
            write(e.copyWith(removal: e.removal.copyWith(mode: v)));
            commit();
          },
        ),
        if (e.removal.mode == RemovalMode.chromaKey)
          CanvasColorButton(
            label: "Key",
            color: e.removal.keyColor,
            allowAlpha: false,
            onChanged: (c) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(keyColor: c)));
              commit();
            },
          ),
        if (e.removal.mode == RemovalMode.luminance)
          CanvasNumberField(
            label: "Threshold",
            min: 0,
            max: 1,
            decimals: 2,
            width: 62,
            value: e.removal.threshold,
            onChanged: (v) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(threshold: v)));
            },
            onCommit: commit,
          ),
        // A method's settings only while one is chosen: hand work alone
        // reads no tolerance or softness.
        if (e.removal.mode != RemovalMode.none) ...[
          // Edge first: on a photograph it does the work, setting how sharp a
          // change ends the flood. Tolerance is the runaway guard.
          if (e.removal.mode == RemovalMode.cornerFlood)
            CanvasNumberField(
              label: "Edge",
              min: 0.005,
              max: 0.5,
              decimals: 3,
              width: 62,
              value: e.removal.edge,
              onChanged: (v) {
                begin();
                write(e.copyWith(removal: e.removal.copyWith(edge: v)));
              },
              onCommit: commit,
            ),
          // Every method but brightness, which cuts at a threshold.
          if (e.removal.mode != RemovalMode.luminance)
            CanvasNumberField(
              label: e.removal.mode == RemovalMode.cornerFlood
                  ? "Spread"
                  : "Tolerance",
              min: 0,
              decimals: 2,
              width: 62,
              value: e.removal.tolerance,
              max: 1,
              onChanged: (v) {
                begin();
                write(e.copyWith(removal: e.removal.copyWith(tolerance: v)));
              },
              onCommit: commit,
            ),
          CanvasNumberField(
            label: "Softness",
            min: 0,
            decimals: 2,
            width: 62,
            value: e.removal.softness,
            max: 0.3,
            onChanged: (v) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(softness: v)));
            },
            onCommit: commit,
          ),
          // Marks for the learning method: mark some background and some
          // subject; the numbers below only fine-tune.
          if (e.removal.mode == RemovalMode.learn) ...[
            CanvasIconButton(
              icon: Icons.format_paint_outlined,
              tooltip: controller.retouch == RetouchBrush.markBackground
                  ? "Stop marking background"
                  : "Mark some background — draw over a few parts that should "
                      "go",
              active: controller.retouch == RetouchBrush.markBackground,
              onPressed: () => controller.retouch =
                  controller.retouch == RetouchBrush.markBackground
                      ? RetouchBrush.off
                      : RetouchBrush.markBackground,
            ),
            CanvasIconButton(
              icon: Icons.person_outline,
              tooltip: controller.retouch == RetouchBrush.markSubject
                  ? "Stop marking the subject"
                  : "Mark the subject — draw over a few parts that should "
                      "stay",
              active: controller.retouch == RetouchBrush.markSubject,
              onPressed: () => controller.retouch =
                  controller.retouch == RetouchBrush.markSubject
                      ? RetouchBrush.off
                      : RetouchBrush.markSubject,
            ),
            if (e.removal.hints.isNotEmpty)
              CanvasIconButton(
                icon: Icons.layers_clear_outlined,
                tooltip: "Forget the marks and start again",
                onPressed: () {
                  begin();
                  write(
                      e.copyWith(removal: e.removal.copyWith(hints: const [])));
                  commit();
                },
              ),
            Padding(
              padding: const EdgeInsets.only(top: controlLabelHeight, right: 6),
              child: SizedBox(
                height: controlHeight,
                child: Center(
                  child: Txt.S(e.removal.backgroundHints.isEmpty ||
                          e.removal.subjectHints.isEmpty
                      ? "Mark both, then it can compare them"
                      : "${e.removal.hints.length} marks"),
                ),
              ),
            ),
          ],
          CanvasToggle(
            label: "Invert",
            value: e.removal.invert,
            onChanged: (v) {
              begin();
              write(e.copyWith(removal: e.removal.copyWith(invert: v)));
              commit();
            },
          ),
        ],
      ]);
}

/// pictureSourceButtons put in, remove or resize a picture, from a file or
/// the store; for a layer, [layerFrame] is its frame.
List<Widget> pictureSourceButtons(BuildContext context, ImageElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit,
    {Rect? layerFrame}) {
  void now(ImageElement next) {
    begin();
    write(next);
    commit();
  }

  // A new picture gives the box its proportions, so it is neither cropped
  // nor squashed; only shrinking, as growing could leave the canvas.
  Future<void> use(String id) async {
    var next = e.copyWith(assetId: id);
    var size = await pictureSize(id);
    if (size != null) {
      next = layerFrame != null
          ? withPictureProportions(next, layerFrame, size)
          : fitToPicture(next, size);
    }
    now(next);
  }

  return [
    // Somewhere to put a picture: without one the element does nothing.
    CanvasIconButton(
      icon: e.hasImage ? Icons.image_outlined : Icons.add_photo_alternate,
      tooltip: e.hasImage ? "Replace this picture" : "Add a picture",
      onPressed: () async {
        var id = await pickCanvasImage(context, vectors: false);
        if (id != null) await use(id);
      },
    ),
    // The store's pictures, to reuse one without finding the file again.
    CanvasIconButton(
      icon: Icons.photo_library_outlined,
      tooltip: "Use a picture you have already added",
      onPressed: () async {
        var id = await showRecentPictures(context);
        if (id != null) await use(id);
      },
    ),
    // The size controls again: on import they are offered only past half
    // a megabyte. The app's own width, quality and format controls.
    if (e.hasImage)
      CanvasIconButton(
        icon: Icons.compress,
        tooltip: "Change this picture's size and quality",
        onPressed: () async {
          var id = await compressCanvasPicture(context, e.assetId);
          if (id != null) await use(id);
        },
      ),
    if (e.hasImage)
      CanvasIconButton(
        icon: Icons.hide_image_outlined,
        tooltip: "Take the picture out",
        onPressed: () => now(e.copyWith(assetId: "")),
      ),
  ];
}

/// grownForPadding gives [e] new padding and grows its box, as a picture
/// cannot reflow and would crop. From the drawn place, so a drag's
/// repeated calls keep the picture still.
ImageElement grownForPadding(ImageElement e, BoxSpec box) {
  var inner = e.box.inner(e.bounds);
  if (inner.width <= 0 || inner.height <= 0) return e.copyWith(box: box);
  var grown = Rect.fromLTRB(
    inner.left - box.padLeft,
    inner.top - box.padTop,
    inner.right + box.padRight,
    inner.bottom + box.padBottom,
  );
  return e.copyWith(box: box).withBase(
      x: grown.left,
      y: grown.top,
      width: grown.width,
      height: grown.height) as ImageElement;
}

/// pictureLookGroups is how a picture is drawn: cut shape, framing, crop,
/// filter, overlay, outline; shared with video. [shown]: anything yet.
List<Widget> pictureLookGroups(ImageElement e, SettingsWrite write,
    VoidCallback begin, VoidCallback commit,
    {required bool shown,
    ValueChanged<ImageElement?>? tryLook,
    bool shape = true,
    bool framing = true,
    bool flipX = false,
    bool flipY = false,
    bool crop = true,
    bool filter = true,
    bool overlay = true,
    bool outline = true}) {
  void now(ImageElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    if (shown && shape)
      CanvasControlGroup(label: "Shape", rule: false, children: [
        CanvasDropdown<String>(
          label: "Cut to",
          value: e.frame == ShapeKind.rectangle ? "" : e.frame?.name ?? "",
          width: 128,
          options: [
            ("", "Rectangle"),
            // "Rectangle" above is no cut; the rectangle shape would repeat it.
            for (var k in ShapeKind.values)
              if (k != ShapeKind.rectangle) (k.name, k.label),
          ],
          // Cut to a shape, it clips to it: a circle with a stroke running
          // out of it is not a circle.
          onChanged: (v) => now(v.isEmpty
              ? e.copyWith(clearFrame: true)
              : e.copyWith(frame: ShapeKind.fromName(v), clip: true)),
        ),
      ]),
    // Framing is the double-click gesture's three numbers (see
    // CanvasStageState._applyFraming), so pictures can match exactly;
    // explained, not hidden, where they would do nothing.
    if (shown && framing && e.fit != ImageFit.cover)
      const CanvasHint(
          "Framing — moving the picture about inside its box and zooming it "
          "— is for a picture that fills its frame. Set Fills its box to Cover to "
          "reach it: contained shows the whole picture and stretched pulls "
          "it to the box, and neither leaves anything to move."),
    if (shown && framing && e.fit == ImageFit.cover)
      CanvasControlGroup(label: "Framing", rule: false, children: [
        CanvasHint("Double-click the picture to drag it about inside its box, "
            "and scroll to zoom."),
        for (var (label, value, apply)
            in <(String, double, ImageFraming Function(double))>[
          ("Across", e.framing.x, (v) => e.framing.copyWith(x: v)),
          ("Down", e.framing.y, (v) => e.framing.copyWith(y: v)),
          ("Zoom", e.framing.zoom, (v) => e.framing.copyWith(zoom: v)),
        ])
          CanvasNumberField(
            label: label,
            min: label == "Zoom" ? 1 : 0,
            max: label == "Zoom" ? 8 : 1,
            decimals: 2,
            width: 62,
            value: value,
            onChanged: (v) {
              begin();
              write(e.copyWith(framing: apply(v)));
            },
            onCommit: commit,
          ),
        CanvasIconButton(
          icon: Icons.filter_center_focus,
          tooltip: "Put the picture back in the middle",
          onPressed: () => now(e.copyWith(framing: const ImageFraming())),
        ),
      ]),
    if (shown && crop)
      CanvasControlGroup(
          label: "Crop",
          rule: false,
          children: cropControls(e, write, begin, commit,
              flipX: flipX, flipY: flipY)),
    if (shown && (filter || overlay))
      CanvasControlGroup(
          label: filter ? "Look" : "Overlay",
          rule: false,
          children: [
            if (filter)
              CanvasDropdown<ImageFilterPreset>(
                label: "Filter",
                value: e.filter,
                width: 116,
                options: [for (var f in ImageFilterPreset.values) (f, f.label)],
                onChanged: (v) => now(e.copyWith(filter: v)),
                onPreview: tryLook == null
                    ? null
                    : (v) => tryLook(v == null ? null : e.copyWith(filter: v)),
              ),
            if (overlay)
              CanvasDropdown<OverlayBlend>(
                label: "Overlay",
                value: e.blend,
                width: 116,
                options: [for (var b in OverlayBlend.values) (b, b.label)],
                onChanged: (v) => now(e.copyWith(blend: v)),
                onPreview: tryLook == null
                    ? null
                    : (v) => tryLook(v == null ? null : e.copyWith(blend: v)),
              ),
            if (overlay && e.blend != OverlayBlend.none)
              CanvasColorButton(
                key: const ValueKey("imageOverlayColour"),
                label: "Colour",
                color: e.overlay,
                onChanged: (c) => now(e.copyWith(overlay: c)),
              ),
          ]),
    // Not under "Remove background", though that is its use: it traces the
    // alpha channel however it got there.
    if (shown && outline)
      CanvasControlGroup(label: "Outline", rule: false, children: [
        CanvasNumberField(
          label: "Width",
          min: 0,
          max: 60,
          decimals: 1,
          width: 62,
          value: e.outline.width,
          onChanged: (v) {
            begin();
            write(e.copyWith(outline: e.outline.copyWith(width: v)));
          },
          onCommit: commit,
        ),
        if (e.outline.width > 0) ...[
          CanvasColorButton(
            key: const ValueKey("imageOutlineColour"),
            label: "Colour",
            color: e.outline.color,
            onChanged: (c) =>
                now(e.copyWith(outline: e.outline.copyWith(color: c))),
          ),
          CanvasDropdown<OutlineStyle>(
            label: "Style",
            value: e.outline.style,
            width: 116,
            options: [for (var o in OutlineStyle.values) (o, o.label)],
            onChanged: (v) =>
                now(e.copyWith(outline: e.outline.copyWith(style: v))),
          ),
          CanvasNumberField(
            label: "Feather",
            min: 0,
            max: 1,
            decimals: 2,
            width: 62,
            value: e.outline.feather,
            onChanged: (v) {
              begin();
              write(e.copyWith(outline: e.outline.copyWith(feather: v)));
            },
            onCommit: commit,
          ),
        ],
      ]),
  ];
}

/// cropControls are the Crop tool: trims per edge of [e] and a show-all
/// button. [flipX] and [flipY] are a layer's mirror (see croppedTo).
List<Widget> cropControls(ImageElement e, SettingsWrite write,
    VoidCallback begin, VoidCallback commit,
    {bool flipX = false, bool flipY = false}) {
  return [
    for (var (label, value, apply)
        in <(String, double, ImageCrop Function(double))>[
      ("Left", e.crop.left, (v) => e.crop.copyWith(left: v)),
      ("Top", e.crop.top, (v) => e.crop.copyWith(top: v)),
      ("Right", e.crop.right, (v) => e.crop.copyWith(right: v)),
      ("Bottom", e.crop.bottom, (v) => e.crop.copyWith(bottom: v)),
    ])
      CanvasNumberField(
        key: ValueKey("crop$label"),
        label: label,
        min: 0,
        max: 1,
        decimals: 2,
        width: 62,
        value: value,
        onChanged: (v) {
          begin();
          // The frame is trimmed with the crop, so what is left stays put
          // (see ImageElement.croppedTo).
          write(e.croppedTo(apply(v), flipX: flipX, flipY: flipY));
        },
        onCommit: commit,
      ),
    CanvasIconButton(
      key: const ValueKey("cropShowWhole"),
      icon: Icons.crop_free,
      tooltip: "Show the whole picture again",
      onPressed: () {
        begin();
        write(e.croppedTo(const ImageCrop(), flipX: flipX, flipY: flipY));
        commit();
      },
    ),
  ];
}
