// Command mkthesaurus condenses the MyThes thesaurus in data/ into the
// compact, single-word-headword form the plugin ships.
//
// The source is 18MB, over half of whose headwords are phrases ("'s
// gravenhage", ".22 caliber") that a lookup keyed on one selected word can
// never reach. Those are dropped.
//
// What remains needs sorting by how safe a replacement it is, because
// MyThes marks its cross-references and they do not all mean the same thing:
//
//   - unmarked        a true synonym of this sense.
//   - (similar term)  WordNet's satellite adjectives. Real replacements --
//     "blissful" for "happy" -- and for many adjectives the
//     ONLY ones, since the direct synonym list is empty.
//   - (related term)  looser, but still usually substitutable: "cheerful",
//     "contented", "joyful" for "happy".
//   - (generic term)  a hypernym, and never a replacement: offering "city"
//     for "Hague" produces a sentence that no longer means
//     what it did. Dropped outright.
//
// The three kept tiers are emitted in that order, so the safest words lead.
// An earlier version dropped all three marked tiers and left "happy" with
// felicitous, glad and well-chosen while discarding every word anyone would
// actually pick.
//
// Antonyms are kept and tagged, because a word's opposite is worth offering
// even though it is not a replacement.
//
// Run from the repo root:
//
//	go run ./tools/mkthesaurus > thesaurus.txt
//
// Output is one line per word, sorted:
//
//	word|pos:syn,syn,syn|pos:syn,syn!ant,ant
//
// with "!" separating a sense's antonyms from its synonyms. Commas and pipes
// cannot appear in the source's entries, so no escaping is needed.
package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

const datPath = "data/th_en_US_v2.dat"

// maxSynonyms caps one sense. Past a dozen the tail is invariably obscure,
// and the menu showing them has to stay readable.
const maxSynonyms = 12

type sense struct {
	pos      string
	synonyms []string
	antonyms []string
}

// tier ranks one MyThes entry by how safely it substitutes for the headword:
// 0 direct synonym, 1 similar, 2 related, and -1 for anything to discard.
func tier(entry string) (string, int) {
	switch {
	case strings.HasSuffix(entry, " (generic term)"):
		return "", -1
	case strings.HasSuffix(entry, " (similar term)"):
		return strings.TrimSuffix(entry, " (similar term)"), 1
	case strings.HasSuffix(entry, " (related term)"):
		return strings.TrimSuffix(entry, " (related term)"), 2
	default:
		return entry, 0
	}
}

// maxPhraseWords caps how long a headword may be.
//
// Three. WordNet carries entries of six and seven words -- "arteria
// gastrica sinistra", "American Federation of Labor" -- and a lookup is
// triggered by a selection, so an entry longer than anybody would select is
// weight in the file and nothing else. Two and three cover the phrasal
// verbs and compounds that are actually looked up: "take off", "give up
// on", "wedding ring".
const maxPhraseWords = 3

// usableHeadword keeps what a lookup could actually be triggered on: one to
// three alphabetic words.
//
// WordNet writes a multi-word entry with underscores, and those used to be
// rejected outright -- which discarded 64,246 headwords, 43% of its
// vocabulary, and left the tool with nothing to say about "take off" or "in
// spite of". Those are exactly the constructions somebody still learning
// English looks up, so they are kept now and the underscores become spaces.
func usableHeadword(w string) bool {
	if w == "" {
		return false
	}
	// WordNet joins a phrase's words with underscores and MyThes with
	// spaces; both are read here so the two generators can share this.
	words := 1
	for _, r := range w {
		switch {
		case r >= 'a' && r <= 'z':
		case r == '_' || r == ' ':
			words++
			if words > maxPhraseWords {
				return false
			}
		default:
			return false
		}
	}
	for _, bad := range []string{"_", " ", "__", "  ", "_ ", " _"} {
		if strings.HasPrefix(w, bad) || strings.HasSuffix(w, bad) ||
			strings.Contains(w, "__") || strings.Contains(w, "  ") {
			return false
		}
	}
	return true
}

// headwordText is the form a headword is stored and looked up under: the
// words as somebody would type them.
func headwordText(w string) string { return strings.ReplaceAll(w, "_", " ") }

func main() {
	f, err := os.Open(datPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "mkthesaurus:", err)
		os.Exit(1)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	sc.Scan() // the first line is the file's encoding, not an entry

	entries := map[string][]sense{}
	var kept, skipped int

	for sc.Scan() {
		head := sc.Text()
		bar := strings.LastIndex(head, "|")
		if bar < 0 {
			continue
		}
		word := strings.ToLower(strings.TrimSpace(head[:bar]))
		count, err := strconv.Atoi(strings.TrimSpace(head[bar+1:]))
		if err != nil {
			continue
		}

		var senses []sense
		for i := 0; i < count && sc.Scan(); i++ {
			parts := strings.Split(sc.Text(), "|")
			if len(parts) < 2 {
				continue
			}
			s := sense{pos: strings.Trim(parts[0], "()")}
			var byTier [3][]string
			for _, raw := range parts[1:] {
				raw = strings.TrimSpace(raw)
				if raw == "" || strings.EqualFold(raw, word) {
					continue
				}
				if trimmed := strings.TrimSuffix(raw, " (antonym)"); trimmed != raw {
					s.antonyms = append(s.antonyms, trimmed)
					continue
				}
				entry, t := tier(raw)
				if t < 0 {
					continue
				}
				byTier[t] = append(byTier[t], entry)
			}
			// Safest tier first, and deduplicated: a word can appear as both
			// a similar and a related term of the same sense.
			seen := map[string]bool{word: true}
			for _, group := range byTier {
				for _, w := range group {
					if seen[strings.ToLower(w)] || len(s.synonyms) >= maxSynonyms {
						continue
					}
					seen[strings.ToLower(w)] = true
					s.synonyms = append(s.synonyms, w)
				}
			}
			if len(s.synonyms) > 0 || len(s.antonyms) > 0 {
				senses = append(senses, s)
			}
		}

		if !usableHeadword(word) {
			skipped++
			continue
		}
		word = headwordText(word)
		if len(senses) == 0 {
			continue
		}
		entries[word] = senses
		kept++
	}
	if err := sc.Err(); err != nil {
		fmt.Fprintln(os.Stderr, "mkthesaurus:", err)
		os.Exit(1)
	}

	words := make([]string, 0, len(entries))
	for w := range entries {
		words = append(words, w)
	}
	sort.Strings(words)

	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	fmt.Fprintln(out, "# Generated by tools/mkthesaurus -- do not edit.")
	fmt.Fprintf(out, "# %d single-word entries condensed from %s.\n", kept, datPath)
	fmt.Fprintln(out, "# Licence and attribution: data/LICENSE-WORDNET.")
	fmt.Fprintln(out, "# Format: word|pos:syn,syn|pos:syn!ant")
	for _, w := range words {
		var b strings.Builder
		b.WriteString(w)
		for _, s := range entries[w] {
			b.WriteByte('|')
			b.WriteString(s.pos)
			b.WriteByte(':')
			b.WriteString(strings.Join(s.synonyms, ","))
			if len(s.antonyms) > 0 {
				b.WriteByte('!')
				b.WriteString(strings.Join(s.antonyms, ","))
			}
		}
		fmt.Fprintln(out, b.String())
	}
	fmt.Fprintf(os.Stderr, "mkthesaurus: %d words kept, %d phrase headwords dropped\n",
		kept, skipped)
}
