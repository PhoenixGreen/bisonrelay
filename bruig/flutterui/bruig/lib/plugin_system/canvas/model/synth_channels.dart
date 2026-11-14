import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
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

/// SynthDesigned is an element as the Chain's Design has it on a frame
/// (see designedNow): how a knob keyed there is read as it plays.
typedef SynthDesigned = CanvasElement Function(CanvasElement e, int frame);

/// synthSynced is [doc] with each speaker's channel playing the patch it
/// hears -- with [designedAt], its knobs keyed in the Chain's Design turning
/// as it plays (see SynthPatch.lanes). A channel already so is left as it
/// is, and a document with no modules is answered as it is.
CanvasDocument synthSynced(CanvasDocument doc, {SynthDesigned? designedAt}) {
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
    if (designedAt != null) {
      var lanes = <String, List<double>>{};
      for (var m in patch.modules) {
        var e = doc.elementById(m.id);
        if (e is SynthModuleElement) {
          lanes.addAll(_lanesOf(e, doc, ch.clip.at, designedAt));
        }
      }
      if (lanes.isNotEmpty) {
        patch = patch.withLanes(lanes, doc.frameRate.toDouble());
      }
    }
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

/// synthCopied is [doc] with the synth parts of a copy made whole: [ids]
/// maps each element copied to its copy, already in [doc]. A copy's cables
/// from modules copied with it come from their copies (its start's too); a
/// cable from one not copied stays where it was. A copied speaker gets a
/// channel of its own, a copy of its original's; a copied task card is
/// about the copied modules where they were copied with it.
CanvasDocument synthCopied(CanvasDocument doc, Map<String, String> ids) {
  SynthPlug plug(SynthPlug p) =>
      (module: ids[p.module] ?? p.module, port: p.port);
  Map<String, SynthPlug> plugs(Map<String, SynthPlug> m) =>
      {for (var MapEntry(:key, :value) in m.entries) key: plug(value)};
  var next = doc;
  for (var copyId in ids.values) {
    var e = next.elementById(copyId);
    if (e is SynthModuleElement) {
      var s = e.start;
      var made = e.copyWith(
          inputs: plugs(e.inputs),
          start: s == null
              ? null
              : SynthModule(e.id, e.module,
                  values: s.values,
                  choices: s.choices,
                  inputs: plugs(s.inputs)));
      if (e.module == SynthModuleKind.out && e.channel.isNotEmpty) {
        var ch = next.elementById(e.channel);
        if (ch is AudioElement) {
          var own = ch.withId(newElementId());
          next = next.addElement(own);
          made = made.copyWith(channel: own.id);
        }
      }
      next = next.withElement(made);
    } else if (e is SynthTaskElement) {
      next = next.withElement(e.copyWith(
          speaker: ids[e.speaker] ?? e.speaker,
          target: e.target == null
              ? null
              : SynthPatch([
                  for (var m in e.target!.modules)
                    SynthModule(ids[m.id] ?? m.id, m.kind,
                        values: m.values,
                        choices: m.choices,
                        inputs: plugs(m.inputs))
                ], ids[e.target!.speaker] ?? e.target!.speaker),
          checks: [
            for (var c in e.checks) c.remapped(ids),
          ]));
    }
  }
  return next;
}

/// synthKeyedKnobs are [e]'s knobs keyed in its Design devices.
Set<String> synthKeyedKnobs(SynthModuleElement e) {
  var ids = <String>{};
  for (var d in e.base.motion.designs) {
    for (var MapEntry(:key, :value) in d.keys.entries) {
      if (value.isNotEmpty) ids.add(key);
    }
    for (var phase in d.phaseKeys.values) {
      for (var MapEntry(:key, :value) in phase.entries) {
        if (value.isNotEmpty) ids.add(key);
      }
    }
  }
  return {
    for (var k in synthKnobs[e.module]!)
      if (ids.contains("synth.${e.module.name}.${k.key}")) k.key
  };
}

/// _lanes keeps each module's lanes as last sampled, for as long as it
/// and the document's frames are as they were: a knob is sampled once a
/// frame, which is not done again at every edit of something else.
final Expando<((int, int, int), Map<String, List<double>>)> _lanes =
    Expando("synthLanes");

/// _lanesOf is [e]'s keyed knobs, each sampled once a frame from frame
/// [from] (its speaker's channel's start) to the document's end.
Map<String, List<double>> _lanesOf(SynthModuleElement e, CanvasDocument doc,
    int from, SynthDesigned designedAt) {
  var knobs = synthKeyedKnobs(e);
  if (knobs.isEmpty) return const {};
  var key = (doc.frames, doc.frameRate, from);
  if (_lanes[e] case (var k, var kept) when k == key) return kept;
  var out = {for (var k in knobs) "${e.id}/$k": <double>[]};
  for (var f = math.max(0, from); f < doc.frames; f++) {
    var now = designedAt(e, f);
    if (now is! SynthModuleElement) continue;
    for (var k in knobs) {
      out["${e.id}/$k"]!.add(now.value(k));
    }
  }
  _lanes[e] = (key, out);
  return out;
}
