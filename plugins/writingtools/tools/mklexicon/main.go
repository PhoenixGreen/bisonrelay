// Command mklexicon builds the list of what each word can be in a sentence.
//
// A dictionary says a word exists. A grammar rule needs to know more than
// that: that "goes" is the form "go" takes after "he", that "went" is its
// past and "gone" its participle, that "works" is as often a noun as a verb
// and "the" is never either. Without it the only rules that can be written
// are about particular words -- which is what this plugin's rules all were,
// and why "He go to school" passed unmarked.
//
// One line per word, with every reading it has and how common each is:
//
//	went	VBD:100:go
//	works	NNS:55:work VBZ:45:work
//	go	VB:97 NN:3	VBZ=goes VBD=went VBN=gone VBG=going
//
// The last column, on a base form's own line, is the forms it takes -- what
// lets a correction be built ("didn't went" becomes "didn't go") as well as
// recognised.
//
// Four sources, each for what it is good at:
//
//   - data/closed-class.txt, by hand, for the grammar words.
//   - WordNet's index and exception files, for which words are nouns, verbs,
//     adjectives and adverbs, and for the irregular forms.
//   - inflections.txt, for the regular ones.
//   - data/pos-counts.txt, for how often. WordNet lists "see" as a noun (a
//     bishop's seat) beside the verb and gives no hint that one is a
//     curiosity; counted usage does.
//
// Run from the module root, after mkwords and mkinflections:
//
//	go run ./tools/mklexicon > lexicon.txt
package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

const (
	wordnetDir     = "data/wordnet"
	closedFile     = "data/closed-class.txt"
	countsFile     = "data/pos-counts.txt"
	inflectionFile = "inflections.txt.gz"
)

var wordFiles = []string{"words-en-GB.txt.gz", "words-en-US.txt.gz"}

// reading is one thing a word can be.
type reading struct {
	tag    string
	weight int
	lemma  string
}

// counts is how one written form was used, from data/pos-counts.txt.
type counts struct {
	noun, verb, adj, adv, other int64
	lower, capital              int64
}

func (c counts) tagged() int64 { return c.noun + c.verb + c.adj + c.adv + c.other }

