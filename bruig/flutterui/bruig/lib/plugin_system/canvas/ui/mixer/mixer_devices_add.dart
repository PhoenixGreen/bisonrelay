part of 'mixer_plugins.dart';

// The chain's add buttons, and the panel they open: a search and the device
// kinds by family. Part of mixer_plugins.dart.

/// AddDeviceSlot is the chain's "+" on strip [owner], adding a device last.
class AddDeviceSlot extends StatelessWidget {
  final CanvasController controller;

  /// owner is the strip it adds to: see CanvasController.devicesOf.
  final String owner;
  final double height;

  const AddDeviceSlot(
      {required this.controller,
      required this.owner,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    // A sound's channel may take a generator (Speech, making its clips);
    // MIDI channels, buses, videos and channels with speech take none.
    var lane =
        controller.timelineChannels.where((l) => l.key == owner).firstOrNull;
    var canSpeak = lane != null &&
        !lane.video &&
        !controller.instrumentChannel(owner) &&
        controller.speechOf(owner) == null;
    devicePresets.load();
    return ListenableBuilder(
      listenable: devicePresets,
      builder: (context, _) => AddSlot(
        id: "addDeviceOpen",
        title: "Add a device",
        height: height,
        groups: [
          // Kept with Save as a preset: a device, or a whole chain.
          if (devicePresets.presets.where((p) => presetHolds(p)) case var kept
              when kept.isNotEmpty)
            (
              "Presets",
              [
                for (var p in kept)
                  (
                    "addPreset-${p.id}",
                    p.name,
                    () => useDevicePreset(controller, owner, p.data),
                  ),
              ]
            ),
          if ([
            for (var part in removableParts)
              if (controller.partRemoved(owner, part)) part
          ]
              case var gone when gone.isNotEmpty)
            (
              "Channel strip",
              [
                for (var part in gone)
                  (
                    "addPart-$part",
                    switch (part) {
                      chainEq => "EQ",
                      chainComp => "Compressor",
                      stripDucked => "Ducked by others",
                      _ => "Ducker",
                    },
                    () => controller.restorePart(owner, part),
                  ),
              ]
            ),
          // A voice can be sung: the Vocaliser, among its effects.
          if (lane != null &&
              controller.speechOf(owner) != null &&
              controller.vocaliserOf(owner) == null)
            (
              "Voice",
              [
                (
                  "addDevice-vocaliser",
                  "Vocaliser",
                  () {
                    controller.beginInteraction();
                    controller.setVocaliser(owner, const VocaliserSpec());
                    controller.endInteraction();
                    controller.openEffects(owner, device: "vocaliser");
                  }
                ),
              ]
            ),
          if (canSpeak)
            (
              "Generators",
              [
                (
                  "addDevice-speech",
                  "Speech",
                  () {
                    controller.beginInteraction();
                    controller.setSpeech(owner, const SpeechSpec());
                    controller.endInteraction();
                    controller.showSpeech(owner);
                  }
                ),
              ]
            ),
          for (var group in DeviceGroup.values)
            (
              group.label,
              [
                for (var kind in DeviceKind.values)
                  if (kind.group == group)
                    (
                      "addDevice-${kind.name}",
                      kind.label,
                      () {
                        var now = controller.devicesOf(owner);
                        controller.beginInteraction();
                        controller
                            .setDevicesOf(owner, [...now, MixDevice(kind)]);
                        controller.endInteraction();
                        controller.openEffects(owner,
                            device: deviceKey(deviceIdAt(
                                controller.devicesOf(owner), now.length)));
                      }
                    ),
              ]
            ),
        ],
      ),
    );
  }
}

/// AddSlot is the chain's dashed "+", opening a search and each family.
class AddSlot extends StatelessWidget {
  /// id keys the slot itself; each item is keyed by its own key.
  final String id;
  final String title;
  final double height;

  /// groups are each family's name and its items: a key, a name, and what
  /// picking it does.
  final List<(String, List<(String, String, VoidCallback)>)> groups;

  const AddSlot(
      {required this.id,
      required this.title,
      required this.height,
      required this.groups,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return MenuAnchor(
      builder: (context, menu, _) => Tooltip(
        message: title,
        child: InkWell(
          key: ValueKey(id),
          borderRadius: BorderRadius.circular(8),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: SizedBox(
            width: 30,
            height: height,
            child: CustomPaint(
              painter: _DashedSlot(look.studio.edge),
              child: Center(
                child: Icon(Icons.add, size: 16, color: look.studio.muted),
              ),
            ),
          ),
        ),
      ),
      menuChildren: [
        Builder(
          builder: (context) => _AddPanel(
            title: title,
            groups: groups,
            onPicked: () => MenuController.maybeOf(context)?.close(),
          ),
        ),
      ],
    );
  }
}

class _DashedSlot extends CustomPainter {
  final Color colour;
  _DashedSlot(this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    var r = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(3), const Radius.circular(8));
    var paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var metric in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedSlot old) => old.colour != colour;
}

/// _AddPanel is what "+" opens: a search, and kinds by family, four a row.
class _AddPanel extends StatefulWidget {
  final String title;
  final List<(String, List<(String, String, VoidCallback)>)> groups;
  final VoidCallback onPicked;
  const _AddPanel(
      {required this.title, required this.groups, required this.onPicked});

  @override
  State<_AddPanel> createState() => _AddPanelState();
}

class _AddPanelState extends State<_AddPanel> {
  String _q = "";

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var q = _q.toLowerCase();
    var shown = [
      for (var (family, items) in widget.groups)
        (
          family,
          [
            for (var item in items)
              if (q.isEmpty ||
                  item.$2.toLowerCase().contains(q) ||
                  family.toLowerCase().contains(q))
                item
          ]
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    var columns = math.min(4, math.max(1, shown.length));
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 150.0 * columns + 8 * (columns - 1),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 30,
                child: TextField(
                  key: const ValueKey("addSlotSearch"),
                  autofocus: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText:
                        "Find ${widget.title.toLowerCase().replaceFirst("add ", "")}",
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5)),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (var (family, items) in shown)
                  SizedBox(
                    width: 150,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                            child: Text(family.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 9.5,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w500,
                                    color: look.studio.muted)),
                          ),
                          for (var (key, label, pick) in items)
                            InkWell(
                              key: ValueKey(key),
                              borderRadius: BorderRadius.circular(5),
                              onTap: () {
                                widget.onPicked();
                                pick();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                child: Text(label,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                        ]),
                  ),
              ]),
            ]),
      ),
    );
  }
}
