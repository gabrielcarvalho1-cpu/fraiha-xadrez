FROM debian:bookworm-slim
ARG GODOT_VERSION=4.5.1
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libasound2 libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libgl1 libfontconfig1 && rm -rf /var/lib/apt/lists/*
RUN curl -fL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -o /tmp/godot.zip && unzip /tmp/godot.zip -d /tmp/godot && mv /tmp/godot/Godot* /usr/local/bin/godot && chmod +x /usr/local/bin/godot && rm -rf /tmp/godot /tmp/godot.zip
RUN useradd --create-home godot
WORKDIR /app
COPY --chown=godot:godot . /app
USER godot
RUN godot --headless --editor --path /app --import --quit
ENV PORT=10000
EXPOSE 10000
CMD ["godot", "--headless", "--path", "/app", "--script", "res://online_v020/server.gd"]
