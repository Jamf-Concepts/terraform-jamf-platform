package migrate

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/hashicorp/hcl/v2/hclwrite"
	"github.com/zclconf/go-cty/cty"
)

// ── token transform helpers ───────────────────────────────────────────────────

// replaceStringLiteral replaces the content of a quoted string literal in a token sequence.
// hclwrite represents "hello" as three tokens: TokenOQuote("), TokenQuotedLit(hello), TokenCQuote(")
// so we operate on the serialized form and re-parse.
func replaceStringLiteral(tokens hclwrite.Tokens, replacements map[string]string) hclwrite.Tokens {
	serialized := tokensString(tokens)
	for from, to := range replacements {
		if serialized == `"`+from+`"` || serialized == " \""+from+"\"" {
			newSrc := strings.TrimSpace(serialized)
			newSrc = `"` + to + `"`
			src := []byte("x = " + newSrc + "\n")
			f, _ := hclwrite.ParseConfig(src, "", hcl.Pos{Line: 1, Column: 1})
			if f != nil {
				for _, attr := range f.Body().Attributes() {
					return attr.Expr().BuildTokens(nil)
				}
			}
		}
	}
	return tokens
}

// stripLeadingDot removes a leading "." from a quoted string token value.
// e.g. ".jpg" → "jpg"
func stripLeadingDot(tokens hclwrite.Tokens) hclwrite.Tokens {
	s := strings.TrimSpace(tokensString(tokens))
	if strings.HasPrefix(s, `".`) && strings.HasSuffix(s, `"`) {
		newVal := `"` + s[2:]
		src := []byte("x = " + newVal + "\n")
		f, _ := hclwrite.ParseConfig(src, "", hcl.Pos{Line: 1, Column: 1})
		if f != nil {
			for _, attr := range f.Body().Attributes() {
				return attr.Expr().BuildTokens(nil)
			}
		}
	}
	return tokens
}

// scriptPriorityTransform uppercases the priority enum and converts "At Reboot".
func scriptPriorityTransform(tokens hclwrite.Tokens) hclwrite.Tokens {
	return replaceStringLiteral(tokens, map[string]string{
		"Before":   "BEFORE",
		"After":    "AFTER",
		"At Reboot": "AT_REBOOT",
	})
}

// appInstallerDeploymentTypeTransform converts deployment_type enum.
func appInstallerDeploymentTypeTransform(tokens hclwrite.Tokens) hclwrite.Tokens {
	return replaceStringLiteral(tokens, map[string]string{
		"AUTOMATIC": "INSTALL_AUTOMATICALLY",
	})
}

// ── applyAttrMappings rewrites attrs in a body using a ResourceMapping ────────

// applyAttrMappings applies the Attrs, DropAttrs, InjectAfter, and WriteOnlyFields
// rules from the mapping to a body block.
//
// Attribute ordering note: hclwrite's SetAttributeRaw appends to the body when
// the attribute name changes. We process attrs in the order of the Attrs slice
// for deterministic output. Unchanged attrs stay in their original positions;
// renamed attrs appear at the end in mapping-definition order.
func applyAttrMappings(body *hclwrite.Body, m *ResourceMapping) {
	// Drop attrs first.
	for _, d := range m.DropAttrs {
		body.RemoveAttribute(d)
	}

	// Process renames/transforms in the order defined in the Attrs slice
	// (deterministic — map iteration would give random order).
	for _, am := range m.Attrs {
		attr := body.GetAttribute(am.From)
		if attr == nil {
			continue
		}
		var val hclwrite.Tokens
		if am.Transform != nil {
			val = am.Transform(attr.Expr().BuildTokens(nil))
		} else {
			val = attr.Expr().BuildTokens(nil)
		}
		if am.To == "" {
			body.RemoveAttribute(am.From)
		} else if am.To != am.From {
			body.RemoveAttribute(am.From)
			body.SetAttributeRaw(am.To, val)
		} else if am.Transform != nil {
			body.SetAttributeRaw(am.From, val)
		}
	}

	// Inject InjectAfter attrs (appended at end — hclwrite has no insert-after).
	for _, injectLine := range m.InjectAfter {
		parts := strings.SplitN(injectLine, " = ", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])
		if body.GetAttribute(key) == nil {
			body.SetAttributeRaw(key, hclTokensForLiteral(val))
		}
	}

	// Inject WriteOnly version fields.
	for secretAttr, woAttr := range m.WriteOnlyFields {
		if body.GetAttribute(secretAttr) != nil && body.GetAttribute(woAttr) == nil {
			body.SetAttributeValue(woAttr, cty.NumberIntVal(1))
		}
	}
}

// hclTokensForLiteral returns raw tokens for a literal value string like `"1"` or `1`.
func hclTokensForLiteral(val string) hclwrite.Tokens {
	src := []byte("x = " + val + "\n")
	f, _ := hclwrite.ParseConfig(src, "", hcl.Pos{Line: 1, Column: 1})
	if f == nil {
		return hclwrite.TokensForValue(cty.StringVal(val))
	}
	for _, attr := range f.Body().Attributes() {
		return attr.Expr().BuildTokens(nil)
	}
	return hclwrite.TokensForValue(cty.StringVal(val))
}

// ── cross-reference rewrites ──────────────────────────────────────────────────

// rewriteGroupReferences rewrites cross-references to folded group types in
// expression tokens. e.g. jamfpro_smart_computer_group.foo.id →
// jamfplatform_device_group.foo.jamf_pro_id
func rewriteGroupReferences(tokens hclwrite.Tokens) hclwrite.Tokens {
	oldPrefixes := []string{
		"jamfpro_smart_computer_group",
		"jamfpro_smart_computer_group_v2",
		"jamfpro_static_computer_group",
		"jamfpro_smart_mobile_device_group",
		"jamfpro_smart_mobile_device_group_v2",
		"jamfpro_static_mobile_device_group",
	}

	result := make(hclwrite.Tokens, len(tokens))
	copy(result, tokens)

	for i, tok := range result {
		s := string(tok.Bytes)
		for _, prefix := range oldPrefixes {
			if strings.Contains(s, prefix) {
				s = strings.ReplaceAll(s, prefix, "jamfplatform_device_group")
				result[i].Bytes = []byte(s)
			}
		}
		// .id → .jamf_pro_id for device group references (token i-2 is the type name)
		if i >= 2 {
			prev2 := string(result[i-2].Bytes)
			if strings.HasPrefix(prev2, "jamfplatform_device_group") && s == "id" {
				result[i].Bytes = []byte("jamf_pro_id")
			}
		}
	}
	return result
}

