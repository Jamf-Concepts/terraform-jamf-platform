resource "jamfplatform_pro_network_segment" "hq" {
  name                 = "Example Network Segment"
  starting_address     = "192.168.1.1"
  ending_address       = "192.168.1.254"
  building             = "Main Building"
  department           = "IT Department"
  override_buildings   = true
  override_departments = false
}
