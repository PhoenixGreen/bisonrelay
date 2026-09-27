import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// audio_settings.dart is an Audio element's settings.
//
// In the order one is set up: the sound itself, how it plays, what the reader
// can do to it, and only then what the speaker looks like. The playlist is
// first because an Audio element with nothing in it does nothing at all, and
// the one thing the panel has to make obvious is where the sound goes in.

List<Widget> audioSettings(
  BuildContext context,
  CanvasController controller,
  AudioElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit, {
  /// background is a backdrop's sound, which is never drawn: nothing to
  /// press, no icon, no box.
  bool background = false,
}) {
  var across = controller.document.editingMaster ||
      (background && controller.document.sharedBackdrop);
  void now(AudioElement next) {
    begin();
    write(next);
    commit();
  }

  var clip = e.clip;
  void clipNow(MediaClip next) => now(e.copyWith(clip: next));
  var list = clip.playlist;
  var state = controller.audioState(e);
  var word = controller.document.kind;

  Future<void> add() async {
    var source = await pickCanvasAudio(context, controller);
    if (source == null) return;
    // Read again: the element may have been edited while the file dialog
    // was open, and writing the stale one back would undo that.
    var current = controller.document.elementById(e.id);
    if (current is! AudioElement) return;
    now(current.copyWith(
        clip: current.clip
            .copyWith(playlist: [...current.clip.playlist, source])));
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
    var moved = sources.removeAt(i);
    sources.insert(j, moved);
    clipNow(clip.copyWith(playlist: sources));
  }

  return [
    CanvasControlGroup(
      label: "Sound",
      hideCaption: true,
      rule: false,
      children: [
        CanvasIconButton(
          key: const ValueKey("audioAdd"),
          icon: Icons.library_music_outlined,
          tooltip: list.isEmpty ? "Add a sound file" : "Add another file",
          onPressed: add,
        ),
        if (!clip.isEmpty)
          CanvasIconButton(
            key: const ValueKey("audioListen"),
            icon: state.playing ? Icons.pause : Icons.play_arrow,
            tooltip: state.playing ? "Pause" : "Listen",
            onPressed: () => controller.pressAudio(e, AudioControl.playPause),
          ),
        if (!clip.isEmpty)
          CanvasIconButton(
            icon: Icons.stop,
            tooltip: "Stop, and back to the start",
            onPressed: () => controller.audio.stop(e.id),
          ),
        if (list.isEmpty)
          const CanvasHint(
              "Add a sound file: MP3, WAV, Ogg or FLAC. M4A and AIFF are "
              "converted when ffmpeg is installed."),
        if (controller.audioUnavailable)
          const CanvasHint(
              "No sound device could be opened, so nothing will be heard. "
              "Check that one is connected and not in use."),
        // One line per file: its name, the part of it that plays, and where
        // it sits in the list. More than one file is a playlist.
        for (var (i, source) in list.indexed) ...[
          const CanvasLineBreak(),
          CanvasChip(
            label: source.name.isEmpty ? "Sound ${i + 1}" : source.name,
            onRemove: () =>
                clipNow(clip.copyWith(playlist: [...list]..removeAt(i))),
          ),
          CanvasNumberField(
            key: ValueKey("audioStart$i"),
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
            key: ValueKey("audioEnd$i"),
            label: "End",
            // Nought is "to the end", and shows as the end where the length
            // is known -- a field reading 0 beside a start of 10 reads as a
            // range that is backwards.
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
        if (list.isNotEmpty)
          const CanvasHint("Start and End are seconds into the file."),
      ],
    ),
    CanvasMoreGroup(
      label: "Playback",
      remember: "audioPlaybackMore",
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
          key: const ValueKey("audioLoop"),
          label: "Repeat",
          value: clip.loop,
          width: 130,
          options: [for (var l in MediaLoop.values) (l, l.label)],
          onChanged: (v) => clipNow(clip.copyWith(loop: v)),
        ),
        CanvasToggle(
          key: const ValueKey("audioAutoplay"),
          label: "Start by itself",
          value: clip.autoplay,
          onChanged: (v) => clipNow(clip.copyWith(autoplay: v)),
        ),
        // The one setting only the master can mean -- see
        // MediaClip.acrossPages -- so it is only offered there.
        if (across) ...[
          CanvasToggle(
            key: const ValueKey("audioAcross"),
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
          key: const ValueKey("audioFadeIn"),
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
          key: const ValueKey("audioFadeOut"),
          label: "Fade out",
          value: clip.fadeOut,
          min: 0,
          max: 60,
          decimals: 1,
          width: 58,
          onChanged: (v) => write(e.copyWith(clip: clip.copyWith(fadeOut: v))),
          onCommit: commit,
        ),
        CanvasToggle(
          label: "Start muted",
          value: clip.muted,
          onChanged: (v) => clipNow(clip.copyWith(muted: v)),
        ),
        CanvasHint(clip.autoplay
            ? "It starts when the canvas plays, and on each ${word.one} it "
                "is on as that ${word.one} opens during playback."
            : "Fades are seconds, at the start and end of each file."),
      ],
    ),
    if (!background)
      CanvasControlGroup(
        label: "Reader's controls",
        rule: false,
        children: [
          for (var control in AudioControl.values)
            CanvasToggle(
              key: ValueKey("audioControl${control.name}"),
              label: control.label,
              value: e.has(control),
              onChanged: (on) {
                var controls = [
                  for (var c in AudioControl.values)
                    if (c == control ? on : e.has(c)) c,
                ];
                now(_fitted(e.copyWith(controls: controls)));
              },
            ),
          if (e.controls.isEmpty)
            const CanvasHint(
                "Nothing to press: the speaker is a picture, and the sound "
                "plays by itself or from a button. A sound only ever started by "
                "buttons can be hidden -- hidden is not drawn, and still plays."),
        ],
      ),
    if (!background)
      CanvasMoreGroup(
        label: "Icon",
        remember: "audioIconMore",
        rule: false,
        tooltip: "Your own pictures for the icon",
        row: [
          CanvasDropdown<AudioGlyph>(
            key: const ValueKey("audioGlyph"),
            label: "Shape",
            value: e.glyph,
            width: 130,
            options: [for (var g in AudioGlyph.values) (g, g.label)],
            onChanged: (v) => now(e.copyWith(glyph: v)),
          ),
          CanvasColorButton(
            label: "Icon",
            color: e.iconColor,
            onChanged: (c) => now(e.copyWith(iconColor: c)),
          ),
          CanvasColorButton(
            label: "Playing",
            color: e.accent,
            onChanged: (c) => now(e.copyWith(accent: c)),
          ),
        ],
        more: [
          for (var (label, id, set) in [
            ("Icon", e.picture, (String v) => e.copyWith(picture: v)),
            (
              "Paused",
              e.pausedPicture,
              (String v) => e.copyWith(pausedPicture: v)
            ),
            (
              "Muted",
              e.mutedPicture,
              (String v) => e.copyWith(mutedPicture: v)
            ),
          ]) ...[
            CanvasReadout(
                label: label,
                value: id.isEmpty ? "Drawn" : "Picture",
                width: 64),
            CanvasIconButton(
              icon: Icons.add_photo_alternate_outlined,
              tooltip: "Use a picture for the ${label.toLowerCase()} icon",
              onPressed: () async {
                var picked = await pickCanvasImage(context);
                if (picked != null) now(set(picked));
              },
            ),
            CanvasIconButton(
              icon: Icons.photo_library_outlined,
              tooltip: "Use a picture you have already added",
              onPressed: () async {
                var picked = await showRecentPictures(context);
                if (picked != null) now(set(picked));
              },
            ),
            if (id.isNotEmpty)
              CanvasIconButton(
                icon: Icons.hide_image_outlined,
                tooltip: "Back to the drawn icon",
                onPressed: () => now(set("")),
              ),
            const CanvasLineBreak(),
          ],
          const CanvasHint(
              "Paused and Muted fall back to Icon, so one picture is enough. "
              "Three make an icon that changes with the sound."),
        ],
      ),
    if (!background)
      boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
          remember: "audio", rule: false),
    if (!background)
      boxed(
          context,
          elementAnimationSection(controller, e, e.animation,
              (a) => write(e.copyWith(animation: a)), begin, commit)),
  ];
}

/// _fitted is [e] made wide enough for the controls it has, or square again
/// when it has none beside the icon.
///
/// Worked out from the layout's own proportions -- see audioParts -- so a
/// volume bar turned on arrives at a width it can be used at, rather than as
/// a sliver the reader then has to find the handle to widen.
AudioElement _fitted(AudioElement e) {
  var pad = e.box.pad;
  var side = math.max(1.0, e.height - pad.top - pad.bottom);
  var across = side;
  if (e.has(AudioControl.mute)) across += side * 0.95;
  if (e.has(AudioControl.volume)) across += side * 3.25;
  var width = across + pad.left + pad.right;
  return e.withBase(width: width) as AudioElement;
}
