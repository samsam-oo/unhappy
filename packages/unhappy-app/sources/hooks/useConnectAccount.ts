import * as React from 'react';
import { Platform } from 'react-native';
import { CameraView } from 'expo-camera';
import { useRouter } from 'expo-router';
import { useAuth } from '@/auth/AuthContext';
import { decodeBase64 } from '@/encryption/base64';
import { encryptBox } from '@/encryption/libsodium';
import { authAccountApprove } from '@/auth/authAccountApprove';
import { useCheckScannerPermissions } from '@/hooks/useCheckCameraPermissions';
import { Modal } from '@/modal';
import { t } from '@/text';
import { parseUnhappyQrData } from '@/auth/unhappyQr';

interface UseConnectAccountOptions {
    onSuccess?: () => void;
    onError?: (error: any) => void;
}

export function useConnectAccount(options?: UseConnectAccountOptions) {
    const auth = useAuth();
    const router = useRouter();
    const [isLoading, setIsLoading] = React.useState(false);
    const checkScannerPermissions = useCheckScannerPermissions();
    const modernSubscriptionRef = React.useRef<{ remove: () => void } | null>(null);
    const modernHandlingRef = React.useRef(false);

    const cleanupModernSubscription = React.useCallback(() => {
        try {
            modernSubscriptionRef.current?.remove();
        } finally {
            modernSubscriptionRef.current = null;
        }
    }, []);

    const processAuthUrl = React.useCallback(async (url: string) => {
        const parsed = parseUnhappyQrData(url);
        if (!parsed || parsed.kind !== 'account') {
            Modal.alert(t('common.error'), t('modals.invalidAuthUrl'), [{ text: t('common.ok') }]);
            return false;
        }
        
        setIsLoading(true);
        try {
            const publicKey = decodeBase64(parsed.publicKeyBase64Url, 'base64url');
            const response = encryptBox(decodeBase64(auth.credentials!.secret, 'base64url'), publicKey);
            await authAccountApprove(auth.credentials!.token, publicKey, response);
            
            Modal.alert(t('common.success'), t('modals.deviceLinkedSuccessfully'), [
                { 
                    text: t('common.ok'), 
                    onPress: () => options?.onSuccess?.()
                }
            ]);
            return true;
        } catch (e) {
            console.error(e);
            Modal.alert(t('common.error'), t('modals.failedToLinkDevice'), [{ text: t('common.ok') }]);
            options?.onError?.(e);
            return false;
        } finally {
            setIsLoading(false);
        }
    }, [auth.credentials, options]);

    const connectAccount = React.useCallback(async () => {
        // iOS "modern scanner" (DataScannerViewController) doesn't provide a reliable JS signal for
        // user-cancel/dismiss, and can leave the OS camera indicator stuck on some devices.
        // Prefer the in-app CameraView-based scanner on iOS for predictable teardown.
        const canUseModernScanner = Platform.OS === 'android' && CameraView.isModernBarcodeScannerAvailable;
        const needsCameraPermission = Platform.OS === 'ios' || !canUseModernScanner;

        if (await checkScannerPermissions(needsCameraPermission)) {
            if (canUseModernScanner) {
                try {
                    // Scope the modern scanner subscription to the duration of the scanner session.
                    cleanupModernSubscription();
                    modernHandlingRef.current = false;
                    modernSubscriptionRef.current = CameraView.onModernBarcodeScanned(async (event) => {
                        if (modernHandlingRef.current) return;
                        const parsed = parseUnhappyQrData(event.data);
                        if (parsed?.kind !== 'account') return;

                        modernHandlingRef.current = true;
                        cleanupModernSubscription();
                        // Dismiss scanner on Android is called automatically when barcode is scanned
                        if (Platform.OS === 'ios') {
                            try {
                                await CameraView.dismissScanner();
                            } catch {
                                // Ignore
                            }
                        }
                        await processAuthUrl(event.data);
                    });

                    await CameraView.launchScanner({ barcodeTypes: ['qr'] });
                } catch (e) {
                    console.error(e);
                    // Ensure we don't keep a stale subscription around if launching fails.
                    cleanupModernSubscription();
                    // Fall back to in-app camera view scanner.
                    router.push('/scanner/account');
                } finally {
                    /**
                     * expo-camera behavior differs by platform:
                     * - Android: `launchScanner()` resolves/rejects when the scan completes/cancels.
                     * - iOS: `launchScanner()` resolves immediately after presenting the scanner UI.
                     *
                     * If we clean up the subscription immediately on iOS, we will miss scan events.
                     * We instead clean up on:
                     * - successful scan (in the event handler above)
                     * - hook unmount (effect below)
                     * - next scan attempt (cleanup at the top of this block)
                     */
                    if (Platform.OS !== 'ios') {
                        cleanupModernSubscription();
                    }
                }
            } else {
                // iOS < 16 (or devices without modern scanner) need an in-app scanner UI.
                router.push('/scanner/account');
            }
        } else {
            Modal.alert(t('common.error'), t('modals.cameraPermissionsRequiredToScanQr'), [{ text: t('common.ok') }]);
        }
    }, [checkScannerPermissions, cleanupModernSubscription, processAuthUrl, router]);

    const connectWithUrl = React.useCallback(async (url: string) => {
        return await processAuthUrl(url);
    }, [processAuthUrl]);

    React.useEffect(() => {
        // Ensure subscription is cleaned up if the hook unmounts mid-scan.
        return () => cleanupModernSubscription();
    }, [cleanupModernSubscription]);

    return {
        connectAccount,
        connectWithUrl,
        isLoading,
        processAuthUrl
    };
}
