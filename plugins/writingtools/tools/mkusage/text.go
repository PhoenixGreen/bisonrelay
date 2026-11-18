package main

// text.go reads text the way the app does.
//
// The counts this tool makes are looked up by the app with keys it builds
// from its own reading of what somebody typed, so the two have to cut a
// sentence into the same pieces and call the pieces the same things. This is
// the app's engine/language/tokens.dart over again, as closely as it needs
// to be: where the two differ, a count is filed under a name nobody asks for.

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

// --- the lexicon ---

type reading struct {
	tag    int
	weight int
}

type lexicon struct {
	words map[string][]reading
}

func (l *lexicon) has(w string) bool { _, ok := l.words[w]; return ok }

var tagNames = []string{
	"NN", "NNS", "NNP",
	"VB", "VBP", "VBZ", "VBD", "VBN", "VBG",
	"JJ", "JJR", "JJS", "RB", "RBR", "RBS",
	"DT", "PDT", "CD", "EX", "IN", "TO", "CC", "MD", "UH", "RP",
	"PRP", "PRP$", "WP", "WDT", "WP$", "WRB", "POS",
	"COMMA", "STOP", "PUNCT", "SYM", "BOUND",
}

var tagID = func() map[string]int {
	m := map[string]int{}
	for i, n := range tagNames {
		m[n] = i
	}
	return m
}()

func readLexicon() *lexicon {
	file, err := os.Open(lexiconFile)
	if err != nil {
		fatal(fmt.Errorf("%v -- run tools/mklexicon first", err))
	}
	defer file.Close()
	lex := &lexicon{words: map[string][]reading{}}
	sc := bufio.NewScanner(file)
	sc.Buffer(make([]byte, 1<<20), 1<<24)
	for sc.Scan() {
		line := sc.Text()
		if line == "" || line[0] == '#' {
			continue
		}
		cols := strings.Split(line, "\t")
		if len(cols) < 2 {
			continue
		}
		var rs []reading
		for _, spec := range strings.Fields(cols[1]) {
			p := strings.Split(spec, ":")
			id, ok := tagID[p[0]]
			if !ok || len(p) < 2 {
				continue
			}
			w, _ := strconv.Atoi(p[1])
			rs = append(rs, reading{id, w})
		}
		lex.words[cols[0]] = rs
	}
	return lex
}

// --- tokens ---

const (
	kindWord = iota
	kindNumber
	kindPunct
	kindOther
)

type token struct {
	text, lower string
	kind        int
	space       bool
	known       bool
}

var notProse = regexp.MustCompile("(?:https?://|www\\.)\\S+|[\\w.+-]+@[\\w-]+(?:\\.[\\w-]+)+|`[^`\\n]*`|[@#][A-Za-z_][\\w-]*")

var clitics = map[string]bool{"'s": true, "'re": true, "'ve": true, "'ll": true, "'d": true, "'m": true}

