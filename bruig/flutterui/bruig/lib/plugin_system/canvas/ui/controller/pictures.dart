part of '../canvas_controller.dart';

// Pictures: their layers, masks and brushwork. Part of CanvasController. Its
// state is _PictureState, at the end of this file.

extension CanvasPictures on CanvasController {
  /// imageEditing is the id of the picture whose layers are open, or null;
  /// imageLayer is its picked layer, which the tools and settings work on
  /// (the base layer when nothing else is).
  String? get imageEditing => _imageEditing;

  String get imageLayer => _imageLayer;

  String get _imageLayer => _pictures.layerId;

  /// _imageLayer picks one layer, letting go of any others (see
  /// pickImageLayer for several).
  set _imageLayer(String id) {
    _pictures.layerId = id;
    _alsoPicked.clear();
  }

  /// imageLayers is every layer picked, the first one first.
  List<String> get imageLayers => [_pictures.layerId, ..._alsoPicked];

  List<ImageLayer> get pickedLayers {
    var e = editingImage;
    if (e == null) return const [];
    return [
      for (var id in imageLayers)
        if (e.layerById(id) case var l?) l
    ];
  }

  /// alignableLayers are the picked layers with a place of their own in the
  /// frame: picture layers, shown and unlocked. An adjustment or texture
  /// covers the whole frame.
  List<ImageLayer> get alignableLayers => [
        for (var l in pickedLayers)
          if (l.kind == LayerKind.picture && l.visible && !layerLocked(l)) l
      ];

  /// frameTool is the Frame section's tool open on its shelf (Image until
  /// another is picked), or null with all shut.
  FrameTool? get frameTool => _pictures.frameTool;

  set frameTool(FrameTool? v) {
    _pictures.frameTool = v;
    notifyListeners();
  }

  /// positionTool is the Position section's tool open on its shelf (Place
  /// until another is picked), or null with all shut. The Warp tool shows
  /// the picked picture's grid on the canvas while open.
  PositionTool? get positionTool => _pictures.positionTool;

  set positionTool(PositionTool? v) {
    _pictures.positionTool = v;
    notifyListeners();
  }

  /// warpLayer is the layer of the picture being edited whose warp grid is
  /// shown (see ImageWarp), or null. Only while that layer is picked:
  /// picking another puts the grid away.
  String? get warpLayer {
    var e = editingImage, id = _pictures.warpLayer;
    if (e == null || id == null || id != _pictures.layerId) return null;
    return e.layerById(id) == null ? null : id;
  }

  /// warpPicks is the picked warp grid points, by index.
  Set<int> get warpPicks => _pictures.warpPicks;

  set warpPicks(Set<int> v) {
    _pictures.warpPicks = Set.unmodifiable(v);
    notifyListeners();
  }

  /// warpOf is the warp of picture layer [layerId] of [e].
  ImageWarp warpOf(ImageElement e, String layerId) =>
      lookOf(e, layerId)?.warp ?? const ImageWarp();

  /// editWarp shows the picked layer's warp grid, opening the picture's
  /// layers on [layerId] if not open, or with [on] false puts it away.
  void editWarp(String elementId, String layerId, {bool on = true}) {
    if (!on) {
      _putWarpAway();
      notifyListeners();
      return;
    }
    if (imageEditing != elementId || _pictures.layerId != layerId) {
      editImage(elementId, layer: layerId);
    }
    _pictures.warpLayer = layerId;
    _pictures.warpPicks = const {};
    _pictures.positionTool = PositionTool.warp;
    imageTool = ImageTool.move;
    notifyListeners();
  }

  /// _putWarpAway puts the warp grid away with its picked points: asked
  /// for, or its picture no longer the one being edited (deselected, taken
  /// away, another picked), whose layer ids another picture may share.
  void _putWarpAway() {
    _pictures.warpLayer = null;
    _pictures.warpPicks = const {};
    // The Warp tool has nothing to show without its grid.
    if (_pictures.positionTool == PositionTool.warp) {
      _pictures.positionTool = PositionTool.place;
    }
  }

