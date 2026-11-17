part of '../canvas_controller.dart';

// How the panels under the canvas are laid out: the timeline's rows and play
// bar, the dock's places and saved arrangements, and the slots column beside
// the rows. Part of CanvasController: its fields and lifecycle are in
// canvas_controller.dart.

extension CanvasDockLayout on CanvasController {
  /// rowsShown is the Timeline panel, open in its place (see dock).
  bool get rowsShown => _rowsShown;

  set rowsShown(bool value) {
    if (_rowsShown == value) return;
    _rowsShown = value;
    if (value) _dockOpening(DockPanel.timeline);
    _notifyView();
  }

  /// barBelow puts the play bar under the panels: kept by CanvasPlayBar.
  bool get barBelow => _barBelow;

  set barBelow(bool value) {
    if (_barBelow == value) return;
    _barBelow = value;
    _notifyView();
  }

  /// trackpadScrolls lets a sideways swipe or the wheel move the timeline.
  /// Off by default, so swiping through the channels does not slide frames.
  bool get trackpadScrolls => _trackpadScrolls;

  set trackpadScrolls(bool value) {
    if (_trackpadScrolls == value) return;
    _trackpadScrolls = value;
    _notifyView();
  }

  void askTimelineZoom(double factor) {
    timelineZoomFactor = factor;
    timelineZoomAsked++;
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

  bool dockOpen(DockPanel panel) => switch (panel) {
        DockPanel.timeline => _rowsShown,
        DockPanel.slots => _slotsBeside,
        DockPanel.mixer => _mixerOpen,
        DockPanel.chain => _animationOpen || _effectsOpen,
      };

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
        } else {
          _animationOpen = false;
          effectsOpen = false;
          _notifyView();
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
  DockPanel? dockShownIn(DockPlace place) {
    for (var panel in DockPanel.values) {
      if (dockOpen(panel) && _dock.placeOf(panel) == place) return panel;
    }
    return null;
  }

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
    if (shown.containsValue(DockPanel.chain)) _chainMotion = layout.chainMotion;
    for (var panel in DockPanel.values) {
      _setDockRaw(panel, shown.containsValue(panel));
    }
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

  /// _dockOpening closes whatever else shows in [panel]'s place, silently.
  void _dockOpening(DockPanel panel) {
    var place = _dock.placeOf(panel);
    for (var other in DockPanel.values) {
      if (other != panel && dockOpen(other) && _dock.placeOf(other) == place) {
        _setDockRaw(other, false);
      }
    }
    _arrangementChosen = null;
  }

  /// _dockSettle leaves one open panel per place, the first in button order.
  void _dockSettle() {
    var taken = <DockPlace>{};
    for (var panel in DockPanel.values) {
      if (!dockOpen(panel)) continue;
      if (!taken.add(_dock.placeOf(panel))) _setDockRaw(panel, false);
    }
  }

  /// _setDockRaw opens or closes [panel] and nothing else.
  void _setDockRaw(DockPanel panel, bool open) {
    switch (panel) {
      case DockPanel.timeline:
        _rowsShown = open;
      case DockPanel.slots:
        _slotsBeside = open;
      case DockPanel.mixer:
        _mixerOpen = open;
        if (!open) _mixerMinimised = _mixerSmallest = false;
      case DockPanel.chain:
        _animationOpen = open && _chainMotion;
        _effectsOpen = open && !_chainMotion;
    }
  }

  /// timelineShow is the ⋯ menu's Show, for the timeline and the mixer.
  TimelineShow get timelineShow => _timelineShow;

  set timelineShow(TimelineShow value) {
    if (_timelineShow == value) return;
    _timelineShow = value;
    _notifyView();
  }

  /// slotsBeside is the Slots panel, open in its place (see dock); level
  /// with the timeline's rows when it is on the left and they are in main.
  bool get slotsBeside => _slotsBeside;

  set slotsBeside(bool value) {
    if (_slotsBeside == value) return;
    _slotsBeside = value;
    if (value) _dockOpening(DockPanel.slots);
    _notifyView();
  }

  /// slotsWithRows is the slots drawn level with the timeline's rows.
  bool get slotsWithRows =>
      _slotsBeside &&
      _rowsShown &&
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
