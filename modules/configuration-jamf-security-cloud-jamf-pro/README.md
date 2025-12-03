**This module requires both Jamf Pro and Jamf Security Cloud credentials.**

Running this will complete the following steps:

- Create the API Role in Jamf Pro that allows for Jamf Security Cloud's UEM Connect feature to sync devices between the two services
- Create the API Role in Jamf Pro that allows Jamf Security Cloud to signal Jamf Pro when risk levels are heightened or a specific detection is triggered by a device
- Create the API Role in Jamf Pro that allows Jamf Security Cloud to upload its Activation Profiles directly to Jamf Pro with a chosen Smart Group as the scope
- Create the API Client in Jamf Pro with the three previous API Roles attached
- Establish the UEM Connect feature's synchronization with Jamf Pro