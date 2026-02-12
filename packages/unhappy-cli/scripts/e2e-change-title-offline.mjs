#!/usr/bin/env node

/**
 * Offline E2E for Unhappy title bridge.
 *
 * What this validates:
 * 1) A local mock HTTP MCP server exposes `change_title`.
 * 2) `bin/unhappy-mcp.mjs` starts a stdio MCP bridge to that HTTP server.
 * 3) A stdio MCP client can call `change_title` and the mock server receives it.
 *
 * No external network or cloud dependencies are required.
 */

import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, '..');
const bridgeEntrypoint = join(projectRoot, 'bin', 'unhappy-mcp.mjs');

const expectedTitle =
  process.argv[2] && process.argv[2].trim().length > 0
    ? process.argv[2].trim()
    : `offline-e2e-${randomUUID().slice(0, 8)}`;

let receivedTitle = null;
let server = null;
let mcpServer = null;
let client = null;
let clientTransport = null;

async function cleanup() {
  if (client) {
    try {
      await client.close();
    } catch {}
  }
  if (clientTransport) {
    try {
      await clientTransport.close();
    } catch {}
  }
  if (mcpServer) {
    try {
      await mcpServer.close();
    } catch {}
  }
  if (server) {
    try {
      await new Promise((resolve) => server.close(() => resolve()));
    } catch {}
  }
}

try {
  // 1) Start mock HTTP MCP server
  mcpServer = new McpServer({
    name: 'Offline Mock MCP',
    version: '1.0.0',
  });

  mcpServer.registerTool(
    'change_title',
    {
      description: 'Mock title update',
      title: 'Mock Change Title',
      inputSchema: {
        title: z.string().describe('The new title for the chat session'),
      },
    },
    async (args) => {
      receivedTitle = args.title;
      return {
        content: [
          {
            type: 'text',
            text: `Mock server accepted title: "${args.title}"`,
          },
        ],
        isError: false,
      };
    },
  );

  const httpTransport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
  });
  await mcpServer.connect(httpTransport);

  server = createServer(async (req, res) => {
    try {
      await httpTransport.handleRequest(req, res);
    } catch (error) {
      if (!res.headersSent) {
        res.writeHead(500).end();
      }
      process.stderr.write(
        `[offline-e2e] Mock HTTP MCP request failed: ${error instanceof Error ? error.message : String(error)}\n`,
      );
    }
  });

  const baseUrl = await new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        throw new Error('Failed to get local mock MCP address');
      }
      resolve(`http://127.0.0.1:${address.port}`);
    });
  });

  // 2) Start stdio bridge client against local mock server
  clientTransport = new StdioClientTransport({
    command: process.execPath,
    args: [bridgeEntrypoint, '--url', baseUrl],
    cwd: projectRoot,
    stderr: 'pipe',
  });

  let bridgeStderr = '';
  if (clientTransport.stderr) {
    clientTransport.stderr.on('data', (chunk) => {
      bridgeStderr += chunk.toString();
    });
  }

  client = new Client(
    { name: 'offline-e2e-client', version: '1.0.0' },
    { capabilities: {} },
  );

  await client.connect(clientTransport);
  const tools = await client.listTools();
  const hasChangeTitle = tools.tools.some((tool) => tool.name === 'change_title');
  if (!hasChangeTitle) {
    throw new Error('Bridge did not expose change_title tool');
  }

  // 3) Call change_title through stdio bridge and validate round-trip
  const response = await client.callTool({
    name: 'change_title',
    arguments: { title: expectedTitle },
  });

  if (response.isError) {
    const text = response.content
      .filter((v) => v.type === 'text')
      .map((v) => v.text)
      .join('\n');
    throw new Error(`change_title returned error: ${text || 'unknown error'}`);
  }

  if (receivedTitle !== expectedTitle) {
    throw new Error(
      `Mock server title mismatch: expected="${expectedTitle}" received="${receivedTitle}"`,
    );
  }

  const responseText = response.content
    .filter((v) => v.type === 'text')
    .map((v) => v.text)
    .join('\n');

  process.stdout.write(
    `[offline-e2e] PASS\n` +
      `  mockServerUrl: ${baseUrl}\n` +
      `  expectedTitle: ${expectedTitle}\n` +
      `  receivedTitle: ${receivedTitle}\n` +
      `  response: ${responseText || '(no text response)'}\n`,
  );

  if (bridgeStderr.trim().length > 0) {
    process.stdout.write(
      `  bridgeStderr:\n${bridgeStderr
        .trim()
        .split('\n')
        .map((line) => `    ${line}`)
        .join('\n')}\n`,
    );
  }
} catch (error) {
  process.stderr.write(
    `[offline-e2e] FAIL: ${error instanceof Error ? error.message : String(error)}\n`,
  );
  process.exitCode = 1;
} finally {
  await cleanup();
}
