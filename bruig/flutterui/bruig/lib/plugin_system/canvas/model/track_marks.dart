import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';

// track_marks.dart is an element's own keyframes as the Keys strip and the
// Curves show them: a row a property (Location, Scale, Rotation, Opacity)
// and a row a channel, each with a mark wherever a keyframe pins it. A mark
// moves, goes, or is copied by itself: the rest of its keyframe stays where
// it is. Where every row a keyframe shows is picked, the keyframe goes as a
// whole, so a keyframe saved before keyframes were split is not left behind
// holding the properties that never change.

/// KeyMark is one mark: a row (see rowsOf) and the frame it is on.
typedef KeyMark = ({String row, int frame});

/// allRow is the only row of a track whose keyframes pin nothing that
/// changes (a start pinned before anything is posed): its marks are the
/// keyframes themselves.
const allRow = "all";

/// channelRow is the row of the channel [name] (a counter's number, a
/// chart's reveal).
String channelRow(String name) => "v:$name";

/// rowLabel is what a row is called.
String rowLabel(String row) {
  if (row == allRow) return "Keyframes";
  if (row.startsWith("v:")) {
    var c = row.substring(2);
    return c.isEmpty ? c : c[0].toUpperCase() + c.substring(1);
  }
  return KeyProp.fromName(row)?.label ?? row;
}

/// rowOfValue is the row a Curves line belongs to: across and down are both
/// the location's.
String rowOfValue(String id) => switch (id) {
      "dx" || "dy" => KeyProp.location.name,
      "scale" => KeyProp.scale.name,
      "rotate" => KeyProp.rotation.name,
      "opacity" => KeyProp.opacity.name,
      _ => channelRow(id),
    };

extension TrackMarks on ElementTrack {
  /// rows are the rows shown: each property some keyframe pins away from
  /// rest, then each channel, in the order they first appear. A property
  /// pinned only at rest never changes, so has no row. With nothing that
  /// changes, the one [allRow].
  List<String> get rows {
    var out = <String>[
      for (var p in KeyProp.values)
        if (keys.any((k) => k.pinsProp(p) && !_atRest(k, p))) p.name,
    ];
    var channels = <String>{
      for (var k in keys) ...k.values.keys,
    };
    out.addAll(channels.map(channelRow));
    if (out.isEmpty && keys.isNotEmpty) out.add(allRow);
    return out;
  }

  /// pinsRow is whether [k] has a mark on [row].
  static bool pinsRow(Keyframe k, String row) {
    if (row == allRow) return true;
    if (row.startsWith("v:")) return k.values.containsKey(row.substring(2));
    var p = KeyProp.fromName(row);
    return p != null && k.pinsProp(p);
  }

  /// marksOn are the frames of [row]'s marks.
  List<int> marksOn(String row) => [
        for (var k in keys)
          if (pinsRow(k, row)) k.frame
      ];

  /// allMarks is every mark on the rows shown.
  List<KeyMark> get allMarks => [
        for (var r in rows)
          for (var f in marksOn(r)) (row: r, frame: f)
      ];

  /// moveMarks is this track with [marks] [by] frames later (earlier where
  /// negative), keeping their spacing: null where one would leave the
  /// scene's frames 0 to [last], or land on a mark of its own row.
  ElementTrack? moveMarks(Iterable<KeyMark> marks, int by,
      {required int last}) {
    if (by == 0) return this;
    var groups = _grouped(marks);
    if (groups.isEmpty) return null;
    var at = {for (var k in keys) k.frame: k};
    var lifted = <Keyframe>[];
    for (var MapEntry(key: f, value: rs) in groups.entries) {
      var to = f + by;
      if (to < 0 || to > last) return null;
      var k = at[f]!;
      lifted.add(_part(k, rs).copyWith(frame: to));
      var left = _without(k, rs);
      left == null ? at.remove(f) : at[f] = left;
    }
    for (var part in lifted) {
      var there = at[part.frame];
      if (there != null && _overlaps(there, part)) return null;
    }
    for (var part in lifted) {
      at[part.frame] = _merged(at[part.frame], part);
    }
    return ElementTrack(at.values.toList());
  }

  /// withoutMarks is this track with [marks] taken off: a keyframe left
  /// pinning nothing goes.
  ElementTrack withoutMarks(Iterable<KeyMark> marks) {
    var at = {for (var k in keys) k.frame: k};
    for (var MapEntry(key: f, value: rs) in _grouped(marks).entries) {
      var left = _without(at[f]!, rs);
      left == null ? at.remove(f) : at[f] = left;
    }
    return ElementTrack(at.values.toList());
  }

