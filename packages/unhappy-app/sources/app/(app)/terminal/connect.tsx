import React, { useEffect, useState } from 'react';
import { Platform, View } from 'react-native';
import { Text } from '@/components/StyledText';
import { useRouter } from 'expo-router';
import { Typography } from '@/constants/Typography';
import { RoundButton } from '@/components/RoundButton';
import { useConnectTerminal } from '@/hooks/useConnectTerminal';
import { Ionicons } from '@/icons/vector-icons';
import { ItemList } from '@/components/ItemList';
import { t } from '@/text';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

export default function TerminalConnectScreen() {
    const router = useRouter();
    const { theme } = useUnistyles();
    const [publicKey, setPublicKey] = useState<string | null>(null);
    const [hashProcessed, setHashProcessed] = useState(false);
    const { processAuthUrl, isLoading } = useConnectTerminal({
        onSuccess: () => {
            router.back();
        }
    });

    // Extract key from hash on web platform
    useEffect(() => {
        if (Platform.OS === 'web' && typeof window !== 'undefined' && !hashProcessed) {
            const hash = window.location.hash;
            if (hash.startsWith('#key=')) {
                const key = hash.substring(5); // Remove '#key='
                setPublicKey(key);
                
                // Clear the hash from URL to prevent exposure in browser history
                window.history.replaceState(null, '', window.location.pathname + window.location.search);
                setHashProcessed(true);
            } else {
                setHashProcessed(true);
            }
        }
    }, [hashProcessed]);

    const handleConnect = async () => {
        if (publicKey) {
            // Convert the hash key format to the expected unhappy:// URL format
            const authUrl = `unhappy://terminal?${publicKey}`;
            await processAuthUrl(authUrl);
        }
    };

    const handleReject = () => {
        router.back();
    };

    const keyPreview = publicKey
        ? `${publicKey.slice(0, 16)}...${publicKey.slice(-10)}`
        : '';

    const renderFrame = (content: React.ReactNode) => (
        <ItemList>
            <View style={styles.page}>
                <View pointerEvents="none" style={[styles.ambientGlow, styles.ambientGlowTop]} />
                <View pointerEvents="none" style={[styles.ambientGlow, styles.ambientGlowBottom]} />
                <View style={[styles.card, Platform.OS === 'web' && styles.cardWeb]}>
                    {content}
                </View>
            </View>
        </ItemList>
    );

    const renderHeader = (
        iconName: React.ComponentProps<typeof Ionicons>['name'],
        iconColor: string,
        title: string,
        description: string
    ) => (
        <View style={styles.header}>
            <View style={[styles.iconBadge, { backgroundColor: theme.dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)' }]}>
                <Ionicons name={iconName} size={30} color={iconColor} />
            </View>
            <Text style={styles.title}>{title}</Text>
            <Text style={styles.description}>{description}</Text>
        </View>
    );

    if (Platform.OS !== 'web') {
        return renderFrame(
            <>
                {renderHeader(
                    'laptop-outline',
                    theme.colors.textSecondary,
                    t('terminal.webBrowserRequired'),
                    t('terminal.webBrowserRequiredDescription')
                )}
            </>
        );
    }

    if (!hashProcessed) {
        return renderFrame(
            <>
                {renderHeader(
                    'hourglass-outline',
                    theme.colors.radio.active,
                    t('terminal.connectTerminal'),
                    t('terminal.processingConnection')
                )}
            </>
        );
    }

    if (!publicKey) {
        return renderFrame(
            <>
                {renderHeader(
                    'warning-outline',
                    theme.colors.textDestructive,
                    t('terminal.invalidConnectionLink'),
                    t('terminal.invalidConnectionLinkDescription')
                )}
                <RoundButton
                    title={t('terminal.reject')}
                    onPress={handleReject}
                    size="large"
                    display="inverted"
                />
            </>
        );
    }

    return renderFrame(
        <>
            {renderHeader(
                'terminal-outline',
                theme.colors.radio.active,
                t('terminal.connectTerminal'),
                t('terminal.terminalRequestDescription')
            )}

            <View style={styles.infoSection}>
                <Text style={styles.sectionLabel}>{t('terminal.connectionDetails')}</Text>
                <View style={styles.infoRow}>
                    <Ionicons name="finger-print-outline" size={20} color={theme.colors.radio.active} />
                    <View style={styles.infoText}>
                        <Text style={styles.infoTitle}>{t('terminal.publicKey')}</Text>
                        <Text style={styles.infoValue}>{keyPreview}</Text>
                    </View>
                </View>
                <View style={styles.divider} />
                <View style={styles.infoRow}>
                    <Ionicons name="lock-closed-outline" size={20} color={theme.colors.success} />
                    <View style={styles.infoText}>
                        <Text style={styles.infoTitle}>{t('terminal.encryption')}</Text>
                        <Text style={styles.infoValue}>{t('terminal.endToEndEncrypted')}</Text>
                    </View>
                </View>
            </View>

            <View style={styles.securityNote}>
                <Ionicons name="shield-checkmark-outline" size={20} color={theme.colors.success} />
                <View style={styles.securityText}>
                    <Text style={styles.securityTitle}>{t('terminal.clientSideProcessing')}</Text>
                    <Text style={styles.securitySubtitle}>{t('terminal.linkProcessedLocally')}</Text>
                </View>
            </View>

            <View style={styles.actionGroup}>
                <RoundButton
                    title={isLoading ? t('terminal.connecting') : t('terminal.acceptConnection')}
                    onPress={handleConnect}
                    size="large"
                    disabled={isLoading}
                    loading={isLoading}
                />
                <RoundButton
                    title={t('terminal.reject')}
                    onPress={handleReject}
                    size="large"
                    display="inverted"
                    disabled={isLoading}
                />
            </View>

            <Text style={styles.footerText}>{t('terminal.securityFooter')}</Text>
        </>
    );
}

const styles = StyleSheet.create((theme) => ({
    page: {
        flex: 1,
        justifyContent: 'center',
        paddingHorizontal: 16,
        paddingVertical: 24,
    },
    ambientGlow: {
        position: 'absolute',
        width: 220,
        height: 220,
        borderRadius: 110,
        opacity: 0.35,
    },
    ambientGlowTop: {
        top: -90,
        right: -60,
        backgroundColor: theme.dark ? 'rgba(148, 163, 184, 0.12)' : 'rgba(15, 23, 42, 0.05)',
    },
    ambientGlowBottom: {
        bottom: -95,
        left: -70,
        backgroundColor: theme.dark ? 'rgba(100, 116, 139, 0.10)' : 'rgba(15, 23, 42, 0.04)',
    },
    card: {
        gap: 16,
        padding: 22,
        borderRadius: 20,
        borderWidth: 1,
        borderColor: theme.dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
        backgroundColor: theme.dark ? 'rgba(15, 18, 24, 0.90)' : 'rgba(255, 255, 255, 0.94)',
    },
    cardWeb: {
        width: '100%',
        maxWidth: 620,
        alignSelf: 'center',
    },
    header: {
        alignItems: 'center',
        gap: 10,
    },
    iconBadge: {
        width: 56,
        height: 56,
        borderRadius: 16,
        alignItems: 'center',
        justifyContent: 'center',
    },
    title: {
        ...Typography.default('semiBold'),
        fontSize: 22,
        color: theme.colors.text,
        textAlign: 'center',
    },
    description: {
        ...Typography.default(),
        fontSize: 14,
        lineHeight: 21,
        textAlign: 'center',
        color: theme.colors.textSecondary,
        maxWidth: 480,
    },
    infoSection: {
        borderRadius: 14,
        padding: 14,
        gap: 12,
        borderWidth: 1,
        borderColor: theme.dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)',
        backgroundColor: theme.dark ? 'rgba(255,255,255,0.02)' : 'rgba(0,0,0,0.015)',
    },
    sectionLabel: {
        ...Typography.default('semiBold'),
        fontSize: 13,
        letterSpacing: 0.2,
        color: theme.colors.textSecondary,
    },
    infoRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
    },
    infoText: {
        flex: 1,
        gap: 3,
    },
    infoTitle: {
        ...Typography.default(),
        fontSize: 13,
        color: theme.colors.textSecondary,
    },
    infoValue: {
        ...Typography.default('semiBold'),
        fontSize: 14,
        color: theme.colors.text,
    },
    divider: {
        height: 1,
        backgroundColor: theme.dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)',
    },
    securityNote: {
        flexDirection: 'row',
        gap: 10,
        alignItems: 'flex-start',
        padding: 14,
        borderRadius: 14,
        backgroundColor: theme.dark ? 'rgba(148,163,184,0.12)' : 'rgba(15,23,42,0.06)',
    },
    securityText: {
        flex: 1,
        gap: 2,
    },
    securityTitle: {
        ...Typography.default('semiBold'),
        fontSize: 13,
        color: theme.colors.text,
    },
    securitySubtitle: {
        ...Typography.default(),
        fontSize: 13,
        lineHeight: 18,
        color: theme.colors.textSecondary,
    },
    actionGroup: {
        gap: 10,
    },
    footerText: {
        ...Typography.default(),
        fontSize: 12,
        lineHeight: 18,
        color: theme.colors.textSecondary,
        textAlign: 'center',
    },
}));
