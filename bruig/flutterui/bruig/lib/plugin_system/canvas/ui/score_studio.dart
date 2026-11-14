import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart' show keyAlter;
import 'package:bruig/plugin_system/canvas/model/score_edit.dart';
import 'package:bruig/plugin_system/canvas/render/score_engraver.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// score_studio.dart is the Score Studio (Ken, 2026-11-14): a score written
// as MuseScore writes one, given the whole page as the Character Studio is.
// Instruments down the left, the score on paper in the middle, palettes and
// the picked note's settings on the right, what the keys do along the
// bottom. Every change is the score's, made through the controller, so each
// is one step to undo and every part's channel follows it.
//
// The approved prototype is its board: sheet-music-prototype/index.html.

/// scoreDurations are the values the toolbar offers, with MuseScore's keys
/// and the Bravura note each is drawn with.
const scoreDurations = <(double, String, int, String)>[
  (4, "Whole", 0xE1D2, "7"),
  (2, "Half", 0xE1D3, "6"),
  (1, "Quarter", 0xE1D5, "5"),
  (0.5, "Eighth", 0xE1D7, "4"),
  (0.25, "16th", 0xE1D9, "3"),
];

/// ScorePalette is a tab of the palettes.
enum ScorePalette {
  clefs("Clefs"),
  keys("Keys"),
  time("Time"),
  dynamics("Dynamics"),
  articulations("Articulations"),
  lines("Lines"),
  text("Text"),
  repeats("Repeats"),
  strum("Strum");

  final String label;
  const ScorePalette(this.label);
}

class ScoreStudio extends StatefulWidget {
  final CanvasController controller;
  final String scoreId;
  final VoidCallback onDone;
  const ScoreStudio(
      {required this.controller,
      required this.scoreId,
      required this.onDone,
      super.key});

  @override
  State<ScoreStudio> createState() => _ScoreStudioState();
}

class _ScoreStudioState extends State<ScoreStudio> {
  CanvasController get c => widget.controller;
  MusicScore? get score => c.scoreById(widget.scoreId);

  final _focus = FocusNode(debugLabel: "scoreStudio");

  /// sel is the event picked; cursor where note input writes.
  String? sel;
  ScoreCursor? cursor;
  bool input = false;
  double value = 1;
  int dots = 0;
  int voice = 0;

  /// alone is the part shown by itself, or null for the full score.
  String? alone;
  ScorePalette palette = ScorePalette.dynamics;

  /// last is the last pitch written: the next letter goes nearest it.
  Pitch? last;

  EngravedScore? _engraved;
  MusicScore? _engravedFrom;
  String? _engravedAlone;

  // A marking being dragged: what it is, where it started, its offset then.
  ScoreHit? _drag;
  Offset _dragFrom = Offset.zero, _dragWas = Offset.zero;

  Timer? _noteOff;

  /// _scale is the paper's drawn size to the score's own.
  double _scale = 1;

  @visibleForTesting
  double get scale => _scale;

  /// placeOf is where on the paper event [id] is drawn: for tests.
  @visibleForTesting
  Offset placeOf(String id) =>
      _engraved!.hits
          .firstWhere((h) => h.kind == ScoreHitKind.event && h.event == id)
          .rect
          .center *
      _scale;

  /// staffPlace is where on the paper [pitch] at [at] in [bar] of [part]'s
  /// [staff] would be written: for tests.
  @visibleForTesting
  Offset staffPlace(String part, int staff, int bar, double at, String pitch) {
    var es = _engraved!;
    var h = es.hits.firstWhere((h) =>
        h.kind == ScoreHitKind.staff &&
        h.part == part &&
        h.staff == staff &&
        h.bar == bar);
    var x = es.xOf(bar, at)!.$1 + es.options.space * 0.6;
    var y =
        h.bottom - (Pitch.parse(pitch)!.step - h.step0) * es.options.space / 2;
    return Offset(x, y) * _scale;
  }

  /// handlePlace is where on the paper the picked marking's handle [i] is:
  /// for tests.
  @visibleForTesting
  Offset handlePlace(int i) {
    var pm = _markPick!;
    var hit = _engraved!.hits.firstWhere((h) =>
        h.kind == ScoreHitKind.mark && h.mark == pm.kind && h.event == pm.id);
    return scoreMarkHandles(hit, _engraved!.options.space)[i] * _scale;
  }

  /// markPlace is where on the paper event [id]'s marking [kind] is drawn:
  /// for tests.
  @visibleForTesting
  Offset markPlace(String id, String kind) =>
      _engraved!.hits
          .firstWhere((h) =>
              h.kind == ScoreHitKind.mark && h.event == id && h.mark == kind)
          .rect
          .center *
      _scale;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    _typed.dispose();
    _typedFocus.dispose();
    c.removeListener(_changed);
    _noteOff?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// edit makes [next] the score: one step to undo, the channels following.
  void edit(MusicScore next) {
    c.setScore(next);
  }

  EngravedScore _layout(MusicScore s) {
    if (_engraved != null &&
        identical(_engravedFrom, s) &&
        _engravedAlone == alone) {
      return _engraved!;
    }
    _engravedFrom = s;
    _engravedAlone = alone;
    return _engraved =
        layoutScore(s, EngraveOptions(parts: alone == null ? null : {alone!}));
  }

  // ------------------------------------------------------------- hearing

  void hear(String part, List<Pitch> pitches) {
    var s = score;
    var ch = s == null ? null : c.scoreChannel(s.id, part);
    if (ch == null || pitches.isEmpty) return;
    var transpose = s!.partById(part)!.kind.transpose;
    var keys = [for (var p in pitches) (p.key - transpose).clamp(0, 127)];
    for (var k in keys) {
      c.noteOn(ch, k, velocity: 90);
    }
    _noteOff?.cancel();
    _noteOff = Timer(const Duration(milliseconds: 450), () {
      var now = c.document.elementById(ch.id);
      if (now is AudioElement) {
        for (var k in keys) {
          c.noteOff(now, k);
        }
      }
    });
  }

  // ------------------------------------------------------------- note input

  /// pitchFor is [letter] (0 C to 6 B) in the key, in the octave nearest
  /// the last note written (or the middle of the cursor's staff).
  Pitch pitchFor(int letter) {
    var s = score!;
    var cur = cursor!;
    var clef = s.partById(cur.part)!.staves[cur.staff].clef;
    var near = last?.step ?? clef.bottom + 4;
    Pitch? best;
    for (var o = 0; o <= 8; o++) {
      var p = Pitch(letter, o, keyAlter(letter, s.keyAt(cur.bar)));
      if (best == null || (p.step - near).abs() < (best.step - near).abs()) {
        best = p;
      }
    }
    return best!;
  }

  void enter(List<Pitch> pitches) {
    var s = score;
    var cur = cursor;
    if (s == null || cur == null) return;
    var strum = s.partById(cur.part)!.strum;
    var (next, id, moved) = s.enter(cur, strum ? const [] : pitches, value,
        dots: dots,
        slash: strum && pitches.isNotEmpty,
        strum: strum ? Strum.down : null);
    edit(next);
    setState(() {
      sel = id;
      cursor = moved;
      if (pitches.isNotEmpty && !strum) last = pitches.last;
    });
    if (!strum) hear(cur.part, pitches);
  }

