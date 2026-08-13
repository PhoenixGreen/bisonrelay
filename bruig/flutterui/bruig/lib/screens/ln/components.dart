import 'package:flutter/material.dart';

/// lnSectionGap is the space between an LN section's heading and the first
/// thing under it.
///
/// Overview's figure, applied to every page. Each page used to space its own
/// headings -- 21 here, 10 there, 8 on three others, and nothing at all
/// above the account list -- so moving between LN pages the headings sat at
/// a different height each time and Accounts read as though its title
/// belonged to the first row.
const double lnSectionGap = 21;

class LNInfoSectionHeader extends StatelessWidget {
  final String title;

  const LNInfoSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    // The gap belongs to the heading rather than to each caller, so a new
    // section can't be added without it and the pages can't drift apart
    // again.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text(title),
          const SizedBox(width: 8),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: lnSectionGap),
      ],
    );
  }
}
