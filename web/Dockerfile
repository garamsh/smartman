# syntax=docker/dockerfile:1.27.1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

# The web app's image. Its context is the repository root, `docker build -f web/Dockerfile .`,
# because the fonts it bundles are the app's, in app/assets/fonts, and the engine it serves is
# engine-wasm/pkg; web/Dockerfile.dockerignore admits only web/ and those two. Both NEXT_PUBLIC_
# values are public and frozen at build.

FROM node:24.22.0-trixie-slim@sha256:a6155384446670e9719bdc4fd0ebe4d4b29fb32a8d6aa523da3547a6cfbcf22c AS deps
WORKDIR /repo/web
COPY web/package.json web/package-lock.json ./
RUN npm ci

FROM node:24.22.0-trixie-slim@sha256:a6155384446670e9719bdc4fd0ebe4d4b29fb32a8d6aa523da3547a6cfbcf22c AS build
WORKDIR /repo/web
COPY app/assets/fonts /repo/app/assets/fonts
COPY engine-wasm/pkg /repo/engine-wasm/pkg
COPY web/ ./
COPY --from=deps /repo/web/node_modules ./node_modules
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:24.22.0-trixie-slim@sha256:a6155384446670e9719bdc4fd0ebe4d4b29fb32a8d6aa523da3547a6cfbcf22c AS runtime
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 HOSTNAME=0.0.0.0 PORT=3000
COPY --from=build --chown=node:node /repo/web/.next/standalone ./
COPY --from=build --chown=node:node /repo/web/.next/static ./.next/static
COPY --from=build --chown=node:node /repo/web/public ./public
# The node user, uid 1000, comes with the base image.
USER node
EXPOSE 3000
CMD ["node", "server.js"]
