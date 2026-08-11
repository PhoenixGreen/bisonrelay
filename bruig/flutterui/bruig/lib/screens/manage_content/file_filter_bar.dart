import 'package:bruig/components/inputs.dart';
import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';

// FileFilterBar is the search box, sort picker and count that sit above a
// list of files. Shared by the Manage pages so the two lists are worked
// the same way -- the sort options differ (a download has a sender, a
// share has recipients), but nothing else about it should.
class FileFilterBar<T> extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onSearch;
  final T sort;
  final Map<T, String> sortLabels;
  final ValueChanged<T> onSort;
  // summary is the line under the controls: how many files are listed and
  // how much they come to.
  final String summary;
  const FileFilterBar({
    required this.hintText,
    required this.onSearch,
    required this.sort,
    required this.sortLabels,
    required this.onSort,
    required this.summary,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              style: kInputTextStyle,
              decoration: themedInputDecoration(
                context,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: hintText,
                fallbackBorder: const OutlineInputBorder(),
              ),
              onChanged: onSearch,
            ),
          ),
          const SizedBox(width: 12),
          const Txt.S("Sort:"),
          const SizedBox(width: 6),
          DropdownButton<T>(
            value: sort,
            items: sortLabels.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Txt.S(e.value)))
                .toList(),
            onChanged: (s) {
              if (s != null) onSort(s);
            },
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(summary,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ),
    ]);
  }
}

// fileCountSummary is the "12 files - 340 MB" line both lists show.
String fileCountSummary(int count, String size) =>
    count == 1 ? "1 file - $size" : "$count files - $size";
