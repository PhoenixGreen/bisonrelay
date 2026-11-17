part of '../canvas_controller.dart';

// What the timeline and the mixer are drawn from: the lanes and channels, what
// they show, how a mixer band is shown, the timeline's tools, and the sizes
// they keep to. Part of canvas_controller.dart.

/// TimedLane is one clip on the Channels strip.
class TimedLane {
  final CanvasElement element;

  /// offset is how many frames the clip's timeline is ahead of the scene's:
  /// 0 on this scene, the scene's run start for a clip following the run.
  final int offset;

  /// editable is whether it can be changed here: a transition's sound is
  /// changed on its transition; the master's, from any scene.
  final bool editable;

  /// scene is the clip's canvas: -1 for the master, else the scene's index.
  final int scene;

  const TimedLane(this.element,
      {this.offset = 0, this.editable = true, this.scene = -1});

  /// sceneLabel names the scene on the channel strip: M, or S1 for the first.
  String get sceneLabel => scene < 0 ? "M" : "S${scene + 1}";

  MediaClip get clip => switch (element) {
        VideoElement v => v.clip,
        AudioElement a => a.clip,
        _ => const MediaClip(),
      };

  /// channelKey is the channel this is on: its own, for a clip with none.
  String get channelKey => clip.channel.isNotEmpty ? clip.channel : element.id;

  /// interactive is whether this sounds when pressed on the canvas rather
  /// than at a time: it has a strip and effects like any sound, but nothing
  /// on its lane to move or cut. See interactiveLanes.
  bool get interactive =>
      (element is AudioElement || element is VideoElement) && !clip.timed;
}

/// TimelineShow is what the timeline and the mixer show: see
/// CanvasController.timelineShow.
enum TimelineShow {
  everything("Everything"),
  animation("Animation only"),
  sound("Sound only");

  final String label;
  const TimelineShow(this.label);
}

/// TimelineChannel is one channel of the timeline and the sounds on it.
class TimelineChannel {
  final String key;
  final List<TimedLane> lanes;
  const TimelineChannel(this.key, this.lanes);

  TimedLane get first => lanes.first;

  String get name {
    var named = first.clip.channelName;
    return named.isNotEmpty ? named : first.element.name;
  }

  /// mix is the channel's strip, which every sound on it carries.
  ChannelMix get mix => first.clip.mix;

  bool get editable => lanes.any((l) => l.editable);
  bool get video => first.element is VideoElement;

  /// interactive is a channel of sounds pressed on the canvas (TimedLane).
  bool get interactive => lanes.every((l) => l.interactive);

  /// sceneLabel is which canvas its clips are on (TimedLane.sceneLabel).
  String get sceneLabel => first.sceneLabel;

  /// locked is whether every sound on it is locked -- see lockChannel.
  bool get locked => lanes.every((l) => l.element.locked);
}

/// BandState is how one of the mixer's bands is shown.
enum BandState { shown, minimised, hidden }

/// MixerSection is one of the mixer's bands, in the rail's order: the
/// sends, last, are drawn between the devices and the mixer, as Ableton's.
enum MixerSection {
  clips("C", "Clips"),
  devices("D", "Devices"),
  mixer("M", "Mixer"),

  /// sends are the send dials, a band of their own -- shown or hidden,
  /// never minimised: there is nothing smaller to show of a dial.
  sends("S", "Sends");

  final String letter;
  final String label;
  const MixerSection(this.letter, this.label);
}

/// TimelineTool is what a press on a sound does. See timelineTool.
enum TimelineTool { select, knife }

/// timelineHeaderMin and timelineHeaderMax bound the channel strips' column:
/// from the icon alone to everything on it.
const double timelineHeaderMin = 28;
const double timelineHeaderMax = 360;

/// waveformPoints is how finely a sound's shape is read: enough for a lane
/// several screens wide, few enough to draw every frame.
const int waveformPoints = 2400;
