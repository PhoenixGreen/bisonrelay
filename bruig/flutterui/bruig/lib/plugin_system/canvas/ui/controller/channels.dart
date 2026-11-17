part of '../canvas_controller.dart';

// Part of CanvasController: the timeline's channels -- naming them, picking
// them, their rows' colours.

extension CanvasChannelTools on CanvasController {
  /// newChannelName is "Channel" and the next free number: not "Audio", as a
  /// channel also holds a video's soundtrack.
  String newChannelName() {
    var taken = {for (var c in timelineChannels) c.name};
    for (var n = 1;; n++) {
      if (!taken.contains("Channel $n")) return "Channel $n";
    }
  }

  String newChannelId() => "ch${newElementId()}";

  /// moveClipToChannel puts [lane]'s sound on [to], or a channel of its own;
  /// the channel it leaves goes if it was the last thing on it.
  void moveClipToChannel(TimedLane lane, TimelineChannel? to,
      {bool transient = false}) {
    var e = lane.element;
    if ((e is! AudioElement && e is! VideoElement) || !lane.editable) return;
    // Onto a channel of its own canvas: a channel is the clips on it, and
    // one holding a scene's clip and the master's would be two canvases'.
    if (to != null && to.first.scene != lane.scene) return;
    var clip = lane.clip;
    var moved = to == null
        ? clip.copyWith(
            channel: newChannelId(),
            channelName: newChannelName(),
            mix: const ChannelMix())
        : clip.copyWith(channel: to.key, channelName: to.name, mix: to.mix);
    _setClips([(lane.element, moved)], transient: transient);
  }

  /// splitClip cuts [lane]'s sound at [frame] of the scene, the part after
  /// becoming a sound of its own on the same channel, where the cut was.
  bool splitClip(TimedLane lane, int frame) {
    var e = lane.element;
    // A sound, or a video -- whose two halves are two videos in the same
    // place on the canvas, each on screen while its half plays.
    if ((e is! AudioElement && e is! VideoElement) ||
        !lane.editable ||
        e.locked) {
      return false;
    }
    var clip = lane.clip;
    CanvasElement withClip(MediaClip c) => switch (e) {
          VideoElement v => v.copyWith(clip: c),
          AudioElement a => a.copyWith(clip: c),
          _ => e,
        };
    // Both halves on one channel. A video put on the timeline from its
    // settings has none of its own -- its lane is keyed by its id -- so it
    // is given one here, or the half after the cut would be a lane apart.
    if (clip.channel.isEmpty) {
      clip = clip.copyWith(
          channel: newChannelId(),
          channelName: clip.channelName.isNotEmpty ? clip.channelName : e.name);
    }
    var rate = math.max(1, _document.frameRate);
    var into = (frame - (clip.at - lane.offset)) / rate;
    if (into <= 0.05 || into >= clip.runLength - 0.05) return false;
    // The files are cut in their own seconds: at a speed of its own, a
    // second of the timeline is more or less of the file.
    var inFile = into * (clip.speed > 0.01 ? clip.speed : 1);
    var from = 0.0;
    for (var (i, source) in clip.playlist.indexed) {
      var span = source.span;
      if (inFile < from + span) {
        var cut = source.start + (inFile - from);
        var before = [
          ...clip.playlist.take(i),
          source.copyWith(end: cut),
        ];
        var after = [
          source.copyWith(start: cut),
          ...clip.playlist.skip(i + 1),
        ];
        var first = withClip(
            clip.copyWith(playlist: before, fadeOut: 0, loop: MediaLoop.none));
        var second = withClip(clip.copyWith(
                playlist: after,
                fadeIn: 0,
                at: clip.at + (into * rate).round()))
            .withId(newElementId());
        var replaced = _replacedAnywhere(_document, first);
        var both =
            replaced == null ? null : _addedBeside(replaced, first.id, second);
        if (both == null) return false;
        apply(both);
        // Picked where it can be: on the canvas being edited.
        if (_document.elements.any((x) => x.id == second.id)) {
          selectOnly(second.id);
        }
        return true;
      }
      from += span;
    }
    return false;
  }

