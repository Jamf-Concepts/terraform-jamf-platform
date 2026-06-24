package migrate

import (
	"bytes"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclwrite"
)

// -update rewrites golden files instead of diffing them.
var update = flag.Bool("update", false, "update golden files")

// TestGolden runs the migration engine against every testdata/<name>/input.tf
// and compares the output to testdata/<name>/golden.tf.
func TestGolden(t *testing.T) {
	entries, err := os.ReadDir("testdata")
	if err != nil {
		t.Fatalf("reading testdata: %v", err)
	}

	registry := RegistryByFromType()

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		name := entry.Name()
		t.Run(name, func(t *testing.T) {
			inputPath := filepath.Join("testdata", name, "input.tf")
			goldenPath := filepath.Join("testdata", name, "golden.tf")

			src, err := os.ReadFile(inputPath)
			if err != nil {
				t.Fatalf("reading input: %v", err)
			}

			got := applyMigration(t, src, inputPath, registry)

			if *update {
				if err := os.WriteFile(goldenPath, got, 0o644); err != nil {
					t.Fatalf("writing golden: %v", err)
				}
				t.Logf("updated %s", goldenPath)
				return
			}

			want, err := os.ReadFile(goldenPath)
			if err != nil {
				t.Fatalf("reading golden (run with -update to create): %v", err)
			}

			if !bytes.Equal(normalizeHCL(got), normalizeHCL(want)) {
				t.Errorf("output mismatch for %s\n\ngot:\n%s\n\nwant:\n%s",
					name, string(got), string(want))
			}
		})
	}
}

// applyMigration runs the migration engine on src and returns the transformed bytes.
func applyMigration(t *testing.T, src []byte, path string, registry map[string]*ResourceMapping) []byte {
	t.Helper()

	file, diags := hclwrite.ParseConfig(src, path, hcl.Pos{Line: 1, Column: 1})
	if diags.HasErrors() {
		t.Fatalf("parse error: %s", diags.Error())
	}

	report := &Report{}

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

		mapping, ok := registry[resourceType]
		if !ok || mapping.SkipReason != "" {
			continue
		}

		applyMapping(file, block, mapping, resourceLabel, path, report)
	}

	out := rewriteFileText(file.Bytes(), registry)
	return out
}

// normalizeHCL trims trailing whitespace on each line for comparison stability.
func normalizeHCL(b []byte) []byte {
	lines := strings.Split(string(b), "\n")
	for i, line := range lines {
		lines[i] = strings.TrimRight(line, " \t")
	}
	return []byte(strings.Join(lines, "\n"))
}

// TestSkippedResourcesReport verifies that skipped resource types appear in the
// report as SevSkip items and are left unchanged in the output HCL.
func TestSkippedResourcesReport(t *testing.T) {
	inputPath := filepath.Join("testdata", "skipped_resources", "input.tf")
	src, err := os.ReadFile(inputPath)
	if err != nil {
		t.Fatalf("reading input: %v", err)
	}

	registry := RegistryByFromType()
	file, diags := hclwrite.ParseConfig(src, inputPath, hcl.Pos{Line: 1, Column: 1})
	if diags.HasErrors() {
		t.Fatalf("parse error: %s", diags.Error())
	}

	report := &Report{}
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
		mapping, ok := registry[resourceType]
		if !ok {
			continue
		}
		if mapping.SkipReason != "" {
			report.AddSkip(mapping.FromType, resourceLabel, inputPath, 0, mapping.SkipReason)
			continue
		}
		applyMapping(file, block, mapping, resourceLabel, inputPath, report)
	}

	// Verify skip count
	_, _, skipCount := report.counts()
	if skipCount != 2 {
		t.Errorf("expected 2 skipped resources, got %d", skipCount)
	}

	// Verify skip items have correct types
	skippedTypes := map[string]bool{}
	for _, item := range report.items {
		if item.Severity == SevSkip {
			skippedTypes[item.OldType] = true
		}
	}
	for _, expected := range []string{"jamfpro_engage_settings", "jamfpro_managed_software_update_feature_toggle"} {
		if !skippedTypes[expected] {
			t.Errorf("expected skip for %q not found in report", expected)
		}
	}

	// Verify exit code is 1 (not 0) because skips are present
	if code := report.ExitCode(); code != 1 {
		t.Errorf("expected exit code 1, got %d", code)
	}

	// Verify skipped blocks are left unchanged in output
	out := string(rewriteFileText(file.Bytes(), registry))
	if !strings.Contains(out, `resource "jamfpro_engage_settings"`) {
		t.Error("expected jamfpro_engage_settings block to be left unchanged")
	}
	if !strings.Contains(out, `resource "jamfpro_managed_software_update_feature_toggle"`) {
		t.Error("expected jamfpro_managed_software_update_feature_toggle block to be left unchanged")
	}

	// Verify the report renders the skip section
	rendered := report.Render("testdata/skipped_resources")
	if !strings.Contains(rendered, "Skipped resources") {
		t.Error("expected 'Skipped resources' section in report")
	}
	if !strings.Contains(rendered, "jamfpro_engage_settings") {
		t.Error("expected jamfpro_engage_settings in skipped section")
	}
}

