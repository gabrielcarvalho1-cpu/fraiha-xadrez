# FRAIHA · backend MODERNO (Node, online_v021): contas, Casual, Ranked, Amigos, DM, convites, XEQUE/Marcha
# online (party_*/xeque_*/marcha_*), voz, pagamentos e Admin. É o MESMO servidor do staging (npm start).
# Antes este arquivo subia o servidor LEGADO em Godot (online_v020/server.gd, só salas create/join): qualquer
# serviço Render em runtime Docker apontado para esta branch rodaria o protocolo antigo.
# Variáveis (Render > Environment, NUNCA no Git): ver docs/backend/BACKEND_PRODUCAO.md.
FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY online_v021 ./online_v021
COPY admin ./admin
COPY bot/bot_ladder.json ./bot/bot_ladder.json
ENV PORT=10000
EXPOSE 10000
USER node
CMD ["node", "online_v021/server.js"]