  void pickValue(double v) {
    setState(() {
      value = v;
      dots = 0;
    });
    // Picked with a note picked (and input off), the note takes it.
    var s = score;
    if (!input && sel != null && s != null) edit(s.setValue(sel!, v));
  }

  void toggleDot() {
    setState(() => dots = dots == 0 ? 1 : 0);
    var s = score;
    var e = sel == null ? null : s?.event(sel!);
    if (!input && e != null) edit(s!.setValue(sel!, e.value, dots: dots));
  }

  // ------------------------------------------------------------- moving

  /// step picks the event [by] places on in the picked one's staff.
  void step(int by) {
    var s = score;
    if (s == null || sel == null) return;
    var at = s.find(sel!);
    if (at == null) return;
    var st = s.partById(at.part)!.staves[at.staff];
    var all = <String>[
      for (var b in st.bars)
        for (var e in b) e.id
    ];
    var i = all.indexOf(sel!) + by;
    if (i < 0 || i >= all.length) return;
    setState(() {
      sel = all[i];
      var p = s.find(sel!)!;
      cursor = (
        part: p.part,
        staff: p.staff,
        bar: p.bar,
        at: s.timeOf(sel!),
        voice: s.event(sel!)!.voice
      );
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var s = score;
    if (s == null) return KeyEventResult.ignored;
    // Typing in a field (a title, a lyric on the score) is typing, not the
    // Studio's keys.
    if (FocusManager.instance.primaryFocus != _focus) {
      return KeyEventResult.ignored;
    }
    var k = ev.logicalKey;
    var meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    var shift = HardwareKeyboard.instance.isShiftPressed;
    var alt = HardwareKeyboard.instance.isAltPressed;
    if (meta && k == LogicalKeyboardKey.keyZ) {
      shift ? c.redo() : c.undo();
      return KeyEventResult.handled;
    }
    // ⌘L a lyric, ⌘K a chord symbol, on the note picked, as MuseScore.
    if (meta && sel != null && k == LogicalKeyboardKey.keyL) {
      startTyping("lyr", sel!);
      return KeyEventResult.handled;
    }
    if (meta && sel != null && k == LogicalKeyboardKey.keyK) {
      startTyping("ch", sel!);
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) &&
        _markPick != null) {
      // The marking picked goes.
      var pm = _markPick!;
      edit(pm.kind == MarkKind.hairpin
          ? s.removeSpanner(pm.id)
          : s.setDynamic(pm.id, null));
      setState(() => _markPick = null);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space) {
      togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(() {
        if (input) {
          input = false;
        } else {
          sel = null;
        }
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyN && !meta) {
      toggleInput();
      return KeyEventResult.handled;
    }
    const letters = {
      "C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6, //
    };
    var label = k.keyLabel.toUpperCase();
    if (letters.containsKey(label) && !meta) {
      if (input && cursor != null) {
        var p = pitchFor(letters[label]!);
        if (shift && sel != null) {
          // Shift with a letter adds it to the chord, as MuseScore does.
          edit(s.addToChord(sel!, p));
          hear(cursor!.part, [p]);
        } else {
          enter([p]);
        }
      }
      return KeyEventResult.handled;
    }
    for (var (v, _, _, key) in scoreDurations) {
      if (label == key && !meta) {
        pickValue(v);
        return KeyEventResult.handled;
      }
    }
    if (label == "0" && input && cursor != null) {
      enter(const []);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.period) {
      toggleDot();
      return KeyEventResult.handled;
    }
    if (sel != null) {
      if (k == LogicalKeyboardKey.keyT && !meta) {
        edit(s.toggleTie(sel!));
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown) {
        var d = k == LogicalKeyboardKey.arrowUp ? 1 : -1;
        var next = meta
            ? s.transposed(sel!, octaves: d)
            : alt
                ? s.transposed(sel!, steps: d)
                : s.transposed(sel!, semitones: d);
        edit(next);
        var at = next.find(sel!);
        var e = next.event(sel!);
        if (at != null && e != null) {
          hear(at.part, e.pitches);
          if (e.pitches.isNotEmpty) last = e.pitches.last;
        }
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        step(k == LogicalKeyboardKey.arrowRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
        edit(s.deleteEvent(sel!));
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void toggleInput() {
    setState(() {
      input = !input;
      if (input && cursor == null) {
        var s = score!;
        var e = sel == null ? null : s.find(sel!);
        var p = alone ?? s.parts.first.id;
        cursor = e != null
            ? (
                part: e.part,
                staff: e.staff,
                bar: e.bar,
                at: s.timeOf(sel!),
                voice: voice
              )
            : (part: p, staff: 0, bar: 0, at: 0.0, voice: voice);
      }
    });
  }

  // ------------------------------------------------------------- playing

  void togglePlay() {
    if (c.playing) {
      c.pause();
    } else {
      c.frame = 0;
      c.play();
    }
    setState(() {});
  }

  /// _sounding is what is sounding and where, while it plays.
  (Set<String>, ({int bar, double at})?) _sounding(MusicScore s) {
    if (!c.playing) return (const {}, null);
    var seconds = c.frame / math.max(1, c.document.frameRate);
    var order = s.playOrder();
    var place = s.placeAt(order, seconds);
    if (place == null) return (const {}, null);
    var ids = <String>{};
    for (var p in s.parts) {
      for (var n in _notesOf(s, p.id)) {
        if (n.note.start <= seconds && n.note.end > seconds) ids.add(n.event);
      }
    }
    return (ids, (bar: place.bar, at: place.at));
  }

  final Map<String, List<ScoreNote>> _notes = {};
  MusicScore? _notesFor;
  List<ScoreNote> _notesOf(MusicScore s, String part) {
    if (!identical(_notesFor, s)) {
      _notes.clear();
      _notesFor = s;
    }
    return _notes[part] ??= s.partNotes(part);
  }

  // ------------------------------------------------------------- the page

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var s = score;
    if (s == null) {
      return Material(
          color: colors.surface,
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("That score is no longer here.",
                style: TextStyle(color: colors.onSurface)),
            const SizedBox(height: 12),
            StudioPill(
                label: "Back to the canvas",
                filled: true,
                onTap: widget.onDone),
          ])));
    }
    if (sel != null && s.find(sel!) == null) sel = null;
    if (alone != null && s.partById(alone!) == null) alone = null;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: Material(
        color: colors.surface,
        child: Column(children: [
          _topBar(context, s),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          _toolbar(context, s),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                  width: 220,
                  color: colors.surfaceContainerLow,
                  child: _instruments(context, s)),
              Expanded(child: _paper(context, s)),
              Container(
                  width: 330,
                  color: colors.surfaceContainerLow,
                  child: _side(context, s)),
            ]),
          ),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          _status(context, s),
        ]),
      ),
    );
  }

  Widget _topBar(BuildContext context, MusicScore s) {
    final colors = ThemeNotifier.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Text("Score Studio",
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.onSurface)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(s.title.isEmpty ? "Untitled score" : s.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
        ),
        StudioPill(
            key: const ValueKey("scorePlay"),
            label: c.playing ? "■ Stop" : "▶ Play",
            selected: c.playing,
            tooltip: "Every part, from its channel (Space)",
            onTap: togglePlay),
        const SizedBox(width: 8),
        StudioPill(
            key: const ValueKey("scoreDone"),
            label: "Done",
            filled: true,
            onTap: widget.onDone),
      ]),
    );
  }

  Widget _tool(BuildContext context,
      {required Widget child,
      required bool on,
      required VoidCallback onTap,
      required String tip,
      Key? key}) {
    final colors = ThemeNotifier.of(context).colors;
    return Tooltip(
      message: tip,
      child: Material(
        key: key,
        color: on
            ? colors.primary.withValues(alpha: 0.18)
            : colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
                color: on ? colors.primary : colors.outlineVariant,
                width: on ? 1.5 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(width: 34, height: 32, child: Center(child: child)),
        ),
      ),
    );
  }

  /// _music is a Bravura glyph in a toolbar button, its baseline at
  /// [baseline] of the button's height: drawn, not set as text, so that no
  /// text size can push a quaver's flag out of the top (Ken, 2026-11-14).
  Widget _music(BuildContext context, int code,
          {double size = 18, double baseline = 0.78}) =>
      CustomPaint(
          size: const Size(34, 32),
          painter: _GlyphPainter(code, size, baseline,
              ThemeNotifier.of(context).colors.onSurface));

  Widget _toolbar(BuildContext context, MusicScore s) {
    final colors = ThemeNotifier.of(context).colors;
    var e = sel == null ? null : s.event(sel!);
    Widget gap() => const SizedBox(width: 10);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          StudioPill(
              key: const ValueKey("scoreInput"),
              label: "Note input  N",
              selected: input,
              tooltip: "Type A to G to write, a number for its value",
              onTap: toggleInput),
          gap(),
          for (var (v, name, code, key) in scoreDurations) ...[
            _tool(context,
                key: ValueKey("scoreValue-$v"),
                on: (input ? value : e?.value ?? value) == v,
                tip: "$name ($key)",
                onTap: () => pickValue(v),
                child: _music(context, code)),
            const SizedBox(width: 4),
          ],
          _tool(context,
              key: const ValueKey("scoreDot"),
              on: (input ? dots : e?.dots ?? dots) > 0,
              tip: "Dotted (.)",
              onTap: toggleDot,
              child: Text("•",
                  style: TextStyle(fontSize: 18, color: colors.onSurface))),
          const SizedBox(width: 4),
          _tool(context,
              key: const ValueKey("scoreRest"),
              on: false,
              tip: "A rest (0)", onTap: () {
            if (input && cursor != null) {
              enter(const []);
            } else if (sel != null) {
              edit(s.deleteEvent(sel!));
            }
          }, child: _music(context, 0xE4E5, size: 20, baseline: 0.5)),
          const SizedBox(width: 4),
          _tool(context,
              key: const ValueKey("scoreTie"),
              on: e?.tie ?? false,
              tip: "Tie to the next (T)", onTap: () {
            if (sel != null) edit(s.toggleTie(sel!));
          },
              child: Text("⁀",
                  style: TextStyle(fontSize: 18, color: colors.onSurface))),
          gap(),
          for (var (alter, code, name) in [
            (-1, 0xE260, "Flat"),
            (0, 0xE261, "Natural"),
            (1, 0xE262, "Sharp"),
          ]) ...[
            _tool(context,
                key: ValueKey("scoreAlter-$alter"),
                on: false,
                tip: name, onTap: () {
              if (sel != null) edit(s.setAlter(sel!, alter));
            }, child: _music(context, code, size: 20, baseline: 0.62)),
            const SizedBox(width: 4),
          ],
          gap(),
          for (var v = 0; v < 4; v++) ...[
            _tool(context,
                key: ValueKey("scoreVoice-$v"),
                on: voice == v,
                tip: "Voice ${v + 1}",
                onTap: () => setState(() {
                      voice = v;
                      if (cursor case var cur?) {
                        cursor = (
                          part: cur.part,
                          staff: cur.staff,
                          bar: cur.bar,
                          at: cur.at,
                          voice: v
                        );
                      }
                    }),
                child: Text("${v + 1}",
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: colors.onSurface))),
            const SizedBox(width: 4),
          ],
          // On the note picked: a chord symbol or a lyric typed on the
          // score, a strum turned down or up.
          if (e != null && sel != null) ...[
            gap(),
            StudioPill(
                key: const ValueKey("scoreTypeChord"),
                label: "Chord",
                tooltip: "Type its chord symbol on the score (⌘K)",
                onTap: () => startTyping("ch", sel!)),
            const SizedBox(width: 4),
            if (!e.isRest && !e.slash)
              StudioPill(
                  key: const ValueKey("scoreTypeLyric"),
                  label: "Lyric",
                  tooltip: "Type its words on the score (⌘L); space or a "
                      "hyphen moves on to the next note",
                  onTap: () => startTyping("lyr", sel!)),
            if (e.slash) ...[
              StudioPill(
                  key: const ValueKey("scoreStrumDown"),
                  label: "⊓ Down",
                  selected: e.strum == Strum.down,
                  onTap: () => edit(s.setStrum(sel!, Strum.down))),
              const SizedBox(width: 4),
              StudioPill(
                  key: const ValueKey("scoreStrumUp"),
                  label: "V Up",
                  selected: e.strum == Strum.up,
                  onTap: () => edit(s.setStrum(sel!, Strum.up))),
            ],
          ],
          gap(),
          _tool(context,
              key: const ValueKey("scoreUndo"),
              on: false,
              tip: "Undo (⌘Z)",
              onTap: c.undo,
              child: Icon(Icons.undo, size: 18, color: colors.onSurface)),
          const SizedBox(width: 4),
          _tool(context,
              key: const ValueKey("scoreRedo"),
              on: false,
              tip: "Redo (⇧⌘Z)",
              onTap: c.redo,
              child: Icon(Icons.redo, size: 18, color: colors.onSurface)),
        ]),
      ),
    );
  }

  Widget _instruments(BuildContext context, MusicScore s) {
    final colors = ThemeNotifier.of(context).colors;
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      const StudioPartHeading("Instruments", first: true),
      for (var p in s.parts)
        StudioPartRow(
          id: p.id,
          name: p.name,
          keyPrefix: "scorePart",
          changed: false,
          selected: alone == p.id,
          onTap: () => setState(() => alone = alone == p.id ? null : p.id),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: PopupMenuButton<String>(
          key: const ValueKey("scoreAddPart"),
          tooltip: "Add an instrument",
          onSelected: (id) => edit(s.addPart(id)),
          itemBuilder: (context) => [
            for (var i in scoreInstruments)
              PopupMenuItem(value: i.id, child: Text(i.name)),
          ],
          child: const IgnorePointer(
              child: StudioPill(label: "+ Instrument", onTap: _none)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Text(
            "Each instrument plays on a channel of its own, its notes the "
            "score's. Click one to see its part alone.",
            style: TextStyle(
                fontSize: 12, height: 1.45, color: colors.onSurfaceVariant)),
      ),
      if (alone != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: StudioPill(
              key: const ValueKey("scoreFullScore"),
              label: "Full score",
              onTap: () => setState(() => alone = null)),
        ),
    ]);
  }

  static void _none() {}

  Widget _paper(BuildContext context, MusicScore s) {
    final colors = ThemeNotifier.of(context).colors;
    var es = _layout(s);
    var (playing, playhead) = _sounding(s);
    var state = ScorePaintState(
        playing: playing,
        picked: {if (sel != null) sel!},
        cursor: input && cursor != null
            ? (
                part: cursor!.part,
                staff: cursor!.staff,
                bar: cursor!.bar,
                at: cursor!.at
              )
            : null,
        pickedMark: _markPick,
        playhead: playhead);
    return Container(
      color: colors.surfaceContainerLowest,
      child: LayoutBuilder(builder: (context, box) {
        var scale = _scale = math.min(
            1.6, math.max(0.5, (box.maxWidth - 32) / es.options.width));
        Offset toScore(Offset local) => local / scale;
        var typing = _typing == null ? null : _typingPlace(s, es);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Stack(clipBehavior: Clip.none, children: [
              // A press on a marking (or a picked one's handle) is a drag
              // from the start, so the page's scroll cannot take it; one
              // that does not move is a click after all (see _dragEnd).
              RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  _MarkDrag: GestureRecognizerFactoryWithHandlers<_MarkDrag>(
                      () => _MarkDrag(), (r) {
                    r.dragStartBehavior = DragStartBehavior.down;
                    r.grabs = (local) => _grabs(es, toScore(local));
                    r.onStart = (d) {
                      _pressGlobal = d.globalPosition;
                      _dragStart(s, es, toScore(d.localPosition));
                    };
                    r.onUpdate = (d) => _dragMove(es, toScore(d.localPosition));
                    r.onEnd = (_) => _dragEnd(es);
                  }),
                },
                child: GestureDetector(
                  key: const ValueKey("scorePaper"),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) =>
                      _tap(s, es, toScore(d.localPosition), d.globalPosition),
                  child: Container(
                    decoration: BoxDecoration(boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 6)),
                    ]),
                    child: CustomPaint(
                      size: Size(es.options.width * scale, es.height * scale),
                      painter: _ScorePainter(es, state, scale),
                    ),
                  ),
                ),
              ),
              // A lyric or chord being typed, on the score where it goes.
              if (typing != null)
                Positioned(
                  left: typing.dx * scale,
                  top: typing.dy * scale,
                  child: _inlineEditor(context, s, scale),
                ),
            ]),
          ),
        );
      }),
    );
  }

  // ----------------------------------------- typing on the score

  /// _typing is a lyric (kind "lyr", its verse) or a chord symbol (kind
  /// "ch") being typed on the score, on event [event].
  ({String kind, String event, int verse})? _typing;
  late final _typed = TextEditingController();
  late final _typedFocus = FocusNode(debugLabel: "scoreInline");

  /// _typingPlace is where, on the engraving, the text being typed goes.
  Offset? _typingPlace(MusicScore s, EngravedScore es) {
    var t = _typing!;
    var at = s.find(t.event);
    var ev = es.hits
        .where((h) => h.kind == ScoreHitKind.event && h.event == t.event)
        .firstOrNull;
    if (at == null || ev == null) return null;
    var staff = es.hits
        .where((h) =>
            h.kind == ScoreHitKind.staff &&
            h.part == at.part &&
            h.staff == at.staff &&
            h.bar == at.bar)
        .firstOrNull;
    if (staff == null) return null;
    var sp = es.options.space;
    var bottom = staff.bottom;
    if (t.kind == "ch") {
      var strum = s.partById(at.part)!.strum;
      return Offset(ev.rect.left - sp * 0.4,
          bottom - sp * 4 - sp * (strum ? 5.0 : 3.2) - sp * 0.3);
    }
    return Offset(ev.rect.left - sp * 1.4,
        bottom + sp * 4.6 + t.verse * sp * 2.3 - sp * 0.3);
  }

  /// startTyping opens the lyric ([kind] "lyr", [verse]) or chord ("ch")
  /// editor on event [id], with what it says now.
  void startTyping(String kind, String id, {int verse = 0}) {
    var s = score;
    var e = s?.event(id);
    if (e == null) return;
    setState(() {
      input = false;
      sel = id;
      _markPick = null;
      _typing = (kind: kind, event: id, verse: verse);
      _typed.text = kind == "ch"
          ? e.chord ?? ""
          : verse < e.lyrics.length
              ? e.lyrics[verse]
              : "";
      _typed.selection =
          TextSelection(baseOffset: 0, extentOffset: _typed.text.length);
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _typedFocus.requestFocus());
  }

  /// _commitTyped writes what is typed into the score.
  void _commitTyped(String text) {
    var t = _typing;
    var s = score;
    if (t == null || s == null || s.event(t.event) == null) return;
    var e = s.event(t.event)!;
    if (t.kind == "ch") {
      if ((e.chord ?? "") != text.trim()) edit(s.setChord(t.event, text));
    } else {
      var was = t.verse < e.lyrics.length ? e.lyrics[t.verse] : "";
      if (was != text.trim()) edit(s.setLyric(t.event, t.verse, text.trim()));
    }
  }

  /// _typeOn writes what is typed and moves to the next note (a lyric) or
  /// event (a chord) in the staff, as MuseScore's space and hyphen do.
  void _typeOn(String text) {
    _commitTyped(text);
    var t = _typing!;
    var next = nextEvent(score!, t.event, notes: t.kind != "ch");
    if (next == null) {
      _stopTyping(commit: false);
      return;
    }
    startTyping(t.kind, next, verse: t.verse);
  }

  void _stopTyping({bool commit = true}) {
    if (_typing == null) return;
    if (commit) _commitTyped(_typed.text);
    setState(() => _typing = null);
    _focus.requestFocus();
  }

  Widget _inlineEditor(BuildContext context, MusicScore s, double scale) {
    final colors = ThemeNotifier.of(context).colors;
    var chord = _typing!.kind == "ch";
    var sp = 8.0 * scale;
    return Focus(
      onKeyEvent: (node, ev) {
        if (ev is KeyDownEvent && ev.logicalKey == LogicalKeyboardKey.escape) {
          _stopTyping(commit: false);
          return KeyEventResult.handled;
        }
        if (ev is KeyDownEvent && ev.logicalKey == LogicalKeyboardKey.tab) {
          _typeOn(_typed.text);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        key: const ValueKey("scoreInline"),
        width: sp * (chord ? 9 : 8),
        height: sp * 2.6,
        child: TextField(
          controller: _typed,
          focusNode: _typedFocus,
          textAlign: chord ? TextAlign.left : TextAlign.center,
          style: TextStyle(
              fontSize: sp * (chord ? 1.6 : 1.45),
              fontWeight: chord ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF1D1C1A)),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: sp * 0.4, vertical: sp * 0.4),
            filled: true,
            fillColor: const Color(0xFFFFFFFF),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.primary, width: 1.5)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.primary, width: 2)),
          ),
          onChanged: (t) {
            // A space moves on; so, for a lyric, does a hyphen, which is
            // kept: the word goes on into the next note.
            if (t.endsWith(" ")) {
              _typeOn(t.trim());
            } else if (!chord && t.endsWith("-") && t.trim().length > 1) {
              _typeOn(t.trim());
            }
          },
          onSubmitted: (t) => _stopTyping(),
          onTapOutside: (_) => _stopTyping(),
        ),
      ),
    );
  }

  // ----------------------------------------- pressing the paper

  /// _markPick is the marking picked (a dynamic, a hairpin): drawn with the
  /// handles that size or stretch it.
  ({String kind, String id})? _markPick;

  DateTime _lastTap = DateTime(0);
  Offset _lastTapAt = Offset.zero;

  void _tap(MusicScore s, EngravedScore es, Offset p, Offset global) {
    if (_typing != null) _stopTyping();
    _focus.requestFocus();
    var now = DateTime.now();
    var twice = now.difference(_lastTap) < const Duration(milliseconds: 350) &&
        (p - _lastTapAt).distance < es.options.space;
    _lastTap = now;
    _lastTapAt = p;
    var mark = es.markAt(p);
    if (mark != null && mark.event != null) {
      var kind = mark.mark!;
      var id = mark.event!;
      if (twice) {
        if (kind == MarkKind.dynamic) {
          _redrawDynamic(s, id, global);
        } else if (kind == MarkKind.chord) {
          startTyping("ch", id);
        } else if (kind.startsWith("lyr")) {
          startTyping("lyr", id, verse: int.tryParse(kind.substring(3)) ?? 0);
        }
        return;
      }
      if (kind == MarkKind.strum) {
        // A click turns a strum the other way.
        var e = s.event(id);
        if (e != null) {
          edit(s.setStrum(id, e.strum == Strum.up ? Strum.down : Strum.up));
        }
        return;
      }
      if (kind == MarkKind.dynamic || kind == MarkKind.hairpin) {
        setState(() {
          _markPick = (kind: kind, id: id);
          if (kind == MarkKind.dynamic) sel = id;
        });
        return;
      }
    }
    if (_markPick != null) setState(() => _markPick = null);
    if (twice) {
      // Twice on the chord line over a note, or the lyric line under one:
      // type there.
      if (_lineAt(s, es, p) case (var kind, var id, var verse)?) {
        startTyping(kind, id, verse: verse);
        return;
      }
    }
    var area = es.staffAt(p);
    if (input && area != null) {
      // A note where it is clicked, on the grid of the value chosen.
      var grid = math.min(1.0, value);
      var t = area.timeAt(p.dx, s.barQuarters(area.bar), grid: grid);
      var stepped = area.stepAt(p.dy, es.options.space);
      var fifths = s.keyAt(area.bar);
      var letter = stepped % 7;
      var pitch = Pitch(letter, stepped ~/ 7 - 1, keyAlter(letter, fifths));
      setState(() => cursor = (
            part: area.part,
            staff: area.staff,
            bar: area.bar,
            at: t,
            voice: voice
          ));
      enter([pitch]);
      return;
    }
    var hit = es.eventAt(p);
    setState(() {
      if (hit == null) {
        sel = null;
        return;
      }
      sel = hit.event;
      cursor = (
        part: hit.part,
        staff: hit.staff,
        bar: hit.bar,
        at: hit.at,
        voice: s.event(hit.event!)?.voice ?? 0
      );
    });
    if (hit != null) {
      var e = s.event(hit.event!);
      if (e != null && !e.isRest) {
        hear(hit.part, e.pitches);
        if (e.pitches.isNotEmpty) last = e.pitches.last;
      }
    }
  }

  /// _lineAt is the chord line over a staff ("ch") or a lyric line under it
  /// ("lyr", its verse) at [p], with the event nearest across: a note for a
  /// lyric, anything for a chord.
  (String, String, int)? _lineAt(MusicScore s, EngravedScore es, Offset p) {
    var sp = es.options.space;
    for (var h in es.hits) {
      if (h.kind != ScoreHitKind.staff) continue;
      if (p.dx < h.rect.left || p.dx > h.rect.right) continue;
      var top = h.bottom - sp * 4;
      var chordLine = p.dy >= top - sp * 6.5 && p.dy < top - sp * 0.6;
      var lyricLine = p.dy > h.bottom + sp * 3.8 &&
          p.dy < h.bottom + sp * (4.6 + 2.3 * (s.verses + 1));
      if (!chordLine && !lyricLine) continue;
      String? best;
      var bestD = double.infinity;
      for (var e in es.hits) {
        if (e.kind != ScoreHitKind.event ||
            e.part != h.part ||
            e.staff != h.staff ||
            e.bar != h.bar) {
          continue;
        }
        if (lyricLine && (s.event(e.event!)?.isRest ?? true)) continue;
        var d = (e.rect.center.dx - p.dx).abs();
        if (d < bestD) {
          bestD = d;
          best = e.event;
        }
      }
      if (best == null) continue;
      if (chordLine) return ("ch", best, 0);
      var verse = ((p.dy - (h.bottom + sp * 4.6)) / (sp * 2.3)).floor();
      return ("lyr", best, verse.clamp(0, s.verses));
    }
    return null;
  }

  /// _redrawDynamic offers the dynamics in place of event [id]'s.
  Future<void> _redrawDynamic(MusicScore s, String id, Offset global) async {
    var picked = await showMenu<Dynamic>(
      context: context,
      position:
          RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        for (var d in Dynamic.values)
          PopupMenuItem(
              key: ValueKey("scoreDynamicMenu-${d.name}"),
              value: d,
              child: Text(d.name,
                  style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700))),
      ],
    );
    var now = score;
    if (picked == null || now == null || now.event(id) == null) return;
    edit(now.withEvent(id, (e) => e.copyWith(dyn: picked)));
  }

  // ----------------------------------------- dragging on the paper

  /// _handle is a picked marking's handle being dragged: which (0 a
  /// dynamic's corner or a hairpin's start, 1 a hairpin's end), and the
  /// marking's rect and size when it began.
  int? _handle;
  Rect _handleRect = Rect.zero;
  double _handleWas = 1;

  /// _grabs is whether a press at [p] is on a marking, or on the picked
  /// marking's handle: a drag to claim at once.
  bool _grabs(EngravedScore es, Offset p) {
    if (es.markAt(p) != null) return true;
    if (_markPick case var pm?) {
      var hit = es.hits
          .where((h) =>
              h.kind == ScoreHitKind.mark &&
              h.mark == pm.kind &&
              h.event == pm.id)
          .firstOrNull;
      if (hit != null) {
        var sp = es.options.space;
        return scoreMarkHandles(hit, sp)
            .any((h) => (h - p).distance < sp * 1.2);
      }
    }
    return false;
  }

  Offset _pressGlobal = Offset.zero, _pressAt = Offset.zero;
  double _travelled = 0;

  void _dragStart(MusicScore s, EngravedScore es, Offset p) {
    _pressAt = p;
    _travelled = 0;
    if (_typing != null) _stopTyping();
    var sp = es.options.space;
    // A picked marking's handle.
    if (_markPick case var pm?) {
      var hit = es.hits
          .where((h) =>
              h.kind == ScoreHitKind.mark &&
              h.mark == pm.kind &&
              h.event == pm.id)
          .firstOrNull;
      if (hit != null) {
        var handles = scoreMarkHandles(hit, sp);
        for (var (i, h) in handles.indexed) {
          if ((h - p).distance < sp * 1.2) {
            _handle = i;
            _drag = hit;
            _dragFrom = p;
            _handleRect = hit.rect;
            _handleWas = s.event(pm.id)?.sizeOf(MarkKind.dynamic) ?? 1;
            c.beginInteraction();
            return;
          }
        }
      }
    }
    var m = es.markAt(p);
    if (m == null) return;
    _handle = null;
    _drag = m;
    _dragFrom = p;
    _dragWas = switch (m) {
      _ when m.mark == MarkKind.hairpin =>
        s.spanners.where((x) => x.id == m.event).firstOrNull?.offset ??
            Offset.zero,
      ScoreHit(event: var id?) => s.event(id)?.offsets[m.mark] ?? Offset.zero,
      _ when m.mark == MarkKind.tempo =>
        s.offsets[MarkKind.tempo] ?? Offset.zero,
      _ => s.bars[m.bar].offsets[m.mark] ?? Offset.zero,
    };
    c.beginInteraction();
  }

  void _dragMove(EngravedScore es, Offset p) {
    _travelled = math.max(_travelled, (p - _pressAt).distance);
    var m = _drag;
    var s = score;
    if (m == null || s == null) return;
    var kind = m.mark!;
    if (_handle case var h?) {
      if (kind == MarkKind.dynamic) {
        // The corner pulled out or in: the dynamic as much bigger.
        var from = (_dragFrom - _handleRect.topLeft).distance;
        var to = (p - _handleRect.topLeft).distance;
        edit(s.resizedEventMark(
            m.event!, MarkKind.dynamic, _handleWas * to / math.max(1, from)));
      } else if (kind == MarkKind.hairpin) {
        // An end pulled to another note of its staff.
        if (_noteTimeAt(s, es, m, p) case var t?) {
          edit(s.withSpanner(m.event!, (sn) {
            var start = h == 0 ? t : sn.from, end = h == 0 ? sn.to : t;
            bool before(ScoreTime a, ScoreTime b) =>
                a.bar < b.bar || (a.bar == b.bar && a.at <= b.at);
            return before(start, end) ? sn.copyWith(from: start, to: end) : sn;
          }));
        }
      }
      return;
    }
    var to = _dragWas + (p - _dragFrom);
    to = Offset(to.dx.roundToDouble(), to.dy.roundToDouble());
    edit(kind == MarkKind.hairpin
        ? s.withSpanner(m.event!, (sn) => sn.copyWith(offset: to))
        : m.event != null
            ? s.movedEventMark(m.event!, kind, to)
            : kind == MarkKind.tempo
                ? s.movedScoreMark(kind, to)
                : s.movedBarMark(m.bar, kind, to));
  }

  /// _noteTimeAt is the note start nearest [p] across, in the staff of
  /// hairpin [m].
  ScoreTime? _noteTimeAt(MusicScore s, EngravedScore es, ScoreHit m, Offset p) {
    ScoreTime? best;
    var bestD = double.infinity;
    for (var h in es.hits) {
      if (h.kind != ScoreHitKind.event ||
          h.part != m.part ||
          h.staff != m.staff) {
        continue;
      }
      var d = (h.rect.center.dx - p.dx).abs() +
          (h.rect.center.dy - p.dy).abs() * 0.2;
      if (d < bestD) {
        bestD = d;
        best = (bar: h.bar, at: h.at);
      }
    }
    return best;
  }

  void _dragEnd(EngravedScore es) {
    var was = _drag;
    _drag = null;
    _handle = null;
    if (was == null) return;
    c.endInteraction();
    // A press that did not travel is a click: on a strum mark, a dynamic.
    if (_travelled < es.options.space * 0.4) {
      var s = score;
      if (s != null) _tap(s, es, _pressAt, _pressGlobal);
    }
  }

  // ------------------------------------------------------------- the side

  Widget _side(BuildContext context, MusicScore s) {
    return ListView(
      key: const ValueKey("scoreSide"),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _picked(context, s),
        const StudioLabel("Palettes"),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var p in ScorePalette.values)
            StudioPill(
                key: ValueKey("scorePalette-${p.name}"),
                label: p.label,
                selected: palette == p,
                onTap: () => setState(() => palette = p)),
        ]),
        const SizedBox(height: 10),
        ..._palette(context, s),
        _scoreSettings(context, s),
      ],
    );
  }

  Widget _picked(BuildContext context, MusicScore s) {
    final colors = ThemeNotifier.of(context).colors;
    var at = sel == null ? null : s.find(sel!);
    var e = sel == null ? null : s.event(sel!);
    var says = e == null || at == null
        ? "Click a note to pick it. With Note input on, type A to G to write, "
            "and a number for its value: 7 whole, 6 half, 5 crotchet, "
            "4 quaver, 3 semiquaver."
        : "${s.partById(at.part)!.name} · bar ${at.bar + 1} · beat "
            "${_beat(s.timeOf(sel!))} · "
            "${e.isRest ? "a rest" : e.slash ? "a strum" : e.pitches.join(" ")}";
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StudioPanelHead(
            title: e == null
                ? "Nothing picked"
                : e.isRest
                    ? "Rest"
                    : "Note",
            says: says),
        if (e != null && at != null && !e.isRest) ...[
          const StudioLabel("Lyrics"),
          for (var v = 0; v < s.verses; v++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _field(context,
                  key: ValueKey("scoreLyric-$v"),
                  label: "Verse ${v + 1}",
                  value: v < e.lyrics.length ? e.lyrics[v] : "",
                  onDone: (t) => edit(s.setLyric(sel!, v, t))),
            ),
          _field(context,
              key: const ValueKey("scoreChord"),
              label: "Chord",
              value: e.chord ?? "",
              onDone: (t) => edit(s.setChord(sel!, t))),
        ],
        Divider(height: 24, color: colors.outlineVariant),
      ]),
    );
  }

  String _beat(double t) {
    var b = t + 1;
    return b == b.roundToDouble() ? "${b.round()}" : b.toStringAsFixed(2);
  }

  Widget _field(BuildContext context,
      {required Key key,
      required String label,
      required String value,
      required ValueChanged<String> onDone}) {
    final colors = ThemeNotifier.of(context).colors;
    return Row(children: [
      SizedBox(
          width: 86,
          child: Text(label,
              style:
                  TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant))),
      Expanded(
        child: _TextBox(key: key, value: value, onDone: onDone),
      ),
    ]);
  }

  Widget _button(String key, String label, VoidCallback? onTap,
          {bool on = false}) =>
      StudioPill(
          key: ValueKey("scoreDo-$key"),
          label: label,
          selected: on,
          onTap: onTap);

  List<Widget> _palette(BuildContext context, MusicScore s) {
    final colors = ThemeNotifier.of(context).colors;
    var at = sel == null ? null : s.find(sel!);
    var e = sel == null ? null : s.event(sel!);
    var bar = at?.bar ?? cursor?.bar ?? 0;
    VoidCallback? onSel(MusicScore Function(String id) f) =>
        sel == null ? null : () => edit(f(sel!));
    Widget grid(List<Widget> items) =>
        Wrap(spacing: 6, runSpacing: 6, children: items);
    Widget note(String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, height: 1.45, color: colors.onSurfaceVariant)));
    switch (palette) {
      case ScorePalette.clefs:
        var place = at ??
            (cursor == null
                ? null
                : (part: cursor!.part, staff: cursor!.staff, bar: 0, index: 0));
        return [
          grid([
            for (var cl in Clef.values)
              _button(
                  "clef-${cl.name}",
                  cl.label,
                  place == null
                      ? null
                      : () => edit(s.setClef(place.part, place.staff, cl)),
                  on: place != null &&
                      s.partById(place.part)!.staves[place.staff].clef == cl),
          ]),
          note("A clef for the staff of the note picked."),
        ];
      case ScorePalette.keys:
        const names = [
          "C♭",
          "G♭",
          "D♭",
          "A♭",
          "E♭",
          "B♭",
          "F",
          "C",
          "G",
          "D",
          "A",
          "E",
          "B",
          "F♯",
          "C♯"
        ];
        return [
          grid([
            for (var f = -7; f <= 7; f++)
              _button("key-$f", names[f + 7], () {
                edit(bar == 0
                    ? s.copyWith(fifths: f)
                    : s.withBarInfo(bar, (b) => b.copyWith(key: f)));
              }, on: s.keyAt(bar) == f),
          ]),
          note(bar == 0
              ? "The key of the whole score."
              : "A change of key at bar ${bar + 1}."),
        ];
      case ScorePalette.time:
        return [
          grid([
            for (var (b, u) in const [
              (2, 4),
              (3, 4),
              (4, 4),
              (5, 4),
              (6, 8),
              (9, 8),
              (12, 8),
              (2, 2)
            ])
              _button("time-$b-$u", "$b/$u", () {
                edit(bar == 0
                    ? s.copyWith(beats: b, beatUnit: u)
                    : s.withBarInfo(bar, (x) => x.copyWith(time: (b, u))));
              }, on: s.timeAt(bar) == (b, u)),
          ]),
          note("Changing the time keeps the notes; fill or trim bars to fit."),
        ];
      case ScorePalette.dynamics:
        return [
          grid([
            for (var d in Dynamic.values)
              _button(
                  "dyn-${d.name}", d.name, onSel((id) => s.setDynamic(id, d)),
                  on: e?.dyn == d),
            _button("cresc", "cresc. <",
                at == null ? null : () => _hairpin(s, SpannerKind.crescendo)),
            _button("dim", "dim. >",
                at == null ? null : () => _hairpin(s, SpannerKind.diminuendo)),
          ]),
          note("Dynamics play: p is softer than f, and a hairpin swells or "
              "fades the notes under it."),
        ];
      case ScorePalette.articulations:
        return [
          grid([
            for (var a in Articulation.values)
              _button("art-${a.name}", a.label,
                  onSel((id) => s.toggleArticulation(id, a)),
                  on: e?.articulations.contains(a) ?? false),
          ]),
          note(
              "Staccato plays short, tenuto full, accents harder, a fermata held."),
        ];
      case ScorePalette.lines:
        return [
          grid([
            _button("slur", "Slur", at == null ? null : () => _slur(s)),
            _button("cresc2", "Crescendo",
                at == null ? null : () => _hairpin(s, SpannerKind.crescendo)),
            _button("dim2", "Diminuendo",
                at == null ? null : () => _hairpin(s, SpannerKind.diminuendo)),
          ]),
          note("From the note picked to the next few in its staff."),
        ];
      case ScorePalette.text:
        var info = s.bars[bar];
        return [
          _field(context,
              key: const ValueKey("scoreRehearsal"),
              label: "Rehearsal",
              value: info.mark,
              onDone: (t) =>
                  edit(s.withBarInfo(bar, (b) => b.copyWith(mark: t.trim())))),
          const SizedBox(height: 6),
          _field(context,
              key: const ValueKey("scoreVerses"),
              label: "Verses",
              value: "${s.verses}",
              onDone: (t) =>
                  edit(s.copyWith(verses: int.tryParse(t) ?? s.verses))),
          note("Chord symbols and lyrics are on the note picked, above. The "
              "rehearsal mark is on bar ${bar + 1}. Every marking can be "
              "dragged on the paper."),
        ];
      case ScorePalette.repeats:
        var info = s.bars[bar];
        MusicScore set(BarInfo Function(BarInfo b) f) => s.withBarInfo(bar, f);
        return [
          grid([
            _button("repStart", "Start repeat",
                () => edit(set((b) => b.copyWith(repeatStart: !b.repeatStart))),
                on: info.repeatStart),
            _button(
                "repEnd",
                "End repeat",
                () => edit(
                    set((b) => b.copyWith(repeatEnd: b.repeatEnd > 0 ? 0 : 2))),
                on: info.repeatEnd > 0),
            _button(
                "end1",
                "1st ending",
                () => edit(set((b) => b.copyWith(
                    endings: b.endings.contains(1) ? const [] : const [1]))),
                on: info.endings.contains(1)),
            _button(
                "end2",
                "2nd ending",
                () => edit(set((b) => b.copyWith(
                    endings: b.endings.contains(2) ? const [] : const [2]))),
                on: info.endings.contains(2)),
            for (var j in Jump.values.skip(1))
              _button(
                  "jump-${j.name}",
                  j.label,
                  () => edit(set(
                      (b) => b.copyWith(jump: b.jump == j ? Jump.none : j))),
                  on: info.jump == j),
            _button("segno", "Segno",
                () => edit(set((b) => b.copyWith(segno: !b.segno))),
                on: info.segno),
            _button("coda", "Coda",
                () => edit(set((b) => b.copyWith(coda: !b.coda))),
                on: info.coda),
            _button("toCoda", "To Coda",
                () => edit(set((b) => b.copyWith(toCoda: !b.toCoda))),
                on: info.toCoda),
            _button("fine", "Fine",
                () => edit(set((b) => b.copyWith(fine: !b.fine))),
                on: info.fine),
            _button(
                "break",
                "Line break",
                () => edit(set((b) => b.copyWith(
                    breakAfter: b.breakAfter == BarBreak.none
                        ? BarBreak.system
                        : BarBreak.none))),
                on: info.breakAfter != BarBreak.none),
            _button("addBar", "+ Bar after", () => edit(s.insertBars(bar + 1))),
            _button("removeBar", "− This bar",
                s.barCount > 1 ? () => edit(s.removeBars(bar)) : null),
          ]),
          note("For bar ${bar + 1}. Play order: "
              "${s.playOrder().map((p) => p.bar + 1).join(" ")}"),
        ];
      case ScorePalette.strum:
        return [
          grid([
            _button("strumDown", "⊓ Down",
                onSel((id) => s.setStrum(id, Strum.down)),
                on: e?.strum == Strum.down),
            _button("strumUp", "V Up", onSel((id) => s.setStrum(id, Strum.up)),
                on: e?.strum == Strum.up),
            _button("strumPart", "+ Guitar (strum)",
                () => edit(s.addPart("guitarStrum"))),
          ]),
          note("A strum part is written as slashes: with Note input on, any "
              "letter writes a strum of the chord in force. It plays the "
              "chord symbol, low to high going down and high to low going up."),
        ];
    }
  }

  /// _hairpin puts a hairpin from the note picked to the end of its bar.
  void _hairpin(MusicScore s, SpannerKind kind) {
    var at = s.find(sel!)!;
    var from = s.timeOf(sel!);
    var end = s.barQuarters(at.bar);
    var last = 0.0;
    var t = 0.0;
    for (var e in s.partById(at.part)!.staves[at.staff].bars[at.bar]) {
      if (e.voice != s.event(sel!)!.voice) continue;
      if (t < end) last = t;
      t += e.quarters;
    }
    edit(s.addSpanner(kind, at.part, at.staff, (bar: at.bar, at: from),
        (bar: at.bar, at: math.max(from, last))));
  }

  /// _slur slurs the note picked to the next one in its voice.
  void _slur(MusicScore s) {
    var at = s.find(sel!)!;
    var st = s.partById(at.part)!.staves[at.staff];
    var v = s.event(sel!)!.voice;
    var found = false;
    for (var b = at.bar; b < st.bars.length; b++) {
      var t = 0.0;
      for (var e in st.bars[b]) {
        if (e.voice != v) continue;
        if (found && !e.isRest) {
          edit(s.addSpanner(SpannerKind.slur, at.part, at.staff,
              (bar: at.bar, at: s.timeOf(sel!)), (bar: b, at: t)));
          return;
        }
        if (e.id == sel) found = true;
        t += e.quarters;
      }
    }
  }

  Widget _scoreSettings(BuildContext context, MusicScore s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StudioLabel("Score"),
          for (var (key, label, value, set)
              in <(String, String, String, MusicScore Function(String))>[
            ("Title", "Title", s.title, (t) => s.copyWith(title: t)),
            (
              "Subtitle",
              "Subtitle",
              s.subtitle,
              (t) => s.copyWith(subtitle: t)
            ),
            (
              "Composer",
              "Composer",
              s.composer,
              (t) => s.copyWith(composer: t)
            ),
            ("Lyricist", "Words", s.lyricist, (t) => s.copyWith(lyricist: t)),
            (
              "TempoText",
              "Tempo word",
              s.tempoText,
              (t) => s.copyWith(tempoText: t)
            ),
            (
              "Tempo",
              "Tempo",
              "${s.tempo.round()}",
              (t) => s.copyWith(tempo: double.tryParse(t) ?? s.tempo)
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _field(context,
                  key: ValueKey("score$key"),
                  label: label,
                  value: value,
                  onDone: (t) => edit(set(t))),
            ),
        ],
      );

  Widget _status(BuildContext context, MusicScore s) {
    final colors = ThemeNotifier.of(context).colors;
    var style = TextStyle(
        fontSize: 11.5,
        color: colors.onSurfaceVariant,
        fontFamily: "RobotoMono");
    var name = scoreDurations.where((d) => d.$1 == value).firstOrNull?.$2 ?? "";
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(children: [
        Flexible(
          child: Text(
              "Note input: ${input ? "on" : "off"}   Value: $name${dots > 0 ? ", dotted" : ""}   "
              "Voice ${voice + 1}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Text(
              "N input · A–G write · ⇧A–G chord · 3–7 value · . dot · 0 rest · "
              "T tie · ↑↓ pitch · ⌥↑↓ step · ⌘↑↓ octave · Space play · ⌘Z undo",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: style),
        ),
      ]),
    );
  }
}