func isLetter(r rune) bool {
	return (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') ||
		(r >= 0xc0 && r <= 0x24f && r != 0xd7 && r != 0xf7)
}
func isDigit(r rune) bool { return r >= '0' && r <= '9' }
func isApostrophe(r rune) bool {
	return r == '\'' || r == 0x2019 || r == 0x2bc || r == 0x2018
}

func tokenize(line string, lex *lexicon) []token {
	rs := []rune(line)
	// Where the stretches that are not prose begin and end, in runes.
	skip := map[int]int{}
	for _, m := range notProse.FindAllStringIndex(line, -1) {
		skip[len([]rune(line[:m[0]]))] = len([]rune(line[:m[1]]))
	}
	var out []token
	space := true
	for i := 0; i < len(rs); {
		c := rs[i]
		if unicode.IsSpace(c) {
			space = true
			i++
			continue
		}
		if end, ok := skip[i]; ok {
			s := string(rs[i:end])
			out = append(out, token{s, strings.ToLower(s), kindOther, space, false})
			i, space = end, false
			continue
		}
		switch {
		case isLetter(c):
			end := i + 1
			for end < len(rs) {
				d := rs[end]
				if isLetter(d) {
					end++
					continue
				}
				joins := isApostrophe(d) || d == '-' || d == '.'
				if joins && end+1 < len(rs) && isLetter(rs[end+1]) {
					if d == '.' {
						single := end-i == 1 || (end-i >= 2 && rs[end-2] == '.')
						nextSingle := end+2 >= len(rs) || !isLetter(rs[end+2])
						if !single || !nextSingle {
							break
						}
					}
					end += 2
					continue
				}
				break
			}
			raw := string(rs[i:end])
			lower := strings.Map(func(r rune) rune {
				if isApostrophe(r) {
					return '\''
				}
				return unicode.ToLower(r)
			}, raw)
			known := lex.has(lower)
			if !known {
				if cut := strings.LastIndexByte(lower, '\''); cut > 0 && clitics[lower[cut:]] {
					head := lower[:cut]
					rawRunes := []rune(raw)
					headRunes := len([]rune(head))
					out = append(out, token{string(rawRunes[:headRunes]), head, kindWord, space, lex.has(head)})
					out = append(out, token{string(rawRunes[headRunes:]), lower[cut:], kindWord, false, lex.has(lower[cut:])})
					i, space = end, false
					continue
				}
			}
			out = append(out, token{raw, lower, kindWord, space, known})
			i = end
		case isDigit(c):
			end := i + 1
			for end < len(rs) {
				d := rs[end]
				if isDigit(d) || isLetter(d) {
					end++
				} else if (d == '.' || d == ',' || d == ':' || d == '/') &&
					end+1 < len(rs) && isDigit(rs[end+1]) {
					end++
				} else {
					break
				}
			}
			s := string(rs[i:end])
			out = append(out, token{s, strings.ToLower(s), kindNumber, space, false})
			i = end
		default:
			end := i + 1
			for end < len(rs) && rs[end] == c {
				end++
			}
			s := string(rs[i:end])
			out = append(out, token{s, s, kindPunct, space, false})
			i = end
		}
		space = false
	}
	return out
}

// units is the sentence as the counted contexts see it: each word whole,
// contractions included, numbers all one thing, and the marks reduced to
// what they do. Quotes and brackets are left out altogether, since a word's
// company is the same inside them as outside.
func units(toks []token) []string {
	out := make([]string, 0, len(toks))
	for i, t := range toks {
		switch t.kind {
		case kindWord:
			if !t.space && len(out) > 0 && strings.HasPrefix(t.lower, "'") &&
				i > 0 && toks[i-1].kind == kindWord {
				out[len(out)-1] += t.lower
				continue
			}
			out = append(out, t.lower)
		case kindNumber:
			out = append(out, "#")
		case kindOther:
			out = append(out, "*")
		case kindPunct:
			switch []rune(t.text)[0] {
			case ',', ';', ':', 0x2014, 0x2013:
				out = append(out, ",")
			case '.', '!', '?', 0x2026:
				// The stop that ends the sentence is the sentence's end, and
				// is not counted as a neighbour of its own.
				closing := true
				for _, after := range toks[i+1:] {
					if after.kind != kindPunct || !transparent(after.text) {
						closing = false
					}
				}
				if !closing {
					out = append(out, ".")
				}
			case '"', '\'', 0x2018, 0x2019, 0x201c, 0x201d, '(', ')', '[', ']':
			default:
				out = append(out, "*")
			}
		}
	}
	return out
}

// transparent is a quote or a bracket: a mark a word's company is counted
// straight through.
func transparent(text string) bool {
	switch []rune(text)[0] {
	case '"', '\'', 0x2018, 0x2019, 0x201c, 0x201d, '(', ')', '[', ']':
		return true
	}
	return false
}

// --- which tag follows which ---

func punctTag(text string) int {
	switch []rune(text)[0] {
	case ',', ';', ':', 0x2014, 0x2013:
		return tagID["COMMA"]
	case '.', '!', '?', 0x2026:
		return tagID["STOP"]
	case '"', '\'', 0x2018, 0x2019, 0x201c, 0x201d, '(', ')', '[', ']':
		return tagID["PUNCT"]
	}
	return tagID["SYM"]
}

func capitalised(s string) bool { return s != "" && s[0] >= 'A' && s[0] <= 'Z' }

// readings is what the token at [i] may be: tokens.dart's _readings.
func readings(toks []token, i int, first bool, lex *lexicon) []reading {
	t := toks[i]
	switch t.kind {
	case kindNumber:
		return []reading{{tagID["CD"], 100}}
	case kindOther:
		return []reading{{tagID["NNP"], 100}}
	case kindPunct:
		return []reading{{punctTag(t.text), 100}}
	}
	entry, ok := lex.words[t.lower]
	if !ok && strings.HasSuffix(t.lower, "n't") && len(t.lower) > 3 {
		entry, ok = lex.words[t.lower[:len(t.lower)-3]]
	}
	w := t.lower
	if !ok {
		switch {
		case strings.Contains(w, "-"):
			return []reading{{tagID["JJ"], 50}, {tagID["NN"], 40}}
		case capitalised(t.text):
			return []reading{{tagID["NNP"], 100}}
		case strings.HasSuffix(w, "ly"):
			return []reading{{tagID["RB"], 80}, {tagID["JJ"], 20}}
		case strings.HasSuffix(w, "ing"):
			return []reading{{tagID["VBG"], 60}, {tagID["NN"], 30}, {tagID["JJ"], 10}}
		case strings.HasSuffix(w, "ed"):
			return []reading{{tagID["VBN"], 45}, {tagID["VBD"], 40}, {tagID["JJ"], 15}}
		case strings.HasSuffix(w, "s") && !strings.HasSuffix(w, "ss"):
			return []reading{{tagID["NNS"], 70}, {tagID["VBZ"], 30}}
		}
		return []reading{{tagID["NN"], 70}, {tagID["JJ"], 15}, {tagID["VB"], 15}}
	}
	allCaps := len(t.text) > 1 && t.text == strings.ToUpper(t.text)
	if capitalised(t.text) && !first && !allCaps {
		nnp := tagID["NNP"]
		out := make([]reading, 0, len(entry)+1)
		had := 0
		for _, r := range entry {
			if r.tag == nnp {
				had = r.weight
				continue
			}
			out = append(out, reading{r.tag, r.weight / 2})
		}
		return append(out, reading{nnp, 50 + had/2})
	}
	return entry
}

type tagModel struct {
	n     int
	pair  []float64
	one   []float64
	total float64
	lift  []float64
}

func newTagModel() *tagModel {
	n := len(tagNames)
	return &tagModel{n: n, pair: make([]float64, n*n), one: make([]float64, n),
		lift: make([]float64, n*n)}
}

func (m *tagModel) add(a, b int) {
	m.pair[a*m.n+b]++
	m.one[b]++
	m.total++
}

func firstWord(toks []token) int {
	for i, t := range toks {
		if t.kind == kindWord {
			return i
		}
		if t.kind != kindPunct {
			break
		}
	}
	return -1
}

// sure is the one tag a token can be, or -1.
func sure(rs []reading) int {
	tag, n := -1, 0
	for _, r := range rs {
		if r.weight >= 3 {
			tag = r.tag
			n++
		}
	}
	if n == 1 {
		return tag
	}
	return -1
}

// countSure counts only between neighbours that each have one reading -- the
// part of the text that needs no model to tag.
func (m *tagModel) countSure(toks []token, lex *lexicon) {
	bound := tagID["BOUND"]
	fw := firstWord(toks)
	prev := bound
	for i := range toks {
		tag := sure(readings(toks, i, i == fw, lex))
		if prev >= 0 && tag >= 0 {
			m.add(prev, tag)
		}
		prev = tag
	}
	if prev >= 0 {
		m.add(prev, bound)
	}
}

// countTagged tags the sentence with [with] and counts every neighbour.
func (m *tagModel) countTagged(toks []token, lex *lexicon, with *tagModel) {
	if len(toks) == 0 {
		return
	}
	bound := tagID["BOUND"]
	fw := firstWord(toks)
	options := make([][]reading, len(toks))
	for i := range toks {
		options[i] = readings(toks, i, i == fw, lex)
	}
	score := make([][]float64, len(toks))
	back := make([][]int, len(toks))
	for i, here := range options {
		score[i] = make([]float64, len(here))
		back[i] = make([]int, len(here))
		for k, r := range here {
			w := float64(r.weight)
			if r.weight < 1 {
				w = 0.3
			}
			emit := math.Log(w)
			if i == 0 {
				score[i][k] = emit + with.lift[bound*m.n+r.tag]
				continue
			}
			best, from := math.Inf(-1), 0
			for j, p := range options[i-1] {
				if v := score[i-1][j] + with.lift[p.tag*m.n+r.tag]; v > best {
					best, from = v, j
				}
			}
			score[i][k], back[i][k] = best+emit, from
		}
	}
	last := len(toks) - 1
	bestEnd, bestScore := 0, math.Inf(-1)
	for k, r := range options[last] {
		if v := score[last][k] + with.lift[r.tag*m.n+bound]; v > bestScore {
			bestScore, bestEnd = v, k
		}
	}
	tags := make([]int, len(toks))
	for i, k := last, bestEnd; i >= 0; i-- {
		tags[i] = options[i][k].tag
		k = back[i][k]
	}
	prev := bound
	for _, t := range tags {
		m.add(prev, t)
		prev = t
	}
	m.add(prev, bound)
}

// finish turns the counts into lifts: the log of how many times likelier a
// tag is after another than it is anywhere. Bounded, so that a pair which
// happened not to turn up is unlikely rather than impossible.
func (m *tagModel) finish() {
	for a := 0; a < m.n; a++ {
		var from float64
		for b := 0; b < m.n; b++ {
			from += m.pair[a*m.n+b]
		}
		for b := 0; b < m.n; b++ {
			if from < 50 || m.one[b] < 50 {
				continue
			}
			given := (m.pair[a*m.n+b] + 0.5) / (from + 0.5*float64(m.n))
			overall := m.one[b] / m.total
			m.lift[a*m.n+b] = math.Max(-6, math.Min(4, math.Log(given/overall)))
		}
	}
}

func (m *tagModel) write() {
	var b strings.Builder
	for a := 0; a < m.n; a++ {
		for c := 0; c < m.n; c++ {
			if v := m.lift[a*m.n+c]; v != 0 {
				fmt.Fprintf(&b, "%s %s %.2f\n", tagNames[a], tagNames[c], v)
			}
		}
	}
	must(os.WriteFile("usage-tags.txt", []byte(b.String()), 0o644))
}
