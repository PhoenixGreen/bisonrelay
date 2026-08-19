# Writing tools plugin

The data half of Bison Relay's writing tools: a 120,000-word English
dictionary, 787 writing rules, a thesaurus and a dictionary of definitions,
compiled to a WebAssembly module the client ships inside itself.

It lives here, in the client's own repository, because it is a built-in --
`client/pluginmgr/builtin` embeds the module it produces and unpacks it on
first run, so a rule written here and a rule reviewed here are the same rule.
It was a separate repository until August 2026 and the split cost more than it
was worth: the embedded copy went stale without anyone noticing, and a change
to a rule and a change to the panel that shows it were two pull requests.

Its own Go module, deliberately. The plugin builds for `wasip1` with
`-buildmode=c-shared` and must not be part of the client's build; a nested
module is how Go says so.

The manifest id is `spellcheck`, which is what the client tracks an installed
plugin by. Changing it would orphan an existing install for no gain.

**Headless**: it contributes no nav item and no screens, only the
`spellcheck-data` and `thesaurus` capabilities. Nothing here matches anything.
The rules are regex *source*, executed in Dart by the app -- whose engine,
unlike Go's RE2, has the backreferences a rule like "repeated word" needs --
and the panels, the underlines and the corrections all live in
`bruig/flutterui/bruig/lib/plugin_system/writing_tools`. This half supplies
the data, once, when the plugin is enabled. It runs sandboxed, with no network
and no filesystem access, and needs neither: everything it knows is compiled
into the module.

## What it checks

**Spelling.** A 121,407-word dictionary: 121,338 surface forms expanded from the
SCOWL-derived hunspell `en_US` dictionary, plus 69 words of Bison Relay, Decred and
crypto vocabulary a general dictionary has never heard of (see `data/extra-words.txt`).

Surface forms matter. A hunspell `.dic` stores roots plus affix flags -- `abandon/LDGS`,
not the five words that spells -- so a checker fed the roots alone flags every inflection
anyone actually types. `tools/mkwords` expands them ahead of time, which keeps this
plugin's runtime a set membership test.

**Writing style.** 787 rules: 587 errors, 180 suggestions and 20 checks,
covering confusable words, agreement, articles, capitalisation, punctuation,
redundancy, inclusive language, typography and the commas that depend on what
the sentence is doing.

Rules come in three severities. An **error** is text that is wrong whatever the writer meant --
a misspelling, a missing apostrophe, "have went" -- and every one of them is held to a
standard of never firing on correct writing. A **suggestion** is an opinion: wordiness, a
cliche, the passive voice. Those cannot meet that standard and are not asked to, because
the app underlines them in a different colour and lists them on a separate page, so being
wrong costs a quieter mark somewhere the reader went looking for opinions.

A **check** is a question rather than a finding: the word is spelled correctly
and the sentence parses, and all that is being claimed is that this is one of
the pairs -- or one of the commas -- people get wrong. "It would brake the
system" is the case. Checks are underlined in amber, listed beside the
suggestions, and offer "Correct Usage", which is the answer only a question
can take. See the note at the top of `spellcheck/rules_checks.go`.

That distinction is what makes the second and third groups below shippable at all. Without
it they would put the same alarming red wave under prose that is perfectly good, and the
reader who learns to ignore that mark ignores it over the misspellings too.

A rule can also carry **antipatterns** -- patterns saying where it is *not* to fire. The
alternative is a negative lookahead glued onto the end of the pattern, which works and is
worse in three ways: it is unreadable, it cannot be tested on its own, and it puts the rule
beyond Go's RE2, which is how the corpus below loses sight of exactly the rules whose
exceptions most need watching. Moving the guards out of the patterns took the number of
rules the corpus cannot check from 19 to 9, and immediately found a bug in one of them --
"with out-of-date firmware" had been flagged since the rule was written, and the test that
would have caught it had been skipping the rule for the same reason.

