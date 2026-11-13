import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart'
    show channelClip;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// element_sound.dart is an element's own sound channel, shown with it: its
// lane under the element's rows on the timeline, its strip beside the
// element's in the mixer. Underneath it is a channel like any other, keyed
// [elementSoundKey] and holding hidden audio elements, so playing, slots,
// effects, the fader and export all work on it. Its Output can send it into
// a return, for elements to share a bus; see ChannelMix.output.

/// elementSoundKey is the key of [element]'s own sound channel.
String elementSoundKey(String element) => "snd-$element";

/// soundOwnerOf is the element that owns channel [key], if one does: the
/// element a "snd-" channel was made for, or a video on the timeline whose
/// channel is its own -- keyed by its id, carrying its own sound. Owned, a
/// channel is one row with its element's motion (see canvasRowsOf): a
/// video's was two, Motion and Video, the motion row showing only while it
/// was picked (Ken, 2026-11-13: "we might have missed the video element
/// when we were combining tracks").
CanvasElement? soundOwnerOf(CanvasDocument doc, String key) {
  if (key.startsWith("snd-")) return doc.elementById(key.substring(4));
  if (doc.elementById(key) case VideoElement v when ownsChannel(v)) return v;
  return null;
}

/// ownsChannel is whether [v] is on the timeline on a channel of its own,
/// not one it shares with other sounds.
bool ownsChannel(VideoElement v) => v.clip.timed && v.clip.channel.isEmpty;

/// ownChannelOf is the key of [element]'s own channel, the one on its row:
/// a video's own, for a video on the timeline; else the one made for its
/// sound (elementSoundKey), whether or not it has been yet.
String ownChannelOf(CanvasDocument doc, String element) =>
    switch (doc.elementById(element)) {
      VideoElement v when ownsChannel(v) => v.id,
      _ => elementSoundKey(element),
    };

/// hasOwnSound is whether [element] has a sound channel of its own.
bool hasOwnSound(CanvasDocument doc, String element) {
  var key = elementSoundKey(element);
  return doc.elements.any((e) => e is AudioElement && e.clip.channel == key);
}

extension ElementSound on CanvasController {
  /// soundChannelOf is [element]'s own channel, if it has one.
  TimelineChannel? soundChannelOf(String element) {
    var key = elementSoundKey(element);
    return timelineChannels.where((c) => c.key == key).firstOrNull;
  }

  /// ensureElementSound gives [element] a channel of its own, empty, if it
  /// has none: a lane to drop sounds on, and slots to put them in. Its key.
  String ensureElementSound(String element) {
    var key = elementSoundKey(element);
    if (hasOwnSound(document, element)) return key;
    var e = document.elementById(element);
    var name = e == null || e.name.isEmpty ? "Sound" : e.name;
    addElement(AudioElement(
      ElementBase(id: newElementId(), name: name, visible: false),
      clip: MediaClip(timed: true, channel: key, channelName: name),
      controls: const [],
    ));
    return key;
  }

  /// addElementSound puts [source] on [element]'s own channel at [frame],
  /// giving it one if it has none, playing through it as it is set.
  void addElementSound(String element, MediaSource source, int frame) {
    var key = elementSoundKey(element);
    var e = document.elementById(element);
    var name = e == null || e.name.isEmpty ? "Sound" : e.name;
    var mix = soundChannelOf(element)?.mix ?? const ChannelMix();
    addElement(channelClip(document, frame,
        source: source, channel: key, channelName: name, mix: mix));
  }

  /// soundOutputOf is where [element]'s own sound goes: "" the master, or a
  /// return's id.
  String soundOutputOf(String element) =>
      soundChannelOf(element)?.mix.output ?? "";

  /// setSoundOutput sends [element]'s own sound into return [output], or
  /// "" to the master.
  void setSoundOutput(String element, String output) {
    var channel = soundChannelOf(element);
    if (channel == null) return;
    // Where it goes is not a setting a lane moves: the channel's own mix.
    setChannelMix(channel, channel.mix.copyWith(output: output));
  }
}
