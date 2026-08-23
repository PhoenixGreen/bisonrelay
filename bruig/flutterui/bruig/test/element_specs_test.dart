import 'package:bruig/components/feed/markdown_nav.dart';
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
      for (var setting in pageSpec.settings) {
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
      for (var setting in panelSpec.settings) {
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