  /// changeWarp changes the warp of the layer being warped.
  void changeWarp(ImageWarp Function(ImageWarp) edit,
      {bool transient = false}) {
    var e = editingImage, id = warpLayer;
    if (e == null || id == null) return;
    var look = lookOf(e, id);
    if (look == null) return;
    replaceElement(withLook(e, id, look.copyWith(warp: edit(look.warp))),
        transient: transient);
  }

  /// skewHandles is whether an element's side handles slant rather than
  /// size it without a key held, for a touch screen or pen. A way of
  /// working: not saved.
  bool get skewHandles => _pictures.skewHandles;

  set skewHandles(bool v) {
    if (v == _pictures.skewHandles) return;
    _pictures.skewHandles = v;
    notifyListeners();
  }

  /// imageSolo is whether only the picked layer of the picture being edited
  /// can be worked on, every other held as if locked; it follows the pick.
  /// A way of working: not saved.
  bool get imageSolo => _imageSolo;

  set imageSolo(bool v) {
    if (v == _imageSolo) return;
    _imageSolo = v;
    notifyListeners();
  }

  /// layerLocked is whether [layer] of the picture being edited is held in
  /// place: locked, or not the soloed one.
  bool layerLocked(ImageLayer layer) =>
      layer.locked || (_imageSolo && layer.id != _pictures.layerId);

  /// aligning is how many things the align tools would line up: picked
  /// layers while a picture is open, elements otherwise.
  int get aligning =>
      editingImage != null ? alignableLayers.length : selection.length;

  ImageTool get imageTool => _pictures.tool;

  set imageTool(ImageTool tool) {
    if (_pictures.tool == tool) return;
    _pictures.tool = tool;
    // The removal brushes and the mask tools both paint on a press; only
    // one of them can have it.
    if (tool.masks) _retouch = RetouchBrush.off;
    notifyListeners();
  }

  ImageElement? get editingImage {
    var id = _imageEditing;
    var e = id == null ? null : _document.elementById(id);
    return e is ImageElement ? e : null;
  }

  ImageLayer? get pickedLayer => editingImage?.layerById(_imageLayer);

  /// editImage opens picture [id]'s layers, picking [layer]; null closes
  /// them. The edited picture is selected, as a drawing is.
  void editImage(String? id, {String? layer}) {
    if (_imageEditing == id && layer == null) return;
    // Solo is for working on one picture; another, or none, starts without,
    // and with no warp grid.
    if (_imageEditing != id) {
      _imageSolo = false;
      _putWarpAway();
    }
    _imageEditing = id;
    _imageLayer = layer ?? baseLayerId;
    if (id != null) {
      _selection = {id};
      _backgroundSelected = false;
      // A brush left in hand belongs to the base picture.
      if (_imageLayer != baseLayerId) _retouch = RetouchBrush.off;
    }
    notifyListeners();
  }

  /// pickImageLayer picks layer [id] of the picture being edited: alone, or
  /// with [add] (Shift or Command held) toggled among those already picked.
  void pickImageLayer(String id, {bool add = false}) {
    if (add) {
      if (id == _pictures.layerId) {
        if (_alsoPicked.isEmpty) return;
        _pictures.layerId = _alsoPicked.removeAt(0);
      } else if (!_alsoPicked.remove(id)) {
        _alsoPicked.add(id);
      }
      notifyListeners();
      return;
    }
    if (_imageLayer == id && _alsoPicked.isEmpty) return;
    _imageLayer = id;
    // The removal brushes paint on the base picture, and only there.
    if (id != baseLayerId) _retouch = RetouchBrush.off;
    notifyListeners();
  }

  /// changeImage replaces the picture being edited, as one undo step unless
  /// [transient].
  void changeImage(ImageElement next, {bool transient = false}) =>
      replaceElement(next, transient: transient);

  /// addImageLayer puts [layer] in just above the one picked, and picks it.
  void addImageLayer(ImageLayer layer, {bool onTop = false}) {
    var e = editingImage;
    if (e == null) return;
    replaceElement(
        withLayerAdded(e, layer, above: onTop ? e.stack.last.id : _imageLayer));
    _imageLayer = layer.id;
    _retouch = RetouchBrush.off;
    notifyListeners();
  }

