resource "jamfpro_script" "deploy_app" {
  name            = "Deploy App"
  script_contents = "#!/bin/bash\necho hello"
  category_id     = 5
  os_requirements = "13"
  priority        = "Before"
  info            = "Deploys the app"
  notes           = "Run as root"
  parameter4      = "target_id"
  parameter5      = "group"
  parameter6      = "membership"
  parameter7      = "add"
}

resource "jamfpro_script" "reboot_script" {
  name            = "Reboot at Night"
  script_contents = "#!/bin/bash\nreboot"
  priority        = "At Reboot"
}
