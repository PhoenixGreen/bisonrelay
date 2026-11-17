import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
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
