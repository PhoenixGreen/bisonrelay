import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/pages/forms.dart' as pages;
import 'package:bruig/components/tooltips.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// form_help_test.dart covers the question mark a form field can carry.
//
// "A phone number is only for whoever delivers this" is worth knowing once and
// read every time by everybody who already knows it -- and as a line of prose
// above the boxes it is read before anybody knows which box it is about.

Widget _host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (c) => MarkdownAreaModel("/tmp")),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 600, child: child)),
        ),
      ),
    );

const _form = """
--form--
type="action" value="/setCheckout"
type="txtinput" label="Postal code" name="postalCode"
type="txtinput" label="Phone (optional)" name="phone" help="A phone number is only for whoever delivers this."
type="submit" label="Continue"
--/form--
""";

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("keeps the words behind a mark on the box they are about",
      (tester) async {
    await tester.pumpWidget(_host(MarkdownArea(_form, false)));
    await tester.pump();

    expect(find.text("Phone (optional)"), findsOneWidget);
    expect(find.textContaining("only for whoever delivers"), findsNothing);

    var tips = tester.widgetList<HelpTooltip>(find.byType(HelpTooltip));
    expect(tips.length, 1,
        reason: "only the field that asked for one gets a mark");
    expect(tips.first.message,
        "A phone number is only for whoever delivers this.");
    expect(tips.first.triggerMode, TooltipTriggerMode.tap);
  });

  // Inside the field's own outline, so it is plainly about that field and not
  // the one below it.
  testWidgets("puts it at the end of that field's box", (tester) async {
    await tester.pumpWidget(_host(MarkdownArea(_form, false)));
    await tester.pump();

    var phone = tester.getRect(find.ancestor(
        of: find.text("Phone (optional)"),
        matching: find.byType(TextFormField)));
    var mark = tester.getRect(find.byIcon(Icons.help_outline));

    expect(mark.center.dy, greaterThan(phone.top));
    expect(mark.center.dy, lessThan(phone.bottom));
    expect(phone.right - mark.right, lessThan(24));
  });

  test("a field with nothing to explain carries no mark", () {
    expect(pages.FormField("txtinput", name: "city").help, "");
  });
}
