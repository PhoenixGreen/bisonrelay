import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:flutter/material.dart';

// canvas_sidebar_host.dart puts the Canvas sidebar up for a test: the real
// one (CanvasSidebar), as the Canvas page builds it, so that a test of a
// panel is a test of that panel where the app shows it.

/// designSidebar is the sidebar on its Design sidebar, which holds Add,
/// Scenes, Vocal cues, Layers, Colour and the selection's settings.
Widget designSidebar(CanvasController controller) =>
    CanvasSidebarHost(controller: controller, current: "design");

/// assetsSidebar is the sidebar on its Assets sidebar.
Widget assetsSidebar(CanvasController controller) =>
    CanvasSidebarHost(controller: controller, current: "assets");

/// CanvasSidebarHost holds the sidebar's layout, as the Canvas page does,
/// so its menus and its icons work. [laid] is told each change.
class CanvasSidebarHost extends StatefulWidget {
  final CanvasController controller;

  /// current is the id of the sidebar shown first.
  final String current;
  final ValueChanged<SidebarLayout>? laid;

  const CanvasSidebarHost(
      {required this.controller, required this.current, this.laid, super.key});

  @override
  State<CanvasSidebarHost> createState() => _CanvasSidebarHostState();
}

class _CanvasSidebarHostState extends State<CanvasSidebarHost> {
  late SidebarLayout _layout = SidebarLayout(current: widget.current);
  late SidebarPanelBodies _bodies = _bodiesFor(widget.controller);

  static SidebarPanelBodies _bodiesFor(CanvasController controller) =>
      SidebarPanelBodies(
        controller: controller,
        onOpen: (_, __) async {},
        onPublish: (_, __) {},
        onNew: (_, __) async {},
        onChoosePreset: (_, __) {},
      );

  @override
  void didUpdateWidget(CanvasSidebarHost old) {
    super.didUpdateWidget(old);
    // The bodies are built once for a controller.
    if (old.controller != widget.controller) {
      _bodies = _bodiesFor(widget.controller);
    }
  }

  @override
  Widget build(BuildContext context) => CanvasSidebar(
        controller: widget.controller,
        layout: _layout,
        onLayout: (next) {
          setState(() => _layout = next);
          widget.laid?.call(next);
        },
        onHide: () {},
        bodies: _bodies,
        onCustomise: () {},
      );
}
