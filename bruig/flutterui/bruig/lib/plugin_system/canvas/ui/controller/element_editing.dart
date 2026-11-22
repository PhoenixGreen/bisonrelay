part of '../canvas_controller.dart';

// Elements edited: the team player in focus, a change tried before it is made,
// adding, deleting and duplicating, the clipboard, nudging, aligning and
// spreading. Part of CanvasController: its fields and lifecycle are in
// canvas_controller.dart.

extension CanvasElementEditing on CanvasController {
  /// focusedPlayer is which player of the selected team the keyframe
  /// controls point at, since a player cannot be selected. Set by clicking
  /// one on the canvas; cleared when the selection changes.
  int? get focusedPlayer => _focusedPlayer;

  set focusedPlayer(int? value) {
    if (_focusedPlayer == value) return;
    _focusedPlayer = value;
    notifyListeners();
  }

  /// focusedTeam is the selected element when it is a team, else null.
  TeamElement? get focusedTeam {
    var element = selected;
    return element is TeamElement ? element : null;
  }

  bool get trying => _beforePreview != null;

  /// tryElement previews [element] in place of the one it replaces, outside
  /// the history and unsaved, until a null or the next real edit: for
  /// previewing a list's options before one is chosen.
  void tryElement(CanvasElement? element) {
    if (element == null) {
      if (_endPreview()) notifyListeners();
      return;
    }
    _beforePreview ??= _document;
    _document = _beforePreview!.withElement(element);
    notifyListeners();
  }

  /// _endPreview restores the real document; false if there was no preview.
  bool _endPreview() {
    var before = _beforePreview;
    if (before == null) return false;
    _beforePreview = null;
    _document = before;
    return true;
  }

  /// withCountLaidOut pins a new keyframed counter's count from the playhead
  /// to two seconds on (or the last two seconds near the end), so From and
  /// To work without pinning both by hand.
  CounterElement withCountLaidOut(CounterElement e) {
    var last = _document.frames - 1;
    if (!e.keyed || e.track != null || last < 1) return e;
    var rate = math.max(1, _document.frameRate);
    var start = _frame.clamp(0, last);
    var end = math.min(last, start + rate * 2);
    if (end - start < rate ~/ 2) {
      end = last;
      start = math.max(0, last - rate * 2);
    }
    return e.withBase(
        track: ElementTrack([
      Keyframe(frame: start).withValue(KeyframeChannel.count, e.from),
      Keyframe(frame: end).withValue(KeyframeChannel.count, e.to),
    ])) as CounterElement;
  }

  void replaceElement(CanvasElement element, {bool transient = false}) =>
      apply(_document.withElement(element), transient: transient);

  void addElement(CanvasElement element, {bool select = true}) {
    if (element is CounterElement) element = withCountLaidOut(element);
    var next = _document.addElement(element);
    // A stage is the set everything else is played in front of.
    if (element is StageElement ||
        (element is BackgroundElement && element.isStage)) {
      next = next.reorder(next.elements.length - 1, 0);
    }
    apply(next);
    if (select) selectOnly(element.id);
  }

  void deleteSelected() {
    // While a drawing is being edited, Delete takes out the points picked,
    // or the shape picked -- and with neither, nothing: never the drawing.
    if (editingVector != null) {
      deleteVectorPoint();
      return;
    }
    // Clips picked together on the timeline: those placings, not their
    // elements -- and then the sounds picked with them, which are elements.
    if (_motionPicks.length > 1) {
      beginInteraction();
      for (var (element, placement) in _motionPicks) {
        removePlacement(element, placement);
      }
      _motionPicks = const {};
      _pickedMotion = _pickedPlacement = null;
      var sounds = {..._selection, ..._offCanvas}
          .where((id) => _document.elementById(id) is AudioElement ||
              _offCanvas.contains(id))
          .toSet();
      _selection = {
        for (var id in _selection)
          if (sounds.contains(id)) id
      };
      if (_selection.isEmpty && _offCanvas.isEmpty) {
        endInteraction();
        notifyListeners();
        return;
      }
      deleteSelected();
      endInteraction();
      return;
    }
    // A clip picked on the timeline: that placing of it, not the element.
    if ((pickedPlacement, _selection.length) case (var p?, 1)) {
      var element = _selection.first;
      _pickedMotion = null;
      _pickedPlacement = null;
      removePlacement(element, p);
      return;
    }
    if (_selection.isEmpty && _offCanvas.isEmpty) return;
    var next = _document;
    for (var id in _selection) {
      next = next.removeElement(id);
      // Its own sound's channel goes with it: see element_sound.dart.
      var own = "snd-$id";
      for (var e in [...next.elements]) {
        if (e is AudioElement && e.clip.channel == own) {
          next = next.removeElement(e.id);
        }
      }
    }
    // And clips picked on the timeline from another scene or the master.
    for (var id in _offCanvas) {
      next = _removedAnywhere(next, id);
    }
    _selection = {};
    _offCanvas = const {};
    apply(next);
  }

