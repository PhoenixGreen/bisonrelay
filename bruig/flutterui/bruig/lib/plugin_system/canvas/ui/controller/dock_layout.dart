part of '../canvas_controller.dart';

// How the panels under the canvas are laid out: the timeline's rows and play
// bar, the dock's places and saved arrangements, and the slots column beside
// the rows. Part of CanvasController: its fields and lifecycle are in
// canvas_controller.dart.

extension CanvasDockLayout on CanvasController {
  /// rowsShown is the Timeline panel, open in its place (see dock).
  bool get rowsShown => dockOpen(DockPanel.timeline);

  set rowsShown(bool value) {
    if (rowsShown == value) return;
    value ? _openPanel(DockPanel.timeline) : _closePanel(DockPanel.timeline);
    _notifyView();
  }

  /// barBelow puts the play bar under the panels: kept as the person's
  /// (KeptView).
  bool get barBelow => _barBelow;

  set barBelow(bool value) {
    if (_barBelow == value) return;
    _barBelow = value;
    _notifyView();
  }

  /// restoreBarBelow and restoreTrackpadScrolls put back what the
  /// preferences hold, without notifying, for the page as it opens.
  void restoreBarBelow(bool value) => _barBelow = value;
  void restoreTrackpadScrolls(bool value) => _trackpadScrolls = value;

  /// trackpadScrolls lets a sideways swipe or the wheel move the timeline.
  /// Off by default, so swiping through the channels does not slide frames.
  /// Kept as the person's (KeptView).
  bool get trackpadScrolls => _trackpadScrolls;

  set trackpadScrolls(bool value) {
    if (_trackpadScrolls == value) return;
    _trackpadScrolls = value;
    _notifyView();
  }

  /// dock is where each panel under the canvas opens and how the places are
  /// switched, saved in preferences. Changing it leaves one panel per place.
  DockLayout get dock => _dock;

  set dock(DockLayout next) {
    if (next == _dock) return;
    _dock = next;
    _dockSettle();
    _notifyView();
  }

  /// restoreDock puts back [layout] as the screen opens, without notifying.
  void restoreDock(DockLayout layout) {
    _dock = layout;
    _dockSettle();
  }

  /// dockOpen is whether [panel] is open.
  bool dockOpen(DockPanel panel) => _dockState.isOpen(panel);

  /// _openPanel opens [panel], shutting whatever shared its place. Every
  /// panel is opened through here or [_showChain], so that each place shows
  /// one; a layout chosen by name no longer describes what is open.
  void _openPanel(DockPanel panel) {
    _dockState = _dockState.opened(panel, _dock);
    _arrangementChosen = null;
  }

  void _closePanel(DockPanel panel) => _dockState = _dockState.closed(panel);

  /// _showChain opens the Chain on [view], shutting whatever shared its
  /// place.
  void _showChain(ChainView view) {
    _dockState = _dockState.onView(view);
    _openPanel(DockPanel.chain);
  }

  /// setDockOpen opens or closes [panel], displacing what shares its place.
  void setDockOpen(DockPanel panel, bool open) {
    switch (panel) {
      case DockPanel.timeline:
        rowsShown = open;
      case DockPanel.slots:
        slotsBeside = open;
      case DockPanel.mixer:
        mixerOpen = open;
      case DockPanel.chain:
        if (open) {
          showChain(motion: _chainOpensOnMotion);
        } else if (dockOpen(DockPanel.chain)) {
          _closePanel(DockPanel.chain);
          notifyListeners();
        }
    }
  }

  /// toggleDock is [panel]'s button; [beside] opens it on the left, if any.
  void toggleDock(DockPanel panel, {bool beside = false}) {
    if (beside && _dock.places != DockPlaces.one) {
      if (_dock.homeOf(panel) != DockPlace.left) {
        _dock = _dock.withHome(panel, DockPlace.left);
        _dockSettle();
      }
      setDockOpen(panel, true);
      _notifyView();
      return;
    }
    setDockOpen(panel, !dockOpen(panel));
  }

  /// moveDockPanel makes [place] the home of [panel] and opens it there.
  void moveDockPanel(DockPanel panel, DockPlace place) {
    if (!_dock.placesShown.contains(place)) return;
    _dock = _dock.withHome(panel, place);
    _dockSettle();
    setDockOpen(panel, true);
    _notifyView();
  }

  /// dockShownIn is the panel showing in [place], or null.
  DockPanel? dockShownIn(DockPlace place) =>
      _dockState.shownIn(place, _dock);

  /// dockArrangement is the layout last chosen, until anything changes.
  String? get dockArrangement => _arrangementChosen;

