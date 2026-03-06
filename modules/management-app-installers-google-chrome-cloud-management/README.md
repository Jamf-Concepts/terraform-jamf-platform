This module configures Google Chrome for Cloud Management. A Chrome Enterprise Core enrollment token is required: <https://support.google.com/chrome/a/answer/9771882?hl=en>

Running this will:

- Create a Category named "Google Chrome Cloud Management"
- Create a Smart Computer Group named "Google Chrome Cloud Management Devices"
- Create an App Installer named "Google Chrome" scoped to the above group
- Create a macOS Configuration Profile named "Google Chrome Cloud Management Settings" containing the enrollment token scoped to the above group
