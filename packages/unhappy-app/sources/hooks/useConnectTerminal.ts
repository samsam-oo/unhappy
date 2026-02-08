import * as React from 'react';
import { Platform } from 'react-native';
import { CameraView } from 'expo-camera';
import { useRouter } from 'expo-router';
import { useAuth } from '@/auth/AuthContext';
import { decodeBase64 } from '@/encryption/base64';
import { encryptBox } from '@/encryption/libsodium';
import { authApprove } from '@/auth/authApprove';
import { useCheckScannerPermissions } from '@/hooks/useCheckCameraPermissions';
import { Modal } from '@/modal';
import { t } from '@/text';
import { sync } from '@/sync/sync';
import { getUnhappyQrDebugInfo, parseUnhappyQrData } from '@/auth/unhappyQr';

const QR_DEBUG = !!process.env.EXPO_PUBLIC_DEBUG;
function qrDebug(message: string, details?: any) {
    if (!QR_DEBUG) return;
    if (details !== undefined) console.log(`[QR DEBUG] ${message}`, details);
    else console.log(`[QR DEBUG] ${message}`);
}

interface UseConnectTerminalOptions {
    onSuccess?: () => void;
    onError?: (error: any) => void;
}

export function useConnectTerminal(options?: UseConnectTerminalOptions) {
    const auth = useAuth();
    const router = useRouter();
    const [isLoading, setIsLoading] = React.useState(false);
    const checkScannerPermissions = useCheckScannerPermissions();

    const processAuthUrl = React.useCallback(async (url: string) => {
        qrDebug('processAuthUrl() called', getUnhappyQrDebugInfo(url));
        const parsed = parseUnhappyQrData(url);
        if (!parsed || parsed.kind !== 'terminal') {
            qrDebug('processAuthUrl() rejected: not a terminal QR', { parsedKind: parsed?.kind ?? null });
            Modal.alert(t('common.error'), t('modals.invalidAuthUrl'), [{ text: t('common.ok') }]);
            return false;
        }
        
        setIsLoading(true);
        try {
            qrDebug('processAuthUrl() accepted', { kind: parsed.kind, publicKeyLen: parsed.publicKeyBase64Url.length });
            const publicKey = decodeBase64(parsed.publicKeyBase64Url, 'base64url');
            const responseV1 = encryptBox(decodeBase64(auth.credentials!.secret, 'base64url'), publicKey);
            let responseV2Bundle = new Uint8Array(sync.encryption.contentDataKey.length + 1);
            responseV2Bundle[0] = 0;
            responseV2Bundle.set(sync.encryption.contentDataKey, 1);
            const responseV2 = encryptBox(responseV2Bundle, publicKey);
            await authApprove(auth.credentials!.token, publicKey, responseV1, responseV2);
            
            qrDebug('processAuthUrl() authApprove() success');
            Modal.alert(t('common.success'), t('modals.terminalConnectedSuccessfully'), [
                { 
                    text: t('common.ok'), 
                    onPress: () => options?.onSuccess?.()
                }
            ]);
            return true;
        } catch (e) {
            qrDebug('processAuthUrl() failed', { message: (e as any)?.message });
            console.error(e);
            Modal.alert(t('common.error'), t('modals.failedToConnectTerminal'), [{ text: t('common.ok') }]);
            options?.onError?.(e);
            return false;
        } finally {
            setIsLoading(false);
        }
    }, [auth.credentials, options]);

    const connectTerminal = React.useCallback(async () => {
        const canUseModernScanner = Platform.OS !== 'web' && CameraView.isModernBarcodeScannerAvailable;
        const needsCameraPermission = Platform.OS === 'ios' || !canUseModernScanner;

        qrDebug('connectTerminal() start', { platform: Platform.OS, canUseModernScanner, needsCameraPermission });
        if (await checkScannerPermissions(needsCameraPermission)) {
            qrDebug('connectTerminal() permissions OK');
            if (canUseModernScanner) {
                try {
                    await CameraView.launchScanner({ barcodeTypes: ['qr'] });
                    qrDebug('connectTerminal() launchScanner() resolved');
                } catch (e) {
                    qrDebug('connectTerminal() launchScanner() threw, falling back', { message: (e as any)?.message });
                    console.error(e);
                    router.push('/scanner/terminal');
                }
            } else {
                qrDebug('connectTerminal() modern scanner unavailable, routing to in-app scanner');
                router.push('/scanner/terminal');
            }
        } else {
            qrDebug('connectTerminal() permissions denied/unavailable');
            Modal.alert(t('common.error'), t('modals.cameraPermissionsRequiredToConnectTerminal'), [{ text: t('common.ok') }]);
        }
    }, [checkScannerPermissions, router]);

    const connectWithUrl = React.useCallback(async (url: string) => {
        qrDebug('connectWithUrl() called', getUnhappyQrDebugInfo(url));
        return await processAuthUrl(url);
    }, [processAuthUrl]);

    // Set up barcode scanner listener
    React.useEffect(() => {
        qrDebug('onModernBarcodeScanned effect setup', { modernAvailable: CameraView.isModernBarcodeScannerAvailable });
        if (CameraView.isModernBarcodeScannerAvailable) {
            const subscription = CameraView.onModernBarcodeScanned(async (event) => {
                qrDebug('onModernBarcodeScanned event', getUnhappyQrDebugInfo(event.data));
                const parsed = parseUnhappyQrData(event.data);
                if (parsed?.kind === 'terminal') {
                    qrDebug('onModernBarcodeScanned accepted terminal QR');
                    // Dismiss scanner on Android is called automatically when barcode is scanned
                    if (Platform.OS === 'ios') {
                        await CameraView.dismissScanner();
                    }
                    await processAuthUrl(event.data);
                } else {
                    qrDebug('onModernBarcodeScanned ignored', { parsedKind: parsed?.kind ?? null });
                }
            });
            return () => {
                qrDebug('onModernBarcodeScanned effect cleanup');
                subscription.remove();
            };
        }
    }, [processAuthUrl]);

    return {
        connectTerminal,
        connectWithUrl,
        isLoading,
        processAuthUrl
    };
}
