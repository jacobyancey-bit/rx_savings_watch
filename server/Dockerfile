# Multi-stage production Dockerfile for rx_savings_watch backend
FROM node:22-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Production image
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Install curl for healthcheck
RUN apk add --no-cache curl

# Copy dependencies from builder
COPY --from=builder /app/node_modules ./node_modules
COPY package*.json ./

# Copy application source and schema
COPY src/ ./src/
COPY scripts/ ./scripts/
COPY data/fixtures/ ./data/fixtures/
COPY data/live_seed_drugs.json ./data/live_seed_drugs.json

# Ensure data directory exists for volume mount
RUN mkdir -p /app/data

EXPOSE 3000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Start the server
CMD ["node", "src/server.js"]