Antipatterns suppress and cannot create: a rule that needs *context* to fire still says so
in its pattern.

Every rule also carries its own **examples** -- text it must catch, and text it must not --
and `TestRuleExamples` runs all 265 of them. They are attached to the rule rather than kept
in a list somewhere else, because the failure this plugin actually suffers is not a missing
rule: it is a rule that was wrong from the day it was written and went unnoticed for weeks.
Three of those turned up in a single afternoon of real use. Each would have failed here the
moment it was typed, and named the rule rather than a line of shared corpus.

They never reach the host. `json:"-"`, with a test that says so -- this is how a rule is
developed, not what it does, and sending it would put a test fixture on the capability's
contract where it would have to be reviewed and versioned like a feature.

Each rule carries a category and an explanation as well as a message and a replacement.
The message names the problem in the few words a menu row allows; the explanation is a
sentence saying what is wrong and *why*, which is the whole reason the app shows a popup
rather than a list of replacement words. Someone who already knows the rule does not need
to right-click; someone who does not cannot act on "Should be it's" alone.

Each rule is deliberately conservative, because a false positive costs more than a missed
error: an underline under correct writing teaches people to ignore the underlines. That
rules out most of what a word processor offers -- subject/verb agreement, their/there,
its/it's -- none of which a regex can decide without guessing. A filler-word rule was
written and then removed when its own test caught it firing on "he said quite clearly".

**Function words and contractions.** 143 hand-written glosses for the words WordNet structurally cannot hold.
It is organised as four networks -- nouns, verbs, adjectives, adverbs -- and has nothing at
all for "the", "of", "although" or "which". Those are the commonest words in English and so
the ones a reader is likeliest to select, which made the gap look like a broken feature
rather than a boundary of the data. Each says what the word *does* in a sentence, because
that is what these words have instead of a meaning. They replace WordNet's entry where there
is one, since "will" as willpower is not the sense anyone selecting it means.

Contractions are here for the same reason -- both halves of one are function words, so
WordNet holds none of them. The negatives are spelled out rather than left to reduce to
their base verb: "wouldn't" reducing to "would" is true and useless, because it drops the
negation that is the whole reason the word is there.

A typographic apostrophe is folded to a plain one before any lookup. A text field that
substitutes U+2019 as you type -- which macOS does by default -- otherwise makes every
contraction unfindable, since the data is keyed with the plain form.

**Words written as two.** 21 rules for compounds split in half -- "my self", "some where",
"with out", "them selves". These need a rule rather than the dictionary, and that is the whole
point of them: "my self" is two perfectly good words, so no wordlist can object to it however
large. The risk runs the other way from most rules here -- the danger is that the split form
is *also* a phrase somewhere -- so each is either a pair with no valid reading apart, or is
guarded against the reading it has. "My self-esteem", "every body in the room", "would be
cause for concern" and "parked in side streets" are all in the corpus for that reason.

**Unpaired brackets and quotes.** A bracket that is never closed, a closer with nothing
open, a mismatched pair, an odd number of double quotes. A counting check rather than a
matching one, and the only one of those that is an error: an unclosed bracket is not a matter
of taste, and the reader of the post sees it too. It reports the position rather than the
imbalance, because in a long post finding it is most of the work.

Code and emoticons are skipped. A fenced block or an inline span is full of brackets that
balance in a language this knows nothing about, and `:)` is a closing bracket with nothing
open -- flagging that would be the single most annoying thing this plugin does. The
apostrophe is not counted at all: it is the same character as a single quote, and "don't"
would leave every message unbalanced.

**Commas and the marks around them.** Most of what people mean by "check my commas" is not
decidable by pattern matching. Whether a clause is restrictive, whether two halves of a
sentence are independent, whether a list wants a serial comma -- each needs to know what the
sentence *is*, not what it looks like. Comma splices in particular are indistinguishable from
a correctly punctuated introductory phrase, which is why they are absent.

