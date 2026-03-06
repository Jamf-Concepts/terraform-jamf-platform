locals {
  # Determine the source of the plist content
  defender_onboarding_plist_raw = var.defender_onboarding_plist != "" ? base64decode(var.defender_onboarding_plist) : (var.defender_onboarding_plist_path != "" ? file(var.defender_onboarding_plist_path) : "")

  # Extract OrgId from the onboarding plist
  defender_org_id = local.defender_onboarding_plist_raw != "" ? regex("<key>OrgId</key>\\s*<string>([^<]+)</string>", local.defender_onboarding_plist_raw)[0] : ""

  # Extract OnboardingInfo (the JSON blob) from the onboarding plist
  defender_onboarding_info = local.defender_onboarding_plist_raw != "" ? regex("<key>OnboardingInfo</key>\\s*<string>([^<]+)</string>", local.defender_onboarding_plist_raw)[0] : ""

  # Build the complete configuration profile by injecting values into template
  defender_onboarding_profile = local.defender_onboarding_plist_raw != "" ? templatefile(
    "${path.module}/support_files/onboarding.tpl",
    {
      org_id          = local.defender_org_id
      onboarding_info = local.defender_onboarding_info
    }
  ) : ""
}