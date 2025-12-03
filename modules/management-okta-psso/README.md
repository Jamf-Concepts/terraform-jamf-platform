## This module creates the necessary pieces in Jamf Pro to enable PSSO in your environment. 

# Required Variables:

## Jamf Pro Account Details

```
jamfpro_auth_method   = "" ## oauth2 or basic
jamfpro_instance_fqdn  = ""
jamfpro_client_id     = ""
jamfpro_client_secret = ""
jamfpro_username      = ""
jamfpro_password      = ""
```

You will only need the client authentication items for ```oauth2``` or the username / password for ```basic``` 


## Okta PSSO Module Variables

```
okta_short_url   = ""  # ex: tenant.okta.com
okta_org_name    = ""
okta_scep_url    = ""
okta_psso_client = ""
```


## Implementation Notes

Due to concerns with sending SCEP challenge domains, SCEP Usernames, and SCEP Passwords through API, Jamf Pro does not allow this to happen. You will need to add this manuallly to the ```Okta Device Access SCEP``` configuration profile prior to scoping. 

To prevent deployment of these settings before everything is completed, the Smart Group that we create as part of this module includes a placeholder serial number. If you remove the placeholder serial number from the ```Okta PSSO Target Group``` Smart Group, the configuration profiles will automatically scope. Do **not** do this prior to adding the SCEP details noted above. 


