// Package spellcheck holds this plugin's actual content -- the wordlist and
// the writing rules -- separately from the WebAssembly plumbing in main.go, so
// it can be built and tested as ordinary Go.
//
// Nothing here matches anything. The plugin's whole job is to hand Bison Relay
// a body of data once, when it is enabled; the matching, the wavy underline
// and the suggestion menu all live in the app. That split is why the rules are
// regex *source*, never compiled here: they are executed by Dart, whose engine
// (unlike Go's RE2) supports the backreferences a rule like "repeated word"
// needs.
//
// The package is laid out so that adding a rule is a local change:
//
//	schema.go       the wire types, mirroring the capability's JSON exactly
//	rules.go        the one ordered list every group is assembled into
//	rulebuild.go    the helpers a rules_*.go file builds its patterns from
//	rules_*.go      one family of rules each, exposing a single []GrammarRule
//	analysis.go     the checks that count rather than match, declared only
//
// To add a family: write rules_yours.go exposing `var yourRules
// []GrammarRule`, and name it in the list in rules.go. TestEveryRuleGroupIsUsed
// fails if you forget the second half.
package spellcheck

import "strings"

// ParseWords tokenizes a generated wordlist: one lowercase word per line, with
// blank lines and "#" comments ignored.
func ParseWords(txt string) []string {
	lines := strings.Split(txt, "\n")
	words := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.ToLower(strings.TrimSpace(line))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		words = append(words, line)
	}
	return words
}
