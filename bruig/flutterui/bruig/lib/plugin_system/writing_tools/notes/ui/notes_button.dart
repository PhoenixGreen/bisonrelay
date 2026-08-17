import 'package:bruig/plugin_system/writing_tools/notes/notes_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// notes_button.dart is the one control that opens notes anywhere in the app.
//
// One button, because the previous arrangement had a note button on every row
// of every file list and in the preview header, and the count only went up as
// notes reached chats and posts. A control repeated everywhere stops being
// read; a control in one place gets learned once.
//
// It sits over the bottom edge of the content area rather than in a toolbar,
// which is the other half of the same argument: there is no toolbar every page
// has, and adding one to each would put the button in a different place on
// every page. The cost is that it overlaps whatever the page draws down there,
// which is why the reader chooses which corner it takes.
//
// It is only ever drawn while the panel is CLOSED -- see NotesHost. The panel
// carries its own close button, and a second control doing the same thing two
// inches below it is one the reader has to decide between for no reason.

/// _size is the button's tap target.
///
/// Small: it is drawn over somebody else's content and is not the thing on the
/// page anyone came for.
const double _size = 24;

/// _wedgeSize is how much of that the triangle forms actually paint.
///
/// Half, so the mark in the corner stays discreet, while the thing you have to
/// hit stays the full [_size]. Keeping the two apart is the point: shrinking
/// the button itself would have made a 12-pixel target in the very corner of
/// the window, which is a fiddly thing to ask anyone to click.
const double _wedgeSize = 12;

/// NotesButton opens the notes panel.
class NotesButton extends StatelessWidget {
  final NotesButtonPosition position;

  /// hasNote fills the button in at full strength, so a page that has
  /// something written about it says so without being opened.
  final bool hasNote;
  final VoidCallback onPressed;

  const NotesButton({
    required this.position,
    required this.hasNote,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var color = hasNote ? theme.colors.primary : theme.colors.onSurfaceVariant;

    return Tooltip(
      message: hasNote ? "Notes for this page" : "Add a note for this page",
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: _size,
          height: _size,
          child: position == NotesButtonPosition.threeDots
              ? Center(child: Icon(Icons.more_horiz, size: 18, color: color))
              // Pinned to the same corner the button is in, so the wedge stays
              // against the two window edges while the slack it leaves inside
              // the tap target falls away from them, over the page.
              : Align(
                  alignment: position == NotesButtonPosition.leftTriangle
                      ? Alignment.bottomLeft
                      : Alignment.bottomRight,
                  child: SizedBox(
                    width: _wedgeSize,
                    height: _wedgeSize,
                    child: CustomPaint(
                      painter: _CornerPainter(
                        color: color,
                        // Dimmed rather than outlined when there is nothing
                        // written yet. An outline would draw a line along the
                        // two window edges the wedge sits against, which is
                        // exactly the shape a rendering fault takes.
                        opacity: hasNote ? 1 : 0.45,
                        left: position == NotesButtonPosition.leftTriangle,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// _CornerPainter draws the wedge that fills a bottom corner of the content
/// area.
///
/// A right-angled triangle with its square corner in the window's own corner,
/// so its two short sides lie along the edges that are already there and only
/// the hypotenuse is new. That is what makes it read as a fold in the corner
/// of the page rather than as a triangle icon parked near it -- and it is why
/// it is painted rather than taken from the icon font, where every glyph is an
/// equilateral triangle floating in a square of padding.
class _CornerPainter extends CustomPainter {
  final Color color;
  final double opacity;

  /// left puts the square corner bottom-left; otherwise bottom-right.
  final bool left;

  _CornerPainter({
    required this.color,
    required this.opacity,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    if (left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.opacity != opacity || old.left != left;
}
