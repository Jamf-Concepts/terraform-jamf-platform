**This module requires both Jamf Pro and Jamf Security Cloud credentials.**

Running this will complete the following steps:


- Create an Okta Identity Provider entry in Jamf Security Cloud
- Create an Activation Profile in Jamf Security Cloud with Network Access, Network Security, and Content Controls enabled with the previously created Okta IDP assigned
- Collect the Activation Profile plist and create a new Configuration Profile in Jamf Pro
- Create a category named "Jamf Security Cloud - Activation Profiles" in Jamf Pro and assign the newly created Configuration Profile to that category
- Create custom Block Page entries in Jamf Security Cloud. In their default state, they will have blocker text like "Your Text Here." You can customize this output by editing the module first in your own Branch and changing the **title** and **description** fields.