  /// removeImageLayer removes layer [id], picking the one under it.
  void removeImageLayer(String id) {
    var e = editingImage;
    if (e == null || id == baseLayerId) return;
    var at = e.stack.indexWhere((l) => l.id == id);
    if (at < 0) return;
    var next = withoutLayer(e, id);
    _imageLayer = next.stack[(at - 1).clamp(0, next.stack.length - 1)].id;
    replaceElement(next);
  }

  void duplicateImageLayer(String id) {
    var e = editingImage;
    if (e == null) return;
    var copied = withLayerCopied(e, id);
    if (copied == null) return;
    _imageLayer = copied.$2;
    replaceElement(copied.$1);
  }

  /// maskHide is whether the mask tools hide the picture (true) or reveal
  /// it. X flips it; Option held flips it for one stroke.
  bool get maskHide => _pictures.maskHide;

  set maskHide(bool v) {
    if (_pictures.maskHide == v) return;
    _pictures.maskHide = v;
    notifyListeners();
  }

  /// maskBrushSize is the mask brush's radius, as a fraction of the
  /// picture's shorter side; maskHardness and maskStrength as a MaskMark's.
  double get maskBrushSize => _pictures.maskBrushSize;

  set maskBrushSize(double v) {
    _pictures.maskBrushSize = v.clamp(0.001, 0.5);
    notifyListeners();
  }

  double get maskHardness => _pictures.maskHardness;

