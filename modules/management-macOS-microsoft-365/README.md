**This module requires Jamf Pro credentials.**

Running this will:

- Create a Microsoft 365 category
- Create a Smart Group in Jamf Pro looking for Microsoft Word to be installed
- Create a Smart Group in Jamf Pro looking for Microsoft Excel to be installed
- Create a Smart Group in Jamf Pro looking for Microsoft OneDrive to be installed
- Create a Smart Group in Jamf Pro looking for Microsoft Outlook to be installed
- Create a Smart Group in Jamf Pro looking for Microsoft Powerpoint to be installed
- Create a Smart Group in Jamf Pro looking for Microsoft Edge to be installed
- Create a Smart Group in Jamf Pro looking for Microsoft Teams to be installed
- Create App Installers for each Microsoft 365 app outlined above scoped to the Smart Groups created for each app

**We scope it this way to use App Installers as an update mechanism rather than initial deployment**