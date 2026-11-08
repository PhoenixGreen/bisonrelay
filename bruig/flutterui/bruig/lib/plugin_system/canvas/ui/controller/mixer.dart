part of '../canvas_controller.dart';

// The mixer and automation.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasMixing on CanvasController {
  /// solo is which channels are soloed. The session's rather than the
  /// document's: an export plays every channel that is not muted.
  Set<String> get solo => _solo;

  /// toggleSolo solos or unsolos a channel, by its key.
  void toggleSolo(String id) {
    if (!_solo.remove(id)) _solo.add(id);
    _applyMix();
    notifyListeners();
  }

  /// automationNow is where the lanes are read: the playhead, in seconds of
  /// its scene, between frames too while it plays.
  double get automationNow =>
      (_frame + betweenFrames) / math.max(1, _document.frameRate);

  /// overridden is what is held by hand on each channel, by its key:
  /// settings moved while their lanes played, left where the hand put them
  /// until backToArrangement, as Ableton does. The session's, not the
  /// document's: opened again, a canvas plays as it was written.
  Map<String, Set<String>> get overridden => _overridden;

  /// anyOverridden is whether anything is held by hand: what lights Back to
  /// arrangement.
  bool get anyOverridden => _overridden.values.any((s) => s.isNotEmpty);

  /// backToArrangement hands every setting held by hand back to its lane.
  void backToArrangement() {
    if (!anyOverridden) return;
    _overridden.clear();
    _applyMix();
    notifyListeners();
  }

  /// backToAutomationFor hands [target] of [channel] alone back to its
  /// lane, where a hand was holding it: the prototype's knob menu "Back to
  /// its automation".
  void backToAutomationFor(String channel, String target) {
    if (_overridden[channel]?.remove(target) != true) return;
    _applyMix();
    notifyListeners();
  }

  /// automationArmed is the control bar's Arm automation: while it is on
  /// and the timeline plays, a setting moved by hand writes its lane --
  /// starting one, if it has none -- rather than being held.
  bool get automationArmed => _automationArmed;

  set automationArmed(bool on) {
    if (on == _automationArmed) return;
    _automationArmed = on;
    notifyListeners();
  }

  /// automationShown is the channels whose lanes are open under them on
  /// the timeline, by key -- the reader's view, not the document's.
  Set<String> get automationShown => _automationShown;

  void toggleAutomation(String channel) {
    if (!_automationShown.remove(channel)) _automationShown.add(channel);
    notifyListeners();
  }

  /// automationRows are the lanes shown under [channel], each the setting
  /// it shows, as Ableton's are: views onto the channel's automation, so a
  /// lane hidden keeps its points and one switched to another setting
  /// shows that setting's. To start with, every setting with points -- or
  /// the volume, with none.
  List<String> automationRows(TimelineChannel channel) =>
      _automationRows[channel.key] ??= () {
        var laned = [
          for (var l in channel.mix.automation)
            if (l.points.isNotEmpty) l.target
        ];
        return laned.isEmpty ? [AutomationTarget.volume.id] : laned;
      }();

  void showAutomationRow(TimelineChannel channel, int index, String target) {
    var rows = automationRows(channel);
    if (index < 0 || index >= rows.length) return;
    rows[index] = target;
    notifyListeners();
  }

  /// addAutomationRow shows another lane under [channel]: the first setting
  /// not shown yet that has points, else the first not shown at all.
  void addAutomationRow(TimelineChannel channel) {
    var rows = automationRows(channel);
    var all = [
      for (var t in automationTargets(channel.mix, _document.returns)) t.id
    ];
    var laned = {
      for (var l in channel.mix.automation)
        if (l.points.isNotEmpty) l.target
    };
    var next =
        all.where((t) => laned.contains(t) && !rows.contains(t)).firstOrNull ??
            all.where((t) => !rows.contains(t)).firstOrNull;
    if (next == null) return;
    rows.add(next);
    notifyListeners();
  }

  /// hideAutomationRow hides lane [index] under [channel]: its points are
  /// kept, and played. The last one hidden closes the lanes.
  void hideAutomationRow(TimelineChannel channel, int index) {
    var rows = automationRows(channel);
    if (index < 0 || index >= rows.length) return;
    rows.removeAt(index);
    if (rows.isEmpty) {
      _automationRows.remove(channel.key);
      _automationShown.remove(channel.key);
    }
    notifyListeners();
  }

  /// showLaneFor opens [channel]'s lanes on the timeline with one showing
  /// [target]: a knob's "Show its automation lane".
  void showLaneFor(String channel, String target) {
    var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
    if (lane == null) return;
    var rows = automationRows(lane);
    if (!rows.contains(target)) rows.add(target);
    _automationShown.add(channel);
    notifyListeners();
  }

  /// learning is the setting a controller's next knob turned is learnt
  /// for, as (channel, target), or null.
  (String, String)? get learning => _learning;

  /// learnControl waits for a controller's knob to be turned, to turn
  /// [target] of [channel] from then on.
  void learnControl(String channel, String target) {
    _learning = (channel, target);
    notifyListeners();
  }

  /// controlOf is the control change learnt for [target] of [channel], or
  /// null.
  int? controlOf(String channel, String target) => _document.audio.controls
      .where((l) => l.channel == channel && l.target == target)
      .firstOrNull
      ?.cc;

  /// forgetControl lets [target] of [channel] go from its controller knob.
  void forgetControl(String channel, String target) =>
      setAudio(_document.audio.copyWith(controls: [
        for (var l in _document.audio.controls)
          if (l.channel != channel || l.target != target) l,
      ]));

  /// midiCc is control change [cc] turned to [value], nought to one: learnt
  /// for what is waiting for one, or turning what it was learnt for. Each
  /// run of turning is one undo step.
  void midiCc(int cc, double value) {
    if (_learning case (var channel, var target)) {
      _learning = null;
      setAudio(_document.audio.copyWith(controls: [
        for (var l in _document.audio.controls)
          if (l.cc != cc && (l.channel != channel || l.target != target)) l,
        ControlLink(cc, channel, target),
      ]));
      return;
    }
    for (var link in _document.audio.controls) {
      if (link.cc == cc) _turnByControl(link, value);
    }
  }

  void _turnByControl(ControlLink link, double height) {
    var what = AutomationTarget.parse(link.target);
    var lane = timelineChannels.where((c) => c.key == link.channel).firstOrNull;
    if (what == null || lane == null) return;
    var v = what.valueAt(height.clamp(0.0, 1.0));
    beginInteraction();
    var mix = mixNow(lane);
    switch (what.kind) {
      case AutomationKind.volume:
        setChannelMix(lane, mix.copyWith(gainDb: v),
            transient: true, anywhere: true);
      case AutomationKind.pan:
        setChannelMix(lane, mix.copyWith(balance: v),
            transient: true, anywhere: true);
      case AutomationKind.send:
        setChannelMix(lane, mix.copyWith(sends: {...mix.sends, what.send: v}),
            transient: true, anywhere: true);
      case AutomationKind.device:
        var devices = devicesOf(link.channel);
        var i = deviceIndexOf(devices, what.device);
        if (i < 0) return;
        setDevicesOf(link.channel,
            [...devices]..[i] = devices[i].withValue(what.param, v),
            transient: true);
    }
    _controlIdle?.cancel();
    _controlIdle = Timer(const Duration(milliseconds: 400), endInteraction);
  }

  /// automationLaneOf is [channel]'s lane for [target], or null with none.
  AutomationLane? automationLaneOf(TimelineChannel channel, String target) =>
      channel.mix.automation.where((l) => l.target == target).firstOrNull;

  /// setAutomationPoints sets the points of [channel]'s lane for [target]:
  /// a lane made for the first, and taken away with the last.
  void setAutomationPoints(
      TimelineChannel channel, String target, List<AutomationPoint> points,
      {bool transient = false}) {
    var lanes = [
      for (var l in channel.mix.automation)
        if (l.target != target) l,
      if (points.isNotEmpty) AutomationLane(target).withPoints(points),
    ];
    setAutomation(channel, lanes, transient: transient);
  }

  /// mixFollowsPlayhead is whether a strip shows something the playhead
  /// moves: a lane of automation, or the envelope of a clip playing in a
  /// slot (see mixNow).
  bool get mixFollowsPlayhead {
    for (var l in timelineChannels) {
      if (l.mix.automation.isNotEmpty) return true;
    }
    for (var MapEntry(key: channel, value: ch) in _clipChannels.entries) {
      if (ch.now case var play?
          when session.at(channel, play.row)?.automation.isNotEmpty ?? false) {
        return true;
      }
    }
    return false;
  }

  /// mixNow is [channel]'s mix as it plays now: its own, with each lane's
  /// setting put in but for those held by hand. What its strip shows.
  ChannelMix mixNow(TimelineChannel channel) {
    var held = _overridden[channel.key] ?? const <String>{};
    return _withClipAutomation(channel.key,
        automatedAt(channel.mix, automationNow, except: held), held);
  }

  /// changeChannelMix writes [next] -- the mix as it was shown, [shown],
  /// changed by a hand -- to [channel]. Each setting the hand changed is
  /// the channel's own now; where a lane moves it, it is held by hand -- or,
  /// armed and playing, written into its lane where the playhead is. Every
  /// other setting stays the channel's own, not the lane's value that was
  /// shown for it.
  void changeChannelMix(
      TimelineChannel channel, ChannelMix shown, ChannelMix next,
      {bool transient = false,
      bool anywhere = false,
      List<AutomationLane>? automation}) {
    var own = automation == null
        ? channel.mix
        : channel.mix.copyWith(automation: automation);
    var writing = _automationArmed && playing;
    var launched = _clipChannels[channel.key]?.now;
    var clip = launched == null ? null : session.at(channel.key, launched.row);
    var clipLanes = clip?.automation ?? const <ClipAutomation>[];
    if (own.automation.isEmpty && clipLanes.isEmpty && !writing) {
      setChannelMix(channel, next, transient: transient, anywhere: anywhere);
      return;
    }
    var moved = <String>{};
    var gain = own.gainDb, balance = own.balance;
    if (next.gainDb != shown.gainDb) {
      gain = next.gainDb;
      moved.add(AutomationTarget.volume.id);
    }
    if (next.balance != shown.balance) {
      balance = next.balance;
      moved.add(AutomationTarget.pan.id);
    }
    var sends = {...own.sends};
    for (var id in {...shown.sends.keys, ...next.sends.keys}) {
      if (next.sends[id] == shown.sends[id]) continue;
      moved.add(AutomationTarget.sendTo(id).id);
      if (next.sends[id] case var db?) {
        sends[id] = db;
      } else {
        sends.remove(id);
      }
    }
    // The devices, setting by setting, each found by its id, so a chain
    // put in another order keeps what each device had; a device put on or
    // taken off is the chain the hand made.
    var ownDevices = withDeviceIds(own.devices),
        shownDevices = withDeviceIds(shown.devices),
        nextDevices = withDeviceIds(next.devices);
    var devices = nextDevices;
    if (nextDevices.length == shownDevices.length &&
        ownDevices.length == shownDevices.length) {
      devices = [
        for (var d in nextDevices)
          switch ((
            deviceIndexOf(ownDevices, d.id),
            deviceIndexOf(shownDevices, d.id)
          )) {
            (var o, var sh)
                when o >= 0 &&
                    sh >= 0 &&
                    d.kind == ownDevices[o].kind &&
                    d.kind == shownDevices[sh].kind =>
              _mergedDevice(ownDevices[o], shownDevices[sh], d, moved),
            _ => d,
          },
      ];
    } else if (shownDevices.length == ownDevices.length &&
        nextDevices.length == ownDevices.length - 1) {
      // One taken out: the rest as the channel had them.
      devices = [
        for (var d in ownDevices)
          if (deviceIndexOf(nextDevices, d.id) >= 0) d
      ];
    } else if (shownDevices.length == ownDevices.length &&
        nextDevices.length == ownDevices.length + 1) {
      // One put on the end.
      devices = [...ownDevices, nextDevices.last];
    }
    var lanes = own.automation;
    if (writing) {
      var t = automationNow;
      var probe = next.copyWith(
          gainDb: gain, balance: balance, sends: sends, devices: devices);
      lanes = [
        for (var l in lanes)
          if (moved.contains(l.target)) l.written(t, l.what!.own(probe)) else l,
        // A setting with no lane yet starts one.
        for (var id in moved)
          if (!lanes.any((l) => l.target == id))
            AutomationLane(id, [(t, AutomationTarget.parse(id)!.own(probe))]),
      ];
    } else {
      // What a lane moves -- the timeline's, or the clip's playing.
      var laned = {
        for (var l in lanes)
          if (l.points.isNotEmpty) l.target,
        for (var a in clipLanes)
          if (a.points.isNotEmpty) a.target,
      };
      var held = moved.intersection(laned);
      if (held.isNotEmpty) (_overridden[channel.key] ??= {}).addAll(held);
    }
    setChannelMix(
        channel,
        next.copyWith(
            gainDb: gain,
            balance: balance,
            sends: sends,
            devices: devices,
            automation: lanes),
        transient: transient,
        anywhere: anywhere);
  }

  /// _lanesAfter is [lanes] once the chain [was] is [now]: a device taken
  /// out takes its lanes with it. The others' lanes follow them by id,
  /// wherever they now are.
  List<AutomationLane> _lanesAfter(
      List<AutomationLane> lanes, List<MixDevice> was, List<MixDevice> now) {
    var ids = {for (var i = 0; i < now.length; i++) deviceIdAt(now, i)};
    return [
      for (var l in lanes)
        if (l.what case var w?
            when w.kind == AutomationKind.device && !ids.contains(w.device))
          ...[]
        else
          l,
    ];
  }

  /// _mergedDevice is a device as the hand left it: each setting it
  /// changed from what was [shown] taken from [next] -- and noted in
  /// [moved] -- the rest the channel's [own]; switched on or off as the
  /// hand left it.
  MixDevice _mergedDevice(
      MixDevice own, MixDevice shown, MixDevice next, Set<String> moved) {
    // What it moves, its branches and its saved variations are as the hand
    // left them: only its settings are merged.
    var out = MixDevice(own.kind,
        on: next.on,
        values: own.values,
        source: next.source,
        id: next.id,
        mods: next.mods,
        branches: next.branches,
        variations: next.variations);
    for (var p in next.kind.params) {
      if (next.value(p.id) == shown.value(p.id)) continue;
      out = out.withValue(p.id, next.value(p.id));
      moved.add(AutomationTarget.deviceSetting(next.id, next.kind, p.id).id);
    }
    return out;
  }

  /// setAutomation sets [channel]'s lanes.
  void setAutomation(TimelineChannel channel, List<AutomationLane> lanes,
      {bool transient = false}) {
    // A lane with its points gone is no longer holding anything by hand.
    var targets = {
      for (var l in lanes)
        if (l.points.isNotEmpty) l.target
    };
    _overridden[channel.key]?.removeWhere((t) => !targets.contains(t));
    setChannelMix(channel, channel.mix.copyWith(automation: lanes),
        transient: transient);
  }

  /// setChannelMix changes one strip, as the Channels strip changes a clip --
  /// see setTimedClip.
  ///
  /// [anywhere] writes a clip's channel from wherever it is seen: a master
  /// clip picked from a scene is not editable on that scene's timeline, but
  /// its settings, opened on purpose, are its own.
  void setChannelMix(TimelineChannel channel, ChannelMix mix,
          {bool transient = false, bool anywhere = false}) =>
      _setClips([
        for (var lane in channel.lanes)
          if (lane.editable ||
              (anywhere && !lane.element.id.startsWith(transitionSoundPrefix)))
            (lane.element, lane.clip.copyWith(mix: mix)),
      ], transient: transient);

  void setMasterMix(MasterMix mix, {bool transient = false}) =>
      apply(_document.copyWith(masterMix: mix), transient: transient);

  /// sceneBus is the bus of the scene being shown -- see CanvasScene.bus --
  /// which every sound in it goes through on its way to the master.
  ChannelMix get sceneBus => _document.scene.bus;

  /// writeStripPart sets strip [owner]'s own EQ, compressor or Ducker --
  /// the master's (mixerMasterKey), the scene's bus, a return's or a
  /// channel's, wherever its sound is -- as one undo step. A part the strip
  /// does not have is left alone: only a channel has a Ducker.
  void writeStripPart(String owner, {Eq? eq, Dynamics? comp, Ducking? duck}) {
    beginInteraction();
    if (owner == mixerMasterKey) {
      setMasterMix(_document.masterMix.copyWith(eq: eq, comp: comp),
          transient: true);
    } else if (owner == sceneBusKey) {
      setSceneBus(sceneBus.copyWith(eq: eq, comp: comp), transient: true);
    } else if (returnOf(owner) case var ret?) {
      setReturn(ret.copyWith(mix: ret.mix.copyWith(eq: eq, comp: comp)),
          transient: true);
    } else if (timelineChannels.where((l) => l.key == owner).firstOrNull
        case var lane?) {
      setChannelMix(lane, lane.mix.copyWith(eq: eq, comp: comp, duck: duck),
          transient: true, anywhere: true);
    }
    endInteraction();
  }

  /// setSceneBus changes the shown scene's bus.
  void setSceneBus(ChannelMix bus, {bool transient = false}) => apply(
      _document.withScene(_document.at, _document.scene.copyWith(bus: bus)),
      transient: transient);

  /// returnOf is the return called [id], or null.
  ReturnChannel? returnOf(String? id) =>
      _document.returns.where((r) => r.id == id).firstOrNull;

  /// devicesOf is strip [key]'s devices -- a return's, or a channel's own --
  /// in order; empty for none, or for a strip that is neither.
  ///
  /// Every device has its id (see withDeviceIds), so a chain changed from
  /// this one -- a device taken out, one put on -- keeps the others' ids.
  List<MixDevice> devicesOf(String key) {
    if (key == mixerMasterKey)
      return withDeviceIds(_document.masterMix.devices);
    if (key == sceneBusKey) return withDeviceIds(sceneBus.devices);
    if (returnOf(key) case var r?) return withDeviceIds(r.devices);
    // As they play now: a setting a lane moves, where the lane has it.
    var lane = timelineChannels.where((c) => c.key == key).firstOrNull;
    return lane == null ? const [] : withDeviceIds(mixNow(lane).devices);
  }

  /// setDevicesOf changes strip [key]'s devices.
  void setDevicesOf(String key, List<MixDevice> devices,
      {bool transient = false}) {
    if (key == mixerMasterKey) {
      setMasterMix(_document.masterMix.copyWith(devices: devices),
          transient: transient);
      return;
    }
    if (key == sceneBusKey) {
      setSceneBus(sceneBus.copyWith(devices: devices), transient: transient);
      return;
    }
    if (returnOf(key) case var r?) {
      setReturn(r.copyWith(devices: devices), transient: transient);
      return;
    }
    var lane = timelineChannels.where((c) => c.key == key).firstOrNull;
    if (lane == null) return;
    var shown = mixNow(lane);
    changeChannelMix(lane, shown, shown.copyWith(devices: devices),
        transient: transient,
        automation: _lanesAfter(lane.mix.automation, shown.devices, devices));
  }

  /// chainOf is strip [key]'s chain in the order it runs: device ids, and
  /// chainEq and chainComp for its EQ and compressor (see ChannelMix.chain).
  /// A return's as a channel's, from its devices and its strip.
  List<String> chainOf(String key) {
    if (key == mixerMasterKey) return _document.masterMix.chain;
    if (key == sceneBusKey) return sceneBus.chain;
    if (returnOf(key) case var r?) return r.chainMix.chain;
    var lane = timelineChannels.where((c) => c.key == key).firstOrNull;
    return lane == null ? const [] : mixNow(lane).chain;
  }

  /// moveDevice moves [id] -- a device, or chainEq or chainComp -- [by]
  /// places along strip [key]'s chain, minus to the left, as one undo step.
  /// A device's lanes, its fold and its settings go with it: they follow its
  /// id, not its place.
  void moveDevice(String key, String id, int by) {
    var chain = [...chainOf(key)];
    var i = chain.indexOf(id), j = i + by;
    if (i < 0 || j < 0 || j >= chain.length || by == 0) return;
    chain.insert(j, chain.removeAt(i));
    // The devices kept in the same order among themselves, so a list of
    // them reads as the chain does.
    var devices = devicesOf(key);
    var sorted = [
      for (var step in chain)
        if (deviceIndexOf(devices, step) case var at when at >= 0) devices[at],
    ];
    beginInteraction();
    if (key == mixerMasterKey) {
      var m = _document.masterMix;
      setMasterMix(
          m.copyWith(
              devices: sorted, order: chain, compFirst: compFirstIn(chain)),
          transient: true);
    } else if (key == sceneBusKey) {
      setSceneBus(
          sceneBus.copyWith(
              devices: sorted, order: chain, compFirst: compFirstIn(chain)),
          transient: true);
    } else if (returnOf(key) case var r?) {
      setReturn(
          r.copyWith(
              devices: sorted,
              mix: r.mix.copyWith(order: chain, compFirst: compFirstIn(chain))),
          transient: true);
    } else if (timelineChannels.where((c) => c.key == key).firstOrNull
        case var lane?) {
      var shown = mixNow(lane);
      changeChannelMix(
          lane,
          shown,
          shown.copyWith(
              devices: sorted, order: chain, compFirst: compFirstIn(chain)),
          transient: true);
    }
    endInteraction();
  }

  /// setReturn changes a return -- its name, its devices, its strip.
  void setReturn(ReturnChannel next, {bool transient = false}) => apply(
      _document.copyWith(returns: [
        for (var r in _document.returns) r.id == next.id ? next : r,
      ]),
      transient: transient);

  /// addReturn adds a return at the end, with a reverb on it -- the
  /// commonest reason for one -- and picks it.
  ReturnChannel? addReturn() {
    var returns = _document.returns;
    if (returns.length >= maxReturns) return null;
    var taken = {for (var r in returns) r.id};
    var n = returns.length;
    while (taken.contains("return${returnLetter(n)}")) {
      n++;
    }
    var made = ReturnChannel("return${returnLetter(n)}",
        name: "Reverb", devices: const [MixDevice(DeviceKind.reverb)]);
    apply(_document.copyWith(returns: [...returns, made]));
    pickStrip(made.id);
    return made;
  }

  /// removeReturn takes a return away. What was sent to it is sent nowhere:
  /// the sends are kept on the channels, so putting it back with undo finds
  /// them as they were.
  void removeReturn(String id) {
    apply(_document.copyWith(returns: [
      for (var r in _document.returns)
        if (r.id != id) r,
    ]));
    if (selectedChannel == id) selectedChannel = null;
    if (_effectsOf == id) _effectsOf = null;
  }

  /// levels is how loud a strip -- by its channel's key, or the master with
  /// none -- is coming out now, for the meters.
  (double, double) levels([String? channel]) =>
      _audio?.levels(channel) ?? (0, 0);

  /// deviceLevels is channel [channel]'s levels at each step of its strip --
  /// see AudioEngine.deviceLevels -- for the meters between its devices.
  /// The master's are asked for by mixerMasterKey; a return's, a scene
  /// bus's, by theirs.
  List<(double, double)> deviceLevels(String channel) =>
      _audio?.deviceLevels(channel == mixerMasterKey ? "" : channel) ??
      const [];

  /// deviceScope is what device [id] of [channel]'s strip passes now, for
  /// its screen (see device_scope.dart): asked for while its display is
  /// on, and stopped with [stopScope] when it is put off or away.
  ScopeReading? deviceScope(String channel, String id) =>
      _audio?.deviceScope(channel == mixerMasterKey ? "" : channel, id);

  /// listening is the chain heard from a point, and where -- see listenAt --
  /// or null.
  (String, int)? get listening => _listening;

  /// listenAt hears channel [channel] from step [step] of its chain, as the
  /// prototype's "Listen from here"; null, all of it again.
  void listenAt(String channel, int? step) {
    // The master is heard at its taps' key ("", masterTapKey), as its
    // levels are read.
    String engineKey(String k) => k == mixerMasterKey ? "" : k;
    if (_listening case (var was, _) when was != channel) {
      _audio?.listenAt(engineKey(was), null);
    }
    _listening = step == null ? null : (channel, step);
    _audio?.listenAt(engineKey(channel), step);
    notifyListeners();
  }

  /// insertDevice puts [device] at step [at] of strip [key]'s chain: an
  /// analyser added from a join. One undo step.
  void insertDevice(String key, MixDevice device, int at) {
    beginInteraction();
    setDevicesOf(key, [...devicesOf(key), device], transient: true);
    var devices = devicesOf(key);
    var id = deviceIdAt(devices, devices.length - 1);
    var from = chainOf(key).indexOf(id);
    if (from >= 0 && from != at) moveDevice(key, id, at - from);
    endInteraction();
  }

  void stopScope(String channel, String id) =>
      _audio?.stopScope(channel == mixerMasterKey ? "" : channel, id);

  /// reduction is how many decibels [channel]'s compressor takes off now.
  double reduction(String channel) => _audio?.reduction(channel) ?? 0;

  /// spectrum is what a strip -- by its channel's key, or the master with
  /// none -- is playing now, for the EQ to draw. See AudioEngine.spectrum.
  Float32List? spectrum([String? channel]) => _audio?.spectrum(channel);

  /// pitch is what a tuner on strip [channel] hears now -- the master's
  /// with mixerMasterKey -- or null.
  PitchReading? pitch(String channel) =>
      _audio?.pitch(channel == mixerMasterKey ? null : channel);

  /// wave is what [channel]'s first analyser of [kind] last heard: see
  /// AudioEngine.wave.
  Wave? wave(DeviceKind kind, String channel) =>
      _audio?.wave(kind, channel == mixerMasterKey ? null : channel);

  /// loudness is [channel]'s Loudness's reading: see AudioEngine.loudness.
  LoudnessReading? loudness(String channel) =>
      _audio?.loudness(channel == mixerMasterKey ? null : channel);

  void resetLoudness(String channel) =>
      _audio?.resetLoudness(channel == mixerMasterKey ? null : channel);

  /// _heard opens the runtime, where it is not open yet, with the mixer
  /// already in it: a sound pressed on the canvas plays through its strip
  /// from its first note.
  void _heard() {
    audio;
    _applyMix();
  }

  /// hear is which of a surround mix's speakers the editor plays on its two:
  /// everything folded down, or one group alone (see SpeakerGroup). Only
  /// what is heard here; the mix and its exports are as they are.
  SpeakerGroup get hear => _hear;

  void hearSpeakers(SpeakerGroup group) {
    if (group == _hear) return;
    _hear = group;
    _applyMix();
    notifyListeners();
  }

  /// _applyMix hands the runtime the mixer as it stands. Cheap when nothing
  /// has changed: the runtime compares before it calls the engine.
  void _applyMix() {
    var timed = timedLanes;
    // A sound pressed on the canvas opens the device when it is pressed --
    // see _heard -- not when the canvas holding it is opened.
    if (timed.isEmpty && _audio == null) return;
    var lanes = [...timed, ...interactiveLanes];
    // One strip per channel, every sound on it routed through it. The strip
    // is the channel's first sound's mix, which setChannelMix copies onto
    // every sound on the channel; each as it plays now, its lanes' settings
    // put in but for those held by hand.
    var strips = <String, ChannelMix>{};
    // The channels heard through the scene's bus: those whose first sound
    // -- whose strip it is -- is in a scene, or a transition's; not the
    // master's.
    var inScene = <String>{};
    var now = automationNow;
    for (var lane in lanes) {
      if (!strips.containsKey(lane.channelKey) &&
          (lane.scene >= 0 ||
              lane.element.id.startsWith(transitionSoundPrefix))) {
        inScene.add(lane.channelKey);
      }
      strips.putIfAbsent(lane.channelKey, () {
        var held = _overridden[lane.channelKey] ?? const <String>{};
        var mix = _withClipAutomation(lane.channelKey,
            automatedAt(lane.clip.mix, now, except: held), held);
        // Its LFOs set to Sync at the tempo's rate: the engine knows none.
        return mix.copyWith(devices: _document.synced(mix.devices));
      });
    }
    audio.setMix(strips,
        routes: {for (var lane in lanes) lane.element.id: lane.channelKey},
        solo: {
          for (var key in _solo)
            if (strips.containsKey(key)) key,
        },
        master: _document.syncedMaster,
        returns: _document.syncedReturns,
        sceneBus:
            sceneBus.copyWith(devices: _document.synced(sceneBus.devices)),
        sceneChannels: inScene,
        speakers: _document.audio.speakers,
        hear: _hear,
        placements: placementsNow);
  }

  /// _withClipAutomation is [mix] with the envelopes of the clip playing on
  /// [channel] put in, over the timeline's lanes -- or as it was, with no
  /// clip playing or none with envelopes of the channel's settings.
  ChannelMix _withClipAutomation(
      String channel, ChannelMix mix, Set<String> held) {
    var play = _clipChannels[channel]?.now;
    if (play == null) return mix;
    var clip = session.at(channel, play.row);
    if (clip == null || clip.id != play.clipId || clip.automation.isEmpty) {
      return mix;
    }
    var beat = clipAt(channel);
    if (beat == null) return mix;
    var elapsed = (_sessionNow - play.origin) /
        math.max(0.001, _document.audio.secondsPerBeat);
    return clipAutomatedAt(mix, clip.automation, beat, elapsed, except: held);
  }

  /// placementsNow is where each placed sound's channel is heard from on
  /// this frame, by channel -- the first placed sound on a channel says,
  /// which is the only one on it unless channels have been shared.
  Map<String, Heard> get placementsNow {
    var out = <String, Heard>{};
    for (var lane in [...timedLanes, ...interactiveLanes]) {
      var place = lane.clip.place;
      if (place.isOff || out.containsKey(lane.channelKey)) continue;
      if (heardAt(_document, lane.element, place, _frame) case var h?) {
        out[lane.channelKey] = h;
      }
    }
    // A sound a game set off at an instance: from there, until the next.
    for (var e in _soundFrom.entries) {
      if (out.containsKey(e.key)) out[e.key] = e.value;
    }
    return out;
  }

  /// _autoplayAudio starts the sounds on screen that start by themselves.
  void _autoplayAudio() {
    var starting = [
      for (var e in _pageAudio)
        if (e.clip.autoplay && !e.clip.isEmpty && !e.clip.timed) e,
    ];
    if (starting.isNotEmpty) {
      _heard();
      audio.autoplay(starting);
    }

    var videos = [
      for (var e in [
        ..._document.elements,
        if (!_document.editingMaster) ...?_document.masterScene?.elements,
      ])
        if (e is VideoElement &&
            e.clip.autoplay &&
            !e.clip.isEmpty &&
            !e.clip.timed)
          e,
    ];

    // And the backdrop's, which is where a looping video or a music bed
    // usually is.
    for (var e in _document.drawnBackground.media) {
      switch (e) {
        case VideoElement v when v.clip.autoplay && !v.clip.timed:
          videos.add(v);
        case AudioElement a when a.clip.autoplay && !a.clip.timed:
          audio.autoplay([a]);
      }
    }
    if (videos.isNotEmpty) {
      _heard();
      video.autoplay(videos);
    }
  }

  // ---- Freezing a chain

  /// frozenSteps are the steps of [channel]'s chain frozen into its sounds:
  /// device ids, chainEq and chainComp. Empty for one not frozen.
  Set<String> frozenSteps(String channel) =>
      timelineChannels
          .where((l) => l.key == channel)
          .firstOrNull
          ?.mix
          .frozen
          ?.steps ??
      const {};

  /// freezing is whether [channel] is being frozen now.
  bool freezing(String channel) => _freezing.contains(channel);

  /// canFreeze is why [channel] cannot be frozen, or null where it can: a
  /// recording's channel, one sound or several, not already frozen.
  String? canFreeze(String channel) {
    var lane = timelineChannels.where((l) => l.key == channel).firstOrNull;
    if (lane == null) return "Only a channel's chain can be frozen.";
    if (lane.video) return "A video's sound cannot be frozen.";
    if (instrumentChannel(channel)) {
      return "An instrument's channel cannot be frozen yet.";
    }
    if (lane.mix.frozen != null) return "It is frozen: unfreeze it first.";
    if (!lane.lanes.any((l) => l.editable && l.clip.playlist.isNotEmpty)) {
      return "There is no sound on it to freeze.";
    }
    return null;
  }

  /// freezeChain renders each sound of [channel] through its chain from
  /// the start to [upTo] (a device's id, chainEq or chainComp) -- with its
  /// modulators, as it plays -- keeps each as a new sound in the library,
  /// and plays those: the steps frozen switched off so they are not run
  /// twice, and remembered to be put back (unfreezeChain). Off the main
  /// thread; one undo step. Answers why not, or null.
  Future<String?> freezeChain(String channel, String upTo) async {
    if (canFreeze(channel) case var why?) return why;
    if (!_freezing.add(channel)) return "It is being frozen.";
    notifyListeners();
    try {
      var lane = timelineChannels.firstWhere((l) => l.key == channel);
      var mix = lane.mix;
      var chain = mix.chain;
      var at = chain.indexOf(upTo);
      if (at < 0) return "That is not on this channel's chain.";
      var steps = chain.sublist(0, at + 1).toSet();
      var devices = withDeviceIds(mix.devices);
      // The strip's start: what is frozen as it is set, the rest off but
      // for its modulators, which turn knobs and make no sound.
      var part = mix.copyWith(
        mute: false,
        devices: [
          for (var (i, d) in devices.indexed)
            steps.contains(deviceIdAt(devices, i)) || d.kind.modulates
                ? d
                : d.switched(false),
        ],
        eq: steps.contains(chainEq) ? mix.eq : mix.eq.copyWith(on: false),
        comp:
            steps.contains(chainComp) ? mix.comp : mix.comp.copyWith(on: false),
      );
      var playlists = <String, List<Map<String, dynamic>>>{};
      var made = <(CanvasElement, List<MediaSource>)>[];
      for (var sound in lane.lanes) {
        if (!sound.editable) continue;
        var next = <MediaSource>[];
        for (var s in sound.clip.playlist) {
          var file = await CanvasMedia.existingPath(MediaKind.audio, s.assetId);
          if (file == null) return "\"${s.name}\" is missing from the library.";
          var pcm = await readWholeAway(file);
          if (pcm == null) return "\"${s.name}\" could not be read.";
          var wav = await _frozenWav(part, pcm.$1, pcm.$2);
          var id = await _keepSound(wav);
          if (id == null) return "The frozen sound could not be kept.";
          next.add(s.copyWith(
              assetId: id,
              name: s.name.isEmpty ? "Frozen" : "${s.name} (frozen)"));
        }
        playlists[sound.element.id] = [
          for (var s in sound.clip.playlist) s.toJson(),
        ];
        made.add((sound.element, next));
      }
      // Changed while it rendered: not frozen, rather than half frozen.
      var now = timelineChannels.where((l) => l.key == channel).firstOrNull;
      if (now == null || now.mix.chain.join("|") != chain.join("|")) {
        return "The chain changed while it was being frozen.";
      }
      var frozen = FrozenChain(
        upTo: upTo,
        wasOn: {
          for (var step in steps)
            step: step == chainEq
                ? mix.eq.on
                : step == chainComp
                    ? mix.comp.on
                    : devices[deviceIndexOf(devices, step)].on,
        },
        playlists: playlists,
      );
      beginInteraction();
      for (var (e, playlist) in made) {
        var current = _document.elementById(e.id);
        if (current is! AudioElement) continue;
        setTimedClip(current, current.clip.copyWith(playlist: playlist),
            transient: true);
      }
      var lane2 = timelineChannels.firstWhere((l) => l.key == channel);
      var m = lane2.mix;
      var ds = withDeviceIds(m.devices);
      setChannelMix(
          lane2,
          m.copyWith(
            frozen: frozen,
            devices: [
              for (var (i, d) in ds.indexed)
                steps.contains(deviceIdAt(ds, i)) ? d.switched(false) : d,
            ],
            eq: steps.contains(chainEq) ? m.eq.copyWith(on: false) : null,
            comp: steps.contains(chainComp) ? m.comp.copyWith(on: false) : null,
          ),
          transient: true);
      endInteraction();
      return null;
    } catch (exception) {
      debugPrint("Unable to freeze $channel: $exception");
      return "It could not be frozen.";
    } finally {
      _freezing.remove(channel);
      notifyListeners();
    }
  }

  /// _frozenWav runs [l] and [r] through [part]'s strip before its fader,
  /// in its own isolate where it can, and answers it as a WAV file's bytes.
  Future<Uint8List> _frozenWav(
      ChannelMix part, Float32List l, Float32List r) async {
    Uint8List run() {
      var strip = StripProcessor(part);
      const block = 1024;
      for (var i = 0; i < l.length; i += block) {
        var n = math.min(block, l.length - i);
        strip.shape(Float32List.sublistView(l, i, i + n),
            Float32List.sublistView(r, i, i + n), n);
      }
      return wav16(l, r);
    }

    try {
      return await Isolate.run(run);
    } catch (_) {
      // Something in the chain cannot cross to an isolate: here, then.
      return run();
    }
  }

  /// unfreezeChain puts [channel] back as it was before freezeChain: its
  /// sounds' own files, and the steps frozen switched as they were. The
  /// frozen copies stay in the library. One undo step.
  void unfreezeChain(String channel) {
    var lane = timelineChannels.where((l) => l.key == channel).firstOrNull;
    var frozen = lane?.mix.frozen;
    if (lane == null || frozen == null) return;
    beginInteraction();
    for (var sound in lane.lanes) {
      var was = frozen.playlists[sound.element.id];
      if (was == null || sound.element is! AudioElement) continue;
      setTimedClip(
          sound.element,
          sound.clip.copyWith(playlist: [
            for (var s in was) MediaSource.fromJson(s),
          ]),
          transient: true);
    }
    var lane2 = timelineChannels.firstWhere((l) => l.key == channel);
    var m = lane2.mix;
    var ds = withDeviceIds(m.devices);
    var eqWas = frozen.wasOn[chainEq], compWas = frozen.wasOn[chainComp];
    setChannelMix(
        lane2,
        m.copyWith(
          noFrozen: true,
          devices: [
            for (var (i, d) in ds.indexed)
              if (frozen.wasOn[deviceIdAt(ds, i)] case var on?)
                d.switched(on)
              else
                d,
          ],
          eq: eqWas == null ? null : m.eq.copyWith(on: eqWas),
          comp: compWas == null ? null : m.comp.copyWith(on: compWas),
        ),
        transient: true);
    endInteraction();
  }

  // ---- The strip's own parts taken out, and put back

  /// _stripMix is strip [owner]'s mix: a channel's, a return's or the
  /// scene's bus's. Null for the master, whose parts stay.
  ChannelMix? _stripMix(String owner) {
    if (owner == sceneBusKey) return sceneBus;
    return timelineChannels.where((l) => l.key == owner).firstOrNull?.mix ??
        returnOf(owner)?.mix;
  }

  void _setStripMix(String owner, ChannelMix mix) {
    if (owner == sceneBusKey) {
      setSceneBus(mix, transient: true);
      return;
    }
    if (timelineChannels.where((l) => l.key == owner).firstOrNull
        case var lane?) {
      setChannelMix(lane, mix, transient: true, anywhere: true);
      return;
    }
    if (returnOf(owner) case var r?) {
      setReturn(r.copyWith(mix: mix), transient: true);
    }
  }

  /// partRemoved is whether strip [owner]'s [part] -- chainEq, chainComp
  /// or stripDuck -- is taken out of its chain.
  bool partRemoved(String owner, String part) =>
      _stripMix(owner)?.removed.contains(part) ?? false;

  /// canRemovePart is whether [part] of strip [owner] can be taken out: a
  /// channel's, a return's or the scene bus's EQ and compressor, and a
  /// channel's Ducker. The master's stay.
  bool canRemovePart(String owner, String part) =>
      _stripMix(owner) != null &&
      ((part != stripDuck && part != stripDucked) ||
          timelineChannels.any((l) => l.key == owner));

  /// removePart takes [part] out of strip [owner]'s chain, as a device is:
  /// switched off and no longer shown, its settings kept. One undo step.
  void removePart(String owner, String part) {
    var m = _stripMix(owner);
    if (m == null || m.removed.contains(part)) return;
    beginInteraction();
    // Ducked no more: out of every Ducker that would turn it down.
    if (part == stripDucked) {
      setDuckedBy(owner, false);
      m = _stripMix(owner)!;
    }
    _setStripMix(
        owner,
        m.copyWith(
          removed: [...m.removed, part],
          eq: part == chainEq ? m.eq.copyWith(on: false) : null,
          comp: part == chainComp ? m.comp.copyWith(on: false) : null,
          duck: part == stripDuck ? m.duck.copyWith(on: false) : null,
        ));
    endInteraction();
  }

  /// restorePart puts [part] back in strip [owner]'s chain, switched on,
  /// with the settings it had. One undo step.
  void restorePart(String owner, String part) {
    var m = _stripMix(owner);
    if (m == null || !m.removed.contains(part)) return;
    beginInteraction();
    if (part == stripDucked) {
      setDuckedBy(owner, true);
      m = _stripMix(owner)!;
    }
    _setStripMix(
        owner,
        m.copyWith(
          removed: [
            for (var r in m.removed)
              if (r != part) r
          ],
          eq: part == chainEq ? m.eq.copyWith(on: true) : null,
          comp: part == chainComp ? m.comp.copyWith(on: true) : null,
          duck: part == stripDuck ? m.duck.copyWith(on: true) : null,
        ));
    endInteraction();
  }
}
