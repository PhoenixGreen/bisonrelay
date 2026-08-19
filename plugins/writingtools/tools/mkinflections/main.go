// Command mkinflections builds the list of forms each word takes.
//
// The plugin already reduces an inflected word to its base so it can be
// looked up -- "children" finds "child". This is the same knowledge pointed
// the other way: having looked "child" up, say that it also appears as
// "children". Every dictionary shows this and the data was already on disk,
// used in one direction only.
//
// Two sources, and the second is what keeps it honest:
//
//   - WordNet's four .exc files, inverted. These are the irregulars no rule
//     reaches: go/went/gone, child/children, good/better/best.
//   - Regular forms built by suffix rules, then CHECKED AGAINST THE
//     DICTIONARY and dropped if they are not in it.
//
// The check is most of the design. Generating regular forms blindly produces
// "goed", "childs" and "runned" -- confidently wrong, which is worse than
// silent. A form only ships if SCOWL lists it as a real English word.
//
// The dictionary alone is not enough, though, because it rejects non-words
// and not wrong ones: "run" + "es" is "runes", which is a real word and not
// a form of "run", and "-er" on "take" gives "taker", which is a derived
// noun rather than an inflection. So the rules are also gated on part of
// speech, read from definitions.txt: only a verb takes "-ed", only a noun or
// verb takes "-s", only an adjective compares. Derivations are left out
// entirely -- "happily" is a different word from "happy", however closely
// related, and this is a list of a word's own forms.
//
// Run from the repo root, after mkwords and mkdefs:
//
//	go run ./tools/mkinflections > inflections.txt
//
// Output is one line per word that has any, sorted:
//
//	word|form,form,form
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	wordnetDir = "data/wordnet"
	// The GB list is the larger of the two and a superset for this purpose:
	// a form spelled differently in US English is still a real form, and
	// showing "realises" to somebody writing en-US is a smaller error than
	// showing nothing to anybody.
	wordsFile = "words-en-GB.txt"
	// definitionsFile is read for its part-of-speech labels only.
	definitionsFile = "definitions.txt"
)

var excFiles = []string{"noun.exc", "verb.exc", "adj.exc", "adv.exc"}

// suffixRule is one regular ending, with the parts of speech it applies to
// and any spelling condition on the stem.
//
// The rules still over-generate within their part of speech -- a verb is
// offered "-ed", "-d" and "-ied" and the dictionary settles which is real --
// but they no longer reach across into a part of speech the word does not
// have, which is what produced "runes" from the noun "run".
type suffixRule struct {
	trim, add string
	pos       string // "n", "v", "a": which senses may take it
	// after, if set, is the endings the stem must have. It is what keeps
	// "-es" on "bus" and "box" and off "run".
	after []string
}

var suffixRules = []suffixRule{
	// Plurals and third-person singular.
	{add: "s", pos: "nv"},
	{add: "es", pos: "nv", after: []string{"s", "x", "z", "ch", "sh", "o"}},
	{trim: "y", add: "ies", pos: "nv"},
	{trim: "f", add: "ves", pos: "n"},
	{trim: "fe", add: "ves", pos: "n"},
	// Past and progressive.
	{add: "ed", pos: "v"},
	{add: "d", pos: "v"},
	{trim: "e", add: "ed", pos: "v"},
	{trim: "y", add: "ied", pos: "v"},
	{add: "ing", pos: "v"},
	{trim: "e", add: "ing", pos: "v"},
	// Comparison, adjectives and adverbs only.
	{add: "er", pos: "a"},
	{add: "est", pos: "a"},
	{trim: "e", add: "er", pos: "a"},
	{trim: "e", add: "est", pos: "a"},
	{trim: "y", add: "ier", pos: "a"},
	{trim: "y", add: "iest", pos: "a"},
}

