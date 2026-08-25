import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/inputs.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

class _FormSubmitButton extends StatelessWidget {
  final FormElement form;
  final FormField submit;
  final GlobalKey<FormState> formKey;
  const _FormSubmitButton(this.form, this.submit, this.formKey);

  void doSubmit(BuildContext context, FormElement form) async {
    var snackbar = SnackBarModel.of(context);
    Map<String, dynamic> formData = {};
    String action = "";
    String asyncTargetID = "";
    for (var field in form.fields) {
      if (field.type == "action") {
        action = field.value ?? "";
      }
      if (field.type == "asynctarget") {
        asyncTargetID = field.value ?? "";
        continue;
      }
      if (field.name == "" || field.value == null) {
        continue;
      }
      formData[field.name] = field.value;
    }

    if (action == "") {
      return;
    }

    var parsed = Uri.parse(action);

    var downSource = Provider.of<DownloadSource?>(context, listen: false);
    var pageSource = Provider.of<PagesSource?>(context, listen: false);
    var uid = downSource?.uid ?? pageSource?.uid ?? "";

    var resources = Provider.of<ResourcesModel>(context, listen: false);
    var sessionID = pageSource?.sessionID ?? 0;
    var parentPageID = pageSource?.pageID ?? 0;

    try {
      await resources.fetchPage(uid, parsed.pathSegments, sessionID,
          parentPageID, formData, asyncTargetID);
    } catch (exception) {
      snackbar.error("Unable to fetch page: $exception");
    }
  }

  /// _role is the button this submit is drawn as, or null for the ordinary
  /// one.
  ///
  /// Named by the page and resolved against the reader's own theme, so a
  /// shop's Place Order button is the same primary button as every other
  /// primary button in the app rather than a colour a page picked.
  ButtonRole? get _role {
    for (var role in ButtonRole.values) {
      if (role.name == submit.style.trim().toLowerCase()) return role;
    }
    return null;
  }

  /// _ask puts the submit's question, and is true if the answer was yes.
  ///
  /// Only where the page asked for one. A form that acts on a tap is right
  /// for most of them -- adding something to a cart, changing a quantity --
  /// and a dialog in front of every one of those is a page nobody can use.
  Future<bool> _ask(BuildContext context) async {
    var question = submit.confirm.trim();
    if (question.isEmpty) return true;

    var answered = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(submit.label),
        content: Text(question),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(submit.label)),
        ],
      ),
    );
    return answered == true;
  }

  @override
  Widget build(BuildContext context) {
    var role = _role;
    var theme = ThemeNotifier.of(context);
    return ElevatedButton(
        style: role == null
            ? null
            // A button the page has picked out is given the room to be
            // picked out in: the same fill the app's own primary and danger
            // buttons have, and a larger tap target than the plain one.
            : theme.buttonStyle(role).copyWith(
                  padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 24, vertical: 8)),
                  minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
                ),
        onPressed: () async {
          if (!formKey.currentState!.validate()) return;
          if (!await _ask(context)) return;
          if (context.mounted) doSubmit(context, form);
        },
        child: Text(submit.label));
  }
}

class FormElementBuilder extends MarkdownElementBuilder {
  FormElementBuilder();

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element is! FormElement) {
      return const Text("not-a-form-element",
          style: TextStyle(color: Colors.amber));
    }

    FormElement form = element;
    return CustomForm(form);
  }
}

class CustomForm extends StatefulWidget {
  final FormElement form;
  const CustomForm(this.form, {super.key});

  @override
  CustomFormState createState() {
    return CustomFormState();
  }
}

