package migrate

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclwrite"
)

// Options controls migrate.Run behaviour.
type Options struct {
	DryRun    bool
	Report    string // path for report file; "" uses <inputDir>/migration-report.md
	Resources string // comma-separated filter; "" means all
	NoState   bool
	Force     bool
}

// Run is the main entry point. Returns exit code (0, 1, or 2) and any fatal error.
func Run(inputDir string, opts Options) (int, error) {
	// Validate input directory.
	info, err := os.Stat(inputDir)
	if err != nil || !info.IsDir() {
		return 2, fmt.Errorf("input dir %q does not exist or is not a directory", inputDir)
	}

	// Check for .tf files.
	tfFiles, err := findTFFiles(inputDir)
	if err != nil {
		return 2, err
	}
	if len(tfFiles) == 0 {
		return 2, fmt.Errorf("no .tf files found in %q", inputDir)
	}

	// Branch guard.
	if !opts.Force {
		branch, _ := gitBranch(inputDir)
		if branch == "main" || branch == "master" {
			return 2, fmt.Errorf("refusing to run on branch %q — use --force to override", branch)
		}
	}

	// Build resource type filter set.
	filterSet := map[string]bool{}
	if opts.Resources != "" {
		for _, r := range strings.Split(opts.Resources, ",") {
			filterSet[strings.TrimSpace(r)] = true
		}
	}

	registry := RegistryByFromType()

	report := &Report{}

	// Process each file.
	for _, path := range tfFiles {
		if err := processFile(path, registry, filterSet, report, opts.DryRun); err != nil {
			return 2, fmt.Errorf("processing %s: %w", path, err)
		}
	}

	// Write report.
	if !opts.DryRun {
		reportPath := opts.Report
		if reportPath == "" {
			reportPath = filepath.Join(inputDir, "migration-report.md")
		}
		if err := os.WriteFile(reportPath, []byte(report.Render(inputDir)), 0o644); err != nil {
			return 2, fmt.Errorf("writing report: %w", err)
		}
		fmt.Printf("Migration complete. Report written to %s\n", reportPath)
	} else {
		fmt.Print(report.Render(inputDir))
	}

	return report.ExitCode(), nil
}

// processFile parses, transforms, and (unless dryRun) rewrites a single .tf file.
func processFile(path string, registry map[string]*ResourceMapping, filterSet map[string]bool, report *Report, dryRun bool) error {
	src, err := os.ReadFile(path)
	if err != nil {
		return err
	}

	file, diags := hclwrite.ParseConfig(src, path, hcl.Pos{Line: 1, Column: 1})
	if diags.HasErrors() {
		return fmt.Errorf("parse error: %s", diags.Error())
	}

	changed := false

	for _, block := range file.Body().Blocks() {
		if block.Type() != "resource" {
			continue
		}
		labels := block.Labels()
		if len(labels) < 2 {
			continue
		}
		resourceType := labels[0]
		resourceLabel := labels[1]

		// Apply filter if set.
		if len(filterSet) > 0 && !filterSet[resourceType] {
			continue
		}

		mapping, ok := registry[resourceType]
		if !ok {
			// Unknown type — silently skip; only known types are processed.
			continue
		}

		// Skip resources with no new equivalent.
		if mapping.SkipReason != "" {
			report.AddSkip(mapping.FromType, resourceLabel, path, 0, mapping.SkipReason)
			continue
		}

		// Apply the mapping.
		applyMapping(file, block, mapping, resourceLabel, path, report)
		changed = true
	}

	// Rewrite cross-references at text level. Run unconditionally — a file may
	// reference resources declared in another file, so even files with no
	// resource blocks of their own need their expression references updated.
	out := rewriteFileText(file.Bytes(), registry)
	textChanged := string(out) != string(src)
	if (changed || textChanged) && !dryRun {
		if err := os.WriteFile(path, out, 0o644); err != nil {
			return err
		}
	}

	return nil
}

// applyMapping applies a single ResourceMapping to a resource block.
func applyMapping(file *hclwrite.File, block *hclwrite.Block, m *ResourceMapping, label, path string, report *Report) {
	body := block.Body()

	// Get line number from block's first token for reporting.
	line := 0 // hclwrite doesn't expose source positions after parse

	// Rename the resource type label.
	if m.ToType != "" {
		block.SetLabels([]string{m.ToType, label})
	}

	// Tier 4: device group folding.
	if m.Tier == 4 {
		transformDeviceGroup(body, m.FoldedGroupType, m.FoldedDeviceType, label, report, path, line)
		report.AddClean(m.FromType, m.ToType, label, path, line)
		return
	}

	// Tier 3: delegate fully to StructuralTransform, but apply any simple attr
	// mappings first (some Tier 2 resources have both Attrs/DropAttrs and a
	// StructuralTransform — applyAttrMappings is a no-op for pure Tier 3 resources
	// that don't define Attrs/DropAttrs).
	if m.StructuralTransform != nil {
		applyAttrMappings(body, m)
		m.StructuralTransform(body, label, report, path, line)
		// Structural transforms add their own report items; add clean if no review added.
		// We add a base clean item; StructuralTransform may override with review items.
		if m.ReviewNote == "" {
			report.AddClean(m.FromType, m.ToType, label, path, line)
		} else {
			report.AddReview(m.FromType, m.ToType, label, path, line, m.ReviewNote, m.ReviewAction)
		}
		return
	}

	// Tier 1 & 2: attr-level transforms.
	applyAttrMappings(body, m)

	if m.ReviewNote != "" {
		report.AddReview(m.FromType, m.ToType, label, path, line, m.ReviewNote, m.ReviewAction)
	} else {
		report.AddClean(m.FromType, m.ToType, label, path, line)
	}
}

// findTFFiles walks dir and returns all .tf file paths.
func findTFFiles(dir string) ([]string, error) {
	var files []string
	err := filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() && strings.HasSuffix(path, ".tf") {
			files = append(files, path)
		}
		return nil
	})
	return files, err
}

// gitBranch returns the current git branch for the given directory.
func gitBranch(dir string) (string, error) {
	cmd := exec.Command("git", "-C", dir, "rev-parse", "--abbrev-ref", "HEAD")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
