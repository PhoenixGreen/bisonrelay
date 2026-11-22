import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';

// element_offers.dart is what the Add panel offers for each element kind,
// and in what order. It is kept out of element_factory.dart because it needs
// the controller (which puts down a synth rack and a code lesson), and the
// factory, which the controller uses, should not import the controller.

/// AddOffer is one thing the Add panel offers: a chip that adds it in the
/// middle of the page when pressed, or where it is let go when dragged.
class AddOffer {
  /// label is the chip's name.
  final String label;

  /// icon is the chip's picture.
  final IconData icon;

  /// add puts it on the canvas, centred on [center] (the page's middle
  /// without one), and selected.
  final void Function(CanvasController controller, {Offset? center}) add;

  const AddOffer(this.label, this.icon, this.add);
}

/// _plain is the offer of one empty element of [kind], as the factory
/// makes it.
AddOffer _plain(ElementKind kind) =>
    AddOffer(kind.label, iconForKind(kind), (c, {center}) {
      c.addElement(newElement(kind, c.document, center: center));
    });

/// addOffersFor is what the Add panel offers for [kind]. Usually the kind
/// itself. More than one where a kind is added in more than one form (a
/// sound as a speaker or as an instrument). None for a kind that is made
/// another way, and each such case says which way.
List<AddOffer> addOffersFor(ElementKind kind) => switch (kind) {
      ElementKind.text ||
      ElementKind.shape ||
      ElementKind.image ||
      ElementKind.vector ||
      ElementKind.line ||
      ElementKind.button ||
      ElementKind.counter ||
      ElementKind.sheet ||
      ElementKind.metronome ||
      ElementKind.playTask ||
      ElementKind.video ||
      ElementKind.background ||
      ElementKind.layout ||
      ElementKind.player ||
      ElementKind.character3d ||
      ElementKind.object3d ||
      ElementKind.path ||
      ElementKind.sprite ||
      ElementKind.tileMap ||
      ElementKind.camera =>
        [_plain(kind)],
      // The Data element: a sheet shown as a table, switched to a chart in
      // its settings, so it is offered by the name of the two.
      ElementKind.table => [
          AddOffer("Data", Icons.dataset_outlined, (c, {center}) {
            c.addElement(newElement(kind, c.document, center: center));
          }),
        ],
      // A speaker, and an instrument: an Audio element playing a part from
      // keys, with its own channel.
      ElementKind.audio => [
          _plain(kind),
          AddOffer("Instrument", Icons.piano, (c, {center}) {
            c.addElement(newInstrument(c.document, center: center));
          }),
        ],
      // Modules are put down as a rack, patched and ready, with the hidden
      // channel that plays it; one alone comes from a module's settings.
      ElementKind.synth => [
          AddOffer("Synth", Icons.cable,
              (c, {center}) => c.addSynthRack(center: center)),
        ],
      // A Code panel is put down with the Run panel that runs it.
      ElementKind.code => [
          AddOffer("Code", Icons.code,
              (c, {center}) => c.addCodeLesson(center: center)),
        ],
      // A chart is the Data element switched to a chart in its settings.
      ElementKind.chart => const [],
      // A 3D stage and parallax scenery are a background's backdrop, chosen
      // in the background's settings.
      ElementKind.stage || ElementKind.parallax => const [],
      // A synth task is put beside its rack from a module's settings.
      ElementKind.synthTask => const [],
      // A Run panel comes with its Code panel, from the Code chip.
      ElementKind.codeRun => const [],
      // A code task is put under its Code panel from that panel's settings.
      ElementKind.codeTask => const [],
    };

/// _gridOrder is the kinds the Add panel offers, in the order it shows them.
/// It is the one thing here kept by hand: a kind that offers something and
/// is missing from it, or one that offers nothing and is in it, fails the
/// test of the Add panel in canvas_editor_layers_test.dart.
const List<ElementKind> _gridOrder = [
  ElementKind.text,
  ElementKind.shape,
  ElementKind.image,
  ElementKind.vector,
  ElementKind.line,
  ElementKind.table,
  ElementKind.button,
  ElementKind.counter,
  ElementKind.audio,
  ElementKind.synth,
  ElementKind.sheet,
  ElementKind.metronome,
  ElementKind.code,
  ElementKind.playTask,
  ElementKind.video,
  ElementKind.background,
  ElementKind.layout,
  ElementKind.player,
  ElementKind.character3d,
  ElementKind.object3d,
  ElementKind.path,
  ElementKind.sprite,
  ElementKind.tileMap,
  ElementKind.camera,
];

/// addOffers is every offer, in the order the grid shows them: what is
/// wanted most first, not the kinds' own order.
final List<AddOffer> addOffers = [
  for (var kind in _gridOrder) ...addOffersFor(kind),
];
