part of 'instrument_editor.dart';

// The editor's playable keyboard: bend and mod wheels, octave, sustain, strike
// strength, chords and key letters over the keys, and how the keys, drum pads
// or neck are laid out and drawn. Part of instrument_editor.dart.

const _chords = <(String, List<int>)>[
  ("No chord", [0]),
  ("Major", [0, 4, 7]),
  ("Minor", [0, 3, 7]),
  ("Seventh", [0, 4, 7, 10]),
  ("Octave", [0, 12]),
];

/// _Keyboard is the editor's keyboard: bend and mod wheels, octave, sustain
/// pedal, strike strength, chord, hold and key letters; then the keys,
/// played with the pointer (lower on a key, harder) or the computer's keys.
class _Keyboard extends StatefulWidget {
  final CanvasController controller;
  final AudioElement element;
  const _Keyboard({required this.controller, required this.element, super.key});

  @override
  State<_Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<_Keyboard> {
  CanvasController get c => widget.controller;
  final FocusNode _focus = FocusNode(debugLabel: "instrumentKeys");

  /// _octave is the C the keys start from: 48 is C3.
  int _octave = 48;
  bool _byHeight = true;
  final int _velocity = 100;
  int _chord = 0;
  bool _hold = false;
  bool _sustain = false;

  /// _labels is what the keys show: 0 computer letters, 1 names, 2 nothing.
  int _labels = 0;

  final Map<int, List<int>> _held = {};

  final Map<int, FretPlace> _placed = {};

  /// _pressed is the key each pointer holds, by pointer: kept on the state,
  /// not in the build, so the release finds the key it played even after a
  /// rebuild, and the note does not keep sounding.
  final Map<int, int> _pressed = {};

  /// _typed is the key each computer key plays: let go, the same note stops,
  /// whatever the octave has become meanwhile.
  final Map<LogicalKeyboardKey, int> _typed = {};
  double _bend = 0.5, _mod = 0;

  @override
  void initState() {
    super.initState();
    // Focus gone, no key up comes: release what the computer keys hold.
    _focus.addListener(() {
      if (_focus.hasFocus) return;
      for (var k in [..._typed.values]) {
        _off(k);
      }
      _typed.clear();
    });
  }

  @override
  void dispose() {
    for (var k in [..._held.keys]) {
      _off(k, force: true);
    }
    if (_sustain) c.controlOn(widget.element, MidiControl.sustain, 0);
    _focus.dispose();
    super.dispose();
  }

  void _on(int key, int velocity) {
    if (_held.containsKey(key)) return;
    var notes = [for (var d in _chords[_chord].$2) key + d];
    for (var n in notes) {
      c.noteOn(widget.element, n,
          velocity: velocity, place: n == key ? _placed[key] : null);
    }
    setState(() => _held[key] = notes);
  }

  void _off(int key, {bool force = false}) {
    if (_hold && !force) return;
    var notes = _held.remove(key);
    if (notes == null) return;
    for (var n in notes) {
      c.noteOff(widget.element, n);
    }
    if (mounted && !force) setState(() {});
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    var ch = e.character?.toLowerCase() ?? e.logicalKey.keyLabel.toLowerCase();
    if (e is KeyDownEvent) {
      if (ch == "z") {
        setState(() => _octave = math.max(12, _octave - 12));
        return KeyEventResult.handled;
      }
      if (ch == "x") {
        setState(() => _octave = math.min(96, _octave + 12));
        return KeyEventResult.handled;
      }
    }
    // Let go: the note it started, found by the key, not worked out again.
    if (e is KeyUpEvent) {
      var was = _typed.remove(e.logicalKey);
      if (was == null) return KeyEventResult.ignored;
      _off(was);
      return KeyEventResult.handled;
    }
    var key = _keyFor(ch);
    if (key == null) return KeyEventResult.ignored;
    if (e is KeyDownEvent && !_typed.containsKey(e.logicalKey)) {
      _typed[e.logicalKey] = key;
      _on(key, _byHeight ? 100 : _velocity);
    }
    return KeyEventResult.handled;
  }

  /// _keyFor is the note computer key [ch] plays, or null: drum pads by their
  /// place along the row, anything else up from the octave's C.
  int? _keyFor(String ch) {
    var i = ch.length == 1 ? keyRow.indexOf(ch) : -1;
    if (i < 0) return null;
    var drums = widget.element.instrument?.look == InstrumentLook.drums;
    if (drums) return i < drumPads.length ? drumPads[i].$1 : null;
    return _octave + i;
  }

  /// _played is [child] played with the pointer, [hit] giving the key under
  /// a point and how hard it strikes there; let go or dragged off, the note
  /// stops.
  Widget _played(
          {required Key key,
          required (int, int)? Function(Offset) hit,
          required Widget child}) =>
      Listener(
        key: key,
        onPointerDown: (e) {
          _focus.requestFocus();
          var h = hit(e.localPosition);
          if (h == null) return;
          if (_hold && _held.containsKey(h.$1)) {
            _off(h.$1, force: true);
            setState(() {});
            return;
          }
          _pressed[e.pointer] = h.$1;
          _on(h.$1, h.$2);
        },
        onPointerMove: (e) {
          var h = hit(e.localPosition);
          var was = _pressed[e.pointer];
          if (h?.$1 == was) return;
          if (was != null) {
            _pressed.remove(e.pointer);
            _off(was);
          }
          if (h == null) return;
          _pressed[e.pointer] = h.$1;
          _on(h.$1, h.$2);
        },
        onPointerUp: (e) => _letGo(e.pointer),
        onPointerCancel: (e) => _letGo(e.pointer),
        child: child,
      );

  void _letGo(int pointer) {
    var was = _pressed.remove(pointer);
    if (was != null) _off(was);
  }

  /// _surface is the pads or the neck [size] big, played as the keys are:
  /// lower on a pad, harder.
  Widget _surface(InstrumentPart part, Size size, MixerLook look) {
    var layout = keyboardLayout(part, Offset.zero & size, titled: false);
    int velocity(double depth) =>
        _byHeight ? (40 + 87 * depth).round() : _velocity;
    var drums = part.look == InstrumentLook.drums;
    return _played(
      key: const ValueKey("instrumentKeys"),
      hit: (p) => switch (layout.keyAt(p)) {
        (var key, var depth)? => () {
            if (neckPlaceAt(layout, part, p) case var at?) _placed[key] = at;
            return (key, velocity(depth));
          }(),
        null => null,
      },
      child: CustomPaint(
        key: ValueKey("instrumentSurface-${part.look.name}"),
        size: size,
        painter: _SurfacePainter(layout, part,
            down: {for (var n in _held.values) ...n},
            places: {
              for (var k in _held.keys)
                if (_placed[k] case var at?) k: at
            },
            letters: drums && _labels == 0
                ? {
                    for (var (i, (key, _)) in drumPads.indexed)
                      if (i < keyRow.length) key: keyRow[i].toUpperCase()
                  }
                : const {},
            face: look.studio.raised,
            ink: look.studio.text,
            accent: look.colors.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    Widget pill(String key, String label, bool on, VoidCallback tap) =>
        GestureDetector(
          key: ValueKey(key),
          onTap: tap,
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? look.colors.primary : null,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color: on ? look.colors.primary : look.studio.edge),
            ),
            child: Text(label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 10,
                    color: on ? look.colors.onPrimary : look.studio.muted)),
          ),
        );
    String name(int key) => "${const [
          "C",
          "C♯",
          "D",
          "E♭",
          "E",
          "F",
          "F♯",
          "G",
          "A♭",
          "A",
          "B♭",
          "B"
        ][key % 12]}${key ~/ 12 - 1}";
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Container(
        decoration: BoxDecoration(
          color: look.studio.inset,
          border: Border(top: BorderSide(color: look.studio.edge)),
        ),
        child: LayoutBuilder(builder: (context, room) {
          var roomy = room.maxHeight >= 80;
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 116,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: look.studio.edge))),
              child: Row(children: [
                _Wheel(
                  key: const ValueKey("instrumentBendWheel"),
                  value: _bend,
                  springs: true,
                  look: look,
                  onChanged: (v) {
                    setState(() => _bend = v);
                    c.controlOn(widget.element, MidiControl.pitchBend, v);
                  },
                ),
                const SizedBox(width: 5),
                _Wheel(
                  key: const ValueKey("instrumentModWheel"),
                  value: _mod,
                  look: look,
                  onChanged: (v) {
                    setState(() => _mod = v);
                    c.controlOn(widget.element, MidiControl.modulation, v);
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 52,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            pill(
                                "instrumentOctaveDown",
                                "◀ ${name(_octave - 12)}",
                                false,
                                () => setState(() =>
                                    _octave = math.max(12, _octave - 12))),
                            if (roomy) const SizedBox(height: 3),
                            pill(
                                "instrumentOctaveUp",
                                "${name(_octave + 12)} ▶",
                                false,
                                () => setState(() =>
                                    _octave = math.min(96, _octave + 12))),
                            if (roomy) ...[
                              const SizedBox(height: 3),
                              pill("instrumentSustain", "Sustain", _sustain,
                                  () {
                                setState(() => _sustain = !_sustain);
                                c.controlOn(widget.element, MidiControl.sustain,
                                    _sustain ? 1 : 0);
                              }),
                            ],
                          ]),
                    ),
                  ),
                ),
              ]),
            ),
            if (roomy)
              Container(
                width: 92,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: look.studio.edge))),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 80,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          pill(
                              "instrumentVelocityMode",
                              _byHeight ? "Vel: by height" : "Vel: $_velocity",
                              _byHeight,
                              () => setState(() => _byHeight = !_byHeight)),
                          const SizedBox(height: 3),
                          pill(
                              "instrumentChord",
                              _chords[_chord].$1,
                              _chord > 0,
                              () => setState(() =>
                                  _chord = (_chord + 1) % _chords.length)),
                          const SizedBox(height: 3),
                          pill("instrumentHold", "Hold", _hold, () {
                            setState(() => _hold = !_hold);
                            if (!_hold) {
                              for (var k in [..._held.keys]) {
                                _off(k, force: true);
                              }
                              setState(() {});
                            }
                          }),
                          const SizedBox(height: 3),
                          pill(
                              "instrumentLabels",
                              const ["Letters", "Names", "No labels"][_labels],
                              false,
                              () =>
                                  setState(() => _labels = (_labels + 1) % 3)),
                        ]),
                  ),
                ),
              ),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                var part = widget.element.instrument;
                if (part != null && part.look != InstrumentLook.keyboard) {
                  return _surface(part, box.biggest, look);
                }
                var layout = _KeysLayout(box.biggest, _octave);
                int? at(Offset p) => layout.keyAt(p);
                int velocity(Offset p) => _byHeight
                    ? (40 + 87 * (p.dy / box.maxHeight).clamp(0.0, 1.0)).round()
                    : _velocity;
                return _played(
                  key: const ValueKey("instrumentKeys"),
                  hit: (p) => switch (at(p)) {
                    var k? => (k, velocity(p)),
                    null => null,
                  },
                  child: CustomPaint(
                    size: box.biggest,
                    painter: _KeysPainter(
                      layout,
                      down: {for (var n in _held.values) ...n},
                      labels: _labels,
                      look: look,
                    ),
                  ),
                );
              }),
            ),
          ]);
        }),
      ),
    );
  }
}