// deviceGroupIDRe matches jamfplatform_device_group.<label>.id (whole-word .id)
var deviceGroupIDRe = regexp.MustCompile(`(jamfplatform_device_group\.[a-zA-Z0-9_-]+)\.id\b`)

// rewriteFileText does text-level substitution of cross-references after AST rewriting.
func rewriteFileText(src []byte) []byte {
	s := string(src)

	// Rewrite group type prefixes in expressions (longest first to avoid partial matches)
	oldPrefixes := []string{
		"jamfpro_smart_computer_group_v2",
		"jamfpro_smart_computer_group",
		"jamfpro_static_computer_group",
		"jamfpro_smart_mobile_device_group_v2",
		"jamfpro_smart_mobile_device_group",
		"jamfpro_static_mobile_device_group",
	}
	for _, prefix := range oldPrefixes {
		s = strings.ReplaceAll(s, prefix+".", "jamfplatform_device_group.")
	}

	// .id → .jamf_pro_id for all device group references
	s = deviceGroupIDRe.ReplaceAllString(s, "$1.jamf_pro_id")

	return []byte(s)
}


// ── body extraction helpers ───────────────────────────────────────────────────

// orderedAttrNames returns the attribute names in the body in document order.
// hclwrite.Body.Attributes() returns a map (unordered), so we scan the serialized
// token bytes for "ident =" patterns to preserve document order.
func orderedAttrNames(body *hclwrite.Body) []string {
	tokens := body.BuildTokens(nil)
	attrs := body.Attributes()
	var names []string
	seen := map[string]bool{}
	for i, tok := range tokens {
		if tok.Type != hclsyntax.TokenIdent {
			continue
		}
		name := string(tok.Bytes)
		if _, exists := attrs[name]; !exists || seen[name] {
			continue
		}
		// Check if next non-space token is '='
		for j := i + 1; j < len(tokens); j++ {
			next := tokens[j]
			if len(bytes.TrimSpace(next.Bytes)) == 0 {
				continue
			}
			if next.Type == hclsyntax.TokenEqual {
				names = append(names, name)
				seen[name] = true
			}
			break
		}
	}
	return names
}

// getAttrStringValue extracts the unquoted string value from an attribute, or "".
func getAttrStringValue(body *hclwrite.Body, name string) string {
	attr := body.GetAttribute(name)
	if attr == nil {
		return ""
	}
	tokens := attr.Expr().BuildTokens(nil)
	var buf bytes.Buffer
	for _, t := range tokens {
		buf.Write(t.Bytes)
	}
	s := strings.TrimSpace(buf.String())
	// Strip surrounding quotes if present.
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		return s[1 : len(s)-1]
	}
	return s
}

// getAttrRawTokens returns the raw expression tokens for an attribute.
func getAttrRawTokens(body *hclwrite.Body, name string) hclwrite.Tokens {
	attr := body.GetAttribute(name)
	if attr == nil {
		return nil
	}
	return attr.Expr().BuildTokens(nil)
}

// copyAttr copies an attribute from src to dst, renaming if toName differs.
func copyAttr(dst *hclwrite.Body, src *hclwrite.Body, fromName, toName string) bool {
	attr := src.GetAttribute(fromName)
	if attr == nil {
		return false
	}
	dst.SetAttributeRaw(toName, attr.Expr().BuildTokens(nil))
	return true
}

// ── Tier 3 structural transforms ─────────────────────────────────────────────

// transformIcon merges icon_file_path + icon_file_web_source → icon_file_source.
func transformIcon(body *hclwrite.Body, label string, report *Report, file string, line int) {
	pathAttr := body.GetAttribute("icon_file_path")
	webAttr := body.GetAttribute("icon_file_web_source")

	var srcTokens hclwrite.Tokens
	if pathAttr != nil {
		srcTokens = pathAttr.Expr().BuildTokens(nil)
	} else if webAttr != nil {
		srcTokens = webAttr.Expr().BuildTokens(nil)
	}

	body.RemoveAttribute("icon_file_path")
	body.RemoveAttribute("icon_file_web_source")

	if srcTokens != nil {
		body.SetAttributeRaw("icon_file_source", srcTokens)
	}
}

// transformAppInstaller injects app_title_name = name and converts sub-blocks to objects.
func transformAppInstaller(body *hclwrite.Body, label string, report *Report, file string, line int) {
	nameTokens := getAttrRawTokens(body, "name")
	if nameTokens != nil && body.GetAttribute("app_title_name") == nil {
		body.SetAttributeRaw("app_title_name", nameTokens)
	}
	// Convert notification_settings and self_service_settings blocks → object attrs.
	for _, block := range body.Blocks() {
		switch block.Type() {
		case "notification_settings", "self_service_settings":
			objLit := blockBodyToObjectLiteral(block.Body(), "  ")
			body.SetAttributeRaw(block.Type(), hclTokensForLiteral(objLit))
			body.RemoveBlock(block)
		}
	}
}

// transformSMTPServer converts connection/credential sub-blocks to object attrs
// and injects WriteOnly version fields inside the credential objects.
func transformSMTPServer(body *hclwrite.Body, label string, report *Report, file string, line int) {
	blockNames := []string{
		"connection_settings", "sender_settings",
		"basic_auth_credentials", "graph_api_credentials", "google_mail_credentials",
	}
	for _, block := range body.Blocks() {
		found := false
		for _, n := range blockNames {
			if block.Type() == n {
				found = true
				break
			}
		}
		if !found {
			continue
		}
		bBody := block.Body()
		// Inject WriteOnly version fields inside the credential blocks.
		if block.Type() == "basic_auth_credentials" {
			if bBody.GetAttribute("password") != nil && bBody.GetAttribute("password_wo_version") == nil {
				bBody.SetAttributeValue("password_wo_version", cty.NumberIntVal(1))
			}
		}
		if block.Type() == "graph_api_credentials" {
			if bBody.GetAttribute("client_secret") != nil && bBody.GetAttribute("client_secret_wo_version") == nil {
				bBody.SetAttributeValue("client_secret_wo_version", cty.NumberIntVal(1))
			}
		}
		objLit := blockBodyToObjectLiteral(bBody, "  ")
		body.SetAttributeRaw(block.Type(), hclTokensForLiteral(objLit))
		body.RemoveBlock(block)
	}
}

// transformMacOSProfile restructures a macOS config profile.
func transformMacOSProfile(body *hclwrite.Body, label string, report *Report, file string, line int) {
	transformConfigProfile(body, label, report, file, line, false)
}

// transformMobileProfile restructures a mobile device config profile.
func transformMobileProfile(body *hclwrite.Body, label string, report *Report, file string, line int) {
	transformConfigProfile(body, label, report, file, line, true)
}

