#!/bin/bash

# Update and install packages
yum update -y
yum install -y nginx

# Write the SSL certificate
cat <<EOF > /etc/nginx/server.crt
${cert_pem}
EOF

# Write the private key
cat <<EOF > /etc/nginx/server.key
${private_key}
EOF

# Write the server.ext file
cat <<EOF > /etc/nginx/server.ext
${server_ext}
EOF

# Write Nginx configuration
cat <<EOF > /etc/nginx/conf.d/default.conf
${nginx_config}
EOF


systemctl start nginx
systemctl enable nginx