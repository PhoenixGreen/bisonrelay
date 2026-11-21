import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_app.dart';

// canvas_number_field_test.dart is the number field's caption, dragged
// sideways to change the number. Every change it makes must be followed by
// a commit: the settings open an undo step on the first change, and only
// the commit closes it.

void main() {
  /// field is a number field at 10, counting its changes and commits.
  Future<({List<double> changes, List<int> commits})> field(
      WidgetTester tester) async {
    var changes = <double>[];
    var commits = <int>[];
    await tester.pumpWidget(canvasApp(Center(
        child: CanvasNumberField(
            label: "Size",
            value: 10,
            min: 0,
            max: 100,
            onChanged: changes.add,
            onCommit: () => commits.add(changes.length)))));
    await tester.pumpAndSettle();
    return (changes: changes, commits: commits);
  }

  testWidgets("a drag along the caption changes the number, then commits",
      (tester) async {
    var seen = await field(tester);
    var drag = await tester.startGesture(tester.getCenter(find.text("Size")),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(30, 0));
    expect(seen.changes, isNotEmpty);
    expect(seen.changes.last, greaterThan(10));
    expect(seen.commits, isEmpty, reason: "not until it is let go");
    await drag.up();
    expect(seen.commits, [seen.changes.length]);
  });

  testWidgets("a drag that is cancelled commits too", (tester) async {
    // A pointer can be taken away mid-drag (the window loses it, another
    // gesture claims it). What it had changed is changed all the same.
    var seen = await field(tester);
    var drag = await tester.startGesture(tester.getCenter(find.text("Size")),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(30, 0));
    expect(seen.changes, isNotEmpty);
    await drag.cancel();
    expect(seen.commits, [seen.changes.length]);
  });
}