// transformConfigProfile is the shared config profile structural transform.
func transformConfigProfile(body *hclwrite.Body, label string, report *Report, file string, line int, isMobile bool) {
	generalAttrs := map[string]bool{
		"name": true, "description": true, "level": true,
		"distribution_method": true, "redeploy_on_update": true,
		"category_id": true, "user_removable": true, "payloads": true,
	}
	if isMobile {
		generalAttrs["deployment_method"] = true
		generalAttrs["redeploy_days_before_certificate_expires"] = true
	}

	// Collect general attrs and scope block children before modifying the body.
	type savedAttr struct {
		name   string
		tokens hclwrite.Tokens
	}
	var generalSaved []savedAttr

	// Use orderedAttrNames to collect in document order (deterministic output).
	for _, attrName := range orderedAttrNames(body) {
		if attrName == "payload_validate" || attrName == "site_id" {
			body.RemoveAttribute(attrName)
			continue
		}
		if !generalAttrs[attrName] {
			continue
		}
		tok := getAttrRawTokens(body, attrName)
		if tok != nil {
			outName := attrName
			if isMobile && attrName == "deployment_method" {
				outName = "distribution_method"
			}
			generalSaved = append(generalSaved, savedAttr{outName, tok})
			body.RemoveAttribute(attrName)
		}
	}

	// Collect scope block.
	var scopeTargetAttrs []savedAttr
	for _, block := range body.Blocks() {
		if block.Type() == "scope" {
			scopeBody := block.Body()
			// Use orderedAttrNames for deterministic scope attr order.
			for _, name := range orderedAttrNames(scopeBody) {
				attr := scopeBody.GetAttribute(name)
				if attr != nil {
					scopeTargetAttrs = append(scopeTargetAttrs, savedAttr{name, attr.Expr().BuildTokens(nil)})
				}
			}
			body.RemoveBlock(block)
			break
		}
	}

	// Remove self_service block — will re-add as object attr later.
	// (self_service restructuring is complex; for now copy as-is and flag)
	// TODO: full self_service restructuring

	// Drop all_jss_users from scope.
	var filteredScope []savedAttr
	for _, sa := range scopeTargetAttrs {
		if sa.name != "all_jss_users" {
			filteredScope = append(filteredScope, sa)
		}
	}

	// Build general = { ... } block as HCL text.
	var generalHCL bytes.Buffer
	generalHCL.WriteString("{\n")
	for _, sa := range generalSaved {
		valStr := tokensString(sa.tokens)
		generalHCL.WriteString(fmt.Sprintf("    %s = %s\n", sa.name, valStr))
	}
	generalHCL.WriteString("  }")
	body.SetAttributeRaw("general", hclTokensForLiteral(generalHCL.String()))

	// Build scope = { targets = { ... } } if we have scope attrs.
	if len(filteredScope) > 0 {
		var scopeHCL bytes.Buffer
		scopeHCL.WriteString("{\n    targets = {\n")
		for _, sa := range filteredScope {
			// Rewrite group refs: .id → .jamf_pro_id
			valStr := tokensString(rewriteGroupReferences(sa.tokens))
			scopeHCL.WriteString(fmt.Sprintf("      %s = %s\n", sa.name, valStr))
		}
		scopeHCL.WriteString("    }\n  }")
		body.SetAttributeRaw("scope", hclTokensForLiteral(scopeHCL.String()))
	}
}

// transformPolicy restructures a policy resource.
func transformPolicy(body *hclwrite.Body, label string, report *Report, file string, line int) {
	generalAttrNames := map[string]bool{
		"name": true, "enabled": true, "frequency": true,
		"trigger_checkin": true, "trigger_enrollment_complete": true,
		"trigger_login": true, "trigger_logout": true, "trigger_network_state_change": true,
		"trigger_other": true, "trigger_startup": true,
		"category_id": true, "site_id": true, "offline": true,
		"network_requirement": true, "override_default_settings": true,
	}

	type savedAttr struct {
		name   string
		tokens hclwrite.Tokens
	}

	// Collect general attrs in document order.
	var generalSaved []savedAttr
	for _, attrName := range orderedAttrNames(body) {
		if !generalAttrNames[attrName] {
			continue
		}
		tok := getAttrRawTokens(body, attrName)
		if tok != nil {
			generalSaved = append(generalSaved, savedAttr{attrName, tok})
			body.RemoveAttribute(attrName)
		}
	}

	// Process top-level blocks.
	var scopeTargetAttrs []savedAttr
	var selfServiceAttrs []savedAttr
	var payloadsBlock *hclwrite.Block

	for _, block := range body.Blocks() {
		switch block.Type() {
		case "scope":
			for name, attr := range block.Body().Attributes() {
				scopeTargetAttrs = append(scopeTargetAttrs, savedAttr{name, attr.Expr().BuildTokens(nil)})
			}
			body.RemoveBlock(block)

		case "self_service":
			for name, attr := range block.Body().Attributes() {
				selfServiceAttrs = append(selfServiceAttrs, savedAttr{name, attr.Expr().BuildTokens(nil)})
			}
			body.RemoveBlock(block)

		case "payloads":
			payloadsBlock = block
			body.RemoveBlock(block)

		case "date_time_limitations", "network_limitations":
			body.RemoveBlock(block)
			report.AddReview("jamfpro_policy", "jamfplatform_pro_policy", label, file, line,
				block.Type()+" block has no equivalent — removed",
				"manually configure scheduling/network limitations if needed")
		}
	}

	// Build general = { ... }.
	if len(generalSaved) > 0 {
		var generalHCL bytes.Buffer
		generalHCL.WriteString("{\n")
		for _, sa := range generalSaved {
			generalHCL.WriteString(fmt.Sprintf("    %s = %s\n", sa.name, tokensString(sa.tokens)))
		}
		generalHCL.WriteString("  }")
		body.SetAttributeRaw("general", hclTokensForLiteral(generalHCL.String()))
	}

	// Build scope = { targets = { ... } }.
	if len(scopeTargetAttrs) > 0 {
		var scopeHCL bytes.Buffer
		scopeHCL.WriteString("{\n    targets = {\n")
		for _, sa := range scopeTargetAttrs {
			valStr := tokensString(rewriteGroupReferences(sa.tokens))
			scopeHCL.WriteString(fmt.Sprintf("      %s = %s\n", sa.name, valStr))
		}
		scopeHCL.WriteString("    }\n  }")
		body.SetAttributeRaw("scope", hclTokensForLiteral(scopeHCL.String()))
	}

	// Build self_service = { ... }.
	if len(selfServiceAttrs) > 0 {
		var ssHCL bytes.Buffer
		ssHCL.WriteString("{\n")
		for _, sa := range selfServiceAttrs {
			ssHCL.WriteString(fmt.Sprintf("    %s = %s\n", sa.name, tokensString(sa.tokens)))
		}
		ssHCL.WriteString("  }")
		body.SetAttributeRaw("self_service", hclTokensForLiteral(ssHCL.String()))
	}

	// Process payloads block.
	if payloadsBlock != nil {
		transformPolicyPayloads(body, payloadsBlock, label, report, file, line)
	}
}

