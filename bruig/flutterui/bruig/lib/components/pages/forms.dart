import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/inputs.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/components/tooltips.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

/// postToPage sends [formData] to the shop's [action] and shows whatever it
/// answers with, exactly as submitting a form on the page does.
///
/// Pulled out of the submit button because a form is not the only shape an
/// action takes. A payment card the buyer presses to choose it, or a button
/// that pays an order, is one field and one press -- wrapping either in a
/// form to reach this would be putting a form on the page to hide it again.
///
/// Everything a page can act on goes through here, so the rules about where
/// a press may lead are in one place: the action is a path on the site that
/// served the page, and this is what resolves it against that site.
Future<void> postToPage(
  BuildContext context,
  String action,
  Map<String, dynamic> formData, {
  String asyncTargetID = "",
}) async {
  if (action == "") return;
  var snackbar = SnackBarModel.of(context);

  var parsed = Uri.parse(action);

  var downSource = Provider.of<DownloadSource?>(context, listen: false);
  var pageSource = Provider.of<PagesSource?>(context, listen: false);
  var uid = downSource?.uid ?? pageSource?.uid ?? "";

  var resources = Provider.of<ResourcesModel>(context, listen: false);
  var sessionID = pageSource?.sessionID ?? 0;
  var parentPageID = pageSource?.pageID ?? 0;

  try {
    await resources.fetchPage(
        uid, parsed.pathSegments, sessionID, parentPageID, formData, asyncTargetID);
  } catch (exception) {
    snackbar.error("Unable to fetch page: $exception");
  }
}

class _FormSubmitButton extends StatelessWidget {
  final FormElement form;
  final FormField submit;
  final GlobalKey<FormState> formKey;
  const _FormSubmitButton(this.form, this.submit, this.formKey);

  void doSubmit(BuildContext context, FormElement form) async {
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

    await postToPage(context, action, formData, asyncTargetID: asyncTargetID);
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
                // At the end of the box, which is where a question mark
                // about a box belongs: the same corner the app's own help
                // icons sit in, and inside the field's own outline so it is
                // plainly about that field and not the one below it.
                suffixIcon: field.help.isEmpty
                    ? null
                    : HelpTooltip(
                        message: field.help,
                        triggerMode: TooltipTriggerMode.tap,
                        showDuration: const Duration(seconds: 8),
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Icon(Icons.help_outline,
                            size: 18,
                            color: ThemeNotifier.of(context)
                                .colors
                                .onSurfaceVariant),
                      ),
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
        case "select":
          // One of a few answers, chosen rather than typed. The first is
          // what the page gets unless somebody picks another, so a select
          // always has a value -- a form whose field is null until it is
          // touched is a form that behaves differently for somebody who
          // agreed with the default.
          var choices = field.choices;
          if (choices.isEmpty) break;
          field.value ??= choices.first.value;
          if (!choices.any((c) => c.value == field.value)) {
            field.value = choices.first.value;
          }
          fieldWidgets.add(StatefulBuilder(
            builder: (context, setInner) => DropdownButtonFormField<String>(
              initialValue: field.value as String,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: field.label,
                hintText: field.hint,
              ),
              items: [
                for (var choice in choices)
                  DropdownMenuItem(
                      value: choice.value,
                      child:
                          Text(choice.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setInner(() => field.value = v);
              },
            ),
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

  /// options is what a select offers: value|Label, separated by commas.
  ///
  ///     type="select" name="method" options="ln|Lightning, onchain|On-chain"
  ///
  /// The label is what the reader chooses between and the value is what the
  /// page receives, because those are rarely the same thing: a shop asking
  /// how somebody wants to pay wants "ln" and the buyer is choosing
  /// "Lightning".
  final String options;

  /// help is a sentence kept behind a question mark at the end of a box, or
  /// empty for a field that needs none.
  ///
  /// "A phone number is only for whoever delivers this" is worth knowing once
  /// and read every time by everybody who already knows it -- and as a line
  /// of prose above the boxes it is read before anybody knows which box it is
  /// about. Beside the box, it is answering a question somebody is having.
  ///
  /// It follows Hide help text under Appearance, like the app's own.
  final String help;

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
      this.help = "",
      this.options = "",
      this.value});

  /// choices are what a select offers, in the order they were written.
  List<({String value, String label})> get choices {
    var out = <({String value, String label})>[];
    for (var part in options.split(",")) {
      var text = part.trim();
      if (text.isEmpty) continue;
      var at = text.indexOf("|");
      out.add(at == -1
          ? (value: text, label: text)
          : (
              value: text.substring(0, at).trim(),
              label: text.substring(at + 1).trim()
            ));
    }
    return out;
  }
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
          case "help":
          case "options":
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
