# frontend/Dockerfile

FROM node:20-bookworm-slim AS deps
WORKDIR /app

# Copy only package.json for dependency install.
# We intentionally don't require package-lock.json because you don't have npm locally.
COPY package.json ./

# Resolve peer deps safely (you had eslint conflicts earlier).
# Once you install Node locally and commit package-lock.json, we’ll switch to `npm ci`.
RUN npm install --legacy-peer-deps

FROM node:20-bookworm-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app ./
EXPOSE 3000
CMD ["npm", "start"]