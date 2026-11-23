part of '../canvas_controller.dart';

// The brush on a picture: retouching, the stroke held before it is put down,
// and the brush's hardness, snap and size. Part of CanvasController: its fields
// and lifecycle are in canvas_controller.dart.

extension CanvasBrushwork on CanvasController {
  /// retouch is the brush painting a picture's background in or out. A mode
  /// rather than a modifier key, since retouching takes a run of strokes.
  RetouchBrush get retouch => _retouch;

  set retouch(RetouchBrush value) {
    if (_retouch == value) return;
    _retouch = value;
    notifyListeners();
  }

  List<Offset>? get pendingStroke => _pendingStroke;

  String? get pendingPicture => _pendingPicture;

  bool get pendingKeeps => _pendingKeeps;

  bool get pendingTeaches => _pendingTeaches;

  bool get pendingFills => _pendingFills;

  bool get hasPendingStroke =>
      _pendingStroke != null && _pendingStroke!.isNotEmpty;

  /// holdStroke keeps a freshly drawn stroke back for adjustment.
  void holdStroke(String pictureId, List<Offset> points,
      {required bool keeps, required bool teaches, bool fills = false}) {
    if (points.isEmpty) return;
    _pendingPicture = pictureId;
    _pendingStroke = List.unmodifiable(points);
    _pendingKeeps = keeps;
    _pendingTeaches = teaches;
    _pendingFills = fills;
    notifyListeners();
  }

  void discardStroke() {
    if (_pendingStroke == null) return;
    _pendingStroke = null;
    _pendingPicture = null;
    notifyListeners();
  }

  /// applyStroke writes the held stroke onto its picture, brush as it is.
  void applyStroke() {
    var id = _pendingPicture;
    var points = _pendingStroke;
    if (id == null || points == null || points.isEmpty) return;

    var picture = _document.elementById(id);
    if (picture is! ImageElement) {
      discardStroke();
      return;
    }

    var stroke = RemovalStroke(
      points: points,
      radius: _brushSize,
      keep: _pendingKeeps,
      // A hint is a sample, not a mark, so it is taken exactly where drawn:
      // softening or snapping it would collect colours not pointed at.
      hardness: _pendingTeaches ? 1 : _brushHardness,
      snap: _clingFor(_pendingTeaches, _pendingKeeps),
      fill: _pendingFills,
      fillInside: _pendingFills && _cutInside,
    );

    replaceElement(picture.copyWith(
        removal: _pendingTeaches
            ? picture.removal
                .copyWith(hints: [...picture.removal.hints, stroke])
            : picture.removal
                .copyWith(strokes: [...picture.removal.strokes, stroke])));
    discardStroke();
  }

  /// magnetiseCling sets the cling to the edge the held stroke crossed, where
  /// its colour distances split into two clusters (see suggestSnap). False
  /// when there is no edge.
  Future<bool> magnetiseCling() async {
    var stroke = pendingAsStroke();
    var id = _pendingPicture;
    if (stroke == null || id == null) return false;

    var picture = _document.elementById(id);
    if (picture is! ImageElement) return false;
    var source = images.original(picture.assetId);
    if (source == null) return false;

    var loads = _loads;
    var found = await snapForStroke(source, stroke);
    // The stroke was the last canvas's: its edge sets nothing here.
    if (found == null || !_stillOn(loads)) return false;
    brushSnap = found;
    return true;
  }

  /// pendingAsStroke is the held stroke as it would apply now: the preview.
  RemovalStroke? pendingAsStroke() {
    var points = _pendingStroke;
    if (points == null || points.isEmpty) return null;
    return RemovalStroke(
      points: points,
      radius: _brushSize,
      keep: _pendingKeeps,
      hardness: _pendingTeaches ? 1 : _brushHardness,
      snap: _clingFor(_pendingTeaches, _pendingKeeps),
      fill: _pendingFills,
      fillInside: _pendingFills && _cutInside,
    );
  }

  /// _clingFor is how much a stroke clings. Never for a hint, sampled exactly
  /// where drawn, nor for putting back: the subject is every colour, so
  /// clinging would restore only pixels like the first.
  double _clingFor(bool teaches, bool keeps) =>
      teaches || keeps ? 0 : _brushSnap;

  /// brushHardness is how abruptly a stroke stops at its own edge. See
  /// RemovalStroke.hardness.
  double get brushHardness => _brushHardness;

  set brushHardness(double value) {
    var next = value.clamp(0.05, 1.0);
    if (next == _brushHardness) return;
    _brushHardness = next;
    notifyListeners();
  }

  /// cutInside takes what a boundary encloses rather than what surrounds it,
  /// read when the stroke is applied so it can be flipped while one is held.
  bool get cutInside => _cutInside;

  set cutInside(bool value) {
    if (_cutInside == value) return;
    _cutInside = value;
    notifyListeners();
  }

  /// brushSnap makes a stroke cling to what is already in the picture. See
  /// RemovalStroke.snap.
  double get brushSnap => _brushSnap;

  set brushSnap(double value) {
    var next = value.clamp(0.0, 0.6);
    if (next == _brushSnap) return;
    _brushSnap = next;
    notifyListeners();
  }

  /// brushSize is the brush's radius as a fraction of the picture's shorter
  /// side, as a stroke is stored, so it is independent of zoom.
  double get brushSize => _brushSize;

  set brushSize(double value) {
    var next = value.clamp(0.005, 0.6);
    if (next == _brushSize) return;
    _brushSize = next;
    notifyListeners();
  }
}
