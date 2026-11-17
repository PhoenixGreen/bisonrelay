part of 'panel_kit.dart';

// panel_kit_hold.dart keeps a settings panel's untouched sections as they
// were while a pointer is held in a gesture. A drag on the canvas, or of one
// control, changes the element on every step, and building every section
// again for each costs several frames' worth. So the section the pointer
// went down in is built as usual -- or, for a drag on the canvas, the
// sections that show where the element is -- and the rest keep what they
// last built. When the pointer lifts, or anything happens that is not a
// gesture's step, the whole panel is built again: a kept control holds the
// element as it was, and must not be pressed with it.

/// PanelHold is one settings panel's hold, provided over it by
/// [PanelHoldScope]. Sections ask [keeps].
class PanelHold {
  /// gesturing is whether an edit gesture is under way: beginInteraction
  /// to endInteraction. Sections are kept only inside one.
  final bool Function() gesturing;

  /// onRelease builds the panel again once the last pointer lifts.
  final VoidCallback onRelease;

  PanelHold({required this.gesturing, required this.onRelease}) {
    _Pointers.watch(this);
  }

  /// epoch moves with every change that is not a gesture's step (the
  /// controller's chrome): a section kept at another epoch is built again.
  int epoch = 0;

  void dispose() => _Pointers.unwatch(this);

  /// keeps is whether section [key] keeps what it last built: a gesture is
  /// under way with a pointer held, and the pointer went down elsewhere --
  /// in another of this panel's sections, or outside the panel, where a
  /// section that [followsStage] (the element's place and size) stays live.
  bool keeps(String key, {bool followsStage = false}) {
    if (!_Pointers.held || !gesturing()) return false;
    var live = _Pointers.claimed(this);
    return live == null ? !followsStage : !live.contains(key);
  }

  /// claim marks [pointer] as gone down in section [key] of this panel, and
  /// in every section round it: a section inside another is built again
  /// only if the one holding it is.
  void claim(int pointer, String key) {
    var c = _Pointers._claim;
    if (c != null && c.$1 == pointer && identical(c.$2, this)) {
      c.$3.add(key);
    } else {
      _Pointers._claim = (pointer, this, {key});
    }
  }
}

/// PanelHoldScope provides a [PanelHold] to the sections under it. It never
/// notifies: sections read it as they build.
class PanelHoldScope extends InheritedWidget {
  final PanelHold hold;
  const PanelHoldScope({required this.hold, required super.child, super.key});

  static PanelHold? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PanelHoldScope>()?.hold;

  @override
  bool updateShouldNotify(PanelHoldScope old) => false;
}

/// _HeldBody is a section's body kept by a [PanelHold]: the same widget as
/// last built, so nothing under it is built again.
class _HeldBody {
  Widget? _built;
  int _epoch = -1;

  Widget of(BuildContext context, String key, Widget Function() build,
      {bool followsStage = false}) {
    var hold = PanelHoldScope.of(context);
    var built = _built;
    if (hold != null &&
        built != null &&
        _epoch == hold.epoch &&
        hold.keeps(key, followsStage: followsStage)) {
      return built;
    }
    _epoch = hold?.epoch ?? -1;
    return _built = build();
  }
}

/// _Pointers follows every pointer in the app, through the gesture
/// binding's global route: which are down, the last to go down, and the
/// section of which panel it went down in.
abstract final class _Pointers {
  static final Set<int> _down = {};
  static int? _last;
  static (int, PanelHold, Set<String>)? _claim;
  static final Set<PanelHold> _holds = {};
  static bool _routed = false;

  static bool get held => _down.isNotEmpty;

  static void watch(PanelHold hold) {
    _holds.add(hold);
    if (_routed) return;
    _routed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  static void unwatch(PanelHold hold) => _holds.remove(hold);

  /// claimed is the sections of [hold] the held pointer went down in, or
  /// null where it went down outside it. A section's listener claims the
  /// pointer before this route sees it go down.
  static Set<String>? claimed(PanelHold hold) {
    var c = _claim;
    return c != null && c.$1 == _last && identical(c.$2, hold) ? c.$3 : null;
  }

  static void _route(PointerEvent event) {
    if (event is PointerDownEvent) {
      _down.add(event.pointer);
      _last = event.pointer;
    } else if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerRemovedEvent) {
      if (_down.remove(event.pointer) && _down.isEmpty) {
        _claim = null;
        for (var hold in _holds.toList()) {
          hold.onRelease();
        }
      }
    }
  }
}
