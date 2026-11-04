import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart'
    show channelClip;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// element_sound.dart is an element's own sound: a sound channel it owns,
// shown with it -- its lane under the element's rows on the timeline, its
// strip beside the element's in the mixer -- rather than among the canvas's
// other channels (Ken).
//
// A channel like any other underneath: its sounds are hidden audio elements
// on the channel keyed [elementSoundKey], so playing, the slots, the effects,
// the fader and an export all work on it as they do on any. Its Output sends
// it whole into a return instead of to the master, for a group of elements
// to share one bus -- see ChannelMix.output.

/// elementSoundKey is the key of [element]'s own sound channel.
String elementSoundKey(String element) => "snd-$element";

/// soundOwnerOf is the element that owns channel [key], if one does.
CanvasElement? soundOwnerOf(CanvasDocument doc, String key) =>
    key.startsWith("snd-") ? doc.elementById(key.substring(4)) : null;

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
