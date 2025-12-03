variable "jamfpro_instance_fqdn" {
  description = "Jamf Pro Instance name."
  type        = string
}

variable "jamfpro_auth_method" {
  description = "Jamf Pro Auth Method."
  type        = string
  default     = "oauth2" #basic or oauth2
}

variable "jamfpro_client_id" {
  description = "Jamf Pro Client ID for authentication."
  type        = string
}

variable "jamfpro_client_secret" {
  description = "Jamf Pro Client Secret for authentication."
  type        = string
  sensitive   = true
}

variable "app_installer_name" {
  type = string
}

variable "enabled" {
  description = "If the App Installer is enabled"
  type        = bool
  default     = false
}

variable "deployment_type" {
  description = "The type of deployment for App Installer (allowed values: INSTALL_AUTOMATICALLY or SELF_SERVICE)"
  type        = string
  default     = "INSTALL_AUTOMATICALLY"

  validation {
    condition     = var.deployment_type == "INSTALL_AUTOMATICALLY" || var.deployment_type == "SELF_SERVICE"
    error_message = "Allowed values for deployment_type are 'INSTALL_AUTOMATICALLY' or 'SELF_SERVICE'."
  }
}

variable "update_behavior" {
  description = "The update behavior for App Installer (allowed values: AUTOMATIC or MANUAL)"
  type        = string
  default     = "AUTOMATIC"

  validation {
    condition     = var.update_behavior == "AUTOMATIC" || var.update_behavior == "MANUAL"
    error_message = "Allowed values for update_behavior are 'AUTOMATIC' or 'MANUAL'."
  }
}

variable "category_id" {
  description = "The category ID for the app installer"
  type        = string
  default     = "-1"
}

variable "site_id" {
  description = "The site ID for the app installer"
  type        = string
  default     = "-1"
}

variable "smart_group_id" {
  description = "The smart group ID for the app installer"
  type        = string
  default     = "1"
}

variable "install_predefined_config_profiles" {
  description = "Whether to install predefined configuration profiles"
  type        = bool
  default     = true
}

variable "trigger_admin_notifications" {
  description = "Log event notifications for this app. Opt in to receiving notifications for certain events including app updates and installation failures."
  type        = bool
  default     = true
}

variable "notification_message" {
  description = "The notification message for app updates"
  type        = string
  default     = "A new update is available"
}

variable "notification_interval" {
  description = "Interval between update notifications (in hours)"
  type        = number
  default     = 1
}

variable "deadline_message" {
  description = "Message displayed when the update deadline is approaching"
  type        = string
  default     = "Update deadline approaching"
}

variable "deadline" {
  description = "The Update deadline in hours."
  type        = number
  default     = 1
}

variable "quit_delay" {
  description = "Force quit grace period in minutes."
  type        = number
  default     = 1
}

variable "complete_message" {
  description = "Message displayed when the update is completed successfully"
  type        = string
  default     = "Update completed successfully"
}

variable "relaunch" {
  description = "Whether the app should relaunch after an update"
  type        = bool
  default     = true
}

variable "suppress" {
  description = "Whether to suppress update notifications"
  type        = bool
  default     = false
}

variable "include_in_featured_category" {
  description = "Whether to include the app in the Featured category in Self Service"
  type        = bool
  default     = true
}

variable "include_in_compliance_category" {
  description = "Whether to include the app in the Compliance category in Self Service"
  type        = bool
  default     = false
}

variable "force_view_description" {
  description = "Whether the app description should be forced in Self Service"
  type        = bool
  default     = false
}

variable "self_service_description" {
  description = "Description for the app in Self Service"
  type        = string
  default     = "This is an app provided from your Self Service Provider."
}

variable "random_string" {
  type    = string
  default = ""
}


