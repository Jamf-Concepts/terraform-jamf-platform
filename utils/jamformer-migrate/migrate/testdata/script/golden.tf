resource "jamfplatform_pro_script" "deploy_app" {
  name            = "Deploy App"
  os_requirements = "13"
  priority        = "BEFORE"
  info            = "Deploys the app"
  notes           = "Run as root"
  script          = "#!/bin/bash\necho hello"
  parameter_4     = "target_id"
  parameter_5     = "group"
  parameter_6     = "membership"
  parameter_7     = "add"
}

resource "jamfplatform_pro_script" "reboot_script" {
  name     = "Reboot at Night"
  priority = "AT_REBOOT"
  script   = "#!/bin/bash\nreboot"
}
