part of 'speech_device.dart';

// The Takes panel: the picked section's three slots and what can be done with a
// take, its joins and splits, and Speak all. Part of _SpeechDeviceState: its
// fields, lifecycle and build are in speech_device.dart.

extension _SpeechTakes on _SpeechDeviceState {
  /// _linePanel is the Takes panel: the picked section's slots, what can be
  /// done with the take in the slot picked, joining and splitting, and
  /// Speak all with its progress.
  Widget _linePanel(_SpeechView view) {
    var k = view.k,
        s = view.s,
        lines = view.lines,
        line = view.line,
        queue = view.queue,
        busy = view.busy,
        cantSpeak = view.cantSpeak,
        allSpoken = view.allSpoken,
        reading = view.reading;
    var l = line;
    var ready = !cantSpeak && !busy;
    // The slot picked: as clicked, or the one its take is chosen in.
    var sel = (_slot ?? (l == null || l.chosen < 0 ? 0 : l.chosen))
        .clamp(0, SpeechLine.speechSlots - 1);
    var selTake = l?.slot(sel);
    var letter = String.fromCharCode(65 + sel);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: l == null
            ? Text("Pick a section.", style: k.text(11, colour: s.muted))
            : SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: k.label("Section ${_line + 1} · takes")),
                        for (var t = 0; t < SpeechLine.speechSlots; t++)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: _slotButton(view, _line, l, t,
                                key: ValueKey("speechSlot-$t")),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      // The picked slot's take's actions, if any.
                      if (selTake == null)
                        Text(
                            "Slot $letter is free: Another take, or Speak "
                            "all, speaks into it.",
                            style: k.text(10, colour: s.muted))
                      else ...[
                        Row(children: [
                          Expanded(
                            child: Text(
                                "Take $letter · "
                                "${selTake.length.toStringAsFixed(1)} s"
                                "${selTake.shaped ? " · shaped" : ""}"
                                "${selTake.saved ? " · in Audio" : ""}",
                                style: k.text(10.5, colour: s.text)),
                          ),
                          k.button(
                              c.speechHeard == selTake.assetId
                                  ? "Stop"
                                  : "Hear",
                              () => _run(
                                  () => c.hearSlot(widget.channel, _line, sel)),
                              key: const ValueKey("speechHear"),
                              icon: c.speechHeard == selTake.assetId
                                  ? Icons.stop
                                  : Icons.play_arrow,
                              small: true),
                        ]),
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          k.button(
                              selTake.saved ? "Saved" : "Save",
                              selTake.saved || busy
                                  ? null
                                  : () => _run(() async => (await c.saveTake(
                                          widget.channel, _line, sel))
                                      .$2),
                              key: const ValueKey("speechSave"),
                              icon: Icons.save_alt,
                              small: true,
                              tip: "Keep it in the Audio library"),
                          k.button(
                              "Add to timeline",
                              busy
                                  ? null
                                  : () => _run(() =>
                                      c.addTake(widget.channel, _line, sel)),
                              key: const ValueKey("speechAddTake"),
                              icon: Icons.playlist_add,
                              small: true,
                              tip: "A clip of this take at the playhead, "
                                  "and in the Audio library"),
                          k.button(
                              "Remove",
                              busy
                                  ? null
                                  : () =>
                                      c.removeTake(widget.channel, _line, sel),
                              key: const ValueKey("speechRemoveTake"),
                              icon: Icons.delete_outline,
                              small: true,
                              tip: selTake.saved
                                  ? "Empty the slot: the Audio library "
                                      "keeps its copy"
                                  : "Empty the slot: the take is gone"),
                          k.button(
                              "Replace",
                              ready
                                  ? () => _run(() =>
                                      c.replaceTake(widget.channel, _line, sel))
                                  : null,
                              key: const ValueKey("speechReplace"),
                              icon: Icons.autorenew,
                              small: true,
                              tip: "Speak it again into this slot, as it "
                                  "is said now"),
                        ]),
                      ],
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: k.button(
                              "Join",
                              _line + 1 < lines.length && !busy && !reading
                                  ? () =>
                                      c.joinSpeechLine(widget.channel, _line)
                                  : null,
                              key: const ValueKey("speechJoin"),
                              icon: Icons.call_merge,
                              tip: "Join with the next section: one take"),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: k.button(
                              "Split",
                              CanvasController.speechSplitAt(l.text) != null &&
                                      !busy &&
                                      !reading
                                  ? () =>
                                      c.splitSpeechLine(widget.channel, _line)
                                  : null,
                              key: const ValueKey("speechSplit"),
                              icon: Icons.content_cut,
                              tip: "Two sections, cut at the sentence's end "
                                  "nearest its middle"),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: k.button(
                              "Another take",
                              ready && l.freeSlot >= 0
                                  ? () => _run(() => c.anotherTake(
                                      widget.channel, l,
                                      slot: sel))
                                  : null,
                              key: const ValueKey("speechAnother"),
                              icon: Icons.refresh,
                              tip: l.freeSlot < 0
                                  ? "All three slots are in use: pick one, "
                                      "and Replace it"
                                  : "Speak the section again into a free "
                                      "slot, its takes kept to compare"),
                        ),
                      ]),
                    ]),
              ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 32,
        // While it speaks, Stop, to let go of a voice that takes too long.
        child: queue != null
            ? FilledButton.icon(
                key: const ValueKey("speechStop"),
                style: FilledButton.styleFrom(
                  backgroundColor: s.arm,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                ),
                onPressed: () => c.stopSpeaking(widget.channel),
                icon: const Icon(Icons.stop, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text("Stop",
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              )
            : FilledButton.icon(
                key: const ValueKey("speechSpeak"),
                style: FilledButton.styleFrom(
                  backgroundColor: s.meterLow,
                  foregroundColor: const Color(0xFF0D2416),
                  disabledBackgroundColor: s.raised,
                  disabledForegroundColor: s.muted,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                ),
                // Every line spoken: nothing to do; Another
                // take or a new direction respeaks.
                onPressed: busy || cantSpeak || allSpoken ? null : _speakAll,
                icon: busy
                    ? SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: s.muted))
                    : const Icon(Icons.record_voice_over, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      busy
                          ? "Joining…"
                          : allSpoken
                              ? "All spoken"
                              : "Speak all",
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
      ),
      // Only while it works: how far, and that it is in the background.
      if (busy) ...[
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
              key: const ValueKey("speechProgress"),
              minHeight: 4,
              color: s.meterLow,
              backgroundColor: s.raised),
        ),
        const SizedBox(height: 3),
        Text(
            queue != null
                ? "${queue.length} "
                    "${queue.length == 1 ? "section" : "sections"} to speak · "
                    "keep working meanwhile"
                : "Joining the sections into the clip…",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: k.text(10, colour: s.muted)),
      ],
    ]);
  }
}
