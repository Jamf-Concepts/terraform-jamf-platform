resource "jamfpro_ldap_server" "corp" {
  name                = "Corporate LDAP"
  hostname            = "ldap.example.com"
  server_type         = "Active Directory"
  port                = 636
  use_ssl             = true
  authentication_type = "simple"

  account {
    distinguished_username = "CN=ServiceAccount,DC=example,DC=com"
    password               = "your-secure-password"
  }

  open_close_timeout = 15
  search_timeout     = 60
  referral_response  = ""
  use_wildcards      = true

  user_mappings {
    map_object_class_to_any_or_all = "any"
    object_classes                 = "organizationalPerson"
    search_base                    = "DC=example,DC=com"
    search_scope                   = "All Subtrees"
    map_username                   = "sAMAccountName"
    map_realname                   = "displayName"
    map_email_address              = "mail"
    map_user_uuid                  = "objectGUID"
  }

  user_group_mappings {
    map_object_class_to_any_or_all = "any"
    object_classes                 = "group, top"
    search_base                    = "DC=example,DC=com"
    search_scope                   = "All Subtrees"
    map_group_name                 = "name"
    map_group_uuid                 = "objectGUID"
  }

  user_group_membership_mappings {
    user_group_membership_stored_in    = "user object"
    map_group_membership_to_user_field = "memberOf"
    use_dn                             = true
    recursive_lookups                  = true
    map_object_class_to_any_or_all     = "all"
    object_classes                     = "group"
    search_scope                       = "All Subtrees"
  }
}
