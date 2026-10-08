import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/video_settings.dart';
import 'package:flutter/material.dart';

// background_media_settings.dart is the picture, video and sound a background
// can carry, under its pattern's settings.
//
// Each is the settings of its own element -- a background picture is set up
// exactly as a picture element is, a background video as a video -- with the
// parts that mean nothing on a backdrop left out: nothing on it is pressed,
// it has no box of its own, and it does not arrive, it is there. See
// CanvasBackground.picture.

List<Widget> backgroundMediaSettings(
    BuildContext context, CanvasController controller) {
  var bg = controller.document.editedBackground;
  var page = controller.document.size.size;

  // Read at the moment of writing rather than when the panel was built, so a
  // setting written after a file dialog does not put back what was there
  // before the dialog opened.
  CanvasBackground current() => controller.document.editedBackground;
  void write(CanvasBackground next) {
    controller.beginInteraction();
    controller.setBackground(next, transient: true);
  }

  void now(CanvasBackground next) {
    write(next);
    controller.endInteraction();
  }

  // Shown standing on the page, which is where they are drawn.
  T onPage<T extends CanvasElement>(T e) => e.rebase(
      e.base.copyWith(x: 0, y: 0, width: page.width, height: page.height)) as T;

  ElementBase fresh(String name) => ElementBase(
      id: newElementId(), name: name, width: page.width, height: page.height);

  Widget remove(String what, VoidCallback onPressed) => CanvasIconButton(
        icon: Icons.delete_outline,
        tooltip: "Take the $what off the background",
        onPressed: onPressed,
      );

  var picture = bg.shownPicture;
  var drawing = bg.drawing;
  var video = bg.video;
  var sound = bg.sound;
  var begin = controller.beginInteraction;
  var commit = controller.endInteraction;

  return [
    boxed(
      context,
      CanvasExpander(
        key: const ValueKey("backgroundPicture"),
        label: "Picture",
        remember: "backgroundPicture",
        trailing: picture == null ? "None" : null,
        children: [
          if (picture == null)
            CanvasControlGroup(
                label: "Picture",
                hideCaption: true,
                rule: false,
                children: [
                  CanvasIconButton(
                    key: const ValueKey("backgroundAddPicture"),
                    icon: Icons.add_photo_alternate,
                    tooltip: "Put a picture behind everything",
                    onPressed: () async {
                      var id = await pickCanvasImage(context, vectors: false);
                      if (id == null) return;
                      now(current().copyWith(
                          picture: ImageElement(fresh("Background picture"),
                              assetId: id)));
                    },
                  ),
                  CanvasIconButton(
                    icon: Icons.photo_library_outlined,
                    tooltip: "Use a picture you have already added",
                    onPressed: () async {
                      var id = await showRecentPictures(context);
                      if (id == null) return;
                      now(current().copyWith(
                          picture: ImageElement(fresh("Background picture"),
                              assetId: id)));
                    },
                  ),
                ])
          else ...[
            remove(
                "picture", () => now(current().copyWith(clearPicture: true))),
            ...imageSettings(
                context,
                controller,
                onPage(picture),
                (e) => write(current().copyWith(picture: e as ImageElement)),
                begin,
                commit,
                background: true),
          ],
        ],
      ),
    ),
    // A drawing behind everything: an .svg, kept a drawing, sharp at any
    // size. Over the picture and under the video.
    boxed(
      context,
      CanvasExpander(
        key: const ValueKey("backgroundDrawing"),
        label: "Drawing",
        remember: "backgroundDrawing",
        trailing: drawing == null ? "None" : null,
        children: [
          CanvasControlGroup(
              label: "Drawing",
              hideCaption: true,
              rule: false,
              children: [
                CanvasIconButton(
                  key: const ValueKey("backgroundAddDrawing"),
                  icon: drawing == null ? Icons.add : Icons.draw_outlined,
                  tooltip: drawing == null
                      ? "Put a drawing behind everything"
                      : "Use another drawing",
                  onPressed: () async {
                    var id = await pickCanvasVector(context);
                    if (id == null) return;
                    now(current().copyWith(
                        drawing: (drawing ??
                                VectorElement(fresh("Background drawing"),
                                    fit: VectorFit.cover))
                            .copyWith(
                                assetId: id,
                                viewBox: Rect.zero,
                                clearShapes: true)));
                  },
                ),
                CanvasIconButton(
                  icon: Icons.photo_library_outlined,
                  tooltip: "Use a drawing you have already added",
                  onPressed: () async {
                    var id = await showRecentPictures(context, drawings: true);
                    if (id == null) return;
                    now(current().copyWith(
                        drawing: (drawing ??
                                VectorElement(fresh("Background drawing"),
                                    fit: VectorFit.cover))
                            .copyWith(
                                assetId: id,
                                viewBox: Rect.zero,
                                clearShapes: true)));
                  },
                ),
                if (drawing != null) ...[
                  CanvasDropdown<VectorFit>(
                    key: const ValueKey("backgroundDrawingFit"),
                    label: "Fit",
                    value: drawing.fit,
                    width: 86,
                    options: [for (var f in VectorFit.values) (f, f.label)],
                    onChanged: (v) {
                      now(current()
                          .copyWith(drawing: drawing.copyWith(fit: v)));
                    },
                  ),
                  remove("drawing",
                      () => now(current().copyWith(clearDrawing: true))),
                ],
              ]),
        ],
      ),
    ),
    boxed(
      context,
      CanvasExpander(
        key: const ValueKey("backgroundVideo"),
        label: "Video",
        remember: "backgroundVideo",
        trailing: video == null ? "None" : null,
        children: [
          if (video == null)
            CanvasControlGroup(
                label: "Video",
                hideCaption: true,
                rule: false,
                children: [
                  CanvasIconButton(
                    key: const ValueKey("backgroundAddVideo"),
                    icon: Icons.video_library_outlined,
                    tooltip: "Put a video behind everything",
                    onPressed: () async {
                      var source = await pickCanvasVideo(context, controller);
                      if (source == null) return;
                      // Going by itself and round again, which is what a
                      // backdrop that moves is for; and nothing to press.
                      now(current().copyWith(
                          video: VideoElement(fresh("Background video"),
                              controls: const [],
                              clip: MediaClip(
                                  playlist: [source],
                                  volume: 1,
                                  autoplay: true,
                                  loop: MediaLoop.all))));
                    },
                  ),
                  const CanvasHint(
                      "A video behind everything, starting when the canvas "
                      "plays and going round again. Take a green screen out "
                      "of it and the pattern and picture show through."),
                ])
          else ...[
            remove("video", () {
              controller.video.stop(video.id);
              now(current().copyWith(clearVideo: true));
            }),
            ...videoSettings(
                context,
                controller,
                onPage(video),
                (e) => write(current().copyWith(video: e as VideoElement)),
                begin,
                commit,
                background: true),
          ],
        ],
      ),
    ),
    // Sound goes on the timeline's channels now. A background that already
    // has one keeps it -- changed, or taken off, here -- but a new one is
    // not offered: two places to put a soundtrack is one too many.
    if (sound != null)
      boxed(
        context,
        CanvasExpander(
          key: const ValueKey("backgroundSound"),
          label: "Sound",
          remember: "backgroundSound",
          children: [
            remove("sound", () {
              controller.audio.stop(sound.id);
              now(current().copyWith(clearSound: true));
            }),
            const CanvasHint("New sounds go on the timeline, in a channel "
                "of their own."),
            ...audioSettings(
                context,
                controller,
                sound,
                (e) => write(current().copyWith(sound: e as AudioElement)),
                begin,
                commit,
                background: true),
          ],
        ),
      ),
  ];
}