  /// copyMarks are [marks] as keyframes holding only what is marked, each
  /// with its frame after the first: what pasted elsewhere lands.
  List<(int, Keyframe)> copyMarks(Iterable<KeyMark> marks) {
    var groups = _grouped(marks);
    if (groups.isEmpty) return const [];
    var frames = groups.keys.toList()..sort();
    var at = {for (var k in keys) k.frame: k};
    return [
      for (var f in frames) (f - frames.first, _part(at[f]!, groups[f]!)),
    ];
  }

  /// pasted is this track with [copied] laid from [at]: each over what is
  /// already there, replacing the same properties and keeping the rest.
  ElementTrack pasted(List<(int, Keyframe)> copied, int at) {
    var next = this;
    for (var (offset, part) in copied) {
      var f = at + offset;
      next = next.withKey(_merged(next.keyAt(f), part.copyWith(frame: f)));
    }
    return next;
  }

  /// toggled is this track with [row]'s mark at [frame] taken off, or laid
  /// there holding what the row shows on that frame.
  ElementTrack toggled(String row, int frame) {
    var k = keyAt(frame);
    if (k != null && pinsRow(k, row)) {
      return withoutMarks([(row: row, frame: frame)]);
    }
    if (row == allRow) {
      return withKey(isEmpty ? Keyframe(frame: frame) : restingAt(frame));
    }
    if (row.startsWith("v:")) {
      var c = row.substring(2);
      var v = at(frame).values[c];
      if (v == null) return this;
      return withKey((k ?? Keyframe(frame: frame, pins: 0)).withValue(c, v));
    }
    var p = KeyProp.fromName(row);
    return p == null ? this : posed(frame, [p], (pose) => pose);
  }

  /// shiftLocations is this track with the location of each keyframe at
  /// [frames] moved [dx] across and [dy] down: a keyed path moved whole.
  ElementTrack shiftLocations(Iterable<int> frames, double dx, double dy) {
    var next = this;
    for (var f in frames) {
      var k = keyAt(f);
      if (k == null || !k.pinsProp(KeyProp.location)) continue;
      next = next.withKey(k.copyWith(dx: k.dx + dx, dy: k.dy + dy));
    }
    return next;
  }

  /// _grouped is [marks] by frame, each the rows to take of that keyframe:
  /// [allRow] where they are every row it shows. Marks on no keyframe, or a
  /// row the keyframe does not pin, are left out.
  Map<int, List<String>> _grouped(Iterable<KeyMark> marks) {
    var shown = rows;
    var out = <int, List<String>>{};
    for (var m in marks) {
      var k = keyAt(m.frame);
      if (k == null || !pinsRow(k, m.row)) continue;
      (out[m.frame] ??= []).add(m.row);
    }
    for (var f in out.keys.toList()) {
      var k = keyAt(f)!;
      var has = [
        for (var r in shown)
          if (pinsRow(k, r)) r
      ];
      if (out[f]!.contains(allRow) || has.every(out[f]!.contains)) {
        out[f] = const [allRow];
      }
    }
    return out;
  }
}

/// _atRest is whether [k] holds [p] at rest.
bool _atRest(Keyframe k, KeyProp p) => switch (p) {
      KeyProp.location => k.dx == 0 && k.dy == 0,
      KeyProp.scale => k.scale == 1,
      KeyProp.rotation => k.rotate == 0,
      KeyProp.opacity => k.opacity == 1,
    };

/// _part is [k] holding only [rows], its easing kept.
Keyframe _part(Keyframe k, List<String> rows) {
  if (rows.contains(allRow)) return k;
  var out = Keyframe(frame: k.frame, easing: k.easing, curve: k.curve, pins: 0);
  for (var r in rows) {
    if (r.startsWith("v:")) {
      var c = r.substring(2);
      if (k.values[c] case var v?) out = out.withValue(c, v);
    } else if (KeyProp.fromName(r) case var p?) {
      out = out.withProp(p, k);
    }
  }
  return out;
}

/// _without is [k] without [rows], or null where nothing is left.
Keyframe? _without(Keyframe k, List<String> rows) {
  if (rows.contains(allRow)) return null;
  var out = k;
  for (var r in rows) {
    if (r.startsWith("v:")) {
      out = out.withoutValue(r.substring(2));
    } else if (KeyProp.fromName(r) case var p?) {
      out = out.withoutProp(p);
    }
  }
  return out.holdsNothing ? null : out;
}

/// _overlaps is whether [part] pins anything [there] already does.
bool _overlaps(Keyframe there, Keyframe part) =>
    there.pins & part.pins != 0 ||
    part.values.keys.any(there.values.containsKey);

/// _merged is [part] laid over [into]: its properties and channels replace
/// those, the rest of [into], its easing too, kept.
Keyframe _merged(Keyframe? into, Keyframe part) {
  if (into == null) return part;
  var out = into;
  for (var p in part.props) {
    out = out.withProp(p, part);
  }
  return out.copyWith(values: {...out.values, ...part.values});
}
