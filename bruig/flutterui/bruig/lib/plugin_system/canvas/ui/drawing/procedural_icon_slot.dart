part of 'procedural_settings.dart';

// The look's icon slot, its drift and the sectioned layout. Part of
// ProceduralSettings: its fields, lifecycle and build are in
// procedural_settings.dart.

extension ProceduralIconSlot on ProceduralSettings {
  /// _iconSlot is one placing: the picture, what it is drawn like, and, round
  /// a ring, the others it may be drawn as and how far each may differ.
  List<Widget> _iconSlot(
      BuildContext context, RingSpec rings, RingIconPlace place) {
    var at = place.name;
    var icon = rings.icons.where((i) => i.place == place).firstOrNull;
    var around = place == RingIconPlace.around;

    void set(RingIcon next) => _put(rings, place, next);

    // Nothing chosen yet: the two ways of choosing one, and what it would do.
    if (icon == null) {
      return [
        CanvasIconButton(
          key: ValueKey("ringIconPick-$at"),
          icon: Icons.add_photo_alternate,
          tooltip: "Choose a picture from a file",
          onPressed: () async {
            var id = await pickCanvasImage(context);
            if (id == null) return;
            set(RingIcon(asset: id, place: place));
          },
        ),
        CanvasIconButton(
          key: ValueKey("ringIconLibrary-$at"),
          icon: Icons.photo_library_outlined,
          tooltip: "Use a picture you have already added",
          onPressed: () async {
            var id = await showRecentPictures(context);
            if (id == null) return;
            set(RingIcon(asset: id, place: place));
          },
        ),
        CanvasHint(around
            ? "Pictures spaced around a ring like beads on it, each turned to "
                "face out of it. They inherit the ring: where it is, how big "
                "it has grown and how far through its fade it is."
            : "One picture in the middle of the rings, sized against the ring "
                "it is tied to -- so it arrives, swells and dissolves with "
                "it."),
      ];
    }

    return [
      CanvasIconButton(
        key: ValueKey("ringIconPick-$at"),
        icon: Icons.image_outlined,
        tooltip: "Choose a different picture from a file",
        onPressed: () async {
          var id = await pickCanvasImage(context);
          if (id == null) return;
          set(icon.copyWith(asset: id));
        },
      ),
      // Or from the pictures this canvas already has, the usual source.
      CanvasIconButton(
        key: ValueKey("ringIconLibrary-$at"),
        icon: Icons.photo_library_outlined,
        tooltip: "Use a picture you have already added",
        onPressed: () async {
          var id = await showRecentPictures(context);
          if (id == null) return;
          set(icon.copyWith(asset: id));
        },
      ),
      CanvasNumberField(
        key: ValueKey("ringIconRing-$at"),
        label: "On ring",
        width: 54,
        value: icon.ring.toDouble(),
        // Nought is no ring at all, for the one in the middle: a picture tied
        // to the movement, simply there while rings come and go.
        min: around ? 1 : 0,
        max: 200,
        onChanged: (v) => set(icon.copyWith(ring: v.round())),
        onCommit: onCommit,
      ),
      if (!around && icon.ring <= 0)
        const CanvasHint(
            "On no ring. It lives the length of one run rather than of a "
            "ring, and its size is a fraction of the page rather than of a "
            "radius. With both fades held it is simply there, for the whole "
            "animation."),
      if (around)
        CanvasNumberField(
          key: ValueKey("ringIconCount-$at"),
          label: "How many",
          width: 54,
          value: icon.count.toDouble(),
          min: 1,
          max: 60,
          onChanged: (v) => set(icon.copyWith(count: v.round())),
          onCommit: onCommit,
        ),
      CanvasNumberField(
        key: ValueKey("ringIconSize-$at"),
        label: "Size",
        decimals: 2,
        width: 58,
        value: icon.size,
        min: 0.01,
        max: 4,
        onChanged: (v) {
          onBegin();
          set(icon.copyWith(size: v));
        },
        onCommit: onCommit,
      ),
      CanvasNumberField(
        key: ValueKey("ringIconTurn-$at"),
        label: "Turn",
        width: 54,
        suffix: "\u00b0",
        value: icon.turn,
        min: -360,
        max: 360,
        onChanged: (v) {
          onBegin();
          set(icon.copyWith(turn: v));
        },
        onCommit: onCommit,
      ),
      // The design's colour rather than its own, as a ring's line drawing
      // usually wants.
      CanvasToggle(
        key: ValueKey("ringIconTinted-$at"),
        label: "Colour it",
        value: icon.tinted,
        onChanged: (v) => set(icon.copyWith(tinted: v)),
      ),
      if (icon.tinted)
        CanvasColorButton(
          key: ValueKey("ringIconTint-$at"),
          label: "Colour",
          color: icon.tint,
          onChanged: (c) => set(icon.copyWith(tint: c)),
        ),
      CanvasIconButton(
        key: ValueKey("ringIconRemove-$at"),
        icon: Icons.close,
        tooltip: "Take this picture off the rings",
        onPressed: () => _put(rings, place, null),
      ),
      if (around) ...[
        // What it may be drawn as instead, and how often. Six of one picture
        // round a ring is a pattern; a crest, a ball and a boot is a set.
        const CanvasLineBreak(),
        for (var (n, pick) in icon.also.indexed) ...[
          CanvasIconButton(
            key: ValueKey("ringIconAlsoPick-$at$n"),
            icon: pick.asset.isEmpty
                ? Icons.add_photo_alternate
                : Icons.image_outlined,
            tooltip: "Choose this picture from a file",
            onPressed: () async {
              var id = await pickCanvasImage(context);
              if (id == null) return;
              set(_withPick(icon, n, pick.copyWith(asset: id)));
            },
          ),
          CanvasIconButton(
            key: ValueKey("ringIconAlsoLibrary-$at$n"),
            icon: Icons.photo_library_outlined,
            tooltip: "Use a picture you have already added",
            onPressed: () async {
              var id = await showRecentPictures(context);
              if (id == null) return;
              set(_withPick(icon, n, pick.copyWith(asset: id)));
            },
          ),
          CanvasNumberField(
            key: ValueKey("ringIconAlsoWeight-$at$n"),
            label: "How often",
            decimals: 1,
            width: 58,
            value: pick.weight,
            min: 0,
            max: 100,
            onChanged: (v) {
              onBegin();
              set(_withPick(icon, n, pick.copyWith(weight: v)));
            },
            onCommit: onCommit,
          ),
          CanvasIconButton(
            key: ValueKey("ringIconAlsoRemove-$at$n"),
            icon: Icons.close,
            tooltip: "Stop using this picture",
            onPressed: () => set(icon.copyWith(also: [
              for (var (m, other) in icon.also.indexed)
                if (m != n) other,
            ])),
          ),
          // A line each: side by side, two pictures' buttons look alike.
          const CanvasLineBreak(),
        ],
        // The first picture's own share, meaningless until there is another.
        if (icon.also.isNotEmpty)
          CanvasNumberField(
            key: ValueKey("ringIconWeight-$at"),
            label: "First one",
            decimals: 1,
            width: 58,
            value: icon.weight,
            min: 0,
            max: 100,
            onChanged: (v) {
              onBegin();
              set(icon.copyWith(weight: v));
            },
            onCommit: onCommit,
          ),
        CanvasIconButton(
          key: ValueKey("ringIconAlsoAdd-$at"),
          icon: Icons.library_add_outlined,
          tooltip: "Another picture to use around this ring",
          onPressed: () =>
              set(icon.copyWith(also: [...icon.also, const RingPick()])),
        ),
        if (icon.also.isNotEmpty)
          const CanvasHint(
              "Each place around the ring takes one of these pictures at "
              "random. How often is how much of the draw it gets: one at two "
              "comes up twice as often as one at one, and one at nought "
              "never."),
        // How far each one may differ from the rest: pictures threaded on a
        // wire, or pictures that happen to be near a ring.
        const CanvasLineBreak(),
        ..._drift(icon, place, "When", "Time", icon.driftWhen,
            (d) => icon.copyWith(driftWhen: d)),
        ..._drift(icon, place, "Where", "Position", icon.driftWhere,
            (d) => icon.copyWith(driftWhere: d)),
        ..._drift(icon, place, "Size", "Size", icon.driftSize,
            (d) => icon.copyWith(driftSize: d),
            limit: 4),
        ..._drift(icon, place, "Turn", "Turn", icon.driftTurn,
            (d) => icon.copyWith(driftTurn: d),
            limit: 360, decimals: 0, suffix: "\u00b0"),
        // A share of the ring's strength, nought invisible and one the ring's
        // own; never more: a full-strength ring cannot be brightened.
        ..._drift(icon, place, "Fade", "Fade", icon.driftFade,
            (d) => icon.copyWith(driftFade: d),
            least: 0),
        const CanvasHint(
            "How far each of these pictures is allowed to differ from the "
            "rest, and every one of them takes its own place in the range. "
            "Time is measured in the ring's life, so a picture moved through "
            "it sits off the line -- ahead of the ring or behind it -- and "
            "arrives and leaves at its own moment. One moved past either end "
            "of the life is not born yet, or gone. Position is measured in "
            "the gap to the next picture. Size is added to one: a half is "
            "half as big again. Fade is a share of the strength its ring is "
            "drawn at, so a half is half of it and nought is nothing."),
      ],
      // What a picture in the middle may set rather than inherit from its ring,
      // each off until switched on. Only in the middle: a set round a ring
      // differs by the ranges above.
      if (!around) ...[
        const CanvasLineBreak(),
        CanvasToggle(
          key: ValueKey("ringIconOwnFade-$at"),
          label: "Own opacity",
          value: icon.opacity != null,
          onChanged: (v) =>
              set(icon.copyWith(setOpacity: true, opacity: v ? 1.0 : null)),
        ),
        if (icon.opacity != null)
          CanvasNumberField(
            key: ValueKey("ringIconOpacity-$at"),
            label: "Opacity",
            decimals: 2,
            width: 58,
            value: icon.opacity!,
            min: 0,
            max: 1,
            onChanged: (v) {
              onBegin();
              set(icon.copyWith(setOpacity: true, opacity: v));
            },
            onCommit: onCommit,
          ),
        CanvasToggle(
          key: ValueKey("ringIconOwnSmallest-$at"),
          label: "Smallest",
          value: icon.smallest != null,
          onChanged: (v) =>
              set(icon.copyWith(setSmallest: true, smallest: v ? 0.1 : null)),
        ),
        if (icon.smallest != null)
          CanvasNumberField(
            key: ValueKey("ringIconSmallest-$at"),
            label: "No smaller than",
            decimals: 2,
            width: 58,
            value: icon.smallest!,
            min: 0,
            max: 4,
            onChanged: (v) {
              onBegin();
              set(icon.copyWith(setSmallest: true, smallest: v));
            },
            onCommit: onCommit,
          ),
        CanvasToggle(
          key: ValueKey("ringIconOwnLargest-$at"),
          label: "Largest",
          value: icon.largest != null,
          onChanged: (v) =>
              set(icon.copyWith(setLargest: true, largest: v ? 0.4 : null)),
        ),
        if (icon.largest != null)
          CanvasNumberField(
            key: ValueKey("ringIconLargest-$at"),
            label: "No bigger than",
            decimals: 2,
            width: 58,
            value: icon.largest!,
            min: 0,
            max: 4,
            onChanged: (v) {
              onBegin();
              set(icon.copyWith(setLargest: true, largest: v));
            },
            onCommit: onCommit,
          ),
        CanvasToggle(
          key: ValueKey("ringIconHoldIn-$at"),
          label: "No fade in",
          value: icon.holdIn,
          onChanged: (v) => set(icon.copyWith(holdIn: v)),
        ),
        CanvasToggle(
          key: ValueKey("ringIconHoldOut-$at"),
          label: "No fade out",
          value: icon.holdOut,
          onChanged: (v) => set(icon.copyWith(holdOut: v)),
        ),
        CanvasToggle(
          key: ValueKey("ringIconFirstRun-$at"),
          label: "First run only",
          value: icon.firstRunOnly,
          onChanged: (v) => set(icon.copyWith(firstRunOnly: v)),
        ),
        const CanvasHint(
            "Off, each of these is inherited from the ring the picture is "
            "tied to. Own opacity draws it at one strength whatever the ring "
            "is doing. Smallest and largest hold its size between two "
            "fractions of the page, so it stops growing with the ring rather "
            "than growing out of the picture. The two fades leave out the "
            "ring's arrival or its departure, and first run only says it "
            "once."),
      ],
    ];
  }

