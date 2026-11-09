import 'package:bruig/plugin_system/canvas/model/canvas_document.dart'
    show transitionSoundPrefix;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_lanes.dart'
    show motionRowsOf;

// canvas_rows.dart is the one list of rows the timeline, the mixer and the
// slots all show (Ken, 2026-11-08: "audio and motion should be one channel
// rather than 2"): one row for each element, its motion with its own sound
// (the channel keyed elementSoundKey, see element_sound.dart); then a row
// for each sound that is nobody's -- music, a narrator, a MIDI part. A row
// on the master canvas, heard in every scene, is in the All group, shown
// after the scene's own and folded away as one.

/// RowGroup is which group a row is shown in: the scene's own, or All -- on
/// the master canvas, there in every scene.
enum RowGroup { scene, all }

/// CanvasRow is one row: an element and its own sound, or a sound alone.
class CanvasRow {
  /// element is the element whose motion the row shows; null for a sound
  /// that belongs to no element.
  final CanvasElement? element;

  /// channels are the sound the row carries: the element's own channel (at
  /// most one), or the channel a sound-only row is.
  final List<TimelineChannel> channels;

  final RowGroup group;

  const CanvasRow(
      {this.element, this.channels = const [], this.group = RowGroup.scene});

  /// key is the row's: its element's id, or its channel's key.
  String get key => element?.id ?? channels.first.key;

  bool get hasMotion => element != null;
  bool get hasSound => channels.isNotEmpty;

  /// channel is the row's sound channel, where it has one.
  TimelineChannel? get channel => channels.isEmpty ? null : channels.first;

  /// transitions is whether the row is the scenes' transition sounds: a
  /// channel of its own today, the Scenes row's in the new timeline.
  bool get transitions =>
      element == null &&
      channels.isNotEmpty &&
      channels.first.lanes
          .every((l) => l.element.id.startsWith(transitionSoundPrefix));
}

/// canvasRowsOf is [c]'s rows, in the order every panel shows them: the
/// elements (as motionRowsOf has them), then the sounds that are nobody's
/// (as timelineChannels has them, the master's last); the All group's after
/// the scene's own.
List<CanvasRow> canvasRowsOf(CanvasController c) {
  var doc = c.document;
  var elements = motionRowsOf(c);
  var withRow = {for (var e in elements) e.id};
  var owned = <String, List<TimelineChannel>>{};
  var loose = <TimelineChannel>[];
  for (var ch in c.timelineChannels) {
    var owner = soundOwnerOf(doc, ch.key);
    if (owner != null && withRow.contains(owner.id)) {
      (owned[owner.id] ??= []).add(ch);
    } else {
      loose.add(ch);
    }
  }
  // On the master canvas while a scene is edited: in every scene, so in All.
  // Editing the master itself, everything is the master's: one group.
  RowGroup groupOf(TimelineChannel ch) =>
      !doc.editingMaster && ch.lanes.every((l) => l.scene < 0)
          ? RowGroup.all
          : RowGroup.scene;
  var rows = [
    for (var e in elements)
      CanvasRow(element: e, channels: owned[e.id] ?? const []),
    for (var ch in loose) CanvasRow(channels: [ch], group: groupOf(ch)),
  ];
  return [
    for (var r in rows)
      if (r.group == RowGroup.scene) r,
    for (var r in rows)
      if (r.group == RowGroup.all) r,
  ];
}
