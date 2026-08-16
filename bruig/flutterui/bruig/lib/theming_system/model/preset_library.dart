import 'dart:convert';

import 'package:bruig/theming_system/model/preset.dart';

// preset_library.dart holds the whole themes that ship with the app.
//
// A built-in preset is an ordinary ThemePreset that nobody has to build: it
// appears in the theme picker beside the ones the reader has saved, cannot
// be deleted, and is never written to disk. Editing one forks it into a
// theme of the reader's own (see ensureDraftPreset), the same way editing a
// built-in style guide does, so the shipped one always means the same thing
// on every device -- which is the entire point of shipping it.
//
// Stored as JSON rather than as a Dart literal, which is the opposite of how
// the palettes and style guides ship. A palette is fifteen colours and a
// guide is a page of typography, both worth reading in the source; a whole
// preset is a palette *plus* a style entry for each of fourteen theme areas,
// and written out as a constructor it would be several hundred lines of
// field names in which nothing could be found and a typo could not be seen.
// It is exported from the editor and pasted in, and a test parses it to
// prove it still loads.

/// _ulyssesJson is the "Ulysses" theme as exported from the editor.
///
/// Its Markdown area names the built-in "ulysses" style guide rather than
/// carrying a copy of it -- see markdown_guides.dart.
const _ulyssesJson = r'''
{"id":"ulysses","name":"Ulysses","brightness":"dark","paletteVersion":9,"palette":{"primary":"#ff1e1e1e","headerBackground":"#ff1e1e1e","dualBackground":"#ff1e1e1e","contentBackground":"#ff1e1e1e","tertiary":"#ff262626","secondary":"#ff161616","navSelected":"#ff0a84ff","sidebarBackground":"#ff1a1a1a","fourth":"#ff4a4a4a","speechBackground":"#ff262626","speechBackgroundSent":"#ff161616","outline":"#ff2b2b2b","onSurface":"#ffe5e1e9","onSurfaceVariant":"#ff8c8c94","navText":"#ff8c8c94","sidebarText":"#ff8c8c94","accentContainer":"#ff17456f","buttonBackgroundSecondary":"#ff93000a","buttonBackgroundThird":"#ff3f3f3f","buttonBorderColor":"#ff7a7a7a","buttonHover":"#1fc08a5b","buttonText1":"#ffc08a5b","buttonText2":"#ffe4dfff","navAccent":"#ff0a84ff","inputResting":"#ff3b2f26","inputSelected":"#ffc08a5b","inputBackground":"#00000000","sidebarAccent":"#ffc08a5b","error":"#ffff6b6b","success":"#ff5bc46b"},"areas":{"chat":{"collapseComposerIcons":true,"enableMessageActions":true,"showChatListLastMessage":true,"chatListDesignEnabled":true,"chatListCornerRadius":0.0,"chatListBackgroundColor":"#ff161616","chatListBackgroundColorIndex":5,"chatListGlowIntensity":0.1,"chatListTopHighlight":false,"enableChatSearch":true,"chatSidebarFooter":false,"formattingToolbar":true,"composerPolish":true,"bubbleCorners":true,"bubbleCornerStyle":"speech","avatarTheme":"monochrome","expandMessageWidth":true,"expandMessagePadding":5.0},"navBar":{"borderMode":"solid","borderColor":"#ff262626","borderColorIndex":11,"borderWidth":2.0,"borderRadius":20.0,"logoSize":50.0,"navRoutes":["/chat","/feed","/dynplugin/rss","/ln","/pages","/manageContent","/settings"],"showLogo":true,"showDcrPrice":true,"showBtcPrice":true,"priceIconSize":32.0,"dcrPricePadding":10.0,"dcrPricePaddingSides":[10.0,0.0,0.0,10.0],"btcPricePadding":10.0,"btcPricePaddingSides":[10.0,0.0,0.0,24.0],"logoAlign":"start"},"masterBackground":{"margin":5.0},"header":{"hideHeaderTitle":true,"hideHeaderNewPost":true,"headerPosition":"none"},"loginScreen":{"mode":"solid","solidColor":"#ff1e1e1e","solidColorIndex":0},"subMenuTabBar":{"paddingSides":[0.0,10.0,0.0,0.0],"marginSides":[0.0,10.0,0.0,10.0],"subMenuStyle":"resizable","sidebarCornerRadius":5.0,"sidebarShowIcons":true},"contentArea":{"margin":10.0,"marginSides":[2.0,10.0,2.0,10.0]},"dualPanel":{"margin":2.0},"feed":{"feedImageLayout":"cropped","feedTextOrder":"textLast","feedLinksMode":"offIfImage","feedTextLimit":300.0,"feedStripMarkdown":true},"markdown":{"markdownGuideId":"ulysses"},"realtimeChat":{"autoUnmuteOnJoin":true},"manageContent":{"hideFilePaths":true},"settingsPages":{"payStatsCardStyle":true,"accountCardLayout":true},"inputAreas":{"inputBorderRadius":15.0}},"menuLabels":{"/chat":"Chat","/addressBook":"Address Book","/feed":"Posts","/dynplugin/rss":"RSS","/realtimechat":"Live Chat","/ln":"Wallet","/pages":"Pages","/manageContent":"Files","/settings":"Settings"},"menuOrder":["/chat","/addressBook","/feed","/dynplugin/rss","/realtimechat","/ln","/pages","/manageContent","/settings"]}
''';

/// builtinPresets are the whole themes that ship with the app.
///
/// Parsed once, on first use. A malformed entry would be a bug in this file
/// rather than in anything a user did, so it is left to throw rather than
/// being quietly skipped -- the test that loads them is what catches it.
final List<ThemePreset> builtinPresets = [
  ThemePreset.fromJson(jsonDecode(_ulyssesJson) as Map<String, dynamic>),
];

/// isBuiltinPresetId reports whether [id] is one of them.
bool isBuiltinPresetId(String id) => builtinPresets.any((p) => p.id == id);