  /// _removedAnywhere is [doc] without element [id], wherever it is.
  CanvasDocument _removedAnywhere(CanvasDocument doc, String id) {
    if (doc.elements.any((e) => e.id == id)) return doc.removeElement(id);
    var master = doc.master;
    if (master != null && master.elements.any((e) => e.id == id)) {
      return doc.copyWith(
          master: master.copyWith(elements: [
        for (var e in master.elements)
          if (e.id != id) e,
      ]));
    }
    for (var (i, scene) in doc.allScenes.indexed) {
      if (!scene.elements.any((e) => e.id == id)) continue;
      return doc.withScene(
          i,
          scene.copyWith(elements: [
            for (var e in scene.elements)
              if (e.id != id) e,
          ]));
    }
    return doc;
  }

  /// clipRunStart is where element [id]'s clip starts on the run's clock --
  /// its canvas's start and its own -- or null for one not on a canvas.
  int? clipRunStart(String id) {
    var start = _canvasStart(id);
    if (start == null) return null;
    CanvasElement? found;
    _everyElement(_document, (e, _) {
      if (e.id == id) found = e;
      return e;
    });
    var clip = switch (found) {
      AudioElement a => a.clip,
      VideoElement v => v.clip,
      _ => null,
    };
    return clip == null ? null : start + clip.at;
  }

