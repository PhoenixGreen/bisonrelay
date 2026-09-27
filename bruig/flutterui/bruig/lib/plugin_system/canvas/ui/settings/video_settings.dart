import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// video_settings.dart is a Video element's settings.
//
// In the order one is set up: where the video comes from, how it plays, what
// the reader can do to it, the green screen, and then how the picture looks.
// The look is the image element's own groups -- see pictureLookGroups -- so a
// video and a photograph are cut, cropped and graded by the same controls.

List<Widget> videoSettings(
  BuildContext context,
  CanvasController controller,
  VideoElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit, {
  /// background is a backdrop's video: a file, not a link, with nothing on
  /// it to press and no box of its own.
  bool background = false,
}) {
  var across = controller.document.editingMaster ||
      (background && controller.document.sharedBackdrop);
  void now(VideoElement next) {
    begin();
    write(next);
    commit();
  }

  var clip = e.clip;
  void clipNow(MediaClip next) => now(e.copyWith(clip: next));
  var list = clip.playlist;
  var show = controller.videoShow(e);
  var word = controller.document.kind;

  Future<void> add() async {
    var source = await pickCanvasVideo(context, controller);
    if (source == null) return;
    var current = controller.document.elementById(e.id);
    if (current is! VideoElement) return;
    var next = current.copyWith(
        link: "",
        clip: current.clip
            .copyWith(playlist: [...current.clip.playlist, source]));
    // The first file gives the box its shape, the way a photograph does: a
    // video squeezed into whatever rectangle happened to be there is either
    // cropped or letterboxed, and the first thing anybody would do is drag
    // the handles until it fits.
    if (current.clip.playlist.isEmpty &&
        source.width > 0 &&
        source.height > 0) {
      var inner = current.look.box.inner(current.bounds);
      var extra = current.height - inner.height;
      next = next.withBase(
              height: inner.width * source.height / source.width + extra)
          as VideoElement;
    }
    now(next);
  }

  void setSource(int i, MediaSource next) {
    var sources = [...list];
    sources[i] = next;
    write(e.copyWith(clip: clip.copyWith(playlist: sources)));
  }

  void move(int i, int by) {
    var j = i + by;
    if (j < 0 || j >= list.length) return;
    var sources = [...list];
    sources.insert(j, sources.removeAt(i));
    clipNow(clip.copyWith(playlist: sources));
  }

  // The look is edited as the picture it is, standing where the video
  // stands, and taken back with whatever it did to the box.
  void writeLook(CanvasElement edited) =>
      write(e.withPicture(edited as ImageElement));

  return [
    CanvasControlGroup(
      label: "Video",
      hideCaption: true,
      rule: false,
      children: [
        CanvasIconButton(
          key: const ValueKey("videoAdd"),
          icon: Icons.video_library_outlined,
          tooltip: list.isEmpty ? "Add a video file" : "Add another file",
          onPressed: add,
        ),
        if (!e.isLink && !clip.isEmpty) ...[
          CanvasIconButton(
            key: const ValueKey("videoPlay"),
            icon: show.playing ? Icons.pause : Icons.play_arrow,
            tooltip: show.playing ? "Pause" : "Play",
            onPressed: () => controller.pressVideo(e, VideoPart.playPause),
          ),
          CanvasIconButton(
            icon: Icons.stop,
            tooltip: "Stop, and back to the poster",
            onPressed: () => controller.video.stop(e.id),
          ),
        ],
        if (!background)
          CanvasTextField(
            key: const ValueKey("videoLink"),
            label: "Or a link",
            value: e.link,
            hint: "https://youtube.com/…",
            width: 180,
            onChanged: (v) => write(e.copyWith(link: v.trim())),
            onCommit: commit,
          ),
        if (e.isLink) ...[
          CanvasNumberField(
            label: "Opens at",
            value: e.linkStart,
            min: 0,
            max: 36000,
            width: 62,
            onChanged: (v) => write(e.copyWith(linkStart: v)),
            onCommit: commit,
          ),
          const CanvasLineBreak(),
          CanvasIconButton(
            icon: Icons.add_photo_alternate_outlined,
            tooltip: "Choose a picture to show for it",
            onPressed: () async {
              var id = await pickCanvasImage(context);
              if (id != null)
                now(e.copyWith(look: e.look.copyWith(assetId: id)));
            },
          ),
          CanvasIconButton(
            icon: Icons.photo_library_outlined,
            tooltip: "Use a picture you have already added",
            onPressed: () async {
              var id = await showRecentPictures(context);
              if (id != null)
                now(e.copyWith(look: e.look.copyWith(assetId: id)));
            },
          ),
          CanvasHint(
              "A ${VideoHost.of(e.link).label} link shows a picture and opens "
              "the video when pressed, after asking. It is somebody else's "
              "video, so it cannot be keyed, trimmed or put into an export -- "
              "add the file for that."),
        ],
        if (!e.isLink && list.isEmpty)
          const CanvasHint(
              "Add a video file (ffmpeg reads it), or paste a link to a video "
              "on YouTube, Vimeo or anywhere else."),
        if (!e.isLink)
          for (var (i, source) in list.indexed) ...[
            const CanvasLineBreak(),
            CanvasChip(
              label: source.name.isEmpty ? "Video ${i + 1}" : source.name,
              onRemove: () =>
                  clipNow(clip.copyWith(playlist: [...list]..removeAt(i))),
            ),
            CanvasNumberField(
              key: ValueKey("videoStart$i"),
              label: "Start",
              value: source.start,
              min: 0,
              max: source.length > 0 ? source.length : 36000,
              decimals: 1,
              width: 58,
              onChanged: (v) => setSource(i, source.copyWith(start: v)),
              onCommit: commit,
            ),
            CanvasNumberField(
              key: ValueKey("videoEnd$i"),
              label: "End",
              value: source.end > 0 ? source.end : source.length,
              min: 0,
              max: source.length > 0 ? source.length : 36000,
              decimals: 1,
              width: 58,
              onChanged: (v) => setSource(
                  i,
                  source.copyWith(
                      end: source.length > 0 && v >= source.length ? 0 : v)),
              onCommit: commit,
            ),
            if (list.length > 1) ...[
              CanvasIconButton(
                icon: Icons.arrow_upward,
                tooltip: "Play earlier",
                onPressed: i == 0 ? null : () => move(i, -1),
              ),
              CanvasIconButton(
                icon: Icons.arrow_downward,
                tooltip: "Play later",
                onPressed: i == list.length - 1 ? null : () => move(i, 1),
              ),
            ],
          ],
      ],
    ),
    if (!e.isLink)
      CanvasMoreGroup(
        label: "Playback",
        remember: "videoPlaybackMore",
        rule: false,
        tooltip: "Fades, and where it starts",
        row: [
          CanvasSlider(
            label: "Volume",
            value: clip.volume,
            onChanged: (v) => write(e.copyWith(clip: clip.copyWith(volume: v))),
            onCommit: commit,
          ),
          CanvasDropdown<MediaLoop>(
            key: const ValueKey("videoLoop"),
            label: "Repeat",
            value: clip.loop,
            width: 130,
            options: [for (var l in MediaLoop.values) (l, l.label)],
            onChanged: (v) => clipNow(clip.copyWith(loop: v)),
          ),
          CanvasToggle(
            key: const ValueKey("videoAutoplay"),
            label: "Start by itself",
            value: clip.autoplay,
            onChanged: (v) => clipNow(clip.copyWith(autoplay: v)),
          ),
          if (across) ...[
            CanvasToggle(
              key: const ValueKey("videoAcross"),
              label: "Across ${word.many}",
              value: clip.acrossPages,
              onChanged: (v) => clipNow(clip.copyWith(acrossPages: v)),
            ),
            CanvasHint(clip.acrossPages
                ? "Keeps playing as the ${word.many} change."
                : "Stops when the ${word.one} changes."),
          ],
        ],
        more: [
          CanvasNumberField(
            label: "Fade in",
            value: clip.fadeIn,
            min: 0,
            max: 60,
            decimals: 1,
            width: 58,
            onChanged: (v) => write(e.copyWith(clip: clip.copyWith(fadeIn: v))),
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Fade out",
            value: clip.fadeOut,
            min: 0,
            max: 60,
            decimals: 1,
            width: 58,
            onChanged: (v) =>
                write(e.copyWith(clip: clip.copyWith(fadeOut: v))),
            onCommit: commit,
          ),
          CanvasToggle(
            label: "Start muted",
            value: clip.muted,
            onChanged: (v) => clipNow(clip.copyWith(muted: v)),
          ),
          const CanvasHint("Fades are seconds, and fade the picture and its "
              "sound together, at the start and end of each file."),
        ],
      ),
    if (!e.isLink && !background)
      CanvasControlGroup(
        label: "Reader's controls",
        rule: false,
        children: [
          for (var control in VideoControl.values)
            CanvasToggle(
              key: ValueKey("videoControl${control.name}"),
              label: control.label,
              value: e.has(control),
              onChanged: (on) => now(e.copyWith(controls: [
                for (var c in VideoControl.values)
                  if (c == control ? on : e.has(c)) c,
              ])),
            ),
        ],
      ),
    if (!e.isLink)
      CanvasControlGroup(
        label: "Green screen",
        rule: false,
        children: [
          CanvasToggle(
            key: const ValueKey("videoKey"),
            label: "Take out the screen",
            value: e.key.on,
            onChanged: (v) => now(e.copyWith(key: e.key.copyWith(on: v))),
          ),
          if (e.key.on) ...[
            CanvasColorButton(
              key: const ValueKey("videoKeyColour"),
              label: "Screen",
              color: e.key.color,
              onChanged: (c) => now(e.copyWith(key: e.key.copyWith(color: c))),
            ),
            CanvasIconButton(
              icon: Icons.circle,
              tooltip: "A green screen",
              onPressed: () => now(e.copyWith(
                  key: e.key.copyWith(color: const Color(0xFF00B140)))),
            ),
            CanvasIconButton(
              icon: Icons.circle_outlined,
              tooltip: "A blue screen",
              onPressed: () => now(e.copyWith(
                  key: e.key.copyWith(color: const Color(0xFF0047BB)))),
            ),
            const CanvasLineBreak(),
            for (var (label, value, apply)
                in <(String, double, ChromaKey Function(double))>[
              (
                "Tolerance",
                e.key.tolerance,
                (v) => e.key.copyWith(tolerance: v)
              ),
              ("Softness", e.key.softness, (v) => e.key.copyWith(softness: v)),
              ("Spill", e.key.spill, (v) => e.key.copyWith(spill: v)),
            ])
              CanvasSlider(
                label: label,
                value: value,
                width: 72,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(key: apply(v)));
                },
                onCommit: commit,
              ),
            const CanvasHint(
                "Tolerance is how much of the screen goes, softness how "
                "gently the edge falls away, and spill how much green is "
                "taken back out of what is left."),
          ],
        ],
      ),
    CanvasControlGroup(label: "Colour", rule: false, children: [
      CanvasDropdown<ImageFit>(
        label: "Fit",
        value: e.look.fit,
        width: 106,
        options: [for (var f in ImageFit.values) (f, f.label)],
        onChanged: (v) => now(e.copyWith(look: e.look.copyWith(fit: v))),
      ),
      CanvasNumberField(
        label: "Saturation",
        decimals: 2,
        width: 62,
        value: e.look.saturation,
        min: 0,
        max: 3,
        onChanged: (v) {
          begin();
          write(e.copyWith(look: e.look.copyWith(saturation: v)));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Brightness",
        decimals: 2,
        width: 62,
        value: e.look.brightness,
        min: 0,
        max: 3,
        onChanged: (v) {
          begin();
          write(e.copyWith(look: e.look.copyWith(brightness: v)));
        },
        onCommit: commit,
      ),
    ]),
    ...pictureLookGroups(e.picture, writeLook, begin, commit, shown: true),
    if (!background)
      boxGroup(
          e.look.box,
          (box) => write(e.copyWith(look: e.look.copyWith(box: box))),
          begin,
          commit,
          remember: "video",
          label: "Background and Border",
          fillLabel: "Background",
          rule: false),
    if (!background)
      boxed(
          context,
          elementAnimationSection(controller, e, e.animation,
              (a) => write(e.copyWith(animation: a)), begin, commit)),
  ];
}
