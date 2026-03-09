import { execFile, spawn } from 'node:child_process';

import {
  getDaemonLauncherEnvironment,
  resolveDaemonExecutable,
  spawnDaemonExecutable,
} from './executable';

function resolveLauncherEnvironment(opts?: {
  env?: NodeJS.ProcessEnv;
}): Promise<NodeJS.ProcessEnv> {
  return getDaemonLauncherEnvironment(opts?.env ?? process.env);
}

export async function runRustDaemonLauncherCommand(
  args: string[],
  opts?: {
    env?: NodeJS.ProcessEnv;
  },
): Promise<string> {
  const executable = resolveDaemonExecutable();
  const env = await resolveLauncherEnvironment(opts);

  return await new Promise<string>((resolve, reject) => {
    execFile(
      executable.executablePath,
      args,
      { env },
      (error, stdout, stderr) => {
        if (error) {
          reject(
            stderr.trim()
              ? new Error(stderr.trim())
              : error,
          );
          return;
        }
        resolve(stdout.trim());
      },
    );
  });
}

export async function startDaemonViaRustLauncher(opts?: {
  detached?: boolean;
  env?: NodeJS.ProcessEnv;
}): Promise<string> {
  if (opts?.detached === false) {
    const child = await spawnDaemonExecutable({
      detached: false,
      stdio: 'inherit',
      env: opts.env ?? process.env,
    });
    await new Promise<void>((resolve, reject) => {
      child.once('error', reject);
      child.once('close', (code, signal) => {
        if (signal) {
          reject(new Error(`daemon start terminated by signal ${signal}`));
          return;
        }
        if ((code ?? 0) !== 0) {
          reject(new Error(`daemon start exited with code ${code ?? 'unknown'}`));
          return;
        }
        resolve();
      });
    });
    return '';
  }

  return await runRustDaemonLauncherCommand(['start'], {
    env: opts?.env,
  });
}

export async function stopDaemonViaRustLauncher(opts?: {
  env?: NodeJS.ProcessEnv;
}): Promise<void> {
  await runRustDaemonLauncherCommand(['stop'], { env: opts?.env });
}

export async function printDaemonStatusViaRustLauncher(opts?: {
  env?: NodeJS.ProcessEnv;
}): Promise<void> {
  const executable = resolveDaemonExecutable();
  const env = await resolveLauncherEnvironment({ env: opts?.env });
  await new Promise<void>((resolve, reject) => {
    const child = spawn(executable.executablePath, ['status'], {
      env,
      stdio: 'inherit',
    });
    child.once('error', reject);
    child.once('close', (code, signal) => {
      if (signal) {
        reject(new Error(`daemon status terminated by signal ${signal}`));
        return;
      }
      if ((code ?? 0) !== 0) {
        reject(new Error(`daemon status exited with code ${code ?? 'unknown'}`));
        return;
      }
      resolve();
    });
  });
}

export async function listDaemonProcessesViaRust(opts?: {
  env?: NodeJS.ProcessEnv;
}): Promise<Array<{ pid: number; command: string; processType: string }>> {
  const output = await runRustDaemonLauncherCommand(['doctor-processes', '--json'], {
    env: opts?.env,
  });
  return JSON.parse(output) as Array<{ pid: number; command: string; processType: string }>;
}

export async function cleanDaemonProcessesViaRust(opts?: {
  env?: NodeJS.ProcessEnv;
}): Promise<{ killed: number; errors: Array<{ pid: number; error: string }> }> {
  const output = await runRustDaemonLauncherCommand(['doctor-clean', '--json'], {
    env: opts?.env,
  });
  return JSON.parse(output) as { killed: number; errors: Array<{ pid: number; error: string }> };
}

export async function installDaemonViaRust(opts?: {
  env?: NodeJS.ProcessEnv;
}): Promise<void> {
  await runRustDaemonLauncherCommand(['install'], {
    env: opts?.env,
  });
}

export async function uninstallDaemonViaRust(opts?: {
  env?: NodeJS.ProcessEnv;
}): Promise<void> {
  await runRustDaemonLauncherCommand(['uninstall'], {
    env: opts?.env,
  });
}
