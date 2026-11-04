part of '../canvas_controller.dart';

// Pictures: their layers, masks and brushwork.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasPictures on CanvasController {
  /// imageEditing is the picture whose layers are open for editing, by id,
  /// or null; imageLayer is the layer of it picked, which the tools and the
  /// settings work on. The base layer is picked when nothing else is.
  String? get imageEditing => _imageEditing;

  String get imageLayer => _imageLayer;

  String get _imageLayer => _imageLayerId;

  /// _imageLayer picks one layer, letting go of any others picked with it.
  /// See pickImageLayer for picking several.
  set _imageLayer(String id) {
    _imageLayerId = id;
    _alsoPicked.clear();
  }

  /// imageLayers is every layer picked, the first one first.
  List<String> get imageLayers => [_imageLayerId, ..._alsoPicked];

  /// pickedLayers is those layers.
  List<ImageLayer> get pickedLayers {
    var e = editingImage;
    if (e == null) return const [];
    return [
      for (var id in imageLayers)
        if (e.layerById(id) case var l?) l
    ];
  }

  /// alignableLayers are the picked layers with a place of their own in the
  /// frame: picture layers, shown and not locked. An adjustment or a texture
  /// covers the whole frame.
  List<ImageLayer> get alignableLayers => [
        for (var l in pickedLayers)
          if (l.kind == LayerKind.picture && l.visible && !layerLocked(l)) l
      ];

  /// frameTool is the Frame section's tool open on its shelf, Image until
  /// another is picked; null with all of them shut.
  FrameTool? get frameTool => _frameTool;

  set frameTool(FrameTool? v) {
    _frameTool = v;
    notifyListeners();
  }

  /// cardShut is whether the card [key] has been shut -- see _shutCards.
  bool cardShut(String key) => _shutCards.contains(key);

  /// toggleCard shuts the card [key] if it is open, and opens it if shut.
  void toggleCard(String key) {
    if (!_shutCards.remove(key)) _shutCards.add(key);
    notifyListeners();
  }

  /// openCard opens the card [key], without a redraw of its own: it goes
  /// with the change that is about to be made.
  void openCard(String key) => _shutCards.remove(key);

  /// textLayer is the piece of [e] picked in its Layers, or null for its
  /// own words (also what a piece since removed comes back as).
  TextItem? textLayer(TextElement e) {
    var id = _textLayers[e.id];
    if (id == null) return null;
    for (var item in e.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// pickTextLayer picks the piece [itemId] of the text element [elementId]
  /// in its Layers, or its own words with null.
  void pickTextLayer(String elementId, String? itemId) {
    if (_textLayers[elementId] == itemId) return;
    if (itemId == null) {
      _textLayers.remove(elementId);
    } else {
      _textLayers[elementId] = itemId;
    }
    notifyListeners();
  }

  /// positionTool is the Position section's tool open on its shelf, Place
  /// until another is picked; null with all of them shut. The Warp tool
  /// shows the picked picture's grid on the canvas while it is open.
  PositionTool? get positionTool => _positionTool;

  set positionTool(PositionTool? v) {
    _positionTool = v;
    notifyListeners();
  }

  /// warpLayer is the layer of the picture being edited whose warp grid is
  /// shown to be worked on -- see ImageWarp -- or null for none. Only while
  /// that layer is the one picked: picking another puts the grid away.
  String? get warpLayer {
    var e = editingImage, id = _warpLayer;
    if (e == null || id == null || id != _imageLayerId) return null;
    return e.layerById(id) == null ? null : id;
  }

  /// warpPicks is the points of the warp grid picked, by their place in it.
  Set<int> get warpPicks => _warpPicks;

  set warpPicks(Set<int> v) {
    _warpPicks = Set.unmodifiable(v);
    notifyListeners();
  }

  /// warpOf is the warp of the picture [layerId] of [e] shows.
  ImageWarp warpOf(ImageElement e, String layerId) =>
      lookOf(e, layerId)?.warp ?? const ImageWarp();

  /// editWarp shows the picked layer's warp grid to be worked on, opening
  /// the picture's layers on [layerId] where they are not open -- or, with
  /// [on] false, puts it away.
  void editWarp(String elementId, String layerId, {bool on = true}) {
    if (!on) {
      _warpLayer = null;
      _warpPicks = const {};
      // The Warp tool has nothing to show without its grid.
      if (_positionTool == PositionTool.warp) {
        _positionTool = PositionTool.place;
      }
      notifyListeners();
      return;
    }
    if (imageEditing != elementId || _imageLayerId != layerId) {
      editImage(elementId, layer: layerId);
    }
    _warpLayer = layerId;
    _warpPicks = const {};
    _positionTool = PositionTool.warp;
    imageTool = ImageTool.move;
    notifyListeners();
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

  /// skewHandles is whether an element's side handles slant it rather than
  /// size it, without a key held -- for a touch screen, or a pen. A way of
  /// working, not part of the design: it is not saved.
  bool get skewHandles => _skewHandles;

  set skewHandles(bool v) {
    if (v == _skewHandles) return;
    _skewHandles = v;
    notifyListeners();
  }

  /// imageSolo is whether only the picked layer of the picture being edited
  /// can be worked on, every other held as if locked; it follows the pick.
  /// A way of working, not part of the picture: it is not saved.
  bool get imageSolo => _imageSolo;

  set imageSolo(bool v) {
    if (v == _imageSolo) return;
    _imageSolo = v;
    notifyListeners();
  }

  /// layerLocked is whether [layer] of the picture being edited is held
  /// where it is on the canvas: locked, or not the soloed one.
  bool layerLocked(ImageLayer layer) =>
      layer.locked || (_imageSolo && layer.id != _imageLayerId);

  /// aligning is how many things the align tools would line up: picked
  /// picture layers while a picture is open, elements otherwise.
  int get aligning =>
      editingImage != null ? alignableLayers.length : selection.length;

  ImageTool get imageTool => _imageTool;

  set imageTool(ImageTool tool) {
    if (_imageTool == tool) return;
    _imageTool = tool;
    // The old removal brushes and the mask tools both paint on a press;
    // only one of them can have it.
    if (tool.masks) _retouch = RetouchBrush.off;
    notifyListeners();
  }

  /// editingImage is the picture being edited, where there is one.
  ImageElement? get editingImage {
    var id = _imageEditing;
    var e = id == null ? null : _document.elementById(id);
    return e is ImageElement ? e : null;
  }

  /// pickedLayer is the layer of the picture being edited that is picked.
  ImageLayer? get pickedLayer => editingImage?.layerById(_imageLayer);

  /// editImage opens the picture [id]'s layers, picking [layer]; null closes
  /// them. Edited is selected, as a drawing is -- see notifyListeners.
  void editImage(String? id, {String? layer}) {
    if (_imageEditing == id && layer == null) return;
    // Solo is a way of working on one picture; another, or none, starts
    // without it.
    if (_imageEditing != id) _imageSolo = false;
    _imageEditing = id;
    _imageLayer = layer ?? baseLayerId;
    if (id != null) {
      _selection = {id};
      _backgroundSelected = false;
      // A brush left in hand from before belongs to the base picture.
      if (_imageLayer != baseLayerId) _retouch = RetouchBrush.off;
    }
    notifyListeners();
  }

  /// pickImageLayer picks the layer [id] of the picture being edited --
  /// alone, or with [add] (Shift or Command held) as well as those picked
  /// already, or let go of again if it was.
  void pickImageLayer(String id, {bool add = false}) {
    if (add) {
      if (id == _imageLayerId) {
        if (_alsoPicked.isEmpty) return;
        _imageLayerId = _alsoPicked.removeAt(0);
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

  /// changeImage replaces the picture being edited, as one step unless
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

  /// removeImageLayer takes out the layer [id], picking the one under it.
  void removeImageLayer(String id) {
    var e = editingImage;
    if (e == null || id == baseLayerId) return;
    var at = e.stack.indexWhere((l) => l.id == id);
    if (at < 0) return;
    var next = withoutLayer(e, id);
    _imageLayer = next.stack[(at - 1).clamp(0, next.stack.length - 1)].id;
    replaceElement(next);
  }

  /// duplicateImageLayer copies the layer [id] and picks the copy.
  void duplicateImageLayer(String id) {
    var e = editingImage;
    if (e == null) return;
    var copied = withLayerCopied(e, id);
    if (copied == null) return;
    _imageLayer = copied.$2;
    replaceElement(copied.$1);
  }

  /// maskHide is whether the mask tools take the picture away (true) or put
  /// it back. X turns it over; Option held turns it over for one stroke.
  bool get maskHide => _maskHide;

  set maskHide(bool v) {
    if (_maskHide == v) return;
    _maskHide = v;
    notifyListeners();
  }

  /// maskBrushSize is the mask brush's radius, as a fraction of the
  /// picture's shorter side; maskHardness and maskStrength as a MaskMark's.
  double get maskBrushSize => _maskBrushSize;

  set maskBrushSize(double v) {
    _maskBrushSize = v.clamp(0.001, 0.5);
    notifyListeners();
  }

  double get maskHardness => _maskHardness;

  set maskHardness(double v) {
    _maskHardness = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  double get maskStrength => _maskStrength;

  set maskStrength(double v) {
    _maskStrength = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  /// maskRadial makes the gradient tool's fades spread from a middle.
  bool get maskRadial => _maskRadial;

  set maskRadial(bool v) {
    _maskRadial = v;
    notifyListeners();
  }

  /// maskView is how the mask is shown while a mask tool is in hand.
  MaskView get maskView => _maskView;

  set maskView(MaskView v) {
    _maskView = v;
    notifyListeners();
  }

  /// maskBusy says what is being worked out, while finding a subject takes
  /// its moment; maskNote what the last attempt had to say, where it found
  /// nothing or failed.
  String? get maskBusy => _maskBusy;

  String? get maskNote => _maskNote;

  /// changeMask changes the picked layer's mask by [edit], as one step
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

  /// findSubject finds the picked layer's subject -- every subject, or the
  /// one at [at], a fraction of its picture -- and puts it in the mask as
  /// [how] says.
  Future<void> findSubject(
      {Offset? at, MaskCombine how = MaskCombine.replace}) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    if (e == null || look == null || !look.hasImage || _maskBusy != null) {
      return;
    }
    _maskBusy = "Finding the subject…";
    _maskNote = null;
    notifyListeners();
    try {
      // Without the operating system's own finder, a rougher guess from
      // colour and edge, which says so.
      Uint8List? png;
      if (await SubjectFinder.available()) {
        png = await SubjectFinder.find(look.assetId, at: at);
      } else {
        var picture = images.original(look.assetId);
        if (picture != null) png = await guessSubjectMask(picture, at: at);
        _maskNote = "Found by colour and edge — finish it with Quick select "
            "or the brush";
      }
      if (png == null) {
        _maskNote = at == null
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
      if (id == null) {
        _maskNote = "The subject could not be kept";
        return;
      }
      // Whatever has happened to the picture meanwhile, the mask goes on the
      // picture as it is now.
      var now = _document.elementById(e.id);
      var nowLook = now is ImageElement ? lookOf(now, layerId) : null;
      if (now is! ImageElement || nowLook == null) return;
      var mask = nowLook.mask.copyWith(
          subject: id,
          // A subject found afresh starts the mask afresh: marks made for the
          // last one would land on the wrong thing.
          marks: how == MaskCombine.replace ? const [] : null,
          on: true);
      replaceElement(withLook(now, layerId, nowLook.copyWith(mask: mask)));
    } catch (message) {
      _maskNote = "$message";
    } finally {
      _maskBusy = null;
      notifyListeners();
    }
  }

  /// quickSelect grows a quick-select stroke along [stroke] -- fractions
  /// of the picked layer's picture -- out to the edges near it and keeps
  /// what it finds, or, with [subtract], takes it away. The mask's marks are
  /// worked into its new subject.
  Future<void> quickSelect(List<Offset> stroke, {bool subtract = false}) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    var picture = look == null ? null : images.original(look.assetId);
    if (e == null || look == null || picture == null || _maskBusy != null) {
      return;
    }
    _maskBusy = "Selecting…";
    _maskNote = null;
    notifyListeners();
    try {
      var subject = look.mask.subject.isEmpty
          ? null
          : await _maskImageOf(look.mask.subject);
      var png = await quickSelectMask(
          picture, look.mask, subject, stroke, _maskBrushSize,
          subtract: subtract);
      var id = png == null ? null : await CanvasAssets.saveMask(png);
      if (id == null) {
        _maskNote = "Nothing could be selected there";
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
      _maskNote = "$message";
    } finally {
      _maskBusy = null;
      notifyListeners();
    }
  }

  /// refineEdge refines the picked layer's mask along [stroke], fractions of
  /// its picture: the edge under it given the alpha its colours say it has.
  Future<void> refineEdge(List<Offset> stroke) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    var picture = look == null ? null : images.original(look.assetId);
    if (e == null || look == null || picture == null || _maskBusy != null) {
      return;
    }
    if (look.mask.empty) {
      _maskNote = "There is no edge to refine yet: find the subject first";
      notifyListeners();
      return;
    }
    _maskBusy = "Refining the edge…";
    _maskNote = null;
    notifyListeners();
    try {
      var subject = look.mask.subject.isEmpty
          ? null
          : await _maskImageOf(look.mask.subject);
      var png = await refineEdgeMask(
          picture, look.mask, subject, stroke, _maskBrushSize);
      var id = png == null ? null : await CanvasAssets.saveMask(png);
      if (id == null) return;
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
      _maskNote = "$message";
    } finally {
      _maskBusy = null;
      notifyListeners();
    }
  }

  /// _maskImageOf is the stored mask [id], decoded.
  Future<ui.Image?> _maskImageOf(String id) async {
    var held = images.resolve(id, const BackgroundRemoval());
    if (held != null) return held;
    var path = await CanvasAssets.pathOf(id);
    if (path == null) return null;
    return decodeMask(await File(path).readAsBytes());
  }

  /// _pictureSizeOf is the picture [id]'s size in pixels.
  Future<Size?> _pictureSizeOf(String id) async {
    var held = images.original(id);
    if (held != null) {
      return Size(held.width.toDouble(), held.height.toDouble());
    }
    return pictureSize(id);
  }

  /// paintColour, paintSize (a fraction of the frame's or the picture's
  /// shorter side), paintHardness and paintStrength are the paint and
  /// retouching brushes' settings, shared between them.
  Color get paintColour => _paintColour;

  set paintColour(Color c) {
    _paintColour = c;
    notifyListeners();
  }

  double get paintSize => _paintSize;

  set paintSize(double v) {
    _paintSize = v.clamp(0.001, 0.5);
    notifyListeners();
  }

  double get paintHardness => _paintHardness;

  set paintHardness(double v) {
    _paintHardness = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  double get paintStrength => _paintStrength;

  set paintStrength(double v) {
    _paintStrength = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  /// paintTip is the paint brush's shape and how the pen drives it -- see
  /// BrushTip -- and paintBrush the brush it was last taken from, by id, or
  /// "" once anything about it has been changed by hand.
  BrushTip get paintTip => _paintTip;

  set paintTip(BrushTip v) {
    _paintTip = v;
    _paintBrush = "";
    notifyListeners();
  }

  String get paintBrush => _paintBrush;

  /// useBrush takes everything about the paint brush from [brush].
  void useBrush(BrushPreset brush) {
    _paintSize = brush.size;
    _paintHardness = brush.hardness;
    _paintStrength = brush.strength;
    _paintTip = brush.tip;
    _paintBrush = brush.id;
    notifyListeners();
  }

  /// currentBrush is the paint brush as it is set now, as a preset that can
  /// be kept under [name].
  BrushPreset currentBrush(String name) => BrushPreset("", name,
      size: _paintSize,
      hardness: _paintHardness,
      strength: _paintStrength,
      tip: _paintTip);

  /// burning makes the dodge tool burn, as Option held does for a stroke.
  bool get burning => _burning;

  set burning(bool v) {
    _burning = v;
    notifyListeners();
  }

  /// cloneFrom is where the clone tool copies from, a fraction of the
  /// picked picture, chosen with Option-click; cloneOffset is how far that
  /// is from where the first stroke after it started, kept so later strokes
  /// copy from the same relative place.
  Offset? get cloneFrom => _cloneFrom;

  set cloneFrom(Offset? at) {
    _cloneFrom = at;
    cloneOffset = null;
    _maskNote = null;
    notifyListeners();
  }

  /// retouchWholeFrame is whether the retouching brushes work on everything
  /// in the frame -- every layer, as one picture -- rather than on the
  /// picture picked. Strokes made so go on a paint layer of their own, over
  /// the layer picked: see retouchesFrame.
  bool get retouchWholeFrame => _retouchWholeFrame;

  set retouchWholeFrame(bool v) {
    if (v == _retouchWholeFrame) return;
    _retouchWholeFrame = v;
    // Where to copy from was a fraction of one picture or of the frame.
    cloneFrom = null;
  }

  /// retouchLayerForFrame picks the layer whole-frame retouching goes on: a
  /// paint layer already picked, or the Retouch layer at the top of the
  /// picture, made if there is none. On top because it works on what is under
  /// it; lower down it would copy from part of the frame and be hidden by the
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

  /// retouchesFrame is whether a retouching stroke now works on the whole
  /// frame: asked to, or with a layer picked that has no picture of its own
  /// to work on -- a paint layer, an adjustment, a colour.
  bool get retouchesFrame =>
      _retouchWholeFrame || (pickedLayer?.framed ?? false);

  /// _cloneFollowsFrame keeps where a whole-frame clone copies from on the
  /// same part of the picture when the frame it is measured in changes from
  /// [was]'s to [now]'s.
  void _cloneFollowsFrame(ImageElement was, ImageElement now) {
    if (!retouchesFrame) return;
    var a = was.box.inner(was.bounds), b = now.box.inner(now.bounds);
    if (b.isEmpty) return;
    if (_cloneFrom case var f?) {
      _cloneFrom = Offset((a.left + f.dx * a.width - b.left) / b.width,
          (a.top + f.dy * a.height - b.top) / b.height);
    }
    if (cloneOffset case var o?) {
      cloneOffset =
          Offset(o.dx * a.width / b.width, o.dy * a.height / b.height);
    }
  }

  /// noteForBrush says something about the brush in its settings row.
  void noteForBrush(String? note) {
    _maskNote = note;
    notifyListeners();
  }

  /// changePaint changes the picked paint layer's strokes.
  void changePaint(List<StrokeMark> Function(List<StrokeMark>) edit,
      {bool transient = false}) {
    var e = editingImage, layer = pickedLayer;
    if (e == null || layer == null || layer.kind != LayerKind.paint) return;
    var next =
        e.withLayer(layer.id, (l) => l.copyWith(strokes: edit(l.strokes)));
    // Painted past the frame, the frame grows as the stroke goes, so the
    // stroke is drawn where it is being painted.
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
