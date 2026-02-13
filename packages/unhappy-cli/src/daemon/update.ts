import { spawn } from 'child_process';

import { logger } from '@/ui/logger';
import { spawnUnhappyCLI } from '@/utils/spawnUnhappyCLI';
import { stopDaemon } from './controlClient';

const DEFAULT_UPDATE_COMMAND = 'npm install -g unhappy-cli@latest';

function resolveUpdateCommand(): string {
  const override = process.env.UNHAPPY_DAEMON_UPDATE_COMMAND?.trim();
  if (override) {
    return override;
  }
  return DEFAULT_UPDATE_COMMAND;
}

async function runShellCommand(
  command: string,
  opts: { quiet: boolean },
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(command, {
      shell: true,
      stdio: opts.quiet ? 'ignore' : 'inherit',
      env: process.env,
    });

    child.once('error', (error) => {
      reject(error);
    });

    child.once('exit', (code, signal) => {
      if (code === 0) {
        resolve();
        return;
      }
      const reason =
        signal !== null
          ? `terminated by signal ${signal}`
          : `exited with code ${code ?? 'unknown'}`;
      reject(new Error(`Update command ${reason}`));
    });
  });
}

export async function runDaemonUpdate(opts?: {
  quiet?: boolean;
}): Promise<{ command: string }> {
  const quiet = opts?.quiet === true;
  const command = resolveUpdateCommand();

  logger.info(`[DAEMON UPDATE] Running update command: ${command}`);
  await runShellCommand(command, { quiet });

  // Always restart daemon after update command, even if version did not change.
  // This keeps behavior predictable for "update now" requests from mobile.
  await stopDaemon();

  const child = spawnUnhappyCLI(['daemon', 'start-sync'], {
    detached: true,
    stdio: 'ignore',
    env: process.env,
  });
  child.unref();

  logger.info('[DAEMON UPDATE] Daemon restart requested');
  return { command };
}
