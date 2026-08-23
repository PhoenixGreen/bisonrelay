import 'dart:convert';

import 'package:bruig/components/pages/forms.dart' as pf;
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// page_form_number_test.dart covers what a number field puts on the wire.
//
// A quantity is read on the other side as a number. This field is built with
// an int in it and was putting the *text* of one back the moment anybody
// typed, so a form whose number was left alone worked and the same form with
// the number changed came back "bad request".
//
// Adding to a cart hid it for a long time: nobody changes the quantity from
// 1, so the int survived to the wire. Changing a quantity in a cart is
// nothing but that change, so it failed every time.

void main() {
  Future<void> pump(WidgetTester tester, pf.FormElement form) async {
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ], child: MaterialApp(home: Scaffold(body: pf.CustomForm(form)))));
    await tester.pumpAndSettle();
  }

  pf.FormElement quantityForm() => pf.FormElement([
        pf.FormField("action", value: "/setCartQty"),
        pf.FormField("hidden", name: "sku", value: "r1"),
        pf.FormField("intinput", name: "qty", label: "Quantity", value: "2"),
        pf.FormField("submit", label: "Update"),
      ]);

  testWidgets('a number left alone goes as a number', (tester) async {
    var form = quantityForm();
    await pump(tester, form);
    var qty = form.fields.firstWhere((f) => f.name == "qty");
    expect(qty.value, isA<int>());
    expect(qty.value, 2);
  });

  testWidgets('a number that is typed goes as a number too', (tester) async {
    // The case that failed. Everything about the form is the same except
    // that somebody used it.
    var form = quantityForm();
    await pump(tester, form);

    await tester.enterText(find.byType(TextFormField), "5");
    await tester.pumpAndSettle();

    var qty = form.fields.firstWhere((f) => f.name == "qty");
    expect(qty.value, isA<int>(),
        reason: "typed a quantity and it went as text");
    expect(qty.value, 5);
  });

  testWidgets('what is sent can be read as the other side reads it',
      (tester) async {
    // The real check: the other side unmarshals qty into a uint32, and a
    // JSON string is not one. Asserting the type alone would not have
    // caught a value that is an int but encodes oddly.
    var form = quantityForm();
    await pump(tester, form);
    await tester.enterText(find.byType(TextFormField), "3");
    await tester.pumpAndSettle();

    var data = {
      for (var f in form.fields)
        if (f.name.isNotEmpty && f.value != null) f.name: f.value
    };
    expect(jsonEncode(data), contains('"qty":3'));
    expect(jsonEncode(data), isNot(contains('"qty":"3"')));
  });

  testWidgets('an emptied box is nought, not nothing', (tester) async {
    // Clearing the box and submitting means "I do not want this", which the
    // cart reads as removing the line. It must not arrive as "" and be
    // refused as unreadable.
    var form = quantityForm();
    await pump(tester, form);
    await tester.enterText(find.byType(TextFormField), "");
    await tester.pumpAndSettle();

    var qty = form.fields.firstWhere((f) => f.name == "qty");
    expect(qty.value, 0);
  });
}