What is decidable is a comma's own position: against a full stop, inside a bracket it does
not belong to, run into the quote after it. Plus the one missing comma that is not a
judgement call -- after a conjunctive adverb opening a sentence, where no other reading
exists. "However" and "Similarly" are deliberately excluded from that list, because "However
you do it, it works" and "Similarly designed products failed" are both correct and both would
be broken by a comma. Numbers run through all of it: "1,000", "3:00" and "v1.2.3" are correct
and common, so every rule is written to leave them alone.

**Proper nouns.** Days, months, languages and nationalities take a capital wherever they
appear, and the dictionary cannot help: "monday" and "english" are both in it, because the
wordlist is lowercased when it is built. So the checker saw a word it knew and said nothing.

The whole difficulty is which words are safe. A proper noun that is also an ordinary word
cannot be corrected without knowing what the sentence means, so **March, May and August are
absent** -- "we march on Friday", "it may rain" and "an august institution" are all correct.
So are polish, welsh, czech and thai, and every bare country name, since china, turkey, chile
and jersey are ordinary words too. The survivors that have a common-noun sense in some
phrase are guarded by an antipattern instead: french fries, roman numerals, a dutch oven,
turkish delight. A checker with an opinion on whether "french fries" wants a capital is a
checker arguing with its user about lunch.

**"A" against "an".** The rule everybody knows -- "an" before a vowel -- is about *sound*,
and spelling only mostly agrees with it: "a unique opportunity" and "an hour" are both
correct and both break it as usually stated. Nothing here can hear anything, so the letters
decide and the exceptions are listed -- which makes this the clearest case in the plugin for
antipatterns. The rule is one line and the interesting part is entirely the two lists it must
not touch: the "yoo" words (unique, uniform, university, euro, European), the silent-h words
(hour, honest, heir), and the initialisms whose letter *names* start with a vowel (an MBA, an
X-ray).

The trap in the first list is that "uni" is not the test. "Unimportant" and "uninteresting"
open the same way on paper and take "an", so the stems are spelled out rather than shortened.

**Confusable pairs.** 290 rules covering then/than, lose/loose, affect/effect, your/you're,
to/too, whose/who's, their/they're, brake/break, passed/past, quiet/quite, accept/except,
breath/breathe and the past participles after have/has/had. LanguageTool decides the general
case with ngram frequency data -- given "more money then you", it knows "money than you" is
the commoner trigram -- which is gigabytes and out of the question here. What is possible
without any of it is the decidable slice: positions where only one of the pair can be right
whatever the sentence is about. "Than" cannot follow "and"; a possessive cannot precede a
verb; "apart of" is never a phrase.

The your/you're rule is the shape of the work. It began with sixteen words and finished with
four, because almost everything that reads as an adjective after "you're" also reads as
something ownable after "your": your right (to refuse), your correct address, your late
payment, your invited guests, your amazing work. Each of those is now a line in the corpus.

Its companion covers the position that list never could: `your` before an `-ing` word, and
the same rule for `their`, `there` and `whose`. A possessive cannot own an action in
progress, so the rule keys on the shape rather than on which word follows. Two readings keep
it honest. The fused participle is correct English and is exactly this shape -- "your talking
is distracting me", "their leaving was sudden" -- and is excluded by what comes *after* the
`-ing` word, since a phrase acting as a subject is followed by the verb it is the subject of.
And the `-ing` words that are ordinary possessed nouns -- your writing, your reading list,
their training, whose cooking -- are left out of the shared list entirely. WordNet is no help
here, unusually: it gives almost every `-ing` form a noun sense, so the part-of-speech test
that settles advice/advise says nothing at all about this one.

