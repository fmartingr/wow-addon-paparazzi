package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func copyTree(t *testing.T, src, dst string) {
	t.Helper()
	err := filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, path)
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, data, 0o644)
	})
	if err != nil {
		t.Fatal(err)
	}
}

func fixture(t *testing.T) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "wow")
	copyTree(t, "../../testdata/wow", dir)
	return dir
}

func exec(args ...string) (code int, stdout, stderr string) {
	var out, errOut bytes.Buffer
	code = run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestRunWritesSidecars(t *testing.T) {
	dir := fixture(t)
	code, stdout, stderr := exec("--wow-dir", dir)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, stderr)
	}
	if got := strings.TrimSpace(stdout); got != "written=2 skipped=0 unmatched=1 ambiguous=0" {
		t.Fatalf("summary %q", got)
	}
	for _, want := range []string{"unsupported schema", "invalid file name", "no screenshot for WoWScrnShot_103126_202502.jpg"} {
		if !strings.Contains(stderr, want) {
			t.Errorf("stderr misses %q:\n%s", want, stderr)
		}
	}

	exact, err := os.ReadFile(filepath.Join(dir, "Screenshots", "WoWScrnShot_103126_201502.json"))
	if err != nil {
		t.Fatal(err)
	}
	var record map[string]any
	if err := json.Unmarshal(exact, &record); err != nil {
		t.Fatal(err)
	}
	if record["file"] != "WoWScrnShot_103126_201502.jpg" || record["schema"] != float64(1) {
		t.Errorf("unexpected record: %v", record)
	}
	events := record["events"].([]any)
	if events[0].(map[string]any)["trigger"] != "levelUp" {
		t.Errorf("unexpected events: %v", events)
	}
	if _, err := os.Stat(filepath.Join(dir, "Screenshots", "WoWScrnShot_103126_201603.json")); err != nil {
		t.Errorf("the nearest match has no sidecar: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "Screenshots", "WoWScrnShot_103126_220000.json")); err == nil {
		t.Error("a screenshot without a capture got a sidecar")
	}
}

func TestRunSecondRunSkips(t *testing.T) {
	dir := fixture(t)
	exec("--wow-dir", dir)
	code, stdout, _ := exec("--wow-dir", dir)
	if code != 0 || strings.TrimSpace(stdout) != "written=0 skipped=2 unmatched=1 ambiguous=0" {
		t.Fatalf("exit %d: %q", code, stdout)
	}
	code, stdout, _ = exec("--wow-dir", dir, "--force")
	if code != 0 || !strings.HasPrefix(stdout, "written=2 ") {
		t.Fatalf("exit %d: %q", code, stdout)
	}
}

func TestRunDryRun(t *testing.T) {
	dir := fixture(t)
	code, stdout, _ := exec("--wow-dir", dir, "--dry-run")
	if code != 0 || !strings.HasPrefix(stdout, "written=2 ") {
		t.Fatalf("exit %d: %q", code, stdout)
	}
	matches, _ := filepath.Glob(filepath.Join(dir, "Screenshots", "*.json"))
	if len(matches) != 0 {
		t.Fatalf("dry run wrote %v", matches)
	}
}

func TestRunAccountAndScreenshotsFlags(t *testing.T) {
	dir := fixture(t)
	other := filepath.Join(t.TempDir(), "shots")
	copyTree(t, filepath.Join(dir, "Screenshots"), other)
	code, stdout, stderr := exec("--wow-dir", dir, "--account", "TEST", "--screenshots", other, "--tolerance", "0s")
	if code != 0 {
		t.Fatalf("exit %d: %s", code, stderr)
	}
	if !strings.HasPrefix(stdout, "written=1 ") {
		t.Fatalf("a zero tolerance must keep only the exact match: %q", stdout)
	}
	if code, _, _ := exec("--wow-dir", dir, "--account", "NOPE"); code != 1 {
		t.Errorf("unknown account: exit %d", code)
	}
}

func TestRunSeveralAccounts(t *testing.T) {
	dir := fixture(t)
	second := filepath.Join(dir, "WTF", "Account", "OTHER", "SavedVariables")
	if err := os.MkdirAll(second, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(second, "Paparazzi.lua"), []byte("PaparazziDB = { captures = {} }"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, stdout, _ := exec("--wow-dir", dir)
	if code != 0 || !strings.HasPrefix(stdout, "written=2 ") {
		t.Fatalf("exit %d: %q", code, stdout)
	}
}

func TestRunErrors(t *testing.T) {
	dir := fixture(t)
	if err := os.RemoveAll(filepath.Join(dir, "Screenshots")); err != nil {
		t.Fatal(err)
	}
	if code, _, stderr := exec("--wow-dir", dir); code != 1 || !strings.Contains(stderr, "screenshots folder") {
		t.Errorf("missing screenshots folder: exit %d: %s", code, stderr)
	}

	empty := t.TempDir()
	if code, _, _ := exec("--wow-dir", empty); code != 1 {
		t.Errorf("no SavedVariables: exit %d", code)
	}

	broken := fixture(t)
	db := filepath.Join(broken, "WTF", "Account", "TEST", "SavedVariables", "Paparazzi.lua")
	if err := os.WriteFile(db, []byte("PaparazziDB = @"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := exec("--wow-dir", broken); code != 1 {
		t.Errorf("parse error: exit %d", code)
	}

	readonly := fixture(t)
	shots := filepath.Join(readonly, "Screenshots")
	if err := os.Chmod(shots, 0o555); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(shots, 0o755)
	if os.Geteuid() != 0 {
		if code, _, _ := exec("--wow-dir", readonly); code != 1 {
			t.Errorf("write error: exit %d", code)
		}
	}
}

func TestRunUsage(t *testing.T) {
	for _, args := range [][]string{
		{},
		{"--bogus"},
		{"--wow-dir", "x", "extra"},
		{"--wow-dir", "x", "--account", "../x"},
		{"--wow-dir", "x", "--account", ".."},
	} {
		if code, _, _ := exec(args...); code != 2 {
			t.Errorf("%v: exit %d, want 2", args, code)
		}
	}
}

func TestRunVersion(t *testing.T) {
	code, stdout, _ := exec("--version")
	if code != 0 || strings.TrimSpace(stdout) != version {
		t.Fatalf("exit %d: %q", code, stdout)
	}
}
