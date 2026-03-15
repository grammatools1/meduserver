# -----------------------------
# Stage 1 — Builder
# -----------------------------
FROM node:20-alpine AS builder

WORKDIR /server

RUN corepack enable

# System deps
RUN apk add --no-cache libc6-compat

# Copy dependency manifests
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

# Install dependencies
RUN \
  if [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; \
  else echo "No lockfile found." && exit 1; fi

# Copy source code
COPY . .

# Build Medusa
RUN npm run build


# -----------------------------
# Stage 2 — Production
# -----------------------------
FROM node:20-alpine

WORKDIR /server

RUN corepack enable

# Install curl for healthcheck
RUN apk add --no-cache curl

# Create non-root user
RUN addgroup -S nodejs -g 1001 && \
    adduser -S medusa -u 1001 -G nodejs

# Copy built project from builder
COPY --from=builder /server /server

# Fix permissions
RUN chown -R medusa:nodejs /server

USER medusa

ENV NODE_ENV=production

EXPOSE 9000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

# Start Medusa
CMD ["npx","medusa","start"]
