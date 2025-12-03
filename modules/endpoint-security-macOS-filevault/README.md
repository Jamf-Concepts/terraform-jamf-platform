**This module requires Jamf Pro credentials.**

Running this will complete the following:

- Create a "Disk Encryption" category in Jamf Pro
- Upload a script that reissues Recovery Keys for FileVault
- Create a Smart Group looking for invalid Recovery Keys
- Create a Smart Group looking for valid FileVault states in the environment
- Create a Policy scope to computers with Invalid Recovery Keys and utilizing the script uploaded to reissue a new Recovery Key
- Create a Configuration Profile that enforces FileVault 2

**Note: The Configuration Profile is not scoped by default since Jamf Pro will not generate the certificate needed until you have clicked save in the Jamf Pro tenant. To finalize this setup, please navigate to the Config Profile named "Enable FileVault 2", scope that appropriately and click "Save"**