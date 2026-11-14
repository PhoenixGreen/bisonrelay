import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';

// synth_channels.dart keeps what each synth speaker plays made from the
// modules on the canvas and the cables between them: every change to a
// module -- a knob, a cable, one added or taken away -- writes the patch the
// speaker hears into its channel's part (see InstrumentPart.patch), so the
// keyboard, the timeline, the mix and a video export all hear it. As
// score_channels.dart does for a score.

/// synthPatchOf is the patch speaker [speaker] plays, of the modules in
/// [elements]: only those it hears, so a knob on a module patched into
/// nothing changes nothing.
SynthPatch synthPatchOf(List<CanvasElement> elements, String speaker) {
  var all = SynthPatch([
    for (var e in elements)
      if (e is SynthModuleElement) e.asModule
  ], speaker);
  return SynthPatch(all.heard, speaker);
}

/// samePatch is whether two patches are the same modules, settings and
/// cables.
bool samePatch(SynthPatch a, SynthPatch b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());

/// synthSynced is [doc] with each speaker's channel playing the patch it
/// hears. A channel already so is left as it is, and a document with no
/// modules is answered as it is.
CanvasDocument synthSynced(CanvasDocument doc) {
  List<SynthModuleElement>? speakers;
  for (var e in doc.elements) {
    if (e is SynthModuleElement &&
        e.module == SynthModuleKind.out &&
        e.channel.isNotEmpty) {
      (speakers ??= []).add(e);
    }
  }
  if (speakers == null) return doc;
  var next = doc;
  for (var s in speakers) {
    var ch = next.elementById(s.channel);
    if (ch is! AudioElement || ch.instrument == null) continue;
    var part = ch.instrument!;
    var patch = synthPatchOf(doc.elements, s.id);
    if (part.sound == InstrumentSound.patch &&
        part.patch != null &&
        samePatch(part.patch!, patch)) {
      continue;
    }
    next = next.withElement(ch.copyWith(
        instrument: part.copyWith(sound: InstrumentSound.patch, patch: patch)));
  }
  return next;
}

/// synthSpeakerOf is the speaker module whose channel is [channel], if it
/// is one's.
SynthModuleElement? synthSpeakerOf(CanvasDocument doc, String channel) {
  for (var e in doc.elements) {
    if (e is SynthModuleElement &&
        e.module == SynthModuleKind.out &&
        e.channel == channel) {
      return e;
    }
  }
  return null;
}

/// synthSpeakersHearing are the speakers module [id]'s sound reaches: the
/// keyboard's keys play on these.
List<SynthModuleElement> synthSpeakersHearing(CanvasDocument doc, String id) =>
    [
      for (var e in doc.elements)
        if (e is SynthModuleElement &&
            e.module == SynthModuleKind.out &&
            synthPatchOf(doc.elements, e.id).byId(id) != null)
          e,
    ];
