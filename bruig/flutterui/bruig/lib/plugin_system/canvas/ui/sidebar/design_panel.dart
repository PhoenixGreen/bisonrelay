import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/scenes_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/panel_stack.dart';
import 'package:flutter/material.dart';

// design_panel.dart is the three things you use to build a canvas, in one
// column: what you can add, what is already there, and the settings of
// whichever of it is selected.
//
// They were three tabs, and the cost of that was paid on every element: add
// one from the first tab, change it on the third, look for it on the second.
// Two of the three ended up carrying copies of the settings just to shorten
// the journey, which is how you can tell tabs were the wrong shape -- the
// work does not divide the way the tabs did.
//
// A stack rather than a fixed split, so the arrangement is the reader's:
// each panel opens, closes, takes the height it is given and sits where it is
// put, and all of that is remembered. See panel_stack.dart.

class CanvasDesignPanel extends StatefulWidget {
  final CanvasController controller;
  const CanvasDesignPanel({required this.controller, super.key});

  @override
  State<CanvasDesignPanel> createState() => _CanvasDesignPanelState();
}

class _CanvasDesignPanelState extends State<CanvasDesignPanel> {
  CanvasController get controller => widget.controller;

  /// The three bodies, built once and handed to the stack unchanged.
  ///
  /// This is the whole of what keeps the panel quick. The stack rebuilds
  /// whenever a heading changes -- the layer count, the name of what is
  /// selected -- and every notification from the controller is one of those:
  /// it notifies on every pixel of a drag. Rebuilt with it, all three bodies
  /// were laid out sixty times a second, and the settings alone are twenty or
  /// thirty text fields.
  ///
  /// Handed the same widget instance twice, Flutter leaves that subtree
  /// alone. So each body decides for itself when to rebuild -- the layers and
  /// the settings listen for what they show, and the palette of things to add
  /// does not listen at all, because nothing about the document changes it.
  late Widget _add;
  late Widget _scenes;
  late Widget _layers;
  late Widget _settings;

  @override
  void initState() {
    super.initState();
    _makeBodies();
  }

  @override
  void didUpdateWidget(CanvasDesignPanel old) {
    super.didUpdateWidget(old);
    // Built once, but once *per controller*. Holding the first one's bodies
    // after being handed a second would leave the whole column bound to a
    // document nobody is looking at any more -- a panel that is cheap because
    // it is stale is not cheap, it is broken.
    if (old.controller != widget.controller) _makeBodies();
  }

  void _makeBodies() {
    _add = CanvasElementsPanel(controller: controller);
    _scenes = CanvasScenesPanel(controller: controller);
    _layers = CanvasLayersPanel(controller: controller);
    _settings = _SettingsBody(controller: controller);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // The headings, and only the headings: two of the three say something
        // about the document. A panel whose name is out of date is worse than
        // one with no name.
        listenable: controller,
        builder: (context, _) => _stack(context),
      );

  Widget _stack(BuildContext context) => CanvasPanelStack(
        storageKey: "canvasDesign",
        panels: [
          CanvasStackPanel(
            id: "add",
            label: "Add",
            icon: Icons.category_outlined,
            hint: "Click to add one in the middle of the canvas, or drag it "
                "where you want it.",
            body: _add,
          ),
          // Between what can be added and what is on this canvas, because
          // that is the order the questions come in: which canvas am I on,
          // then what is on it.
          CanvasStackPanel(
            id: "scenes",
            label: "Scenes",
            icon: Icons.movie_outlined,
            trailing: controller.document.hasScenes
                ? "${controller.document.at + 1}/"
                    "${controller.document.allScenes.length}"
                : null,
            hint: "The canvases this document plays through, in order. Drag "
                "one up or down to change when it plays.",
            // Shut to begin with: most documents are one canvas, and a list
            // with one row in it is a hole in a column that has three other
            // panels wanting the room.
            startsOpen: false,
            body: _scenes,
          ),
          CanvasStackPanel(
            id: "layers",
            label: "Layers",
            icon: Icons.layers_outlined,
            // The count on the heading rather than inside the list, so a shut
            // panel still says how much is behind it. One more than the
            // elements, because the background is a layer too.
            trailing: "${controller.document.elements.length + 1}",
            body: _layers,
          ),
          CanvasStackPanel(
            id: "settings",
            // Named for what is selected. The settings no longer head
            // themselves with the element's name, so this is what says what is
            // being edited -- and "Image settings" is a more useful heading
            // than a phrase that is true of everything.
            label: elementSettingsTitle(controller),
            icon: Icons.tune,
            hint: elementSettingsHint,
            body: _settings,
          ),
        ],
      );
}

/// _SettingsBody is the settings of whatever is selected.
///
/// Its own widget so that it can be built once and handed to the stack, and
/// so that its listener is its own: it is by far the most expensive thing in
/// this column, and it must not be rebuilt because a heading elsewhere
/// changed.
class _SettingsBody extends StatefulWidget {
  final CanvasController controller;
  const _SettingsBody({required this.controller});

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  CanvasController get controller => widget.controller;

  /// _scroll keeps the column where it was.
  ///
  /// Held here rather than left to the scroll view, and remembered *per
  /// element*: selecting another element and coming back rebuilt this from
  /// scratch and put the column back at the top, so anybody working on the
  /// animation section at the bottom of a text element's settings had to
  /// scroll down to it again every time they clicked on the canvas.
  final ScrollController _scroll = ScrollController();

  /// _at is where each element's settings were left, by element id.
  ///
  /// A map rather than one number: the panels are different lengths, so one
  /// remembered offset would put a short element's settings somewhere they do
  /// not reach.
  static final Map<String, double> _at = {};

  /// _showing is whose settings are on screen, so the offset is filed under
  /// the right element when the selection changes.
  String? _showing;

  @override
  void initState() {
    super.initState();
    _showing = controller.selected?.id;
    controller.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _remember();
    controller.removeListener(_onSelectionChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _remember() {
    var id = _showing;
    if (id != null && _scroll.hasClients) _at[id] = _scroll.offset;
  }

  /// _onSelectionChanged files the offset under whoever is leaving and
  /// restores whoever is arriving.
  void _onSelectionChanged() {
    var id = controller.selected?.id;
    if (id == _showing) return;
    _remember();
    _showing = id;

    // After the frame: the new element's settings are a different height and
    // there is nothing to scroll to until they have been laid out.
    var wanted = id == null ? 0.0 : (_at[id] ?? 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(wanted.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) => CanvasWatch<int>(
        listenable: controller,
        // Every change except the ones about the view. See
        // CanvasController.revision, which counts them the safe way round: a
        // notification moves it unless it has been deliberately marked as
        // being about the zoom, the pan, the frame's shape or the tool in
        // hand -- none of which these controls show, and all of which used to
        // lay out twenty or thirty text fields for nothing.
        //
        // Keyed on that alone, rather than on a list of what the settings
        // happen to read. That list was tried and it was wrong within the
        // hour: these controls also show the retouching brush, its size, its
        // hardness, whether a stroke is waiting -- none of it in the document.
        // A key that has to name everything is a key that goes stale the next
        // time somebody adds a control.
        select: () => controller.revision,
        builder: (context, _) => SingleChildScrollView(
          controller: _scroll,
          // A clear gap under the header. It is a coloured band, so settings
          // starting immediately beneath it read as being part of it.
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: CanvasControlScope(
            maxWidth: 240,
            child: elementSettingsBody(context, controller),
          ),
        ),
      );
}