class CustomFormState extends State<CustomForm> {
  final _formKey = GlobalKey<FormState>();
  FormElement get form => widget.form;
  @override
  Widget build(BuildContext context) {
    FormField? submit;

    List<Widget> fieldWidgets = [];
    for (var field in form.fields) {
      switch (field.type) {
        case "txtinput":
          TextEditingController ctrl = TextEditingController();
          if (field.value is String) {
            ctrl.text = field.value;
          }
          fieldWidgets.add(TextFormField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: field.hint,
                labelText: field.label,
              ),
              onSaved: (String? value) {
                // This optional block of code can be used to run
                // code when the user saves the form.
              },
              validator: (String? value) {
                if (value != null && field.regexp != "") {
                  return RegExp(field.regexp).hasMatch(value)
                      ? null
                      : field.regexpstr;
                }
                return null;
              },
              onChanged: (String val) {
                field.value = val;
                _formKey.currentState!.validate();
              }));

          break;
        case "intinput":
          IntEditingController ctrl = IntEditingController();
          if (field.value is int) {
            ctrl.intvalue = field.value;
          } else if (field.value is double) {
            ctrl.intvalue = (field.value as double).truncate();
          } else if (field.value is String) {
            ctrl.intvalue = int.tryParse(field.value as String) ?? 0;
          }
          field.value = ctrl.intvalue;
          fieldWidgets.add(TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly
            ],
            decoration: InputDecoration(
              labelText: field.label,
              hintText: field.hint,
            ),
            onChanged: (String val) {
              // A number, not the text of one. This field is built with an
              // int in it and was putting a String back the moment anybody
              // typed, so a form whose number was left alone worked and the
              // same form with the number changed came back "bad request".
              //
              // Adding to a cart hid it: nobody changes the quantity from 1,
              // so the int survived to the wire. Changing a quantity in a
              // cart is nothing but that change, so it failed every time.
              field.value = int.tryParse(val) ?? 0;
            },
            validator: (String? value) {
              if (value != null && field.regexp != "") {
                return RegExp(field.regexp).hasMatch(value)
                    ? null
                    : field.regexpstr;
              }
              return null;
            },
          ));
          break;
        case "submit":
          submit = field;
          break;
        case "asynctarget":
        case "hidden":
        case "action":
          break;
        default:
          debugPrint("Unknown field type ${field.type}");
      }
    }

    // Build a Form widget using the _formKey created above.
    //
    // The button sits where the page put it. A form is often the only thing
    // on a page and belongs on the left; two forms side by side -- update
    // and remove, on one line of a cart -- belong at the end of the row they
    // are in, next to each other rather than at opposite ends.
    var side = switch (form.align) {
      "right" => CrossAxisAlignment.end,
      "center" || "centre" => CrossAxisAlignment.center,
      _ => CrossAxisAlignment.stretch,
    };

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: side,
        children: <Widget>[
          // The fields keep the full width whatever the button does: a text
          // box as wide as its own label is not a text box anybody can type
          // an address into.
          ...fieldWidgets.map(
              (w) => side == CrossAxisAlignment.stretch ? w : _fullWidth(w)),
          const SizedBox(height: 10),
          submit != null
              ? _FormSubmitButton(form, submit, _formKey)
              : const Empty(),
          // Add TextFormFields and ElevatedButton here.
        ],
      ),
    );
  }
}

/// _fullWidth keeps a field the width of the form when the form's own
/// children are no longer stretched to it.
Widget _fullWidth(Widget child) => Row(children: [Expanded(child: child)]);

class FormField {
  final String type;
  final String name;
  final String label;
  dynamic value;
  final String regexp;
  final String regexpstr;
  final String hint;

  /// style is which of the app's buttons a submit is drawn as: the name of
  /// one of the theme's button roles -- primary, danger, tonal, outlined,
  /// plain -- or empty for the ordinary one.
  ///
  /// What a button does is what decides how prominent it should be, and only
  /// the page knows that. Placing an order and emptying a cart are not the
  /// same weight of act as changing a quantity, and before this all three
  /// were the same button in a column.
  final String style;

  /// confirm is what a submit asks before it does anything, or empty for one
  /// that just does it.
  ///
  /// The whole question, so a page asks in its own words -- with the order's
  /// total in it, or the name of the thing being removed -- rather than
  /// through a dialog that can only say "are you sure".
  final String confirm;

  FormField(this.type,
      {this.name = "",
      this.label = "",
      this.regexp = "",
      this.regexpstr = "",
      this.hint = "",
      this.style = "",
      this.confirm = "",
      this.value});
}

class FormElement extends md.Element {
  final List<FormField> fields;

  /// align is which side its button sits on: "left", "center" or "right".
  /// Empty is the left, which is where every form's button was before this.
  final String align;

  FormElement(this.fields, {this.align = ""}) : super("form", [md.Text("")]);
}

class FormBlockSyntax extends md.BlockSyntax {
  static String closeTag = r'--/form--';

  /// tagPattern opens a form, with the form's own settings in brackets the
  /// way --panel[...]-- and --grid[3]-- carry theirs.
  static RegExp tagPattern = RegExp(r'^\s*--form(?:\[([^\]]*)\])?--\s*$');
  static RegExp fieldPattern = RegExp(r'([\w]+)="([^"]*)"');

  /// _setting reads one of the settings in the brackets.
  static final RegExp _setting = RegExp(r'(\w+)\s*=\s*([^,]*)');

  @override
  RegExp get pattern => tagPattern;

  @override
  bool canEndBlock(md.BlockParser parser) =>
      parser.current.content == "--/form--";

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = tagPattern.firstMatch(parser.current.content)?.group(1);
    parser.advance();
    List<FormField> children = [];

    while (!parser.isDone && !md.BlockSyntax.isAtBlockEnd(parser)) {
      if (parser.current.content == closeTag) {
        parser.advance();
        continue;
      }

      var matches = fieldPattern.allMatches(parser.current.content);
      String type = "";
      Map<Symbol, dynamic> args = {};
      for (var m in matches) {
        if (m.groupCount < 2) {
          continue;
        }
        String name = m.group(1)!;
        String value = m.group(2)!;
        switch (name) {
          case "type":
            type = value;
            break;
          case "value":
          case "label":
          case "name":
          case "regexp":
          case "regexpstr":
          case "style":
          case "confirm":
            args[Symbol(name)] = value;
            break;
        }
      }

      FormField field = Function.apply(FormField.new, [type], args);
      children.add(field);
      parser.advance();
    }

    var align = "";
    for (var setting in _setting.allMatches(attributes ?? "")) {
      if (setting.group(1)?.trim().toLowerCase() == "align") {
        align = setting.group(2)?.trim().toLowerCase() ?? "";
      }
    }

    var res = md.Element("p", [FormElement(children, align: align)]);
    return res;
  }
}
