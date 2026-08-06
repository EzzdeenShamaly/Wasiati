# Two usable stages:
#   docker build -t wasiati-api .                    → the runtime image (this file's end)
#   docker build --target builder -t wasiati-api:tools .
# The :tools tag is for ONE-OFF ECS TASKS — migrations and seeds. It carries src/,
# ts-node and the full toolchain, which the runtime image deliberately does not:
# seed-pricing.ts imports from src/ (../src/commerce/plan-rules) and cannot run from
# the runtime image at all. Never point the ALB at :tools.
FROM node:20-alpine AS builder
WORKDIR /app
# For `prisma generate` below, not for the build itself. Prisma probes the system OpenSSL
# to resolve the "native" binaryTarget; bare node:20-alpine ships no openssl binary, so
# that probe fails and "native" resolves to the openssl-1.1.x engine — a second, unusable
# copy alongside the one schema.prisma names explicitly. With openssl here, "native" and
# linux-musl-openssl-3.0.x collapse to the same engine and the image carries one, not two.
RUN apk add --no-cache openssl && rm -rf /var/cache/apk/*
COPY package.json ./
# Puppeteer must not download its own Chromium — the runtime image installs the
# Alpine chromium package instead (musl-incompatible bundled build otherwise).
ENV PUPPETEER_SKIP_DOWNLOAD=true
# --ignore-scripts: never execute a dependency's install lifecycle script at build time,
# so a compromised transitive package can't run code in the image build.
# NOTE (follow-up): this backend-scoped build context has no committed lockfile, so
# versions aren't pinned. Reproducible builds need the workspace lockfile in context
# (build from repo root with pnpm --frozen-lockfile, or commit a backend lockfile).
RUN npm install --ignore-scripts
# --ignore-scripts above also skipped @prisma/engines' postinstall — the step that
# downloads the SCHEMA engine `prisma migrate deploy` runs on. `prisma generate`
# fetches only QUERY engines, so without this the deployed image cannot migrate:
# the CLI would try to download the engine at migration time, as the non-root
# `node` user, into root-owned node_modules — EACCES, in the middle of a deploy.
# `npm rebuild` executes the install scripts of ONE first-party Prisma package,
# keeping the ignore-scripts supply-chain posture for every other dependency.
RUN npm rebuild @prisma/engines
COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production

# Chromium + font stack for the will PDF renderer. The will is bilingual, so the
# Arabic-capable font matters; we also embed Noto Naskh Arabic in the document
# itself (see assets/fonts) which is what actually guarantees correct shaping.
# openssl is for Prisma, not Chromium: the query engine picks which .so.node to load by
# detecting the OpenSSL version AT RUNTIME. Alpine ships libssl.so.3 but no openssl CLI, so
# that detection silently fails, falls back to "openssl-1.1.x", and loads the engine linked
# against libssl.so.1.1 — which is absent — killing the app in PrismaService.onModuleInit
# after Nest has fully booted. schema.prisma's binaryTargets makes the right engine exist;
# this makes Prisma actually choose it. Both halves are required.
RUN apk add --no-cache \
      chromium \
      nss \
      freetype \
      harfbuzz \
      ca-certificates \
      ttf-freefont \
      openssl \
    && rm -rf /var/cache/apk/*

ENV PUPPETEER_SKIP_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
# The embedded PDF font — without this the Arabic falls back to host fonts.
COPY --from=builder /app/assets ./assets
COPY package.json ./
# Drop root: the process renders user-influenced will HTML via Chromium, so a renderer
# or Node compromise should not be root-in-container. `node` is a built-in non-root user
# on the official image and has read/execute on the copied app + /usr/bin/chromium.
USER node
EXPOSE 4000
CMD ["node", "dist/main.js"]
