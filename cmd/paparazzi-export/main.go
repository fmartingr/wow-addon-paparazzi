// Command paparazzi-export writes a JSON sidecar file next to each Paparazzi screenshot.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/fmartingr/wow-addon-paparazzi/internal/export"
)

var version = "dev"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("paparazzi-export", flag.ContinueOnError)
	fs.SetOutput(stderr)
	wowDir := fs.String("wow-dir", "", "WoW flavor folder, for example .../World of Warcraft/_retail_ (required)")
	account := fs.String("account", "", "account folder name (default: every account)")
	screenshots := fs.String("screenshots", "", "screenshots folder (default: <wow-dir>/Screenshots)")
	tolerance := fs.Duration("tolerance", 2*time.Second, "time window for the nearest-file match")
	force := fs.Bool("force", false, "overwrite existing .json files")
	dryRun := fs.Bool("dry-run", false, "write nothing")
	showVersion := fs.Bool("version", false, "print the version")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *showVersion {
		fmt.Fprintln(stdout, version)
		return 0
	}
	if *wowDir == "" || fs.NArg() > 0 {
		fmt.Fprintln(stderr, "usage: paparazzi-export --wow-dir <flavor dir> [flags]")
		return 2
	}
	if strings.ContainsAny(*account, `/\`) || *account == ".." {
		fmt.Fprintln(stderr, "invalid --account value")
		return 2
	}

	dbFiles, err := findDBFiles(*wowDir, *account)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	dir := *screenshots
	if dir == "" {
		dir = filepath.Join(*wowDir, "Screenshots")
	}
	files, err := listScreenshots(dir)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}

	var captures []export.Capture
	for _, db := range dbFiles {
		loaded, warnings, err := export.LoadCaptures(db)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		for _, w := range warnings {
			fmt.Fprintln(stderr, "warning:", w)
		}
		captures = append(captures, loaded...)
	}

	result := export.Match(captures, files, *tolerance)
	for _, c := range result.Unmatched {
		fmt.Fprintf(stderr, "warning: no screenshot for %s\n", c.File)
	}
	for _, c := range result.Ambiguous {
		fmt.Fprintf(stderr, "warning: several screenshots match %s, skipped\n", c.File)
	}

	written, skipped, failed := 0, 0, false
	for _, pair := range result.Pairs {
		status, err := export.Write(dir, pair, *force, *dryRun)
		if err != nil {
			fmt.Fprintln(stderr, err)
			failed = true
			continue
		}
		if status == export.Written {
			written++
		} else {
			skipped++
		}
	}
	fmt.Fprintf(stdout, "written=%d skipped=%d unmatched=%d ambiguous=%d\n",
		written, skipped, len(result.Unmatched), len(result.Ambiguous))
	if failed {
		return 1
	}
	return 0
}

func findDBFiles(wowDir, account string) ([]string, error) {
	accountsDir := filepath.Join(wowDir, "WTF", "Account")
	entries, err := os.ReadDir(accountsDir)
	if err != nil {
		return nil, fmt.Errorf("cannot read %s: %w", accountsDir, err)
	}
	var matches []string
	for _, e := range entries {
		if !e.IsDir() || (account != "" && e.Name() != account) {
			continue
		}
		path := filepath.Join(accountsDir, e.Name(), "SavedVariables", "Paparazzi.lua")
		if _, err := os.Stat(path); err == nil {
			matches = append(matches, path)
		}
	}
	if len(matches) == 0 {
		return nil, fmt.Errorf("no Paparazzi.lua found under %s; log out of the game or /reload first", accountsDir)
	}
	sort.Strings(matches)
	return matches, nil
}

func listScreenshots(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("cannot read the screenshots folder: %w", err)
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && export.FileNamePattern.MatchString(e.Name()) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}
