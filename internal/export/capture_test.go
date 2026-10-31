package export

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeDB(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "Paparazzi.lua")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadCapturesFixture(t *testing.T) {
	captures, warnings, err := LoadCaptures("../../testdata/wow/WTF/Account/TEST/SavedVariables/Paparazzi.lua")
	if err != nil {
		t.Fatal(err)
	}
	if len(captures) != 3 {
		t.Fatalf("got %d captures, want 3", len(captures))
	}
	if len(warnings) != 2 {
		t.Fatalf("got warnings %v, want 2", warnings)
	}
	if !strings.Contains(warnings[0], "unsupported schema") || !strings.Contains(warnings[1], "invalid file name") {
		t.Errorf("unexpected warnings: %v", warnings)
	}
	first := captures[0]
	if first.File != "WoWScrnShot_103126_201502.jpg" || first.Unix != 1793474102 || first.UtcOffset != 3600 {
		t.Errorf("unexpected first capture: %+v", first)
	}
}

func TestLoadCapturesEdgeCases(t *testing.T) {
	tests := []struct {
		name string
		body string
		want int
	}{
		{"missing PaparazziDB", "Other = {}", 0},
		{"header comment only", "-- nothing\n", 0},
		{"no captures key", "PaparazziDB = {}", 0},
		{"empty captures", "PaparazziDB = { captures = {} }", 0},
		{"PaparazziDB is not a table", "PaparazziDB = 1", 0},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			captures, _, err := LoadCaptures(writeDB(t, tc.body))
			if err != nil {
				t.Fatal(err)
			}
			if len(captures) != tc.want {
				t.Fatalf("got %d captures, want %d", len(captures), tc.want)
			}
		})
	}
}

func TestLoadCapturesErrors(t *testing.T) {
	if _, _, err := LoadCaptures(filepath.Join(t.TempDir(), "missing.lua")); err == nil {
		t.Error("expected an error for a missing file")
	}
	if _, _, err := LoadCaptures(writeDB(t, "PaparazziDB = @")); err == nil {
		t.Error("expected a parse error")
	}
	if _, _, err := LoadCaptures(writeDB(t, `PaparazziDB = { captures = 5 }`)); err == nil {
		t.Error("expected an error for a captures value that is not a list")
	}
	if _, _, err := LoadCaptures(writeDB(t, `PaparazziDB = { captures = { a = 1 } }`)); err == nil {
		t.Error("expected an error for a captures map")
	}
}

func TestNewCaptureRejections(t *testing.T) {
	good := func() map[string]any {
		return map[string]any{"schema": int64(1), "file": "WoWScrnShot_103126_201502.jpg", "unix": int64(1), "utcOffset": int64(0)}
	}
	if _, w := newCapture(good()); w != "" {
		t.Fatalf("good record rejected: %s", w)
	}
	cases := map[string]func(map[string]any){
		"schema":    func(m map[string]any) { m["schema"] = int64(2) },
		"file":      func(m map[string]any) { m["file"] = "../WoWScrnShot_103126_201502.jpg" },
		"extension": func(m map[string]any) { m["file"] = "WoWScrnShot_103126_201502.exe" },
		"unix":      func(m map[string]any) { delete(m, "unix") },
		"offset":    func(m map[string]any) { m["utcOffset"] = "x" },
	}
	for name, mutate := range cases {
		m := good()
		mutate(m)
		if _, w := newCapture(m); w == "" {
			t.Errorf("%s: expected a warning", name)
		}
	}
	if _, w := newCapture("text"); w == "" {
		t.Error("expected a warning for a record that is not a table")
	}
	m := good()
	m["unix"] = 5.0
	m["utcOffset"] = 7200.0
	if c, w := newCapture(m); w != "" || c.Unix != 5 || c.UtcOffset != 7200 {
		t.Errorf("float numbers: %+v %q", c, w)
	}
	m["unix"] = 5.5
	if _, w := newCapture(m); w == "" {
		t.Error("expected a warning for a fractional time")
	}
}