func main() {
	words := readWords(wordsFile)
	pos := readPos(definitionsFile)
	forms := map[string]map[string]bool{}

	add := func(base, form string) {
		if base == "" || form == "" || form == base {
			return
		}
		if forms[base] == nil {
			forms[base] = map[string]bool{}
		}
		forms[base][form] = true
	}

	// The irregulars, inverted. Taken as given: WordNet recorded them
	// precisely because no rule produces them, so the dictionary check
	// below would be the only thing standing between a reader and "went",
	// and a couple of hundred of these are absent from SCOWL as headwords.
	var irregular int
	for _, name := range excFiles {
		f, err := os.Open(filepath.Join(wordnetDir, name))
		if err != nil {
			fmt.Fprintln(os.Stderr, "mkinflections:", err)
			os.Exit(1)
		}
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			fields := strings.Fields(sc.Text())
			if len(fields) < 2 {
				continue
			}
			// "went go" -- the form first, then the base(s) it reduces to.
			form := strings.ToLower(fields[0])
			if strings.ContainsAny(form, "_ ") {
				continue
			}
			for _, base := range fields[1:] {
				base = strings.ToLower(base)
				if strings.ContainsAny(base, "_ ") {
					continue
				}
				add(base, form)
				irregular++
			}
		}
		f.Close()
	}

	// The regulars, generated and then filtered by the dictionary.
	var regular int
	for w := range words {
		if len(w) < 3 || strings.ContainsAny(w, "_ '") {
			continue
		}
		have := pos[w]
		if have == "" {
			// No definition means no part of speech to gate on, and
			// guessing here is how "runes" got in. A word with no entry has
			// nothing to show inflections beside anyway.
			continue
		}
		for _, r := range suffixRules {
			if !anyPos(have, r.pos) {
				continue
			}
			if len(r.after) > 0 && !hasAnySuffix(w, r.after) {
				continue
			}
			stem := w
			if r.trim != "" {
				if !strings.HasSuffix(w, r.trim) {
					continue
				}
				stem = w[:len(w)-len(r.trim)]
			}
			cand := stem + r.add
			if cand == w || !words[cand] {
				continue
			}
			add(w, cand)
			regular++
		}
		// A doubled final consonant: stop/stopped/stopping, run/running.
		// Verbs and adjectives only, for the same reason as above -- "-er"
		// on a noun is an agent, not a comparison.
		if n := len(w); n >= 3 && !isVowel(w[n-1]) && isVowel(w[n-2]) &&
			!isVowel(w[n-3]) {
			for _, end := range []string{"ed", "ing", "er", "est"} {
				want := "v"
				if end == "er" || end == "est" {
					want = "a"
				}
				if !anyPos(have, want) {
					continue
				}
				cand := w + string(w[n-1]) + end
				if words[cand] {
					add(w, cand)
					regular++
				}
			}
		}
	}

	bases := make([]string, 0, len(forms))
	for b := range forms {
		bases = append(bases, b)
	}
	sort.Strings(bases)

	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	fmt.Fprintln(out, "# Generated by tools/mkinflections -- do not edit.")
	fmt.Fprintf(out, "# %d words with inflected forms, from %s and %s.\n",
		len(bases), wordnetDir, wordsFile)
	fmt.Fprintln(out, "# Licence and attribution: data/LICENSE-WORDNET31, data/LICENSE-SCOWL.")
	fmt.Fprintln(out, "# Format: word|form,form")
	var written int
	for _, b := range bases {
		list := make([]string, 0, len(forms[b]))
		for f := range forms[b] {
			list = append(list, f)
		}
		sort.Strings(list)
		written += len(list)
		fmt.Fprintf(out, "%s|%s\n", b, strings.Join(list, ","))
	}
	fmt.Fprintf(os.Stderr,
		"mkinflections: %d words, %d forms (%d irregular, %d regular kept)\n",
		len(bases), written, irregular, regular)
}

func readWords(path string) map[string]bool {
	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "mkinflections:", err)
		os.Exit(1)
	}
	defer f.Close()
	out := make(map[string]bool, 128*1024)
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		w := strings.TrimSpace(sc.Text())
		if w == "" || strings.HasPrefix(w, "#") {
			continue
		}
		out[strings.ToLower(w)] = true
	}
	return out
}

// readPos reads which parts of speech each word has, as a string of the
// initials: "nv" for a word that is both a noun and a verb.
func readPos(path string) map[string]string {
	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "mkinflections:", err)
		os.Exit(1)
	}
	defer f.Close()
	out := make(map[string]string, 128*1024)
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		line := sc.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Split(line, "|")
		if len(parts) < 2 {
			continue
		}
		word := parts[0]
		have := out[word]
		for _, sense := range parts[1:] {
			p, _, ok := strings.Cut(sense, ":")
			if !ok || p == "" {
				continue
			}
			// "noun" -> n, "verb" -> v, "adj"/"adv" -> a. The two kinds of
			// modifier share a letter because they take the same endings.
			var initial string
			switch p {
			case "noun":
				initial = "n"
			case "verb":
				initial = "v"
			case "adj", "adv":
				initial = "a"
			default:
				continue
			}
			if !strings.Contains(have, initial) {
				have += initial
			}
		}
		out[word] = have
	}
	return out
}

// anyPos reports whether the word's parts of speech include any the rule
// applies to.
func anyPos(have, want string) bool {
	for i := 0; i < len(want); i++ {
		if strings.IndexByte(have, want[i]) >= 0 {
			return true
		}
	}
	return false
}

func hasAnySuffix(w string, ends []string) bool {
	for _, e := range ends {
		if strings.HasSuffix(w, e) {
			return true
		}
	}
	return false
}

func isVowel(b byte) bool {
	switch b {
	case 'a', 'e', 'i', 'o', 'u':
		return true
	}
	return false
}
