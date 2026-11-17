part of 'piano_roll.dart';

// The lanes under the notes and the settings beside them. Part of
// _PianoRollState: its fields, lifecycle and build are in piano_roll.dart.

extension _PianoRollLanes on _PianoRollState {
  /// _laneEdge is the edge over the lanes: dragged up, they grow, and the
  /// notes over them give way -- down to the notes' least.
  Widget _laneEdge(MixerLook look, double laneH, double tallest) => MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const ValueKey("rollLanesEdge"),
          supportedDevices: dragPointers,
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onVerticalDragStart: (d) {
            _edgeFrom = d.globalPosition.dy;
            _tallFrom = laneH;
          },
          // From where the drag began, not move by move: a move between
          // frames is not lost. Shared between the lanes there are.
          onVerticalDragUpdate: (d) => setState(() => _laneTall =
              (_tallFrom - (d.globalPosition.dy - _edgeFrom) / _lanes.length)
                  .clamp(_laneLeast, math.max(_laneLeast, tallest))),
          child: Container(
            height: _splitH,
            decoration: BoxDecoration(
                color: look.studio.panel,
                border: Border(
                    top: BorderSide(color: look.studio.edge),
                    bottom: BorderSide(color: look.studio.edge))),
          ),
        ),
      );

  /// _foldedLanes is a bar naming the folded lanes; its arrow opens them.
  Widget _foldedLanes(MixerLook look, {required bool canOpen}) {
    var studio = look.studio;
    return Container(
      key: const ValueKey("rollLanesFolded"),
      height: _headH,
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: studio.edge))),
      child: InkWell(
        key: const ValueKey("rollLanesOpen-0"),
        onTap: canOpen ? () => setState(() => _lanesOpen = true) : null,
        child: Row(children: [
          SizedBox(
              width: 22,
              child: Icon(Icons.chevron_right,
                  size: 14, color: canOpen ? studio.text : studio.muted)),
          Expanded(
            child: Text(
                canOpen
                    ? _lanes.map((l) => l.label).join(" · ")
                    : "Lanes: make the editor taller to open them",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: studio.muted)),
          ),
        ]),
      ),
    );
  }

  /// _lanePanel is lane [i]'s panel, under the keys: the lanes folded away,
  /// what it shows, a second lane added -- or this one taken away.
  Widget _lanePanel(MixerLook look, int i) {
    var studio = look.studio;
    var lane = _lanes[i];
    var others = {
      for (var (j, l) in _lanes.indexed)
        if (j != i) l
    };
    var choices = _laneChoices();
    var clip = _clip;
    Widget icon(String key, IconData icon, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(icon, size: 14, color: studio.text),
            ),
          ),
        );
    return Container(
      key: ValueKey("rollLaneHeading-$i"),
      width: _keysW,
      padding: const EdgeInsets.fromLTRB(2, 2, 4, 2),
      decoration: BoxDecoration(
          color: studio.panel,
          border: Border(
              right: BorderSide(color: studio.edge),
              top: i > 0 ? BorderSide(color: studio.edge) : BorderSide.none)),
      // Short, with the app's text large, it scrolls rather than spill.
      child: SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            icon("rollLanesOpen-$i", Icons.expand_more, "Fold the lanes away",
                () => setState(() => _lanesOpen = false)),
            const Spacer(),
            if (i == 0 && _lanes.length < 2)
              icon("rollLaneAdd", Icons.add,
                  "Add a second lane: another controller, or velocity", () {
                setState(() => _lanes
                    .add(RollLane.all.firstWhere((l) => !_lanes.contains(l))));
              }),
            if (i > 0)
              icon("rollLaneRemove", Icons.close, "Take this lane away",
                  () => setState(() => _lanes.removeAt(i))),
          ]),
          Column(
            key: ValueKey(i == 0 ? "rollLane" : "rollLane2"),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var (l, label) in choices)
                if (!others.contains(l))
                  InkWell(
                    key: ValueKey("rollLaneChoice-$i-$label"),
                    borderRadius: BorderRadius.circular(3),
                    onTap: () => setState(() => _lanes[i] = l),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: l == lane
                            ? look.colors.primary.withValues(alpha: 0.28)
                            : null,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              color: l == lane ? studio.text : studio.muted)),
                    ),
                  ),
            ],
          ),
          // A setting's envelope: the clip's length, or its own.
          if (lane.setting case var key? when clip != null)
            DropdownButton<double>(
              key: ValueKey("rollLaneLength-$i"),
              value: clip.lengthOf(key) ?? 0,
              isDense: true,
              isExpanded: true,
              underline: const SizedBox(),
              iconSize: 14,
              style: TextStyle(fontSize: 10.5, color: studio.text),
              dropdownColor: look.colors.surfaceContainerHigh,
              items: [
                for (var (beats, label)
                    in envelopeLengths(c.document.audio.beatsPerBar))
                  DropdownMenuItem(
                      value: beats ?? 0,
                      child: Text(label,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v == null) return;
                c.editClip((x) => x.withLength(key, v == 0 ? null : v));
              },
            ),
        ]),
      ),
    );
  }

  Widget _laneArea(RollContent content, MixerLook look, double width,
      RollLane lane, double laneH) {
    var control = lane.control;
    double valueAt(double y) => (1 - (y - 4) / (laneH - 8)).clamp(0.0, 1.0);
    if (control == null && lane.setting == null) {
      // A bar for each note: dragged, how hard it is played -- every note
      // picked with it, if it is picked.
      void set(Offset p, {bool transient = true}) {
        var i = _laneNote;
        if (i == null) return;
        var v = (1 + valueAt(p.dy) * 126).round();
        var together = _selected.contains(i) ? _selected : {i};
        _write([
          for (var (j, n) in content.notes.indexed)
            together.contains(j) ? n.copyWith(velocity: v) : n,
        ], transient: transient);
      }

      int? noteAt(Offset p) {
        int? best;
        var bestD = 8.0;
        for (var (i, n) in content.notes.indexed) {
          var d = (n.start * _beatW + 2 - p.dx).abs();
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        return best;
      }

      return GestureDetector(
        key: const ValueKey("rollVelocity"),
        supportedDevices: dragPointers,
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: (d) {
          _laneNote = noteAt(d.localPosition);
          set(d.localPosition);
        },
        onVerticalDragUpdate: (d) => set(d.localPosition),
        onVerticalDragEnd: (_) {
          if (_laneNote != null) c.endInteraction();
          _laneNote = null;
        },
        onTapUp: (d) {
          _laneNote = noteAt(d.localPosition);
          set(d.localPosition, transient: false);
          _laneNote = null;
        },
        child: CustomPaint(
          size: Size(width, laneH),
          painter: _VelocityPainter(
              content.notes, _beatW, {..._selected}, look.studio),
        ),
      );
    }
    if (lane.setting case var key?) {
      return _settingArea(key, look, width, laneH);
    }
    // A controller's curve: a press adds a point, a drag moves it, a
    // double-click takes it away.
    var points = content.controls[control!] ?? const <ControlPoint>[];
    int? pointAt(Offset p) {
      for (var (i, (t, v)) in points.indexed) {
        var at = Offset(t * _beatW, 4 + (1 - v) * (laneH - 8));
        if ((at - p).distance < 8) return i;
      }
      return null;
    }

    void put(int i, Offset p, {bool transient = true}) {
      // The curve as it is now, not as it was when the lane was last
      // built: a drag's first move can come before the frame that shows
      // the point its press put down.
      var now = c.rollContent?.controls ?? content.controls;
      var next = [...?now[control]];
      if (i < 0 || i >= next.length) return;
      ControlPoint moved = (math.max(0, p.dx / _beatW), valueAt(p.dy));
      next[i] = moved;
      next.sort((a, b) => a.$1.compareTo(b.$1));
      // Dragged past a neighbour, it is still the one being dragged.
      _lanePoint = next.indexOf(moved);
      _writeControls({...now, control: next}, transient: transient);
    }

    return GestureDetector(
      key: ValueKey("rollLane-${control.name}"),
      supportedDevices: dragPointers,
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        var p = d.localPosition;
        if (pointAt(p) != null) return;
        var next = [...points, (math.max(0.0, p.dx / _beatW), valueAt(p.dy))]
          ..sort((a, b) => a.$1.compareTo(b.$1));
        _writeControls({...content.controls, control: next});
      },
      onSecondaryTapUp: (d) {
        var i = pointAt(d.localPosition);
        if (i == null) return;
        _writeControls({
          ...content.controls,
          control: [...points]..removeAt(i)
        });
      },
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (d) {
        _lanePoint = pointAt(d.localPosition);
        if (_lanePoint == null) {
          // From where it was pressed: a point there, then dragged.
          var p = d.localPosition;
          var next = [...points, (math.max(0.0, p.dx / _beatW), valueAt(p.dy))]
            ..sort((a, b) => a.$1.compareTo(b.$1));
          c.beginInteraction();
          c.setRollContent(
              controls: {...content.controls, control: next}, transient: true);
          _lanePoint = next.indexOf(
              next.firstWhere((q) => q.$1 == math.max(0.0, p.dx / _beatW)));
        }
      },
      onPanUpdate: (d) {
        var i = _lanePoint;
        if (i != null) put(i, d.localPosition);
      },
      onPanEnd: (_) {
        c.endInteraction();
        _lanePoint = null;
      },
      child: CustomPaint(
        size: Size(width, laneH),
        painter: _CurvePainter(points, control.rest, _beatW, look.studio),
      ),
    );
  }

  /// _settingArea is a clip's envelope of one of its channel's settings,
  /// under its notes and edited as a controller's curve: points a beat and
  /// a height up the setting's range, its own length repeated along the clip.
  Widget _settingArea(String key, MixerLook look, double width, double laneH) {
    var clip = _clip;
    var t = c.pianoRoll;
    if (clip == null || t == null) return SizedBox(width: width, height: laneH);
    var what = AutomationTarget.parse(key);
    var channel =
        c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    var rest = what == null || channel == null
        ? 0.5
        : what.height(what.own(channel.mix));
    var length = clip.lengthOf(key);
    var points = clip.curveOf(key);
    double valueAt(double y) => (1 - (y - 4) / (laneH - 8)).clamp(0.0, 1.0);
    // To the grid, and inside its own length: its points are the first time
    // round, which the rest repeat.
    double beatAt(double x) {
      var b = math.max(0.0, _round(x / _beatW));
      return length == null ? b : b.clamp(0.0, math.max(0.0, length - _grid));
    }

    int? pointAt(Offset p) {
      for (var (i, (b, v)) in points.indexed) {
        var at = Offset(b * _beatW, 4 + (1 - v) * (laneH - 8));
        if ((at - p).distance < 8) return i;
      }
      return null;
    }

    void put(int i, Offset p) {
      var now = [...?_clip?.curveOf(key)];
      if (i < 0 || i >= now.length) return;
      ControlPoint moved = (beatAt(p.dx), valueAt(p.dy));
      now[i] = moved;
      now.sort((a, b) => a.$1.compareTo(b.$1));
      _lanePoint = now.indexOf(moved);
      c.editClip((x) => x.withCurve(key, now), transient: true);
    }

    return GestureDetector(
      key: ValueKey("rollSetting-$key"),
      supportedDevices: dragPointers,
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        if (pointAt(d.localPosition) != null) return;
        var p = d.localPosition;
        c.editClip((x) => x.withCurve(
            key, [...x.curveOf(key), (beatAt(p.dx), valueAt(p.dy))]));
      },
      onSecondaryTapUp: (d) {
        var i = pointAt(d.localPosition);
        if (i == null) return;
        c.editClip((x) => x.withCurve(key, [...x.curveOf(key)]..removeAt(i)));
      },
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (d) {
        c.beginInteraction();
        _lanePoint = pointAt(d.localPosition);
        if (_lanePoint == null) {
          // From where it was pressed: a point there, then dragged.
          var p = d.localPosition;
          ControlPoint added = (beatAt(p.dx), valueAt(p.dy));
          var next = [...points, added]..sort((a, b) => a.$1.compareTo(b.$1));
          c.editClip((x) => x.withCurve(key, next), transient: true);
          _lanePoint = next.indexOf(added);
        }
      },
      onPanUpdate: (d) {
        var i = _lanePoint;
        if (i != null) put(i, d.localPosition);
      },
      onPanEnd: (_) {
        c.endInteraction();
        _lanePoint = null;
      },
      child: CustomPaint(
        size: Size(width, laneH),
        painter:
            _CurvePainter(points, rest, _beatW, look.studio, length: length),
      ),
    );
  }
}
