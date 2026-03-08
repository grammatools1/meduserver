# Multi-stage build for optimal security and size
FROM node:20-alpine AS builder
RUN corepack enable
WORKDIR /server
# Copy package files and install all dependencies (needed for build)
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .yarnrc.yml* ./
RUN \
  if [ -f yarn.lock ]; then yarn set version 3.2.1; fi
RUN \
  if [ -f yarn.lock ]; then yarn install; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then pnpm install; \
  else echo "No lockfile found." && exit 1; fi
# Copy source code
COPY . .
# Build the Medusa application for production
RUN \
  if [ -f yarn.lock ]; then yarn medusa build; \
  elif [ -f package-lock.json ]; then npx medusa build; \
  elif [ -f pnpm-lock.yaml ]; then pnpm medusa build; \
  fi
# Production stage
FROM node:20-alpine AS production
RUN corepack enable
# Security hardening
RUN addgroup -g 1001 -S nodejs && \
    adduser -S medusa -u 1001 && \
    apk add --no-cache curl && \
    rm -rf /var/cache/apk/* /tmp/*
# IMPORTANT: Use /server as WORKDIR, not /app, to avoid conflicts
# with Medusa Admin customizations
WORKDIR /server
# Copy Yarn config and releases from builder (in case they were generated)
COPY --from=builder --chown=medusa:nodejs /server/.yarnrc.yml ./
COPY --from=builder --chown=medusa:nodejs /server/.yarn .yarn
# Copy only the production build output from builder
# Medusa build outputs to .medusa/server
COPY --from=builder --chown=medusa:nodejs /server/.medusa/server ./.medusa/server
COPY --from=builder --chown=medusa:nodejs /server/package.json ./package.json
# Create necessary directories with proper permissions
RUN mkdir -p /server/uploads /server/logs /tmp /server/.yarn && \
    chown -R medusa:nodejs /server/uploads /server/logs /tmp /server/.yarn
# Switch to non-root user
USER medusa
# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1
EXPOSE 9000
# Install production deps, run migrations, then start
CMD ["sh", "-c", "cd .medusa/server && yarn install && yarn predeploy && yarn run start"]