// TestDryRun verifies that --dry-run mode writes no files but prints the report.
func TestDryRun(t *testing.T) {
	tmp := t.TempDir()

	// Write a simple input file.
	inputTF := `resource "jamfpro_category" "test" {
  name     = "Test"
  priority = 9
}
`
	tfPath := filepath.Join(tmp, "main.tf")
	if err := os.WriteFile(tfPath, []byte(inputTF), 0o644); err != nil {
		t.Fatal(err)
	}

	// Set up a throwaway git repo so the branch guard passes.
	if err := runGit(tmp, "init", "-q"); err != nil {
		t.Fatal(err)
	}
	if err := runGit(tmp, "checkout", "-b", "test-branch"); err != nil {
		t.Fatal(err)
	}

	opts := Options{DryRun: true}
	code, err := Run(tmp, opts)
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}
	if code != 0 {
		t.Errorf("expected exit code 0, got %d", code)
	}

	// File must be unchanged (dry-run writes nothing).
	got, _ := os.ReadFile(tfPath)
	if string(got) != inputTF {
		t.Errorf("dry-run modified the file; expected no change")
	}

	// No report file should exist.
	reportPath := filepath.Join(tmp, "migration-report.md")
	if _, err := os.Stat(reportPath); err == nil {
		t.Error("dry-run wrote migration-report.md but should not have")
	}
}

// TestResourcesFilter verifies that --resources only migrates the listed types.
func TestResourcesFilter(t *testing.T) {
	tmp := t.TempDir()

	inputTF := `resource "jamfpro_category" "cat" {
  name     = "Test"
  priority = 9
}

resource "jamfpro_script" "scr" {
  name     = "test.sh"
  priority = "Before"
}
`
	tfPath := filepath.Join(tmp, "main.tf")
	if err := os.WriteFile(tfPath, []byte(inputTF), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := runGit(tmp, "init", "-q"); err != nil {
		t.Fatal(err)
	}
	if err := runGit(tmp, "checkout", "-b", "test-branch"); err != nil {
		t.Fatal(err)
	}

	// Only migrate scripts; category should be left as jamfpro_category.
	opts := Options{Resources: "jamfpro_script"}
	code, err := Run(tmp, opts)
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}
	if code != 0 {
		t.Errorf("expected exit code 0, got %d", code)
	}

	got, _ := os.ReadFile(tfPath)
	s := string(got)
	if !strings.Contains(s, `resource "jamfplatform_pro_script"`) {
		t.Error("expected script to be migrated to jamfplatform_pro_script")
	}
	if !strings.Contains(s, `priority = "BEFORE"`) {
		t.Error("expected script priority to be uppercased to BEFORE")
	}
	// category must NOT be renamed because it was filtered out
	if strings.Contains(s, `resource "jamfplatform_pro_category"`) {
		t.Error("category should not be migrated when --resources=jamfpro_script")
	}
}

// runGit runs a git command in the given directory.
func runGit(dir string, args ...string) error {
	fullArgs := append([]string{"-C", dir}, args...)
	out, err := exec.Command("git", fullArgs...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("git %v: %w\n%s", args, err, string(out))
	}
	return nil
}
