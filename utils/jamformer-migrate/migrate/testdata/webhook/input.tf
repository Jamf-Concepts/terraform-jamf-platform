resource "jamfpro_webhook" "basic_auth" {
  name                = "ExampleWebhook"
  enabled             = true
  url                 = "https://example.com/webhook"
  content_type        = "application/json"
  event               = "DeviceAddedToDEP"
  connection_timeout  = 5
  read_timeout        = 5
  authentication_type = "BASIC"
  username            = "exampleUser"
  password            = "examplePassword"
}
