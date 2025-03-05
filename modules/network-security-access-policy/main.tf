## Call Terraform provider
terraform {
  required_providers {
    jsc = {
      source  = "danjamf/jsctfprovider"
      version = ">= 0.0.15"
    }
  }
}

data "jsc_pag_vpnroutes" "vpn_route_nearest" {
  name = var.vpn_route
}

data "jsc_pag_apptemplates" "access_policy" {
  name = var.access_policy_name
}

resource "jsc_pag_ztnaapp" "ap_atlassian" {
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
  apptemplateid                                    = data.jsc_pag_apptemplates.ap_data_atlassian.id
}
