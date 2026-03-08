import { z } from 'zod'
import { UsageSchema } from '@/claude/types'

/**
 * Permission mode type - includes both Claude and Codex modes
 * Must match MessageMetaSchema.permissionMode enum values
 *
 * Claude modes: default, acceptEdits, bypassPermissions, plan
 * Codex modes: passthrough, read-only, safe-yolo, yolo
 *
 * When calling Claude SDK, Codex modes are mapped at the SDK boundary:
 * - yolo → bypassPermissions
 * - safe-yolo → default
 * - read-only → default
 */
export type PermissionMode =
  | 'default'
  | 'acceptEdits'
  | 'bypassPermissions'
  | 'plan'
  | 'passthrough'
  | 'read-only'
  | 'safe-yolo'
  | 'yolo'

/**
 * Usage data type from Claude
 */
export type Usage = z.infer<typeof UsageSchema>

/**
 * Update body for machine updates
 */
export const UpdateMachineBodySchema = z.object({
  t: z.literal('update-machine'),
  machineId: z.string(),
  metadata: z.object({
    version: z.number(),
    value: z.string()
  }).nullish(),
  daemonState: z.object({
    version: z.number(),
    value: z.string()
  }).nullish()
})

export type UpdateMachineBody = z.infer<typeof UpdateMachineBodySchema>

/**
 * Update event from server
 */
export const UpdateSchema = z.object({
  id: z.string(),
  seq: z.number(),
  body: UpdateMachineBodySchema,
  createdAt: z.number()
})

export type Update = z.infer<typeof UpdateSchema>

/**
 * Machine metadata - static information (rarely changes)
 */
export const MachineMetadataSchema = z.object({
  host: z.string(),
  platform: z.string(),
  happyCliVersion: z.string(),
  homeDir: z.string(),
  unhappyHomeDir: z.string(),
  unhappyLibDir: z.string()
})

export type MachineMetadata = z.infer<typeof MachineMetadataSchema>

/**
 * Daemon state - dynamic runtime information (frequently updated)
 */
export const DaemonStateSchema = z.object({
  status: z.union([
    z.enum(['running', 'shutting-down']),
    z.string() // Forward compatibility
  ]),
  pid: z.number().optional(),
  httpPort: z.number().optional(),
  startedAt: z.number().optional(),
  shutdownRequestedAt: z.number().optional(),
  shutdownSource:
    z.union([
      z.enum(['mobile-app', 'cli', 'os-signal', 'unknown']),
      z.string() // Forward compatibility
    ]).optional(),
  openedProjects: z.array(
    z.object({
      path: z.string(),
      openedAt: z.number().optional()
    })
  ).optional()
})

export type DaemonState = z.infer<typeof DaemonStateSchema>

export type Machine = {
  id: string,
  encryptionKey: Uint8Array;
  metadata: MachineMetadata,
  metadataVersion: number,
  daemonState: DaemonState | null,
  daemonStateVersion: number,
}

/**
 * Message metadata schema
 */
export const MessageMetaSchema = z.object({
  sentFrom: z.string().optional(), // Source identifier
  permissionMode: z.enum(['default', 'acceptEdits', 'bypassPermissions', 'plan', 'passthrough', 'read-only', 'safe-yolo', 'yolo']).optional(), // Permission mode for this message
  steerMode: z.enum(['queue', 'immediate']).optional(), // Codex steer behavior for this message
  model: z.string().nullable().optional(), // Model name for this message (null = reset)
  fallbackModel: z.string().nullable().optional(), // Fallback model for this message (null = reset)
  effort: z.string().nullable().optional(), // Reasoning effort for this message (null = reset)
  customSystemPrompt: z.string().nullable().optional(), // Custom system prompt for this message (null = reset)
  appendSystemPrompt: z.string().nullable().optional(), // Append to system prompt for this message (null = reset)
  allowedTools: z.array(z.string()).nullable().optional(), // Allowed tools for this message (null = reset)
  disallowedTools: z.array(z.string()).nullable().optional() // Disallowed tools for this message (null = reset)
})

export type MessageMeta = z.infer<typeof MessageMetaSchema>

const UserTextContentSchema = z.object({
  type: z.literal('text'),
  text: z.string()
});

const UserStructuredTextItemSchema = z.object({
  type: z.enum(['text', 'input_text']),
  text: z.string().optional(),
  input_text: z.string().optional(),
}).refine((value) => {
  const text = typeof value.text === 'string' ? value.text.trim() : '';
  const inputText = typeof value.input_text === 'string' ? value.input_text.trim() : '';
  return text.length > 0 || inputText.length > 0;
}, {
  message: 'User text content item must include text',
});

