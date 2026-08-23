import 'package:bruig/components/feed/markdown_header.dart';
import 'package:bruig/components/feed/markdown_nav.dart';
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
              expect(got.color?.name, option.value);
            case "radius":
              expect(got.radius, double.parse(option.value));
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
      for (var option in navSpec.settings.first.options) {
        var written = navSpec.write({"style": option.value});
        var el = parseBlock(
            written.split("\n").skip(1).join("\n"), NavBlockSyntax());
        expect(el.attributes["style"], option.value, reason: option.value);
        expect(int.parse(el.attributes["count"]!), 3, reason: option.value);
      }
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
      var el = parseBlock(
          written.split("\n").skip(1).join("\n"), HeaderBlockSyntax());
      return el.attributes;
    }

    /// bannerFields are the settings written as lines of the banner --
    /// everything but the row's, whose settings are words in its brackets.
    List<ElementSetting> bannerFields() {
      var rowKeys = {for (var s in headerSpec.rows!.settings) s.key};
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
        var setting =
            headerSpec.allSettings.firstWhere((s) => s.key == key);
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
          headerSpec
              .write({"height": "200", "layout": "center"})
              .split("\n")
              .skip(1)
              .join("\n"),
          HeaderBlockSyntax());
      var rows = headerRowsOf(el.attributes);
      expect(rows, hasLength(1));
      expect(rows.first.height, 200);
      expect(rows.first.mode, HeaderRowMode.center);
    });

    test('flush and group are words, and only when asked for', () {
      var plain = headerRowsOf(parseBlock(
              headerSpec.write(const {}).split("\n").skip(1).join("\n"),
              HeaderBlockSyntax())
          .attributes);
      expect(plain.first.flush, isFalse);
      expect(plain.first.group, isFalse);

      var both = headerRowsOf(parseBlock(
              headerSpec
                  .write({"flush": "flush", "group": "group"})
                  .split("\n")
                  .skip(1)
                  .join("\n"),
              HeaderBlockSyntax())
          .attributes);
      expect(both.first.flush, isTrue);
      expect(both.first.group, isTrue);
    });

    test('every layout is one the row understands', () {
      var setting =
          headerSpec.rows!.settings.firstWhere((s) => s.key == "layout");
      for (var option in setting.options) {
        expect(HeaderRowMode.parse(option.value).name, option.value,
            reason: option.value);
      }
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
        for (var setting in spec.rows?.settings ?? const []) {
          expect(keys, contains(setting.key), reason: setting.key);
        }
      }
    });

    test('the banner still offers all of them', () {
      // Named rather than counted, so grouping cannot quietly drop one.
      expect(
        {for (var s in headerSpec.allSettings) s.key},
        {
          "background", "titlesize",
          "titlecolor", "titlegradient", "titleimage",
          "titleoutline", "titleoutlinecolor",
          "titlebackground", "titlepadding", "titleradius",
          "titleweight", "titleitalic", "titlecase", "titletracking",
          "height", "layout", "flush", "group",
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
      expect(navSpec.settings.first.fallback.value, "plain");
      expect(NavStyle.parse(null), NavStyle.plain);
    });
  });

  group('the note beside a block', () {
    test('is a comment, which the renderer draws as nothing', () {
      for (var spec in pageElementSpecs) {
        var written = spec.write(const {});
        expect(written, startsWith("<!--"), reason: spec.name);
        expect(written, contains("-->"), reason: spec.name);
      }
    });

    test('says how to delete it, because it is for the writer only', () {
      for (var spec in pageElementSpecs) {
        expect(spec.tip.toLowerCase(), contains("delete this note"),
            reason: spec.name);
      }
    });

    test('sits on its own line, so deleting it is one line', () {
      for (var spec in pageElementSpecs) {
        var first = spec.write(const {}).split("\n").first;
        expect(first.trim(), endsWith("-->"), reason: spec.name);
      }
    });
  });

  group('writing a block', () {
    test('leaves out a setting with no answer, rather than writing a blank', () {
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
