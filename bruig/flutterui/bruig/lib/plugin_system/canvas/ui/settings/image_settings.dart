import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// image settings.dart is a picture's settings.

List<Widget> imageSettings(
    BuildContext context,
    CanvasController controller,
    ImageElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  void now(ImageElement next) {
    begin();
    write(next);
    commit();
  }

  // Putting a picture in also gives the box the picture's proportions. A
  // photograph dropped into whatever rectangle happened to be there is either
  // cropped by the fit or squashed by it, and the first thing anybody did was
  // drag the handles until it looked right -- which is arithmetic the picture
  // itself already knows the answer to. It only ever shrinks the box: growing
  // one could push it off the canvas, and the reader asked for a picture, not
  // for the layout to move.
  Future<void> use(String id) async {
    var next = e.copyWith(assetId: id);
    var size = await pictureSize(id);
    if (size != null) next = fitToPicture(next, size);
    now(next);
  }

  return [
    // No caption: the panel header says "Picture settings" already, and a
    // group called Picture directly under it was the word twice.
    CanvasControlGroup(label: "Picture", hideCaption: true, children: [
      // The one control this element did not have, and without which it does
      // nothing at all: somewhere to put a picture in it.
      CanvasIconButton(
        icon: e.hasImage ? Icons.image_outlined : Icons.add_photo_alternate,
        tooltip: e.hasImage ? "Replace this picture" : "Add a picture",
        onPressed: () async {
          var id = await pickCanvasImage(context);
          if (id != null) await use(id);
        },
      ),
      // The other half of a shared picture store: the bytes have always been
      // shared between canvases, but nothing ever showed what was in there, so
      // the only way to put the same badge on a second canvas was to go and
      // find the file again.
      CanvasIconButton(
        icon: Icons.photo_library_outlined,
        tooltip: "Use a picture you have already added",
        onPressed: () async {
          var id = await showRecentPictures(context);
          if (id != null) await use(id);
        },
      ),
      // The size controls are offered on the way in, but only above half a
      // megabyte -- so anybody who wanted them for a smaller picture, or who
      // took a size on the way in and thought better of it, had nowhere to
      // go. This is that door, and it is the app's own width, quality and
      // format controls, the same ones an embedded picture goes through.
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
      CanvasIconButton(
        icon: e.lockAspect ? Icons.link : Icons.link_off,
        tooltip: e.lockAspect
            ? "Proportions are held while it is resized — Shift to stretch"
            : "It can be stretched — Shift to hold its proportions",
        active: e.lockAspect,
        onPressed: () {
          begin();
          write(e.copyWith(lockAspect: !e.lockAspect));
          commit();
        },
      ),
      CanvasDropdown<ImageFit>(
        label: "Fit",
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
    CanvasControlGroup(label: "Remove background", children: [
      // The brush comes before the method, and outside the check for whether
      // anything is being removed yet.
      //
      // It used to be inside it, which made it unreachable on exactly the
      // picture it is for: a fresh image has no method chosen and no strokes,
      // so nothing was being removed, so the brushes were hidden -- and the
      // only way to reach the tool that needs no method was to choose a
      // method first.
      //
      // It is first because it is the tool. Every automatic method has
      // photographs it cannot do, and on those this is not a refinement.
      CanvasIconButton(
        icon: Icons.auto_fix_high,
        tooltip: controller.retouch == RetouchBrush.erase
            ? "Stop rubbing out"
            : "Rub the background out by hand",
        active: controller.retouch == RetouchBrush.erase,
        onPressed: () => controller.retouch =
            controller.retouch == RetouchBrush.erase
                ? RetouchBrush.off
                : RetouchBrush.erase,
      ),
      // The tool for the job the brush is bad at: a large, awkward,
      // many-coloured area. Draw a rough line around what is being kept, let
      // go, and everything the picture's own edge can reach without crossing
      // that line goes -- whatever colour any of it is.
      CanvasIconButton(
        icon: Icons.content_cut,
        tooltip: controller.retouch == RetouchBrush.cutAround
            ? "Stop cutting around"
            : "Cut around — draw a line around what you are keeping",
        active: controller.retouch == RetouchBrush.cutAround,
        onPressed: () => controller.retouch =
            controller.retouch == RetouchBrush.cutAround
                ? RetouchBrush.off
                : RetouchBrush.cutAround,
      ),
      CanvasIconButton(
        icon: Icons.healing,
        tooltip: controller.retouch == RetouchBrush.restore
            ? "Stop putting back"
            : "Put back what was taken by mistake",
        active: controller.retouch == RetouchBrush.restore,
        onPressed: () => controller.retouch =
            controller.retouch == RetouchBrush.restore
                ? RetouchBrush.off
                : RetouchBrush.restore,
      ),
      // A drawn stroke waits here until it is applied, so the settings above
      // can be adjusted against it and the result watched on the canvas.
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
        // Only for the brushes that mark the picture. A hint is a sample
        // and is taken exactly where it was drawn.
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
          // Not for putting back: clinging finds the edge of a background,
          // and what is being put back is the subject, which is every colour
          // there is.
          // Neither for putting back nor for cutting around. Clinging finds
          // the edge of a background by colour; what is being put back is the
          // subject, and a boundary does not care what colour anything is.
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
          // Which side of the boundary goes. Read when the stroke is
          // applied rather than when it was drawn, so it can be turned over
          // with a stroke still held and the preview redraws.
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
          // The magnet. Cling wants a number nobody can read off a
          // photograph, so this reads it off the picture instead -- see
          // CanvasController.magnetiseCling.
          if (!controller.retouch.keeps &&
              !controller.retouch.fills &&
              controller.hasPendingStroke)
            CanvasIconButton(
              icon: Icons.my_location,
              tooltip: "Find the edge this stroke crossed and cling to it",
              onPressed: () async {
                var found = await controller.magnetiseCling();
                if (!found) {
                  // Nothing to say it wrongly: a stroke drawn entirely on the
                  // background has no edge in it, and pretending otherwise
                  // would cut the background in half.
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
            write(e.copyWith(removal: e.removal.copyWith(strokes: const [])));
            commit();
          },
        ),
      ],
      CanvasDropdown<RemovalMode>(
        label: "Method",
        value: e.removal.mode,
        width: 140,
        options: [for (var m in RemovalMode.values) (m, m.label)],
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
      // A method's own settings, and only while one is chosen. They were
      // shown whenever anything was being removed -- which includes a
      // picture the brush alone has been used on -- so somebody working by
      // hand was offered a tolerance and a softness that nothing reads.
      if (e.removal.mode != RemovalMode.none) ...[
        // Edge first, because on a photograph it is the control that does
        // the work: it says how sharply the picture has to change for the
        // flood to treat it as the end of the background. Tolerance is the
        // runaway guard behind it.
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
        // Every method but the brightness one, which cuts at a threshold
        // and has no use for it.
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
        // Marking, when the method is the one that learns from it. These
        // two are the whole interface to it: mark some background, mark
        // some subject, and the numbers below are a fine adjustment rather
        // than the way in.
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
                write(e.copyWith(removal: e.removal.copyWith(hints: const [])));
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
    ]),
    if (e.hasImage)
      CanvasControlGroup(label: "Frame", children: [
        CanvasDropdown<String>(
          label: "Cut to",
          value: e.frame?.name ?? "",
          width: 128,
          options: [
            ("", "Rectangle"),
            for (var k in ShapeKind.values) (k.name, k.label),
          ],
          onChanged: (v) => now(v.isEmpty
              ? e.copyWith(clearFrame: true)
              : e.copyWith(frame: ShapeKind.fromName(v))),
        ),
      ]),
    // Framing is the same three numbers the double-click gesture writes -- see
    // CanvasStageState._applyFraming. Here as well as there because a number
    // is the only way to put two pictures in exactly the same place as each
    // other, and because a control that exists is how anybody finds out the
    // gesture is there at all.
    if (e.hasImage && e.fit == ImageFit.cover)
      CanvasControlGroup(label: "Framing", children: [
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
    if (e.hasImage)
      CanvasControlGroup(label: "Crop", children: [
        for (var (label, value, apply)
            in <(String, double, ImageCrop Function(double))>[
          ("Left", e.crop.left, (v) => e.crop.copyWith(left: v)),
          ("Top", e.crop.top, (v) => e.crop.copyWith(top: v)),
          ("Right", e.crop.right, (v) => e.crop.copyWith(right: v)),
          ("Bottom", e.crop.bottom, (v) => e.crop.copyWith(bottom: v)),
        ])
          CanvasNumberField(
            label: label,
            min: 0,
            max: 1,
            decimals: 2,
            width: 62,
            value: value,
            onChanged: (v) {
              begin();
              write(e.copyWith(crop: apply(v)));
            },
            onCommit: commit,
          ),
        CanvasIconButton(
          icon: Icons.crop_free,
          tooltip: "Show the whole picture again",
          onPressed: () => now(e.copyWith(crop: const ImageCrop())),
        ),
      ]),
    if (e.hasImage)
      CanvasControlGroup(label: "Look", children: [
        CanvasDropdown<ImageFilterPreset>(
          label: "Filter",
          value: e.filter,
          width: 116,
          options: [for (var f in ImageFilterPreset.values) (f, f.label)],
          onChanged: (v) => now(e.copyWith(filter: v)),
        ),
        CanvasDropdown<OverlayBlend>(
          label: "Overlay",
          value: e.blend,
          width: 116,
          options: [for (var b in OverlayBlend.values) (b, b.label)],
          onChanged: (v) => now(e.copyWith(blend: v)),
        ),
        if (e.blend != OverlayBlend.none)
          CanvasColorButton(
            key: const ValueKey("imageOverlayColour"),
            label: "Colour",
            color: e.overlay,
            onChanged: (c) => now(e.copyWith(overlay: c)),
          ),
      ]),
    // Not part of "Remove background", though that is what it is for. It
    // traces the alpha channel and does not care how the alpha got there, so
    // it works just as well on a picture that arrived with one -- and burying
    // it in the removal group would say otherwise.
    if (e.hasImage)
      CanvasControlGroup(label: "Outline", children: [
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
    // "Border", not "Frame". Frame is now the shape the picture is cut to,
    // and one word for the outline round a rectangle and for the rectangle
    // being a circle is a word doing two jobs.
    boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
        label: "Border"),
  ];
}

/// boxed draws a rule around a section and leaves a gap after it.
///
/// For the one section that is a panel rather than a row of controls. The rest
/// of these settings are captioned clusters that read as a list; a table with
/// its own scrollbars sitting in the middle of that list needs an edge, or
/// what follows it looks like part of it.
