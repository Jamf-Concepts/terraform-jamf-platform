package migrate

import (
	"github.com/hashicorp/hcl/v2/hclwrite"
)

// AttrMapping describes how a single attribute should be handled.
type AttrMapping struct {
	From      string
	To        string                                  // empty = drop attr
	Transform func(hclwrite.Tokens) hclwrite.Tokens  // nil = copy verbatim
}

// ResourceMapping describes the full migration for one source resource type.
type ResourceMapping struct {
	FromType string
	ToType   string
	Tier     int

	// Tier 1 & 2: attribute-level renames/drops expressed as a lookup table.
	// Any attr not mentioned is copied verbatim.
	Attrs []AttrMapping

	// DropAttrs is a convenience list of attribute names to silently drop.
	// Equivalent to an AttrMapping with empty To.
	DropAttrs []string

	// InjectAttrs are fixed key=value pairs added after the named anchor attr.
	// key: anchor attr name; value: "attrName = value" string to inject.
	InjectAfter map[string]string

	// WriteOnlyFields maps secret attr names to their *_wo_version sibling name.
	// When the secret attr is found, the wo_version attr is injected after it.
	WriteOnlyFields map[string]string

	// Tier 4 folded-type fields.
	FoldedGroupType  string // "smart" or "static"
	FoldedDeviceType string // "computer" or "mobile"

	// StructuralTransform is called for Tier 3 resources that need deep rewrites.
	// It receives the body block and may mutate it in place or return a new block.
	StructuralTransform func(body *hclwrite.Body, label string, report *Report, file string, line int)

	// ReviewNote is added to every instance's report entry (used for resources
	// that always need review regardless of attrs).
	ReviewNote string
	ReviewAction string

	// SkipReason non-empty means this resource has no equivalent and should be
	// left unchanged while a skip entry is added to the report.
	SkipReason string
}

// Registry is the ordered list of all known resource mappings.
var Registry []ResourceMapping

func init() {
	Registry = buildRegistry()
}

