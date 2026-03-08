# -----------------------------
# Stage 1 — Build
# -----------------------------
FROM node:20-alpine AS builder

RUN corepack enable

WORKDIR /server

# Copy package manager files
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .yarnrc.yml* ./

# Copy yarn directory if present
COPY .yarn/ ./.yarn/

# Install dependencies
RUN \
  if [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; \
  else echo "No lockfile found." && exit 1; fi

# Copy source code
COPY . .

# Build Medusa project
RUN npx medusa build

# Verify build output
RUN ls -la .medusa && ls -la .medusa/dist


# -----------------------------
# Stage 2 — Production Image
# -----------------------------
FROM node:20-alpine AS production

RUN corepack enable

# Security hardening
RUN addgroup -S nodejs -g 1001 && \
    adduser -S medusa -u 1001 -G nodejs && \
    apk add --no-cache curl && \
    rm -rf /var/cache/apk/*

WORKDIR /server

# Copy only required runtime files
COPY --from=builder --chown=medusa:nodejs /server/package.json ./package.json
COPY --from=builder --chown=medusa:nodejs /server/yarn.lock* ./
COPY --from=builder --chown=medusa:nodejs /server/.yarnrc.yml* ./
COPY --from=builder --chown=medusa:nodejs /server/.yarn/ ./.yarn/

# Copy built Medusa app
COPY --from=builder --chown=medusa:nodejs /server/.medusa /server/.medusa

# Runtime directories
RUN mkdir -p /server/uploads /server/logs /tmp && \
    chown -R medusa:nodejs /server/uploads /server/logs /tmp

# Switch to non-root
USER medusa

ENV NODE_ENV=production

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

EXPOSE 9000

# Install runtime dependencies, run migrations, start server
CMD ["sh", "-c", "cd .medusa && yarn install --production --frozen-lockfile && npx medusa migrations run && node dist/main.js"]
