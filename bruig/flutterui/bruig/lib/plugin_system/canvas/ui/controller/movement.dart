part of '../canvas_controller.dart';

// Elements moved in time: a move made into motion where the canvas
// CanvasController.animates, the camera's shifts and zoom, following a path,
// and the value keys an element's settings take. Part of CanvasController: its
// fields and lifecycle are in canvas_controller.dart.

extension CanvasMovement on CanvasController {
  /// movedTo is the stage's drag: where [element]'s top-left should now be.
  /// Absolute rather than a delta, since deltas drift and compound on a pose.
  CanvasElement movedTo(CanvasElement element, Offset topLeft) {
    // An element on a stage moves across its floor, or along its back wall.
    if (element.base.spot != null) {
      var at = stagedIn(_document, element, _frame);
      if (at != null) {
        // Where it stands on this frame; keyed, the move is a key here.
        var spot = at.spot;
        var by = topLeft - at.box.topLeft;
        var view = at.view;
        // Snapping lands on the 3D steps: a stage has no lines to snap to.
        var step =
            _document.guides.stageSnap ? _document.guides.stageStep : 0.0;
        double snap(double v) =>
            step > 0 ? (v / step).roundToDouble() * step : v;
        switch (spot.stand) {
          case SpotStand.wall:
            var was = view.toWall(at.box.bottomCenter, -at.stage.size + 0.01);
            var now = view.toWall(at.box.bottomCenter + by,
                -at.stage.size + 0.01);
            if (was == null || now == null) return element;
            return spotted(
                element,
                spot.copyWith(
                    x: snap(spot.x + now.dx - was.dx),
                    lift: snap(spot.lift + now.dy - was.dy)));
          default:
            // The floor point under the pointer follows it, on the level
            // the element is lifted to.
            var level = spot.stand == SpotStand.floor ? 0.0 : spot.lift;
            var was = view.toFloor(at.foot, y: level),
                now = view.toFloor(at.foot + by, y: level);
            if (was == null || now == null) return element;
            return spotted(
                element,
                spot.copyWith(
                    x: snap(spot.x + now.dx - was.dx),
                    z: snap(spot.z + now.dy - was.dy)));
        }
      }
    }
    if (!posesRatherThanMoves(element)) {
      return element.withBase(x: topLeft.dx, y: topLeft.dy);
    }
    var track = (element.track ?? ElementTrack.empty).seededFor(_frame);
    var pose = track.at(_frame);
    return element.withBase(
      track: track.withKey(pose.copyWith(
        frame: _frame,
        dx: topLeft.dx - element.x,
        dy: topLeft.dy - element.y,
      )),
    );
  }

  /// cameraShifted is [start], a camera as a drag began, looking [by]
  /// further across and down: a key on this frame where it is animated,
  /// else its box moved. Kept to what the framing allows, so a drag past
  /// the edge leaves no pose the frame cannot follow.
  CanvasElement cameraShifted(CameraElement start, Offset by) {
    var page = _document.size.rect;
    var (zoom, _) = cameraFraming(start, _frame, _document);
    var roll = cameraLookAt(start, _frame, _document).roll;
    var (hx, hy) = cameraHalfExtents(zoom, roll, page.size);
    var posed = posesRatherThanMoves(start);
    var track = (start.track ?? ElementTrack.empty).seededFor(_frame);
    var pose = posed ? track.at(_frame) : Keyframe.rest;
    var centre = start.bounds.center + Offset(pose.dx, pose.dy) + by;
    var kept = Offset(centre.dx.clamp(page.left + hx, page.right - hx),
        centre.dy.clamp(page.top + hy, page.bottom - hy));
    var moved = kept - (start.bounds.center + Offset(pose.dx, pose.dy));
    if (!posed) {
      return start.withBase(x: start.x + moved.dx, y: start.y + moved.dy);
    }
    return start.withBase(
        track: track.withKey(pose.copyWith(
            frame: _frame, dx: pose.dx + moved.dx, dy: pose.dy + moved.dy)));
  }

  /// cameraZoomed is [start], a camera as a drag began, [factor] times
  /// closer about the middle of its view: a key's size where animated, else
  /// its box. Between the whole page and eight times.
  CanvasElement cameraZoomed(CameraElement start, double factor) {
    if (!factor.isFinite || factor <= 0) return start;
    var (zoom, at) = cameraFraming(start, _frame, _document);
    var next = (zoom * factor).clamp(1.0, 8.0);
    var by = next / zoom;
    CanvasElement out;
    if (posesRatherThanMoves(start)) {
      var track = (start.track ?? ElementTrack.empty).seededFor(_frame);
      var pose = track.at(_frame);
      // Where it looks stays put: the pose's shift is from its box's middle.
      out = start.withBase(
          track: track.withKey(pose.copyWith(
              frame: _frame,
              scale: pose.scale * by,
              dx: at.dx - start.bounds.center.dx,
              dy: at.dy - start.bounds.center.dy)));
    } else {
      var w = start.width / by, h = start.height / by;
      out = start.withBase(
          x: at.dx - w / 2, y: at.dy - h / 2, width: w, height: h);
    }
    // Further out near an edge, the framing moves it back onto the page.
    var cam = out as CameraElement;
    var (_, now) = cameraFraming(cam, _frame, _document.withElement(cam));
    var raw = cam.bounds.center +
        (posesRatherThanMoves(cam)
            ? Offset((cam.track ?? ElementTrack.empty).at(_frame).dx,
                (cam.track ?? ElementTrack.empty).at(_frame).dy)
            : Offset.zero);
    if ((now - raw).distance > 1e-6) {
      return cameraShifted(cam, now - raw);
    }
    return cam;
  }

