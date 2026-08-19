// Command writingtools is a Bison Relay dynamic-wasm plugin
// providing two capabilities:
//
//   - spellcheck-data: a dictionary for the requested language, a set of
//     writing rules and a set of declared analysis checks, handed over once
//     when the plugin is enabled and again whenever the language changes.
//     Every match and every count after that happens in the app; there is no
//     per-keystroke work here.
//   - thesaurus: synonyms and definitions for one word, answered on demand.
//     This data stays in the plugin -- at 10MB it is far too much to push
//     across for a feature used a word at a time. The word asked about is
//     reduced to the base form the data is keyed by before it is searched.
//
// It is headless -- no nav item, no screens -- so beyond the `alloc` export
// every plugin must provide, it implements only those two capabilities'
// exports.
//
// That also means the plugin never sees a word anyone types. It has no
// network and no filesystem access, and needs neither.
//
// This file is only the WebAssembly plumbing; the content lives in package
// spellcheck. Build with build.sh (GOOS=wasip1 GOARCH=wasm go build
// -buildmode=c-shared); see wasmhost's package doc in the bisonrelay repo
// for the ABI it implements.
package main

import (
	"bytes"
	"compress/gzip"
	_ "embed"
	"encoding/json"
	"io"

	"unsafe"

	"github.com/companyzero/bisonrelay/plugins/writingtools/spellcheck"
	"github.com/companyzero/bisonrelay/plugins/writingtools/thesaurus"
)

// The datasets are embedded compressed. Together they are 11MB of text, which
// is almost all of the built module; gzipped they are 3.6MB, and the module
// drops to roughly a third of what it would otherwise be.
//
// This costs nothing at runtime that was not already being paid: //go:embed
// puts the data in the module's linear memory either way, so the only
// difference is one decompression the first time each is used.
//
// One pair per language. The two English dictionaries are not subsets of one
// another -- "colour" is in one and "color" in the other -- so a language is
// a different list rather than the same list with extras.
//
//go:embed words-en-US.txt.gz
var wordsUSGZ []byte

//go:embed common-en-US.txt.gz
var commonUSGZ []byte

//go:embed words-en-GB.txt.gz
var wordsGBGZ []byte

//go:embed common-en-GB.txt.gz
var commonGBGZ []byte

// dictionaries maps a language code to its compressed pair.
var dictionaries = map[string]struct{ words, common []byte }{
	"en-US": {wordsUSGZ, commonUSGZ},
	"en-GB": {wordsGBGZ, commonGBGZ},
}

//go:embed thesaurus.txt.gz
var thesaurusGZ []byte

//go:embed definitions.txt.gz
var definitionsGZ []byte

// The irregular forms WordNet's suffix rules cannot reach -- went/go,
// children/child. 91KB, and the difference between a lookup answering for
// two thirds of the dictionary and answering for a third of it.
//
//go:embed exceptions.txt.gz
var exceptionsGZ []byte

// The forms each word takes -- go/goes/went/gone, child/children. The same
// knowledge as exceptions.txt pointed the other way, plus the regular forms
// that WordNet has no list for because its rules generate them. 168KB.
//
//go:embed inflections.txt.gz
var inflectionsGZ []byte

// gunzip decompresses an embedded dataset. A failure here means the module
// was built wrong rather than that anything went wrong at runtime, so the
// caller degrades to having no data rather than trying to recover.
func gunzip(b []byte) string {
	r, err := gzip.NewReader(bytes.NewReader(b))
	if err != nil {
		return ""
	}
	defer r.Close()
	out, err := io.ReadAll(r)
	if err != nil {
		return ""
	}
	return string(out)
}

// thesaurusIndex is built on first use rather than at startup: a plugin whose
// thesaurus is never consulted should not pay to decompress and scan 10MB,
// and the host loads this module during client startup.
var thesaurusIndex *thesaurus.Index

func lookupIndex() *thesaurus.Index {
	if thesaurusIndex == nil {
		thesaurusIndex = thesaurus.NewIndex(
			gunzip(thesaurusGZ), gunzip(definitionsGZ), gunzip(exceptionsGZ),
			gunzip(inflectionsGZ))
	}
	return thesaurusIndex
}

// --- ABI plumbing every dynamic-wasm plugin needs ---

// pinned keeps allocated buffers alive: nothing else references them once
// alloc returns, so without this the Go GC could collect the memory the host
// is about to write to (or has just written to) before it is read.
var pinned = map[int32][]byte{}

//go:wasmexport alloc
func alloc(size int32) int32 {
	if size == 0 {
		size = 1
	}
	buf := make([]byte, size)
	// go vet flags this uintptr(unsafe.Pointer(...)) conversion as a
	// possible misuse since the address outlives the expression it is taken
	// in -- but Go's allocator doesn't move objects, and buf is kept alive
	// via pinned (keyed by this same address) for as long as the host needs
	// it, so there is no actual staleness risk here.
	ptr := int32(uintptr(unsafe.Pointer(&buf[0])))
	pinned[ptr] = buf
	return ptr
}

func writeResult(data []byte) uint64 {
	ptr := alloc(int32(len(data)))
	copy(pinned[ptr], data)
	return (uint64(uint32(ptr)) << 32) | uint64(len(data))
}

// getSpellcheckData answers the spellcheck-data capability for one language.
//
// An unknown or empty language is answered with the default rather than
// refused: a host that has not been told what is on offer should still get a
// working checker, and the reply names the language it actually contains.
//
//go:wasmexport get_spellcheck_data
func getSpellcheckData(language string) uint64 {
	dict, ok := dictionaries[language]
	if !ok {
		language = spellcheck.DefaultLanguage
		dict = dictionaries[language]
	}

	b, err := json.Marshal(spellcheck.Data{
		Words:          spellcheck.ParseWords(gunzip(dict.words)),
		CommonWords:    spellcheck.ParseWords(gunzip(dict.common)),
		Language:       language,
		Languages:      spellcheck.Languages,
		GrammarRules:   spellcheck.Rules,
		AnalysisChecks: spellcheck.AnalysisChecks,
	})
	if err != nil {
		// Returning zero bytes is how this ABI says "I could not answer";
		// the host logs it and carries on without this provider's data.
		return 0
	}
	return writeResult(b)
}

// lookupSynonyms answers the thesaurus capability. The export keeps its
// original name: renaming it would break every host already asking for it,
// and the capability, not the export, is what the contract is written
// against.
//
//go:wasmexport lookup_synonyms
func lookupSynonyms(word string) uint64 {
	entry, ok := lookupIndex().Lookup(word)
	if !ok {
		// Zero bytes is this ABI's "I could not answer", which is the honest
		// result for a name, a typo, or a word the data doesn't cover.
		return 0
	}
	b, err := json.Marshal(entry)
	if err != nil {
		return 0
	}
	return writeResult(b)
}

func main() {}
