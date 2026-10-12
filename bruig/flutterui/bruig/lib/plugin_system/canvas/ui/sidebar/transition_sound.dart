import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// transition_sound.dart is the sound a transition carries: picked from the
// Audio library, and heard wherever the transition is. See
// CanvasDocument.transitionSounds.

/// CanvasTransitionSound picks [value]'s sound, how loud it is and how early
/// it starts -- and puts the same sound on every transition.
class CanvasTransitionSound extends StatefulWidget {
  final SceneTransition value;
  final ValueChanged<SceneTransition> onChanged;

  /// onEvery puts [value]'s sound on every transition of the document.
  final ValueChanged<SceneTransition> onEvery;

  const CanvasTransitionSound(
      {required this.value,
      required this.onChanged,
      required this.onEvery,
      super.key});

  @override
  State<CanvasTransitionSound> createState() => _CanvasTransitionSoundState();
}

class _CanvasTransitionSoundState extends State<CanvasTransitionSound> {
  List<LibraryAsset> _sounds = const [];

  @override
  void initState() {
    super.initState();
    _read();
    CanvasLibrary.changes.addListener(_read);
  }

  @override
  void dispose() {
    CanvasLibrary.changes.removeListener(_read);
    super.dispose();
  }

  Future<void> _read() async {
    var all = await CanvasLibrary.list(kind: AssetKind.audio);
    // Short sounds first: a transition's sound is an effect, not a song.
    all.sort((a, b) => a.length.compareTo(b.length));
    if (mounted) setState(() => _sounds = all);
  }

  @override
  Widget build(BuildContext context) {
    var t = widget.value;
    var known = _sounds.any((a) => a.id == t.sound);
    return CanvasControlGroup(
      key: const ValueKey("transitionSound"),
      label: "Sound",
      children: [
        CanvasDropdown<String>(
          key: const ValueKey("transitionSoundPick"),
          label: "Heard",
          value: t.sound.isEmpty || !known ? "" : t.sound,
          width: 150,
          options: [
            ("", t.sound.isNotEmpty && !known ? t.soundName : "Nothing"),
            for (var a in _sounds) (a.id, a.name),
          ],
          onChanged: (id) {
            if (id.isEmpty) {
              widget.onChanged(t.copyWith(sound: "", soundName: ""));
              return;
            }
            var a = _sounds.firstWhere((a) => a.id == id);
            widget.onChanged(t.copyWith(
                sound: a.id, soundName: a.name, soundLength: a.length));
          },
        ),
        if (t.sound.isNotEmpty) ...[
          CanvasNumberField(
            key: const ValueKey("transitionSoundVolume"),
            label: "Volume",
            value: t.soundVolume * 100,
            min: 0,
            max: 200,
            suffix: "%",
            width: 58,
            onChanged: (v) => widget.onChanged(t.copyWith(soundVolume: v / 100)),
          ),
          CanvasNumberField(
            key: const ValueKey("transitionSoundLead"),
            label: "Early by",
            value: t.soundLead.toDouble(),
            min: -240,
            max: 240,
            width: 54,
            onChanged: (v) => widget.onChanged(t.copyWith(soundLead: v.round())),
          ),
          CanvasIconButton(
            key: const ValueKey("transitionSoundEvery"),
            icon: Icons.library_add_outlined,
            tooltip: "Use this sound on every transition",
            onPressed: () => widget.onEvery(t),
          ),
        ],
      ],
    );
  }
}
