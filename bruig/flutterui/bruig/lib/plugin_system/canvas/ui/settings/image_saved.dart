import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/presets_section.dart';
import 'package:flutter/material.dart';

// image_saved.dart is a picture's saved designs (the whole element, to start
// another from). Its looks -- the grade without the photo -- grew into
// actions, which have a section of their own (image_actions.dart).

class ImageSaved extends StatelessWidget {
  final CanvasController controller;
  final ImageElement element;
  const ImageSaved(
      {required this.controller, required this.element, super.key});

  @override
  Widget build(BuildContext context) => KeyedSubtree(
      key: const ValueKey("imageSaved"),
      child: presetsSection(context, controller, element));
}
