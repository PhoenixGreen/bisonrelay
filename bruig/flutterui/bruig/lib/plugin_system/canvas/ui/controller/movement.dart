part of '../canvas_controller.dart';

// Elements moved in time: a move made into motion where the canvas
// CanvasController.animates, the camera's shifts and zoom, following a path,
// and the value keys an element's settings take. Part of CanvasController: its
// fields and lifecycle are in canvas_controller.dart.

extension CanvasMovement on CanvasController {
  /// moveOrigin is the top-left [movedTo] leaves [element] as it is: where
  /// it stands on a 3D stage on this frame; its rest moved by its keys'
  /// move here where a drag poses it; else its rest. Not where it is drawn:
  /// a clip, a device, a loop or a size about its anchor move what is drawn
  /// as well, and handed back to [movedTo] they would be written in and so
  /// added twice. A drag hands [movedTo] this, taken at its start, plus how
  /// far it has gone, so what is drawn goes exactly as far as the pointer.
  Offset moveOrigin(CanvasElement element) {
    if (element.base.spot != null) {
      if (stagedIn(_document, element, _frame) case var at?) {
        return at.box.topLeft;
      }
    }
    var rest = Offset(element.x, element.y);
    if (!posesRatherThanMoves(element)) return rest;
    var pose = element.poseAt(_frame);
    return rest + Offset(pose.dx, pose.dy);
  }

  /// movedTo is the stage's drag: where [element]'s top-left should now be,
  /// in [moveOrigin]'s terms. Absolute rather than a delta, since deltas
  /// drift and compound on a pose.
  /// [free] is a drag Alt frees from snapping, which the stage tells it: it
  /// is put off a 3D stage's steps however its snap is set.
  CanvasElement movedTo(CanvasElement element, Offset topLeft,
      {bool free = false}) {
    // An element on a stage moves across its floor, or along its back wall.
    if (element.base.spot != null) {
      var at = stagedIn(_document, element, _frame);
      if (at != null) {
        // Where it stands on this frame; keyed, the move is a key here.
        var spot = at.spot;
        var by = topLeft - at.box.topLeft;
        var view = at.view;
        // Snapping lands on the 3D steps: a stage has no lines to snap to.
        var step = _document.guides.stageSnap && !free
            ? _document.guides.stageStep
            : 0.0;
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
    var dx = topLeft.dx - element.x, dy = topLeft.dy - element.y;
    // Location keys picked on the Keys strip: the keyed path moved whole,
    // by however far it is from where it is drawn now.
    if (pickedLocationFrames(element.id) case var frames?) {
      var pose = track.at(_frame);
      return element.withBase(
          track: track.shiftLocations(frames, dx - pose.dx, dy - pose.dy));
    }
    // Its location keyed here, and nothing else: a scale or rotation keyed
    // elsewhere keeps its own timing.
    return element.withBase(
      track: track.posed(_frame, const [KeyProp.location],
          (pose) => pose.copyWith(dx: dx, dy: dy)),
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
  /// per frame of its run (PathElement.endFrame), sampled by arc length.
  /// Baked rather than live, so the renderer, the GIF encoder and a
  /// published canvas play it like any track and cannot disagree.
  void applyPathFollow(PathElement path) {
    var follow = path.follow;
    if (follow == null || path.nodes.length < 2) return;

    var target = _document.elementById(follow.elementId);
    if (target == null) return;

    var from = path.firstFrame;
    var to = path.endFrameIn(_document.frames - 1);
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
      replaceElement(target.withPlayer(index,
          spot.copyWith(track: _bake(path, spot.track, rest, from, to))));
      return;
    }

    // An element is placed by its top-left, so the route, which describes
    // where the thing is, is measured from its centre and shifted back.
    replaceElement(target.withBase(
        track: _bake(path, target.track, target.center, from, to)));
  }

  /// _bakeOnPitch is [_bake] for a player on a pitch, in the units a run on
  /// a pitch is kept in (see playerPlace).
  ElementTrack _bakeOnPitch(PathElement path, TeamGround ground,
      TeamElement team, PlayerSpot spot, int from, int to) {
    var rest = teamFieldPoint(team, spot, ground.place);
    var ref = ground.place.reference;
    return followTrack(spot.track, (f) {
      var at = path.positionAtFrame(f);
      var field = at == null ? null : ground.field(at);
      if (field == null) return null;
      return Offset((field.dx - rest.dx) * ref, -(field.dy - rest.dy) * ref);
    }, from, to);
  }

  /// _bake lays a path into [track], the follower's keys, as its place
  /// relative to [rest] on each frame (see followTrack).
  ElementTrack _bake(PathElement path, ElementTrack? track, Offset rest,
          int from, int to) =>
      followTrack(track, (f) {
        var at = path.positionAtFrame(f);
        return at == null ? null : at - rest;
      }, from, to);

  /// clearPathFollow takes the baked places off, or the follower is
  /// stranded, and leaves what else it has keyed (see ownTrack).
  void clearPathFollow(PathElement path) {
    var follow = path.follow;
    if (follow == null) return;
    var target = _document.elementById(follow.elementId);
    if (target == null) return;

    var index = follow.playerIndex;
    if (target is TeamElement && index != null) {
      if (index < 0 || index >= target.players.length) return;
      var own = ownTrack(target.players[index].track);
      replaceElement(target.withPlayer(
          index,
          own.isEmpty
              ? target.players[index].copyWith(clearTrack: true)
              : target.players[index].copyWith(track: own)));
      return;
    }
    replaceElement(withTrackOrNone(target, ownTrack(target.track)));
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
    replaceElement(element.withBase(
        track: (element.track ?? ElementTrack.empty)
            .withValueKey(channel, value, _frame, seed: seed)));
  }

  /// clearValueKey unpins [channel] here, and the key if that was all of it.
  void clearValueKey(CanvasElement element, String channel) {
    var track = element.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.withoutValue(channel);
    var next = (without.isRest || without.holdsNothing) && without.frame != 0
        ? track.withoutFrame(_frame)
        : track.withKey(without);
    replaceElement(withTrackOrNone(element, next));
  }
}