// transformPolicyPayloads unwraps the payloads block into top-level attrs.
func transformPolicyPayloads(body *hclwrite.Body, payloads *hclwrite.Block, label string, report *Report, file string, line int) {
	type savedAttr struct {
		name   string
		tokens hclwrite.Tokens
	}

	for _, sub := range payloads.Body().Blocks() {
		switch sub.Type() {
		case "packages":
			// packages = { distribution_point, packages = [ { id, action, ... } ] }
			var dpTokens hclwrite.Tokens
			if dp := sub.Body().GetAttribute("distribution_point"); dp != nil {
				dpTokens = dp.Expr().BuildTokens(nil)
			}
			var pkgItems []string
			for _, pkgBlock := range sub.Body().Blocks() {
				if pkgBlock.Type() == "package" {
					pkgItems = append(pkgItems, blockToObjectLiteral(pkgBlock.Body(), "      "))
				}
			}
			var pkgHCL bytes.Buffer
			pkgHCL.WriteString("{\n")
			if dpTokens != nil {
				pkgHCL.WriteString(fmt.Sprintf("    distribution_point = %s\n", tokensString(dpTokens)))
			}
			if len(pkgItems) > 0 {
				pkgHCL.WriteString("    packages = [\n")
				for _, item := range pkgItems {
					pkgHCL.WriteString(item + ",\n")
				}
				pkgHCL.WriteString("    ]\n")
			}
			pkgHCL.WriteString("  }")
			body.SetAttributeRaw("packages", hclTokensForLiteral(pkgHCL.String()))

		case "scripts":
			var scriptItems []string
			for _, sBlock := range sub.Body().Blocks() {
				if sBlock.Type() == "script" {
					scriptItems = append(scriptItems, blockToObjectLiteral(sBlock.Body(), "      "))
				}
			}
			if len(scriptItems) > 0 {
				var scrHCL bytes.Buffer
				scrHCL.WriteString("{\n    scripts = [\n")
				for _, item := range scriptItems {
					scrHCL.WriteString(item + ",\n")
				}
				scrHCL.WriteString("    ]\n  }")
				body.SetAttributeRaw("scripts", hclTokensForLiteral(scrHCL.String()))
			}

		case "maintenance":
			objLit := blockBodyToObjectLiteral(sub.Body(), "  ")
			body.SetAttributeRaw("maintenance", hclTokensForLiteral(objLit))

		case "reboot":
			objLit := blockBodyToObjectLiteral(sub.Body(), "  ")
			body.SetAttributeRaw("restart_options", hclTokensForLiteral(objLit))

		case "files_processes":
			objLit := blockBodyToObjectLiteral(sub.Body(), "  ")
			body.SetAttributeRaw("files_and_processes", hclTokensForLiteral(objLit))

		case "account_maintenance":
			transformPolicyAccountMaintenance(body, sub.Body(), label, report, file, line)

		case "disk_encryption":
			objLit := blockBodyToObjectLiteral(sub.Body(), "  ")
			body.SetAttributeRaw("disk_encryption", hclTokensForLiteral(objLit))

		case "printers":
			var items []string
			for _, pBlock := range sub.Body().Blocks() {
				if pBlock.Type() == "printer" {
					items = append(items, blockToObjectLiteral(pBlock.Body(), "      "))
				}
			}
			if len(items) > 0 {
				var hcl bytes.Buffer
				hcl.WriteString("{\n    printers = [\n")
				for _, item := range items {
					hcl.WriteString(item + ",\n")
				}
				hcl.WriteString("    ]\n  }")
				body.SetAttributeRaw("printers", hclTokensForLiteral(hcl.String()))
			}

		case "dock_items":
			var items []string
			for _, dBlock := range sub.Body().Blocks() {
				if dBlock.Type() == "dock_item" {
					items = append(items, blockToObjectLiteral(dBlock.Body(), "      "))
				}
			}
			if len(items) > 0 {
				var hcl bytes.Buffer
				hcl.WriteString("{\n    dock_items = [\n")
				for _, item := range items {
					hcl.WriteString(item + ",\n")
				}
				hcl.WriteString("    ]\n  }")
				body.SetAttributeRaw("dock_items", hclTokensForLiteral(hcl.String()))
			}

		case "user_interaction":
			objLit := blockBodyToObjectLiteral(sub.Body(), "  ")
			body.SetAttributeRaw("user_interaction", hclTokensForLiteral(objLit))
		}
	}
}

// transformPolicyAccountMaintenance processes the account_maintenance payload block.
func transformPolicyAccountMaintenance(body *hclwrite.Body, am *hclwrite.Body, label string, report *Report, file string, line int) {
	for _, sub := range am.Blocks() {
		switch sub.Type() {
		case "local_accounts":
			// local_accounts = [ { ... password_wo_version = 1 } ]
			var items []string
			for _, acct := range sub.Body().Blocks() {
				if acct.Type() == "account" || acct.Type() == "local_account" {
					// Add password_wo_version if password exists.
					acctBody := acct.Body()
					if acctBody.GetAttribute("password") != nil && acctBody.GetAttribute("password_wo_version") == nil {
						acctBody.SetAttributeValue("password_wo_version", cty.NumberIntVal(1))
					}
					items = append(items, blockToObjectLiteral(acctBody, "    "))
				}
			}
			if len(items) > 0 {
				var hcl bytes.Buffer
				hcl.WriteString("[\n")
				for _, item := range items {
					hcl.WriteString(item + ",\n")
				}
				hcl.WriteString("  ]")
				body.SetAttributeRaw("local_accounts", hclTokensForLiteral(hcl.String()))
			}

		case "management_account":
			mgmtBody := sub.Body()
			if mgmtBody.GetAttribute("managed_password") != nil && mgmtBody.GetAttribute("managed_password_wo_version") == nil {
				mgmtBody.SetAttributeValue("managed_password_wo_version", cty.NumberIntVal(1))
			}
			objLit := blockBodyToObjectLiteral(mgmtBody, "  ")
			body.SetAttributeRaw("management_account", hclTokensForLiteral(objLit))

		case "directory_bindings":
			var items []string
			for _, b := range sub.Body().Blocks() {
				if b.Type() == "binding" {
					if id := b.Body().GetAttribute("id"); id != nil {
						items = append(items, fmt.Sprintf("    { id = %s }", tokensString(id.Expr().BuildTokens(nil))))
					}
				}
			}
			if len(items) > 0 {
				var hcl bytes.Buffer
				hcl.WriteString("[\n")
				for _, item := range items {
					hcl.WriteString(item + ",\n")
				}
				hcl.WriteString("  ]")
				body.SetAttributeRaw("directory_bindings", hclTokensForLiteral(hcl.String()))
			}

		case "efi_password":
			efiBody := sub.Body()
			if efiBody.GetAttribute("of_password") != nil && efiBody.GetAttribute("of_password_wo_version") == nil {
				efiBody.SetAttributeValue("of_password_wo_version", cty.NumberIntVal(1))
			}
			objLit := blockBodyToObjectLiteral(efiBody, "  ")
			body.SetAttributeRaw("efi_password", hclTokensForLiteral(objLit))
		}
	}
}

