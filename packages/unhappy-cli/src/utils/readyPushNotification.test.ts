import { describe, it, expect, vi, beforeEach } from 'vitest';

const { mockExecSync, mockExistsSync, mockReadFileSync, mockHomedir } =
  vi.hoisted(() => ({
    mockExecSync: vi.fn(),
    mockExistsSync: vi.fn(),
    mockReadFileSync: vi.fn(),
    mockHomedir: vi.fn(),
  }));

vi.mock('node:child_process', () => ({
  execSync: mockExecSync,
}));

vi.mock('node:fs', () => ({
  default: {
    existsSync: mockExistsSync,
    readFileSync: mockReadFileSync,
  },
  existsSync: mockExistsSync,
  readFileSync: mockReadFileSync,
}));

vi.mock('node:os', () => ({
  default: {
    homedir: mockHomedir,
  },
  homedir: mockHomedir,
}));

import { buildReadyPushNotification } from './readyPushNotification';

describe('buildReadyPushNotification', () => {
  beforeEach(() => {
    mockExecSync.mockReset();
    mockExistsSync.mockReset();
    mockReadFileSync.mockReset();
    mockHomedir.mockReset();
  });

  it('falls back to cwd when not in a git repo and no package.json', () => {
    mockHomedir.mockReturnValue('/home/test');
    mockExecSync.mockImplementation(() => {
      throw new Error('not a git repo');
    });
    mockExistsSync.mockReturnValue(false);

    const ready = buildReadyPushNotification({
      agentName: 'Codex',
      cwd: '/home/test/work/unhappy',
    });

    expect(ready.title).toBe('Codex ready: unhappy');
    expect(ready.body).toBe('Waiting for your command in ~/work/unhappy');
    expect(ready.data).toMatchObject({
      agentName: 'Codex',
      cwd: '/home/test/work/unhappy',
      projectRoot: '/home/test/work/unhappy',
      gitRoot: undefined,
      gitBranch: undefined,
      packageName: undefined,
      displayName: 'unhappy',
    });
  });

  it('uses git root, branch, and package.json name when available', () => {
    mockHomedir.mockReturnValue('/home/test');
    mockExecSync.mockImplementation((cmd: string) => {
      if (cmd.includes('--show-toplevel')) return '/repo\n';
      if (cmd.includes('--abbrev-ref')) return 'main\n';
      throw new Error('unexpected cmd');
    });
    mockExistsSync.mockImplementation((p: string) => p === '/repo/package.json');
    mockReadFileSync.mockReturnValue(
      JSON.stringify({ name: '@acme/myproj' }),
    );

    const ready = buildReadyPushNotification({
      agentName: 'Gemini',
      cwd: '/repo/packages/app',
    });

    expect(ready.title).toBe('Gemini ready: myproj (main)');
    expect(ready.body).toBe('Waiting for your command in /repo');
    expect(ready.data).toMatchObject({
      agentName: 'Gemini',
      cwd: '/repo/packages/app',
      projectRoot: '/repo',
      gitRoot: '/repo',
      gitBranch: 'main',
      packageName: '@acme/myproj',
      displayName: 'myproj',
    });
  });
});
