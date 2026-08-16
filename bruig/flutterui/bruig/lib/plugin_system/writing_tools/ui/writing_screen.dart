import 'package:bruig/components/chat/chat_side_menu.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/writing_tools/composer_sidebar.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_sidebar.dart';
import 'package:bruig/plugin_system/writing_tools/ui/composer.dart';
import 'package:bruig/plugin_system/writing_tools/ui/composer_sidebar_shell.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/formatting_sidebar.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/writing_sidebar.dart';
import 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// writing_screen.dart is the Writing section: a page for writing a post,
// with the writing tools beside it.
//
// It exists only while the Writing Tools plugin is enabled -- see
// writing_nav.dart, which puts it in and takes it out of the navigation. The
// Feed is unaffected either way and keeps its own plain composer, so nothing
// here is on the path of somebody who has never enabled the plugin.
//
// This used to be the Feed's fourth tab, and the sidebar it needed had to be
// borrowed from the Feed's own for as long as a composer was on screen. That
// arrangement is what most of the composer sidebar's history is about: which
// panel had the slot, what happened when the composer was torn down, and how
// to get back to the Feed's menu from inside it. A page of its own has none
// of those questions -- the slot is its own, and the way out is the
// navigation, like every other page.

/// WritingScreenTitle is the page heading, which follows the menu: renaming
/// the destination in Settings > Appearance > Menu renames the heading too.
class WritingScreenTitle extends StatelessWidget {
  const WritingScreenTitle({super.key});

  @override
  Widget build(BuildContext context) => Consumer<MainMenuModel>(
      builder: (context, menu, child) =>
          Txt.L(menu.headerLabel(WritingScreen.routeName) ?? "Writing"));
}

class WritingScreen extends StatefulWidget {
  static const routeName = '/writing';

  const WritingScreen({super.key});

  @override
  State<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends State<WritingScreen> {
  /// _writingPage is which of the writing tools' pages is showing.
  ///
  /// Held here rather than inside the sidebar, because in the collapsed
  /// drawer that widget is rebuilt from a stored builder and would forget it
  /// -- and because the drawer only redraws for things this screen tells it
  /// changed, which it can only do for state it holds.
  ///
  /// It mirrors the one on WritingPreferences, which outlives this screen.
  /// Kept as a field as well so the build path reads a plain value.
  WritingSidebarPage _writingPage = WritingSidebarPage.mistakes;

  @override
  void initState() {
    super.initState();
    var prefs = Provider.of<WritingPreferences>(context, listen: false);
    var at = prefs.sidebarPage;
    _writingPage = at >= 0 && at < WritingSidebarPage.values.length
        ? WritingSidebarPage.values[at]
        : WritingSidebarPage.mistakes;
  }

  @override
  Widget build(BuildContext context) {
    var client = Provider.of<ClientModel>(context);
    var composer = context.watch<ComposerSidebarController>();

    var content = Consumer<FeedModel>(
        builder: (context, feed, child) => WritingComposer(feed));

    // Hiding the sidebar means nothing beside the editor. Not routed through
    // SecondarySideMenuLayout at all, since that would put its own sidebar
    // back where the panel had been -- which made the hide button look like
    // it had merely closed the panel it was on.
    if (!composer.visible) {
      return ScreenWithChatSideMenu(
          client, contentAreaFrame(ThemeNotifier.of(context), content));
    }

    var sidebar = ComposerSidebarShell(
      controller: composer,
      // In ComposerPanel's own order, so the row cannot drift from the enum
      // it is built out of.
      panels: ComposerPanel.values,
      child: switch (composer.panel) {
        ComposerPanel.writing => WritingSidebar(
            controller: composer.editor,
            page: _writingPage,
            onPageChanged: (page) => setState(() {
                  _writingPage = page;
                  Provider.of<WritingPreferences>(context, listen: false)
                      .sidebarPage = page.index;
                })),
        ComposerPanel.posts => PostSidebar(controller: composer.editor),
        ComposerPanel.formatting => FormattingSidebar(controller: composer),
      },
    );

    return ScreenWithChatSideMenu(
        client,
        SecondarySideMenuLayout(
          storageKey: "writing",
          list: sidebar,
          // The sidebar changes while it is open and the collapsed drawer
          // has no other way to know: its icons registered their taps and
          // redrew nothing. The panel alone was not enough -- switching
          // pages within the writing tools changes it just as much.
          sidebarRevision: (composer.panel, _writingPage),
          content: content,
        ));
  }
}
