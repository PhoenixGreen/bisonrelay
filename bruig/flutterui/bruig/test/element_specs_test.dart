import 'package:bruig/components/feed/markdown_header.dart';
import 'package:bruig/components/feed/markdown_nav.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/components/feed/markdown_title.dart';
import 'package:bruig/components/feed/markdown_page.dart';
import 'package:bruig/components/feed/markdown_panel.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/element_specs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'header_harness.dart';

// element_specs_test.dart holds the panel's description of a block against
// the parser that actually reads one.
//
// The failure worth guarding is quiet: a setting offered that the parser
// does not accept changes nothing when picked, and the writer has no way to
// tell whether they have made a mistake or found a bug. So every option is
// written out and read back by the real parser here.

/// blockOnly drops the note a block may be written with, so what is left is
/// markdown a parser can be handed.
///
/// Only when there is one: a banner goes in without any, and skipping a
/// line regardless took its opening marker instead.
String blockOnly(String written) {
  var lines = written.split("\n");
  return (lines.first.trimLeft().startsWith("<!--") ? lines.skip(1) : lines)
      .join("\n");
}

void main() {
  group('what the panel writes can be read back', () {
    test('every page setting', () {
      for (var setting in pageSpec.allSettings) {
        for (var option in setting.options) {
          var written = pageSpec.write({setting.key: option.value});
          var got = PageSetup.parse(written);
          if (option.value.isEmpty) continue;
          switch (setting.key) {
            case "width":
              expect(got.width, double.parse(option.value),
                  reason: "width=${option.value}");
            case "background":
              expect(got.background.name, option.value,
                  reason: "background=${option.value}");
            case "padding":
              expect(got.padding, EdgeInsets.all(double.parse(option.value)),
                  reason: "padding=${option.value}");
            case "margin":
              expect(got.margin, EdgeInsets.all(double.parse(option.value)),
                  reason: "margin=${option.value}");
          }
        }
      }
    });

    test('every panel setting', () {
      for (var setting in panelSpec.allSettings) {
        for (var option in setting.options) {
          if (option.value.isEmpty) continue;
          var written = panelSpec.write({setting.key: option.value});
          var attrs = RegExp(r'--panel\[([^\]]*)\]--').firstMatch(written);
          expect(attrs, isNotNull, reason: written);
          var got = PanelRule.parse(attrs!.group(1));

          switch (setting.key) {
            case "style":
              expect(got.stroke.name, option.value);
            case "color":
              // A role or a written colour: the spec offers the roles, and
              // what the rule holds for one is the role itself.
              expect(got.color?.role?.name, option.value);
            case "radius":
              expect(got.radius,
                  BorderRadius.circular(double.parse(option.value)));
            case "border":
              expect(got.border, isNotNull, reason: option.value);
            case "padding":
              expect(got.padding, isNotNull, reason: option.value);
            case "margin":
              expect(got.margin, isNotNull, reason: option.value);
          }
        }
      }
    });

    test('every navigation shape, through the block that reads one', () {
      // Through the real block syntax, not just NavStyle.parse: a bar
      // written --nav[style=pills]-- matches nothing and is drawn as the
      // words it is made of, and parsing the value alone would not have
      // noticed. The first version of this spec did exactly that, and left
      // the bar with no closing marker as well.
      var style = navSpec.allSettings.firstWhere((s) => s.key == "style");
      for (var option in style.options) {
        var written = navSpec.write({"style": option.value});
        var el = parseBlock(blockOnly(written), NavBlockSyntax());
        expect(el.attributes["style"], option.value, reason: option.value);
        expect(int.parse(el.attributes["count"]!), 3, reason: option.value);
      }
    });

    test('every setting a bar takes reaches the bar', () {
      // A bar takes only a bare word before this: --nav[pills]--. The
      // settings added beside it have to survive the trip, or they are
      // options that do nothing when picked.
      //
      // Every group, not the first one: walking groups.first covered the
      // placement settings until a Background group was added above them,
      // at which point it covered those instead and said nothing about
      // placement -- without failing.
      for (var setting in navSpec.allSettings) {
        if (setting.key == "style") continue;
        for (var option in setting.options) {
          if (option.value.isEmpty) continue;
          var written = navSpec.write({setting.key: option.value});
          var attrs =
              RegExp(r'--nav\[([^\]]*)\]--').firstMatch(written)?.group(1);
          expect(attrs, isNotNull, reason: written);
          var got = NavWritten.parse(attrs);

          switch (setting.key) {
            case "align":
              expect(got.align?.name, option.value);
            case "width":
              expect(got.fullWidth, option.value == "full");
            case "gap":
              expect(got.gap, double.parse(option.value));
            case "padding":
              expect(got.padding, double.parse(option.value));
            case "margin":
              expect(got.margin, isNotNull, reason: option.value);
            case "radius":
              expect(got.radius, double.parse(option.value));
            case "height":
              expect(got.height, double.parse(option.value));
            case "background":
              // "none" is an answer -- no background -- and not the same as
              // saying nothing, which leaves it to the theme.
              expect(got.background, isNotNull, reason: option.value);
              expect(got.background!.isInherit, option.value == "none",
                  reason: option.value);
          }
        }
      }
    });

    test('a bar background takes a palette role or a colour of your own', () {
      // A bar lives in two places and they want different answers: on a
      // page it belongs to the reader's palette, in a banner it sits over a
      // picture only the writer has seen.
      expect(NavWritten.parse("pills, background=raised").background?.role,
          MarkdownRole.raised);
      expect(
          NavWritten.parse("pills, background=#00000080").background?.literal,
          isNotNull);
      expect(NavWritten.parse("pills, background=none").background?.isInherit,
          isTrue);
      // Not a colour and not a role: left to the theme rather than guessed.
      expect(NavWritten.parse("pills, background=puce").background, isNull);
    });

    test('the style is still the bare word it has always been', () {
      // --nav[pills]-- was the whole syntax. A bar written
      // --nav[style=pills]-- matches nothing and is drawn as its own words.
      var written = navSpec.write({"style": "pills", "align": "left"});
      var attrs = RegExp(r'--nav\[([^\]]*)\]--').firstMatch(written)!.group(1);
      expect(attrs, startsWith("pills"));
      expect(NavWritten.parse(attrs).style, NavStyle.pills);
      expect(NavWritten.parse(attrs).align, NavAlign.left);
    });

    test('a bar that says nothing leaves everything to the theme', () {
      var got = NavWritten.parse("pills");
      expect(got.align, isNull);
      expect(got.gap, isNull);
      expect(got.padding, isNull);
      expect(got.margin, isNull);
      expect(got.fullWidth, isNull);
    });

    test('a setting that will not read is left to the theme, not guessed', () {
      // A bar with a typo in its gap is still a bar.
      var got = NavWritten.parse("pills, gap=enormous, align=sideways");
      expect(got.style, NavStyle.pills);
      expect(got.gap, isNull);
      expect(got.align, isNull);
    });

    test('a navigation bar is written with links in it', () {
      // A bar with no links is markers round nothing, and nothing is drawn.
      var written = navSpec.write(const {});
      expect(written, contains("](index.md)"));
      expect(written, contains("--/nav--"));
    });
  });

  group('every header setting', () {
    // The gap that let two wrong settings ship: titlecolor was offered role
    // names, which it does not take -- it reads hex -- and "titlesize: fill"
    // was offered when it has not been a thing to write since a row became
    // a fixed height. Both would have been picked, done nothing, and left
    // the writer unable to tell a mistake from a bug.
    Map<String, String> fieldsOf(String written) {
      var el = parseBlock(blockOnly(written), HeaderBlockSyntax());
      return el.attributes;
    }

    /// bannerFields are the settings written as lines of the banner --
    /// everything but the row's, whose settings are words in its brackets.
    List<ElementSetting> bannerFields() {
      var rowKeys = {
        for (var s in [for (var r in headerSpec.rows) ...r.settings]) s.key
      };
      return [
        for (var s in headerSpec.allSettings)
          if (!rowKeys.contains(s.key)) s
      ];
    }

    test('reaches the banner, and says what it was told', () {
      for (var setting in bannerFields()) {
        for (var option in setting.options) {
          if (option.value.isEmpty) continue;
          var fields = fieldsOf(headerSpec.write({setting.key: option.value}));
          expect(fields[setting.key], option.value,
              reason: "${setting.key}=${option.value}");
        }
      }
    });

    test('is one the title style actually reads', () {
      // Reaching the banner is not enough: a field it keeps but the style
      // cannot read is a setting that still does nothing.
      for (var setting in bannerFields()) {
        if (!titleStyleFields.contains(setting.key)) continue;
        for (var option in setting.options) {
          if (option.value.isEmpty) continue;
          var style = HeaderTextStyle.parse({setting.key: option.value});
          var plain = HeaderTextStyle.parse(const {});
          expect(style == plain, isFalse,
              reason: "${setting.key}=${option.value} changes nothing");
        }
      }
    });

    test('a colour is read as a colour', () {
      for (var key in [
        "titlecolor",
        "titleoutlinecolor",
        "titlebackground",
      ]) {
        var setting = headerSpec.allSettings.firstWhere((s) => s.key == key);
        for (var option in setting.options) {
          if (option.value.isEmpty) continue;
          var style = HeaderTextStyle.parse({key: option.value});
          var got = switch (key) {
            "titlecolor" => style.color,
            "titleoutlinecolor" => style.outlineColor,
            _ => style.background,
          };
          expect(got, isNotNull, reason: "$key=${option.value}");
        }
      }
    });
  });

  group('a banner row', () {
    test('is written inside the banner, not as a field of it', () {
      // Written as a field it would be a line with a colon in it, which is
      // all the parser would see.
      var written = headerSpec.write(const {});
      expect(written, contains("--row["));
      expect(written, contains("--/row--"));
      expect(written, isNot(contains("height:")));
      expect(written, isNot(contains("layout:")));
    });

    test('carries the height and layout it was given', () {
      var el = parseBlock(
          blockOnly(headerSpec.write({"height1": "200", "layout1": "center"})),
          HeaderBlockSyntax());
      var rows = headerRowsOf(el.attributes);
      expect(rows, hasLength(1));
      expect(rows.first.height, 200);
      expect(rows.first.mode, HeaderRowMode.center);
    });

    test('flush and group are words, and only when asked for', () {
      var plain = headerRowsOf(
          parseBlock(blockOnly(headerSpec.write(const {})), HeaderBlockSyntax())
              .attributes);
      expect(plain.first.flush, isFalse);
      expect(plain.first.group, isFalse);

      var both = headerRowsOf(parseBlock(
              blockOnly(
                  headerSpec.write({"flush1": "flush", "group1": "group"})),
              HeaderBlockSyntax())
          .attributes);
      expect(both.first.flush, isTrue);
      expect(both.first.group, isTrue);
    });

    test('every layout is one the row understands', () {
      var setting =
          headerSpec.allSettings.firstWhere((s) => s.key == "layout1");
      for (var option in setting.options) {
        expect(HeaderRowMode.parse(option.value).name, option.value,
            reason: option.value);
      }
    });

    test('a second row is left out unless it was asked for', () {
      // An empty second row is a fixed height of nothing, which reads as a
      // gap the writer cannot account for.
      expect("--row[".allMatches(headerSpec.write(const {})).length, 1);
    });

    test('and is written when it was', () {
      var written = headerSpec.write({"height2": "44", "flush2": "flush"});
      expect("--row[".allMatches(written).length, 2);
      expect(written, contains("44"));
      expect(written, contains("flush"));
    });

    test('a banner never writes more rows than one may have', () {
      // At most two, which the parser enforces by ignoring the rest -- so a
      // third would be written, sent, and silently not drawn.
      var written = headerSpec.write({
        for (var r in headerSpec.rows)
          for (var s in r.settings) s.key: s.options.last.value
      });
      expect("--row[".allMatches(written).length,
          lessThanOrEqualTo(maxHeaderRows));
    });

    test('each row goes in with something in it', () {
      // A row's cells are the one part the panel cannot choose for anybody,
      // so it puts an example there rather than an empty row -- which is a
      // fixed height of nothing.
      var written = headerSpec.write({"height2": "44"});
      expect(written, contains("left:"));
      expect(written, contains("--include["));
    });

    test('the row has cells in it', () {
      // A row with nothing in it is a fixed height of nothing.
      expect(headerSpec.write(const {}), contains("left:"));
    });
  });

  group('a setting is defined once', () {
    // allSettings is what the tests above walk and what write() uses, so a
    // setting that fell out of it would stop being checked and stop being
    // written, quietly and together. Grouping the banner's settings moved
    // eleven of them out of spec.settings, and every test that walked that
    // list went from covering thirteen to covering two without failing.
    test('and appears in allSettings whichever way it is listed', () {
      for (var spec in pageElementSpecs) {
        var keys = [for (var s in spec.allSettings) s.key];
        expect(keys.toSet().length, keys.length,
            reason: "${spec.name} defines a setting twice");

        for (var group in spec.groups) {
          for (var setting in group.settings) {
            expect(keys, contains(setting.key),
                reason: "${spec.name}: ${setting.key} is grouped but lost");
          }
        }
        for (var r in spec.rows) {
          for (var setting in r.settings) {
            expect(keys, contains(setting.key), reason: setting.key);
          }
        }
      }
    });

    test('the banner still offers all of them', () {
      // Named rather than counted, so grouping cannot quietly drop one.
      expect(
        {for (var s in headerSpec.allSettings) s.key},
        {
          "background",
          "titlesize",
          "titlecolor",
          "titlegradient",
          "titleimage",
          "titleoutline",
          "titleoutlinecolor",
          "titlebackground",
          "titlepadding",
          "titleradius",
          "titleweight",
          "titleitalic",
          "titlecase",
          "titletracking",
          "height1",
          "layout1",
          "flush1",
          "group1",
          "height2",
          "layout2",
          "flush2",
          "group2",
        },
      );
    });

    test('an exclusive group holds alternatives, not additions', () {
      // A title is filled with a colour, or a gradient, or a picture. The
      // panel clears the others when one is picked, so a banner never
      // carries two answers to one question.
      var fill = headerSpec.groups.firstWhere((g) => g.exclusive);
      expect({for (var s in fill.settings) s.key},
          {"titlecolor", "titlegradient", "titleimage"});
    });
  });

  group('what a block says when told nothing', () {
    test('is what the panel shows as active', () {
      // The panel opens describing what the writer would get, so the option
      // it marks active has to be the one the parser falls back to.
      var written = pageSpec.write(const {});
      var got = PageSetup.parse(written);
      expect(got.padding, const EdgeInsets.all(16));
      expect(got.margin, const EdgeInsets.all(16));
    });

    test('a navigation bar with nothing picked is still plain', () {
      expect(
          navSpec.allSettings
              .firstWhere((s) => s.key == "style")
              .fallback
              .value,
          "plain");
      expect(NavStyle.parse(null), NavStyle.plain);
    });
  });

  group('how a banner is laid out', () {
    // A banner is fifteen lines. Written as one run they are a wall, and
    // the rows -- the part anybody scrolling is looking for -- are lost in
    // the middle of it.
    List<String> banner() => headerSpec.write({
          "background": "![](assets/banner.jpg)",
          "height2": "44",
        }).split("\n");

    test('the settings and each row are separated by a blank line', () {
      var lines = banner();
      expect(lines.first, "--header--");
      expect(lines[1], isEmpty, reason: "a blank after the opening marker");
      expect(lines.last, "--/header--");
      expect(lines[lines.length - 2], isEmpty,
          reason: "a blank before the closing marker");

      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith("--row[")) {
          expect(lines[i - 1], isEmpty, reason: "a blank before each row");
        }
      }
    });

    test('nothing is indented', () {
      // A cell's contents are markdown, and markdown reads four spaces as
      // a code block.
      for (var line in banner()) {
        expect(line, equals(line.trimLeft()), reason: line);
      }
    });

    test('a block with only settings gets no blank lines', () {
      // There is nothing to separate it from, and a page block spaced out
      // like a banner would be four lines of air round two settings.
      var lines = pageSpec.write(const {}).split("\n");
      expect(lines.where((l) => l.isEmpty), isEmpty);
    });

    test('the banner goes in without notes in it', () {
      // Three notes -- one for the block and one in each row -- were more
      // of what was on screen than the settings were. A note earns its
      // place on a short block; on a long one it is the thing you delete
      // before you can read what you wrote.
      var written = headerSpec.write({"height2": "44"});
      expect(written, isNot(contains("<!--")));
      expect(headerSpec.tip, isEmpty);
    });

    test('the panel still says what a banner is', () {
      // The explanation costs the document nothing when it stays in the
      // panel, so dropping the note does not mean dropping the help.
      expect(headerSpec.about, isNotEmpty);
      expect(headerSpec.about.toLowerCase(), contains("banner"));
    });
  });

  group('the note beside a block', () {
    test('is a comment, which the renderer draws as nothing', () {
      for (var spec in pageElementSpecs) {
        if (spec.tip.isEmpty) continue;
        var written = spec.write(const {});
        expect(written, startsWith("<!--"), reason: spec.name);
        expect(written, contains("-->"), reason: spec.name);
      }
    });

    test('says how to delete it, because it is for the writer only', () {
      for (var spec in pageElementSpecs) {
        if (spec.tip.isEmpty) continue;
        expect(spec.tip.toLowerCase(), contains("delete this note"),
            reason: spec.name);
      }
    });

    test('sits on its own line, so deleting it is one line', () {
      for (var spec in pageElementSpecs) {
        if (spec.tip.isEmpty) continue;
        var first = spec.write(const {}).split("\n").first;
        expect(first.trim(), endsWith("-->"), reason: spec.name);
      }
    });
  });

  group('every block explains itself', () {
    test('in the panel, whether or not it leaves a note behind', () {
      for (var spec in pageElementSpecs) {
        expect(spec.about, isNotEmpty, reason: spec.name);
      }
    });
  });

  group('writing a block', () {
    test('leaves out a setting with no answer, rather than writing a blank',
        () {
      // "background:" with no answer is a line the parser reads and
      // discards, and a writer looking at it cannot tell it does nothing.
      var written = pageSpec.write({"background": "", "width": ""});
      expect(written, isNot(contains("background:")));
      expect(written, isNot(contains("width:")));
    });

    test('closes what it opens', () {
      for (var spec in pageElementSpecs) {
        var written = spec.write(const {});
        if (spec.shape == ElementShape.single) {
          expect(written, isNot(contains("--/${spec.tag}--")));
        } else {
          expect(written, contains("--/${spec.tag}--"), reason: spec.name);
        }
      }
    });

    test('a fragment names one, because an empty include finds nothing', () {
      expect(fragmentSpec.write(const {}), contains("--include[header]--"));
    });
  });
}
