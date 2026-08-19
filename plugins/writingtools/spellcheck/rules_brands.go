package spellcheck

import "strings"

// rules_brands.go capitalises the names that carry a capital in the middle,
// or in the case of "iOS" at the start of a word that then goes up.
//
// The dictionary cannot help, for exactly the reason it cannot help with
// weekdays: the wordlist is lowercased when it is built, so "github" is a
// word the checker knows and says nothing about. This is the same problem as
// rules_propernouns.go and is kept in its own file because the failure mode
// is different -- a weekday is wrong in one way, and a product name can be
// wrong in several, "Github" and "GITHUB" as well as "github".
//
// What is *not* here is the long tail, and the omissions are the interesting
// part. Every name below has no ordinary-word reading at all. That rules out
// Apple, Windows, Word, Excel, Teams, Zoom, Slack, Signal, Discord, Chrome,
// Safari, Edge, Square, Oracle, Amazon, Swift, Rust, Python, Go and Android
// -- every one of which is a common noun, an adjective or a verb before it
// is a product, and none of which can be corrected without knowing which was
// meant.
//
// Bitcoin is absent on different grounds: "bitcoin" the unit is
// conventionally lowercase and "Bitcoin" the network is not, so both
// spellings are right and only the sentence says which.

const explainBrand = "This is a product name, and it is spelled with " +
	"capitals inside it. Names are spelled the way their owners spell them, " +
	"which is why it is \"GitHub\" and not \"Github\"."

// brands are product names whose canonical spelling is not what an ordinary
// capitalisation would produce.
//
// Only the canonical form is listed. The spellings each rule catches are
// derived from it below, so a name cannot be added with its own misspellings
// typed wrongly beside it -- which, on a list of this shape, is the mistake
// that would actually happen.
var brands = []string{
	// Developer tools and services.
	"GitHub", "GitLab", "JavaScript", "TypeScript", "PostgreSQL", "MySQL",
	"SQLite", "MongoDB", "GraphQL", "Kubernetes", "DevOps", "OAuth",
	// Platforms and operating systems.
	"macOS", "iOS", "iPadOS", "iPhone", "iPad", "MacBook", "Linux", "Ubuntu",
	"Debian", "Bluetooth", "PowerShell",
	// Sites and applications.
	"YouTube", "WhatsApp", "LinkedIn", "PayPal", "eBay", "WordPress",
	"Reddit", "Instagram", "Facebook", "TikTok", "Netflix", "Spotify",
	"Dropbox", "Wikipedia", "Photoshop", "PowerPoint", "OneDrive",
	"SharePoint", "Firefox", "Thunderbird",
	// The rooms this app is actually used in.
	"Decred", "Ethereum", "Monero", "Litecoin", "Dogecoin",
}

var brandRules = buildBrandRules()

func buildBrandRules() []GrammarRule {
	rules := make([]GrammarRule, 0, len(brands))
	for _, name := range brands {
		wrong := wrongCasings(name)
		if len(wrong) == 0 {
			continue
		}
		rules = append(rules, GrammarRule{
			Pattern:     `\b(?:` + strings.Join(wrong, "|") + `)\b`,
			Message:     "Should be \"" + name + "\"",
			Suggest:     name,
			Flags:       []string{"we moved it to " + wrong[0] + " last week"},
			Leaves:      []string{"we moved it to " + name + " last week"},
			Category:    "Capitalization",
			Explanation: explainBrand,
		})
	}
	return rules
}
