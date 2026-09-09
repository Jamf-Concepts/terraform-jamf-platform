output "uem_connect_id" {
  description = "The UEM Connect connector's id, exposed only so the JSC activation-profile module can depend on this connector existing before deploying. Either the connector this module just created, or the pre-existing one the caller found and passed in via uem_connect_already_exists_id."
  value       = var.uem_connect_already_exists_id != "" ? var.uem_connect_already_exists_id : jamfplatform_security_cloud_uem_connect.jamf_pro[0].id
}
