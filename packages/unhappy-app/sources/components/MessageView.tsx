import { Metadata } from "@/sync/storageTypes";
import { sync } from '@/sync/sync';
import { AgentTextMessage, Message, ToolCall, ToolCallMessage, UserTextMessage } from "@/sync/typesMessage";
import { AgentEvent } from "@/sync/typesRaw";
import { t } from '@/text';
import * as React from "react";
import { Text, View } from "react-native";
import { StyleSheet } from 'react-native-unistyles';
import { layout } from "./layout";
import { MarkdownView, Option } from "./markdown/MarkdownView";
import { ToolView } from "./tools/ToolView";

function normalizeThinkingText(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) {
    return '';
  }

  const withoutPrefix = trimmed
    .replace(/^\*?Thinking\.\.\.\*?/i, '')
    .trim();

  const withoutWrapper =
    withoutPrefix.startsWith('*') && withoutPrefix.endsWith('*') && withoutPrefix.length > 1
      ? withoutPrefix.slice(1, -1).trim()
      : withoutPrefix;

  return withoutWrapper
    .split('\n')
    .map((line) => line.replace(/^\*+|\*+$/g, '').trimEnd())
    .join('\n')
    .trim();
}

export const MessageView = (props: {
  message: Message;
  metadata: Metadata | null;
  sessionId: string;
  getMessageById?: (id: string) => Message | null;
}) => {
  return (
    <View style={styles.messageContainer} renderToHardwareTextureAndroid={true}>
      <View style={styles.messageContent}>
        <RenderBlock
          message={props.message}
          metadata={props.metadata}
          sessionId={props.sessionId}
          getMessageById={props.getMessageById}
        />
      </View>
    </View>
  );
};

// RenderBlock function that dispatches to the correct component based on message kind
function RenderBlock(props: {
  message: Message;
  metadata: Metadata | null;
  sessionId: string;
  getMessageById?: (id: string) => Message | null;
}): React.ReactElement {
  switch (props.message.kind) {
    case 'user-text':
      return <UserTextBlock message={props.message} sessionId={props.sessionId} />;

    case 'agent-text':
      return <AgentTextBlock message={props.message} sessionId={props.sessionId} metadata={props.metadata} />;

    case 'tool-call':
      return <ToolCallBlock
        message={props.message}
        metadata={props.metadata}
        sessionId={props.sessionId}
        getMessageById={props.getMessageById}
      />;

    case 'agent-event':
      return <AgentEventBlock event={props.message.event} metadata={props.metadata} />;


    default:
      // Exhaustive check - TypeScript will error if we miss a case
      const _exhaustive: never = props.message;
      throw new Error(`Unknown message kind: ${_exhaustive}`);
  }
}

function UserTextBlock(props: {
  message: UserTextMessage;
  sessionId: string;
}) {
  const handleOptionPress = React.useCallback((option: Option) => {
    sync.sendMessage(props.sessionId, option.title);
  }, [props.sessionId]);

  return (
    <View style={styles.userMessageContainer}>
      <View style={styles.userMessageBubble}>
        <MarkdownView markdown={props.message.displayText || props.message.text} onOptionPress={handleOptionPress} />
        {/* {__DEV__ && (
          <Text style={styles.debugText}>{JSON.stringify(props.message.meta)}</Text>
        )} */}
      </View>
    </View>
  );
}

function AgentTextBlock(props: {
  message: AgentTextMessage;
  sessionId: string;
  metadata: Metadata | null;
}) {
  const handleOptionPress = React.useCallback((option: Option) => {
    sync.sendMessage(props.sessionId, option.title);
  }, [props.sessionId]);

  const isThinkingText =
    props.message.isThinking || /^\*?Thinking\.\.\./i.test(props.message.text.trim());

  if (isThinkingText) {
    const thinkingBody = normalizeThinkingText(props.message.text);
    const syntheticThinkingTool: ToolCall = {
      name: 'think',
      state: 'completed',
      input: { title: 'Thinking...' },
      createdAt: props.message.createdAt,
      startedAt: props.message.createdAt,
      completedAt: props.message.createdAt,
      description: 'Thinking...',
      result: {
        content: thinkingBody || props.message.text,
        status: 'completed',
      },
    };

    return (
      <View style={styles.toolContainer}>
        <ToolView
          tool={syntheticThinkingTool}
          metadata={props.metadata}
          messages={[]}
          variant="chat"
          onPress={() => { }}
        />
      </View>
    );
  }

  return (
    <View style={styles.agentMessageContainer}>
      <MarkdownView markdown={props.message.text} onOptionPress={handleOptionPress} />
    </View>
  );
}

function AgentEventBlock(props: {
  event: AgentEvent;
  metadata: Metadata | null;
}) {
  if (props.event.type === 'switch') {
    return (
      <View style={styles.agentEventContainer}>
        <Text style={styles.agentEventText}>{t('message.switchedToMode', { mode: props.event.mode })}</Text>
      </View>
    );
  }
  if (props.event.type === 'message') {
    return (
      <View style={styles.agentEventContainer}>
        <Text style={styles.agentEventText}>{props.event.message}</Text>
      </View>
    );
  }
  if (props.event.type === 'limit-reached') {
    const formatTime = (timestamp: number): string => {
      try {
        const date = new Date(timestamp * 1000); // Convert from Unix timestamp
        return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      } catch {
        return t('message.unknownTime');
      }
    };

    return (
      <View style={styles.agentEventContainer}>
        <Text style={styles.agentEventText}>
          {t('message.usageLimitUntil', { time: formatTime(props.event.endsAt) })}
        </Text>
      </View>
    );
  }
  return (
    <View style={styles.agentEventContainer}>
      <Text style={styles.agentEventText}>{t('message.unknownEvent')}</Text>
    </View>
  );
}

function ToolCallBlock(props: {
  message: ToolCallMessage;
  metadata: Metadata | null;
  sessionId: string;
  getMessageById?: (id: string) => Message | null;
}) {
  if (!props.message.tool) {
    return null;
  }
  return (
    <View style={styles.toolContainer}>
      <ToolView
        tool={props.message.tool}
        metadata={props.metadata}
        messages={props.message.children}
        sessionId={props.sessionId}
        messageId={props.message.id}
        variant="chat"
      />
    </View>
  );
}

const styles = StyleSheet.create((theme) => ({
  messageContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
  },
  messageContent: {
    flexDirection: 'column',
    flexGrow: 1,
    flexBasis: 0,
    maxWidth: layout.maxWidth,
  },
  userMessageContainer: {
    maxWidth: '100%',
    flexDirection: 'column',
    alignItems: 'flex-end',
    justifyContent: 'flex-end',
    paddingHorizontal: 12,
  },
  userMessageBubble: {
    backgroundColor: theme.colors.userMessageBackground,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 16,
    marginBottom: 8,
    maxWidth: '100%',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.divider,
  },
  agentMessageContainer: {
    marginHorizontal: 12,
    marginBottom: 8,
    borderRadius: 8,
    alignSelf: 'flex-start',
  },
  agentEventContainer: {
    marginHorizontal: 8,
    alignItems: 'center',
    paddingVertical: 8,
  },
  agentEventText: {
    color: theme.colors.agentEventText,
    fontSize: 14,
  },
  toolContainer: {
    marginHorizontal: 6,
  },
  debugText: {
    color: theme.colors.agentEventText,
    fontSize: 12,
  },
}));
