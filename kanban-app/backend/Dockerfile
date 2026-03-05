FROM node:20-alpine

# Build tools needed for better-sqlite3 (native module)
RUN apk add --no-cache python3 make g++

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

# Persistent data directories
RUN mkdir -p /data /app/uploads

EXPOSE 3001

CMD ["node", "server.js"]
