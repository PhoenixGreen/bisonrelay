package capabilities

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr"
)

// thesaurusExport is the function a pluginmgr.CapabilityThesaurus plugin
// must export. It takes one lowercase word and returns a ThesaurusEntry.
const thesaurusExport = "lookup_synonyms"

// thesaurusTimeout bounds one lookup. Shorter than a link card's: this one
// *does* block a UI action -- someone has asked for synonyms and is waiting
// on the menu -- so a provider that cannot answer quickly is better dropped
// than waited on.
const thesaurusTimeout = 5 * time.Second

// ThesaurusSense is one meaning of a word, since a word usually has several
// and their synonyms are not interchangeable: the synonyms for "bank" as a
// place to keep money are wrong for its river sense. Keeping the senses
// apart is what lets the UI show them apart, rather than pooling every
// synonym into one misleading list.
type ThesaurusSense struct {
	// PartOfSpeech is a short label ("noun", "verb", "adj", "adv"), used to
	// caption the sense. Free-form: a provider for another language may have
	// categories English does not.
	PartOfSpeech string `json:"pos"`

	Synonyms []string `json:"synonyms"`

	// Antonyms may be empty, and usually is -- most senses have none.
	Antonyms []string `json:"antonyms,omitempty"`
}

// ThesaurusDefinition is one of a word's meanings.
type ThesaurusDefinition struct {
	PartOfSpeech string `json:"pos"`
	Text         string `json:"text"`
}

// ThesaurusEntry is everything a provider knows about one word.
type ThesaurusEntry struct {
	Word   string           `json:"word"`
	Senses []ThesaurusSense `json:"senses"`

	// Definitions are the word's meanings, listed separately from Senses
	// rather than attached to them.
	//
	// Separate because a provider's synonyms and its definitions need not
	// come from the same source, and two sources will not divide a word into
	// the same senses. Pairing them would mean guessing which meaning went
	// with which group of synonyms, and guessing wrong reads as confidently
	// wrong rather than merely unhelpful.
	Definitions []ThesaurusDefinition `json:"definitions,omitempty"`
}

// IsEmpty reports whether the entry offers nothing worth showing, which is
// the ordinary outcome for a name, a typo, or a word the provider's data
// simply doesn't cover.
func (e ThesaurusEntry) IsEmpty() bool {
	if len(e.Definitions) > 0 {
		return false
	}
	for _, s := range e.Senses {
		if len(s.Synonyms) > 0 || len(s.Antonyms) > 0 {
			return false
		}
	}
	return true
}

// LookupSynonyms asks each enabled thesaurus plugin about word and returns
// the first non-empty answer.
//
// First answer rather than a merge across providers: two thesauruses would
// disagree about how to divide a word's senses, and interleaving them
// produces a list that reads as though one source contradicted itself. A
// user installing a second thesaurus is choosing a different one, not asking
// for both at once; ordering is by plugin id, so which one wins is stable.
//
// A provider that fails or knows nothing is skipped rather than fatal -- the
// caller gets "no synonyms", which is also the honest answer for a word no
// thesaurus covers.
func LookupSynonyms(ctx context.Context, mgr Manager, rt Runtime,
	word string) (ThesaurusEntry, error) {

	word = strings.ToLower(strings.TrimSpace(word))
	if word == "" {
		return ThesaurusEntry{}, fmt.Errorf("capabilities: no word to look up")
	}

	providers := mgr.PluginsProviding(pluginmgr.ServiceThesaurus)
	if len(providers) == 0 {
		return ThesaurusEntry{}, fmt.Errorf("capabilities: no thesaurus plugin is enabled")
	}

	var firstErr error
	for _, manifest := range providers {
		export, _ := manifest.ServiceExport(pluginmgr.ServiceThesaurus)
		var entry ThesaurusEntry
		err := call(ctx, rt, manifest.ID, export, []byte(word),
			thesaurusTimeout, &entry)
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		if !entry.IsEmpty() {
			return entry, nil
		}
	}
	if firstErr != nil {
		return ThesaurusEntry{}, firstErr
	}
	return ThesaurusEntry{Word: word}, nil
}
