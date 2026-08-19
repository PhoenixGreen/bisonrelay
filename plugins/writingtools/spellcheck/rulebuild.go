package spellcheck

import (
	"regexp"
	"strings"
	"unicode"
)

// rulebuild.go holds the helpers a rules_*.go file writes its patterns with.
//
// They were scattered before -- the either-case one in rules_style.go, its
// near-twin in rules_articles.go, the casing variants in rules_brands.go --
// each in whichever file first needed it, so the next file that needed one
// either imported it from an unrelated neighbour or wrote its own. The two
// either-case helpers had in fact already diverged into a pair that look
// identical and are not: one quotes its input as a literal and one does not,
// which matters entirely and was stated nowhere.
//
// Nothing here knows any English. These are string manipulations over patterns
// the rules supply, which is what makes them safe to share.

// concat flattens the rule groups into the single list the capability returns.
func concat(groups ...[]GrammarRule) []GrammarRule {
	total := 0
	for _, group := range groups {
		total += len(group)
	}
	all := make([]GrammarRule, 0, total)
	for _, group := range groups {
		all = append(all, group...)
	}
	return all
}

// eitherCaseFirst puts a two-character class in place of the first letter, so
// a pattern matches the word at the start of a sentence as well as inside one.
//
// The primitive both helpers below are built from. It takes the input as
// pattern source and does not quote it: a caller with a literal phrase has to
// quote it first, which is exactly the difference between the two.
//
// A first character with no case of its own -- a digit, a bracket, a backslash
// opening an escape -- is left exactly as it is, which is what keeps the helper
// usable on a stem like `\d+` without silently corrupting it.
func eitherCaseFirst(pattern string) string {
	if pattern == "" {
		return ""
	}
	first := rune(pattern[0])
	lower, upper := unicode.ToLower(first), unicode.ToUpper(first)
	if lower == upper {
		return pattern
	}
	return "[" + string(lower) + string(upper) + "]" + pattern[1:]
}

// eitherCase turns a literal phrase into a pattern matching it in either case
// at the front. Everything after the first letter is quoted, so a phrase
// containing a full stop or a bracket matches those characters rather than
// being read as a pattern.
func eitherCase(phrase string) string {
	if phrase == "" {
		return ""
	}
	return eitherCaseFirst(string(phrase[0])) + regexp.QuoteMeta(phrase)[1:]
}

// eitherCaseAlternation joins pattern *stems* into one alternation, each
// accepting either case at the front.
//
// Unquoted, unlike eitherCase: the stems it is given are pattern fragments in
// their own right -- `uniqu\w*`, `europ\w*` -- and quoting them would turn the
// `\w*` into a literal backslash, a w and an asterisk, which matches nothing
// anybody has ever typed.
func eitherCaseAlternation(stems []string) string {
	out := make([]string, 0, len(stems))
	for _, stem := range stems {
		out = append(out, eitherCaseFirst(stem))
	}
	return strings.Join(out, "|")
}

// wordBoundary returns `\b` only where it can match: a phrase ending in a
// non-word character has no word boundary after it, and appending one there
// makes a rule that can never fire -- which nothing else would notice.
func wordBoundary(phrase string) string {
	if phrase == "" {
		return ""
	}
	last := phrase[len(phrase)-1]
	isWord := last == '_' ||
		(last >= 'a' && last <= 'z') ||
		(last >= 'A' && last <= 'Z') ||
		(last >= '0' && last <= '9')
	if isWord {
		return `\b`
	}
	return ""
}

// wrongCasings derives the spellings of a name that are not how its owner
// spells it: all lower, all upper, and merely capitalised.
//
// Derived rather than listed beside each name, so a name cannot be added with
// its own misspellings typed wrongly next to it -- which, on a list of that
// shape, is the mistake that would actually happen.
func wrongCasings(name string) []string {
	lower := strings.ToLower(name)
	variants := []string{
		lower,
		strings.ToUpper(name),
		string(unicode.ToUpper(rune(lower[0]))) + lower[1:],
	}
	seen := map[string]bool{name: true}
	out := make([]string, 0, len(variants))
	for _, v := range variants {
		if seen[v] {
			continue
		}
		seen[v] = true
		out = append(out, v)
	}
	return out
}
