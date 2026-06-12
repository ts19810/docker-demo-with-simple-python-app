# syntax=docker/dockerfile:1
#
# moole-sast-ts-facts-extractor — container image.
#
# Node counterpart to moole-sast-jk-facts-extractor's Dockerfile. The Java image
# copies a pre-built jar; here the build is self-contained: stage 1 compiles
# TypeScript -> dist, stage 2 resolves production-only node_modules, and the
# final slim runtime carries just dist + prod deps + the properties file.
#
# Why a forked-worker design matters for the image: the HTTP/BullMQ parent
# process forks a FRESH child (dist/worker/WorkerHarness.js) per scan. tini runs
# as PID 1 so SIGTERM reaches Node AND zombie workers are reaped. No build tools
# or tsx loader are needed at runtime — every production dependency is pure JS
# and the worker script is compiled .js (so no ESM loader is injected).
#
# Build:  docker build -t moole-sast-node-fact-extractor-svc:local .
# Run:    docker run --rm -p 8080:8080 \
#           -e REDIS_HOST=host.docker.internal -e KAFKA_BROKERS=host.docker.internal:9092 \
#           moole-sast-node-fact-extractor-svc:local

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 — build: install ALL deps (incl. dev) and compile TS to dist/
# ─────────────────────────────────────────────────────────────────────────────
FROM node:22-bookworm AS builder
WORKDIR /app

# Install deps first (layer caches unless the lockfile changes).
COPY package.json package-lock.json ./
RUN npm ci

# Compile. tsconfig.build.json has rootDir=src so output lands flat under dist/
# (dist/index.js, dist/worker/WorkerHarness.js, ...).
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 — prod deps: production-only node_modules for the runtime layer
# ─────────────────────────────────────────────────────────────────────────────
FROM node:22-bookworm AS prod-deps
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3 — runtime: slim image with just what the service needs
# ─────────────────────────────────────────────────────────────────────────────
FROM node:22-bookworm-slim AS runtime

# tini = PID 1: forwards SIGTERM/SIGINT to Node and reaps forked scan workers.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    PORT=8080 \
    HOST=0.0.0.0

WORKDIR /app

COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=builder   /app/dist ./dist
COPY package.json ./


RUN chown -R node:node /app
USER node

EXPOSE 8080

# --enable-source-maps maps stack traces back to the .ts sources (dist ships maps).
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "--enable-source-maps", "dist/index.js"]
