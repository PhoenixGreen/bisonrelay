import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_reading.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// canvas_counter_saved_form_test.dart is what a counter saves in each of the
// things it can be (counted by keyframes, a run, a clock, a game's count, a
// page number), written out key by key in order, and what each reads back:
// from what it saves, and from hand-made files that set the keys deciding
// what it is in every combination, including ones the panel never writes.
// A file saved by any build reads the same in every later one, so none of
// it may change by a key, a value or an omission.
//
// The type and the box are written whole by their own classes and are held
// elsewhere; here they are only checked to be where they always were.

const _base = ElementBase(id: "c", x: 10, y: 20, width: 300, height: 120);

/// _saved is what [e] saves of itself, through JSON as a file holds it.
Map<String, dynamic> _saved(CanvasElement e) =>
    jsonDecode(jsonEncode(e.props())) as Map<String, dynamic>;

/// _read is a counter read from a saved form of [e] with [changes] made to
/// it (a [_gone] removes the key).
CounterElement _read(CounterElement e, Map<String, Object?> changes) {
  var json = jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;
  for (var MapEntry(:key, :value) in changes.entries) {
    value == _gone ? json.remove(key) : json[key] = value;
  }
  return elementFromJson(json) as CounterElement;
}

const _gone = "<gone>";

/// _specs are the keys every counter writes whole, and where.
const _specs = ["numberSpec", "affixSpec", "box", "animation"];

