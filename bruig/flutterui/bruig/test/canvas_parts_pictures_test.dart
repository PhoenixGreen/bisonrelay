import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/render/layout_painter.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_hit_test.dart';

import 'support/kept_pictures.dart';

// canvas_parts_pictures_test.dart keeps what the renderer draws of a Layout,
// a Counter, a Button and a Metronome, and what a page looks like through a
// Camera, to the byte, in each of nearly two hundred states: every Layout
// preset, mode and cell shape, cuts several deep with tilts and gutters of
// their own, a Grid with spans, gutters, a margin and their colour, each
// part of a cell's box, and a layout turned, slanted and moved with a shape
// docked in a cell and one docked out; a counter in each of its modes
// (keyed, a run, a clock, a game's count, a page number on a left and a
// right page) at three frames, with each separator, decimals, words and
// their gap, loose words, a box, fitted or not, each set of buttons, and its
// words in each case; a button's label and box, turned, slanted and under
// the pointer; a metronome at every number of beats it can hold and several
// tempos; and a page seen through a Camera's frame, zoom, roll, blur,
// vignette, parallax and motion blur. Beside each picture it keeps the
// numbers the stage and the docks ask of the same elements: where each is
// drawn (visualBoundsOf) and what the stage's press counts as on it; for a
// Layout each cell's outline as the painter lays it on the page and as the
// dock clip and Panel mode lay it, its cut and Grid lines, and each docked
// element's clip; for a counter the value shown and where its buttons and
// loose words are drawn and pressed; for a metronome where its parts are;
// for a Camera its framing and lens.
//
// Some of those numbers are worked out by rules private to the painter or
// the stage (a counter's loose words, the room its number is fitted to).
// Those are written here as the code has them, marked where they are, so a
// change to one of the rules shows only through the picture; the rest come
// from the app's own functions.
//
// To use it, set PARTS_PICTURES to a folder and run this file on the code
// as it is: each state's picture (<state>.rgba and .png) and numbers
// (<state>.txt) are written there. Run it again to see that every one is
// stable from run to run. Then make the change and run it after each step:
// a state whose picture differs fails, saying how many pixels changed and
// where, and leaves the new picture beside the kept one as <state>.new.png;
// numbers that differ fail with both. Without PARTS_PICTURES each state is
// still drawn and measured, and nothing is kept, so the test is harmless in
// the whole suite.
//
// With PARTS_PICTURES set, the app's own fonts are registered first: the
// test font draws every letter and figure as the same square, so 5 beats
// would look like 4, and words upper-cased would measure as they were
// typed. Registered fonts stay for the rest of the process, so they are
// only registered when the file is run by name to keep its pictures, never
// in a shared bundle.
//
// Every preset, mode, cell shape, separator, source, button and case is
// taken from its enum's values, so a new one gets its states without anyone
// remembering to add them.

const _blue = Color(0xFF3D7EFF);
const _orange = Color(0xFFFFA726);
const _red = Color(0xFFE53935);
const _green = Color(0xFF66BB6A);
const _ink = Color(0xFF111111);
const _white = Color(0xFFFFFFFF);
const _paper = Color(0xFFEEEEEE);

/// _State is one thing kept: a page drawn on [frame], with the button
/// [hovered] under the pointer where one is.
typedef _State = ({
  String name,
  CanvasDocument doc,
  int frame,
  String? hovered,
});

_State _state(String name, CanvasDocument doc,
        {int frame = 0, String? hovered}) =>
    (name: name, doc: doc, frame: frame, hovered: hovered);

/// _page is a page [w] by [h] holding [elements].
CanvasDocument _page(int w, int h, List<CanvasElement> elements) =>
    CanvasDocument(
        size:
            CanvasSize(width: w, ratio: CanvasRatio.custom, customRatio: w / h),
        elements: elements,
        frames: 48);

ElementBase _at(Rect r, {String id = "e"}) =>
    ElementBase(id: id, x: r.left, y: r.top, width: r.width, height: r.height);

String _short(double v) =>
    v == v.roundToDouble() ? "${v.round()}" : "$v".replaceAll(".", "_");

/// _keyed is [base] keyed from rest on frame 0 to [to] on frame 24.
ElementBase _keyed(ElementBase base, Keyframe to) => base.copyWith(
    track: ElementTrack([const Keyframe(frame: 0), to.copyWith(frame: 24)]));

/// _clipped is [base] carried 60 across and 30 down in two seconds by a
/// clip.
ElementBase _clipped(ElementBase base) => base.copyWith(
        motion: const ElementMotion(clips: [
      MotionClip(id: "go", kind: MotionKind.action, length: 2, keys: {
        MotionProp.x: [
          MotionKey(0, MotionNumber(0)),
          MotionKey(2, MotionNumber(60))
        ],
        MotionProp.y: [
          MotionKey(0, MotionNumber(0)),
          MotionKey(2, MotionNumber(30))
        ],
      }),
    ], placed: [
      ClipPlacement(id: "p", clip: "go", length: 2)
    ]));

// ---- Layouts, on a page 240 by 300 ----------------------------------------

const _layoutW = 240, _layoutH = 300;
const _layoutBox = Rect.fromLTWH(20, 20, 200, 260);

/// _layoutPage is a grey page, so a white gutter shows, holding [elements].
CanvasDocument _layoutPage(List<CanvasElement> elements) =>
    _page(_layoutW, _layoutH, [
      ShapeElement(_at(Rect.fromLTWH(0, 0, 240, 300), id: "page"),
          fill: const Color(0xFF8A8F99)),
      ...elements,
    ]);

