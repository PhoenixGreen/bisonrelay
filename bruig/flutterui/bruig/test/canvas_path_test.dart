import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_path_test.dart is the bezier tool: the curve, its timing, and the
// thing that runs along it.
//
// The movement is baked into the follower's own keyframes rather than
// evaluated at paint time -- see CanvasController.applyPathFollow -- so most
// of what matters here is that the baking is right. Everything downstream (the
// stage, the GIF encoder, a published interactive canvas) then plays it
// without knowing a path was involved.

void main() {
  PathElement straight({int frames = 10}) => PathElement(
        const ElementBase(id: "p", x: 0, y: 0, width: 100, height: 100),
        nodes: [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 0, frame: frames),
        ],
      );

  group("the curve", () {
    test("a node with no handles gives a straight segment", () {
      // Clicking points rather than dragging them should draw a polyline, not
      // a curve that bulges towards the origin.
      var path = straight();
      for (var i = 0; i <= 10; i++) {
        expect(path.pointOnSegment(0, i / 10).dy, 0);
      }
      expect(path.pointOnSegment(0, 0.5), const Offset(50, 0));
    });

    test("the curve's parameter is not distance along it", () {
      // Why positionOnSegment exists. Even on a segment that is geometrically
      // straight, a cubic whose handles sit on its endpoints crawls away from
      // the start and rushes into the end: a quarter of the way along by
      // parameter is a sixth of the way along by distance.
      var path = straight();
      expect(path.pointOnSegment(0, 0.25).dx, closeTo(15.6, 0.1));
      expect(path.positionOnSegment(0, 0.25).dx, closeTo(25, 0.5));
      expect(path.positionOnSegment(0, 0.75).dx, closeTo(75, 0.5));
    });

    test("handles bend the segment", () {
      var path = PathElement(
        const ElementBase(id: "p", x: 0, y: 0, width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, outDx: 0, outDy: 1, frame: 0),
          PathNode(x: 1, y: 0, inDx: 0, inDy: 1, frame: 10),
        ],
      );
      expect(path.pointOnSegment(0, 0.5).dy, greaterThan(50),
          reason: "the curve sags towards the handles");
    });

    test("points are fractions of the box, so the curve travels with it", () {
      var path = straight();
      var moved = path.withBase(x: 400, y: 200) as PathElement;
      expect(moved.pointOf(moved.nodes.first), const Offset(400, 200));
      expect(moved.pointOf(moved.nodes.last), const Offset(500, 200));

      var wider = path.withBase(width: 200) as PathElement;
      expect(wider.pointOf(wider.nodes.last).dx, 200,
          reason: "resizing the box stretches the curve with it");
    });

    test("a round trip keeps the nodes, the handles and the timing", () {
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0.1, y: 0.2, outDx: 0.3, outDy: -0.1, frame: 2),
          PathNode(x: 0.9, y: 0.4, inDx: -0.2, inDy: 0.15, frame: 18),
        ],
        follow: PathFollow(elementId: "t1", playerIndex: 6),
        guide: true,
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [path]).encode())!.elements.single
          as PathElement;

      expect(back.nodes.length, 2);
      expect(back.nodes.first.outDx, 0.3);
      expect(back.nodes.last.frame, 18);
      expect(back.follow!.elementId, "t1");
      expect(back.follow!.playerIndex, 6);
      expect(back.guide, isTrue);
    });
  });

  group("timing", () {
    test("a node cannot be retimed past its neighbours", () {
      // Sorting instead would reorder the curve: the follower would visit the
      // points in a different order from the one they are drawn in, and the
      // line on screen would stop describing the movement.
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 0.5, y: 0, frame: 10),
          PathNode(x: 1, y: 0, frame: 20),
        ],
      );
      var pulled = path.withNode(1, path.nodes[1].copyWith(frame: 99));
      expect(pulled.nodes[1].frame, 20, reason: "clamped to its neighbour");

      var pushed = path.withNode(1, path.nodes[1].copyWith(frame: -5));
      expect(pushed.nodes[1].frame, 0);
      expect(pushed.nodes.map((n) => n.x).toList(), [0, 0.5, 1],
          reason: "and the curve's own order is untouched");
    });

    test("spreadFrames spaces the points evenly", () {
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 0.5, y: 0, frame: 1),
          PathNode(x: 1, y: 0, frame: 2),
        ],
      ).spreadFrames(0, 20);
      expect(path.nodes.map((n) => n.frame).toList(), [0, 10, 20]);
    });

    test("a follower holds at each end rather than running off", () {
      var path = straight(frames: 10);
      expect(path.positionAtFrame(-5), const Offset(0, 0));
      expect(path.positionAtFrame(50), const Offset(100, 0));
    });

    test("position is measured by distance, not by the curve's parameter", () {
      // A cubic's parameter runs fast through the straight part and slow round
      // the bend, so a player crossing a curved run at a constant parameter
      // appears to slow into the turn and speed out of it.
      var path = PathElement(
        const ElementBase(id: "p", x: 0, y: 0, width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, outDx: 0.9, outDy: 0, frame: 0),
          PathNode(x: 1, y: 1, inDx: 0, inDy: -0.9, frame: 10),
        ],
      );

      // Equal time steps should cover roughly equal distances.
      var steps = [
        for (var f = 0; f <= 10; f++) path.positionAtFrame(f)!,
      ];
      var lengths = [
        for (var i = 1; i < steps.length; i++) (steps[i] - steps[i - 1]).distance,
      ];
      var shortest = lengths.reduce((a, b) => a < b ? a : b);
      var longest = lengths.reduce((a, b) => a > b ? a : b);
      expect(longest / shortest, lessThan(1.6),
          reason: "constant speed along the curve, within reason");
    });
  });

  group("following", () {
    test("an element gets keyframes for every frame of the run", () {
      var shape = ShapeElement(
        const ElementBase(id: "s", x: 0, y: 0, width: 20, height: 20),
      );
      var path = straight(frames: 10)
          .copyWith(follow: const PathFollow(elementId: "s"));
      var controller = CanvasController(const CanvasDocument(frames: 24)
          .addElement(shape)
          .addElement(path));
      addTearDown(controller.dispose);

      controller.applyPathFollow(
          controller.document.elements.whereType<PathElement>().single);

      var track = controller.document.elementById("s")!.track!;
      expect(track.keys.length, 11, reason: "frames 0 to 10 inclusive");
      // Measured from the element's centre, so the curve runs through the
      // middle of the thing rather than through its shoulder.
      expect(track.at(0).dx, -10);
      expect(track.at(10).dx, 90);
      expect(track.at(5).dx, closeTo(40, 1));
    });

    test("a player of a team can follow one", () {
      var team = TeamElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var path = straight(frames: 8)
          .copyWith(follow: const PathFollow(elementId: "t", playerIndex: 9));
      var controller = CanvasController(const CanvasDocument(frames: 24)
          .addElement(team)
          .addElement(path));
      addTearDown(controller.dispose);

      controller.applyPathFollow(
          controller.document.elements.whereType<PathElement>().single);

      var after = controller.document.elements.whereType<TeamElement>().single;
      expect(after.players[9].track, isNotNull);
      expect(after.players[8].track, isNull, reason: "nobody else moved");
      expect(after.centreAt(after.players[9], 0).dx, closeTo(0, 0.001));
      expect(after.centreAt(after.players[9], 8).dx, closeTo(100, 0.001));
    });

    test("unlinking takes the baked keyframes back off", () {
      // Leaving them would strand the element on a route nothing is attached
      // to, which is worse than either state.
      var shape = ShapeElement(const ElementBase(id: "s", width: 20, height: 20));
      var path = straight(frames: 6)
          .copyWith(follow: const PathFollow(elementId: "s"));
      var controller = CanvasController(const CanvasDocument(frames: 24)
          .addElement(shape)
          .addElement(path));
      addTearDown(controller.dispose);

      var live = controller.document.elements.whereType<PathElement>().single;
      controller.applyPathFollow(live);
      expect(controller.document.elementById("s")!.track, isNotNull);

      controller.clearPathFollow(live);
      expect(controller.document.elementById("s")!.track, isNull);
    });

    test("a path with one node or no follower bakes nothing", () {
      var shape = ShapeElement(const ElementBase(id: "s"));
      var controller =
          CanvasController(const CanvasDocument(frames: 24).addElement(shape));
      addTearDown(controller.dispose);

      controller.applyPathFollow(straight());
      expect(controller.document.elementById("s")!.track, isNull);

      controller.applyPathFollow(PathElement(
        const ElementBase(id: "p"),
        nodes: const [PathNode(x: 0, y: 0, frame: 0)],
        follow: const PathFollow(elementId: "s"),
      ));
      expect(controller.document.elementById("s")!.track, isNull);
    });

    test("re-baking replaces the route rather than adding to it", () {
      var shape = ShapeElement(const ElementBase(id: "s", width: 20, height: 20));
      var controller = CanvasController(
          const CanvasDocument(frames: 24).addElement(shape));
      addTearDown(controller.dispose);

      controller.applyPathFollow(
          straight(frames: 10).copyWith(follow: const PathFollow(elementId: "s")));
      controller.applyPathFollow(
          straight(frames: 4).copyWith(follow: const PathFollow(elementId: "s")));

      expect(controller.document.elementById("s")!.track!.keys.length, 5,
          reason: "the shorter run, not the two runs together");
    });
  });

  group("adding points", () {
    test("inserting keeps the curve exactly where it was", () {
      // By de Casteljau subdivision rather than by dropping a point on the
      // line and guessing handles: adding somewhere to grab a run must not
      // move the run.
      var path = PathElement(
        const ElementBase(id: "p", x: 0, y: 0, width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, outDx: 0.5, outDy: 0.4, frame: 0),
          PathNode(x: 1, y: 1, inDx: -0.3, inDy: -0.6, frame: 20),
        ],
      );
      var before = [
        for (var i = 0; i <= 20; i++) path.positionAtFrame(i)!,
      ];

      var after = path.insertAfter(0);
      expect(after.nodes.length, 3);
      for (var i = 0; i <= 20; i++) {
        var was = before[i];
        var now = after.positionAtFrame(i)!;
        expect((now - was).distance, lessThan(1.0), reason: "frame $i moved");
      }
    });

    test("the inserted point is timed between its neighbours", () {
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 4),
          PathNode(x: 1, y: 0, frame: 16),
        ],
      ).insertAfter(0);
      expect(path.nodes[1].frame, 10);
    });

    test("appending carries on in the direction the path was going", () {
      // A new point dropped in the middle of the box has to be dragged into
      // place before it means anything.
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0.1, y: 0.5, frame: 0),
          PathNode(x: 0.4, y: 0.5, frame: 6),
        ],
      ).appendNode();

      expect(path.nodes.length, 3);
      expect(path.nodes.last.x, closeTo(0.7, 0.0001));
      expect(path.nodes.last.frame, 12, reason: "the same gap again");
    });

    test("appending respects the document's length", () {
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 0.5, y: 0, frame: 20),
        ],
      ).appendNode(maxFrame: 23);
      expect(path.nodes.last.frame, 23);
    });

    test("insertAtFrame splits whichever segment spans the frame", () {
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 0.5, y: 0, frame: 10),
          PathNode(x: 1, y: 0, frame: 20),
        ],
      );
      var made = path.insertAtFrame(15);
      expect(made.nodes.length, 4);
      expect(made.nodes[2].frame, 15);
      expect(made.nodes.map((n) => n.frame).toList(), [0, 10, 15, 20],
          reason: "and the order is still increasing");

      // A frame already occupied, or outside the run, adds nothing.
      expect(path.insertAtFrame(10).nodes.length, 3);
      expect(path.insertAtFrame(99).nodes.length, 3);
    });

    test("removing keeps at least two points", () {
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 0, frame: 10),
        ],
      );
      expect(path.withoutNode(0).nodes.length, 2,
          reason: "one point is not a path");
    });
  });

  group("a path owns its follower's timing", () {
    (CanvasController, TeamElement, PathElement) followed() {
      var team = TeamElement(
        const ElementBase(id: "t", name: "Home", x: 0, y: 0, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var path = PathElement(
        const ElementBase(id: "p", name: "Run", x: 0, y: 0, width: 400, height: 300),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 1, frame: 12),
        ],
        follow: const PathFollow(elementId: "t", playerIndex: 0),
      );
      var controller = CanvasController(
          const CanvasDocument(frames: 30).addElement(team).addElement(path));
      controller.applyPathFollow(path);
      return (controller, team, path);
    }

    test("the controller can say which path drives a follower", () {
      var (controller, _, _) = followed();
      addTearDown(controller.dispose);

      expect(controller.pathDriving("t", playerIndex: 0)?.id, "p");
      expect(controller.pathDriving("t", playerIndex: 1), isNull,
          reason: "another player of the same team is not driven");
      expect(controller.pathDriving("t"), isNull,
          reason: "nor is the team itself");
    });

    test("dragging a driven element moves it rather than posing it", () {
      // Its poses belong to the route, and one written by a drag would be
      // overwritten the next time a point moved -- so the drag has to mean
      // something that survives.
      var shape = ShapeElement(
          const ElementBase(id: "s", x: 0, y: 0, width: 20, height: 20));
      var path = PathElement(
        const ElementBase(id: "p", x: 0, y: 0, width: 200, height: 200),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 0, frame: 10),
        ],
        follow: const PathFollow(elementId: "s"),
      );
      var controller = CanvasController(
          const CanvasDocument(frames: 30).addElement(shape).addElement(path));
      addTearDown(controller.dispose);
      controller.applyPathFollow(path);

      var driven = controller.document.elementById("s")!;
      expect(driven.track, isNotNull, reason: "it does have keyframes");
      expect(controller.posesRatherThanMoves(driven), isFalse,
          reason: "but they are not its own to edit");
    });

    test("unlinking hands the timing back", () {
      var (controller, _, path) = followed();
      addTearDown(controller.dispose);

      controller.clearPathFollow(path);
      controller.replaceElement(path.copyWith(clearFollow: true));
      expect(controller.pathDriving("t", playerIndex: 0), isNull);
    });
  });

  group("giving a new point room", () {
    test("appending at the end of the document still gets its own frame", () {
      // The reported problem: the run already finishes on the last frame, so
      // the new point was clamped on top of the old end and the button looked
      // as though it had done nothing.
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 0, frame: 23),
        ],
      ).appendNode(maxFrame: 23);

      expect(path.nodes.length, 3);
      var frames = path.nodes.map((n) => n.frame).toList();
      expect(frames.toSet().length, 3, reason: "three distinct frames");
      expect(frames, orderedEquals([...frames]..sort()));
      expect(frames.last, lessThanOrEqualTo(23));
    });

    test("inserting between two adjacent frames makes room", () {
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 4),
          PathNode(x: 1, y: 0, frame: 5),
        ],
      ).insertAfter(0, maxFrame: 30);

      var frames = path.nodes.map((n) => n.frame).toList();
      expect(frames.length, 3);
      expect(frames.toSet().length, 3);
    });

    test("a run with room keeps the timing it was given", () {
      // The repair only runs when there is a collision; ordinary appending
      // must not re-space a run somebody has tuned.
      var path = PathElement(
        const ElementBase(id: "p", width: 100, height: 100),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 0.3, y: 0, frame: 3),
          PathNode(x: 1, y: 0, frame: 20),
        ],
      ).appendNode(maxFrame: 60);

      expect(path.nodes[0].frame, 0);
      expect(path.nodes[1].frame, 3, reason: "untouched");
      expect(path.nodes[2].frame, 20);
      expect(path.nodes[3].frame, greaterThan(20));
    });
  });
}
