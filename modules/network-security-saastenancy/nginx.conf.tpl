server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_certificate     /etc/nginx/server.crt;
    ssl_certificate_key /etc/nginx/server.key;

    location / {
        client_max_body_size 0;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_buffers 16 32k;
        proxy_buffer_size 64k;
        proxy_busy_buffers_size 64k;
        resolver 1.1.1.1 ipv6=off;

        ${proxy_set_headers}
        ${proxy_pass}
    }
}