  /// arrange shows [layout]'s panel in each place (with one place, its one).
  void arrange(DockArrangement layout) {
    var homes = {..._dock.homes, ...layout.homes};
    Map<DockPlace, DockPanel> shown;
    if (_dock.places == DockPlaces.one) {
      var one = layout.one ??
          layout.shown[DockPlace.main] ??
          layout.shown[DockPlace.left] ??
          layout.shown[DockPlace.above];
      shown = {if (one != null) DockPlace.main: one};
    } else {
      shown = _dock.places == DockPlaces.three || layout.fallback == null
          ? layout.shown
          : layout.fallback!;
      for (var e in shown.entries) {
        if (_dock.placesShown.contains(e.key)) homes[e.value] = e.key;
      }
      if (_dock.places != DockPlaces.three) {
        shown = {
          for (var e in shown.entries)
            if (e.key != DockPlace.above) e.key: e.value
        };
      }
    }
    _dock = _dock.copyWith(homes: homes);
    if (shown.containsValue(DockPanel.chain)) {
      _dockState = _dockState
          .onView(layout.chainMotion ? ChainView.motion : ChainView.sound);
    }
    _dockState = _dockState.showing(shown.values.toSet());
    _arrangementChosen = layout.name;
    _notifyView();
  }

  /// saveArrangement saves what is showing as a layout called [name].
  DockArrangement saveArrangement(String name) {
    var layout = DockArrangement(
      name,
      shown: {
        for (var place in _dock.placesShown)
          if (dockShownIn(place) case var panel?) place: panel
      },
      homes: {..._dock.homes},
      one: dockShownIn(DockPlace.main),
      chainMotion: chainShowsMotion,
    );
    var saved = [
      ..._dock.saved.where((a) => a.name != name),
      layout,
    ];
    _dock = _dock.copyWith(
        saved: saved.length > maxSavedArrangements
            ? saved.sublist(saved.length - maxSavedArrangements)
            : saved);
    _arrangementChosen = name;
    _notifyView();
    return layout;
  }

  void removeArrangement(String name) {
    _dock = _dock.copyWith(
        saved: [..._dock.saved.where((a) => a.name != name)]);
    if (_arrangementChosen == name) _arrangementChosen = null;
    _notifyView();
  }

  /// _dockSettle leaves one open panel per place, the first in button
  /// order, after the places themselves have changed.
  void _dockSettle() => _dockState = _dockState.settled(_dock);

  /// timelineShow is the Show in the play bar's settings, for the timeline
  /// and the mixer.
  TimelineShow get timelineShow => _timelineShow;

  set timelineShow(TimelineShow value) {
    if (_timelineShow == value) return;
    _timelineShow = value;
    _notifyView();
  }

  /// slotsBeside is the Slots panel, open in its place (see dock); level
  /// with the timeline's rows when it is on the left and they are in main.
  bool get slotsBeside => dockOpen(DockPanel.slots);

  set slotsBeside(bool value) {
    if (slotsBeside == value) return;
    value ? _openPanel(DockPanel.slots) : _closePanel(DockPanel.slots);
    _notifyView();
  }

  /// slotsWithRows is the slots drawn level with the timeline's rows.
  bool get slotsWithRows =>
      slotsBeside &&
      rowsShown &&
      _dock.placeOf(DockPanel.slots) == DockPlace.left &&
      _dock.placeOf(DockPanel.timeline) == DockPlace.main;

  /// slotsShown is how many slots each row has: at least two, and one past
  /// the last used (by any clip or named cue), never more than the cues.
  /// See CanvasController._slotRowsGrown.
  int get slotsShown {
    if (!identical(_slotsShownOf, _document)) {
      _slotsShownOf = _document;
      _slotsShownCount = math.min(session.rows,
          math.max(2, CanvasController.lastSlotUsed(_document) + 2));
    }
    return _slotsShownCount;
  }

  /// slotsColumn is the widest the slots beside the rows grow as they fill,
  /// set by dragging the grip; past it they scroll (see slotsScroll).
  double get slotsColumn => _slotsColumn;

  set slotsColumn(double value) {
    var next = value.clamp(CanvasController.slotsColumnMin, CanvasController.slotsColumnMax).toDouble();
    if (next == _slotsColumn) return;
    _slotsColumn = next;
    _clampSlotsScroll();
    notifyListeners();
  }

  /// slotsContent is how wide every slot shown is, laid side by side.
  double get slotsContent => slotsShown * (CanvasController.slotCellWidth + 3) + 5;

  /// scrollSlots scrolls the slots by [by] pixels, within what overflows the
  /// [shown] column (the slots beside the rows by default).
  void scrollSlots(double by, {double? shown}) {
    slotsScroll.value = (slotsScroll.value + by)
        .clamp(0.0, math.max(0.0, slotsContent - (shown ?? slotsWidth)))
        .toDouble();
  }

  void _clampSlotsScroll() => scrollSlots(0);

  /// slotsWidth is the slots beside the rows, or 0 when they are not shown;
  /// leftWidth is everything left of the lanes, where the time starts.
  double get slotsWidth =>
      slotsWithRows ? math.min(_slotsColumn, slotsContent) : 0;

  double get leftWidth => headerWidth + slotsWidth;
}
