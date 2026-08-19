package spellcheck

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// rules_wired_test.go answers the one question the compiler cannot: is every
// group of rules in this package actually shipped?
//
// Rules is assembled by hand in rules.go, which is deliberate -- the order
// matters and ought to be reviewable -- but it means a new rules_*.go file
// compiles, tests, and reaches nobody. Every other test in this package runs
// over Rules, so a group left out of it is not merely unshipped: it is
// unchecked as well, and both failures are completely silent.
//
// So this reads the package's own source, finds every package-level
// `[]GrammarRule` variable, and insists rules.go names it.

// notInRules are the variables that are deliberately not in the shipped list,
// with the reason. Anything else has to be wired up or added here on purpose.
var notInRules = map[string]string{
	"Rules": "the list itself",
}

func TestEveryRuleGroupIsWired(t *testing.T) {
	fset := token.NewFileSet()
	pkgs, err := parser.ParseDir(fset, ".", func(fi os.FileInfo) bool {
		return !strings.HasSuffix(fi.Name(), "_test.go")
	}, 0)
	if err != nil {
		t.Fatalf("parsing the package: %v", err)
	}
	pkg, ok := pkgs["spellcheck"]
	if !ok {
		t.Fatal("package spellcheck not found in .")
	}

	// The right-hand side of `var Rules = concat(...)`, as source text. Read
	// as text rather than walked as a call, because a group may reach the list
	// through a helper one day and the question here is only "is the name
	// mentioned".
	wired, err := os.ReadFile(filepath.Join(".", "rules.go"))
	if err != nil {
		t.Fatalf("reading rules.go: %v", err)
	}

	found := 0
	for name, file := range pkg.Files {
		if filepath.Base(name) == "rules.go" {
			continue
		}
		for _, decl := range file.Decls {
			gen, ok := decl.(*ast.GenDecl)
			if !ok || gen.Tok != token.VAR {
				continue
			}
			for _, spec := range gen.Specs {
				value, ok := spec.(*ast.ValueSpec)
				if !ok || !isRuleSlice(value) {
					continue
				}
				for _, ident := range value.Names {
					if _, skip := notInRules[ident.Name]; skip {
						continue
					}
					found++
					if !mentions(string(wired), ident.Name) {
						t.Errorf("%s is declared in %s but rules.go never "+
							"names it, so none of its rules ship and no test "+
							"covers them", ident.Name, filepath.Base(name))
					}
				}
			}
		}
	}

	// A guard on the guard. If the detection above ever stops recognising a
	// rule group -- a change of shape, a rename -- this test would quietly
	// pass over an empty set and report nothing wrong forever.
	if found < 10 {
		t.Errorf("only found %d rule groups, which is fewer than this package "+
			"has: the detection in this test has probably stopped working",
			found)
	}
}

// isRuleSlice reports whether a var declaration produces a []GrammarRule,
// either declared as one or assigned from something that plainly is.
func isRuleSlice(value *ast.ValueSpec) bool {
	if array, ok := value.Type.(*ast.ArrayType); ok {
		ident, ok := array.Elt.(*ast.Ident)
		return ok && ident.Name == "GrammarRule"
	}
	// `var x = buildX()` or `var x = append(buildY(), ...)`: no written type,
	// so go by the naming convention every group in this package follows.
	if value.Type == nil && len(value.Values) > 0 {
		for _, name := range value.Names {
			if strings.HasSuffix(name.Name, "Rules") {
				return true
			}
		}
	}
	return false
}

// mentions reports whether src refers to name as a whole identifier, so
// "articleRules" is not matched by a search for "pluralArticleRules" or the
// other way round.
func mentions(src, name string) bool {
	for at := 0; ; {
		i := strings.Index(src[at:], name)
		if i < 0 {
			return false
		}
		i += at
		before := byte(' ')
		if i > 0 {
			before = src[i-1]
		}
		after := byte(' ')
		if i+len(name) < len(src) {
			after = src[i+len(name)]
		}
		if !isIdentByte(before) && !isIdentByte(after) {
			return true
		}
		at = i + len(name)
	}
}

func isIdentByte(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9')
}
