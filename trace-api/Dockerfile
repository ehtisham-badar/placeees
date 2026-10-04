# Trace API — production image (Railway, Fly, anything that runs containers).
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
USER node
EXPOSE 3000
# Migrations are idempotent and transactional, so running them on every boot is safe.
CMD ["sh", "-c", "node dist/db/migrate.js && node dist/server.js"]
