# Production Dockerfile for Medusa
FROM node:20-alpine

# Set working directory
WORKDIR /server

# Copy package files
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn/releases .yarn/releases

# Install all dependencies
RUN yarn install

# Copy source code
COPY . .

# Build the Medusa application for production
RUN yarn medusa build

# Expose the port Medusa runs on
EXPOSE 9000

# Change to the build output directory, install production dependencies,
# run migrations, and start the server
CMD ["sh", "-c", "cd .medusa/server && yarn install && yarn predeploy && yarn run start"]
