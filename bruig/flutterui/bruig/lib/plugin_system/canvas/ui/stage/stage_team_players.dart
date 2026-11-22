part of 'canvas_stage.dart';

// A team's players on the stage: the player of any team under a press, and
// a player dragged (_PlayerDrag), kept in the pitch's metres or as a
// fraction of the team's box, as a keyframe while animating. Part of
// CanvasStageState: its fields, lifecycle and build are in canvas_stage.dart.

extension StageTeamPlayers on CanvasStageState {
  TeamElement? _selectedTeam() {
    var selected = controller.selected;
    return selected is TeamElement ? selected : null;
  }

  /// _hitAnyPlayer is the topmost player of any team under [doc]. Team boxes
  /// are ignored: a player is placed as a fraction of one but not confined
  /// to it, and two teams on one pitch overlap.
  (TeamElement, int)? _hitAnyPlayer(Offset doc) {
    var hit = _hit;
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var element = document.elements[i];
      if (element is! TeamElement || element.locked || !element.visible) {
        continue;
      }
      var index = hit.playerOf(element, doc);
      if (index != null) return (element, index);
    }
    return null;
  }

  /// _applyPlayerMove drags player [index] of the selected team, taken
  /// [grab] from where he stands, to [doc]: stored as a fraction of the
  /// team's box so it stays put when the team moves or resizes.
  void _applyPlayerMove(int index, Offset grab, Offset doc) {
    var team = _selectedTeam();
    if (team == null || index < 0 || index >= team.players.length) {
      return;
    }
    var spot = team.players[index];
    var at = doc - grab;

    // On a pitch the pointer is carried onto the field and the player kept
    // in its metres, so the player goes wherever the pitch goes.
    var ground = teamGround(document, team, controller.frame);
    if (ground != null) {
      var field = ground.field(at);
      if (field == null) return;
      var animatingOnPitch = controller.document.isAnimated &&
          (controller.autoKeyframe || (spot.track?.isEmpty == false));
      if (animatingOnPitch) {
        var rest = teamFieldPoint(team, spot, ground.place);
        var ref = ground.place.reference;
        var track =
            (spot.track ?? ElementTrack.empty).seededFor(controller.frame);
        var pose = track.at(controller.frame);
        controller.replaceElement(
          team.withPlayer(
            index,
            spot.copyWith(
              track: track.withKey(pose.copyWith(
                frame: controller.frame,
                dx: (field.dx - rest.dx) * ref,
                dy: -(field.dy - rest.dy) * ref,
              )),
            ),
          ),
          transient: true,
        );
        return;
      }
      var (dx, dy) = spotFromField(team, field, ground.place);
      controller.replaceElement(
        team.withPlayer(index, spot.copyWith(dx: dx, dy: dy)),
        transient: true,
      );
      return;
    }

    // A player animates like anything else: with the document animated and
    // auto-keyframe on or the player already moving, the drag writes a
    // keyframe on their track rather than their lined-up place.
    var animating = controller.document.isAnimated &&
        (controller.autoKeyframe || (spot.track?.isEmpty == false));

    if (animating) {
      var rest = team.centreOf(spot);
      // Seeded at the start, so a drag at frame 12 is a run from where he
      // was, not a move for the whole document. See ElementTrack.seededFor.
      var track =
          (spot.track ?? ElementTrack.empty).seededFor(controller.frame);
      var pose = track.at(controller.frame);
      controller.replaceElement(
        team.withPlayer(
          index,
          spot.copyWith(
            track: track.withKey(pose.copyWith(
              frame: controller.frame,
              dx: at.dx - rest.dx,
              dy: at.dy - rest.dy,
            )),
          ),
        ),
        transient: true,
      );
      return;
    }

    var w = team.width == 0 ? 1.0 : team.width;
    var h = team.height == 0 ? 1.0 : team.height;
    controller.replaceElement(
      team.withPlayer(
        index,
        spot.copyWith(dx: (at.dx - team.x) / w, dy: (at.dy - team.y) / h),
      ),
      transient: true,
    );
  }
}

/// _PlayerDrag is a player of the selected team dragged. The team stays
/// selected: a player is a row of its list, not an element. One undo step.
class _PlayerDrag extends StageGesture {
  _PlayerDrag(this.index, this.grab);

  /// index is which player.
  final int index;

  /// grab is where the pointer took hold, from where he stands, so he does
  /// not jump to the pointer.
  final Offset grab;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyPlayerMove(index, grab, doc);

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}