// transformPackage handles jamfpro_package → jamfplatform_pro_package.
func transformPackage(body *hclwrite.Body, label string, report *Report, file string, line int) {
	// package_name → display_name
	if tok := getAttrRawTokens(body, "package_name"); tok != nil {
		body.RemoveAttribute("package_name")
		body.SetAttributeRaw("display_name", tok)
	}
	// Drop attrs
	for _, d := range []string{
		"fill_user_template", "fill_existing_users", "swu", "self_heal_notify",
		"os_install", "serial_number", "suppress_updates", "ignore_conflicts",
		"suppress_from_dock", "suppress_eula", "suppress_registration",
		"manifest", "md5", "sha256", "sha3512",
	} {
		body.RemoveAttribute(d)
	}
	// manifest_file_name → manifest_file_source
	if tok := getAttrRawTokens(body, "manifest_file_name"); tok != nil {
		body.RemoveAttribute("manifest_file_name")
		body.SetAttributeRaw("manifest_file_source", tok)
	}
}

// transformDiskEncryption handles block → object restructuring and WO injection.
func transformDiskEncryption(body *hclwrite.Body, label string, report *Report, file string, line int) {
	for _, block := range body.Blocks() {
		if block.Type() == "institutional_recovery_key" {
			irkBody := block.Body()
			// Inject password_wo_version
			if irkBody.GetAttribute("password") != nil && irkBody.GetAttribute("password_wo_version") == nil {
				irkBody.SetAttributeValue("password_wo_version", cty.NumberIntVal(1))
			}
			objLit := blockBodyToObjectLiteral(irkBody, "  ")
			body.RemoveBlock(block)
			body.SetAttributeRaw("institutional_recovery_key", hclTokensForLiteral(objLit))
			break
		}
	}
}

// transformAccount handles jamfpro_account → jamfplatform_pro_account.
func transformAccount(body *hclwrite.Body, label string, report *Report, file string, line int) {
	// name → username
	if tok := getAttrRawTokens(body, "name"); tok != nil {
		body.RemoveAttribute("name")
		body.SetAttributeRaw("username", tok)
	}
	// email → email_address
	if tok := getAttrRawTokens(body, "email"); tok != nil {
		body.RemoveAttribute("email")
		body.SetAttributeRaw("email_address", tok)
	}
	// Drop attrs
	for _, d := range []string{"directory_user", "site_id", "force_password_change"} {
		body.RemoveAttribute(d)
	}
	// password_wo_version
	if body.GetAttribute("password") != nil && body.GetAttribute("password_wo_version") == nil {
		body.SetAttributeValue("password_wo_version", cty.NumberIntVal(1))
	}
	// Privilege restructuring
	transformPrivileges(body, report, label, file, line)

	report.AddReview("jamfpro_account", "jamfplatform_pro_account", label, file, line,
		"jss_settings_privileges and casper_admin_privileges dropped (no equivalents)",
		"verify privilege set is complete in new schema")
}

// transformAccountGroup handles jamfpro_account_group → jamfplatform_pro_account_group.
func transformAccountGroup(body *hclwrite.Body, label string, report *Report, file string, line int) {
	// name → display_name
	if tok := getAttrRawTokens(body, "name"); tok != nil {
		body.RemoveAttribute("name")
		body.SetAttributeRaw("display_name", tok)
	}
	// identity_server_id → ldap_server_id
	if tok := getAttrRawTokens(body, "identity_server_id"); tok != nil {
		body.RemoveAttribute("identity_server_id")
		body.SetAttributeRaw("ldap_server_id", tok)
	}
	body.RemoveAttribute("site_id")
	transformPrivileges(body, report, label, file, line)
}

// transformPrivileges converts jss_objects_privileges/jss_actions_privileges flat lists
// to a privileges = { jamf_pro_server_objects = [...], jamf_pro_server_actions = [...] } object.
func transformPrivileges(body *hclwrite.Body, report *Report, label string, file string, line int) {
	objsTok := getAttrRawTokens(body, "jss_objects_privileges")
	actsTok := getAttrRawTokens(body, "jss_actions_privileges")
	body.RemoveAttribute("jss_objects_privileges")
	body.RemoveAttribute("jss_actions_privileges")
	body.RemoveAttribute("jss_settings_privileges")
	body.RemoveAttribute("casper_admin_privileges")

	if objsTok == nil && actsTok == nil {
		return
	}

	var privHCL bytes.Buffer
	privHCL.WriteString("{\n")
	if objsTok != nil {
		privHCL.WriteString(fmt.Sprintf("    jamf_pro_server_objects = %s\n", tokensString(objsTok)))
	}
	if actsTok != nil {
		privHCL.WriteString(fmt.Sprintf("    jamf_pro_server_actions = %s\n", tokensString(actsTok)))
	}
	privHCL.WriteString("  }")
	body.SetAttributeRaw("privileges", hclTokensForLiteral(privHCL.String()))
}

