package export

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Status tells what Write did.
type Status int

const (
	Written Status = iota
	Skipped
)

// Write stores the capture of a pair as a JSON file next to its image.
// It never opens an image.
func Write(dir string, pair Pair, force, dryRun bool) (Status, error) {
	if !FileNamePattern.MatchString(pair.File) {
		return Skipped, fmt.Errorf("invalid file name %q", pair.File)
	}
	target := filepath.Join(dir, strings.TrimSuffix(pair.File, filepath.Ext(pair.File))+".json")
	if _, err := os.Stat(target); err == nil && !force {
		return Skipped, nil
	}
	if dryRun {
		return Written, nil
	}

	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(pair.Capture.Raw); err != nil {
		return Skipped, err
	}

	tmp, err := os.CreateTemp(dir, ".paparazzi-*.tmp")
	if err != nil {
		return Skipped, err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(buf.Bytes()); err != nil {
		tmp.Close()
		return Skipped, err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return Skipped, err
	}
	if err := tmp.Close(); err != nil {
		return Skipped, err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return Skipped, err
	}
	if err := os.Rename(tmp.Name(), target); err != nil {
		return Skipped, err
	}
	return Written, nil
}
