import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_stats.dart is the "Stats" area's own settings (the Payment
// Stats page).
List<Widget> statsAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Redesigned stats page",
        subtitle: "Total sent/received summary cards and redesigned rows "
            "with an avatar and an inline sent-amount bar chart on "
            "the Payment Stats page",
        value: ctx.style.payStatsCardStyle,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(payStatsCardStyle: v)),
      ),
    ];
