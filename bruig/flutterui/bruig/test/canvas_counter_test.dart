import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_counter_test.dart is the number a counter writes.
//
// The whole reason to reach for this element rather than a text box is that
// "1,240,000" and "1 240 000,0" and "20:41" are the same number written three
// ways, and a text box knows none of that. So the formatting is the feature,
// and it is what this pins.

String _plain(double v, [int places = 0]) =>
    formatCounter(v, places, CounterSeparator.none);

void main() {
  group("a plain number", () {
    test("is written as it stands", () {
      expect(_plain(0), "0");
      expect(_plain(1234), "1234");
      expect(_plain(-42), "-42");
    });

    test("with as many figures after the point as were asked for", () {
      expect(_plain(1.5, 2), "1.50");
      expect(_plain(1, 3), "1.000");
      expect(_plain(0.125, 2), "0.13");
    });

    test("rounded once, as a whole", () {
      // Working out the whole part and the fraction separately gets this
      // wrong: the whole part is one and the fraction rounds to 00, which
      // writes 1.00 for a number that is two.
      expect(_plain(1.999, 2), "2.00");
      expect(_plain(-1.999, 2), "-2.00");
    });
  });

  group("the separators", () {
    test("group the thousands the way each of them groups", () {
      expect(formatCounter(1234567, 0, CounterSeparator.comma), "1,234,567");
      expect(formatCounter(1234567, 0, CounterSeparator.dot), "1.234.567");
      expect(formatCounter(1234567, 0, CounterSeparator.space), "1 234 567");
    });

    test("and put the point where that convention puts it", () {
      // A number written 1.234,56 is not 1,234.56 with a different point, it
      // is a different convention -- which is why the grouping and the point
      // are one setting.
      expect(formatCounter(1234.5, 1, CounterSeparator.comma), "1,234.5");
      expect(formatCounter(1234.5, 1, CounterSeparator.dot), "1.234,5");
    });

    test("and leave a number under a thousand alone", () {
      expect(formatCounter(999, 0, CounterSeparator.comma), "999");
      expect(formatCounter(-999, 0, CounterSeparator.comma), "-999");
    });

    test("and a negative keeps its sign in front of the grouping", () {
      expect(formatCounter(-1234567, 0, CounterSeparator.comma), "-1,234,567");
    });
  });

  group("as a time", () {
    test("the value is seconds, written as a clock reads them", () {
      expect(formatCounter(117, 0, CounterSeparator.minutes), "1:57");
      expect(formatCounter(0, 0, CounterSeparator.minutes), "0:00");
      expect(formatCounter(59, 0, CounterSeparator.minutes), "0:59");
    });

    test("and the seconds keep their leading nought", () {
      // A clock that loses it once a minute is a clock that flickers.
      expect(formatCounter(61, 0, CounterSeparator.minutes), "1:01");
      expect(formatCounter(3605, 0, CounterSeparator.hours), "1:00:05");
    });

    test("hours carry the minutes as two figures as well", () {
      expect(formatCounter(3723, 0, CounterSeparator.hours), "1:02:03");
      expect(formatCounter(45296, 0, CounterSeparator.hours), "12:34:56");
    });

    test("and minutes run past sixty rather than rolling over", () {
      // 90 minutes is a stopwatch reading 90:00, not 1:30:00: the Hours
      // separator is what asks for the hour.
      expect(formatCounter(5400, 0, CounterSeparator.minutes), "90:00");
    });

    test("with the fraction of a second after the point", () {
      expect(formatCounter(117.25, 2, CounterSeparator.minutes), "1:57.25");
      expect(formatCounter(9.5, 1, CounterSeparator.minutes), "0:09.5");
    });

    test("and a countdown keeps its minus", () {
      expect(formatCounter(-5, 0, CounterSeparator.minutes), "-0:05");
    });
  });

  group("the element", () {
    test("writes the words either side of the number", () {
      var e = const CounterElement(ElementBase(id: "c"),
          before: "£",
          after: " raised",
          decimals: 2,
          separator: CounterSeparator.comma);
      expect(e.textFor(1234.5), "£1,234.50 raised");
    });

    test("counts either way round", () {
      const up = CounterElement(ElementBase(id: "c"), from: 0, to: 100);
      const down = CounterElement(ElementBase(id: "c"), from: 100, to: 0);
      expect(up.valueAtFraction(0.25), 25);
      expect(down.valueAtFraction(0.25), 75);
      expect(down.span, -100);
    });

    test("and a counter whose ends are the same sits still", () {
      // Which is a perfectly good thing to want from a clock.
      const e = CounterElement(ElementBase(id: "c"), from: 12, to: 12);
      expect(e.valueAtFraction(0), 12);
      expect(e.valueAtFraction(1), 12);
    });

    test("is keyed until it is told to run", () {
      const e = CounterElement(ElementBase(id: "c"));
      expect(e.keyed, isTrue);
      expect(e.live, isFalse);
      expect(e.copyWith(keyed: false).live, isTrue);
    });
  });

  group("what is saved", () {
    test("is what was set, and not what was left alone", () {
      var plain = const CounterElement(ElementBase(id: "c")).props();
      expect(plain.containsKey("sep"), isFalse);
      expect(plain.containsKey("buttons"), isFalse);
      expect(plain.containsKey("live"), isFalse,
          reason: "keyed is the default, and the key says the other thing");
    });

    test("and comes back as it went in", () {
      var e = const CounterElement(
        ElementBase(id: "c"),
        from: 120,
        to: 0,
        decimals: 2,
        separator: CounterSeparator.minutes,
        before: "T-",
        after: " to go",
        keyed: false,
        source: CounterSource.run,
        rate: 60,
        loop: true,
        running: true,
        buttons: [CounterButton.startStop, CounterButton.reset],
      );
      var back = CounterElement.fromJson(e.props(), const ElementBase(id: "c"));
      expect(back.from, 120);
      expect(back.to, 0);
      expect(back.decimals, 2);
      expect(back.separator, CounterSeparator.minutes);
      expect(back.before, "T-");
      expect(back.after, " to go");
      expect(back.keyed, isFalse);
      expect(back.rate, 60);
      expect(back.loop, isTrue);
      expect(back.running, isTrue);
      expect(back.buttons, [CounterButton.startStop, CounterButton.reset]);
    });

    test("and a button nobody recognises is dropped, not crashed on", () {
      var back = CounterElement.fromJson(const {
        "buttons": ["startStop", "explode"]
      }, const ElementBase(id: "c"));
      expect(back.buttons, [CounterButton.startStop]);
    });
  });
}
