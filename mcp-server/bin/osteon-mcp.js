#!/usr/bin/env node

import path from 'node:path';
import { OsteonMcpServer } from '../src/index.js';
import { createHttpServer } from '../src/http.js';

const args = process.argv.slice(2);
let targetDir = process.cwd();
let isHttp = false;
let port = 8080;

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--dir' || args[i] === '-d') {
    targetDir = args[++i];
  } else if (args[i] === '--http') {
    isHttp = true;
  } else if (args[i] === '--port' || args[i] === '-p') {
    port = parseInt(args[++i], 10);
  } else if (!args[i].startsWith('-')) {
    targetDir = args[i];
  }
}

const resolvedDir = path.resolve(targetDir);

if (isHttp) {
  const httpServer = createHttpServer(resolvedDir, port);
  httpServer.listen(port, () => {
    console.error(`[osteon-http] Headless REST API listening on http://localhost:${port} for ${resolvedDir}`);
  });
} else {
  const server = new OsteonMcpServer(resolvedDir);
  server.start();
}
