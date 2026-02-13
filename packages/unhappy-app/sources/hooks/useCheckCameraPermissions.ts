import { useCameraPermissions } from "expo-camera";

export function useCheckScannerPermissions(): (needsCameraPermission?: boolean) => Promise<boolean> {
    const [cameraPermission, requestCameraPermission] = useCameraPermissions();

    return async (needsCameraPermission = true) => {
        if (!needsCameraPermission) return true;

        if (!cameraPermission) {
            // Permission state is still loading; request to unblock first scan attempt.
            if (process.env.EXPO_PUBLIC_DEBUG) console.log('[QR DEBUG] camera permission state not ready; requesting');
            const reqRes = await requestCameraPermission();
            if (process.env.EXPO_PUBLIC_DEBUG) console.log('[QR DEBUG] camera permission request result', { granted: reqRes.granted, canAskAgain: reqRes.canAskAgain, status: reqRes.status });
            return reqRes.granted;
        }

        if (!cameraPermission.granted) {
            if (process.env.EXPO_PUBLIC_DEBUG) console.log('[QR DEBUG] camera permission not granted; requesting', { canAskAgain: cameraPermission.canAskAgain, status: cameraPermission.status });
            const reqRes = await requestCameraPermission();
            if (process.env.EXPO_PUBLIC_DEBUG) console.log('[QR DEBUG] camera permission request result', { granted: reqRes.granted, canAskAgain: reqRes.canAskAgain, status: reqRes.status });
            return reqRes.granted;
        }

        if (process.env.EXPO_PUBLIC_DEBUG) console.log('[QR DEBUG] camera permission already granted');
        return true;
    }
}
