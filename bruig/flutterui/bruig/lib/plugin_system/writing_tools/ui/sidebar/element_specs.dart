import 'package:flutter/material.dart';

// element_specs.dart is what the Pages and store panel knows about the
// blocks it writes: what each one is for, what it can be told, and what it
// does when told nothing.
//
// Declared rather than described in prose, because the panel has three jobs
// for the same knowledge -- list the settings, show what each one accepts,
// and write the block -- and three prose copies of it would be three copies
// to keep in step with the parsers.
//
// Every value here is one the matching parser actually accepts. A panel
// offering a setting that does nothing is worse than a panel not offering
// it: the writer picks it, sees no change, and has no way to tell whether
// they have made a mistake or found a bug.

export 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/element_model.dart';
export 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/fragment_spec.dart';
export 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/header_spec.dart';
export 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/nav_spec.dart';
export 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/page_spec.dart';
export 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/panel_spec.dart';

import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/element_model.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/fragment_spec.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/header_spec.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/nav_spec.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/page_spec.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/specs/panel_spec.dart';

/// pageElementSpecs are the blocks the Pages and store panel explains, in
/// the order it lists them: the page itself, then what goes on it.
const List<ElementSpec> pageElementSpecs = [
  pageSpec,
  headerSpec,
  navSpec,
  panelSpec,
  fragmentSpec,
];