func main() {
	words := readWords()
	closed := readClosed()
	usage := readCounts()
	wn := readWordNet()
	irregular := readIrregular()
	forms := readInflections()

	// analyses[form] is the set of (tag, lemma) the form can be, before
	// anything is known about how often.
	type analysis struct{ tag, lemma string }
	analyses := map[string]map[analysis]bool{}
	add := func(form, tag, lemma string) {
		if analyses[form] == nil {
			analyses[form] = map[analysis]bool{}
		}
		analyses[form][analysis{tag, lemma}] = true
	}

	// A word is whatever WordNet files it under.
	for w := range words {
		// "men" has an entry of its own, and is still only ever a plural.
		if _, plural := wn.nounExc[w]; wn.noun[w] && !plural {
			add(w, "NN", "")
		}
		if wn.verb[w] {
			add(w, "VB", "")
		}
		if wn.adj[w] {
			add(w, "JJ", "")
		}
		if wn.adv[w] {
			add(w, "RB", "")
		}
	}

	// And whatever its base form makes it.
	for lemma, list := range forms {
		for _, form := range list {
			if !words[form] {
				continue
			}
			if wn.verb[lemma] && isVerbForm(lemma, form, wn) {
				for _, tag := range verbTags(lemma, form, irregular, wn.verbExc[form] == lemma) {
					add(form, tag, lemma)
				}
			}
			if wn.noun[lemma] && isPlural(lemma, form, wn) {
				add(form, "NNS", lemma)
			}
			if wn.adj[lemma] || wn.adv[lemma] {
				// "Modest" is listed under "mod", and is not the most mod. A
				// word that is an adjective in its own right, and far
				// commoner than the one it is supposed to be a form of, is
				// not that word's form.
				//
				// WordNet says the same thing its own way for some of them:
				// an exception entry mapping a word to itself is "this is
				// not a form of anything".
				exc := wn.adjExc[form]
				own := exc == form || (wn.adj[form] && exc == "" &&
					(len(lemma) <= 3 || usage[form].lower > usage[lemma].lower))
				if tag := degree(lemma, form, wn); tag != "" && !own {
					if wn.adj[lemma] {
						add(form, "JJ"+tag, lemma)
					}
					if wn.adv[lemma] && !strings.HasSuffix(lemma, "ly") {
						add(form, "RB"+tag, lemma)
					}
				}
			}
		}
	}
	// The inflection list leaves out a form that is also a word in its own
	// right -- "going" the noun, "building", "painting" -- and those are
	// exactly the commonest -ing forms there are. Found here by taking the
	// ending off and seeing whether a verb is left.
	for w := range words {
		for _, cut := range []struct{ suffix, tag string }{
			{"ing", "VBG"}, {"ed", "VBD"}, {"ed", "VBN"},
		} {
			if !strings.HasSuffix(w, cut.suffix) {
				continue
			}
			stem := w[:len(w)-len(cut.suffix)]
			for _, base := range []string{stem, stem + "e", undouble(stem)} {
				if base != "" && len(base) >= 2 && wn.verb[base] && words[base] {
					add(w, cut.tag, base)
					break
				}
			}
		}
	}

	// The irregular table is the authority on the verbs it lists, including
	// the ones whose past is spelled like the base ("put", "read").
	for lemma, v := range irregular {
		for _, past := range v.past {
			if words[past] {
				add(past, "VBD", lemma)
			}
		}
		for _, part := range v.participle {
			if words[part] {
				add(part, "VBN", lemma)
			}
		}
	}

	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	fmt.Fprintln(out, "# Generated by tools/mklexicon -- do not edit.")
	fmt.Fprintln(out, "# What each word can be, how often, and the forms a base word takes.")
	fmt.Fprintln(out, "# Licence and attribution: data/LICENSE-WORDNET31, data/LICENSE-SCOWL,")
	fmt.Fprintln(out, "# data/LICENSE-GOOGLE-BOOKS-NGRAMS.")
	fmt.Fprintln(out, "# Format: word<TAB>TAG:weight[:lemma] ...[<TAB>TAG=form ...]")

	// Every form a lemma takes, by tag, for the last column.
	lemmaForms := map[string]map[string][]string{}
	for form, set := range analyses {
		for a := range set {
			if a.lemma == "" || a.lemma == form {
				continue
			}
			if lemmaForms[a.lemma] == nil {
				lemmaForms[a.lemma] = map[string][]string{}
			}
			lemmaForms[a.lemma][a.tag] = append(lemmaForms[a.lemma][a.tag], form)
		}
	}
	// The verbs whose forms are all grammar words, and so are in the closed
	// table rather than in WordNet's lists.
	lemmaForms["be"] = map[string][]string{"VBP": {"are"}, "VBZ": {"is"},
		"VBD": {"was"}, "VBN": {"been"}, "VBG": {"being"}}
	lemmaForms["have"] = map[string][]string{"VBZ": {"has"}, "VBD": {"had"},
		"VBN": {"had"}, "VBG": {"having"}}
	lemmaForms["do"] = map[string][]string{"VBZ": {"does"}, "VBD": {"did"},
		"VBN": {"done"}, "VBG": {"doing"}}

	// strength is how much a verb is used, judged by its other forms. "saw"
	// is the past of "see" and the base of a verb of its own, and its own
	// count cannot say which more often: "sees" and "seeing" against "saws"
	// and "sawing" can.
	strength := func(lemma, except string) float64 {
		var sum int64
		if lemma != except {
			sum += usage[lemma].verb
		}
		for _, list := range lemmaForms[lemma] {
			for _, form := range list {
				if form != except {
					sum += usage[form].verb
				}
			}
		}
		return float64(sum) + 1
	}

	all := map[string]bool{}
	for w := range words {
		all[w] = true
	}
	for w := range closed {
		all[w] = true
	}
	sorted := make([]string, 0, len(all))
	for w := range all {
		sorted = append(sorted, w)
	}
	sort.Strings(sorted)

	for _, w := range sorted {
		var readings []reading
		if fixed, ok := closed[w]; ok {
			readings = fixed
		} else if strings.Contains(w, "'") {
			// "it's" and "dog's" are in the dictionary, as spellings. As
			// grammar each is two words, and the app reads it as two when it
			// finds no entry for the whole.
			continue
		} else {
			var found []reading
			for a := range analyses[w] {
				found = append(found, reading{tag: a.tag, lemma: a.lemma})
			}
			readings = weigh(w, found, usage[w], strength,
				func(l string) int64 { return usage[l].lower })
		}
		if len(readings) == 0 {
			continue
		}
		sort.SliceStable(readings, func(i, j int) bool {
			if readings[i].weight != readings[j].weight {
				return readings[i].weight > readings[j].weight
			}
			return readings[i].tag < readings[j].tag
		})
		parts := make([]string, 0, len(readings))
		for _, r := range readings {
			s := r.tag + ":" + strconv.Itoa(r.weight)
			if r.lemma != "" && r.lemma != w {
				s += ":" + r.lemma
			}
			parts = append(parts, s)
		}
		line := w + "\t" + strings.Join(parts, " ")
		if byTag := lemmaForms[w]; len(byTag) > 0 {
			var cols []string
			for _, tag := range []string{"VBP", "VBZ", "VBD", "VBN", "VBG",
				"NNS", "JJR", "JJS", "RBR", "RBS"} {
				list := byTag[tag]
				if len(list) == 0 {
					continue
				}
				// Where a word has two forms for one job -- "learned" and
				// "learnt" -- the commoner is the one to offer.
				sort.SliceStable(list, func(i, j int) bool {
					ci, cj := usage[list[i]].lower, usage[list[j]].lower
					if ci != cj {
						return ci > cj
					}
					return list[i] < list[j]
				})
				cols = append(cols, tag+"="+list[0])
			}
			line += "\t" + strings.Join(cols, " ")
		}
		fmt.Fprintln(out, line)
	}
}

