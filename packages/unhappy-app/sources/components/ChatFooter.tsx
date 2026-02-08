import * as React from 'react';
import { View, Text, ViewStyle, TextStyle } from 'react-native';
import { Typography } from '@/constants/Typography';
import { Ionicons } from '@/icons/vector-icons';
import { useUnistyles } from 'react-native-unistyles';
import { useSession, useSessionMessages } from '@/sync/storage';
import { PermissionFooter } from '@/components/tools/PermissionFooter';

interface ChatFooterProps {
    sessionId: string;
}

export const ChatFooter = React.memo((props: ChatFooterProps) => {
    const { theme } = useUnistyles();
    const session = useSession(props.sessionId);
    const { messages } = useSessionMessages(props.sessionId);
    const controlledByUser = session?.agentState?.controlledByUser === true;
    const pendingRequests = session?.agentState?.requests
        ? Object.entries(session.agentState.requests)
        : [];
    const hasVisiblePendingPermission =
        messages.some(
            (m) => m.kind === 'tool-call' && m.tool.permission?.status === 'pending'
        );
    const visiblePendingCount =
        messages.filter(
            (m) => m.kind === 'tool-call' && m.tool.permission?.status === 'pending'
        ).length;

    const containerStyle: ViewStyle = {
        alignItems: 'center',
        paddingTop: 4,
        paddingBottom: 2,
    };
    const warningContainerStyle: ViewStyle = {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 12,
        paddingVertical: 4,
        backgroundColor: theme.colors.box.warning.background,
        borderRadius: 8,
        marginHorizontal: 16,
        marginTop: 4,
    };
    const warningTextStyle: TextStyle = {
        fontSize: 12,
        color: theme.colors.box.warning.text,
        marginLeft: 6,
        ...Typography.default()
    };
    return (
        <View style={containerStyle}>
            {controlledByUser && (
                <View style={warningContainerStyle}>
                    <Ionicons 
                        name="information-circle" 
                        size={16} 
                        color={theme.colors.box.warning.text}
                    />
                    <Text style={warningTextStyle}>
                        Permissions shown in terminal only. Reset or send a message to control from app.
                    </Text>
                </View>
            )}

            {/* Fallback: if we have pending permission requests but no tool card is showing the permission footer,
                surface the first request here so the user can unblock "infinite loading" tools. */}
            {!controlledByUser && pendingRequests.length > 0 && session ? (
                <>
                    {/* If multiple commands are waiting for approval, pin them here so they don't "disappear" off-screen. */}
                    {(!hasVisiblePendingPermission || visiblePendingCount < pendingRequests.length) ? (
                        <>
                            {pendingRequests.map(([id, req]) => (
                                <PermissionFooter
                                    key={id}
                                    permission={{ id, status: 'pending' }}
                                    sessionId={props.sessionId}
                                    toolName={req.tool}
                                    toolInput={req.arguments}
                                    metadata={session.metadata}
                                />
                            ))}
                        </>
                    ) : null}
                </>
            ) : null}
        </View>
    );
});
