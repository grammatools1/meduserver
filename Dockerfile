# Stage 1 — Builder
# -----------------------------
FROM node:20-alpine AS builder

WORKDIR /server

RUN corepack enable

# Copy dependency manifests
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

# Install dependencies
RUN \
  if [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; \
  else echo "No lockfile found." && exit 1; fi

# Copy project files
COPY . .

# Build project using package.json script
RUN npm run build


# -----------------------------
# Stage 2 — Production
# -----------------------------
FROM node:20-alpine

WORKDIR /server

RUN corepack enable

# Security hardening
RUN addgroup -S nodejs -g 1001 && \
    adduser -S medusa -u 1001 -G nodejs && \
    apk add --no-cache curl

# Copy built app
COPY --from=builder --chown=medusa:nodejs /server /server

USER medusa

ENV NODE_ENV=production

EXPOSE 9000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

# Start Medusa
CMD ["npm","start"]
