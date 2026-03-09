import os from 'node:os';

import { type MachineMetadata } from '@/api/types';
import { configuration } from '@/configuration';
import packageJson from '../../package.json';
import { projectPath } from '@/projectPath';
import { resolveMachineHost } from '@/utils/machineHost';

export const initialMachineMetadata: MachineMetadata = {
  host: resolveMachineHost(),
  platform: os.platform(),
  happyCliVersion: packageJson.version,
  homeDir: os.homedir(),
  unhappyHomeDir: configuration.unhappyHomeDir,
  unhappyLibDir: projectPath(),
};