// coarse is which counted class a tag belongs to.
func coarse(tag string) string {
	switch {
	case strings.HasPrefix(tag, "NN"):
		return "noun"
	case strings.HasPrefix(tag, "VB"):
		return "verb"
	case strings.HasPrefix(tag, "JJ"):
		return "adj"
	case strings.HasPrefix(tag, "RB"):
		return "adv"
	}
	return "other"
}

// prior is how a class's share is divided among the readings in it, when a
// form has several: "put" is a base form, a past and a participle, and the
// counts only say it is a verb.
var prior = map[string]int{
	"NN": 6, "NNS": 6, "NNP": 6,
	"VB": 5, "VBZ": 5, "VBD": 3, "VBN": 2, "VBG": 5,
	"JJ": 6, "JJR": 6, "JJS": 6, "RB": 6, "RBR": 6, "RBS": 6,
}

// properShare is how often a word must be capitalised, of all its uses, to be
// taken for a name. Ordinary words are capitalised too -- at the start of a
// sentence, about one use in ten -- so anything near all of the time is a
// word that is capitalised for its own sake.
const properShare = 0.97

// weigh gives each reading its share of the word's uses.
func weigh(word string, found []reading, c counts,
	strength func(lemma, except string) float64,
	lemmaCount func(string) int64) []reading {
	total := c.tagged()

	// A name: nearly always capitalised, and written often enough to say so.
	written := c.lower + c.capital
	if written >= 20000 && float64(c.capital)/float64(written) >= properShare {
		proper := []reading{{tag: "NNP", weight: 100}}
		for _, r := range found {
			r.weight = 0
			proper = append(proper, r)
		}
		return proper
	}

	if total < 200 {
		// Nothing counted: the readings share out by prior alone.
		if len(found) == 0 {
			return guess(word)
		}
		return share(found, 100)
	}

	classShare := map[string]float64{
		"noun": float64(c.noun) / float64(total),
		"verb": float64(c.verb) / float64(total),
		"adj":  float64(c.adj) / float64(total),
		"adv":  float64(c.adv) / float64(total),
	}
	byClass := map[string][]reading{}
	for _, r := range found {
		byClass[coarse(r.tag)] = append(byClass[coarse(r.tag)], r)
	}
	// A class the word is plainly used as, and that nothing above accounts
	// for: "building" the noun, which WordNet has, or "online" the adverb,
	// which it does not.
	generic := map[string]string{"noun": "NN", "adj": "JJ", "adv": "RB", "verb": "VB"}
	if strings.HasSuffix(word, "ing") {
		generic["verb"] = "VBG"
	} else if strings.HasSuffix(word, "ed") {
		generic["verb"] = "VBN"
	}
	for class, tag := range generic {
		if len(byClass[class]) == 0 && classShare[class] >= 0.03 {
			byClass[class] = []reading{{tag: tag}}
		}
	}

	var out []reading
	for _, class := range []string{"noun", "verb", "adj", "adv"} {
		list := byClass[class]
		if len(list) == 0 {
			continue
		}
		total := int(classShare[class]*100 + 0.5)
		if class == "noun" && pluralFirst(word, list, c, lemmaCount) {
			// "Shoes" has an entry of its own in WordNet, and is still the
			// plural of "shoe" nine times in ten.
			for _, r := range list {
				if r.tag == "NNS" {
					r.weight = total * 9 / 10 / countTag(list, "NNS")
				} else {
					r.weight = total / 10 / (len(list) - countTag(list, "NNS"))
				}
				out = append(out, r)
			}
			continue
		}
		if class == "verb" && severalVerbs(word, list) {
			out = append(out, shareByStrength(word, list, total, strength)...)
			continue
		}
		out = append(out, share(list, total)...)
	}
	if len(out) == 0 {
		return guess(word)
	}
	// The commonest reading is never shown as impossible, whatever rounding
	// did to it.
	best := 0
	for i := range out {
		if out[i].weight > out[best].weight {
			best = i
		}
	}
	if out[best].weight == 0 {
		out[best].weight = 100
	}
	return out
}