  /// pathDriving is the path that owns [elementId]'s keyframes, if any. Its
  /// track is rewritten when the route changes, so the timeline refuses hand
  /// edits and shows the path's points.
  PathElement? pathDriving(String elementId, {int? playerIndex}) {
    for (var element in _document.elements) {
      if (element is! PathElement) continue;
      var follow = element.follow;
      if (follow == null || follow.elementId != elementId) continue;
      if (follow.playerIndex != playerIndex) continue;
      return element;
    }
    return null;
  }

  /// applyPathFollow bakes [path]'s route into its follower's keyframes, one
  /// per frame from the first node to the last, sampled by arc length.
  /// Baked rather than live, so the renderer, the GIF encoder and a
  /// published canvas play it like any track and cannot disagree.
  void applyPathFollow(PathElement path) {
    var follow = path.follow;
    if (follow == null || path.nodes.length < 2) return;

    var target = _document.elementById(follow.elementId);
    if (target == null) return;

    var from = path.firstFrame;
    var to = path.lastFrame;
    if (to <= from) return;

    var index = follow.playerIndex;
    if (target is TeamElement && index != null) {
      if (index < 0 || index >= target.players.length) return;
      var spot = target.players[index];
      // On a pitch the route is carried onto the pitch's own metres, so the
      // follower keeps to the curve however the pitch is seen.
      var ground = teamGround(_document, target, from);
      if (ground != null) {
        replaceElement(target.withPlayer(
            index,
            spot.copyWith(
                track: _bakeOnPitch(path, ground, target, spot, from, to))));
        return;
      }
      var rest = target.centreOf(spot);
      replaceElement(target.withPlayer(
          index, spot.copyWith(track: _bake(path, rest, from, to))));
      return;
    }

    // An element is placed by its top-left, so the route, which describes
    // where the thing is, is measured from its centre and shifted back.
    replaceElement(
        target.withBase(track: _bake(path, target.center, from, to)));
  }

  /// _bakeOnPitch is [_bake] for a player on a pitch, in the units a run on
  /// a pitch is kept in (see playerPlace).
  ElementTrack _bakeOnPitch(PathElement path, TeamGround ground,
      TeamElement team, PlayerSpot spot, int from, int to) {
    var rest = teamFieldPoint(team, spot, ground.place);
    var ref = ground.place.reference;
    var keys = <Keyframe>[];
    for (var f = from; f <= to; f++) {
      var at = path.positionAtFrame(f);
      if (at == null) continue;
      var field = ground.field(at);
      if (field == null) continue;
      keys.add(Keyframe(
          frame: f,
          dx: (field.dx - rest.dx) * ref,
          dy: -(field.dy - rest.dy) * ref));
    }
    return ElementTrack(keys);
  }

  /// _bake turns a path into a track of poses relative to [rest].
  ElementTrack _bake(PathElement path, Offset rest, int from, int to) {
    var keys = <Keyframe>[];
    for (var f = from; f <= to; f++) {
      var at = path.positionAtFrame(f);
      if (at == null) continue;
      keys.add(Keyframe(frame: f, dx: at.dx - rest.dx, dy: at.dy - rest.dy));
    }
    return ElementTrack(keys);
  }

  /// clearPathFollow takes the baked keys off, or the follower is stranded.
  void clearPathFollow(PathElement path) {
    var follow = path.follow;
    if (follow == null) return;
    var target = _document.elementById(follow.elementId);
    if (target == null) return;

    var index = follow.playerIndex;
    if (target is TeamElement && index != null) {
      if (index < 0 || index >= target.players.length) return;
      replaceElement(target.withPlayer(
          index, target.players[index].copyWith(clearTrack: true)));
      return;
    }
    replaceElement(target.withBase(clearTrack: true));
  }

  /// followerLabel names what a path is attached to, for the settings.
  String followerLabel(PathFollow? follow) {
    if (follow == null) return "Nothing";
    var target = _document.elementById(follow.elementId);
    if (target == null) return "Missing";
    var index = follow.playerIndex;
    if (target is TeamElement &&
        index != null &&
        index < target.players.length) {
      var spot = target.players[index];
      var who = spot.name.isNotEmpty ? spot.name : "#${spot.number}";
      return "$who (${target.name})";
    }
    return target.name;
  }

  /// valueAt is extra [channel] on this frame, or [orElse] if never keyed.
  double valueAt(CanvasElement element, String channel, double orElse) =>
      element.poseAt(_frame).values[channel] ?? orElse;

  /// hasValueKey is whether [channel] is pinned on this frame: its diamond.
  bool hasValueKey(CanvasElement element, String channel) =>
      element.track?.keyAt(_frame)?.values.containsKey(channel) ?? false;

  /// setValueKey pins one extra property at the current frame, seeded at the
  /// start so one press makes a movement (see ElementTrack.seededFor). A
  /// counter passes [seed] false: a seed marks the element as moving in
  /// space, and a count's first key holds for every frame before it anyway.
  void setValueKey(CanvasElement element, String channel, double value,
      {bool seed = true}) {
    var track = seed
        ? (element.track ?? ElementTrack.empty).seededFor(_frame)
        : (element.track ?? ElementTrack.empty);
    var at = track.at(_frame);
    replaceElement(element.withBase(
        track: track
            .withKey(at.copyWith(frame: _frame).withValue(channel, value))));
  }

  /// clearValueKey unpins [channel] here, and the key if that was all of it.
  void clearValueKey(CanvasElement element, String channel) {
    var track = element.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.withoutValue(channel);
    var next = without.isRest && without.frame != 0
        ? track.withoutFrame(_frame)
        : track.withKey(without);
    replaceElement(withTrackOrNone(element, next));
  }
}
