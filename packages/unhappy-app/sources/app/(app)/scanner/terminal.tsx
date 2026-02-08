import * as React from 'react';
import { ActivityIndicator, Linking, Platform, Pressable, View } from 'react-native';
import { CameraView, useCameraPermissions, type BarcodeScanningResult } from 'expo-camera';
import { useRouter } from 'expo-router';
import { useIsFocused } from '@react-navigation/native';
import { Text } from '@/components/StyledText';
import { useUnistyles } from 'react-native-unistyles';
import { Modal } from '@/modal';
import { t } from '@/text';
import { useConnectTerminal } from '@/hooks/useConnectTerminal';
import { getUnhappyQrDebugInfo } from '@/auth/unhappyQr';

const QR_DEBUG = !!process.env.EXPO_PUBLIC_DEBUG;
function qrDebug(message: string, details?: any) {
    if (!QR_DEBUG) return;
    if (details !== undefined) console.log(`[QR DEBUG] ${message}`, details);
    else console.log(`[QR DEBUG] ${message}`);
}

export default React.memo(function TerminalScannerScreen() {
    const { theme } = useUnistyles();
    const router = useRouter();
    const isFocused = useIsFocused();
    const { connectWithUrl, isLoading } = useConnectTerminal({
        onSuccess: () => router.back(),
    });

    const [permission, requestPermission] = useCameraPermissions();
    const [cameraEnabled, setCameraEnabled] = React.useState(true);
    const handlingRef = React.useRef(false);

    React.useEffect(() => {
        // Stop the camera when this screen isn't visible (or is being dismissed),
        // so the OS camera indicator doesn't linger.
        if (!isFocused) {
            handlingRef.current = false;
            setCameraEnabled(false);
            return;
        }
        // Reset when coming back into focus.
        handlingRef.current = false;
        setCameraEnabled(true);
    }, [isFocused]);

    React.useEffect(() => {
        if (Platform.OS === 'web') return;
        if (!permission) return;
        qrDebug('scanner/terminal permission state', { granted: permission.granted, canAskAgain: permission.canAskAgain, status: permission.status });
        if (!permission.granted && permission.canAskAgain) {
            requestPermission();
        }
    }, [permission, requestPermission]);

    const onBarcodeScanned = React.useCallback(async (result: BarcodeScanningResult) => {
        if (handlingRef.current || isLoading) return;
        handlingRef.current = true;
        setCameraEnabled(false);
        try {
            qrDebug('scanner/terminal onBarcodeScanned', getUnhappyQrDebugInfo(result.data));
            const ok = await connectWithUrl(result.data);
            qrDebug('scanner/terminal connectWithUrl result', { ok });
            if (!ok) {
                handlingRef.current = false;
                setCameraEnabled(true);
            }
        } catch (e) {
            qrDebug('scanner/terminal connectWithUrl threw', { message: (e as any)?.message });
            console.error(e);
            handlingRef.current = false;
            setCameraEnabled(true);
        }
    }, [connectWithUrl, isLoading]);

    if (Platform.OS === 'web') {
        return (
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 16 }}>
                <Text>{t('terminal.webBrowserRequiredDescription')}</Text>
            </View>
        );
    }

    if (!permission) {
        return (
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
                <ActivityIndicator />
            </View>
        );
    }

    if (!permission.granted) {
        return (
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 16 }}>
                <Text style={{ textAlign: 'center', color: theme.colors.text, marginBottom: 12 }}>
                    {t('modals.cameraPermissionsRequiredToConnectTerminal')}
                </Text>
                <Pressable
                    onPress={async () => {
                        const res = await requestPermission();
                        if (!res.granted && !res.canAskAgain) {
                            Modal.alert(t('common.error'), t('modals.cameraPermissionsRequiredToConnectTerminal'), [
                                { text: t('common.ok') },
                            ]);
                        }
                    }}
                    style={{
                        paddingHorizontal: 14,
                        paddingVertical: 10,
                        borderRadius: 10,
                        backgroundColor: theme.colors.button.primary.background,
                        marginBottom: 10,
                    }}
                >
                    <Text style={{ color: theme.colors.button.primary.tint }}>
                        {t('common.continue')}
                    </Text>
                </Pressable>
                <Pressable
                    onPress={() => Linking.openSettings()}
                    style={{ paddingHorizontal: 14, paddingVertical: 10 }}
                >
                    <Text style={{ color: theme.colors.textSecondary }}>
                        {t('common.open')}
                    </Text>
                </Pressable>
            </View>
        );
    }

    return (
        <View style={{ flex: 1, backgroundColor: 'black' }}>
            {isFocused && cameraEnabled ? (
                <CameraView
                    style={{ flex: 1 }}
                    facing="back"
                    barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
                    onBarcodeScanned={isLoading ? undefined : onBarcodeScanned}
                    active={!isLoading}
                />
            ) : (
                <View style={{ flex: 1 }} />
            )}

            <View
                pointerEvents="none"
                style={{
                    position: 'absolute',
                    left: 0,
                    right: 0,
                    top: 0,
                    paddingTop: 18,
                    paddingHorizontal: 16,
                }}
            >
                <View
                    style={{
                        alignSelf: 'center',
                        paddingHorizontal: 12,
                        paddingVertical: 8,
                        borderRadius: 12,
                        backgroundColor: 'rgba(0,0,0,0.55)',
                    }}
                >
                    <Text style={{ color: 'white' }}>
                        {t('settings.scanQrCodeToAuthenticate')}
                    </Text>
                </View>
            </View>

            {isLoading && (
                <View
                    style={{
                        position: 'absolute',
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        alignItems: 'center',
                        justifyContent: 'center',
                        backgroundColor: 'rgba(0,0,0,0.45)',
                    }}
                >
                    <ActivityIndicator color="white" />
                    <View style={{ height: 10 }} />
                    <Text style={{ color: 'white' }}>{t('terminal.processingConnection')}</Text>
                </View>
            )}
        </View>
    );
});