/// _stable is [e] with its cells' ids made c0, c1... in reading order, so
/// a preset's fresh ids do not make each run's numbers its own and a shape
/// can be docked by name.
LayoutElement _stable(LayoutElement e) {
  var ids = <String, String>{};
  for (var (i, c) in e.cells.indexed) {
    ids[c.id] = "c$i";
  }
  LayoutNode walk(LayoutNode n) => n.isLeaf
      ? LayoutNode.leaf(ids[n.cell] ?? n.cell)
      : LayoutNode.cut(
          vertical: n.vertical,
          at: n.at,
          tilt: n.tilt,
          gutter: n.gutter,
          a: walk(n.a!),
          b: walk(n.b!));
  return e.copyWith(
      root: walk(e.root),
      cells: [for (var c in e.cells) c.copyWith(id: ids[c.id])]);
}

LayoutNode _cut(bool vertical, double at, LayoutNode a, LayoutNode b,
        {double tilt = 0, double? gutter}) =>
    LayoutNode.cut(
        vertical: vertical, at: at, tilt: tilt, gutter: gutter, a: a, b: b);

LayoutNode _leaf(String id) => LayoutNode.leaf(id);

/// _panels is a Panels layout of [root], its cells named for their ids.
LayoutElement _panels(LayoutNode root, {String id = "L"}) =>
    LayoutElement(_at(_layoutBox, id: id),
        root: root,
        cells: [
          for (var c in root.cells) LayoutCell(id: c, name: "Panel $c"),
        ],
        gutter: 14,
        rowGutter: 18,
        gutterColor: _white,
        cellStyle: const BoxSpec(
            fill: Color(0xFFDDE6F0), borderWidth: 3, borderColor: _ink));

/// _twoTiers is three panels: one across the top, two below.
LayoutElement _twoTiers() => _panels(
    _cut(false, 0.45, _leaf("c0"), _cut(true, 0.5, _leaf("c1"), _leaf("c2"))));

/// _deep is a Panels layout cut four deep, with tilted cuts and cuts with
/// gutters of their own.
LayoutElement _deep() => _panels(_cut(
    false,
    0.38,
    _cut(true, 0.3, _leaf("c0"),
        _cut(false, 0.5, _leaf("c1"), _leaf("c2"), tilt: -8), tilt: 10),
    _cut(
        true,
        0.6,
        _cut(false, 0.45, _leaf("c3"),
            _cut(true, 0.5, _leaf("c4"), _leaf("c5"), gutter: 4)),
        _leaf("c6"),
        tilt: -6,
        gutter: 30),
    tilt: 4));

LayoutElement _grid() => LayoutElement(_at(_layoutBox, id: "L"),
    mode: LayoutMode.grid,
    columns: const [1, 2, 1],
    rows: const [2, 1, 1],
    cells: const [
      LayoutCell(id: "c0", col: 0, row: 0, colSpan: 2),
      LayoutCell(id: "c1", col: 2, row: 0, rowSpan: 2),
      LayoutCell(id: "c2", col: 0, row: 1, rowSpan: 2),
      LayoutCell(id: "c3", col: 1, row: 1),
      LayoutCell(id: "c4", col: 1, row: 2, colSpan: 2),
    ],
    gutter: 10,
    rowGutter: 16,
    cellStyle: const BoxSpec(
        fill: Color(0xFFF5E6C8), borderWidth: 2, borderColor: _ink));

LayoutElement _free(List<LayoutCell> cells) =>
    LayoutElement(_at(_layoutBox, id: "L"),
        mode: LayoutMode.free,
        cells: cells,
        cellStyle: const BoxSpec(
            fill: Color(0xFFC8E6C9), borderWidth: 3, borderColor: _ink));

/// _docked is a shape of [colour] docked in [cell] of layout L, set over
/// that cell and well past it, so the clip shows; [out] breaks out.
ShapeElement _docked(String id, String cell, Rect box, Color colour,
        {bool out = false}) =>
    ShapeElement(_at(box, id: id).copyWith(dock: "L:$cell", dockOut: out),
        fill: colour);

