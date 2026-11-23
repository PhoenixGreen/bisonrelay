import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';

// canvas_palette.dart is one colour changed everywhere a document uses it
// (the saved colours' Replace everywhere; see CanvasController.replaceColour),
// and reading the colours a canvas already uses (to match a new table to it,
// and counted for whoever reads a canvas's style). All go through the colour
// visitor (colour_map.dart): each thing that holds colours says which they
// are, so none guesses from saved numbers.

/// replacing is the change Replace everywhere makes: every colour with
/// [from]'s red, green and blue becomes [to]'s, each keeping its own
/// opacity, so a half-clear use stays half clear. A fully clear use is
/// replaced too, and stays clear: it is still the colour the person chose,
/// and shows as the new one once it is made visible. So is a colour that is
/// not showing (an outline's while the outline is off). [from]'s opacity
/// and [to]'s play no part.
ColourMap replacing(Color from, Color to) {
  var old = from.toARGB32() & 0xFFFFFF;
  var next = to.toARGB32() & 0xFFFFFF;
  return (Color c, {required bool shown}) {
    var v = c.toARGB32();
    return v & 0xFFFFFF == old ? Color((v & 0xFF000000) | next) : c;
  };
}

/// CanvasColours is what a canvas is already dressed in: the [ground]
/// behind it, the [ink] its words are in, and the [accent] its shapes and
/// headings stand out in, so a new element such as a table can match.
class CanvasColours {
  final Color ground;
  final Color ink;
  final Color accent;
  const CanvasColours(this.ground, this.ink, this.accent);
}

/// canvasColoursOf is what the canvas on screen in [d] is dressed in: the
/// backdrop drawn behind it (a scene's own, where it has one) and its
/// elements, less [except] (the table being matched, which should not
/// match itself).
CanvasColours canvasColoursOf(CanvasDocument d, {String? except}) =>
    canvasColours(d.drawnBackground.spec.background, [
      for (var e in d.elements)
        if (e.id != except) e
    ]);

/// canvasColours reads [ground] -- the background -- and the colours
/// [elements] use most into a ground, an ink and an accent. Only colours
/// that show are counted (see ColourMap), and only those meant to be seen:
/// a faint tint, under three quarters opaque, is a shade, not a choice.
CanvasColours canvasColours(Color ground, Iterable<CanvasElement> elements) {
  var counts = <int, int>{};
  Color count(Color c, {required bool shown}) {
    var v = c.toARGB32();
    if (shown && ((v >> 24) & 0xFF) >= 0xC0) {
      var rgb = v | 0xFF000000;
      counts[rgb] = (counts[rgb] ?? 0) + 1;
    }
    return c;
  }

  for (var e in elements) {
    e.mapColours(count);
  }
  var groundLight = ground.computeLuminance();
  // Most used first; of two used alike, the one met first.
  var byUse = [...counts.entries.indexed]..sort((a, b) {
      var more = b.$2.value - a.$2.value;
      return more != 0 ? more : a.$1 - b.$1;
    });
  Color? ink, accent;
  for (var (_, entry) in byUse) {
    var c = Color(entry.key);
    var light = c.computeLuminance();
    // Words have to be read against the ground.
    if (ink == null && (light - groundLight).abs() > 0.45) ink = c;
    if (accent == null &&
        _saturation(c) > 0.35 &&
        (light - groundLight).abs() > 0.08) {
      accent = c;
    }
    if (ink != null && accent != null) break;
  }
  ink ??= groundLight > 0.4 ? const Color(0xFF1A1D23) : const Color(0xFFF2F4F7);
  accent ??= Color.lerp(ground, ink, 0.18)!.withValues(alpha: 1);
  return CanvasColours(ground, ink, accent);
}

/// ColourUses is how often each colour a document shows is used, keyed by
/// its 0xAARRGGBB number in the order first met: [elements] for the
/// elements of every scene and of the master, [backgrounds] for the
/// backdrops behind them.
typedef ColourUses = ({Map<int, int> elements, Map<int, int> backgrounds});

/// colourUsesOf is how often each colour [d] shows is used. Only colours
/// that show are counted (see ColourMap), at every opacity, fully clear
/// included: what to make of them is the reader's. A colour is counted each
/// time it is held, so one used by many elements weighs more. Neither an
/// element's nor a backdrop's, and so not counted: a scene's transition,
/// the cast and the text styles (never drawn themselves; what is drawn from
/// them holds its own colours, counted where it stands), and the sheets'
/// colour rules.
ColourUses colourUsesOf(CanvasDocument d) {
  ColourMap counting(Map<int, int> counts) => (Color c, {required bool shown}) {
        if (shown) {
          var v = c.toARGB32();
          counts[v] = (counts[v] ?? 0) + 1;
        }
        return c;
      };
  var elements = <int, int>{}, backgrounds = <int, int>{};
  var inFront = counting(elements), behind = counting(backgrounds);
  var master = d.master;
  for (var s in d.allScenes) {
    for (var e in s.elements) {
      e.mapColours(inFront);
    }
  }
  for (var e in master?.elements ?? const <CanvasElement>[]) {
    e.mapColours(inFront.shownOnlyIf(d.masterOn));
  }
  d.background.mapColours(behind);
  for (var s in d.allScenes) {
    s.background?.mapColours(behind.shownOnlyIf(!s.backgroundOff));
  }
  if (master != null) {
    master.background
        ?.mapColours(behind.shownOnlyIf(d.masterOn && !master.backgroundOff));
  }
  return (elements: elements, backgrounds: backgrounds);
}

double _saturation(Color c) {
  var most = math.max(c.r, math.max(c.g, c.b));
  var least = math.min(c.r, math.min(c.g, c.b));
  return most <= 0 ? 0 : (most - least) / most;
}

/// tableInColours is [e] dressed in [colours]: its header band in the
/// accent, its words in the ink, its rules and stripes faint ink; nothing
/// else changes.
TableElement tableInColours(TableElement e, CanvasColours colours) {
  var onAccent = colours.accent.computeLuminance() > 0.4
      ? const Color(0xFF111418)
      : const Color(0xFFFFFFFF);
  return e.copyWith(
    headerFill: colours.accent,
    flatHeader: true,
    cellFill: const Color(0x00000000),
    flatCells: true,
    zebraFill: colours.ink.withValues(alpha: 0.07),
    gridColor: colours.ink.withValues(alpha: 0.22),
    headerSpec: e.headerSpec.copyWith(color: onAccent),
    cellSpec: e.cellSpec.copyWith(color: colours.ink),
  );
}