  /// _withPick is [icon] with one of its other pictures replaced.
  RingIcon _withPick(RingIcon icon, int which, RingPick next) =>
      icon.copyWith(also: [
        for (var (n, pick) in icon.also.indexed)
          if (n == which) next else pick,
      ]);

  /// _drift is the two ends of one of an icon's scatter ranges: a pair, since
  /// the useful thing to say is usually lopsided (a little smaller and a lot
  /// bigger, late but never early). See RingDrift.
  List<Widget> _drift(
    RingIcon icon,
    RingIconPlace place,
    String name,
    String label,
    RingDrift value,
    RingIcon Function(RingDrift) put, {
    double limit = 1,
    double? least,
    int decimals = 2,
    String suffix = "",
  }) =>
      [
        for (var (which, end) in [("Least", value.least), ("Most", value.most)])
          CanvasNumberField(
            key: ValueKey("ringIcon$name$which-${place.name}"),
            label: which == "Least" ? "$label from" : "to",
            decimals: decimals,
            width: 54,
            suffix: suffix,
            value: end,
            min: least ?? -limit,
            max: limit,
            onChanged: (v) {
              onBegin();
              _put(
                  spec.rings,
                  place,
                  put(which == "Least"
                      ? value.copyWith(least: v)
                      : value.copyWith(most: v)));
            },
            onCommit: onCommit,
          ),
      ];