List<_State> _layoutStates() {
  var out = <_State>[];
  for (var p in LayoutPreset.values) {
    out.add(_state("layout-preset-${p.name}",
        _layoutPage([_stable(layoutFrom(_at(_layoutBox, id: "L"), p))])));
  }

  // Each mode as it starts.
  for (var mode in LayoutMode.values) {
    var e = switch (mode) {
      LayoutMode.panels => _panels(_cut(true, 0.5, _leaf("c0"), _leaf("c1"))),
      LayoutMode.grid => LayoutElement(_at(_layoutBox, id: "L"),
            mode: LayoutMode.grid,
            cells: const [
              LayoutCell(id: "c0"),
              LayoutCell(id: "c1", col: 1),
              LayoutCell(id: "c2", row: 1),
              LayoutCell(id: "c3", col: 1, row: 1),
            ]),
      LayoutMode.free => _free(const [
          LayoutCell(id: "c0"),
          LayoutCell(id: "c1", x: 0.5, y: 0.5, width: 0.4, height: 0.4),
        ]),
    };
    out.add(_state("layout-mode-${mode.name}", _layoutPage([e])));
  }

  out.add(_state("layout-panels-deep", _layoutPage([_deep()])));
  out.add(_state("layout-grid-spans", _layoutPage([_grid()])));

  // Every free cell's shape, upright and turned.
  for (var shape in LayoutCellShape.values) {
    for (var turn in [0.0, 25.0]) {
      out.add(_state(
          "layout-free-${shape.name}-turn-${_short(turn)}",
          _layoutPage([
            _free([
              LayoutCell(
                  id: "c0",
                  x: 0.1,
                  y: 0.15,
                  width: 0.8,
                  height: 0.45,
                  turn: turn,
                  shape: shape),
              LayoutCell(
                  id: "c1",
                  x: 0.3,
                  y: 0.65,
                  width: 0.4,
                  height: 0.3,
                  turn: -turn,
                  shape: shape),
            ])
          ])));
    }
  }
  out.add(_state(
      "layout-free-rounded-corners",
      _layoutPage([
        _free(const [
          LayoutCell(
              id: "c0", x: 0.1, y: 0.1, width: 0.8, height: 0.35, turn: 8),
          LayoutCell(
              id: "c1",
              x: 0.1,
              y: 0.55,
              width: 0.8,
              height: 0.35,
              shape: LayoutCellShape.hexagon),
        ]).copyWith(
            cellStyle: const BoxSpec(
                fill: Color(0xFFC8E6C9),
                borderWidth: 3,
                borderColor: _ink,
                borderRadius: 18))
      ])));

  // What is round the cells.
  var tiers = _twoTiers();
  for (var (name, e) in [
    ("layout-gutters-wide", tiers.copyWith(gutter: 40, rowGutter: 6)),
    ("layout-gutters-none", tiers.copyWith(gutter: 0, rowGutter: 0)),
    ("layout-margin", tiers.copyWith(margin: 24)),
    (
      "layout-gutter-colour",
      tiers.copyWith(margin: 12, gutterColor: _red),
    ),
    (
      "layout-gutter-clear",
      tiers.copyWith(gutterColor: const Color(0x00000000)),
    ),
    (
      "layout-grid-gutters-margin-colour",
      _grid()
          .copyWith(gutter: 30, rowGutter: 4, margin: 16, gutterColor: _orange),
    ),
  ]) {
    out.add(_state(name, _layoutPage([e])));
  }

  // A cell's box: each part on the layout's cell style, and one cell
  // styled on its own.
  const plain = BoxSpec(fill: Color(0xFFDDE6F0), padding: 0);
  for (var (part, style) in [
    ("border", plain.copyWith(borderWidth: 6, borderColor: _ink)),
    (
      "radius",
      plain.copyWith(borderRadius: 24, borderWidth: 3, borderColor: _ink)
    ),
    ("fill", const BoxSpec(fill: _blue, padding: 0)),
    (
      "fade",
      plain.copyWith(fill: _blue, fillFade: const GradientSpec(to: _green)),
    ),
    (
      "border-fade",
      plain.copyWith(
          borderWidth: 6,
          borderColor: _orange,
          borderFade: const GradientSpec(to: _blue, angle: 90)),
    ),
    (
      "painted",
      plain.copyWith(
          painted: const TextFill(
              kind: TextFillKind.pattern,
              pattern: ProceduralSpec(
                  style: ProceduralStyle.lineGrid,
                  background: Color(0xFF1E4A7A),
                  foreground: Color(0xFFFFFFFF)))),
    ),
    // A box's per-side borders, per-corner radii, padding and inset, which
    // a cell's box offers.
    (
      "borders-per-side",
      plain.copyWith(borderColor: _ink, bwL: 2, bwT: 12, bwR: 0, bwB: 6),
    ),
    (
      "corners-per-corner",
      plain.copyWith(
          borderWidth: 3, borderColor: _ink, radTL: 0, radTR: 30, radBL: 12),
    ),
    (
      "padding",
      plain.copyWith(
          borderWidth: 3,
          borderColor: _ink,
          padding: 20,
          padL: 4,
          padT: 30,
          padR: 10,
          padB: 0),
    ),
    (
      "inset",
      plain.copyWith(borderWidth: 3, borderColor: _ink, borderInset: 10),
    ),
  ]) {
    out.add(_state(
        "layout-cell-$part", _layoutPage([tiers.copyWith(cellStyle: style)])));
  }
  out.add(_state(
      "layout-cell-own-style",
      _layoutPage([
        tiers.withCell(const LayoutCell(
            id: "c1",
            name: "Panel c1",
            style: BoxSpec(
                fill: _orange,
                borderWidth: 5,
                borderColor: _red,
                borderRadius: 14))),
      ])));

  // Turned, slanted and moved, with a shape docked in a cell and one docked
  // out of another. The docked shapes reach well past their cells.
  List<CanvasElement> dockedIn(LayoutElement l) => [
        l,
        _docked("in", "c1", const Rect.fromLTWH(40, 120, 150, 120), _red),
        _docked("out", "c2", const Rect.fromLTWH(110, 200, 120, 90), _green,
            out: true),
      ];
  var base = tiers.base;
  for (var (how, b, frame) in [
    ("resting", base, 0),
    ("turned", base.copyWith(rotation: 20), 0),
    ("slanted", base.copyWith(skewX: 18), 0),
    ("slanted-down", base.copyWith(skewY: 12), 0),
    (
      "moved-by-keys",
      _keyed(base, const Keyframe(frame: 0, dx: 40, dy: -30, rotate: 16)),
      12
    ),
    (
      "sized-by-keys",
      _keyed(base, const Keyframe(frame: 0, scale: 0.6)),
      12,
    ),
    ("moved-by-clip", _clipped(base), 12),
  ]) {
    out.add(_state("layout-docked-$how",
        _layoutPage(dockedIn(tiers.rebase(b) as LayoutElement)),
        frame: frame));
  }
  // A Free cell, turned, with a shape docked in it, the layout turned too.
  out.add(_state(
      "layout-docked-free-turned",
      _layoutPage([
        _free(const [
          LayoutCell(
              id: "c0",
              x: 0.1,
              y: 0.2,
              width: 0.8,
              height: 0.5,
              turn: 15,
              shape: LayoutCellShape.diamond),
        ]).rebase(base.copyWith(rotation: -12)),
        _docked("in", "c0", const Rect.fromLTWH(30, 60, 180, 180), _red),
      ])));
  return out;
}

// ---- Counters, on a page 280 by 160 ---------------------------------------

const _counterW = 280, _counterH = 160;
const _counterBox = Rect.fromLTWH(30, 20, 220, 120);

