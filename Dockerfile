# Multi-stage build for optimal security and size
FROM node:20-alpine AS builder

WORKDIR /server

# Install necessary build dependencies
RUN apk add --no-cache python3 make g++ git

# Copy Yarn configuration files first (for better caching)
COPY .yarnrc.yml ./
COPY .yarn ./.yarn

# Copy package files
COPY package.json yarn.lock* ./

# Install dependencies using Yarn 3+
RUN if [ -f yarn.lock ]; then \
      yarn set version stable && \
      yarn install --immutable; \
    else \
      echo "No yarn.lock found" && exit 1; \
    fi

# Copy source code (excluding node_modules and .yarn/cache)
COPY . .

# Build the Medusa application
RUN if [ -d ".medusa" ]; then \
      echo "Medusa directory exists, building..." && \
      yarn build; \
    else \
      echo "Running medusa build..." && \
      yarn medusa build; \
    fi

# Production stage
FROM node:20-alpine AS production

# Security hardening
RUN addgroup -g 1001 -S nodejs && \
    adduser -S medusa -u 1001 && \
    apk add --no-cache curl dumb-init && \
    rm -rf /var/cache/apk/* /tmp/*

WORKDIR /server

# Copy necessary files from builder
COPY --from=builder --chown=medusa:nodejs /server/package.json /server/yarn.lock ./
COPY --from=builder --chown=medusa:nodejs /server/.yarnrc.yml ./
COPY --from=builder --chown=medusa:nodejs /server/.yarn ./.yarn

# Copy build output (Medusa build outputs to .medusa/server or dist)
COPY --from=builder --chown=medusa:nodejs /server/.medusa ./.medusa 2>/dev/null || true
COPY --from=builder --chown=medusa:nodejs /server/dist ./dist 2>/dev/null || true
COPY --from=builder --chown=medusa:nodejs /server/build ./build 2>/dev/null || true

# Create necessary directories
RUN mkdir -p /server/uploads /server/logs /server/static /tmp && \
    chown -R medusa:nodejs /server/uploads /server/logs /server/static /tmp

# Install production dependencies only
RUN yarn workspaces focus --production && \
    yarn cache clean

# Switch to non-root user
USER medusa

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

EXPOSE 9000 5173

# Use dumb-init for proper signal handling
ENTRYPOINT ["dumb-init", "--"]

# Start the server
CMD ["sh", "-c", "yarn medusa migrations run && yarn medusa start"]
