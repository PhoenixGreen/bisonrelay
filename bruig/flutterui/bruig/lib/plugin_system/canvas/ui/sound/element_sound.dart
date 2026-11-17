import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart'
    show channelClip;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// element_sound.dart is an element's own sound channel: its lane under the
// element's timeline rows, its strip beside the element's in the mixer. It
// is an ordinary channel keyed [elementSoundKey] holding hidden audio
// elements, so playing, slots, effects, fader and export all work. Its
// Output can send it into a return to share a bus; see ChannelMix.output.

String elementSoundKey(String element) => "snd-$element";

/// soundOwnerOf is the element that owns channel [key]: the one a "snd-"
/// channel was made for, or a timed video whose own channel is keyed by its
/// id. An owned channel is one row with its element's motion (see
/// canvasRowsOf), videos included.
CanvasElement? soundOwnerOf(CanvasDocument doc, String key) {
  if (key.startsWith("snd-")) return doc.elementById(key.substring(4));
  if (doc.elementById(key) case VideoElement v when ownsChannel(v)) return v;
  return null;
}

/// ownsChannel is whether [v] is on the timeline on its own channel rather
/// than one shared with other sounds.
bool ownsChannel(VideoElement v) => v.clip.timed && v.clip.channel.isEmpty;

/// ownChannelOf is the key of [element]'s own channel: a timed video's own,
/// else the one for its sound (elementSoundKey), made yet or not.
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
  TimelineChannel? soundChannelOf(String element) {
    var key = elementSoundKey(element);
    return timelineChannels.where((c) => c.key == key).firstOrNull;
  }

  /// ensureElementSound gives [element] an empty channel of its own if it has
  /// none, and returns its key.
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
  /// making the channel if needed.
  void addElementSound(String element, MediaSource source, int frame) {
    var key = elementSoundKey(element);
    var e = document.elementById(element);
    var name = e == null || e.name.isEmpty ? "Sound" : e.name;
    var mix = soundChannelOf(element)?.mix ?? const ChannelMix();
    addElement(channelClip(document, frame,
        source: source, channel: key, channelName: name, mix: mix));
  }

  /// soundOutputOf is where [element]'s sound goes: "" the master, or a
  /// return's id.
  String soundOutputOf(String element) =>
      soundChannelOf(element)?.mix.output ?? "";

  /// setSoundOutput sends [element]'s sound into return [output], or "" to
  /// the master.
  void setSoundOutput(String element, String output) {
    var channel = soundChannelOf(element);
    if (channel == null) return;
    // The channel's own mix, not a setting a lane moves.
    setChannelMix(channel, channel.mix.copyWith(output: output));
  }
}