CounterElement _counter({
  String id = "n",
  double from = 0,
  double to = 100,
  bool keyed = false,
  CounterSource source = CounterSource.run,
}) =>
    CounterElement(_at(_counterBox, id: id),
        from: from,
        to: to,
        keyed: keyed,
        source: source,
        numberSpec: const TextSpec(
            fontSize: 40,
            weight: 700,
            color: _ink,
            align: TextAlignSpec.center),
        affixSpec: const TextSpec(
            fontSize: 18, color: _blue, align: TextAlignSpec.center),
        buttonSpec: const TextSpec(
            fontSize: 12, weight: 600, align: TextAlignSpec.center),
        box: const BoxSpec(fill: _paper, padding: 10));

CanvasDocument _counterPage(CounterElement e) =>
    _page(_counterW, _counterH, [e]);

/// _pages is a document of three pages, each carrying [e], showing page
/// [at]: page 1 a right-hand leaf, 2 a left-hand one, 3 a right again.
CanvasDocument _pages(CounterElement e, int at) => CanvasDocument(
      kind: CanvasKind.pages,
      size: const CanvasSize(
          width: _counterW,
          ratio: CanvasRatio.custom,
          customRatio: _counterW / _counterH),
      scenes: [
        for (var i = 0; i < 3; i++)
          CanvasScene(id: "p$i", elements: [e], frames: 48),
      ],
      sceneAt: at,
    );

List<_State> _counterStates() {
  var out = <_State>[];
  const frames = [0, 12, 24];

  // Each mode at the start, the middle and the end of a count. A keyed one
  // counts by its keys; a live one shows its start where nothing runs it,
  // as in an export.
  var keyed = _counter(keyed: true, from: 0, to: 1000);
  keyed = keyed.withBase(
      track: ElementTrack([
    const Keyframe(frame: 0).withValue(KeyframeChannel.count, 0),
    const Keyframe(frame: 24).withValue(KeyframeChannel.count, 1000),
  ])) as CounterElement;
  for (var f in frames) {
    out.add(_state("counter-keyed-frame-$f", _counterPage(keyed), frame: f));
  }
  // Keyed, with From and To set away from what its keys hold.
  for (var f in frames) {
    out.add(_state("counter-keyed-from-to-unlike-keys-frame-$f",
        _counterPage(keyed.copyWith(from: 50, to: 5)),
        frame: f));
  }
  for (var source in CounterSource.values) {
    if (source == CounterSource.page) continue;
    var live = _counter(source: source, from: 7, to: 42).copyWith(
        gameCount: source == CounterSource.game ? "coins" : null,
        separator:
            source == CounterSource.clock ? CounterSeparator.hours : null,
        running: source == CounterSource.clock);
    for (var f in frames) {
      out.add(_state("counter-${source.name}-frame-$f", _counterPage(live),
          frame: f));
    }
  }
  // A page number, off to the left, on a right-hand and a left-hand page.
  var number = CounterElement(
      _at(const Rect.fromLTWH(10, 110, 80, 40), id: "n"),
      source: CounterSource.page,
      numberSpec: const TextSpec(
          fontSize: 24, weight: 700, color: _ink, align: TextAlignSpec.left),
      box: const BoxSpec(fill: _paper, padding: 4));
  for (var mirrored in [false, true]) {
    for (var (side, at) in [("right", 2), ("left", 1)]) {
      for (var f in frames) {
        out.add(_state(
            "counter-page-$side-${mirrored ? "mirrored" : "plain"}-frame-$f",
            _pages(number.copyWith(mirrored: mirrored), at),
            frame: f));
      }
    }
  }

  // How the number is written.
  for (var sep in CounterSeparator.values) {
    out.add(_state(
        "counter-separator-${sep.name}",
        _counterPage(_counter(from: 1234567.891)
            .copyWith(separator: sep, decimals: 2))));
  }
  for (var decimals in [0, 1, 3, 8]) {
    out.add(_state("counter-decimals-$decimals",
        _counterPage(_counter(from: 3.14159265).copyWith(decimals: decimals))));
  }
  out.add(_state("counter-negative",
      _counterPage(_counter(from: -2500.5).copyWith(decimals: 1))));

  // Words either side, at each gap.
  for (var gap in [0.0, 0.5, 2.0]) {
    out.add(_state(
        "counter-words-gap-${_short(gap)}",
        _counterPage(_counter(from: 42)
            .copyWith(before: "\$", after: " kg", gap: gap))));
  }
  out.add(_state("counter-word-before-only",
      _counterPage(_counter(from: 42).copyWith(before: "No. "))));
  out.add(_state("counter-word-after-only",
      _counterPage(_counter(from: 42).copyWith(after: " left"))));
  // Loose words, placed away from the number.
  for (var (name, before, after) in [
    ("centred", Offset.zero, Offset.zero),
    ("apart", const Offset(-0.3, -0.35), const Offset(0.3, 0.35)),
    ("corners", const Offset(-0.5, -0.5), const Offset(0.5, 0.5)),
  ]) {
    out.add(_state(
        "counter-loose-words-$name",
        _counterPage(_counter(from: 42).copyWith(
            before: "Total",
            after: "kilograms",
            loose: true,
            beforeAt: before,
            afterAt: after))));
  }

  // The box.
  for (var (name, box) in [
    ("none", const BoxSpec(padding: 0)),
    (
      "bordered",
      const BoxSpec(
          fill: _paper,
          borderWidth: 4,
          borderColor: _orange,
          borderRadius: 16,
          padding: 12),
    ),
    (
      "faded",
      const BoxSpec(
          fill: _blue,
          fillFade: GradientSpec(to: _green, angle: 45),
          padding: 20,
          padL: 40),
    ),
  ]) {
    out.add(_state("counter-box-$name",
        _counterPage(_counter(from: 42).copyWith(box: box))));
  }

  // Fit, in a box too narrow for the count.
  for (var fit in [true, false]) {
    out.add(_state(
        "counter-fit-${fit ? "on" : "off"}",
        _counterPage(_counter(from: 0, to: 9999999).copyWith(
            fit: fit,
            before: "\$",
            after: " each",
            separator: CounterSeparator.comma))));
  }
  // Words in each case, fitted, showing the widest the count reaches: in the
  // usual box, and in one so narrow the width alone sets the fit.
  for (var textCase in TextCase.values) {
    var c = _counter(from: 99999, to: 99999);
    var cased = c.copyWith(
        after: " kilograms",
        affixSpec: c.affixSpec.copyWith(textCase: textCase));
    out.add(_state("counter-words-case-${textCase.name}", _counterPage(cased)));
    out.add(_state("counter-words-case-${textCase.name}-narrow",
        _counterPage(cased.withBase(x: 60, width: 160) as CounterElement)));
  }

  // Each set of buttons, in a row and placed freely.
  var sets = [
    for (var b in CounterButton.values) (b.name, [b]),
    ("all", CounterButton.values),
  ];
  for (var (name, buttons) in sets) {
    for (var loose in [false, true]) {
      out.add(_state(
          "counter-buttons-$name-${loose ? "loose" : "row"}",
          _counterPage(_counter(from: 30).copyWith(
            buttons: buttons,
            looseButtons: loose,
          ))));
    }
  }
  out.add(_state(
      "counter-buttons-placed-sized",
      _counterPage(_counter(from: 30).copyWith(
          buttons: CounterButton.values,
          looseButtons: true,
          buttonAt: const [Offset(-0.35, -0.3), Offset(0.35, -0.3)],
          buttonSize: const Size(0.25, 0.3),
          buttonBox: const BoxSpec(
              fill: _red, borderRadius: 10, padding: 4, borderWidth: 0)))));
  out.add(_state(
      "counter-buttons-running",
      _counterPage(_counter(from: 30)
          .copyWith(buttons: CounterButton.values, running: true))));
  out.add(_state(
      "counter-buttons-and-loose-words",
      _counterPage(_counter(from: 30).copyWith(
          buttons: CounterButton.values,
          before: "Left",
          after: "seconds",
          loose: true,
          beforeAt: const Offset(-0.35, -0.4),
          afterAt: const Offset(0.35, 0.1)))));
  out.add(_state(
      "counter-turned",
      _counterPage(_counter(from: 42)
          .copyWith(before: "\$", buttons: CounterButton.values)
          .withBase(rotation: 15) as CounterElement)));
  return out;
}