  void _setNow(ProceduralSpec next) {
    onBegin();
    onChanged(next);
    onCommit();
  }

  /// _sectioned is [groups] in sections. A section that is a single expander
  /// shows that expander's contents, the section itself being the fold.
  List<Widget> _sectioned(List<Widget> groups) {
    var by = <String, List<Widget>>{};
    for (var g in groups) {
      (by[ProceduralSettings._sectionOf(g)] ??= []).add(g);
    }
    List<Widget> unfolded(List<Widget> ws) {
      if (ws.length != 1) return ws;
      var w = ws.single;
      if (w is Padding && w.child is CanvasExpander) w = w.child!;
      if (w is! CanvasExpander) return ws;
      return [
        if (w.action != null)
          Align(alignment: Alignment.centerRight, child: w.action!),
        ...w.children,
      ];
    }

    var look = lookMatching(spec)?.name;
    Widget part(String name, IconData icon, String title, String summary,
            {bool open = false}) =>
        CanvasSection(
          key: ValueKey("backgroundSection-$name"),
          icon: icon,
          title: title,
          summary: summary,
          remember: "$rememberAs.$name",
          initiallyOpen: open,
          children: unfolded(by[name]!),
        );
    return [
      if (by.containsKey("pattern"))
        part("pattern", Icons.blur_on, "Pattern",
            [spec.style.label, if (look != null) look].join(" · "),
            open: true),
      if (by.containsKey("colour"))
        part("colour", Icons.palette_outlined, "Colour and amount",
            "Density ${(spec.density * 100).round()}%"),
      if (by.containsKey("movement"))
        part("movement", Icons.animation, "Movement",
            spec.animated || layer ? "Moves" : "Still"),
      if (by.containsKey("effects"))
        part("effects", Icons.auto_awesome_outlined, "Effects",
            fx.any ? "On" : "None"),
      if (by.containsKey("lights"))
        part("lights", Icons.light_mode_outlined, "Lights",
            light.on ? "Spotlight" : "None"),
    ];
  }

  RingSpec get rings => spec.rings;

  LightSpec get light => spec.light;

  MetalSpec get metal => spec.metal;

  /// _light, _lightNow and _metalSet are _set and _setNow for the two specs
  /// of their own, the way _rings is for the rings.
  void _light(LightSpec next) => _set(spec.copyWith(light: next));

  void _lightNow(LightSpec next) => _setNow(spec.copyWith(light: next));

  void _metalSet(MetalSpec next) => _set(spec.copyWith(metal: next));
}