/// _SurfacePainter draws drum pads or a neck, the notes held lit.
class _SurfacePainter extends CustomPainter {
  final KeyboardLayout layout;
  final InstrumentPart part;
  final Set<int> down;
  final Map<int, FretPlace> places;
  final Map<int, String> letters;
  final Color face;
  final Color ink;
  final Color accent;
  _SurfacePainter(this.layout, this.part,
      {required this.down,
      this.places = const {},
      required this.accent,
      required this.face,
      required this.ink,
      this.letters = const {}});

  @override
  void paint(Canvas canvas, Size size) =>
      paintPlayingSurface(canvas, layout, part,
          lit: down,
          places: places,
          accent: accent,
          letters: letters,
          face: face,
          ink: ink);

  @override
  bool shouldRepaint(_SurfacePainter old) =>
      old.part != part ||
      old.layout.board != layout.board ||
      old.accent != accent ||
      old.face != face ||
      old.ink != ink ||
      old.letters.length != letters.length ||
      !old.down.containsAll(down) ||
      !down.containsAll(old.down) ||
      !mapEquals(old.places, places);
}

/// _Wheel is a bend or mod wheel; the bend wheel springs back to the
/// middle when let go.
class _Wheel extends StatelessWidget {
  final double value;
  final bool springs;
  final MixerLook look;
  final ValueChanged<double> onChanged;
  const _Wheel(
      {required this.value,
      required this.look,
      required this.onChanged,
      this.springs = false,
      super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var h = box.maxHeight;
        double at(Offset p) => (1 - p.dy / h).clamp(0.0, 1.0);
        return GestureDetector(
          supportedDevices: dragPointers,
          onVerticalDragStart: (d) => onChanged(at(d.localPosition)),
          onVerticalDragUpdate: (d) => onChanged(at(d.localPosition)),
          onVerticalDragEnd: (_) {
            if (springs) onChanged(0.5);
          },
          child: Container(
            width: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: look.studio.edge),
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [look.studio.raised, look.studio.inset]),
            ),
            child: Stack(children: [
              Positioned(
                left: 1,
                right: 1,
                top: (1 - value) * (h - 12),
                height: 10,
                child: Container(
                  decoration: BoxDecoration(
                      color: look.colors.primary,
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ]),
          ),
        );
      });
}