// ---- Buttons, on a page 240 by 140 ----------------------------------------

const _buttonW = 240, _buttonH = 140;
const _buttonBox = Rect.fromLTWH(40, 40, 160, 60);

ButtonElement _button({String label = "Next"}) =>
    ButtonElement(_at(_buttonBox, id: "b"),
        label: label,
        textSpec: const TextSpec(
            fontSize: 20,
            weight: 600,
            color: _white,
            align: TextAlignSpec.center,
            verticalAlign: VerticalAlignSpec.middle),
        hoverFill: _green,
        hoverTextColor: _ink);

CanvasDocument _buttonPage(ButtonElement e) => _page(_buttonW, _buttonH, [e]);

List<_State> _buttonStates() {
  var out = <_State>[];
  for (var (length, label) in [
    ("short", "Go"),
    ("long", "Play the whole of the second movement again"),
  ]) {
    for (var textCase in TextCase.values) {
      var b = _button(label: label);
      out.add(_state(
          "button-label-$length-case-${textCase.name}",
          _buttonPage(
              b.copyWith(textSpec: b.textSpec.copyWith(textCase: textCase)))));
    }
  }
  for (var (name, box) in [
    (
      "border",
      const BoxSpec(fill: _blue, borderWidth: 4, borderColor: _orange),
    ),
    ("radius", const BoxSpec(fill: _blue, borderRadius: 30)),
    ("fill", const BoxSpec(fill: _red)),
    (
      "fade",
      const BoxSpec(fill: _blue, fillFade: GradientSpec(to: _green, angle: 0)),
    ),
    ("padding", const BoxSpec(fill: _blue, padding: 4, padL: 60)),
    ("clear", const BoxSpec()),
  ]) {
    out.add(
        _state("button-box-$name", _buttonPage(_button().copyWith(box: box))));
  }
  out.add(_state("button-turned",
      _buttonPage(_button().withBase(rotation: 30) as ButtonElement)));
  out.add(_state("button-slanted",
      _buttonPage(_button().withBase(skewX: 20) as ButtonElement)));
  out.add(_state("button-hovered", _buttonPage(_button()), hovered: "b"));
  return out;
}

// ---- Metronomes, on a page 160 by 240 -------------------------------------

const _metronomeW = 160, _metronomeH = 240;
const _metronomeBox = Rect.fromLTWH(20, 10, 120, 220);

CanvasDocument _metronomePage(MetronomeElement e) =>
    _page(_metronomeW, _metronomeH, [e]);

List<_State> _metronomeStates() {
  var out = <_State>[];
  var m = MetronomeElement(_at(_metronomeBox, id: "m"));
  // Every number of beats the model holds, which is more than its dropdown
  // offers.
  for (var beats = 1; beats <= 12; beats++) {
    out.add(_state(
        "metronome-beats-$beats", _metronomePage(m.copyWith(beats: beats))));
  }
  for (var bpm in [metronomeSlowest, 60.0, 100.0, 160.0, metronomeFastest]) {
    out.add(_state(
        "metronome-bpm-${_short(bpm)}", _metronomePage(m.copyWith(bpm: bpm))));
  }
  out.add(_state(
      "metronome-colours",
      _metronomePage(m.copyWith(
          body: const Color(0xFF2E5E4E), accent: const Color(0xFF64B5F6)))));
  out.add(_state(
      "metronome-wide-box",
      _metronomePage(MetronomeElement(
          _at(const Rect.fromLTWH(10, 60, 140, 120), id: "m")))));
  return out;
}

