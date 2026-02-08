import * as React from 'react';
import { ActivityIndicator, Linking, Platform, Pressable, View } from 'react-native';
import { CameraView, useCameraPermissions, type BarcodeScanningResult } from 'expo-camera';
import { useRouter } from 'expo-router';
import { Text } from '@/components/StyledText';
import { useUnistyles } from 'react-native-unistyles';
import { Modal } from '@/modal';
import { t } from '@/text';
import { useConnectAccount } from '@/hooks/useConnectAccount';

export default React.memo(function AccountScannerScreen() {
    const { theme } = useUnistyles();
    const router = useRouter();
    const { connectWithUrl, isLoading } = useConnectAccount({
        onSuccess: () => router.back(),
    });

    const [permission, requestPermission] = useCameraPermissions();
    const handlingRef = React.useRef(false);

    React.useEffect(() => {
        if (Platform.OS === 'web') return;
        if (!permission) return;
        if (!permission.granted && permission.canAskAgain) {
            requestPermission();
        }
    }, [permission, requestPermission]);

    const onBarcodeScanned = React.useCallback(async (result: BarcodeScanningResult) => {
        if (handlingRef.current || isLoading) return;
        handlingRef.current = true;
        try {
            const ok = await connectWithUrl(result.data);
            if (!ok) handlingRef.current = false;
        } catch (e) {
            console.error(e);
            handlingRef.current = false;
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
                    {t('modals.cameraPermissionsRequiredToScanQr')}
                </Text>
                <Pressable
                    onPress={async () => {
                        const res = await requestPermission();
                        if (!res.granted && !res.canAskAgain) {
                            Modal.alert(t('common.error'), t('modals.cameraPermissionsRequiredToScanQr'), [
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
            <CameraView
                style={{ flex: 1 }}
                facing="back"
                barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
                onBarcodeScanned={isLoading ? undefined : onBarcodeScanned}
            />

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
                        {t('settingsAccount.linkNewDeviceSubtitle')}
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