  set maskHardness(double v) {
    _pictures.maskHardness = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  double get maskStrength => _pictures.maskStrength;

  set maskStrength(double v) {
    _pictures.maskStrength = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  /// maskRadial makes the gradient tool's fades spread from a middle.
  bool get maskRadial => _pictures.maskRadial;

  set maskRadial(bool v) {
    _pictures.maskRadial = v;
    notifyListeners();
  }

  /// maskView is how the mask is shown while a mask tool is in hand.
  MaskView get maskView => _pictures.maskView;

  set maskView(MaskView v) {
    _pictures.maskView = v;
    notifyListeners();
  }

  /// maskBusy says what is being worked out while finding a subject takes
  /// its moment; maskNote is what the last attempt said, where it found
  /// nothing or failed.
  String? get maskBusy => _pictures.maskBusy;

  String? get maskNote => _pictures.maskNote;

  /// changeMask changes the picked layer's mask by [edit], as one undo step
  /// unless [transient].
  void changeMask(ImageMask Function(ImageMask) edit,
      {bool transient = false}) {
    var e = editingImage;
    var picked = pickedLayer;
    // A frame-masked layer keeps its mask on itself.
    if (e != null && picked != null && picked.framed) {
      replaceElement(
          e.withLayer(picked.id, (l) => l.copyWith(mask: edit(l.mask))),
          transient: transient);
      return;
    }
    var look = e == null ? null : lookOf(e, _imageLayer);
    if (e == null || look == null) return;
    replaceElement(
        withLook(e, _imageLayer, look.copyWith(mask: edit(look.mask))),
        transient: transient);
  }

  /// findSubject finds the picked layer's subject (every subject, or the one
  /// at [at], a fraction of its picture) and puts it in the mask as [how]
  /// says.
  Future<void> findSubject(
      {Offset? at, MaskCombine how = MaskCombine.replace}) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    if (e == null ||
        look == null ||
        !look.hasImage ||
        _pictures.maskBusy != null) {
      return;
    }
    _pictures.maskBusy = "Finding the subject…";
    _pictures.maskNote = null;
    notifyListeners();
    // Found for the picture of the canvas open now, or for none.
    var loads = _loads;
    try {
      // Without the operating system's own finder, a rougher guess from
      // colour and edge, which says so.
      Uint8List? png;
      if (await SubjectFinder.available()) {
        png = await SubjectFinder.find(look.assetId, at: at);
      } else {
        var picture = images.original(look.assetId);
        if (picture != null) png = await guessSubjectMask(picture, at: at);
        if (!_stillOn(loads)) return;
        _pictures.maskNote =
            "Found by colour and edge — finish it with Quick select "
            "or the brush";
      }
      if (!_stillOn(loads)) return;
      if (png == null) {
        _pictures.maskNote = at == null
            ? "No subject could be found in this picture"
            : "No subject there — try a click on the person or thing itself";
        return;
      }
      var bytes = png;
      if (how != MaskCombine.replace) {
        var size = await _pictureSizeOf(look.assetId);
        var found = await decodeMask(png);
        var current = look.mask.subject.isEmpty
            ? null
            : await _maskImageOf(look.mask.subject);
        bytes = await combinedSubject(
                look.mask,
                current,
                found,
                size ?? Size(found.width.toDouble(), found.height.toDouble()),
                how) ??
            png;
      }
      var id = await CanvasAssets.saveMask(bytes);
      if (!_stillOn(loads)) return;
      if (id == null) {
        _pictures.maskNote = "The subject could not be kept";
        return;
      }
      // Whatever has happened meanwhile, the mask goes on the picture as it
      // is now.
      var now = _document.elementById(e.id);
      var nowLook = now is ImageElement ? lookOf(now, layerId) : null;
      if (now is! ImageElement || nowLook == null) return;
      var mask = nowLook.mask.copyWith(
          subject: id,
          // A subject found afresh starts the mask afresh: marks made for
          // the last one would land on the wrong thing.
          marks: how == MaskCombine.replace ? const [] : null,
          on: true);
      replaceElement(withLook(now, layerId, nowLook.copyWith(mask: mask)));
    } catch (message) {
      if (_stillOn(loads)) _pictures.maskNote = "$message";
    } finally {
      if (_stillOn(loads)) {
        _pictures.maskBusy = null;
        notifyListeners();
      }
    }
  }

  /// quickSelect grows a quick-select stroke along [stroke] (fractions of
  /// the picked layer's picture) out to nearby edges and adds what it finds,
  /// or with [subtract] takes it away. The mask's marks are worked into its
  /// new subject.
  Future<void> quickSelect(List<Offset> stroke, {bool subtract = false}) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    var picture = look == null ? null : images.original(look.assetId);
    if (e == null ||
        look == null ||
        picture == null ||
        _pictures.maskBusy != null) {
      return;
    }
    _pictures.maskBusy = "Selecting…";
    _pictures.maskNote = null;
    notifyListeners();
    var loads = _loads;
    try {
      var subject = look.mask.subject.isEmpty
          ? null
          : await _maskImageOf(look.mask.subject);
      var png = await quickSelectMask(
          picture, look.mask, subject, stroke, _pictures.maskBrushSize,
          subtract: subtract);
      var id = png == null ? null : await CanvasAssets.saveMask(png);
      if (!_stillOn(loads)) return;
      if (id == null) {
        _pictures.maskNote = "Nothing could be selected there";
        return;
      }
      var now = _document.elementById(e.id);
      var nowLook = now is ImageElement ? lookOf(now, layerId) : null;
      if (now is! ImageElement || nowLook == null) return;
      replaceElement(withLook(
          now,
          layerId,
          nowLook.copyWith(
              mask: nowLook.mask.copyWith(
                  subject: id, marks: const [], invert: false, on: true))));
    } catch (message) {
      if (_stillOn(loads)) _pictures.maskNote = "$message";
    } finally {
      if (_stillOn(loads)) {
        _pictures.maskBusy = null;
        notifyListeners();
      }
    }
  }

