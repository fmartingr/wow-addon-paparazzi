// Package export turns Paparazzi capture records into JSON sidecar files.
package export

import (
	"fmt"
	"os"
	"regexp"
	"sort"

	"github.com/fmartingr/wow-addon-paparazzi/internal/savedvars"
)

// FileNamePattern is the only form of file name that the exporter accepts.
var FileNamePattern = regexp.MustCompile(`^WoWScrnShot_\d{6}_\d{6}\.(jpg|png|tga)$`)

// Capture is one record of PaparazziDB.captures.
type Capture struct {
	Raw       map[string]any
	File      string
	Unix      int64
	UtcOffset int64
}

func toInt(v any) (int64, bool) {
	switch n := v.(type) {
	case int64:
		return n, true
	case float64:
		return int64(n), n == float64(int64(n))
	}
	return 0, false
}

// LoadCaptures reads the captures of one SavedVariables file.
// It returns a warning for each record that it skips.
func LoadCaptures(dbFile string) ([]Capture, []string, error) {
	f, err := os.Open(dbFile)
	if err != nil {
		return nil, nil, err
	}
	defer f.Close()

	vars, err := savedvars.Parse(f)
	if err != nil {
		return nil, nil, fmt.Errorf("%s: %w", dbFile, err)
	}
	return capturesFrom(dbFile, vars)
}

func capturesFrom(source string, vars map[string]any) ([]Capture, []string, error) {
	db, ok := vars["PaparazziDB"].(map[string]any)
	if !ok {
		return nil, nil, nil
	}

	var records []any
	switch list := db["captures"].(type) {
	case nil:
		return nil, nil, nil
	case []any:
		records = list
	case map[string]any:
		if len(list) > 0 {
			return nil, nil, fmt.Errorf("%s: captures is not a list", source)
		}
	default:
		return nil, nil, fmt.Errorf("%s: captures is not a list", source)
	}

	var captures []Capture
	var warnings []string
	for i, item := range records {
		capture, warning := newCapture(item)
		if warning != "" {
			warnings = append(warnings, fmt.Sprintf("%s: capture %d: %s", source, i+1, warning))
			continue
		}
		captures = append(captures, capture)
	}
	sort.SliceStable(captures, func(i, j int) bool { return captures[i].Unix < captures[j].Unix })
	return captures, warnings, nil
}

func newCapture(item any) (Capture, string) {
	raw, ok := item.(map[string]any)
	if !ok {
		return Capture{}, "record is not a table"
	}
	if schema, _ := toInt(raw["schema"]); schema != 1 {
		return Capture{}, fmt.Sprintf("unsupported schema %v", raw["schema"])
	}
	file, _ := raw["file"].(string)
	if !FileNamePattern.MatchString(file) {
		return Capture{}, fmt.Sprintf("invalid file name %q", file)
	}
	unix, ok := toInt(raw["unix"])
	if !ok {
		return Capture{}, "missing unix time"
	}
	offset, ok := toInt(raw["utcOffset"])
	if !ok {
		return Capture{}, "missing utcOffset"
	}
	return Capture{Raw: raw, File: file, Unix: unix, UtcOffset: offset}, ""
}
