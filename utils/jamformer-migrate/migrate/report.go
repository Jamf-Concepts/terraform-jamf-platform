package migrate

import (
	"fmt"
	"strings"
	"time"
)

// Severity of a report item.
type Severity int

const (
	SevClean  Severity = iota // migrated without issues
	SevReview                 // needs manual review
	SevSkip                   // skipped — no equivalent
)

// ReportItem records the outcome for one resource.
type ReportItem struct {
	Severity     Severity
	NewType      string // empty for skipped
	OldType      string
	Label        string
	File         string
	Line         int
	Reason       string // human-readable explanation
	Action       string // what the user should do
}

// Report accumulates migration results across all files.
type Report struct {
	items []ReportItem
}

func (r *Report) add(item ReportItem) {
	r.items = append(r.items, item)
}

func (r *Report) AddClean(oldType, newType, label, file string, line int) {
	r.add(ReportItem{
		Severity: SevClean,
		OldType:  oldType,
		NewType:  newType,
		Label:    label,
		File:     file,
		Line:     line,
	})
}

func (r *Report) AddReview(oldType, newType, label, file string, line int, reason, action string) {
	r.add(ReportItem{
		Severity: SevReview,
		OldType:  oldType,
		NewType:  newType,
		Label:    label,
		File:     file,
		Line:     line,
		Reason:   reason,
		Action:   action,
	})
}

func (r *Report) AddSkip(oldType, label, file string, line int, reason string) {
	r.add(ReportItem{
		Severity: SevSkip,
		OldType:  oldType,
		Label:    label,
		File:     file,
		Line:     line,
		Reason:   reason,
	})
}

// ExitCode returns 0 (clean), 1 (review needed), or 2 (error).
// Callers pass 2 separately for hard errors.
func (r *Report) ExitCode() int {
	for _, item := range r.items {
		if item.Severity == SevReview || item.Severity == SevSkip {
			return 1
		}
	}
	return 0
}

// Render returns the full markdown report text.
func (r *Report) Render(inputDir string) string {
	var b strings.Builder

	clean, review, skip := r.counts()

	fmt.Fprintf(&b, "# jamformer migrate — %s\n\n", time.Now().Format("2006-01-02"))
	fmt.Fprintf(&b, "Input: `%s`\n\n", inputDir)
	fmt.Fprintf(&b, "| Result | Count |\n")
	fmt.Fprintf(&b, "|--------|-------|\n")
	fmt.Fprintf(&b, "| ✓ Migrated cleanly | %d |\n", clean)
	fmt.Fprintf(&b, "| ⚠ Manual review | %d |\n", review)
	fmt.Fprintf(&b, "| ✗ Skipped | %d |\n", skip)
	fmt.Fprintf(&b, "\n")

	if review > 0 {
		fmt.Fprintf(&b, "## Manual review required\n\n")
		for _, item := range r.items {
			if item.Severity != SevReview {
				continue
			}
			loc := item.File
			if item.Line > 0 {
				loc = fmt.Sprintf("%s:%d", item.File, item.Line)
			}
			label := item.NewType
			if item.Label != "" {
				label = fmt.Sprintf("%s.%s", item.NewType, item.Label)
			}
			fmt.Fprintf(&b, "⚠  %s  (%s)\n", label, loc)
			if item.Reason != "" {
				fmt.Fprintf(&b, "   Reason: %s\n", item.Reason)
			}
			if item.Action != "" {
				fmt.Fprintf(&b, "   Action: %s\n", item.Action)
			}
			fmt.Fprintf(&b, "\n")
		}
	}

	if skip > 0 {
		fmt.Fprintf(&b, "## Skipped resources (no equivalent in new provider)\n\n")
		// Aggregate by type
		type skipKey struct{ oldType, label string }
		seen := map[string]int{}
		for _, item := range r.items {
			if item.Severity != SevSkip {
				continue
			}
			seen[item.OldType]++
		}
		for _, item := range r.items {
			if item.Severity != SevSkip {
				continue
			}
			count := seen[item.OldType]
			if count > 0 {
				instances := "instance"
				if count != 1 {
					instances = "instances"
				}
				fmt.Fprintf(&b, "✗  %s (%d %s) — %s\n\n", item.OldType, count, instances, item.Reason)
				seen[item.OldType] = 0 // only print once per type
			}
		}
	}

	return b.String()
}

func (r *Report) counts() (clean, review, skip int) {
	for _, item := range r.items {
		switch item.Severity {
		case SevClean:
			clean++
		case SevReview:
			review++
		case SevSkip:
			skip++
		}
	}
	return
}
