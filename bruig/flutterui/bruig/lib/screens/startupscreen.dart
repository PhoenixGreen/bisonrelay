import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/models/uistate.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bruig/theme_manager.dart';

class StartupScreen extends StatelessWidget {
  final List<Widget> widgetList;
  final bool hideAboutButton;
  final Widget? fab;
  final double? childrenWidth;
  const StartupScreen(this.widgetList,
      {this.hideAboutButton = false, this.fab, this.childrenWidth, super.key});

  Widget _buildChildren() {
    return Column(
        mainAxisAlignment: MainAxisAlignment.center, children: widgetList);
  }

  Widget _innerContent() => SingleChildScrollView(
      child: childrenWidth != null
          ? SizedBox(width: childrenWidth, child: _buildChildren())
          : _buildChildren());

  // _outerBackground is the full-screen backdrop behind the login form.
  // Unmodified, it's the app's original "network pattern" image exactly;
  // customized, the user's own solid/gradient/image replaces it entirely --
  // this is what exposes that pattern as removable/replaceable, rather than
  // it being an always-on hardcoded asset outside of any themed area.
  BoxDecoration _outerBackground(ThemeNotifier theme, AreaStyle style) {
    if (style.mode == AreaBackgroundMode.token) {
      return const BoxDecoration(
          image: DecorationImage(
        alignment: Alignment.topRight,
        fit: BoxFit.fitHeight,
        image: AssetImage("assets/images/loading-bg.png"),
      ));
    }
    var bg = theme.areaDecoration(ThemeArea.loginScreen, SurfaceColor.surface);
    return BoxDecoration(color: bg.color, gradient: bg.gradient, image: bg.image);
  }

  // _buildLoginContainer wraps the login form: unmodified, it reproduces the
  // original per-theme gradient fade exactly; customized, it uses the full
  // background+border (solid/gradient/image) treatment via areaContainer,
  // which also applies the AreaStyle's own padding/margin -- the original
  // hardcoded 30px padding+center alignment moves to an inner Container so
  // it still applies to the form itself either way.
  Widget _buildLoginContainer(ThemeNotifier theme) {
    var style = theme.areaStyle(ThemeArea.loginScreen);
    var overridden = style.mode != AreaBackgroundMode.token ||
        style.borderMode != AreaBackgroundMode.token ||
        style.padding > 0 ||
        style.margin > 0;
    var inner = Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(30),
        child: _innerContent());

    if (!overridden) {
      return Container(
          decoration: theme.fullTheme.startupScreenBoxDecoration,
          child: inner);
    }
    return theme.areaContainer(ThemeArea.loginScreen, SurfaceColor.surface,
        child: inner);
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    return Scaffold(
        body: Consumer<ThemeNotifier>(
            builder: (context, theme, child) => Container(
                decoration: _outerBackground(
                    theme, theme.areaStyle(ThemeArea.loginScreen)),
                child: Stack(children: [
                  _buildLoginContainer(theme),
                  !hideAboutButton
                      ? Positioned(
                          top: 5,
                          left: 5,
                          child: SizedBox(
                              height: isScreenSmall ? 70 : 100,
                              width: isScreenSmall ? 70 : 100,
                              child: const Center(child: AboutButton())))
                      : const Empty(),
                  if (fab != null)
                    Positioned(right: 10, bottom: 10, child: fab!),
                ]))));
  }
}