// transformLDAPServer handles the major LDAP server restructuring.
func transformLDAPServer(body *hclwrite.Body, label string, report *Report, file string, line int) {
	// Collect connection-related attrs
	connAttrs := []string{
		"hostname", "port", "use_ssl", "authentication_type", "open_close_timeout",
		"search_timeout", "referral_response", "use_wildcards", "server_type",
	}
	type savedAttr struct {
		name   string
		tokens hclwrite.Tokens
	}
	var connSaved []savedAttr
	for _, a := range connAttrs {
		tok := getAttrRawTokens(body, a)
		if tok != nil {
			outName := a
			if a == "open_close_timeout" {
				outName = "connection_timeout"
			} else if a == "server_type" {
				outName = "directory_service"
			}
			connSaved = append(connSaved, savedAttr{outName, tok})
			body.RemoveAttribute(a)
		}
	}

	// Collect account block
	var acctAttrs []savedAttr
	for _, block := range body.Blocks() {
		if block.Type() == "account" {
			for name, attr := range block.Body().Attributes() {
				acctAttrs = append(acctAttrs, savedAttr{name, attr.Expr().BuildTokens(nil)})
			}
			body.RemoveBlock(block)
			break
		}
	}

	// Collect mapping blocks
	type mappingBlock struct {
		blockType string
		attrs     []savedAttr
	}
	var mappingBlocks []mappingBlock
	for _, block := range body.Blocks() {
		switch block.Type() {
		case "user_mappings", "user_group_mappings", "user_group_membership_mappings":
			var attrs []savedAttr
			for name, attr := range block.Body().Attributes() {
				outName := name
				if name == "map_object_class_to_any_or_all" {
					outName = "object_class_limitation"
				}
				attrs = append(attrs, savedAttr{outName, attr.Expr().BuildTokens(nil)})
			}
			mappingBlocks = append(mappingBlocks, mappingBlock{block.Type(), attrs})
			body.RemoveBlock(block)
		}
	}

	// Build connection_settings = { ... account = { ... } }
	var connHCL bytes.Buffer
	connHCL.WriteString("{\n")
	for _, sa := range connSaved {
		connHCL.WriteString(fmt.Sprintf("    %s = %s\n", sa.name, tokensString(sa.tokens)))
	}
	if len(acctAttrs) > 0 {
		connHCL.WriteString("    account = {\n")
		for _, sa := range acctAttrs {
			connHCL.WriteString(fmt.Sprintf("      %s = %s\n", sa.name, tokensString(sa.tokens)))
		}
		// Inject password_wo_version if needed.
		hasPass := false
		for _, sa := range acctAttrs {
			if sa.name == "password" {
				hasPass = true
			}
		}
		if hasPass {
			connHCL.WriteString("      password_wo_version = 1\n")
		}
		connHCL.WriteString("    }\n")
	}
	connHCL.WriteString("  }")
	body.SetAttributeRaw("connection_settings", hclTokensForLiteral(connHCL.String()))

	// Build mappings_for_users = { ... }
	if len(mappingBlocks) > 0 {
		var mapHCL bytes.Buffer
		mapHCL.WriteString("{\n")
		for _, mb := range mappingBlocks {
			mapHCL.WriteString(fmt.Sprintf("    %s = {\n", mb.blockType))
			for _, sa := range mb.attrs {
				mapHCL.WriteString(fmt.Sprintf("      %s = %s\n", sa.name, tokensString(sa.tokens)))
			}
			mapHCL.WriteString("    }\n")
		}
		mapHCL.WriteString("  }")
		body.SetAttributeRaw("mappings_for_users", hclTokensForLiteral(mapHCL.String()))
	}
}

// transformRestrictedSoftware restructures jamfpro_restricted_software.
func transformRestrictedSoftware(body *hclwrite.Body, label string, report *Report, file string, line int) {
	generalAttrNames := map[string]bool{
		"name": true, "process_name": true, "display_message": true, "site_id": true,
		"match_exact_process_name": true, "send_notification": true,
		"delete_executable": true, "kill_process": true,
	}
	generalRenames := map[string]string{
		"match_exact_process_name": "restrict_exact_process_name",
		"send_notification":        "send_email_notification_on_violation",
		"delete_executable":        "delete_application",
	}

	type savedAttr struct {
		name   string
		tokens hclwrite.Tokens
	}
	var generalSaved []savedAttr
	for _, attrName := range orderedAttrNames(body) {
		if !generalAttrNames[attrName] {
			continue
		}
		tok := getAttrRawTokens(body, attrName)
		if tok != nil {
			outName := attrName
			if renamed, ok := generalRenames[attrName]; ok {
				outName = renamed
			}
			generalSaved = append(generalSaved, savedAttr{outName, tok})
			body.RemoveAttribute(attrName)
		}
	}

	var scopeTargetAttrs []savedAttr
	for _, block := range body.Blocks() {
		if block.Type() == "scope" {
			scopeBody := block.Body()
			for _, name := range orderedAttrNames(scopeBody) {
				attr := scopeBody.GetAttribute(name)
				if attr != nil {
					scopeTargetAttrs = append(scopeTargetAttrs, savedAttr{name, attr.Expr().BuildTokens(nil)})
				}
			}
			body.RemoveBlock(block)
			break
		}
	}

	// Build general = { ... }
	if len(generalSaved) > 0 {
		var genHCL bytes.Buffer
		genHCL.WriteString("{\n")
		for _, sa := range generalSaved {
			genHCL.WriteString(fmt.Sprintf("    %s = %s\n", sa.name, tokensString(sa.tokens)))
		}
		genHCL.WriteString("  }")
		body.SetAttributeRaw("general", hclTokensForLiteral(genHCL.String()))
	}

	// Build scope = { targets = { ... }, exclusions = { ... } }
	if len(scopeTargetAttrs) > 0 {
		var scopeHCL bytes.Buffer
		scopeHCL.WriteString("{\n    targets = {\n")
		for _, sa := range scopeTargetAttrs {
			valStr := tokensString(rewriteGroupReferences(sa.tokens))
			scopeHCL.WriteString(fmt.Sprintf("      %s = %s\n", sa.name, valStr))
		}
		scopeHCL.WriteString("    }\n  }")
		body.SetAttributeRaw("scope", hclTokensForLiteral(scopeHCL.String()))
	}
}

