# Multi-stage build for optimal security and size
FROM node:20-alpine AS builder
RUN corepack enable
WORKDIR /server
# Copy package files and yarn config
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .yarnrc.yml* ./
# Copy .yarn directory only if it exists (use a wildcard to avoid failure)
COPY .yarn* ./.yarn/
RUN \
  if [ -f yarn.lock ]; then yarn install; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then pnpm install; \
  else echo "No lockfile found." && exit 1; fi
# Copy source code
COPY . .
# Build the Medusa application for production using the CLI
RUN npx @medusajs/medusa-cli@preview build
# Verify the build output exists (optional for debugging)
RUN ls -la /server/.medusa/server
# Production stage
FROM node:20-alpine AS production
RUN corepack enable
# Security hardening
RUN addgroup -g 1001 -S nodejs && \
    adduser -S medusa -u 1001 && \
    apk add --no-cache curl && \
    rm -rf /var/cache/apk/* /tmp/*
WORKDIR /server
# Copy Yarn config if exists
COPY --from=builder --chown=medusa:nodejs /server/.yarnrc.yml* ./
COPY --from=builder --chown=medusa:nodejs /server/.yarn* .yarn/
COPY --from=builder --chown=medusa:nodejs /server/yarn.lock* ./
# Copy the entire .medusa directory, including server and admin if built
COPY --from=builder --chown=medusa:nodejs /server/.medusa /server/.medusa
COPY --from=builder --chown=medusa:nodejs /server/package.json ./package.json
# Create necessary directories with proper permissions
RUN mkdir -p /server/uploads /server/logs /tmp /server/.yarn && \
    chown -R medusa:nodejs /server/uploads /server/logs /tmp /server/.yarn
# Switch to non-root user
USER medusa
# Set production environment
ENV NODE_ENV=production
# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1
EXPOSE 9000
# Install production deps in the built directory, run migrations, then start
CMD ["sh", "-c", "cd .medusa/server && yarn install --frozen-lockfile --production && npx @medusajs/medusa-cli@preview migrations run && node src/server.js"]