  /// refineEdge refines the picked layer's mask along [stroke] (fractions of
  /// its picture): the edge under it given the alpha its colours imply.
  Future<void> refineEdge(List<Offset> stroke) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    var picture = look == null ? null : images.original(look.assetId);
    if (e == null ||
        look == null ||
        picture == null ||
        _pictures.maskBusy != null) {
      return;
    }
    if (look.mask.empty) {
      _pictures.maskNote =
          "There is no edge to refine yet: find the subject first";
      notifyListeners();
      return;
    }
    _pictures.maskBusy = "Refining the edge…";
    _pictures.maskNote = null;
    notifyListeners();
    var loads = _loads;
    try {
      var subject = look.mask.subject.isEmpty
          ? null
          : await _maskImageOf(look.mask.subject);
      var png = await refineEdgeMask(
          picture, look.mask, subject, stroke, _pictures.maskBrushSize);
      var id = png == null ? null : await CanvasAssets.saveMask(png);
      if (id == null || !_stillOn(loads)) return;
      var now = _document.elementById(e.id);
      var nowLook = now is ImageElement ? lookOf(now, layerId) : null;
      if (now is! ImageElement || nowLook == null) return;
      replaceElement(withLook(
          now,
          layerId,
          nowLook.copyWith(
              mask: nowLook.mask.copyWith(
                  subject: id, marks: const [], invert: false, on: true))));
    } catch (message) {
      if (_stillOn(loads)) _pictures.maskNote = "$message";
    } finally {
      if (_stillOn(loads)) {
        _pictures.maskBusy = null;
        notifyListeners();
      }
    }
  }

  Future<ui.Image?> _maskImageOf(String id) async {
    var held = images.resolve(id, const BackgroundRemoval());
    if (held != null) return held;
    var path = await CanvasAssets.pathOf(id);
    if (path == null) return null;
    return decodeMask(await File(path).readAsBytes());
  }

  Future<Size?> _pictureSizeOf(String id) async {
    var held = images.original(id);
    if (held != null) {
      return Size(held.width.toDouble(), held.height.toDouble());
    }
    return pictureSize(id);
  }

  /// paintColour, paintSize (a fraction of the frame's or picture's shorter
  /// side), paintHardness and paintStrength are the paint and retouching
  /// brushes' shared settings.
  Color get paintColour => _pictures.paintColour;

  set paintColour(Color c) {
    _pictures.paintColour = c;
    notifyListeners();
  }

  double get paintSize => _pictures.paintSize;

  set paintSize(double v) {
    _pictures.paintSize = v.clamp(0.001, 0.5);
    notifyListeners();
  }

  double get paintHardness => _pictures.paintHardness;

  set paintHardness(double v) {
    _pictures.paintHardness = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  double get paintStrength => _pictures.paintStrength;

  set paintStrength(double v) {
    _pictures.paintStrength = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  /// paintTip is the paint brush's shape and how the pen drives it (see
  /// BrushTip); paintBrush is the id of the brush it was last taken from,
  /// or "" once anything has been changed by hand.
  BrushTip get paintTip => _pictures.paintTip;

  set paintTip(BrushTip v) {
    _pictures.paintTip = v;
    _pictures.paintBrush = "";
    notifyListeners();
  }

  String get paintBrush => _pictures.paintBrush;

  void useBrush(BrushPreset brush) {
    _pictures.paintSize = brush.size;
    _pictures.paintHardness = brush.hardness;
    _pictures.paintStrength = brush.strength;
    _pictures.paintTip = brush.tip;
    _pictures.paintBrush = brush.id;
    notifyListeners();
  }

  /// currentBrush is the paint brush as set now, as a preset to keep under
  /// [name].
  BrushPreset currentBrush(String name) => BrushPreset("", name,
      size: _pictures.paintSize,
      hardness: _pictures.paintHardness,
      strength: _pictures.paintStrength,
      tip: _pictures.paintTip);

  /// burning makes the dodge tool burn, as Option held does for a stroke.
  bool get burning => _pictures.burning;

  set burning(bool v) {
    _pictures.burning = v;
    notifyListeners();
  }

  /// cloneFrom is where the clone tool copies from, a fraction of the picked
  /// picture, chosen with Option-click; cloneOffset is its distance from the
  /// start of the first stroke after it, so later strokes copy from the same
  /// relative place.
  Offset? get cloneFrom => _pictures.cloneFrom;

  set cloneFrom(Offset? at) {
    _pictures.cloneFrom = at;
    cloneOffset = null;
    _pictures.maskNote = null;
    notifyListeners();
  }

  /// retouchWholeFrame is whether the retouching brushes work on the whole
  /// frame (every layer, as one picture) rather than the picked picture.
  /// Such strokes go on a paint layer of their own over the picked layer:
  /// see retouchesFrame.
  bool get retouchWholeFrame => _pictures.retouchWholeFrame;

  set retouchWholeFrame(bool v) {
    if (v == _pictures.retouchWholeFrame) return;
    _pictures.retouchWholeFrame = v;
    // Where to copy from is a fraction of one picture or of the frame.
    cloneFrom = null;
  }

  /// retouchLayerForFrame picks the layer whole-frame retouching goes on: a
  /// paint layer already picked, or the Retouch layer at the top of the
  /// picture, made if missing. On top because it works on what is under it;
  /// lower down it would copy from part of the frame and be hidden by the
  /// rest.
  void retouchLayerForFrame() {
    var e = editingImage, picked = pickedLayer;
    if (e == null || picked?.kind == LayerKind.paint) return;
    var top = e.stack.last;
    if (top.kind == LayerKind.paint && top.name == "Retouch") {
      pickImageLayer(top.id);
      return;
    }
    addImageLayer(ImageLayer.painting().copyWith(name: "Retouch"), onTop: true);
  }

  /// retouchesFrame is whether a retouching stroke works on the whole frame:
  /// asked to, or with a picked layer that has no picture of its own (a
  /// paint layer, an adjustment, a colour).
  bool get retouchesFrame =>
      _pictures.retouchWholeFrame || (pickedLayer?.framed ?? false);

  /// _cloneFollowsFrame keeps a whole-frame clone's source on the same part
  /// of the picture when the frame it is measured in changes from [was]'s
  /// to [now]'s.
  void _cloneFollowsFrame(ImageElement was, ImageElement now) {
    if (!retouchesFrame) return;
    var a = was.box.inner(was.bounds), b = now.box.inner(now.bounds);
    if (b.isEmpty) return;
    if (_pictures.cloneFrom case var f?) {
      _pictures.cloneFrom = Offset((a.left + f.dx * a.width - b.left) / b.width,
          (a.top + f.dy * a.height - b.top) / b.height);
    }
    if (cloneOffset case var o?) {
      cloneOffset =
          Offset(o.dx * a.width / b.width, o.dy * a.height / b.height);
    }
  }

  /// noteForBrush says something about the brush in its settings row.
  void noteForBrush(String? note) {
    _pictures.maskNote = note;
    notifyListeners();
  }

  /// changePaint changes the picked paint layer's strokes.
  void changePaint(List<StrokeMark> Function(List<StrokeMark>) edit,
      {bool transient = false}) {
    var e = editingImage, layer = pickedLayer;
    if (e == null || layer == null || layer.kind != LayerKind.paint) return;
    var next =
        e.withLayer(layer.id, (l) => l.copyWith(strokes: edit(l.strokes)));
    // Painted past the frame, the frame grows with the stroke, so it is
    // drawn where it is painted.
    var grown = next.grownToFit();
    if (!identical(grown, next)) _cloneFollowsFrame(next, grown);
    replaceElement(grown, transient: transient);
  }

  /// changeRetouch changes the retouching done to the picked picture.
  void changeRetouch(List<StrokeMark> Function(List<StrokeMark>) edit,
      {bool transient = false}) {
    var e = editingImage;
    var look = e == null ? null : lookOf(e, _imageLayer);
    if (e == null || look == null) return;
    replaceElement(
        withLook(e, _imageLayer, look.copyWith(retouch: edit(look.retouch))),
        transient: transient);
  }
}

/// _PictureState is what CanvasPictures keeps between calls, here beside the code that
/// uses it. The controller holds one, as _pictures; most fields are read and
/// set through CanvasPictures's getters and setters above, which say what each is.
class _PictureState {
  String layerId = baseLayerId;

  FrameTool? frameTool = FrameTool.image;

  PositionTool? positionTool = PositionTool.place;

  String? warpLayer;

  Set<int> warpPicks = const {};

  bool skewHandles = false;

  ImageTool tool = ImageTool.move;

  bool maskHide = true;

  double maskBrushSize = 0.03;

  double maskHardness = 0.6;

  double maskStrength = 1;

  bool maskRadial = false;

  MaskView maskView = MaskView.result;

  String? maskBusy;

  String? maskNote;

  Color paintColour = const Color(0xFFF2B33D);

  double paintSize = 0.02;

  double paintHardness = 0.6;

  double paintStrength = 1;

  BrushTip paintTip = const BrushTip();

  String paintBrush = "round";

  bool burning = false;

  Offset? cloneFrom;

  bool retouchWholeFrame = false;
}