// ---- A page through a Camera, 320 by 180 ----------------------------------

const _cameraW = 320, _cameraH = 180;

/// _scenery is a page with things at three depths: a far band behind, a
/// row of shapes on the page, and a near one in front, each with words.
List<CanvasElement> _scenery() => [
      ShapeElement(
          _at(const Rect.fromLTWH(0, 0, 320, 180), id: "sky")
              .copyWith(depth: 1),
          fill: const Color(0xFF1E3A5F)),
      ShapeElement(
          _at(const Rect.fromLTWH(0, 110, 320, 70), id: "far")
              .copyWith(depth: 0.6),
          shape: ShapeKind.ellipse,
          fill: _green),
      for (var i = 0; i < 4; i++)
        ShapeElement(_at(Rect.fromLTWH(30.0 + i * 70, 60, 50, 50), id: "mid$i"),
            shape: ShapeKind.values[i % ShapeKind.values.length],
            fill: _orange,
            strokeWidth: 3,
            strokeColor: _white,
            text: "$i",
            textSpec: const TextSpec(
                fontSize: 18,
                weight: 700,
                color: _ink,
                align: TextAlignSpec.center,
                verticalAlign: VerticalAlignSpec.middle)),
      ShapeElement(
          _at(const Rect.fromLTWH(220, 120, 80, 50), id: "near")
              .copyWith(depth: -0.8),
          fill: _red,
          text: "near",
          textSpec: const TextSpec(
              fontSize: 16,
              color: _white,
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.middle)),
    ];

CanvasDocument _cameraPage(CameraElement? cam) =>
    _page(_cameraW, _cameraH, [..._scenery(), if (cam != null) cam]);

CameraElement _camera(Rect r) => CameraElement(_at(r, id: "cam"));

List<_State> _cameraStates() {
  var out = <_State>[];
  const whole = Rect.fromLTWH(0, 0, 320, 180);
  const half = Rect.fromLTWH(40, 30, 160, 90);
  out.add(_state("camera-none", _cameraPage(null)));
  out.add(_state("camera-whole-page", _cameraPage(_camera(whole))));
  out.add(_state("camera-hidden",
      _cameraPage(_camera(half).withBase(visible: false) as CameraElement)));
  out.add(_state("camera-frame-half", _cameraPage(_camera(half))));
  out.add(_state("camera-frame-at-edge",
      _cameraPage(_camera(const Rect.fromLTWH(220, 120, 160, 90)))));
  out.add(_state(
      "camera-zoom-by-key",
      _cameraPage(_camera(whole).withBase(
          track: ElementTrack(const [
        Keyframe(frame: 0),
        Keyframe(frame: 24, scale: 3, dx: 60, dy: 20),
      ])) as CameraElement),
      frame: 12));
  for (var roll in [15.0, -40.0, 90.0]) {
    out.add(_state("camera-roll-${_short(roll).replaceAll("-", "minus-")}",
        _cameraPage(_camera(half).withBase(rotation: roll) as CameraElement)));
  }
  for (var (name, focus) in [("page", 0.0), ("far", 1.0), ("near", -0.8)]) {
    out.add(_state("camera-blur-focus-$name",
        _cameraPage(_camera(whole).copyWith(blur: 6, focus: focus))));
  }
  out.add(_state("camera-blur-focus-on-element",
      _cameraPage(_camera(whole).copyWith(blur: 6, focusOn: "near"))));
  out.add(_state(
      "camera-blur-keyed",
      _cameraPage(_camera(whole).withBase(
          track: ElementTrack([
        const Keyframe(frame: 0).withValue("blur", 0),
        const Keyframe(frame: 24).withValue("blur", 20),
      ])) as CameraElement),
      frame: 12));
  for (var (name, amount, soft) in [
    ("hard", 0.9, 0.1),
    ("soft", 0.6, 0.9),
  ]) {
    out.add(_state(
        "camera-vignette-$name",
        _cameraPage(
            _camera(whole).copyWith(vignette: amount, vignetteSoft: soft))));
  }
  for (var strength in [0.3, 1.0]) {
    out.add(_state(
        "camera-parallax-${_short(strength)}",
        _cameraPage(_camera(const Rect.fromLTWH(120, 60, 160, 90))
            .copyWith(parallax: strength))));
  }
  out.add(_state(
      "camera-motion-blur",
      _cameraPage(
          CameraElement(_clipped(_at(half, id: "cam")), motionBlur: 0.8)),
      frame: 12));
  out.add(_state(
      "camera-every-lens",
      _cameraPage(CameraElement(
          _at(const Rect.fromLTWH(60, 40, 200, 112.5), id: "cam")
              .copyWith(rotation: 8),
          blur: 4,
          focus: -0.8,
          parallax: 0.5,
          vignette: 0.7,
          vignetteSoft: 0.4))));
  return out;
}

/// _states is every state kept.
List<_State> _states() => [
      ..._layoutStates(),
      ..._counterStates(),
      ..._buttonStates(),
      ..._metronomeStates(),
      ..._cameraStates(),
    ];

// ---- The numbers kept beside each picture ---------------------------------

/// _gridStep is how far apart the points a press is asked about are, in
/// design units: fine enough that a moved corner or a moved button shows.
const _gridStep = 4.0;

/// _n is [v] to a ten-thousandth: far finer than a pixel, and coarse enough
/// that the same sum done in another order still agrees.
String _n(double v) {
  var s = v.toStringAsFixed(4);
  return s == "-0.0000" ? "0.0000" : s;
}

String _point(Offset p) => "(${_n(p.dx)}, ${_n(p.dy)})";

String _rect(Rect r) =>
    "[${_n(r.left)}, ${_n(r.top)}, ${_n(r.right)}, ${_n(r.bottom)}]";

