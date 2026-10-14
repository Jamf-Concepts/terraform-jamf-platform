output "deployment_status" {
  description = "SentinelOne module deployment status"
  value       = local.has_pkg_source ? "Complete" : "Partial - no package source provided, package upload and deployment policy skipped"
}
