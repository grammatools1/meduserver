# -----------------------------
# Stage 1 — Builder
# -----------------------------
FROM node:20-alpine AS builder

WORKDIR /server

RUN corepack enable
RUN apk add --no-cache libc6-compat

COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

RUN \
  if [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; \
  else echo "No lockfile found." && exit 1; fi

COPY . .

RUN yarn medusa build


# -----------------------------
# Stage 2 — Production
# -----------------------------
FROM node:20-alpine

WORKDIR /server

RUN corepack enable
RUN apk add --no-cache curl

RUN addgroup -S nodejs -g 1001 && \
    adduser -S medusa -u 1001 -G nodejs

COPY --from=builder /server/.medusa/server /server

RUN yarn install --production

RUN chown -R medusa:nodejs /server

USER medusa

ENV NODE_ENV=production

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

CMD ["sh", "-c", "yarn predeploy && yarn run start"]