/// _digest is which points of a grid over [page] [inside] holds for: how
/// many, and a hash of which, so any point that changes changes it.
String _digest(Rect page, bool Function(Offset) inside) {
  var hash = 0x811c9dc5, count = 0, total = 0;
  for (var y = page.top + _gridStep / 2; y < page.bottom; y += _gridStep) {
    for (var x = page.left + _gridStep / 2; x < page.right; x += _gridStep) {
      var hit = inside(Offset(x, y));
      total++;
      if (hit) count++;
      hash = ((hash ^ (hit ? 1 : 0)) * 0x01000193) & 0xFFFFFFFF;
    }
  }
  return "$count/$total #${hash.toRadixString(16).padLeft(8, "0")}";
}

/// _placedBounds is the bounds of [path], in [e]'s own box, laid on the
/// page as paintElement lays [e] on [frame]: its turn, slant and pose.
Rect _placedBounds(CanvasElement e, Path path, int frame, CanvasDocument doc) {
  var place = e.placeAt(frame, doc);
  double? l, t, r, b;
  for (var metric in path.computeMetrics()) {
    var steps = math.max(8, (metric.length / 2).ceil());
    for (var i = 0; i <= steps; i++) {
      var p = place.place(
          metric.getTangentForOffset(metric.length * i / steps)!.position);
      l = l == null ? p.dx : math.min(l, p.dx);
      t = t == null ? p.dy : math.min(t, p.dy);
      r = r == null ? p.dx : math.max(r, p.dx);
      b = b == null ? p.dy : math.max(b, p.dy);
    }
  }
  return l == null ? Rect.zero : Rect.fromLTRB(l, t!, r!, b!);
}

void _layoutNumbers(
    StringBuffer out, LayoutElement e, CanvasDocument doc, int frame) {
  for (var (i, p) in layoutPlaces(e, e.bounds).indexed) {
    var id = "${e.id} cell $i ${p.cell.id}";
    out.writeln("$id shape ${p.cell.shape.name} points ${p.points.length}");
    out.writeln("$id in its box ${_rect(p.bounds)}");
    out.writeln("$id drawn ${_rect(_placedBounds(e, p.path, frame, doc))}");
    out.writeln("$id dock outline ${_rect(onPageOf(e, p.path).getBounds())}");
  }
  for (var line in layoutCutLines(e, e.bounds)) {
    out.writeln("${e.id} cut ${line.path.map((b) => b ? "b" : "a").join()} "
        "${line.vertical ? "down" : "across"} "
        "${_point(line.from)} ${_point(line.to)} in ${_rect(line.box)}");
  }
  for (var line in layoutTrackLines(e, e.bounds)) {
    out.writeln("${e.id} track ${line.column ? "column" : "row"} "
        "${line.index} ${_point(line.from)} ${_point(line.to)}");
  }
}

/// _counterShown is the value [e] shows on [frame], as paintElement works
/// it out with nothing running it (an export).
double _counterShown(CounterElement e, CanvasDocument doc, int frame) =>
    e.isPageNumber
        ? (doc.pageNumber ?? 0).toDouble()
        : e.live
            ? e.from
            : (poseWithMotion(e, frame, doc).values[KeyframeChannel.count] ??
                e.from);

/// _counterBounds is the box paintElement draws [e] in: on a left-hand
/// page a mirrored page number is moved across the page's middle.
Rect _counterBounds(CounterElement e, CanvasDocument doc) {
  var bounds = e.bounds;
  if (e.mirrored && e.isPageNumber && doc.pageIsLeftHand) {
    var page = doc.size.rect;
    bounds = Rect.fromLTWH(page.left + page.right - bounds.right, bounds.top,
        bounds.width, bounds.height);
  }
  return bounds;
}

void _counterNumbers(StringBuffer out, CounterElement e, CanvasDocument doc,
    int frame, StageHitTest hits) {
  var value = _counterShown(e, doc, frame);
  out.writeln("${e.id} shows ${_n(value)} as \"${e.textFor(value)}\"");
  var bounds = _counterBounds(e, doc);
  var posed = hits.posed(e);
  out.writeln("${e.id} drawn in ${_rect(bounds)}, pressed in ${_rect(posed)}");

  // The room the number is fitted to, as the painter works it out (its
  // rule, written here).
  var inner = e.box.inner(bounds);
  var buttons = counterButtonRects(e, bounds);
  var unit = math.max(0.2, inner.shortestSide / 120);
  var room = buttons.isEmpty || e.looseButtons
      ? inner
      : Rect.fromLTRB(inner.left, inner.top, inner.right,
          buttons.first.top - counterGap * unit);
  var fit = e.fit ? counterFitScale(e, room, value) : 1.0;
  out.writeln("${e.id} room ${_rect(room)} fit ${_n(fit)}");

  // Its buttons where they are drawn and where the stage presses them.
  for (var (i, r) in buttons.indexed) {
    out.writeln("${e.id} button $i ${e.buttons[i].name} drawn ${_rect(r)}");
  }
  for (var (i, r) in counterButtonRects(e, posed).indexed) {
    out.writeln("${e.id} button $i ${e.buttons[i].name} pressed ${_rect(r)}");
  }

  // Loose words: where the painter draws each (_paintLoose's box, at the
  // fitted size) and where the stage presses it (_counterPartUnder's box,
  // at the unfitted size), each by its own rule, written here.
  if (e.loose) {
    var pressedInner = e.box.inner(posed);
    for (var (which, text, at) in [
      ("before", e.before, e.beforeAt),
      ("after", e.after, e.afterAt),
    ]) {
      if (text.isEmpty) continue;
      var drawnSize = e.affixSpec.fontSize * (fit >= 0.999 ? 1 : fit);
      var drawn = Rect.fromCenter(
          center: Offset(inner.center.dx + inner.width * at.dx,
              inner.center.dy + inner.height * at.dy),
          width: inner.width,
          height: math.max(drawnSize * 1.6, 1));
      var pressed = Rect.fromCenter(
          center: Offset(pressedInner.center.dx + pressedInner.width * at.dx,
              pressedInner.center.dy + pressedInner.height * at.dy),
          width: math.max(
              e.affixSpec.fontSize * text.length * 0.7, e.affixSpec.fontSize),
          height: e.affixSpec.fontSize * 1.4);
      out.writeln("${e.id} words $which drawn ${_rect(drawn)} "
          "pressed ${_rect(pressed)}");
    }
  }
}

