package resources

import "testing"

// pages_migration_test.go pins the name of the directory a site keeps its
// shared fragments in, and the name it used to have.
//
// Both matter. The first is what --include[name]-- resolves against and what
// a site's own directory is called on disk; the second is the only reason
// golib can find a site made before the rename and move it.

func TestFragmentsAreServedFromFragments(t *testing.T) {
	// The library folder is called Fragments, and the served directory sits
	// in the same window one folder along. Two names for one thing is what
	// somebody finds while looking for a file and cannot explain.
	if PartialsDir != "fragments" {
		t.Fatalf("fragments are served from %q", PartialsDir)
	}
	if got := PartialPath("header"); got[0] != PartialsDir ||
		got[1] != "header.md" {
		t.Fatalf("got %v", got)
	}
}

func TestTheOldNameIsRememberedOnlyToMoveIt(t *testing.T) {
	if OldPartialsDir != "partials" {
		t.Fatalf("a site made before the rename cannot be found: %q",
			OldPartialsDir)
	}
	if OldPartialsDir == PartialsDir {
		t.Fatal("the old name and the new one are the same, so nothing " +
			"would ever be moved")
	}
}
