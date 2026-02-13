import React from 'react';
import { View, Text, Platform, Image } from 'react-native';
import { Typography } from '@/constants/Typography';
import { Session } from '@/sync/storageTypes';
import { useSessionStatus, formatPathRelativeToProjectBase } from '@/utils/sessionUtils';
import { StyleSheet } from 'react-native-unistyles';
import { t } from '@/text';

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        paddingHorizontal: Platform.select({ web: 16, default: 24 }),
    },
    iconContainer: {
        marginBottom: 10,
        width: 168,
        height: 52,
    },
    hostText: {
        fontSize: 16,
        color: theme.colors.text,
        textAlign: 'center',
        marginBottom: 4,
        ...Typography.default('semiBold'),
    },
    pathText: {
        fontSize: 13,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        marginBottom: 24,
        ...Typography.default('regular'),
    },
    noMessagesText: {
        fontSize: 16,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        marginBottom: 8,
        ...Typography.default('regular'),
    },
    createdText: {
        fontSize: 13,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        lineHeight: 18,
        ...Typography.default(),
    },
}));

interface EmptyMessagesProps {
    session: Session;
}

function formatRelativeTime(timestamp: number): string {
    const now = Date.now();
    const diffMs = now - timestamp;
    const diffMinutes = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);
    
    if (diffMinutes < 1) {
        return t('time.justNow');
    } else if (diffMinutes < 60) {
        return t('time.minutesAgo', { count: diffMinutes });
    } else if (diffHours < 24) {
        return t('time.hoursAgo', { count: diffHours });
    } else {
        return t('sessionHistory.daysAgo', { count: diffDays });
    }
}

export function EmptyMessages({ session }: EmptyMessagesProps) {
    const styles = stylesheet;
    const sessionStatus = useSessionStatus(session);
    const startedTime = formatRelativeTime(session.createdAt);
    
    return (
        <View style={styles.container}>
            <Image
                source={require('@/assets/images/logotype.png')}
                style={styles.iconContainer}
                resizeMode="contain"
            />
            
            {session.metadata?.host && (
                <Text style={styles.hostText}>
                    {session.metadata.host}
                </Text>
            )}
            
            {session.metadata?.path && (
                <Text style={styles.pathText}>
                    {formatPathRelativeToProjectBase(session.metadata.path, session.metadata.machineId, session.metadata.homeDir)}
                </Text>
            )}
            
            <Text style={styles.noMessagesText}>
                No messages yet
            </Text>
            
            <Text style={styles.createdText}>
                Created {startedTime}
            </Text>
        </View>
    );
}
