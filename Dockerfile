FROM debian:bookworm-slim
ARG GODOT_VERSION=4.5.1
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip nginx libasound2 libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libgl1 libfontconfig1 && rm -rf /var/lib/apt/lists/*
RUN curl -fL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -o /tmp/godot.zip && unzip /tmp/godot.zip -d /tmp/godot && mv /tmp/godot/Godot* /usr/local/bin/godot && chmod +x /usr/local/bin/godot && rm -rf /tmp/godot /tmp/godot.zip
RUN useradd --create-home godot
WORKDIR /app
COPY . /app
RUN godot --headless --editor --path /app --import --quit
RUN printf '%s\n' \
'events {}' \
'http {' \
'  access_log /dev/stdout;' \
'  error_log /dev/stderr warn;' \
'  server {' \
'    listen 10000;' \
'    location = /health { add_header Content-Type text/plain; return 200 "FRAIHA online\\n"; }' \
'    location / {' \
'      proxy_pass http://127.0.0.1:10001;' \
'      proxy_http_version 1.1;' \
'      proxy_set_header Upgrade $http_upgrade;' \
'      proxy_set_header Connection "upgrade";' \
'      proxy_set_header Host $host;' \
'      proxy_read_timeout 3600s;' \
'      proxy_send_timeout 3600s;' \
'    }' \
'  }' \
'}' > /etc/nginx/nginx.conf
ENV PORT=10000
EXPOSE 10000
CMD ["sh", "-c", "PORT=10001 godot --headless --path /app --script res://online_v020/server.gd & exec nginx -g 'daemon off;'"]
