# jamformer-migrate — Developer Guide

Architecture, design decisions, and contributor workflow for the migration
engine. Read this before making changes.

## Repository layout

```
utils/jamformer-migrate/
├── main.go                  # CLI entry point and flag parsing
├── go.mod                   # module: github.com/jamf/jamformer-migrate
└── migrate/
    ├── mapping.go           # ResourceMapping registry — all tier definitions
    ├── transform.go         # HCL AST rewrite engine (~1550 lines)
    ├── migrate.go           # Orchestrator: walk files, apply transforms, write output
    ├── report.go            # Migration report builder and renderer
    ├── migrate_test.go      # Golden-file test harness
    └── testdata/
        ├── <resource>/
        │   ├── input.tf     # Input fixture (old provider syntax)
        │   └── golden.tf    # Expected output (new provider syntax)
        └── ...
```

## Architecture

The tool is a single-pass HCL rewriter. For each `.tf` file:

1. `hclwrite.ParseConfig` builds a writable AST.
2. Every `resource` block is looked up in the registry (`mapping.go`).
3. The appropriate transform is applied to the block body in place.
4. `rewriteFileText` does a final text-level pass for cross-reference rewrites
   (e.g. `.id` → `.jamf_pro_id` for device group references).
5. The rewritten bytes are written back to disk.

The key dependency is `github.com/hashicorp/hcl/v2/hclwrite`. It gives us a
writable AST that preserves all comments and whitespace for blocks we don't
touch, keeping diffs minimal. The tradeoff: hclwrite works at the token level
for attribute values — it cannot evaluate or deeply inspect expressions. For
our use case (move/rename attributes, convert blocks to object literals) that
is the right level of abstraction.

## The registry (`mapping.go`)

Every source resource type maps to a `ResourceMapping` struct. The registry is
a `[]ResourceMapping` slice built in `buildRegistry()` and exposed via
`RegistryByFromType()` which returns a `map[string]*ResourceMapping` for O(1)
lookup at runtime.

```go
type ResourceMapping struct {
    FromType  string          // e.g. "jamfpro_script"
    ToType    string          // e.g. "jamfplatform_pro_script"
    Tier      int             // 1–4, for reporting

    Attrs           []AttrMapping          // renames / value transforms
    DropAttrs       []string               // attrs to silently remove
    InjectAfter     map[string]string      // "anchor_attr": "key = val" to append
    WriteOnlyFields map[string]string      // secret_attr → wo_version_attr

    FoldedGroupType  string                // Tier 4: "smart" or "static"
    FoldedDeviceType string                // Tier 4: "computer" or "mobile"

    StructuralTransform func(...)          // Tier 3: full custom rewriter
    ReviewNote   string                    // always flags this resource for review
    ReviewAction string
    SkipReason   string                    // non-empty = no equivalent, leave unchanged
}
```

The tiers are not enforced by the engine — they are a documentation and
reporting convention. `Tier` is stored and included in future report
improvements.

## The transform engine (`transform.go`)

### Execution order

`applyMapping` in `migrate.go` calls transforms in this order:

1. **`applyAttrMappings`** — processes `Attrs`, `DropAttrs`, `InjectAfter`,
   and `WriteOnlyFields`. Always runs first, even for Tier 3 resources, so
   simple attr renames can be declared in the mapping without duplicating logic
   inside the structural transform function.

2. **`StructuralTransform`** (if present) — the per-resource custom function.
   Receives the already-attr-mapped body and performs block-to-object
   conversions, list construction, and scope restructuring.

3. **`rewriteFileText`** — a text-level pass that rewrites device group
   cross-references (e.g. `jamfpro_smart_computer_group.foo.id` →
   `jamfplatform_device_group.foo.jamf_pro_id`) after all AST rewriting is
   done. This is the only permitted text-level substitution.

### Critical helpers

**`orderedAttrNames(body)`** — returns attribute names in document order by
scanning the token stream. `hclwrite.Body.Attributes()` returns a `map[string]*Attribute`
which has non-deterministic iteration order in Go. **You must use
`orderedAttrNames` any time you iterate a body's attributes and the output
order matters.** Failing to do this produces goldens that flip between runs.
`blockBodyToObjectLiteral` already calls this internally.

**`blockBodyToObjectLiteral(body, indent)`** — serialises a block body as a
`{ key = val }` object literal string, using `orderedAttrNames` for
deterministic order. Use this for all block → object-attr conversions.

**`replaceStringLiteral(tokens, replacements)`** — rewrites a quoted string
value inside a token sequence (e.g. `"Before"` → `"BEFORE"` for priority
enum). hclwrite represents `"hello"` as three tokens (`"`, `hello`, `"`), so
byte-level manipulation is error-prone. This helper re-parses a minimal HCL
fragment to get correct tokens. Use it for all string value transforms.