  /// placeTimedClip puts [e]'s [clip] at frame [run] of the whole run. A
  /// clip on a scene moves to the scene [run] falls in; one on the master or
  /// the backdrop stays on it.
  void placeTimedClip(CanvasElement e, MediaClip clip, int run,
      {bool transient = false}) {
    run = math.max(0, run);
    var master = _document.master;
    var onMaster = master != null && master.elements.any((x) => x.id == e.id);
    int? from;
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((x) => x.id == e.id)) from = i;
    }
    // The master and a document of one scene run on the run's own clock.
    if (onMaster || from == null || !_document.hasScenes) {
      setTimedClip(e, clip.copyWith(at: run), transient: transient);
      return;
    }
    var scenes = _document.allScenes;
    var to = scenes.length - 1;
    for (var i = 0; i < scenes.length; i++) {
      if (run < _document.startOfScene(i) + scenes[i].frames) {
        to = i;
        break;
      }
    }
    var at = run - _document.startOfScene(to);
    if (to == from) {
      setTimedClip(e, clip.copyWith(at: at), transient: transient);
      return;
    }
    var placed = switch (e) {
      VideoElement v => v.copyWith(clip: clip.copyWith(at: at)),
      AudioElement a => a.copyWith(clip: clip.copyWith(at: at)),
      _ => null,
    };
    if (placed == null) return;
    var next = _removedAnywhere(_document, e.id);
    var scene = next.allScenes[to];
    next = next.withScene(
        to, scene.copyWith(elements: [...scene.elements, placed]));
    // Keep it picked, in the selection here or among clips picked elsewhere.
    var picked = clipSelection.contains(e.id);
    apply(next, transient: transient);
    if (picked) {
      _selection = {..._selection}..remove(e.id);
      _offCanvas = {..._offCanvas}..remove(e.id);
      if (_onCanvas(e.id)) {
        _selection = {..._selection, e.id};
      } else {
        _offCanvas = {..._offCanvas, e.id};
      }
      notifyListeners();
    }
  }

  /// deleteElement takes out element [id], for a layers row's delete,
  /// ending its editing first.
  void deleteElement(String id) {
    if (_document.elementById(id) == null) return;
    if (_vectorEditing == id) editVector(null);
    if (editingImage?.id == id) editImage(null);
    _selection = {..._selection}..remove(id);
    apply(_document.removeElement(id));
  }

  /// duplicateSelected copies the chosen elements, offset a little.
  void duplicateSelected() {
    if (_selection.isEmpty) return;
    var next = _document;
    var made = <String>{};
    var ids = <String, String>{};
    for (var element in selectedElements) {
      var copy = element
          .withId(newElementId())
          .withBase(x: element.x + 24, y: element.y + 24);
      next = next.addElement(copy);
      made.add(copy.id);
      ids[element.id] = copy.id;
    }
    // Synth modules copied together are patched to each other.
    apply(synthCopied(next, ids));
    _selection = made;
    notifyListeners();
  }

  bool get canPaste => CanvasController._clipboard.isNotEmpty;

  /// copySelected copies the selection and the clips picked on the timeline
  /// from another canvas, such as the master's music picked from a scene.
  void copySelected() {
    var chosen = [...selectedElements];
    if (_offCanvas.isNotEmpty) {
      _everyElement(_document, (e, _) {
        if (_offCanvas.contains(e.id)) chosen.add(e);
        return e;
      });
    }
    if (chosen.isEmpty) return;
    CanvasController._clipboard = List.unmodifiable(chosen);
    notifyListeners();
  }

  /// _canvasStart is where the canvas holding element [id] starts on the
  /// run's clock (0 for the master), or null when it is on none.
  int? _canvasStart(String id) {
    var master = _document.master;
    if (master != null && master.elements.any((e) => e.id == id)) return 0;
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == id)) {
        return _document.startOfScene(i);
      }
    }
    return null;
  }

  void cutSelected() {
    if (_selection.isEmpty && _offCanvas.isEmpty) return;
    copySelected();
    deleteSelected();
  }

  /// paste drops the clipboard onto the canvas and selects what it added:
  /// with new ids, in their order relative to each other, on top.
  void paste() {
    if (CanvasController._clipboard.isEmpty) return;
    var next = _document;
    var made = <String>{};
    var ids = <String, String>{};
    var elsewhere = <String>{};
    for (var element in CanvasController._clipboard) {
      CanvasElement copy;
      var timed = (element is AudioElement && element.clip.timed) ||
          (element is VideoElement && element.clip.timed);
      // A master clip copied from a scene goes back onto the master at the
      // playhead on the run's clock. One from another scene comes to the
      // playhead's scene: sent back past its own end, it would never play.
      var away = timed &&
              !_onCanvas(element.id) &&
              (_document.master?.elements.any((e) => e.id == element.id) ??
                  false)
          ? 0
          : null;
      var at = away == null ? _frame : math.max(0, runFrame - away);
      if (element is AudioElement && element.clip.timed) {
        // A sound on the timeline goes where the playhead is, on the channel
        // it was copied from -- which is how one channel comes to hold two.
        copy = element
            .copyWith(clip: element.clip.copyWith(at: at))
            .withId(newElementId());
      } else if (element is VideoElement && element.clip.timed) {
        // A timed video likewise: at the playhead, in the same place.
        copy = element
            .copyWith(clip: element.clip.copyWith(at: at))
            .withId(newElementId());
      } else {
        copy = element
            .withId(newElementId())
            .withBase(x: element.x + CanvasController._pasteOffset, y: element.y + CanvasController._pasteOffset);
      }
      if (away != null) {
        if (_addedBeside(next, element.id, copy) case var added?) {
          next = added;
          elsewhere.add(copy.id);
          continue;
        }
      }
      made.add(copy.id);
      ids[element.id] = copy.id;
      next = next.addElement(copy);
    }
    apply(synthCopied(next, ids));
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = made;
    // Picked where they went, as a click on them would pick them.
    _offCanvas = elsewhere;
    notifyListeners();
  }

  /// duplicateElement is the layer list's button: copy and paste in one
  /// press. The clipboard is left alone, so whatever was copied is kept.
  void duplicateElement(String id) {
    var element = _document.elementById(id);
    if (element == null) return;
    var copy = element
        .withId(newElementId())
        .withBase(x: element.x + CanvasController._pasteOffset, y: element.y + CanvasController._pasteOffset);
    apply(synthCopied(_document.addElement(copy), {id: copy.id}));
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = {copy.id};
    notifyListeners();
  }

  /// nudgeSelected moves everything chosen: the arrow keys.
  void nudgeSelected(double dx, double dy, {bool transient = false}) {
    if (_selection.isEmpty) return;
    // A picture picked in a text's Layers moves alone, as its box on the
    // canvas drags it (stage_text_pieces.dart).
    if (_nudgedPiece(dx, dy) case var moved?) {
      replaceElement(moved, transient: transient);
      return;
    }
    // With a picture's layers open and picture layers picked, the arrows
    // move those layers inside it; with the base picked, the picture.
    if (editingImage case var e?) {
      var ids = [for (var l in alignableLayers) l.id];
      if (ids.isNotEmpty) {
        replaceElement(withLayersMoved(e, ids, Offset(dx, dy)),
            transient: transient);
        return;
      }
    }
    var next = _document;
    for (var element in selectedElements) {
      if (element.locked) continue;
      next = next.withElement(_moved(element, dx, dy));
    }
    apply(next, transient: transient);
  }

  /// _nudgedPiece is the one selected text with its picked picture moved
  /// [dx], [dy] on the page, or null where no picture is picked. Moved in the
  /// text's own frame, so a turned text's picture goes the way the arrow
  /// points; a piece held to the right-hand edge counts its side leftwards.
  TextElement? _nudgedPiece(double dx, double dy) {
    if (_selection.length != 1) return null;
    var e = selected;
    if (e is! TextElement || e.locked || e.curve != null) return null;
    var item = textLayer(e);
    if (item == null || !item.isIcon || item.hidden || item.locked) {
      return null;
    }
    var turn = e.rotation * math.pi / 180;
    var c = math.cos(turn), s = math.sin(turn);
    var x = dx * c + dy * s, y = -dx * s + dy * c;
    var across = item.slot.across == TextAlignSpec.right ? -1 : 1;
    var moved =
        item.copyWith(side: item.side + x * across, down: item.down + y);
    return e.copyWith(items: [
      for (var it in e.items) it.id == item.id ? moved : it,
    ]);
  }

  /// alignSelected lines the chosen elements up on one edge or middle of the
  /// selection's own box, not the canvas, so it needs two.
  void alignSelected(CanvasAlign align, {bool transient = false}) {
    // With a picture's layers open, its picked layers, against their box.
    if (editingImage case var e?) {
      var ids = [for (var l in alignableLayers) l.id];
      if (ids.length >= 2) {
        replaceElement(withLayersAligned(e, ids, align), transient: transient);
      }
      return;
    }
    var chosen = [
      for (var e in selectedElements)
        if (!e.locked) e
    ];
    if (chosen.length < 2) return;

    Rect? box;
    for (var element in chosen) {
      box = box == null ? element.bounds : box.expandToInclude(element.bounds);
    }
    if (box == null) return;

    var next = _document;
    for (var element in chosen) {
      var by = align.offset(box, element.bounds);
      if (by == Offset.zero) continue;
      next = next.withElement(_moved(element, by.dx, by.dy));
    }
    apply(next, transient: transient);
  }

  /// spreadSelected puts an even gap between the chosen elements; the end
  /// two stay, so it needs three. Gaps rather than centres, since spacing
  /// different sizes by centre leaves visibly different gaps.
  void spreadSelected(bool across, {bool transient = false}) {
    if (editingImage case var e?) {
      var ids = [for (var l in alignableLayers) l.id];
      if (ids.length >= 3) {
        replaceElement(withLayersSpread(e, ids, across), transient: transient);
      }
      return;
    }
    var chosen = [
      for (var e in selectedElements)
        if (!e.locked) e
    ];
    if (chosen.length < 3) return;
    chosen.sort((a, b) => across
        ? a.bounds.left.compareTo(b.bounds.left)
        : a.bounds.top.compareTo(b.bounds.top));

    var first = chosen.first.bounds;
    var last = chosen.last.bounds;
    var span = across ? last.right - first.left : last.bottom - first.top;
    var filled = chosen.fold<double>(
        0, (sum, e) => sum + (across ? e.bounds.width : e.bounds.height));
    var gap = (span - filled) / (chosen.length - 1);

    var next = _document;
    var at = across ? first.left : first.top;
    for (var element in chosen) {
      var bounds = element.bounds;
      var shift = at - (across ? bounds.left : bounds.top);
      if (shift != 0) {
        next = next.withElement(
            _moved(element, across ? shift : 0, across ? 0 : shift));
      }
      at += (across ? bounds.width : bounds.height) + gap;
    }
    apply(next, transient: transient);
  }

  /// posesRatherThanMoves is whether dragging [element] records a keyframe
  /// instead of moving it. Keyframes are offsets from the resting position,
  /// so moving the rest moves them all and a pose would record nothing.
  /// A drag poses when the document is animated and auto-keyframe is on or
  /// the element is already posed (not merely keyed: a chart's arrival keys
  /// say only how much is drawn). The X and Y fields still move the rest.
  bool posesRatherThanMoves(CanvasElement element) =>
      _document.isAnimated &&
      // Never for an element a path drives: the next point moved would
      // overwrite the pose, so the drag moves its start instead.
      pathDriving(element.id) == null &&
      (_autoKeyframe || (element.track?.posesAnything == true));

  /// _moved is one element shifted, as either a pose or a relocation.
  CanvasElement _moved(CanvasElement element, double dx, double dy) {
    if (!posesRatherThanMoves(element)) {
      return element.withBase(x: element.x + dx, y: element.y + dy);
    }
    var track = (element.track ?? ElementTrack.empty).seededFor(_frame);
    var pose = track.at(_frame);
    return element.withBase(
      track: track.withKey(
          pose.copyWith(frame: _frame, dx: pose.dx + dx, dy: pose.dy + dy)),
    );
  }
}