void _metronomeNumbers(StringBuffer out, MetronomeElement e, Rect page) {
  var (s, at) = metronomeFit(e.bounds);
  out.writeln("${e.id} fitted ${_n(s)} at ${_point(at)}");
  out.writeln("${e.id} pivot ${_point(at + metronomeLayout.pivot * s)} "
      "lamp ${_point(at + metronomeLayout.lamp * s)} "
      "arm ${_n(metronomeLayout.arm * s)}");
  for (var MapEntry(:key, :value) in metronomeLayout.buttons.entries) {
    var r = Rect.fromLTWH(at.dx + value.left * s, at.dy + value.top * s,
        value.width * s, value.height * s);
    out.writeln("${e.id} part ${key.name} ${_rect(r)} pressed "
        "${_digest(page, (p) => metronomePartAt(e, p) == key)}");
  }
}

void _cameraNumbers(
    StringBuffer out, CameraElement cam, CanvasDocument doc, int frame) {
  var shown = cameraOf(doc);
  out.writeln("${cam.id} frames the page: ${identical(shown, cam)}");
  if (shown == null) return;
  var (zoom, at) = cameraFraming(cam, frame, doc);
  out.writeln("${cam.id} zoom ${_n(zoom)} at ${_point(at)} "
      "shows ${_rect(cameraFrame(cam, frame, doc))}");
  var look = cameraLookAt(cam, frame, doc);
  out.writeln("${cam.id} lens roll ${_n(look.roll)} focus ${_n(look.focus)} "
      "blur ${_n(look.blur)} parallax ${_n(look.parallax)} "
      "vignette ${_n(look.vignette)} soft ${_n(look.vignetteSoft)} "
      "motion blur ${_n(look.motionBlur)}");
  var framing = sceneFraming(doc, frame);
  out.writeln("scene framing "
      "${framing == null ? "none" : "${_n(framing.$1)} ${_point(framing.$2)}"}");
}

/// _numbers is what the stage and the docks ask of each element in [doc]
/// on [frame], one line each.
String _numbers(CanvasDocument doc, int frame) {
  var out = StringBuffer();
  var page = doc.size.rect;
  var hits = StageHitTest(document: doc, frame: frame, scale: 1);
  for (var e in doc.elements) {
    // The grey page and the scenery behind a camera hold nothing of their
    // own: what they are drawn as is the picture.
    if (e.id == "page") continue;
    out.writeln("${e.id} drawn ${_rect(visualBoundsOf(e, doc, frame))}");
    out.writeln("${e.id} pressed ${_digest(page, (p) => hits.contains(e, p))}");
    if (e.base.dock.isNotEmpty) {
      var clip = dockClip(e, doc.elements);
      out.writeln("${e.id} docked ${e.base.dock}${e.base.dockOut ? " out" : ""}"
          " clip ${clip == null ? "none" : _rect(clip.getBounds())}");
    }
    switch (e) {
      case LayoutElement l:
        _layoutNumbers(out, l, doc, frame);
      case CounterElement c:
        _counterNumbers(out, c, doc, frame, hits);
      case MetronomeElement m:
        _metronomeNumbers(out, m, page);
      case CameraElement c:
        _cameraNumbers(out, c, doc, frame);
      case ButtonElement b:
        out.writeln("${b.id} label room ${_rect(b.box.inner(b.bounds))}");
      default:
    }
  }
  if (cameraOf(doc) == null) {
    var framing = sceneFraming(doc, frame);
    if (framing != null) out.writeln("scene framing ${_n(framing.$1)}");
  }
  return out.toString();
}

/// _font registers [files] from the app's fonts as [family].
Future<void> _font(String family, List<String> files) async {
  var loader = FontLoader(family);
  for (var f in files) {
    loader.addFont(File("assets/fonts/$f")
        .readAsBytes()
        .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    var kept = Platform.environment["PARTS_PICTURES"];
    if (kept == null || kept.isEmpty) return;
    await _font("Inter", [
      "Inter-Regular.otf",
      "Inter-SemiBold.otf",
      "Inter-Bold.otf",
      "Inter-ExtraBold.otf",
    ]);
    await _font("RobotoMono", ["RobotoMono-VariableFont_wght.ttf"]);
  });

  // What a metronome shows is asked of the controller that runs it; there
  // is none here, as in an export, whatever a test before this one left.
  setUp(() => metronomeShowOf = null);

  /// keep draws [state] as an export does, through its Camera where it has
  /// one, and compares the picture and numbers with those kept under its
  /// name, or keeps them.
  Future<void> keep(_State state) async {
    var size = state.doc.size;
    var recorder = ui.PictureRecorder();
    paintCanvasDocument(ui.Canvas(recorder), state.doc,
        frame: state.frame,
        hoveredButton: state.hovered,
        camera: sceneFraming(state.doc, state.frame));
    var (raw, png) = await imageBytes(
        await recorder.endRecording().toImage(size.width, size.height));
    keepOrCompare("PARTS_PICTURES", state.name,
        raw: raw,
        png: png,
        width: size.width,
        numbers: _numbers(state.doc, state.frame));
  }

  var states = _states();
  test("there are as many states as meant", () {
    expect(states.length, greaterThan(150));
    expect({for (var s in states) s.name}.length, states.length,
        reason: "every state has a name of its own");
  });
  for (var state in states) {
    test(state.name, () => keep(state));
  }
}
