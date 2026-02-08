#!/usr/bin/env node
/**
 * Cross-platform environment wrapper for unhappy CLI
 * Sets UNHAPPY_HOME_DIR and provides visual feedback
 *
 * Usage: node scripts/env-wrapper.js <variant> <command> [...args]
 *
 * Variants:
 *   - stable: Production-ready version using ~/.unhappy/
 *   - dev: Development version using ~/.unhappy-dev/
 *
 * Examples:
 *   node scripts/env-wrapper.js stable daemon start
 *   node scripts/env-wrapper.js dev auth login
 */

const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');

const VARIANTS = {
  stable: {
    homeDir: path.join(os.homedir(), '.unhappy'),
    color: '\x1b[32m', // Green
    label: '✅ STABLE',
    serverUrl: process.env.UNHAPPY_SERVER_URL || 'https://api.unhappy.im',
  },
  dev: {
    homeDir: path.join(os.homedir(), '.unhappy-dev'),
    color: '\x1b[33m', // Yellow
    label: '🔧 DEV',
    serverUrl: process.env.UNHAPPY_SERVER_URL || 'https://api.unhappy.im',
  },
};

const variant = process.argv[2];
const command = process.argv[3];
const args = process.argv.slice(4);

if (!variant || !VARIANTS[variant]) {
  console.error(
    'Usage: node scripts/env-wrapper.js <stable|dev> <command> [...args]',
  );
  console.error('');
  console.error('Variants:');
  console.error('  stable - Production-ready version (data: ~/.unhappy/)');
  console.error('  dev    - Development version (data: ~/.unhappy-dev/)');
  console.error('');
  console.error('Examples:');
  console.error('  node scripts/env-wrapper.js stable daemon start');
  console.error('  node scripts/env-wrapper.js dev auth login');
  process.exit(1);
}

const config = VARIANTS[variant];

// Create home directory if it doesn't exist
if (!fs.existsSync(config.homeDir)) {
  fs.mkdirSync(config.homeDir, { recursive: true });
}

// Visual feedback
console.log(
  `${config.color}${config.label}\x1b[0m Unhappy CLI (data: ${config.homeDir})`,
);

// Set environment and execute command
const env = {
  ...process.env,
  UNHAPPY_HOME_DIR: config.homeDir,
  UNHAPPY_SERVER_URL: config.serverUrl,
  UNHAPPY_VARIANT: variant, // For internal validation
};

const binPath = path.join(__dirname, '..', 'bin', 'unhappy.mjs');
const proc = spawn('node', [binPath, command, ...args], {
  env,
  stdio: 'inherit',
  shell: process.platform === 'win32',
});

proc.on('exit', (code) => process.exit(code || 0));
