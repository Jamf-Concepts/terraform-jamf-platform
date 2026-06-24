package migrate

import (
	"bytes"
	"flag"
	"os"
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

	out := rewriteFileText(file.Bytes())
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
