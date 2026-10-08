# Base épinglée sur une version précise : build reproductible et auditable
FROM node:22.11-alpine

WORKDIR /app

# Dépendances d'abord (cache), fichiers donnés à l'utilisateur non-root "node" (uid 1000)
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Code ensuite
COPY --chown=node:node server.js db.js ./

# Port >= 1024 : un utilisateur non-root ne peut pas écouter en dessous
EXPOSE 3000

# Sonde de liveness légère, sans dépendance externe (fetch est natif dans Node 22)
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Bascule en non-root juste avant le CMD, une fois les chown faits
USER node

CMD ["node", "server.js"]