/// _MarkDrag is a pan that claims its pointer at once where [grabs] says
/// the press is on something to drag (a marking), so that the scroll the
/// paper is in never takes it.
class _MarkDrag extends PanGestureRecognizer {
  bool Function(Offset local)? grabs;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (grabs?.call(event.localPosition) ?? false) {
      resolve(GestureDisposition.accepted);
    }
  }
}

/// _GlyphPainter draws one Bravura glyph centred across its box, its
/// baseline a share of the way down.
class _GlyphPainter extends CustomPainter {
  final int code;
  final double size, baseline;
  final Color colour;
  _GlyphPainter(this.code, this.size, this.baseline, this.colour);

  @override
  void paint(Canvas canvas, Size box) {
    var t = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(code),
          style: TextStyle(
              fontFamily: "Bravura", fontSize: size, height: 1, color: colour)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    var base = t.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    t.paint(canvas,
        Offset((box.width - t.width) / 2, box.height * baseline - base));
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.code != code || old.colour != colour || old.size != size;
}

class _ScorePainter extends CustomPainter {
  final EngravedScore es;
  final ScorePaintState state;
  final double scale;
  _ScorePainter(this.es, this.state, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    paintScore(canvas, es, state: state);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScorePainter old) =>
      !identical(old.es, es) ||
      old.scale != scale ||
      old.state.playing.length != state.playing.length ||
      !old.state.playing.containsAll(state.playing) ||
      old.state.picked.join() != state.picked.join() ||
      old.state.cursor != state.cursor ||
      old.state.pickedMark != state.pickedMark ||
      old.state.playhead != state.playhead;
}

/// _TextBox is a text field that says what it holds when it is done with:
/// on Enter, or when it loses the focus.
class _TextBox extends StatefulWidget {
  final String value;
  final ValueChanged<String> onDone;
  const _TextBox({required this.value, required this.onDone, super.key});

  @override
  State<_TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<_TextBox> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text != widget.value) {
        widget.onDone(_text.text);
      }
    });
  }

  @override
  void didUpdateWidget(_TextBox old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        style: TextStyle(fontSize: 13, color: colors.onSurface),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          filled: true,
          fillColor: colors.surfaceContainerHigh,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.outlineVariant)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.outlineVariant)),
        ),
        onSubmitted: (t) => widget.onDone(t),
      ),
    );
  }
}
