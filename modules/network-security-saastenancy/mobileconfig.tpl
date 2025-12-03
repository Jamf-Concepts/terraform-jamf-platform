<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1">
  <dict>
    <key>PayloadUUID</key>
    <string>954D9214-C6A3-467B-90F6-9E705665CAE8</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadOrganization</key>
    <string>Jamf</string>
    <key>PayloadIdentifier</key>
    <string>954D9214-C6A3-467B-90F6-9E705665CAE8</string>
    <key>PayloadDisplayName</key>
    <string>JSCP Proxy Cert</string>
    <key>PayloadDescription</key>
    <string/>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadEnabled</key>
    <true/>
    <key>PayloadRemovalDisallowed</key>
    <true/>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadContent</key>
    <array>
      <dict>
        <key>PayloadDisplayName</key>
        <string>Root Certificate</string>
        <key>PayloadUUID</key>
        <string>F866D848-8C52-42A9-92CF-3E639ABBAFCD</string>
        <key>PayloadType</key>
        <string>com.apple.security.root</string>
        <key>PayloadCertificateFileName</key>
        <string>root.cer</string>
        <key>PayloadContent</key>
        <data>${root_cert_body}</data>
      </dict>
      <dict>
        <key>PayloadDisplayName</key>
        <string>Leaf Certificate</string>
        <key>PayloadUUID</key>
        <string>605B9E0B-E31A-4132-8148-8FF396D9E483</string>
        <key>PayloadType</key>
        <string>com.apple.security.pkcs1</string>
        <key>PayloadCertificateFileName</key>
        <string>leaf.cer</string>
        <key>PayloadContent</key>
        <data>${leaf_cert_body}</data>
      </dict>
    </array>
  </dict>
</plist>