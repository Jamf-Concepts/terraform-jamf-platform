output "uem_connect_id" {
  description = "The UEM Connect connector's id, exposed only so the JSC activation-profile module can depend on this connector existing before deploying."
  value       = jamfplatform_security_cloud_uem_connect.jamf_pro.id
}