/// _KeysLayout places the keys on a keyboard [size] big starting at [low].
class _KeysLayout {
  final Size size;
  final int low;
  late final double white = (size.width / 29).clamp(16.0, 34.0);
  late final List<(int, Rect, bool)> keys = _lay();

  _KeysLayout(this.size, this.low);

  List<(int, Rect, bool)> _lay() {
    var whites = <(int, Rect, bool)>[];
    var count = (size.width / white).floor();
    var p = low;
    while (whites.length < count && p < 128) {
      if (!isBlackKey(p)) {
        whites.add((
          p,
          Rect.fromLTWH(whites.length * white, 0, white, size.height),
          false
        ));
      }
      p++;
    }
    var blacks = <(int, Rect, bool)>[];
    for (var (k, r, _) in whites) {
      if (isBlackKey(k + 1) && k + 1 < p) {
        blacks.add((
          k + 1,
          Rect.fromLTWH(
              r.left + white * 0.66, 0, white * 0.68, size.height * 0.6),
          true
        ));
      }
    }
    return [...whites, ...blacks];
  }

  /// keyAt is the key under [p], a black one before the white under it.
  int? keyAt(Offset p) {
    for (var (k, r, black) in keys.reversed) {
      if (black && r.contains(p)) return k;
    }
    for (var (k, r, black) in keys) {
      if (!black && r.contains(p)) return k;
    }
    return null;
  }
}