  /// selectedChannels are the channels picked -- by strip, sound or a box
  /// dragged across them -- which a cut at the playhead is made on.
  Set<String> get selectedChannels => _selectedChannels;

  /// selectedChannel is the one channel picked, where one is; setting it
  /// picks that alone.
  String? get selectedChannel =>
      _selectedChannels.isEmpty ? null : _selectedChannels.first;

  set selectedChannel(String? key) =>
      selectChannels(key == null ? const {} : {key});

  void selectChannels(Set<String> keys) {
    if (setEquals(keys, _selectedChannels)) return;
    _selectedChannels = {...keys};
    // One channel picked -- on the timeline or in the mixer -- is the one
    // the effects panel shows.
    if (keys.length == 1) _effectsOf = keys.first;
    notifyListeners();
  }

  void toggleChannel(String key) {
    var next = {..._selectedChannels};
    if (!next.remove(key)) next.add(key);
    selectChannels(next);
  }

  /// cutAtPlayhead cuts every sound the playhead is part way through on the
  /// selected channel, or the selected sound's: the knife's key.
  bool cutAtPlayhead() {
    var keys = {..._selectedChannels};
    if (keys.isEmpty) {
      var picked = clipSelection;
      for (var lane in timedLanes) {
        if (picked.contains(lane.element.id)) keys.add(lane.channelKey);
      }
    }
    var cut = false;
    for (var channel in timelineChannels) {
      if (!keys.contains(channel.key) || channel.locked) continue;
      for (var lane in channel.lanes) {
        // Fresh each time: a cut changes the document the next one reads.
        var now = timedLanes.where((l) => l.element.id == lane.element.id);
        if (now.isEmpty) continue;
        if (splitClip(now.first, _frame)) cut = true;
      }
    }
    return cut;
  }

  /// lockChannel locks or unlocks every sound on [channel]: locked, none of
  /// them is moved, trimmed, faded, cut or dropped onto.
  void lockChannel(TimelineChannel channel, bool locked) {
    var next = _document;
    for (var lane in channel.lanes) {
      if (!lane.editable) continue;
      next = _replacedAnywhere(next, lane.element.withBase(locked: locked)) ??
          next;
    }
    apply(next);
  }

  /// rowColour is row [key]'s colour -- an element's row by its id, a
  /// sound's by its channel's key -- on the timeline, mixer and slots: the
  /// one picked, kept on its element or sounds, or else its given colour,
  /// the same every time (rowPalette).
  Color rowColour(String key) {
    var channel = timelineChannels.where((c) => c.key == key).firstOrNull;
    int? picked;
    if (channel != null) {
      picked = channel.lanes
          .map((l) => l.element.base.rowColour)
          .whereType<int>()
          .firstOrNull;
    } else {
      picked = _document.elementById(key)?.base.rowColour;
    }
    return picked != null ? Color(picked) : givenRowColour(key);
  }

  /// setRowColour picks row [key]'s colour, or with null gives it back the
  /// one it is given: on its element, or on every sound in its channel.
  void setRowColour(String key, Color? colour) {
    var argb = colour?.toARGB32();
    CanvasElement coloured(CanvasElement e) => e.rebase(e.base
        .copyWith(rowColour: argb, clearRowColour: argb == null));
    var channel = timelineChannels.where((c) => c.key == key).firstOrNull;
    var targets = channel != null
        ? [
            for (var l in channel.lanes)
              if (l.editable) l.element
          ]
        : [
            if (_document.elementById(key) case var e?) e,
          ];
    if (targets.isEmpty) return;
    var next = _document;
    for (var e in targets) {
      next = _replacedAnywhere(next, coloured(e)) ?? next;
    }
    apply(next);
  }

  /// renameChannel names [channel], on every sound it holds.
  void renameChannel(TimelineChannel channel, String name) {
    var named = name.trim();
    if (named.isEmpty) return;
    _setClips([
      for (var lane in channel.lanes)
        if (lane.editable)
          (lane.element, lane.clip.copyWith(channelName: named)),
    ]);
  }
}