func buildRegistry() []ResourceMapping {
	var r []ResourceMapping

	// ── Tier 1: rename only ───────────────────────────────────────────────────

	tier1 := []struct{ from, to string }{
		{"jamfpro_category", "jamfplatform_pro_category"},
		{"jamfpro_department", "jamfplatform_pro_department"},
		{"jamfpro_site", "jamfplatform_pro_site"},
		{"jamfpro_dock_item", "jamfplatform_pro_dock_item"},
		{"jamfpro_api_role", "jamfplatform_pro_api_role"},
		{"jamfpro_access_management_settings", "jamfplatform_pro_access_management_settings"},
		{"jamfpro_impact_alert_notification_settings", "jamfplatform_pro_impact_alert_notification_settings"},
	}
	for _, t := range tier1 {
		r = append(r, ResourceMapping{
			FromType: t.from,
			ToType:   t.to,
			Tier:     1,
		})
	}

	// ── Tier 2: attr remap ────────────────────────────────────────────────────

	r = append(r, ResourceMapping{
		FromType: "jamfpro_building",
		ToType:   "jamfplatform_pro_building",
		Tier:     2,
		Attrs: []AttrMapping{
			{From: "street_address1", To: "street_address_1"},
			{From: "street_address2", To: "street_address_2"},
		},
	})

	r = append(r, ResourceMapping{
		FromType:  "jamfpro_network_segment",
		ToType:    "jamfplatform_pro_network_segment",
		Tier:      2,
		DropAttrs: []string{"distribution_server", "distribution_point", "url", "swu_server"},
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_computer_extension_attribute",
		ToType:   "jamfplatform_pro_computer_extension_attribute",
		Tier:     2,
		Attrs: []AttrMapping{
			{From: "inventory_display_type", To: "inventory_display"},
			{From: "script_contents", To: "script"},
		},
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_mobile_device_extension_attribute",
		ToType:   "jamfplatform_pro_mobile_device_extension_attribute",
		Tier:     2,
		Attrs: []AttrMapping{
			{From: "inventory_display_type", To: "inventory_display"},
		},
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_allowed_file_extension",
		ToType:   "jamfplatform_pro_allowed_file_extension",
		Tier:     2,
		Attrs: []AttrMapping{
			{From: "extension", To: "extension", Transform: stripLeadingDot},
		},
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_printer",
		ToType:   "jamfplatform_pro_printer",
		Tier:     2,
		Attrs: []AttrMapping{
			{From: "category_name", To: "category"},
		},
	})

	r = append(r, ResourceMapping{
		FromType:  "jamfpro_script",
		ToType:    "jamfplatform_pro_script",
		Tier:      2,
		DropAttrs: []string{"category_id"},
		Attrs: []AttrMapping{
			{From: "script_contents", To: "script"},
			{From: "priority", To: "priority", Transform: scriptPriorityTransform},
			{From: "parameter4", To: "parameter_4"},
			{From: "parameter5", To: "parameter_5"},
			{From: "parameter6", To: "parameter_6"},
			{From: "parameter7", To: "parameter_7"},
			{From: "parameter8", To: "parameter_8"},
			{From: "parameter9", To: "parameter_9"},
			{From: "parameter10", To: "parameter_10"},
			{From: "parameter11", To: "parameter_11"},
		},
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_api_integration",
		ToType:   "jamfplatform_pro_api_client",
		Tier:     2,
		Attrs: []AttrMapping{
			{From: "authorization_scopes", To: "api_roles"},
		},
		InjectAfter: map[string]string{
			"enabled": `credential_rotation = "1"`,
		},
	})

	r = append(r, ResourceMapping{
		FromType:  "jamfpro_client_checkin",
		ToType:    "jamfplatform_pro_computer_check_in_settings",
		Tier:      2,
		DropAttrs: []string{"enable_local_configuration_profiles"},
		Attrs: []AttrMapping{
			{From: "create_hooks", To: "create_login_hook"},
			{From: "hook_log", To: "login_hook_log"},
			{From: "hook_policies", To: "login_hook_policies"},
		},
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_icon",
		ToType:   "jamfplatform_pro_icon",
		Tier:     2,
		StructuralTransform: transformIcon,
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_webhook",
		ToType:   "jamfplatform_pro_webhook",
		Tier:     2,
		WriteOnlyFields: map[string]string{
			"password": "password_wo_version",
		},
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_jamf_protect",
		ToType:   "jamfplatform_pro_jamf_protect",
		Tier:     2,
		Attrs: []AttrMapping{
			{From: "protect_url", To: "api_url"},
		},
		WriteOnlyFields: map[string]string{
			"password": "password_wo_version",
		},
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_jamf_connect",
		ToType:   "jamfplatform_pro_jamf_connect",
		Tier:     2,
		Attrs: []AttrMapping{
			{From: "config_profile_uuid", To: "profile_id"},
		},
		ReviewNote:   "config_profile_uuid → profile_id is now a numeric Jamf Pro ID, not a UUID",
		ReviewAction: "replace value with the correct Jamf Pro numeric profile ID",
	})

	r = append(r, ResourceMapping{
		FromType:  "jamfpro_local_admin_password_settings",
		ToType:    "jamfplatform_pro_local_admin_password_settings",
		Tier:      2,
		DropAttrs: []string{"auto_rotate_enabled"},
		Attrs: []AttrMapping{
			{From: "auto_deploy_enabled", To: "laps_for_prestage_accounts_enabled"},
			{From: "password_rotation_time_seconds", To: "rotation_interval"},
			{From: "auto_rotate_expiration_time_seconds", To: "rotation_after_viewing_interval"},
		},
		ReviewNote:   "rotation_interval and rotation_after_viewing_interval changed from integer seconds to duration strings (e.g. 86400 → \"1 day\")",
		ReviewAction: "update rotation_interval and rotation_after_viewing_interval values to duration strings",
	})

	r = append(r, ResourceMapping{
		FromType: "jamfpro_smtp_server",
		ToType:   "jamfplatform_pro_smtp_server",
		Tier:     2,
		WriteOnlyFields: map[string]string{
			"password":      "password_wo_version",
			"client_secret": "client_secret_wo_version",
		},
	})

	r = append(r, ResourceMapping{
		FromType:  "jamfpro_app_installer",
		ToType:    "jamfplatform_pro_app_installer",
		Tier:      2,
		DropAttrs: []string{"enabled", "install_predefined_config_profiles", "trigger_admin_notifications"},
		Attrs: []AttrMapping{
			{From: "deployment_type", To: "deployment_type", Transform: appInstallerDeploymentTypeTransform},
		},
		StructuralTransform: transformAppInstaller,
		ReviewNote:          "app_title_name added (same value as name) — verify catalog title matches exactly",
		ReviewAction:        "verify app_title_name matches the exact title in the Jamf App Catalog",
	})

	// Simple type renames (confirm attrs match examples)
	tier2Renames := []struct{ from, to string }{
		{"jamfpro_sso_failover", "jamfplatform_pro_sso_failover_url"},
		{"jamfpro_reenrollment", "jamfplatform_pro_re_enrollment_settings"},
		{"jamfpro_app_installer_global_settings", "jamfplatform_pro_app_installer_settings"},
		{"jamfpro_managed_software_updates", "jamfplatform_pro_managed_software_update"},
		{"jamfpro_macos_onboarding_settings", "jamfplatform_pro_macos_onboarding"},
		{"jamfpro_adcs_settings", "jamfplatform_pro_pki_adcs"},
		{"jamfpro_mac_application", "jamfplatform_pro_mac_app_store_app"},
		{"jamfpro_mobile_device_application", "jamfplatform_pro_mobile_device_app"},
		{"jamfpro_self_service_settings", "jamfplatform_pro_self_service_macos_settings"},
		{"jamfpro_user_group", "jamfplatform_pro_user_group"},
		{"jamfpro_service_discovery_enrollment_well_known_settings", "jamfplatform_pro_service_discovery_enrollment"},
		{"jamfpro_cloud_ldap", "jamfplatform_pro_cloud_identity_provider"},
		{"jamfpro_volume_purchasing_locations", "jamfplatform_pro_volume_purchasing_location"},
	}
	for _, t := range tier2Renames {
		r = append(r, ResourceMapping{
			FromType: t.from,
			ToType:   t.to,
			Tier:     2,
		})
	}

	// ── Tier 3: structural rewrites ───────────────────────────────────────────

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_macos_configuration_profile_plist",
		ToType:              "jamfplatform_pro_macos_configuration_profile",
		Tier:                3,
		StructuralTransform: transformMacOSProfile,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_mobile_device_configuration_profile_plist",
		ToType:              "jamfplatform_pro_mobile_device_configuration_profile",
		Tier:                3,
		StructuralTransform: transformMobileProfile,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_policy",
		ToType:              "jamfplatform_pro_policy",
		Tier:                3,
		StructuralTransform: transformPolicy,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_package",
		ToType:              "jamfplatform_pro_package",
		Tier:                3,
		StructuralTransform: transformPackage,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_disk_encryption_configuration",
		ToType:              "jamfplatform_pro_disk_encryption_configuration",
		Tier:                3,
		StructuralTransform: transformDiskEncryption,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_account",
		ToType:              "jamfplatform_pro_account",
		Tier:                3,
		StructuralTransform: transformAccount,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_account_group",
		ToType:              "jamfplatform_pro_account_group",
		Tier:                3,
		StructuralTransform: transformAccountGroup,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_ldap_server",
		ToType:              "jamfplatform_pro_ldap_server",
		Tier:                3,
		StructuralTransform: transformLDAPServer,
		ReviewNote:          "LDAP server restructured into connection_settings and mappings_for_users objects — security-sensitive, verify all sub-attributes",
		ReviewAction:        "review all connection_settings and mappings_for_users sub-attributes carefully",
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_restricted_software",
		ToType:              "jamfplatform_pro_restricted_software",
		Tier:                3,
		StructuralTransform: transformRestrictedSoftware,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_computer_inventory_collection_settings",
		ToType:              "jamfplatform_pro_computer_inventory_collection_settings",
		Tier:                3,
		StructuralTransform: transformInventoryCollection,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_sso_settings",
		ToType:              "jamfplatform_pro_sso_settings",
		Tier:                3,
		StructuralTransform: transformSSOSettings,
		ReviewNote:          "SSO settings restructured — security-sensitive, verify all sub-attributes",
		ReviewAction:        "review sso_settings carefully; SAML and OIDC sub-attrs may differ",
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_advanced_computer_search",
		ToType:              "jamfplatform_pro_advanced_computer_search",
		Tier:                3,
		StructuralTransform: transformAdvancedComputerSearch,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_advanced_mobile_device_search",
		ToType:              "jamfplatform_pro_advanced_mobile_device_search",
		Tier:                3,
		StructuralTransform: transformAdvancedMobileSearch,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_enrollment_customization",
		ToType:              "jamfplatform_pro_enrollment_customization",
		Tier:                3,
		StructuralTransform: transformEnrollmentCustomization,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_computer_prestage_enrollment",
		ToType:              "jamfplatform_pro_computer_prestage_enrollment",
		Tier:                3,
		StructuralTransform: transformComputerPrestage,
	})

	r = append(r, ResourceMapping{
		FromType:            "jamfpro_mobile_device_prestage_enrollment",
		ToType:              "jamfplatform_pro_mobile_device_prestage_enrollment",
		Tier:                3,
		StructuralTransform: transformMobileDevicePrestage,
	})

	// ── Tier 4: folded device groups ──────────────────────────────────────────

	tier4 := []struct {
		from      string
		groupType string
		devType   string
	}{
		{"jamfpro_smart_computer_group", "smart", "computer"},
		{"jamfpro_smart_computer_group_v2", "smart", "computer"},
		{"jamfpro_static_computer_group", "static", "computer"},
		{"jamfpro_smart_mobile_device_group", "smart", "mobile"},
		{"jamfpro_smart_mobile_device_group_v2", "smart", "mobile"},
		{"jamfpro_static_mobile_device_group", "static", "mobile"},
	}
	for _, t := range tier4 {
		r = append(r, ResourceMapping{
			FromType:         t.from,
			ToType:           "jamfplatform_device_group",
			Tier:             4,
			FoldedGroupType:  t.groupType,
			FoldedDeviceType: t.devType,
		})
	}

	// ── Skipped resources ─────────────────────────────────────────────────────

	skipped := []struct{ from, reason string }{
		{"jamfpro_engage_settings", "no jamfplatform_pro equivalent — Jamf Engage feature removed"},
		{"jamfpro_managed_software_update_feature_toggle", "no equivalent — likely implicit in managed_software_update"},
		{"jamfpro_account_driven_user_enrollment_settings", "no equivalent found — flag for manual research"},
		{"jamfpro_device_communication_settings", "no equivalent found — flag for manual research"},
		{"jamfpro_device_enrollments", "superseded by automated_device_enrollment and related resources"},
	}
	for _, s := range skipped {
		r = append(r, ResourceMapping{
			FromType:   s.from,
			SkipReason: s.reason,
		})
	}

	return r
}

// RegistryByFromType returns a map from source type string to mapping for fast lookup.
func RegistryByFromType() map[string]*ResourceMapping {
	m := make(map[string]*ResourceMapping, len(Registry))
	for i := range Registry {
		m[Registry[i].FromType] = &Registry[i]
	}
	return m
}
