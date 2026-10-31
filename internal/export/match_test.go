package export

import (
	"testing"
	"time"
)

func capture(file string, unix, offset int64) Capture {
	return Capture{File: file, Unix: unix, UtcOffset: offset}
}

// 2026-10-31 20:15:02 at UTC+1.
const base = int64(1793474102)

func files(names ...string) []string { return names }

func TestMatchExact(t *testing.T) {
	r := Match([]Capture{capture("WoWScrnShot_103126_201502.jpg", base, 3600)},
		files("WoWScrnShot_103126_201502.jpg"), 2*time.Second)
	if len(r.Pairs) != 1 || r.Pairs[0].File != "WoWScrnShot_103126_201502.jpg" {
		t.Fatalf("got %+v", r)
	}
}

func TestMatchNearest(t *testing.T) {
	tests := []struct {
		name    string
		file    string
		matched bool
	}{
		{"one second late", "WoWScrnShot_103126_201503.jpg", true},
		{"one second early", "WoWScrnShot_103126_201501.jpg", true},
		{"two seconds", "WoWScrnShot_103126_201504.jpg", true},
		{"three seconds", "WoWScrnShot_103126_201505.jpg", false},
		{"other extension", "WoWScrnShot_103126_201502.png", true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := Match([]Capture{capture("WoWScrnShot_103126_201502.jpg", base, 3600)}, files(tc.file), 2*time.Second)
			if got := len(r.Pairs) == 1; got != tc.matched {
				t.Fatalf("matched=%v, want %v (%+v)", got, tc.matched, r)
			}
			if !tc.matched && len(r.Unmatched) != 1 {
				t.Fatalf("expected an unmatched capture: %+v", r)
			}
		})
	}
}

func TestMatchTieIsAmbiguous(t *testing.T) {
	r := Match([]Capture{capture("WoWScrnShot_103126_201502.jpg", base, 3600)},
		files("WoWScrnShot_103126_201501.jpg", "WoWScrnShot_103126_201503.jpg"), 2*time.Second)
	if len(r.Ambiguous) != 1 || len(r.Pairs) != 0 {
		t.Fatalf("got %+v", r)
	}
}

func TestMatchFileClaimedOnce(t *testing.T) {
	a := capture("WoWScrnShot_103126_201502.jpg", base, 3600)
	b := capture("WoWScrnShot_103126_201503.jpg", base+1, 3600)
	r := Match([]Capture{b, a}, files("WoWScrnShot_103126_201502.jpg"), 2*time.Second)
	if len(r.Pairs) != 1 || r.Pairs[0].Capture.File != a.File {
		t.Fatalf("got %+v", r)
	}
	if len(r.Unmatched) != 1 || r.Unmatched[0].File != b.File {
		t.Fatalf("got %+v", r)
	}
}

func TestMatchNearestWinsContention(t *testing.T) {
	near := capture("WoWScrnShot_103126_201502.jpg", base, 3600)
	far := capture("WoWScrnShot_103126_201500.jpg", base-2, 3600)
	r := Match([]Capture{far, near}, files("WoWScrnShot_103126_201503.jpg"), 2*time.Second)
	if len(r.Pairs) != 1 || r.Pairs[0].Capture.File != near.File {
		t.Fatalf("got %+v", r)
	}
}

func TestMatchUsesRecordOffset(t *testing.T) {
	// The same instant at UTC-5 reads 14:15:02 in the file name.
	c := capture("WoWScrnShot_103126_141503.jpg", base, -18000)
	r := Match([]Capture{c}, files("WoWScrnShot_103126_141502.jpg"), 2*time.Second)
	if len(r.Pairs) != 1 {
		t.Fatalf("got %+v", r)
	}
	r = Match([]Capture{c}, files("WoWScrnShot_103126_201502.jpg"), 2*time.Second)
	if len(r.Pairs) != 0 {
		t.Fatalf("the machine zone must not matter: %+v", r)
	}
}

func TestMatchIgnoresBadFileNames(t *testing.T) {
	r := Match([]Capture{capture("WoWScrnShot_103126_201502.jpg", base, 3600)},
		files("WoWScrnShot_x.jpg", "WoWScrnShot_999999_999999.jpg"), 2*time.Second)
	if len(r.Pairs) != 0 || len(r.Unmatched) != 1 {
		t.Fatalf("got %+v", r)
	}
}

func TestMatchDoesNotChangeInput(t *testing.T) {
	in := []Capture{capture("b", 2, 0), capture("a", 1, 0)}
	Match(in, nil, time.Second)
	if in[0].File != "b" {
		t.Fatal("input order changed")
	}
}
