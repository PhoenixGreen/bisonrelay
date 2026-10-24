import 'package:bruig/components/containers.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A sidebar's edge dragged: each move of the pointer is added to the width as
// it is, so two moves before the next frame both count and the edge keeps up
// with the pointer.

void main() {
  testWidgets("two moves before a frame both move the edge", (tester) async {
    SharedPreferences.setMockInitialValues({});
    double? shown;
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (c) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
        home: Scaffold(
          body: ResizableSidebar(
            storageKey:
                "test-resizable-${DateTime.now().microsecondsSinceEpoch}",
            defaultWidth: 240,
            builder: (context, width, handle) {
              shown = width;
              return Row(children: [
                SizedBox(width: width),
                SizedBox(key: const ValueKey("edge"), width: 8, child: handle),
                const Expanded(child: SizedBox()),
              ]);
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(shown, 240);
    var g = await tester
        .startGesture(tester.getCenter(find.byKey(const ValueKey("edge"))));
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    var before = shown!;
    // Two moves, no frame between them.
    await g.moveBy(const Offset(10, 0));
    await g.moveBy(const Offset(10, 0));
    await tester.pump();
    // The resize cursor held over the whole sidebar while dragging, not
    // only over the handle the pointer has got ahead of.
    MouseCursor held() => tester
        .widget<MouseRegion>(find
            .ancestor(
                of: find.byType(Row).first, matching: find.byType(MouseRegion))
            .first)
        .cursor;
    expect(held(), SystemMouseCursors.resizeLeftRight);
    await g.up();
    await tester.pumpAndSettle();
    expect(shown, closeTo(before + 20, 0.01));
    expect(held(), MouseCursor.defer, reason: "let go, the cursor is let go");
  });
}
