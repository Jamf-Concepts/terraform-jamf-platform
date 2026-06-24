package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/jamf/jamformer-migrate/migrate"
)

func main() {
	var (
		dryRun    = flag.Bool("dry-run", false, "print what would change, write nothing")
		report    = flag.String("report", "", "write migration report to file (default: <input-dir>/migration-report.md)")
		resources = flag.String("resources", "", "comma-separated list of source types to migrate (default: all)")
		noState   = flag.Bool("no-state", true, "skip import/removed block generation (default: true)")
		force     = flag.Bool("force", false, "allow running on main/master branch")
	)
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: jamformer-migrate [flags] <input-dir>\n\n")
		fmt.Fprintf(os.Stderr, "Migrates Terraform .tf files from deploymenttheory/jamfpro provider\n")
		fmt.Fprintf(os.Stderr, "to Jamf-Concepts/jamfplatform provider.\n\n")
		fmt.Fprintf(os.Stderr, "Flags:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExit codes:\n")
		fmt.Fprintf(os.Stderr, "  0  all resources migrated cleanly\n")
		fmt.Fprintf(os.Stderr, "  1  migration complete but manual review required\n")
		fmt.Fprintf(os.Stderr, "  2  error (invalid input, parse failure, etc.)\n")
	}
	flag.Parse()

	if flag.NArg() != 1 {
		flag.Usage()
		os.Exit(2)
	}

	inputDir := flag.Arg(0)

	opts := migrate.Options{
		DryRun:    *dryRun,
		Report:    *report,
		Resources: *resources,
		NoState:   *noState,
		Force:     *force,
	}

	code, err := migrate.Run(inputDir, opts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(2)
	}
	os.Exit(code)
}
