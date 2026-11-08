#!/usr/bin/env node

import path from 'node:path';
import { OsteonMcpServer } from '../src/index.js';

const args = process.argv.slice(2);
let targetDir = process.cwd();

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--dir' || args[i] === '-d') {
    targetDir = args[++i];
  } else if (!args[i].startsWith('-')) {
    targetDir = args[i];
  }
}

const server = new OsteonMcpServer(path.resolve(targetDir));
server.start();