func countTag(list []reading, tag string) int {
	n := 0
	for _, r := range list {
		if r.tag == tag {
			n++
		}
	}
	return n
}

// pluralFirst says whether a word that is both a plural and listed as a
// noun in its own right is mostly the plural: its singular is written at
// least a fifth as often. "Physics" is not mostly the plural of "physic".
func pluralFirst(word string, list []reading, c counts,
	lemmaCount func(string) int64) bool {
	plural, whole := "", false
	for _, r := range list {
		switch r.tag {
		case "NNS":
			plural = r.lemma
		case "NN":
			whole = true
		}
	}
	if plural == "" || !whole {
		return false
	}
	return lemmaCount(plural)*5 >= c.lower
}

// severalVerbs says whether the verb readings in [list] belong to more than
// one verb.
func severalVerbs(word string, list []reading) bool {
	seen := map[string]bool{}
	for _, r := range list {
		lemma := r.lemma
		if lemma == "" {
			lemma = word
		}
		seen[lemma] = true
	}
	return len(seen) > 1
}

// shareByStrength divides [total] among readings that belong to different
// verbs, by how much each verb is used.
func shareByStrength(word string, list []reading, total int,
	strength func(lemma, except string) float64) []reading {
	weights := make([]float64, len(list))
	var sum float64
	for i, r := range list {
		lemma := r.lemma
		if lemma == "" {
			lemma = word
		}
		weights[i] = strength(lemma, word) * float64(prior[r.tag])
		sum += weights[i]
	}
	out := make([]reading, len(list))
	for i, r := range list {
		r.weight = int(float64(total)*weights[i]/sum + 0.5)
		out[i] = r
	}
	return out
}