const UserStructuredImageItemSchema = z.object({
  type: z.enum(['input_image', 'image_url', 'image']),
  image_url: z.string().optional(),
  url: z.string().optional(),
}).refine((value) => {
  const imageURL = typeof value.image_url === 'string' ? value.image_url.trim() : '';
  const url = typeof value.url === 'string' ? value.url.trim() : '';
  return imageURL.length > 0 || url.length > 0;
}, {
  message: 'User image content item must include a URL',
});

const UserStructuredContentItemSchema = z.union([
  UserStructuredTextItemSchema,
  UserStructuredImageItemSchema,
]);

export const UserMessageSchema = z.object({
  role: z.literal('user'),
  content: z.union([
    UserTextContentSchema,
    z.array(UserStructuredContentItemSchema).min(1),
  ]),
  localKey: z.string().optional(), // Mobile messages include this
  meta: MessageMetaSchema.optional()
})

export type UserMessage = z.infer<typeof UserMessageSchema>

export function extractUserMessageText(content: UserMessage['content']): string {
  if (!Array.isArray(content)) {
    return typeof content.text === 'string' ? content.text : '';
  }
  return content
    .map((item) => {
      if (item.type === 'text' || item.type === 'input_text') {
        if (typeof item.text === 'string' && item.text.trim()) {
          return item.text;
        }
        if (typeof item.input_text === 'string' && item.input_text.trim()) {
          return item.input_text;
        }
      }
      return '';
    })
    .filter((item) => item.trim().length > 0)
    .join('\n');
}

export function extractUserMessageImageUrls(content: UserMessage['content']): string[] {
  if (!Array.isArray(content)) {
    return [];
  }
  return content
    .map((item) => {
      if (item.type === 'input_image' || item.type === 'image_url' || item.type === 'image') {
        if (typeof item.image_url === 'string' && item.image_url.trim()) {
          return item.image_url;
        }
        if (typeof item.url === 'string' && item.url.trim()) {
          return item.url;
        }
      }
      return '';
    })
    .filter((item) => item.trim().length > 0);
}

export const AgentMessageSchema = z.object({
  role: z.literal('agent'),
  content: z.object({
    type: z.literal('output'),
    data: z.any()
  }),
  meta: MessageMetaSchema.optional()
})

export type AgentMessage = z.infer<typeof AgentMessageSchema>

export const MessageContentSchema = z.union([UserMessageSchema, AgentMessageSchema])

export type MessageContent = z.infer<typeof MessageContentSchema>

export type Metadata = {
  path: string,
  host: string,
  version?: string,
  name?: string,
  os?: string,
  summary?: {
    text: string,
    updatedAt: number
  },
  machineId?: string,
  /**
   * Upstream/agent session identifiers (Claude Code / Codex / etc).
   * Preferred over provider-specific fields.
   */
  agentSessionId?: string,
  agentConversationId?: string,
  agentTranscriptPath?: string,
  tools?: string[],
  slashCommands?: string[],
  homeDir: string,
  unhappyHomeDir: string,
  unhappyLibDir: string,
  unhappyToolsDir: string,
  startedFromDaemon?: boolean,
  hostPid?: number,
  startedBy?: 'daemon' | 'terminal',
  // Lifecycle state management
  lifecycleState?: 'running' | 'archiveRequested' | 'archived' | string,
  lifecycleStateSince?: number,
  archivedBy?: string,
  archiveReason?: string,
  flavor?: string
};

export type AgentState = {
  controlledByUser?: boolean | null | undefined
  mode?: {
    model?: string
    effort?: string
    permissionMode?: PermissionMode
    fallbackModel?: string
  }
  queue?: {
    pendingMessages?: string[]
    queuedCount?: number
    isProcessing?: boolean
    hasPendingRetry?: boolean
    updatedAt?: number
  }
  collab?: {
    state: 'in_progress' | 'completed',
    updatedAt: number,
    activeCount?: number
  }
  requests?: {
    [id: string]: {
      tool: string,
      arguments: any,
      createdAt: number
    }
  }
  completedRequests?: {
    [id: string]: {
      tool: string,
      arguments: any,
      createdAt: number,
      completedAt: number,
      status: 'canceled' | 'denied' | 'approved',
      reason?: string,
      mode?: PermissionMode,
      decision?: 'approved' | 'approved_for_session' | 'denied' | 'abort',
      allowTools?: string[]
    }
  }
}
