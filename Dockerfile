# -----------------------------
# Stage 1 — Build
# -----------------------------
FROM node:20-alpine AS builder

RUN corepack enable

WORKDIR /server

# Copy dependency manifests
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

# Install dependencies
RUN \
  if [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; \
  else echo "No lockfile found." && exit 1; fi

# Copy source
COPY . .

# Build Medusa
RUN npx medusa build

# Debug build output
RUN ls -la .medusa && ls -la .medusa/dist


# -----------------------------
# Stage 2 — Production
# -----------------------------
FROM node:20-alpine

RUN corepack enable

# Security
RUN addgroup -S nodejs -g 1001 && \
    adduser -S medusa -u 1001 -G nodejs && \
    apk add --no-cache curl

WORKDIR /server

# Copy runtime files
COPY --from=builder --chown=medusa:nodejs /server/package.json ./
COPY --from=builder --chown=medusa:nodejs /server/yarn.lock* ./
COPY --from=builder --chown=medusa:nodejs /server/package-lock.json* ./
COPY --from=builder --chown=medusa:nodejs /server/pnpm-lock.yaml* ./

# Copy built app
COPY --from=builder --chown=medusa:nodejs /server/.medusa ./.medusa

# Create runtime dirs
RUN mkdir -p /server/uploads /server/logs /tmp && \
    chown -R medusa:nodejs /server

USER medusa

ENV NODE_ENV=production

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

EXPOSE 9000

# Install prod deps + run migrations + start server
CMD ["sh", "-c", "cd .medusa && yarn install --production || npm install --omit=dev && npx medusa migrations run && node dist/main.js"]