// share divides [total] among [list] by prior.
func share(list []reading, total int) []reading {
	sum := 0
	for _, r := range list {
		sum += prior[r.tag]
	}
	out := make([]reading, len(list))
	for i, r := range list {
		r.weight = total * prior[r.tag] / sum
		out[i] = r
	}
	return out
}

// guess is for a dictionary word nothing else knows about, which is nearly
// always a name or a noun too new or too rare for WordNet.
func guess(word string) []reading {
	if strings.HasSuffix(word, "ly") {
		return []reading{{tag: "RB", weight: 100}}
	}
	return []reading{{tag: "NN", weight: 100}}
}

// verbTags says what [form] is of the verb [lemma].
func verbTags(lemma, form string, irregular map[string]irregularVerb, listed bool) []string {
	if form == lemma+"s" || form == lemma+"es" ||
		(strings.HasSuffix(lemma, "y") && form == lemma[:len(lemma)-1]+"ies") {
		return []string{"VBZ"}
	}
	if strings.HasSuffix(form, "ing") {
		return []string{"VBG"}
	}
	if v, ok := irregular[lemma]; ok {
		var tags []string
		for _, p := range v.past {
			if p == form {
				tags = append(tags, "VBD")
			}
		}
		for _, p := range v.participle {
			if p == form {
				tags = append(tags, "VBN")
			}
		}
		return tags
	}
	if strings.HasSuffix(form, "s") && !strings.HasSuffix(form, "ss") {
		return []string{"VBZ"}
	}
	// A regular past, or an irregular one the table above does not list.
	// Anything else under a verb's name is some other word's form -- "faster"
	// is listed under "fast", which is a verb, for the adjective's sake.
	if strings.HasSuffix(form, "ed") || listed {
		return []string{"VBD", "VBN"}
	}
	return nil
}

// isVerbForm says whether [form] belongs to [lemma] the verb at all. The
// inflection list is by word, not by part of speech, so "better" is listed
// under "well" for the adverb and "leaves" under "leaf" for the noun -- and
// both of those words are also verbs, with forms of their own.
func isVerbForm(lemma, form string, wn wordnet) bool {
	if wn.verbExc[form] == lemma || form == lemma+"s" || form == lemma+"es" {
		return true
	}
	if wn.nounExc[form] == lemma || wn.adjExc[form] == lemma ||
		wn.advExc[form] == lemma {
		return false
	}
	stem := lemma
	if len(stem) > 2 {
		stem = stem[:len(stem)-1]
	}
	return strings.HasPrefix(form, stem)
}

// undouble takes a doubled final consonant back to one: "runn" to "run".
func undouble(stem string) string {
	n := len(stem)
	if n >= 3 && stem[n-1] == stem[n-2] {
		return stem[:n-1]
	}
	return ""
}

// isPlural says whether [form] is the plural of the noun [lemma], as against
// a form of the verb spelled the same as the noun.
func isPlural(lemma, form string, wn wordnet) bool {
	if wn.nounExc[form] == lemma {
		return true
	}
	if strings.HasSuffix(form, "ing") || strings.HasSuffix(form, "ed") {
		return false
	}
	return strings.HasSuffix(form, "s")
}

// degree says whether [form] is the comparative ("R") or superlative ("S")
// of [lemma], or neither ("").
func degree(lemma, form string, wn wordnet) string {
	known := wn.adjExc[form] == lemma || wn.advExc[form] == lemma
	switch {
	case strings.HasSuffix(form, "est"):
		return "S"
	case strings.HasSuffix(form, "er"):
		return "R"
	case known && strings.HasSuffix(form, "st"):
		return "S"
	case known:
		return "R"
	}
	return ""
}

type irregularVerb struct{ past, participle []string }

func readIrregular() map[string]irregularVerb {
	out := map[string]irregularVerb{}
	for _, line := range strings.Split(irregularVerbs, "\n") {
		f := strings.Fields(line)
		if len(f) != 3 {
			continue
		}
		out[f[0]] = irregularVerb{strings.Split(f[1], "/"), strings.Split(f[2], "/")}
	}
	return out
}

