import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart' show CanvasTip;
import 'package:bruig/theming_system/runtime/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

// canvas_app.dart puts a widget under test inside what the app gives every
// screen: its theme, its snack bar, the Canvas preferences, a MaterialApp
// and a Scaffold. One harness for every test, so a test says only what it
// is about, and a widget that reads something the app always provides is
// tested with it there.

/// canvasApp is [child] as the app would hold it. [theme] and [prefs] are a
/// test's own where it needs to change or read them; [extra] are any other
/// models the widget reads. Without [scaffold], [child] is the MaterialApp's
/// home itself.
Widget canvasApp(Widget child,
        {ThemeNotifier? theme,
        CanvasPreferences? prefs,
        List<SingleChildWidget> extra = const [],
        bool scaffold = true}) =>
    MultiProvider(
      providers: [
        theme == null
            ? ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false))
            : ChangeNotifierProvider<ThemeNotifier>.value(value: theme),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        prefs == null
            ? ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences())
            : ChangeNotifierProvider<CanvasPreferences>.value(value: prefs),
        ...extra,
      ],
      child: MaterialApp(home: scaffold ? Scaffold(body: child) : child),
    );

/// pumpCanvasApp shows [child] in [canvasApp] on a screen of [size] (at one
/// pixel to the point) and, unless told not to, lets it settle.
Future<void> pumpCanvasApp(WidgetTester tester, Widget child,
    {Size? size,
    ThemeNotifier? theme,
    CanvasPreferences? prefs,
    List<SingleChildWidget> extra = const [],
    bool scaffold = true,
    bool settle = true}) async {
  if (size != null) setTestScreen(tester, size);
  await tester.pumpWidget(canvasApp(child,
      theme: theme, prefs: prefs, extra: extra, scaffold: scaffold));
  if (settle) await tester.pumpAndSettle();
}

/// setTestScreen makes the test's screen [size], at one pixel to the point,
/// until the test ends.
void setTestScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// setTestTextScale sets the system text size the app is laid out at, until
/// the test ends (Ken runs a larger one than the default).
void setTestTextScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// pumpUntil pumps, letting the real event loop turn between frames (a file
/// read or a decode finishes there, not in the test's fake time), until
/// [done] holds or [within] has gone by, then pumps once more so what it
/// changed is drawn. True where [done] came to hold.
Future<bool> pumpUntil(WidgetTester tester, bool Function() done,
    {Duration within = const Duration(seconds: 5)}) async {
  const step = Duration(milliseconds: 10);
  for (var waited = Duration.zero; waited < within && !done(); waited += step) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
  await tester.pump();
  return done();
}

/// sweepSizes lays out what is already pumped again at each text size in
/// [scales] and each screen size in [sizes] in turn, [settle] frames each,
/// and fails naming the size where something threw or overran. [check], if
/// given, runs at each size too, handed the size's name for its reasons.
/// One tree laid out many times costs a fraction of building one for each
/// size; what it does not check is a widget that reads its size only when
/// first built.
///
/// The text size is the platform's (setTestTextScale): a MediaQuery of the
/// test's own round the tree would hold it still.
Future<void> sweepSizes(WidgetTester tester,
    {required List<Size> sizes,
    List<double> scales = const [1.0, 1.4],
    int settle = 4,
    void Function(String at)? check}) async {
  for (var scale in scales) {
    setTestTextScale(tester, scale);
    for (var size in sizes) {
      tester.view.physicalSize = size;
      for (var i = 0; i < settle; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      var at = "at ${size.width.round()} by ${size.height.round()}, "
          "${scale}x text";
      expect(tester.takeException(), isNull, reason: at);
      check?.call(at);
    }
  }
}

/// byTip finds a control by its hover text: a CanvasTip, which builds no
/// Tooltip where hover text is off (an element's settings), or a Tooltip
/// that is not one a CanvasTip built.
Finder byTip(String message, {bool skipOffstage = true}) =>
    find.byElementPredicate((e) {
      var w = e.widget;
      if (w is CanvasTip) return w.message == message;
      if (w is! Tooltip || w.message != message) return false;
      Widget? parent;
      e.visitAncestorElements((a) {
        parent = a.widget;
        return false;
      });
      return parent is! CanvasTip;
    },
        description: 'control with hover text "$message"',
        skipOffstage: skipOffstage);
