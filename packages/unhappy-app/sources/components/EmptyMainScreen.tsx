import React from 'react';
import { View, Text, Platform } from 'react-native';
import { Typography } from '@/constants/Typography';
import { RoundButton } from '@/components/RoundButton';
import { useConnectTerminal } from '@/hooks/useConnectTerminal';
import { Modal } from '@/modal';
import { t } from '@/text';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        marginBottom: Platform.select({ web: 16, default: 32 }),
    },
    title: {
        marginBottom: Platform.select({ web: 10, default: 16 }),
        textAlign: 'center',
        fontSize: Platform.select({ web: 18, default: 24 }),
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    terminalBlock: {
        backgroundColor: theme.colors.surfaceHighest,
        borderRadius: 8,
        padding: Platform.select({ web: 14, default: 20 }),
        marginHorizontal: Platform.select({ web: 12, default: 24 }),
        marginBottom: Platform.select({ web: 12, default: 20 }),
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    terminalText: {
        ...Typography.mono(),
        fontSize: Platform.select({ web: 13, default: 16 }),
        color: theme.colors.status.connected,
    },
    terminalTextFirst: {
        marginBottom: 8,
    },
    stepsContainer: {
        marginTop: Platform.select({ web: 10, default: 12 }),
        marginHorizontal: Platform.select({ web: 12, default: 24 }),
        marginBottom: Platform.select({ web: 20, default: 48 }),
        width: 250,
    },
    stepRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 8,
    },
    stepRowLast: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    stepNumber: {
        width: 24,
        height: 24,
        borderRadius: 12,
        backgroundColor: theme.colors.surfaceHigh,
        alignItems: 'center',
        justifyContent: 'center',
        marginRight: 12,
    },
    stepNumberText: {
        ...Typography.default('semiBold'),
        fontSize: 14,
        color: theme.colors.text,
    },
    stepText: {
        ...Typography.default(),
        fontSize: Platform.select({ web: 14, default: 18 }),
        color: theme.colors.textSecondary,
    },
    buttonsContainer: {
        alignItems: 'center',
        width: '100%',
    },
    buttonWrapper: {
        width: 240,
        marginBottom: 12,
    },
    buttonWrapperSecondary: {
        width: 240,
    },
}));

export function EmptyMainScreen() {
    const { connectTerminal, connectWithUrl, isLoading } = useConnectTerminal();
    const { theme } = useUnistyles();
    const styles = stylesheet;

    return (
        <View style={styles.container}>
            {/* Terminal-style code block */}
            <Text style={styles.title}>{t('components.emptyMainScreen.readyToCode')}</Text>
            <View style={styles.terminalBlock}>
                <Text style={[styles.terminalText, styles.terminalTextFirst]}>
                    $ npm i -g unhappy-cli
                </Text>
                <Text style={styles.terminalText}>
                    $ unhappy
                </Text>
            </View>


            {Platform.OS !== 'web' && (
                <>
                    <View style={styles.stepsContainer}>
                        <View style={styles.stepRow}>
                            <View style={styles.stepNumber}>
                                <Text style={styles.stepNumberText}>1</Text>
                            </View>
                            <Text style={styles.stepText}>
                                {t('components.emptyMainScreen.installCli')}
                            </Text>
                        </View>
                        <View style={styles.stepRow}>
                            <View style={styles.stepNumber}>
                                <Text style={styles.stepNumberText}>2</Text>
                            </View>
                            <Text style={styles.stepText}>
                                {t('components.emptyMainScreen.runIt')}
                            </Text>
                        </View>
                        <View style={styles.stepRowLast}>
                            <View style={styles.stepNumber}>
                                <Text style={styles.stepNumberText}>3</Text>
                            </View>
                            <Text style={styles.stepText}>
                                {t('components.emptyMainScreen.scanQrCode')}
                            </Text>
                        </View>
                    </View>
                    <View style={styles.buttonsContainer}>
                        <View style={styles.buttonWrapper}>
                            <RoundButton
                                title={t('components.emptyMainScreen.openCamera')}
                                size="large"
                                loading={isLoading}
                                onPress={connectTerminal}
                            />
                        </View>
                        <View style={styles.buttonWrapperSecondary}>
                            <RoundButton
                                title={t('connect.enterUrlManually')}
                                size="normal"
                                display="inverted"
                                onPress={async () => {
                                    const url = await Modal.prompt(
                                        t('modals.authenticateTerminal'),
                                        t('modals.pasteUrlFromTerminal'),
                                        {
                                            placeholder: 'unhappy://terminal?...',
                                            cancelText: t('common.cancel'),
                                            confirmText: t('common.authenticate')
                                        }
                                    );

                                    if (url?.trim()) {
                                        connectWithUrl(url.trim());
                                    }
                                }}
                            />
                        </View>
                    </View>
                </>
            )}
        </View>
    );
}
