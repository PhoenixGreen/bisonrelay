part of 'piano_roll.dart';

// The keyboard, and what a press and a drag on the grid do. Part of
// _PianoRollState: its fields, lifecycle and build are in piano_roll.dart.

extension _PianoRollGestures on _PianoRollState {
  /// _stepKey plays Step input from the computer's keys, as the instrument
  /// editor's keys play: A to ' a note each from the octave's C (held
  /// together, a chord), Z and X an octave down and up, Tab a rest. Null
  /// for a key it leaves to the roll.
  KeyEventResult? _stepKey(KeyEvent e) {
    var keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) {
      return null;
    }
    var t = c.pianoRoll;
    var element = t == null ? null : c.instrumentOf(t.channel);
    if (element == null) return null;
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.tab) {
      c.stepRest();
      return KeyEventResult.handled;
    }
    var ch = e.character?.toLowerCase() ?? e.logicalKey.keyLabel.toLowerCase();
    if (ch == "z" || ch == "x") {
      if (e is KeyDownEvent) {
        setState(() => _stepOctave =
            (_stepOctave + (ch == "z" ? -12 : 12)).clamp(12, 108));
      }
      return KeyEventResult.handled;
    }
    var i = ch.length == 1 ? keyRow.indexOf(ch) : -1;
    if (i < 0) return null;
    if (e is KeyDownEvent) c.noteOn(element, _stepOctave + i);
    if (e is KeyUpEvent) c.noteOff(element, _stepOctave + i);
    return KeyEventResult.handled;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (c.rollStep) {
      if (_stepKey(e) case var handled?) return handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var shift = HardwareKeyboard.instance.isShiftPressed;
    var keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed) {
      switch (e.logicalKey) {
        case LogicalKeyboardKey.keyC:
          _copy();
        case LogicalKeyboardKey.keyX:
          _copy(cut: true);
        case LogicalKeyboardKey.keyV:
          _paste();
        case LogicalKeyboardKey.keyA:
          _selectAll();
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.keyV:
        setState(() => _tool = _Tool.select);
      case LogicalKeyboardKey.keyD:
        setState(() => _tool = _Tool.draw);
      case LogicalKeyboardKey.keyB:
        setState(() => _tool = _Tool.paint);
      case LogicalKeyboardKey.keyE:
        setState(() => _tool = _Tool.erase);
      case LogicalKeyboardKey.keyC:
        setState(() => _tool = _Tool.knife);
      case LogicalKeyboardKey.keyM:
        setState(() => _tool = _Tool.mute);
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        _delete();
      case LogicalKeyboardKey.arrowUp:
        _nudge(0, shift ? 12 : 1);
      case LogicalKeyboardKey.arrowDown:
        _nudge(0, shift ? -12 : -1);
      case LogicalKeyboardKey.arrowLeft:
        _nudge(-_grid, 0);
      case LogicalKeyboardKey.arrowRight:
        _nudge(_grid, 0);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// _hit is the note under [p] and whether it is at its right end, where
  /// a drag stretches it.
  (int, bool)? _hit(Offset p, List<MidiNote> notes, List<int> keys) {
    for (var i = notes.length - 1; i >= 0; i--) {
      var n = notes[i];
      var row = keys.indexOf(n.key);
      if (row < 0) continue;
      var r = Rect.fromLTWH(n.start * _beatW, row * _PianoRollState._rowH,
          math.max(4, n.length * _beatW), _PianoRollState._rowH);
      if (r.contains(p)) return (i, p.dx > r.right - 6);
    }
    return null;
  }

  int? _keyAt(double y, List<int> keys) {
    var row = (y / _PianoRollState._rowH).floor();
    return row < 0 || row >= keys.length ? null : keys[row];
  }

  void _tapGrid(Offset p, RollContent content, List<int> keys) {
    _focus.requestFocus();
    var hit = _hit(p, content.notes, keys);
    setState(() {
      if (hit != null) {
        if (!HardwareKeyboard.instance.isShiftPressed) _selected.clear();
        _selected.add(hit.$1);
        return;
      }
      _selected.clear();
    });
    switch (_tool) {
      case _Tool.erase:
        if (hit != null) {
          _write([...content.notes]..removeAt(hit.$1));
          _selected.clear();
        }
        return;
      case _Tool.knife:
        // Cut in two where it was pressed, on the grid.
        if (hit == null) return;
        var n = content.notes[hit.$1];
        var at = _round(p.dx / _beatW);
        if (at <= n.start + 1e-6 || at >= n.end - 1e-6) return;
        _write([
          for (var (i, m) in content.notes.indexed)
            if (i == hit.$1) ...[
              m.copyWith(length: at - m.start),
              m.copyWith(start: at, length: m.end - at),
            ] else
              m,
        ]);
        _selected.clear();
        return;
      case _Tool.mute:
        // It, or all those picked with it, muted or played again.
        if (hit == null) return;
        var which = _selected.length > 1 && _selected.contains(hit.$1)
            ? {..._selected}
            : {hit.$1};
        var muting = !content.notes[hit.$1].muted;
        _write([
          for (var (i, m) in content.notes.indexed)
            which.contains(i) ? m.copyWith(muted: muting) : m,
        ]);
        return;
      case _Tool.draw:
        if (hit != null) return;
        var key = _keyAt(p.dy, keys);
        if (key == null) return;
        var start = _snap(p.dx / _beatW);
        if (start >= content.beats) return;
        var put = [for (var k in _stamp(key)) MidiNote(k, start, _grid, 100)];
        _write([...content.notes, ...put]);
        setState(() => _selected
          ..clear()
          ..addAll(
              [for (var i = 0; i < put.length; i++) content.notes.length + i]));
      case _Tool.select || _Tool.paint:
        return;
    }
  }

  void _startDrag(Offset p, RollContent content, List<int> keys) {
    _focus.requestFocus();
    _from = p;
    _to = p;
    _before = content.notes;
    var hit = _hit(p, content.notes, keys);
    if (_tool == _Tool.erase) {
      _drag = _Drag.erase;
      _eraseAt(p, keys);
      setState(() {});
      return;
    }
    if (_tool == _Tool.paint) {
      var key = _keyAt(p.dy, keys);
      if (key == null) return;
      _drag = _Drag.paint;
      _painted.clear();
      _paintAt(p, _inKey(key));
      setState(() {});
      return;
    }
    if (_tool == _Tool.knife || _tool == _Tool.mute) {
      _drag = _Drag.none;
      return;
    }
    if (hit != null) {
      if (!_selected.contains(hit.$1)) {
        _selected
          ..clear()
          ..add(hit.$1);
      }
      _drag = hit.$2 ? _Drag.resize : _Drag.move;
    } else if (_drawTool) {
      var key = _keyAt(p.dy, keys);
      if (key == null) return;
      _drag = _Drag.draw;
      _drawn = content.notes.length;
      var put = [
        for (var k in _stamp(key)) MidiNote(k, _snap(p.dx / _beatW), _grid, 100)
      ];
      _selected
        ..clear()
        ..addAll([for (var i = 0; i < put.length; i++) _drawn! + i]);
      _write([...content.notes, ...put], transient: true);
    } else {
      _drag = _Drag.box;
      _selected.clear();
    }
    setState(() {});
  }

  void _updateDrag(Offset p, List<int> keys) {
    _to = p;
    var dx = (p.dx - _from.dx) / _beatW;
    switch (_drag) {
      case _Drag.draw:
        var n = _before.length;
        var start = _snap(_from.dx / _beatW);
        var key = _keyAt(_from.dy, keys) ?? 60;
        var end = math.max(start + _grid, _round(p.dx / _beatW));
        _write([
          ..._before.take(n),
          for (var k in _stamp(key)) MidiNote(k, start, end - start, 100)
        ], transient: true);
      case _Drag.paint:
        var key = _keyAt(_from.dy, keys) ?? 60;
        _paintAt(p, _inKey(key));
      case _Drag.erase:
        _eraseAt(p, keys);
      case _Drag.move:
        var steps = _round(dx);
        var rows = ((p.dy - _from.dy) / _PianoRollState._rowH).round();
        _write([
          for (var (i, n) in _before.indexed)
            if (_selected.contains(i))
              n.copyWith(
                  start: math.max(0, n.start + steps),
                  key: _inKey(_shiftKey(n.key, rows, keys)))
            else
              n,
        ], transient: true);
      case _Drag.resize:
        _write([
          for (var (i, n) in _before.indexed)
            if (_selected.contains(i))
              n.copyWith(length: math.max(_grid, _round(n.length + dx)))
            else
              n,
        ], transient: true);
      case _Drag.box:
        var box = Rect.fromPoints(_from, p);
        _selected
          ..clear()
          ..addAll([
            for (var (i, n) in _before.indexed)
              if (keys.indexOf(n.key) case var row when row >= 0)
                if (box.overlaps(Rect.fromLTWH(
                    n.start * _beatW,
                    row * _PianoRollState._rowH,
                    math.max(4, n.length * _beatW),
                    _PianoRollState._rowH)))
                  i,
          ]);
      case _Drag.none:
        break;
    }
    setState(() {});
  }

  /// _shiftKey is [key] moved [rows] rows down the grid as it is drawn --
  /// folded, from one used key to the next.
  int _shiftKey(int key, int rows, List<int> keys) {
    var at = keys.indexOf(key);
    if (at < 0) return key;
    return keys[(at + rows).clamp(0, keys.length - 1)];
  }

  /// _paintAt puts a note of [key] on the step under [p], once per step.
  void _paintAt(Offset p, int key) {
    var content = c.rollContent;
    if (content == null) return;
    var step = (p.dx / _beatW / _grid).floor();
    var last = (content.beats / _grid).ceil() - 1;
    if (step < 0 || step > last) return;
    // Every step from the last one painted: a quick drag passes several
    // between two moves of the pointer.
    var from = _painted.isEmpty ? step : _lastPainted;
    var steps = [
      for (var k = math.min(from, step); k <= math.max(from, step); k++)
        if (!_painted.contains(k)) k
    ];
    _lastPainted = step;
    if (steps.isEmpty) return;
    _painted.addAll(steps);
    _write([
      ...content.notes,
      for (var k in steps) MidiNote(key, k * _grid, _grid, 100)
    ], transient: true);
  }

  void _eraseAt(Offset p, List<int> keys) {
    var content = c.rollContent;
    if (content == null) return;
    var hit = _hit(p, content.notes, keys);
    if (hit == null) return;
    _selected.clear();
    _write([...content.notes]..removeAt(hit.$1), transient: true);
  }

  void _endDrag() {
    if (_drag != _Drag.box && _drag != _Drag.none) c.endInteraction();
    _drag = _Drag.none;
    _drawn = null;
    setState(() {});
  }

  /// _clip is the clip the roll shows, or null for a part.
  SessionClip? get _clip {
    var t = c.pianoRoll;
    if (t == null || t.row == null) return null;
    return c.session.at(t.channel, t.row!);
  }

  /// _laneChoices are what a lane can show, named: velocity, each controller
  /// and, for a clip, each of its channel's settings as an envelope.
  List<(RollLane, String)> _laneChoices() {
    var t = c.pianoRoll;
    var channel = t == null
        ? null
        : c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    var returns = c.document.returns;
    return [
      for (var l in RollLane.all) (l, l.label),
      if (_clip != null && channel != null)
        for (var a in automationTargets(channel.mix, returns))
          (RollLane.setting(a.id), settingLabel(a, channel.mix, returns)),
    ];
  }

  /// _putHead puts the playhead at [x] along the ruler, to the grid.
  void _putHead(double x, RollContent content) {
    _focus.requestFocus();
    c.rollCursor = _round(x / _beatW).clamp(0.0, content.beats);
  }
}
