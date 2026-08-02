import 'dart:async';
import 'dart:math';

import 'package:bruig/components/containers.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:provider/provider.dart';

// _sized layers the fixed geometry the login/startup screens' buttons have
// always had (a wide, tall pill) over a role's compiled ButtonStyle, without
// overwriting anything the Buttons theme area set: merge keeps the receiver's
// own non-null properties and fills the rest in from the argument, so a
// padding chosen in the editor still wins over the one below.
ButtonStyle _sized(ButtonStyle style, {double minWidth = 150}) =>
    style.merge(ButtonStyle(
      padding: const WidgetStatePropertyAll(
          EdgeInsets.only(left: 34, top: 10, right: 34, bottom: 10)),
      minimumSize: WidgetStatePropertyAll(Size(minWidth, 55)),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(30)),
      )),
    ));

// CancelButton is the app's Danger button (ButtonRole.danger) -- the red one
// in every screenshot of Bison Relay: Clear Post, Close Channel, and the
// ~24 plain Cancel/dismiss actions that share the widget. It's styled from
// the palette's "Button Background Secondary" via the compiled role style,
// so the Buttons theme area can retune all of them at once.
class CancelButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String label;
  const CancelButton(
      {required this.onPressed,
      this.loading = false,
      this.label = "Cancel",
      super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
        builder: (context, theme, child) => ElevatedButton(
            style: theme.buttonStyle(ButtonRole.danger),
            onPressed: !loading ? onPressed : null,
            child: Text(label)));
  }
}

// raisedButtonStyle is the Primary button (ButtonRole.primary) at the size
// the login/startup screens draw it: Unlock Wallet, Create Wallet.
ButtonStyle raisedButtonStyle(ThemeNotifier theme) =>
    _sized(theme.buttonStyle(ButtonRole.primary));

// emptyButtonStyle is the same geometry over the Outlined role
// (ButtonRole.outlined) -- the bordered, unfilled button.
ButtonStyle emptyButtonStyle(ThemeNotifier theme) =>
    _sized(theme.buttonStyle(ButtonRole.outlined));

ButtonStyle readMoreButton(ThemeNotifier theme) {
  return ElevatedButton.styleFrom(
    padding: const EdgeInsets.only(left: 10, top: 10, right: 10, bottom: 10),
    // foregroundColor: theme.dividerColor,
    //padding: EdgeInsets.symmetric(horizontal: 16),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(30)),
        side: BorderSide(/*color: theme.indicatorColor,*/ width: 1)),
  );
}

class LoadingScreenButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String text;
  final bool empty;
  final double minSize;
  const LoadingScreenButton(
      {required this.onPressed,
      required this.text,
      this.loading = false,
      this.empty = false,
      this.minSize = 0,
      super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) => TextButton(
            style: minSize != 0
                // A caller-set width still draws the Primary role -- it's
                // the same login-screen button, just measured to fit a
                // specific column.
                ? _sized(theme.buttonStyle(ButtonRole.primary),
                    minWidth: minSize - 30)
                : empty
                    ? emptyButtonStyle(theme)
                    : raisedButtonStyle(theme),
            onPressed: !loading ? onPressed : null,
            child: Txt.L(text, textAlign: TextAlign.center)));
  }
}

// Generic about button.
class AboutButton extends StatelessWidget {
  const AboutButton({super.key});
  @override
  Widget build(BuildContext context) {
    // Follows the app icon setting like every other place the icon is
    // drawn (see customAppIcon). This button is only ever shown on the
    // startup/login screens, so the header area's loginLogoSize is what
    // sizes it; without one it falls back to whatever the icon theme says,
    // which is what it used before the setting existed.
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var iconSize = theme.areaStyle(ThemeArea.header).loginLogoSize ??
          IconTheme.of(context).size ??
          24;
      return IconButton(
          tooltip: "About Bison Relay",
          iconSize: iconSize,
          onPressed: () {
            Navigator.of(context).pushNamed("/about");
          },
          icon: customAppIcon(theme, iconSize) ??
              Image.asset(BisonRelayLogo.assetPath, fit: BoxFit.contain));
    });
  }
}

class CircularProgressButton extends StatefulWidget {
  final bool active;
  final IconData? activeIcon;
  final IconData inactiveIcon;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;
  final VoidCallback? onHold;
  final Duration? holdDuration;
  final double sizeMultiplier;
  const CircularProgressButton(
      {this.active = false,
      required this.inactiveIcon,
      this.activeIcon,
      this.onTapDown,
      this.onTapUp,
      this.onHold,
      this.holdDuration,
      this.sizeMultiplier = 1.0,
      super.key});

  @override
  State<CircularProgressButton> createState() => _CircularProgressButtonState();
}

class _CircularProgressButtonState extends State<CircularProgressButton> {
  double? progress;
  Timer? progressTimer;
  DateTime? progressStart;

  void updateProgress(_) {
    var now = DateTime.now();
    var elapsedMs = DateTime.now()
        .difference(progressStart ?? now)
        .inMilliseconds
        .toDouble();
    var totalMs = (widget.holdDuration?.inMilliseconds ?? 0).toDouble();
    if (totalMs == 0) {
      return;
    }
    var newProgress = min(elapsedMs / totalMs, 1.0);
    setState(() {
      progress = newProgress;
    });

    if (progress == 1) {
      progressTimer?.cancel();
      progressTimer = null;
      if (widget.onHold != null) {
        widget.onHold!();
      }
    }
  }

  void tapDown(_) {
    if (widget.onTapDown != null) {
      widget.onTapDown!();
    }
    if (widget.holdDuration != null && progressTimer == null) {
      progressStart = DateTime.now();
      progressTimer =
          Timer.periodic(const Duration(milliseconds: 80), updateProgress);
    }
  }

  void tapUp(_) {
    if (widget.onTapUp != null) {
      widget.onTapUp!();
    }

    if (progressTimer != null) {
      progressTimer?.cancel();
      progressTimer = null;
      setState(() {
        progress = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant CircularProgressButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.activeIcon != widget.activeIcon ||
        oldWidget.inactiveIcon != widget.inactiveIcon ||
        oldWidget.holdDuration != widget.holdDuration) {
      setState(() {
        if (widget.holdDuration == null) {
          progress = null;
        }
      });
    }
  }

  @override
  void dispose() {
    progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    IconData icon = widget.active
        ? widget.activeIcon ?? widget.inactiveIcon
        : widget.inactiveIcon;
    return Stack(alignment: Alignment.center, children: [
      SizedBox(
          width: 40 * widget.sizeMultiplier,
          height: 40 * widget.sizeMultiplier,
          child: widget.active || progress != null
              ? CircularProgressIndicator(value: progress, strokeWidth: 2)
              : const Empty()),
      InkResponse(
          radius: 17 * widget.sizeMultiplier,
          containedInkWell: false,
          onTapDown: tapDown,
          onTapUp: tapUp,
          child: Consumer<ThemeNotifier>(
              builder: (context, theme, child) => Icon(icon,
                  size: 25 * widget.sizeMultiplier,
                  color: theme.textColor(TextColor.onSurfaceVariant))))
    ]);
  }
}