void main() {
  var spec = jsonDecode(jsonEncode(const CounterElement(_base).props()));

  group("a counter saves what it is", () {
    var cases = <(String, CounterElement, Map<String, dynamic>)>[
      (
        "counted by keyframes, as made",
        const CounterElement(_base),
        {
          "from": 0.0,
          "to": 100.0,
          "numberSpec": spec["numberSpec"],
          "affixSpec": spec["affixSpec"],
          "box": spec["box"],
          "animation": spec["animation"],
        },
      ),
      (
        "a run, with every one of its own settings away from its default",
        const CounterElement(_base,
            from: 120,
            to: -5.5,
            decimals: 2,
            separator: CounterSeparator.minutes,
            before: "T-",
            after: " to go",
            gap: 0.5,
            keyed: false,
            rate: 60,
            loop: true,
            running: true,
            buttons: [CounterButton.startStop, CounterButton.reset],
            looseButtons: true,
            buttonAt: [Offset(-0.25, 0.4), Offset(0.25, 0.4)],
            buttonSize: Size(0.2, 0.15)),
        {
          "from": 120.0,
          "to": -5.5,
          "decimals": 2,
          "sep": "minutes",
          "before": "T-",
          "after": " to go",
          "gap": 0.5,
          "numberSpec": spec["numberSpec"],
          "affixSpec": spec["affixSpec"],
          "box": spec["box"],
          "live": true,
          "rate": 60.0,
          "loop": true,
          "running": true,
          "buttons": ["startStop", "reset"],
          "buttonSpec": jsonDecode(
              jsonEncode(const CounterElement(_base).buttonSpec.toJson())),
          "buttonBox": jsonDecode(
              jsonEncode(const CounterElement(_base).buttonBox.toJson())),
          "looseButtons": true,
          "buttonAt": [
            [-0.25, 0.4],
            [0.25, 0.4]
          ],
          "buttonSize": [0.2, 0.15],
          "animation": spec["animation"],
        },
      ),
      (
        "a clock",
        const CounterElement(_base,
            keyed: false,
            source: CounterSource.clock,
            separator: CounterSeparator.hours,
            running: true),
        {
          "from": 0.0,
          "to": 100.0,
          "sep": "hours",
          "numberSpec": spec["numberSpec"],
          "affixSpec": spec["affixSpec"],
          "box": spec["box"],
          "live": true,
          "source": "clock",
          "running": true,
          "animation": spec["animation"],
        },
      ),
      (
        "a game's count, made from a keyed counter",
        const CounterElement(_base,
            source: CounterSource.game,
            gameCount: "coins",
            buttons: [CounterButton.input]),
        {
          "from": 0.0,
          "to": 100.0,
          "numberSpec": spec["numberSpec"],
          "affixSpec": spec["affixSpec"],
          "box": spec["box"],
          "source": "game",
          "gameCount": "coins",
          "buttons": ["input"],
          "buttonSpec": jsonDecode(
              jsonEncode(const CounterElement(_base).buttonSpec.toJson())),
          "buttonBox": jsonDecode(
              jsonEncode(const CounterElement(_base).buttonBox.toJson())),
          "animation": spec["animation"],
        },
      ),
      (
        "a page number, mirrored, with loose words",
        const CounterElement(_base,
            source: CounterSource.page,
            mirrored: true,
            fit: false,
            before: "Page",
            loose: true,
            beforeAt: Offset(0, -0.4),
            numberStyle: "Folio",
            wordStyle: "Small"),
        {
          "from": 0.0,
          "to": 100.0,
          "before": "Page",
          "loose": true,
          "beforeAt": [0.0, -0.4],
          "afterAt": [0.0, 0.0],
          "numberSpec": spec["numberSpec"],
          "affixSpec": spec["affixSpec"],
          "numberStyle": "Folio",
          "wordStyle": "Small",
          "box": spec["box"],
          "noFit": true,
          "source": "page",
          "mirrored": true,
          "animation": spec["animation"],
        },
      ),
    ];
    for (var (what, counter, saved) in cases) {
      test(what, () {
        expect(jsonEncode(_saved(counter)), jsonEncode(saved));
        var back = _read(counter, const {});
        expect(jsonEncode(back.toJson()), jsonEncode(counter.toJson()),
            reason: "read back as it was");
      });
    }

    test("and writes the type, the box and its arrival whole every time", () {
      var saved = _saved(const CounterElement(_base));
      for (var key in _specs) {
        expect(saved.containsKey(key), isTrue, reason: key);
      }
    });
  });

  group("what decides what a counter is reads back the same", () {
    // Every combination of the two keys that decide it, as a hand-made or
    // older file may hold them: whether it says "live", and its source.
    for (var live in [null, false, true]) {
      for (var source in [null, ...CounterSource.values.map((s) => s.name)]) {
        test("\"live\": $live, \"source\": $source", () {
          var back = _read(const CounterElement(_base), {
            "live": live ?? _gone,
            "source": source ?? _gone,
          });
          expect(back.keyed, live != true,
              reason: "\"live\" is saved for a counter that is not keyed");
          expect(back.source, CounterSource.fromName(source));
          // And written again as it was read, key for key.
          var again = _saved(back);
          expect(again["live"], live == true ? true : null);
          expect(again["source"],
              source == null || source == "run" ? null : source);
        });
      }
    }

    test("a source nobody knows reads as a run", () {
      var back = _read(const CounterElement(_base), {"source": "tides"});
      expect(back.source, CounterSource.run);
      expect(_saved(back).containsKey("source"), isFalse);
    });

    test("and a keyed counter's keys stay on its track, not in its fields", () {
      var keyed = const CounterElement(_base).withBase(
          track: ElementTrack([
        const Keyframe(frame: 0).withValue(KeyframeChannel.count, 0),
        const Keyframe(frame: 24).withValue(KeyframeChannel.count, 100),
      ])) as CounterElement;
      var saved = jsonDecode(jsonEncode(keyed.toJson())) as Map;
      expect(saved.containsKey("track"), isTrue);
      var back = elementFromJson(saved as Map<String, dynamic>);
      expect(jsonEncode(back.toJson()), jsonEncode(keyed.toJson()));
    });
  });

  test("a counter's type reads back with its case", () {
    var cased = const CounterElement(_base,
        affixSpec: TextSpec(fontSize: 20, textCase: TextCase.upper));
    expect(_read(cased, const {}).affixSpec.textCase, TextCase.upper);
  });
}
