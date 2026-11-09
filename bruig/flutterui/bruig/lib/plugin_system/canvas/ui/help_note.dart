import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// help_note.dart is the "?" the play bar, the timeline, the mixer and the
// slots explain themselves with (Ken, 2026-11-08: "I don't want the hover
// tips, if a tip is needed put it in a '?' icon that can be clicked on to
// open and close"). One press opens the note, the next closes it; so does a
// press anywhere else.

/// HelpNote is a small round "?" opening a note: [title] and [paragraphs].
/// Its keys are `help-[id]` for the button and `helpText-[id]` for the note.
class HelpNote extends StatelessWidget {
  final String id;
  final String title;
  final List<String> paragraphs;

  /// size is the button's, across.
  final double size;

  const HelpNote(
      {required this.id,
      required this.title,
      required this.paragraphs,
      this.size = 18,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        Padding(
          key: ValueKey("helpText-$id"),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SizedBox(
            width: 290,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.9,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant)),
                  for (var p in paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(p,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: colors.onSurface)),
                    ),
                ]),
          ),
        ),
      ],
      builder: (context, menu, _) {
        var open = menu.isOpen;
        return Semantics(
          button: true,
          label: "About $title",
          child: InkResponse(
            key: ValueKey("help-$id"),
            radius: size * 0.75,
            onTap: () => open ? menu.close() : menu.open(),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: open ? colors.primary : Colors.transparent,
                border: Border.all(
                    color: open ? colors.primary : colors.outlineVariant),
              ),
              child: Text("?",
                  style: TextStyle(
                      fontSize: size * 0.58,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color:
                          open ? colors.onPrimary : colors.onSurfaceVariant)),
            ),
          ),
        );
      },
    );
  }
}
