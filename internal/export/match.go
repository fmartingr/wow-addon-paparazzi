package export

import (
	"sort"
	"time"
)

const fileTimeLayout = "010206_150405"

// Pair joins a capture to the screenshot file that it describes.
type Pair struct {
	Capture Capture
	File    string
}

// Result is the outcome of Match.
type Result struct {
	Pairs     []Pair
	Unmatched []Capture
	Ambiguous []Capture
}

func fileTime(name string, offset int64) (time.Time, bool) {
	if len(name) < len("WoWScrnShot_")+len(fileTimeLayout) {
		return time.Time{}, false
	}
	stamp := name[len("WoWScrnShot_") : len("WoWScrnShot_")+len(fileTimeLayout)]
	t, err := time.ParseInLocation(fileTimeLayout, stamp, time.FixedZone("", int(offset)))
	return t, err == nil
}

type candidate struct {
	capture int
	file    int
	dist    time.Duration
}

// Match pairs captures with screenshot file names.
// It tries the exact predicted name first. Then it takes the nearest unclaimed file within tol.
func Match(captures []Capture, files []string, tol time.Duration) Result {
	sorted := append([]Capture(nil), captures...)
	sort.SliceStable(sorted, func(i, j int) bool { return sorted[i].Unix < sorted[j].Unix })

	var result Result
	claimed := make(map[string]bool, len(files))
	exists := make(map[string]bool, len(files))
	for _, f := range files {
		exists[f] = true
	}

	done := make([]bool, len(sorted))
	for i, c := range sorted {
		if exists[c.File] && !claimed[c.File] {
			claimed[c.File] = true
			done[i] = true
			result.Pairs = append(result.Pairs, Pair{Capture: c, File: c.File})
		}
	}

	var candidates []candidate
	for i, c := range sorted {
		if done[i] {
			continue
		}
		for j, f := range files {
			if claimed[f] {
				continue
			}
			ft, ok := fileTime(f, c.UtcOffset)
			if !ok {
				continue
			}
			dist := time.Duration(ft.Unix()-c.Unix) * time.Second
			if dist < 0 {
				dist = -dist
			}
			if dist <= tol {
				candidates = append(candidates, candidate{capture: i, file: j, dist: dist})
			}
		}
	}
	sort.SliceStable(candidates, func(a, b int) bool { return candidates[a].dist < candidates[b].dist })

	for _, cand := range candidates {
		if done[cand.capture] || claimed[files[cand.file]] {
			continue
		}
		done[cand.capture] = true
		if tied(candidates, cand, claimed, files) {
			result.Ambiguous = append(result.Ambiguous, sorted[cand.capture])
			continue
		}
		claimed[files[cand.file]] = true
		result.Pairs = append(result.Pairs, Pair{Capture: sorted[cand.capture], File: files[cand.file]})
	}

	for i, c := range sorted {
		if !done[i] {
			result.Unmatched = append(result.Unmatched, c)
		}
	}
	return result
}

func tied(all []candidate, best candidate, claimed map[string]bool, files []string) bool {
	for _, other := range all {
		if other.capture == best.capture && other.file != best.file && other.dist == best.dist && !claimed[files[other.file]] {
			return true
		}
	}
	return false
}
