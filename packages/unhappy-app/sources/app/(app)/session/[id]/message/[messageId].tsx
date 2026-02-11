import * as React from 'react';
import { useLocalSearchParams, Stack, useRouter } from "expo-router";
import { Text, View, ActivityIndicator, ScrollView, Platform } from "react-native";
import { useMessage, useSession, useSessionMessages } from "@/sync/storage";
import { sync } from '@/sync/sync';
import { Deferred } from "@/components/Deferred";
import { ToolFullView } from '@/components/tools/ToolFullView';
import { ToolHeader } from '@/components/tools/ToolHeader';
import { ToolStatusIndicator } from '@/components/tools/ToolStatusIndicator';
import { MarkdownView } from '@/components/markdown/MarkdownView';
import { Ionicons } from '@/icons/vector-icons';
import { Message } from '@/sync/typesMessage';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Typography } from '@/constants/Typography';
import { layout } from '@/components/layout';

const stylesheet = StyleSheet.create((theme) => ({
    loadingContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
    },
    scrollContainer: {
        flex: 1,
        backgroundColor: theme.colors.surface,
    },
    scrollContent: {
        flexGrow: 1,
        paddingBottom: 48,
    },
    detailWrapper: {
        maxWidth: layout.maxWidth,
        alignSelf: 'center',
        width: '100%',
        paddingHorizontal: Platform.select({ web: 24, default: 20 }),
        paddingTop: 24,
    },
    metaRow: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        marginBottom: 20,
    },
    typeBadge: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
        paddingHorizontal: 10,
        paddingVertical: 5,
        borderRadius: 20,
    },
    typeBadgeText: {
        fontSize: 13,
        fontWeight: '600',
        ...Typography.default('semiBold'),
    },
    timestamp: {
        fontSize: 13,
        color: theme.colors.textSecondary,
        ...Typography.default(),
    },
    userBubble: {
        backgroundColor: theme.colors.userMessageBackground,
        borderRadius: 16,
        paddingHorizontal: 16,
        paddingVertical: 12,
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: theme.colors.divider,
    },
    agentContent: {
        paddingHorizontal: 0,
    },
    eventContainer: {
        alignItems: 'center',
        paddingVertical: 40,
        gap: 12,
    },
    eventIconWrapper: {
        width: 56,
        height: 56,
        borderRadius: 28,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.dark ? 'rgba(157,157,157,0.08)' : 'rgba(142,142,147,0.08)',
    },
    eventText: {
        fontSize: 15,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        lineHeight: 22,
        ...Typography.default(),
    },
}));

export default React.memo(() => {
    const { id: sessionId, messageId } = useLocalSearchParams<{ id: string; messageId: string }>();
    const router = useRouter();
    const session = useSession(sessionId!);
    const { isLoaded: messagesLoaded } = useSessionMessages(sessionId!);
    const message = useMessage(sessionId!, messageId!);
    const { theme } = useUnistyles();

    // Trigger session visibility when component mounts
    React.useEffect(() => {
        if (sessionId) {
            sync.onSessionVisible(sessionId);
        }
    }, [sessionId]);

    // Navigate back if message doesn't exist after messages are loaded
    React.useEffect(() => {
        if (messagesLoaded && !message) {
            router.back();
        }
    }, [messagesLoaded, message, router]);

    // Show loader while waiting for session and messages to load
    if (!session || !messagesLoaded) {
        return (
            <View style={stylesheet.loadingContainer}>
                <ActivityIndicator size="small" color={theme.colors.textSecondary} />
            </View>
        );
    }

    // If messages are loaded but specific message not found, show loader briefly
    // The useEffect above will navigate back
    if (!message) {
        return (
            <View style={stylesheet.loadingContainer}>
                <ActivityIndicator size="small" color={theme.colors.textSecondary} />
            </View>
        );
    }

    return (
        <>
            {message.kind === 'tool-call' && message.tool && (
                <Stack.Screen
                    options={{
                        headerTitle: () => <ToolHeader tool={message.tool} />,
                        headerRight: () => <ToolStatusIndicator tool={message.tool} />,
                        headerStyle: {
                            backgroundColor: theme.colors.header.background,
                        },
                        headerTintColor: theme.colors.header.tint,
                        headerShadowVisible: false,
                    }}
                />
            )}
            {(message.kind === 'user-text' || message.kind === 'agent-text') && (
                <Stack.Screen
                    options={{
                        title: message.kind === 'user-text' ? 'Message' : 'Response',
                        headerStyle: {
                            backgroundColor: theme.colors.header.background,
                        },
                        headerTintColor: theme.colors.header.tint,
                        headerShadowVisible: false,
                    }}
                />
            )}
            <Deferred>
                <FullView message={message} />
            </Deferred>
        </>
    );
});

function FullView(props: { message: Message }) {
    const { theme } = useUnistyles();

    if (props.message.kind === 'tool-call') {
        return <ToolFullView tool={props.message.tool} messages={props.message.children} />;
    }

    if (props.message.kind === 'agent-event') {
        return (
            <ScrollView
                style={stylesheet.scrollContainer}
                contentContainerStyle={stylesheet.scrollContent}
            >
                <View style={stylesheet.detailWrapper}>
                    <View style={stylesheet.eventContainer}>
                        <View style={stylesheet.eventIconWrapper}>
                            <Ionicons name="information-circle-outline" size={28} color={theme.colors.textSecondary} />
                        </View>
                        <Text style={stylesheet.eventText}>
                            {props.message.event.type === 'message'
                                ? props.message.event.message
                                : props.message.event.type}
                        </Text>
                    </View>
                </View>
            </ScrollView>
        );
    }

    const isUser = props.message.kind === 'user-text';
    const text = props.message.kind === 'user-text'
        ? (props.message.displayText || props.message.text)
        : props.message.text;
    const createdAt = props.message.createdAt;

    const formattedTime = React.useMemo(() => {
        const date = new Date(createdAt);
        return date.toLocaleString([], {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
        });
    }, [createdAt]);

    return (
        <ScrollView
            style={stylesheet.scrollContainer}
            contentContainerStyle={stylesheet.scrollContent}
        >
            <View style={stylesheet.detailWrapper}>
                {/* Meta row: type badge + timestamp */}
                <View style={stylesheet.metaRow}>
                    <View style={[
                        stylesheet.typeBadge,
                        {
                            backgroundColor: isUser
                                ? (theme.dark ? 'rgba(0,122,255,0.12)' : 'rgba(0,122,255,0.08)')
                                : (theme.dark ? 'rgba(52,199,89,0.12)' : 'rgba(52,199,89,0.08)')
                        }
                    ]}>
                        <Ionicons
                            name={isUser ? 'person' : 'sparkles'}
                            size={13}
                            color={isUser ? theme.colors.chrome.accent : theme.colors.success}
                        />
                        <Text style={[
                            stylesheet.typeBadgeText,
                            { color: isUser ? theme.colors.chrome.accent : theme.colors.success }
                        ]}>
                            {isUser ? 'You' : 'Assistant'}
                        </Text>
                    </View>
                    <Text style={stylesheet.timestamp}>{formattedTime}</Text>
                </View>

                {/* Message content */}
                {isUser ? (
                    <View style={stylesheet.userBubble}>
                        <MarkdownView markdown={text} />
                    </View>
                ) : (
                    <View style={stylesheet.agentContent}>
                        <MarkdownView markdown={text} />
                    </View>
                )}
            </View>
        </ScrollView>
    );
}
