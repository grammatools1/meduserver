# -----------------------------
# Stage 1 — Builder
# -----------------------------
FROM node:20-alpine AS builder

WORKDIR /server

RUN corepack enable

# Install system deps needed for builds
RUN apk add --no-cache libc6-compat

# Copy dependency manifests first (better caching)
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
RUN npm run build


# -----------------------------
# Stage 2 — Production
# -----------------------------
FROM node:20-alpine

WORKDIR /server

RUN corepack enable

# Install runtime dependencies only
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

RUN \
  if [ -f yarn.lock ]; then yarn install --production --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci --omit=dev; \
  elif [ -f pnpm-lock.yaml ]; then pnpm install --prod --frozen-lockfile; \
  else echo "No lockfile found." && exit 1; fi

# Security hardening
RUN addgroup -S nodejs -g 1001 && \
    adduser -S medusa -u 1001 -G nodejs && \
    apk add --no-cache curl

# Copy built application
COPY --from=builder --chown=medusa:nodejs /server/node_modules ./node_modules
COPY --from=builder --chown=medusa:nodejs /server/package.json ./package.json
COPY --from=builder --chown=medusa:nodejs /server/medusa-config.js ./medusa-config.js
COPY --from=builder --chown=medusa:nodejs /server/build.mjs ./build.mjs
COPY --from=builder --chown=medusa:nodejs /server/index.js ./index.js
COPY --from=builder --chown=medusa:nodejs /server/src ./src
COPY --from=builder --chown=medusa:nodejs /server/data ./data

# Ensure correct permissions
RUN chown -R medusa:nodejs /server

USER medusa

ENV NODE_ENV=production

EXPOSE 9000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

# Start Medusa (NO BUILD AT RUNTIME)
CMD ["npx","medusa","start"]
