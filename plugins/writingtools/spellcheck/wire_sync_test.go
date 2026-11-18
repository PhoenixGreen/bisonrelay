package spellcheck

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"reflect"
	"regexp"
	"strings"
	"testing"
)

// wire_sync_test.go checks that what this plugin sends is what arrives.
//
// The payload passes through three definitions of itself, in three places
// and two languages: the structs here, the client's copy of them, which a
// reply is decoded into and the app's copy encoded from, and the app's own.
// They are kept in step by hand, and a field missing from the middle one is
// not an error anywhere -- it is silently dropped, and whatever it carried
// simply never happens. GrammarRule.Alternatives went missing that way for
// months: written here, expected there, and absent in between.
//
// So the three are read as source and compared. The plugin is its own Go
// module and cannot import the client, which is why this is done on the
// text.

const (
	clientSource = "../../../client/pluginmgr/capabilities/spellcheck.go"
	appSource    = "../../../bruig/flutterui/plugin/lib/definitions.g.dart"
)

// wireTypes maps each type this plugin sends to what the client and the app
// call it.
var wireTypes = map[string]struct{ client, app string }{
	"GrammarRule":   {"GrammarRule", "GrammarRule"},
	"TokenRule":     {"TokenRule", "TokenRule"},
	"AnalysisCheck": {"AnalysisCheck", "AnalysisCheck"},
	"Language":      {"Language", "SpellcheckLanguage"},
	"Grammar":       {"Grammar", "GrammarData"},
	"Data":          {"SpellcheckData", "SpellcheckData"},
}

// sentFields are the JSON names of the fields of struct [name] in [files]
// that are actually sent.
func sentFields(t *testing.T, name string, files ...string) map[string]bool {
	t.Helper()
	fields := map[string]bool{}
	fset := token.NewFileSet()
	for _, path := range files {
		file, err := parser.ParseFile(fset, path, nil, 0)
		if err != nil {
			t.Fatalf("%s: %v", path, err)
		}
		ast.Inspect(file, func(n ast.Node) bool {
			spec, ok := n.(*ast.TypeSpec)
			if !ok || spec.Name.Name != name {
				return true
			}
			st, ok := spec.Type.(*ast.StructType)
			if !ok {
				return true
			}
			for _, f := range st.Fields.List {
				if f.Tag == nil {
					continue
				}
				tag := reflect.StructTag(strings.Trim(f.Tag.Value, "`")).Get("json")
				key := strings.Split(tag, ",")[0]
				if key != "" && key != "-" {
					fields[key] = true
				}
			}
			return false
		})
	}
	return fields
}

func TestEveryFieldSentSurvivesTheClient(t *testing.T) {
	if _, err := os.Stat(clientSource); err != nil {
		t.Skipf("the client's source is not beside this module: %v", err)
	}
	for ours, theirs := range wireTypes {
		sent := sentFields(t, ours, "schema.go", "analysis.go")
		if len(sent) == 0 {
			t.Errorf("%s: found no fields; has it moved?", ours)
			continue
		}
		kept := sentFields(t, theirs.client, clientSource)
		for field := range sent {
			if !kept[field] {
				t.Errorf("%s.%s is sent, and the client's %s has no such field: "+
					"it is dropped before it reaches the app. Add it to %s.",
					ours, field, theirs.client, clientSource)
			}
		}
	}
}

func TestEveryFieldSentIsReadByTheApp(t *testing.T) {
	raw, err := os.ReadFile(appSource)
	if err != nil {
		t.Skipf("the app's source is not beside this module: %v", err)
	}
	source := string(raw)
	for ours, theirs := range wireTypes {
		// The body of the generated decoder for this type.
		start := strings.Index(source, "_$"+theirs.app+"FromJson(")
		if start < 0 {
			t.Errorf("%s: the app has no decoder for %s", ours, theirs.app)
			continue
		}
		end := strings.Index(source[start:], "\n    );\n")
		if end < 0 {
			end = len(source) - start
		}
		body := source[start : start+end]
		read := map[string]bool{}
		for _, m := range regexp.MustCompile(`json\['(\w+)'\]`).FindAllStringSubmatch(body, -1) {
			read[m[1]] = true
		}
		for field := range sentFields(t, ours, "schema.go", "analysis.go") {
			if !read[field] {
				t.Errorf("%s.%s is sent, and the app's %s never reads it. "+
					"Add it to definitions.dart and its generated decoder.",
					ours, field, theirs.app)
			}
		}
	}
}
