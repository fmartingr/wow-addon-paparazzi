package export

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func newPair() Pair {
	return Pair{
		File: "WoWScrnShot_103126_201502.jpg",
		Capture: Capture{Raw: map[string]any{
			"schema": int64(1),
			"file":   "WoWScrnShot_103126_201502.jpg",
			"note":   "a <b> & c",
			"events": []any{map[string]any{"trigger": "levelUp", "data": map[string]any{"level": int64(80)}}},
		}},
	}
}

func setup(t *testing.T) (dir string, image []byte) {
	t.Helper()
	dir = t.TempDir()
	image = []byte("not really a jpeg")
	if err := os.WriteFile(filepath.Join(dir, "WoWScrnShot_103126_201502.jpg"), image, 0o644); err != nil {
		t.Fatal(err)
	}
	return dir, image
}

const wantJSON = `{
  "events": [
    {
      "data": {
        "level": 80
      },
      "trigger": "levelUp"
    }
  ],
  "file": "WoWScrnShot_103126_201502.jpg",
  "note": "a <b> & c",
  "schema": 1
}
`

func TestWriteContent(t *testing.T) {
	dir, image := setup(t)
	status, err := Write(dir, newPair(), false, false)
	if err != nil || status != Written {
		t.Fatalf("status=%v err=%v", status, err)
	}
	got, err := os.ReadFile(filepath.Join(dir, "WoWScrnShot_103126_201502.json"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != wantJSON {
		t.Fatalf("got:\n%s\nwant:\n%s", got, wantJSON)
	}
	after, _ := os.ReadFile(filepath.Join(dir, "WoWScrnShot_103126_201502.jpg"))
	if !bytes.Equal(after, image) {
		t.Fatal("the image changed")
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 2 {
		t.Fatalf("temporary files remain: %v", entries)
	}
	info, _ := os.Stat(filepath.Join(dir, "WoWScrnShot_103126_201502.json"))
	if info.Mode().Perm() != 0o644 {
		t.Errorf("mode %v", info.Mode().Perm())
	}
}

func TestWriteSkipsExistingUnlessForced(t *testing.T) {
	dir, _ := setup(t)
	target := filepath.Join(dir, "WoWScrnShot_103126_201502.json")
	if err := os.WriteFile(target, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	status, err := Write(dir, newPair(), false, false)
	if err != nil || status != Skipped {
		t.Fatalf("status=%v err=%v", status, err)
	}
	if got, _ := os.ReadFile(target); string(got) != "old" {
		t.Fatal("existing file changed")
	}
	status, err = Write(dir, newPair(), true, false)
	if err != nil || status != Written {
		t.Fatalf("status=%v err=%v", status, err)
	}
	if got, _ := os.ReadFile(target); string(got) != wantJSON {
		t.Fatal("force did not overwrite")
	}
}

func TestWriteDryRun(t *testing.T) {
	dir, _ := setup(t)
	status, err := Write(dir, newPair(), false, true)
	if err != nil || status != Written {
		t.Fatalf("status=%v err=%v", status, err)
	}
	if _, err := os.Stat(filepath.Join(dir, "WoWScrnShot_103126_201502.json")); err == nil {
		t.Fatal("dry run wrote a file")
	}
}

func TestWriteErrors(t *testing.T) {
	dir, _ := setup(t)
	bad := newPair()
	bad.File = "../WoWScrnShot_103126_201502.jpg"
	if _, err := Write(dir, bad, false, false); err == nil {
		t.Error("expected an error for a path in the file name")
	}
	if _, err := Write(filepath.Join(dir, "missing"), newPair(), false, false); err == nil {
		t.Error("expected an error for a missing folder")
	}
	unsupported := newPair()
	unsupported.Capture.Raw["bad"] = make(chan int)
	if _, err := Write(dir, unsupported, false, false); err == nil {
		t.Error("expected a marshal error")
	}
}
