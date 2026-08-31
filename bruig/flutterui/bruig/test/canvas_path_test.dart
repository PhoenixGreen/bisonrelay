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
}