type wordnet struct {
	noun, verb, adj, adv             map[string]bool
	nounExc, verbExc, adjExc, advExc map[string]string
}

func readWordNet() wordnet {
	index := func(name string) map[string]bool {
		set := map[string]bool{}
		eachLine(wordnetDir+"/index."+name, func(line string) {
			if strings.HasPrefix(line, " ") {
				return
			}
			if sp := strings.IndexByte(line, ' '); sp > 0 {
				set[line[:sp]] = true
			}
		})
		return set
	}
	exc := func(name string) map[string]string {
		m := map[string]string{}
		eachLine(wordnetDir+"/"+name+".exc", func(line string) {
			if f := strings.Fields(line); len(f) >= 2 {
				m[f[0]] = f[1]
			}
		})
		return m
	}
	return wordnet{
		noun: index("noun"), verb: index("verb"),
		adj: index("adj"), adv: index("adv"),
		nounExc: exc("noun"), verbExc: exc("verb"),
		adjExc: exc("adj"), advExc: exc("adv"),
	}
}

func readWords() map[string]bool {
	words := map[string]bool{}
	for _, name := range wordFiles {
		for _, line := range strings.Split(gunzipFile(name), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			words[strings.ToLower(line)] = true
		}
	}
	return words
}

func readInflections() map[string][]string {
	out := map[string][]string{}
	for _, line := range strings.Split(gunzipFile(inflectionFile), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if bar := strings.IndexByte(line, '|'); bar > 0 {
			out[line[:bar]] = strings.Split(line[bar+1:], ",")
		}
	}
	return out
}

func readClosed() map[string][]reading {
	out := map[string][]reading{}
	eachLine(closedFile, func(line string) {
		if line == "" || strings.HasPrefix(line, "#") {
			return
		}
		f := strings.Fields(line)
		for _, spec := range f[1:] {
			p := strings.Split(spec, ":")
			if len(p) < 2 {
				fatal(fmt.Errorf("%s: bad reading %q for %q", closedFile, spec, f[0]))
			}
			weight, err := strconv.Atoi(p[1])
			if err != nil {
				fatal(fmt.Errorf("%s: bad weight in %q for %q", closedFile, spec, f[0]))
			}
			r := reading{tag: p[0], weight: weight}
			if len(p) > 2 {
				r.lemma = p[2]
			}
			out[f[0]] = append(out[f[0]], r)
		}
	})
	return out
}

// readCounts reads data/pos-counts.txt. A build without the file still works:
// every reading is then weighed by prior alone, which is poorer and not
// wrong.
func readCounts() map[string]counts {
	out := map[string]counts{}
	if _, err := os.Stat(countsFile); err != nil {
		fmt.Fprintln(os.Stderr, "mklexicon: no", countsFile, "-- weighing by prior alone")
		return out
	}
	eachLine(countsFile, func(line string) {
		if line == "" || strings.HasPrefix(line, "#") {
			return
		}
		f := strings.Split(line, "\t")
		if len(f) != 8 {
			return
		}
		n := func(i int) int64 { v, _ := strconv.ParseInt(f[i], 10, 64); return v }
		out[f[0]] = counts{noun: n(1), verb: n(2), adj: n(3), adv: n(4),
			other: n(5), lower: n(6), capital: n(7)}
	})
	return out
}

func eachLine(path string, fn func(string)) {
	file, err := os.Open(path)
	if err != nil {
		fatal(err)
	}
	defer file.Close()
	sc := bufio.NewScanner(file)
	sc.Buffer(make([]byte, 1<<20), 1<<24)
	for sc.Scan() {
		fn(sc.Text())
	}
}

func gunzipFile(path string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		fatal(err)
	}
	r, err := gzip.NewReader(bytes.NewReader(raw))
	if err != nil {
		fatal(err)
	}
	defer r.Close()
	out, err := io.ReadAll(r)
	if err != nil {
		fatal(err)
	}
	return string(out)
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "mklexicon:", err)
	os.Exit(1)
}
