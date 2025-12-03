## Call Terraform provider
terraform {
  required_providers {
    jsc = {
      source                = "danjamf/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
  }
}

data "jsc_pag_vpnroutes" "vpn_route_nearest" {
  name = var.vpn_route
}

data "jsc_pag_apptemplates" "app_template" {
  name = var.access_policy_name
}

resource "jsc_pag_ztnaapp" "access_policy" {
  name                                             = var.access_policy_name
  routingtype                                      = var.routing_type
  routingid                                        = data.jsc_pag_vpnroutes.vpn_route_nearest.id
  routingdnstype                                   = var.routing_dns_type
  categoryname                                     = var.category_name
  securityriskcontrolenabled                       = var.risk_control_enabled
  securityriskcontrolthreshold                     = var.risk_threshold
  securityriskcontrolnotifications                 = var.risk_threshold_notifications
  securitydohintegrationblocking                   = var.security_doh_block
  securitydohintegrationnotifications              = var.security_doh_block_notifications
  securitydevicemanagementbasedaccessenabled       = var.security_management_block
  securitydevicemanagementbasedaccessnotifications = var.security_management_block_notification
  assignmentallusers                               = var.all_users
  apptemplateid                                    = data.jsc_pag_apptemplates.app_template.id
}