// transformInventoryCollection flattens the nested block structure.
func transformInventoryCollection(body *hclwrite.Body, label string, report *Report, file string, line int) {
	// Attr renames from the nested computer_inventory_collection_preferences block to top level.
	renames := map[string]string{
		"monitor_application_usage":                          "collect_application_usage_information",
		"include_packages":                                   "collect_package_receipts",
		"include_software_updates":                          "collect_available_software_updates",
		"include_accounts":                                   "collect_local_user_accounts",
		"calculate_sizes":                                    "include_home_directory_sizes",
		"monitor_beacons":                                    "collect_beacons",
		"update_ldap_info_on_computer_inventory_submissions": "collect_user_and_location_from_directory_service",
		"allow_changing_user_and_location":                   "allow_jamf_binary_user_and_location_changes",
		"include_hidden_accounts":                            "collect_active_directory_mobile_account_info",
		"use_unix_user_paths":                                "use_unix_user_paths",
	}

	for _, block := range body.Blocks() {
		if block.Type() == "computer_inventory_collection_preferences" {
			prefBody := block.Body()
			// Move attrs out of nested block to top level with renames.
			for oldName, newName := range renames {
				if tok := getAttrRawTokens(prefBody, oldName); tok != nil {
					body.SetAttributeRaw(newName, tok)
				}
			}
			// application_paths blocks → application_search_paths list
			var paths []string
			for _, pathBlock := range prefBody.Blocks() {
				if pathBlock.Type() == "application_paths" {
					if p := pathBlock.Body().GetAttribute("path"); p != nil {
						paths = append(paths, tokensString(p.Expr().BuildTokens(nil)))
					}
				}
			}
			if len(paths) > 0 {
				var listHCL bytes.Buffer
				listHCL.WriteString("[")
				for i, p := range paths {
					if i > 0 {
						listHCL.WriteString(", ")
					}
					listHCL.WriteString(p)
				}
				listHCL.WriteString("]")
				body.SetAttributeRaw("application_search_paths", hclTokensForLiteral(listHCL.String()))
			}
			body.RemoveBlock(block)
			break
		}
	}
}

// transformSSOSettings handles SSO settings restructuring.
func transformSSOSettings(body *hclwrite.Body, label string, report *Report, file string, line int) {
	// For SSO settings, convert sub-blocks to object attrs and inject WO versions.
	for _, block := range body.Blocks() {
		switch block.Type() {
		case "oidc_settings", "saml_settings":
			// keystore_password_wo_version injection
			samlBody := block.Body()
			if samlBody.GetAttribute("keystore_password") != nil && samlBody.GetAttribute("keystore_password_wo_version") == nil {
				samlBody.SetAttributeValue("keystore_password_wo_version", cty.NumberIntVal(1))
			}
			objLit := blockBodyToObjectLiteral(samlBody, "  ")
			body.SetAttributeRaw(block.Type(), hclTokensForLiteral(objLit))
			body.RemoveBlock(block)
		}
	}
}

// transformAdvancedComputerSearch restructures criteria blocks → list.
func transformAdvancedComputerSearch(body *hclwrite.Body, label string, report *Report, file string, line int) {
	// Drop view_as, sort1, sort2, sort3
	for _, d := range []string{"view_as", "sort1", "sort2", "sort3"} {
		body.RemoveAttribute(d)
	}
	transformCriteriaBlocks(body)
}

// transformAdvancedMobileSearch restructures criteria blocks → list.
func transformAdvancedMobileSearch(body *hclwrite.Body, label string, report *Report, file string, line int) {
	for _, d := range []string{"view_as", "sort1", "sort2", "sort3"} {
		body.RemoveAttribute(d)
	}
	transformCriteriaBlocks(body)
}

// transformCriteriaBlocks converts old criteria { } blocks to criteria = [ { } ] list.
func transformCriteriaBlocks(body *hclwrite.Body) {
	type criteriaItem struct {
		name         string
		searchType   string
		value        string
		andOr        string
		openParen    string
		closeParen   string
		index        int
	}

	var items []criteriaItem
	idx := 0
	for _, block := range body.Blocks() {
		if block.Type() == "criteria" {
			item := criteriaItem{index: idx}
			item.name = getAttrStringValue(block.Body(), "name")
			item.searchType = getAttrStringValue(block.Body(), "search_type")
			item.value = getAttrStringValue(block.Body(), "value")
			item.andOr = getAttrStringValue(block.Body(), "and_or")
			item.openParen = getAttrStringValue(block.Body(), "opening_paren")
			item.closeParen = getAttrStringValue(block.Body(), "closing_paren")
			items = append(items, item)
			body.RemoveBlock(block)
			idx++
		}
	}

	if len(items) == 0 {
		return
	}

	var listHCL bytes.Buffer
	listHCL.WriteString("[\n")
	for i, item := range items {
		listHCL.WriteString("    {\n")
		if i > 0 && item.andOr != "" {
			listHCL.WriteString(fmt.Sprintf("      and_or   = %q\n", item.andOr))
		}
		if item.openParen == "true" {
			listHCL.WriteString("      has_opening_parenthesis = true\n")
		}
		listHCL.WriteString(fmt.Sprintf("      criteria = %q\n", item.name))
		listHCL.WriteString(fmt.Sprintf("      operator = %q\n", item.searchType))
		listHCL.WriteString(fmt.Sprintf("      value    = %q\n", item.value))
		if item.closeParen == "true" {
			listHCL.WriteString("      has_closing_parenthesis = true\n")
		}
		listHCL.WriteString("    },\n")
	}
	listHCL.WriteString("  ]")
	body.SetAttributeRaw("criteria", hclTokensForLiteral(listHCL.String()))
}

// transformDeviceGroup handles Tier 4 smart group criteria conversion.
func transformDeviceGroup(body *hclwrite.Body, groupType, deviceType string, label string, report *Report, file string, line int) {
	// Inject group_type and device_type after name attr.
	body.SetAttributeValue("group_type", cty.StringVal(groupType))
	body.SetAttributeValue("device_type", cty.StringVal(deviceType))

	// Drop site_id (not in new schema).
	body.RemoveAttribute("site_id")

	if groupType == "smart" {
		transformCriteriaBlocks(body)
	} else {
		// Static group: warn about member ID conversion.
		if body.GetAttribute("members") != nil {
			report.AddReview("", "jamfplatform_device_group", label, file, line,
				"static group members converted from numeric Jamf Pro IDs (values unchanged)",
				"replace member values with device UDIDs from Jamf Pro API")
		}
	}
}

