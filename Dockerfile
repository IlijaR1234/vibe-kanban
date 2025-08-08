# Start with the same standard base image
FROM node:18-alpine

# Install build dependencies
RUN apk add --no-cache curl build-base perl tini git

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# Add Rust's binaries to the PATH for subsequent commands
ENV PATH="/root/.cargo/bin:${PATH}"

# --- FIX 1: Set a single, consistent working directory for the entire build ---
WORKDIR /app

# --- FIX 2: Create a dedicated data directory and set correct ownership ---
# The node:alpine image includes a non-root 'node' user (UID 1000). We'll use it.
# This ensures the application has a safe place to write its database.
RUN mkdir /app/data && chown -R node:node /app

# Copy package files first for caching, setting ownership as we copy
COPY --chown=node:node package*.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY --chown=node:node frontend/package*.json ./frontend/
COPY --chown=node:node npx-cli/package*.json ./npx-cli/

# Install dependencies using pnpm
RUN npm install -g pnpm
RUN pnpm install

# Copy the rest of the source code, ensuring the 'node' user owns it
COPY --chown=node:node . .

# Build the frontend and backend
RUN cd frontend && npm run build
RUN cargo build --release --manifest-path backend/Cargo.toml

# --- FIX 3: Enforce the database path and other env variables ---
# This makes the image self-contained and predictable.
ENV DATABASE_PATH=/app/data/sqlite.db
ENV HOST=0.0.0.0
ENV PORT=3000
EXPOSE 3000

# --- FIX 4: Switch to the non-root 'node' user for security ---
USER node

# Use tini as the entrypoint and run the final compiled application
# The working directory is now correctly /app, where the executable is.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/target/release/vibe-kanban"]