class _KeysPainter extends CustomPainter {
  final _KeysLayout layout;
  final Set<int> down;
  final int labels;
  final MixerLook look;
  _KeysPainter(this.layout,
      {required this.down, required this.labels, required this.look});

  @override
  void paint(Canvas canvas, Size size) {
    var lit = Paint()..color = midiColour;
    void say(String text, Offset at, Color colour) {
      var p = TextPainter(
          text: TextSpan(
              text: text, style: TextStyle(fontSize: 9.5, color: colour)),
          textDirection: TextDirection.ltr)
        ..layout();
      p.paint(canvas, at - Offset(p.width / 2, 0));
    }

    String? label(int k) {
      if (labels == 2) return null;
      if (labels == 1) {
        return k % 12 == 0 ? "C${k ~/ 12 - 1}" : null;
      }
      var i = k - layout.low;
      return i >= 0 && i < keyRow.length ? keyRow[i].toUpperCase() : null;
    }

    for (var (k, r, black) in layout.keys) {
      if (black) continue;
      canvas.drawRRect(
          RRect.fromRectAndCorners(r.deflate(0.5),
              bottomLeft: const Radius.circular(4),
              bottomRight: const Radius.circular(4)),
          down.contains(k) ? lit : (Paint()..color = const Color(0xFFECE9F2)));
      if (k % 12 == 0 && labels != 1) {
        say("C${k ~/ 12 - 1}", Offset(r.left + 10, 3), const Color(0xFF6C6788));
      }
      if (label(k) case var l?) {
        say(l, Offset(r.center.dx, r.bottom - 16), const Color(0xFF6C6788));
      }
    }
    for (var (k, r, black) in layout.keys) {
      if (!black) continue;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          down.contains(k) ? lit : (Paint()..color = const Color(0xFF1C1A2C)));
      var l = labels == 0 ? label(k) : null;
      if (l != null) {
        say(l, Offset(r.center.dx, r.bottom - 14), const Color(0xFFB9B4CC));
      }
    }
  }

  @override
  bool shouldRepaint(_KeysPainter old) => true;
}
