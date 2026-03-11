import { z } from 'zod'

export const MACHINE_DATA_PLANE_PROTOCOL_VERSION = 1 as const
export const MACHINE_DATA_PLANE_SUBPROTOCOL = 'unhappy-machine-dp.v1'
export const MACHINE_DATA_PLANE_PATH_TEMPLATE = '/v1/machines/:machineId/data-plane'
export const MACHINE_DATA_PLANE_DEFAULT_MAX_CHUNK_BYTES = 262_144
export const MACHINE_DATA_PLANE_DEFAULT_MAX_IN_FLIGHT_STREAMS = 8

export const MachineDataPlaneRoleSchema = z.enum(['native', 'daemon'])
export const MachineDataPlaneKeyExchangeSchema = z.object({
  algorithm: z.literal('x25519-hkdf-sha256'),
  publicKey: z.string().min(1),
  nonce: z.string().min(1),
})
export const MachineDataPlaneSealedBodySchema = z.object({
  algorithm: z.literal('aes-256-gcm'),
  nonce: z.string().min(1),
  ciphertext: z.string().min(1),
  tag: z.string().min(1),
})
export const MachineDataPlaneOperationSchema = z.enum([
  'provider.spawn',
  'machine.ping',
  'machine.listModels',
  'daemon.preventSleep',
  'daemon.stop',
  'daemon.update',
  'project.list',
  'project.open',
  'project.remove',
  'codex.listThreads',
  'codex.archiveThread',
  'codex.openThread',
  'codex.listMessages',
  'codex.sendMessage',
  'claude.listSessions',
  'claude.listMessages',
  'claude.sendMessage',
  'gemini.listSessions',
  'gemini.listMessages',
  'gemini.sendMessage',
  'fs.listDirectory',
  'fs.getDirectoryTree',
  'fs.readFile',
  'fs.writeFile',
  'exec.bash',
  'search.ripgrep',
  'diff.difftastic',
])

export const MachineDataPlaneFrameTypeSchema = z.enum([
  'hello',
  'hello-ack',
  'request',
  'complete',
  'error',
])

const BaseFrameSchema = z.object({
  v: z.literal(MACHINE_DATA_PLANE_PROTOCOL_VERSION),
  t: MachineDataPlaneFrameTypeSchema,
})

export const MachineDataPlaneHelloFrameSchema = BaseFrameSchema.extend({
  t: z.literal('hello'),
  connectionId: z.string().min(1),
  role: MachineDataPlaneRoleSchema,
  keyExchange: MachineDataPlaneKeyExchangeSchema,
})

export const MachineDataPlaneHelloAckFrameSchema = BaseFrameSchema.extend({
  t: z.literal('hello-ack'),
  connectionId: z.string().min(1),
  sessionId: z.string().min(1),
  keyExchange: MachineDataPlaneKeyExchangeSchema,
  maxChunkBytes: z.number().int().positive(),
  maxInFlightStreams: z.number().int().positive(),
  idleTimeoutSeconds: z.number().int().positive(),
})

export const MachineDataPlaneRequestFrameSchema = BaseFrameSchema.extend({
  t: z.literal('request'),
  streamId: z.string().min(1),
  op: MachineDataPlaneOperationSchema,
  body: MachineDataPlaneSealedBodySchema,
})

export const MachineDataPlaneCompleteFrameSchema = BaseFrameSchema.extend({
  t: z.literal('complete'),
  streamId: z.string().min(1),
  seq: z.number().int().nonnegative(),
  body: MachineDataPlaneSealedBodySchema,
  hasMore: z.boolean().optional(),
  nextCursor: z.string().min(1).optional(),
})

export const MachineDataPlaneErrorFrameSchema = BaseFrameSchema.extend({
  t: z.literal('error'),
  streamId: z.string().min(1),
  code: z.string().min(1),
  message: z.string().min(1),
  retryable: z.boolean(),
})

export const MachineDataPlaneFrameSchema = z.discriminatedUnion('t', [
  MachineDataPlaneHelloFrameSchema,
  MachineDataPlaneHelloAckFrameSchema,
  MachineDataPlaneRequestFrameSchema,
  MachineDataPlaneCompleteFrameSchema,
  MachineDataPlaneErrorFrameSchema,
])

export type MachineDataPlaneHelloFrame = z.infer<typeof MachineDataPlaneHelloFrameSchema>