brake/break is the other shape. Both words are a noun and a verb, so part of speech cannot
separate them either; what decides it is the company each keeps. The device is named in fixed
compounds (hand brake, disc brake) and operated by fixed verbs (hit, press, slam on); the
pause is taken rather than pressed. The trap is "breaks" the ordinary verb -- "the disc
breaks under load", "the car breaks down", "their breaks are too short" are all correct and
all sit in the shape the rules look for, which is why none of them matches a bare possessive
and the compound rules are singular only.

**Wordiness and cliches.** 106 suggestions, from a table of phrase pairs -- "in the event
that" to "if", "each and every" to "each" -- plus 25 phrases worn smooth by overuse, flagged
with no replacement because proposing one would be a worse cliche than the original. Their
first letter matches in either case, since the commonest place for "Due to the fact that" is
the start of a sentence, where a case-sensitive pattern would never fire.

**Passive voice.** Two rules, both requiring proof. One needs a named agent ("was written by
someone else"); the other needs "being" before a participle ("is being considered"). Most
passive writing names no agent and goes unflagged, which is the price of never flagging "I
was interested" -- an `-ed` word after "was" is far more often an adjective than a verb.

**Analysis checks.** Four checks a regex cannot express, because they count: a word used
four or more times in one paragraph, a sentence over thirty words, three consecutive
sentences opening with the same word, and both spellings of a pair in one message. 56 pairs: the
British-against-American ones (organise/organize, colour/color), and the forms that are both
correct in the same English and still should not be mixed -- email/e-mail, cooperate/
co-operate, percent/per cent. The two lists are kept apart because the first is also what the
thesaurus reduces a British spelling through to reach WordNet, and "email" is not a locale. The plugin declares these rather than implementing them -- it
names a check the app knows how to run and supplies the threshold, the wording and the
explanation. Same division as the regexes, which the plugin also writes and never executes.
An app that does not implement an id ignores it, so a check can ship here first.

**Definitions.** 77,549 words and 111,303 meanings, condensed from WordNet 3.1. Up to
three meanings per word, each labelled with its part of speech, with WordNet's usage
examples dropped -- a menu has room for what the word means and not for a paragraph
demonstrating it.

They are returned alongside the synonyms and kept deliberately separate from them, never
paired up. The two datasets divide a word into different senses, so saying which meaning
went with which group of synonyms would mean guessing, and a wrong guess reads as
confidently wrong rather than merely unhelpful.

**Synonyms.** 62,959 words, condensed from the MyThes/WordNet thesaurus. Senses are kept
apart -- "bank" as a place to keep money is listed separately from its river sense --
because pooling them is what makes a thesaurus give confidently wrong advice. Antonyms are
included and marked.

**Lemmatisation.** Both datasets are keyed by base forms only -- "cat" and not "cats",
"run" and not "running" -- which on its own leaves two thirds of the dictionary with nothing
to look up. Measured against the 121,115-word dictionary, a direct lookup answers for 36% of
it. Reducing the word first takes that to **86%**.

The rules are WordNet's own Morphy: suffix detachments per part of speech, plus the
irregular-form lists that ship with WordNet for the words no rule reaches -- went/go,
children/child, better/good, mice/mouse. Possessives are stripped first, since 27,000 of the
dictionary's entries are one. Every candidate is checked against the data before it is
accepted, so an over-eager rule costs nothing: "sing" does not become "s".

The 16,000 words still unanswered are mostly proper nouns SCOWL carries and WordNet does not
gloss -- Canaveral, Mississauga, Bertha -- plus a tail of rare words WordNet simply lacks.
That is a limit of the source, not of the lookup.

Unlike the dictionary and the rules, none of this is handed to the app: the datasets are
10MB, far too much to push across for a feature used a word at a time, so the plugin keeps it and answers
lookups. It is not fully parsed either -- the generated file is sorted, so a lookup binary-
searches line offsets and parses only the line it lands on, keeping the resident cost inside
the wasm instance to a few hundred KB rather than tens of megabytes.

Synonym ranking follows how safely a word substitutes. MyThes marks its cross-references,
and they do not all mean the same thing: `(generic term)` is a hypernym and never a
replacement (offering "city" for "Hague" changes what the sentence says), while
`(similar term)` and `(related term)` usually are -- and for many adjectives are the *only*
ones, since the direct synonym list is empty. A first version dropped all three and left
"happy" with felicitous, glad and well-chosen while discarding cheerful, contented and
blissful.

## Languages

Two: **English (UK)** and **English (US)**, chosen in Settings > Plugins. A language
is a different word list rather than a filter over one -- "colour" is in the British list
and "color" in the American, and each is a misspelling in the other -- so switching goes
back to the plugin for a fresh dictionary.

The lists come from [SCOWL](http://wordlist.sourceforge.net), which publishes plain lists
of surface forms split by how common each word is and by which English uses it. Everyone
gets `english-`, and then either `american-` or `british-`, up to frequency tier 60. Both
land at roughly 120,000 words.

An earlier version expanded a hunspell dictionary instead -- roots plus affix flags,
`abandon/LDGS` into the five words that spells. That worked for the American dictionary,
whose affix file has 73 rules, and produced nonsense for the British one, whose 1,362 rules
include productive derivational affixes that hunspell constrains in ways this plugin's
expander did not: `underwearisable`, `overnazismativeness`, `miscorporativismativeness`.
Reimplementing hunspell correctly is a real project and not this one; SCOWL's lists need no
engine at all. The American list changed by 1% in the move, almost all of it obscure, and
gained the accented words that were previously dropped rather than folded -- `melee`,
`emigre`, `confreres`.

WordNet and MyThes are both American, so a British spelling has no definition or synonyms
of its own. Lookups reduce it first, using the same variant table the consistency check is
built from, so "colour" and "organised" still answer.

## Regenerating the data

The generated `.gz` files are committed, so building needs neither the tools
nor the corpora. They are kept so the lists are reproducible and auditable
rather than opaque blobs.

The corpora themselves are **not** committed -- WordNet, SCOWL and MyThes come
to 46MB, and they are read only when a dataset is regenerated. Download them
into `data/` first (see *Data licences and attribution* below for where each
comes from): `data/wordnet/`, `data/scowl/` and `data/th_en_US_v2.dat`. The two
hand-written files in `data/` -- `extra-words.txt` and `function-words.txt` --
are committed, since nothing can regenerate those.

```sh
go run ./tools/mkwords -locale en-US > words-en-US.txt
go run ./tools/mkwords -locale en-GB > words-en-GB.txt
go run ./tools/mkthesaurus > thesaurus.txt
go run ./tools/mkdefs > definitions.txt
go run ./tools/mkexceptions > exceptions.txt
./build.sh          # recompresses whichever changed, then compiles
```

Only the compressed `.gz` files are committed -- they are what `main.go` embeds, and
keeping the plain text alongside them would be the same data twice, free to drift. To read
one:

```sh
gunzip -c words.txt.gz | grep '^decred$'
```

## Data licences and attribution

The **dictionaries** are SCOWL's own word lists, [SCOWL](http://wordlist.sourceforge.net)
Copyright 2000-2018 Kevin Atkinson. Full text: **`data/LICENSE-SCOWL`**.

The **thesaurus** is the MyThes `th_en_US_v2` data shipped with LibreOffice, derived from
[WordNet](https://wordnet.princeton.edu), WordNet 2.1 Copyright 2005 Princeton University.
Full text: **`data/LICENSE-WORDNET`**.

The **definitions** are from [WordNet](https://wordnet.princeton.edu) 3.1, Copyright 2011
Princeton University. Full text: **`data/LICENSE-WORDNET31`**.

All three permit use, modification and redistribution provided the copyright and permission
notices travel with them. Those notices ship in this repository and must stay with any
redistribution of `words.txt`, `thesaurus.txt`, `definitions.txt`, or a `plugin.wasm` built
from them.

## Building

Requires Go 1.24+ (for `go:wasmexport`) -- no TinyGo, no cgo.

```sh
./build.sh
```

That compiles `plugin.wasm` and then embeds it, gzipped, at
`client/pluginmgr/builtin/writingtools.wasm.gz` along with the manifest. Both
steps matter: `plugin.wasm` in this directory is a build artefact that nothing
reads, and a build stopping there reaches nobody.

The client is Go, so the app has to be rebuilt before a new rule reaches a
running copy:

```sh
./build.sh && ../../bruig/build_desktop.sh run
```

There is no zip to import and no switch to flip. A built-in is present because
the client ships it, and cannot be removed -- see the package doc in
`client/pluginmgr/builtin/builtin.go` for what that does and does not buy it.

## Layout

- `main.go` -- the WebAssembly exports, and nothing else: `alloc` (required of every
  dynamic-wasm plugin) and `get_spellcheck_data` (the one capability export this plugin
  implements). See `client/pluginmgr/wasmhost`'s package doc in the main bisonrelay repo
  for the full ABI reference.
- `spellcheck/spellcheck.go` -- the error rules and the wordlist parser.
- `spellcheck/rules_confusions.go` -- the confusable pairs, each in the one position where
  the right word is not a matter of opinion.
- `spellcheck/rules_style.go` -- the opinions: the wordiness table, the cliche list, the two
  passive-voice rules, and the British/American spelling pairs.
- `spellcheck/analysis.go` -- the nine declared checks that count rather than
  match: repetition, sentence length, mixed spellings, unpaired brackets and
  the date checks.
- `spellcheck/rules_checks.go` and `spellcheck/rules_commas.go` -- the check
  tier: the confusable pairs and the commas no expression over words can
  settle.
- `spellcheck/rules_redundancy.go`, `rules_inclusive.go`,
  `rules_typography.go` -- three tables and a loop each.
- `spellcheck/` -- the plugin's actual content: the grammar rules and the wordlist parser,
  as ordinary Go so they can be tested without building for wasm. Nothing here matches
  anything; the rules are regex *source*, executed by Dart in the app, whose engine
  (unlike Go's RE2) supports the backreferences a rule like "repeated word" needs.
- `thesaurus/` -- the synonym and definition lookup: a binary search over each generated
  file's line offsets, parsing one entry at a time. The two datasets are searched
  independently, so a word in one and not the other still produces an answer.
- `thesaurus/morphy.go` -- reduces a word as typed to the base form the data is keyed by.
- `words-en-US.txt.gz`, `words-en-GB.txt.gz`, `common-en-US.txt.gz`,
  `common-en-GB.txt.gz`, `thesaurus.txt.gz`, `definitions.txt.gz`,
  `exceptions.txt.gz`, `inflections.txt.gz` -- the
  generated datasets, embedded compressed via `//go:embed` and decompressed on first use.
  Together they are 11MB of text and 3.6MB compressed, which is the difference between a
  15MB module and a 7MB one. It costs nothing at runtime that was not already paid:
  `//go:embed` puts the data in linear memory either way.
- `data/scowl/` -- SCOWL's curated word lists, one file per variant and frequency tier.
- `data/` -- the other sources: the supplemental vocabulary, the function-word and
  contraction glosses, the MyThes and WordNet data, and every licence.
- `tools/mkwords/` -- builds one language's `words-*.txt` and `common-*.txt` from
  `data/scowl`.
- `tools/mkthesaurus/` -- condenses the MyThes source into `thesaurus.txt`.
- `tools/mkdefs/` -- condenses WordNet's `data.*` files into `definitions.txt`, merging
  `data/function-words.txt` over the top.
- `tools/mkexceptions/` -- merges WordNet's four irregular-inflection lists into
  `exceptions.txt`.