**`hclTokensForLiteral(val)`** — parses `x = <val>` and returns the expression
tokens. Use this when calling `body.SetAttributeRaw` with a hand-built object
literal or list string.

### WriteOnly injection

Resources with secret attrs need `*_wo_version = 1` injected immediately after
the secret. For simple cases, declare `WriteOnlyFields` in the mapping and
`applyAttrMappings` handles it. For complex cases (secrets inside nested
blocks), inject inside the structural transform function **before** any
block-to-object conversion — once `blockBodyToObjectLiteral` serialises the
block body to a string, the WO field needs to be in the underlying body before
serialisation, not appended afterward.

### Scope restructuring pattern

All Tier 3 resources with a `scope {}` block follow the same pattern:

```
scope {
  all_computers = true
  all_jss_users = false    ← always dropped
  ...direct attrs...       ← go into targets = { }
  limitations { ... }      ← dropped (no equivalent)
  exclusions { ... }       ← go into exclusions = { }
}
```

Output:
```hcl
scope = {
  targets    = { ... }
  exclusions = { ... }
}
```

See `transformConfigProfile`, `transformPolicy`, `transformRestrictedSoftware`
for reference implementations.

### `transformCriteriaBlocks` vs `transformAdvancedSearchCriteria`

These two functions both convert `criteria {}` blocks to a list, but they are
intentionally different:

- **`transformCriteriaBlocks`** — used for Tier 4 device groups. Renames
  `name` → `criteria` and `search_type` → `operator` to match the new device
  group schema.
- **`transformAdvancedSearchCriteria`** — used for advanced computer/mobile
  searches. Keeps `name` and `search_type` attr names unchanged (the new
  provider's advanced search schema uses the same names).

Do not merge them.

## Running the tests

```sh
cd utils/jamformer-migrate
go test ./migrate/ -run TestGolden -v
```

All 33 suites must pass before merging.

### Updating golden files

When you change a transform and the output legitimately changes, regenerate the
affected goldens:

```sh
# Regenerate all goldens:
go test ./migrate/ -run TestGolden -v -update

# Regenerate one specific golden:
go test ./migrate/ -run TestGolden/policy -v -update
```

After regenerating, **always read the updated golden manually** and verify it
matches the new provider's example `.tf` for that resource type. The test
harness can only check that the engine produces consistent output — it cannot
check that the output is semantically correct.

Ground truth for every resource is the side-by-side comparison of:
- Old: `/Users/admin/Documents/GitHub/community/terraform-provider-jamfpro/examples/resources/<resource>/resource.tf`
- New: `/Users/admin/Documents/GitHub/jamf-concepts/terraform-provider-jamfplatform/examples/resources/<resource>/resource.tf`

### Adding a new resource

1. Add a `ResourceMapping` entry to `buildRegistry()` in `mapping.go`.
2. If the resource needs a structural transform, write the function in
   `transform.go` and point `StructuralTransform` at it.
3. Create `migrate/testdata/<name>/input.tf` (old provider syntax, derived from
   the provider example) and run with `-update` to generate the golden.
4. Verify the golden manually against the new provider example.
5. Run `go test ./migrate/ -run TestGolden -v` — all 33+ suites must pass.

### Non-determinism

Map iteration order in Go is intentionally random. Any place that calls
`range body.Attributes()` or `range someMap` and feeds the results into output
is a latent non-determinism bug. The canonical signal: a golden test that passes
on one run but fails on another.

Fix: use `orderedAttrNames(body)` to iterate body attributes, and iterate any
constant-ordered slice (not map) for rename tables. See the renames map in
`transformInventoryCollection` for the correct pattern — it iterates
`orderedAttrNames(prefBody)` and looks up the rename per name, rather than
ranging over the rename map directly.

## Design constraints

These rules must not be violated:

1. **No regex on raw `.tf` text for resource detection.** Always use the
   hclwrite AST. The only permitted text-level operation is `rewriteFileText`
   for cross-reference rewrites (device group `.id` → `.jamf_pro_id`). Regex
   on raw text will match inside comment blocks and produce incorrect output.

2. **`orderedAttrNames`** whenever attribute iteration order affects output.

3. **`replaceStringLiteral`** for string value transforms. Never manipulate
   token bytes directly.

4. **WO version injection before block-to-object conversion.** If a secret
   lives inside a block that will be serialised to an object literal, inject
   the `*_wo_version` attribute into the block body *before* calling
   `blockBodyToObjectLiteral`. After serialisation the original body is
   gone.

5. **Golden files reflect actual engine output, not ideal human-written HCL.**
   `hclwrite.SetAttributeRaw` appends renamed attributes to the body end.
   Golden attribute order may therefore differ from the original source order.
   That is expected and correct.

## Spec reference

The authoritative mapping specification for every resource type lives at:

```
utils/plan-to-improve-our-provider-converter.md
```

The handoff document (`HANDOFF.md` in this directory) records current
implementation state, decisions already locked in, and what remains to be done.
