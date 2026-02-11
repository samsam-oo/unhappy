import { describe, expect, it } from 'vitest';
import { CodexAppServerClient } from '../codexAppServerClient';

describe('Codex identifiers extraction', () => {
  it('extracts session id from structuredContent.threadId', () => {
    const c = new CodexAppServerClient();
    const anyC: any = c;

    anyC.extractIdentifiers({
      content: [{ type: 'text', text: 'OK' }],
      structuredContent: { threadId: 'thread-1', content: 'OK' },
    });

    expect(c.getSessionId()).toBe('thread-1');
  });

  it('extracts session id from event.session_id and event.thread_id', () => {
    const c = new CodexAppServerClient();
    const anyC: any = c;

    anyC.updateIdentifiersFromEvent({ type: 'session_configured', session_id: 'sess-1' });
    expect(c.getSessionId()).toBe('sess-1');

    anyC.updateIdentifiersFromEvent({ type: 'item_started', thread_id: 'thread-2' });
    expect(c.getSessionId()).toBe('thread-2');
  });

  it('extracts conversation id from event.conversation_id', () => {
    const c = new CodexAppServerClient();
    const anyC: any = c;

    anyC.updateIdentifiersFromEvent({ conversation_id: 'conv-1' });
    expect(c.getConversationId()).toBe('conv-1');
  });
});
