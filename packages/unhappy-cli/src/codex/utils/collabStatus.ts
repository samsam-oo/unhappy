export type CollabStage = 'in_progress' | 'completed';

export type CollabStatusEvent = {
  key: string;
  stage: CollabStage;
};

export type CollabStatusState = {
  seenByKey: Map<string, CollabStage>;
  maxEntries: number;
};

const DEFAULT_MAX_ENTRIES = 512;

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object';
}

function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function normalizeStageFromStatus(status: unknown): CollabStage | null {
  const raw = asNonEmptyString(status);
  if (!raw) return null;
  const normalized = raw.toLowerCase();
  if (
    normalized === 'inprogress' ||
    normalized === 'in_progress' ||
    normalized === 'running' ||
    normalized === 'pending' ||
    normalized === 'pending_init' ||
    normalized === 'pendinginit'
  ) {
    return 'in_progress';
  }
  if (
    normalized === 'completed' ||
    normalized === 'failed' ||
    normalized === 'errored' ||
    normalized === 'error' ||
    normalized === 'shutdown' ||
    normalized === 'notfound' ||
    normalized === 'not_found'
  ) {
    return 'completed';
  }
  return null;
}

function buildFallbackKey(parts: Array<string | null>): string {
  return parts.filter((part): part is string => !!part && part.length > 0).join('|');
}

function extractFromLegacyCollabEvent(msg: Record<string, unknown>): CollabStatusEvent | null {
  const type = asNonEmptyString(msg.type);
  if (!type || !type.startsWith('collab_')) {
    return null;
  }

  let stage: CollabStage | null = null;
  if (type.endsWith('_begin')) {
    stage = 'in_progress';
  } else if (type.endsWith('_end')) {
    stage = 'completed';
  } else {
    stage = normalizeStageFromStatus(msg.status);
  }
  if (!stage) return null;

  const callId = asNonEmptyString(msg.call_id) ?? asNonEmptyString(msg.callId);
  const sender = asNonEmptyString(msg.sender_thread_id);
  const receiver = asNonEmptyString(msg.receiver_thread_id);
  const newThread = asNonEmptyString(msg.new_thread_id);
  const key =
    callId ??
    buildFallbackKey([
      type,
      sender,
      receiver,
      newThread,
      asStringArray(msg.receiver_thread_ids).join(','),
    ]);
  if (!key) return null;

  return { key, stage };
}

function extractFromCollabToolCallItem(msg: Record<string, unknown>): CollabStatusEvent | null {
  const msgType = asNonEmptyString(msg.type);
  if (msgType !== 'item_started' && msgType !== 'item_completed') {
    return null;
  }

  const item = isRecord(msg.item) ? msg.item : null;
  if (!item || item.type !== 'collabAgentToolCall') {
    return null;
  }

  const statusStage = normalizeStageFromStatus(item.status);
  const stage =
    statusStage ?? (msgType === 'item_started' ? 'in_progress' : 'completed');

  const callId = asNonEmptyString(item.id);
  const sender = asNonEmptyString(item.senderThreadId);
  const tool = asNonEmptyString(item.tool);
  const receiverIds = asStringArray(item.receiverThreadIds);
  const key =
    callId ??
    buildFallbackKey([tool, sender, receiverIds.join(',')]);
  if (!key) return null;

  return { key, stage };
}

export function createCollabStatusState(maxEntries = DEFAULT_MAX_ENTRIES): CollabStatusState {
  return {
    seenByKey: new Map<string, CollabStage>(),
    maxEntries,
  };
}

export function extractCollabStatusEvent(msg: unknown): CollabStatusEvent | null {
  if (!isRecord(msg)) {
    return null;
  }
  return (
    extractFromLegacyCollabEvent(msg) ?? extractFromCollabToolCallItem(msg)
  );
}

export function consumeCollabStatusMessage(
  msg: unknown,
  state: CollabStatusState,
): string | null {
  const event = extractCollabStatusEvent(msg);
  if (!event) return null;

  const previous = state.seenByKey.get(event.key);
  if (previous === event.stage) {
    return null;
  }

  state.seenByKey.set(event.key, event.stage);
  if (state.seenByKey.size > state.maxEntries) {
    const oldest = state.seenByKey.keys().next().value;
    if (typeof oldest === 'string') {
      state.seenByKey.delete(oldest);
    }
  }

  return event.stage === 'in_progress'
    ? 'Sub-agent in progress'
    : 'Sub-agent completed';
}