// transformEnrollmentCustomization restructures enrollment customization.
func transformEnrollmentCustomization(body *hclwrite.Body, label string, report *Report, file string, line int) {
	for _, block := range body.Blocks() {
		switch block.Type() {
		case "branding_settings":
			bsBody := block.Body()
			// text_color → body_text_color
			if tok := getAttrRawTokens(bsBody, "text_color"); tok != nil {
				bsBody.RemoveAttribute("text_color")
				bsBody.SetAttributeRaw("body_text_color", tok)
			}
			// enrollment_customization_image_source → icon_source
			if tok := getAttrRawTokens(bsBody, "enrollment_customization_image_source"); tok != nil {
				bsBody.RemoveAttribute("enrollment_customization_image_source")
				bsBody.SetAttributeRaw("icon_source", tok)
			}
			objLit := blockBodyToObjectLiteral(bsBody, "  ")
			body.SetAttributeRaw("branding_settings", hclTokensForLiteral(objLit))
			body.RemoveBlock(block)
		}
	}

	// Pane block types → list attrs (text_pane → text_panes, etc.)
	paneTypes := []struct{ singular, plural string }{
		{"text_pane", "text_panes"},
		{"ldap_pane", "ldap_panes"},
		{"sso_pane", "sso_panes"},
	}
	for _, pt := range paneTypes {
		var paneItems []string
		for _, block := range body.Blocks() {
			if block.Type() == pt.singular {
				paneBody := block.Body()
				// Renames within panes.
				if tok := getAttrRawTokens(paneBody, "back_button_text"); tok != nil {
					paneBody.RemoveAttribute("back_button_text")
					paneBody.SetAttributeRaw("previous_button_text", tok)
				}
				if tok := getAttrRawTokens(paneBody, "continue_button_text"); tok != nil {
					paneBody.RemoveAttribute("continue_button_text")
					paneBody.SetAttributeRaw("next_button_text", tok)
				}
				// LDAP pane renames.
				if tok := getAttrRawTokens(paneBody, "short_name_attribute"); tok != nil {
					paneBody.RemoveAttribute("short_name_attribute")
					paneBody.SetAttributeRaw("account_name_attribute", tok)
				}
				if tok := getAttrRawTokens(paneBody, "long_name_attribute"); tok != nil {
					paneBody.RemoveAttribute("long_name_attribute")
					paneBody.SetAttributeRaw("account_full_name_attribute", tok)
				}
				// SSO pane renames.
				if tok := getAttrRawTokens(paneBody, "is_use_jamf_connect"); tok != nil {
					paneBody.RemoveAttribute("is_use_jamf_connect")
					paneBody.SetAttributeRaw("pass_user_info_to_jamf_connect", tok)
				}
				paneItems = append(paneItems, blockToObjectLiteral(paneBody, "    "))
				body.RemoveBlock(block)
			}
		}
		if len(paneItems) > 0 {
			var listHCL bytes.Buffer
			listHCL.WriteString("[\n")
			for _, item := range paneItems {
				listHCL.WriteString(item + ",\n")
			}
			listHCL.WriteString("  ]")
			body.SetAttributeRaw(pt.plural, hclTokensForLiteral(listHCL.String()))
		}
	}
}

// transformComputerPrestage handles computer prestage enrollment restructuring.
func transformComputerPrestage(body *hclwrite.Body, label string, report *Report, file string, line int) {
	transformPrestageCommon(body, false)
	// admin_password_wo_version
	for _, block := range body.Blocks() {
		if block.Type() == "account_settings" {
			asBody := block.Body()
			if asBody.GetAttribute("admin_management_password") != nil && asBody.GetAttribute("admin_password_wo_version") == nil {
				asBody.SetAttributeValue("admin_password_wo_version", cty.NumberIntVal(1))
			}
		}
	}
	// Drop computer-specific attrs
	for _, d := range []string{
		"prestage_installed_profile_ids", "custom_package_ids",
		"custom_package_distribution_point_id", "recovery_lock_password",
		"recovery_lock_password_type", "rotate_recovery_lock_password",
	} {
		body.RemoveAttribute(d)
	}
	// Add scope_serial_numbers if not present
	if body.GetAttribute("scope_serial_numbers") == nil {
		body.SetAttributeRaw("scope_serial_numbers", hclTokensForLiteral("[]"))
	}
}

// transformMobileDevicePrestage handles mobile device prestage enrollment restructuring.
func transformMobileDevicePrestage(body *hclwrite.Body, label string, report *Report, file string, line int) {
	transformPrestageCommon(body, true)
	// names block restructuring
	for _, block := range body.Blocks() {
		if block.Type() == "names" {
			namesBody := block.Body()
			var namesAttrs []struct {
				name   string
				tokens hclwrite.Tokens
			}
			for _, keep := range []string{"assign_names_using", "manage_names"} {
				if tok := getAttrRawTokens(namesBody, keep); tok != nil {
					namesAttrs = append(namesAttrs, struct {
						name   string
						tokens hclwrite.Tokens
					}{keep, tok})
				}
			}
			var namesHCL bytes.Buffer
			namesHCL.WriteString("{\n")
			for _, na := range namesAttrs {
				namesHCL.WriteString(fmt.Sprintf("    %s = %s\n", na.name, tokensString(na.tokens)))
			}
			namesHCL.WriteString("    prestage_device_names = []\n")
			namesHCL.WriteString("  }")
			body.SetAttributeRaw("names", hclTokensForLiteral(namesHCL.String()))
			body.RemoveBlock(block)
			break
		}
	}
	// Add scope_serial_numbers if not present
	if body.GetAttribute("scope_serial_numbers") == nil {
		body.SetAttributeRaw("scope_serial_numbers", hclTokensForLiteral("[]"))
	}
}

// transformPrestageCommon handles blocks common to both prestage types.
func transformPrestageCommon(body *hclwrite.Body, isMobile bool) {
	blockTypes := []string{"skip_setup_items", "location_information", "purchasing_information", "account_settings"}
	for _, bt := range blockTypes {
		for _, block := range body.Blocks() {
			if block.Type() == bt {
				objLit := blockBodyToObjectLiteral(block.Body(), "  ")
				body.SetAttributeRaw(bt, hclTokensForLiteral(objLit))
				body.RemoveBlock(block)
				break
			}
		}
	}
}

// ── HCL text helpers ──────────────────────────────────────────────────────────

// tokensString serializes tokens to a string, trimming leading/trailing whitespace.
func tokensString(tokens hclwrite.Tokens) string {
	var buf bytes.Buffer
	for _, t := range tokens {
		buf.Write(t.Bytes)
	}
	return strings.TrimSpace(buf.String())
}

// blockBodyToObjectLiteral serializes a body's attributes as a { } object literal.
// Attribute order is document order (via orderedAttrNames) for deterministic output.
func blockBodyToObjectLiteral(b *hclwrite.Body, indent string) string {
	var buf bytes.Buffer
	buf.WriteString("{\n")
	for _, name := range orderedAttrNames(b) {
		attr := b.GetAttribute(name)
		if attr == nil {
			continue
		}
		val := tokensString(attr.Expr().BuildTokens(nil))
		buf.WriteString(fmt.Sprintf("%s  %s = %s\n", indent, name, val))
	}
	buf.WriteString(indent + "}")
	return buf.String()
}

// blockToObjectLiteral serializes a block body as an indented { } object literal entry.
func blockToObjectLiteral(b *hclwrite.Body, indent string) string {
	return blockBodyToObjectLiteral(b, indent)
}

