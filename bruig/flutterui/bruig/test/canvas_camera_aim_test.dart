import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/camera_aim.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_camera_aim_test.dart is a Camera that frames part of a chart: one
// bar, the top few, whoever leads, followed through a race.

void main() {
  CanvasDocument docWith(CameraElement cam) {
    var size = const CanvasDocument().size.rect;
    return CanvasDocument(elements: [
      ChartElement(
          ElementBase(
              id: "c",
              x: 100,
              y: 100,
              width: size.width - 200,
              height: size.height - 200),
          type: ChartType.bar,
          data: ChartData.parse(
              "Club\tPts\nArsenal\t79\nLiverpool\t88\nChelsea\t66\nSpurs\t52")),
      cam,
    ]);
  }

  CameraElement camera(CanvasDocument d, {String aimAt = ""}) => CameraElement(
      ElementBase(
          id: "cam", width: d.size.rect.width, height: d.size.rect.height),
      aim: "c",
      aimAt: aimAt);

  test("aimed at one bar: in close, centred on it; saved", () {
    var plain = docWith(const CameraElement(ElementBase(id: "x")));
    var cam = camera(plain, aimAt: "item:Liverpool");
    var doc = docWith(cam);
    var bar = chartAimRect(
        doc.elementById("c") as ChartElement, "item:Liverpool", 0, doc)!;
    var (zoom, at) = cameraFraming(cam, 0, doc);
    expect(zoom, greaterThan(1.5));
    expect((at - bar.center).distance, lessThan(doc.size.rect.width * 0.3),
        reason: "on the bar, held inside the page");
    var back = CameraElement.fromJson(
        jsonDecode(jsonEncode(cam.props())) as Map<String, dynamic>, cam.base);
    expect((back.aim, back.aimAt, back.aimFill), ("c", "item:Liverpool", 0.6));
  });

  test("the leader is the largest; the top three take in three", () {
    var doc = docWith(const CameraElement(ElementBase(id: "x")));
    var chart = doc.elementById("c") as ChartElement;
    var leader = chartAimRect(chart, "leader", 0, doc)!;
    var liverpool = chartAimRect(chart, "item:Liverpool", 0, doc)!;
    expect(leader, liverpool);
    var three = chartAimRect(chart, "top:3", 0, doc)!;
    expect(three.width, greaterThan(leader.width * 2));
    expect(chartAimRect(chart, "item:Nobody", 0, doc), isNull);
  });

  test("keyed half way, half way between its own framing and the aim", () {
    var plain = docWith(const CameraElement(ElementBase(id: "x")));
    var cam = camera(plain, aimAt: "item:Spurs");
    var doc = docWith(cam);
    var (full, _) = cameraFraming(cam, 0, doc);
    var (z, _) = aimedFraming(cam, 1, doc.size.rect.center, 0, doc, 0.5);
    expect(z, closeTo((1 + full) / 2, 0.01));
  });
}
