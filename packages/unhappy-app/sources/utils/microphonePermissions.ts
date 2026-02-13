import { Platform, Linking } from 'react-native';
import { Modal } from '@/modal';
import { AudioModule } from 'expo-audio';

export interface MicrophonePermissionResult {
  granted: boolean;
  canAskAgain?: boolean;
}

/**
 * CRITICAL: Request microphone permissions BEFORE starting any audio session
 * Without this, first voice session WILL fail on iOS/Android
 *
 * Uses expo-audio (SDK 52+) - expo-av is deprecated
 */
export async function requestMicrophonePermission(): Promise<MicrophonePermissionResult> {
  try {
    if (Platform.OS === 'web') {
      // Web: Use navigator.mediaDevices API
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        // Important: Stop the stream immediately after getting permission
        stream.getTracks().forEach(track => track.stop());
        return { granted: true };
      } catch (error: any) {
        // User denied permission or browser doesn't support getUserMedia
        console.error('Web microphone permission denied:', error);
        return { granted: false, canAskAgain: error.name !== 'NotAllowedError' };
      }
    } else {
      // iOS and Android: Use expo-audio (SDK 52+)
      const result = await AudioModule.requestRecordingPermissionsAsync();

      if (result.granted) {
        // Configure audio mode for recording
        await AudioModule.setAudioModeAsync({
          allowsRecording: true,
          playsInSilentMode: true,
        });

        return { granted: true, canAskAgain: result.canAskAgain };
      }

      return { granted: false, canAskAgain: result.canAskAgain };
    }
  } catch (error) {
    console.error('Error requesting microphone permission:', error);
    return { granted: false };
  }
}

/**
 * Check current microphone permission status without prompting
 */
export async function checkMicrophonePermission(): Promise<MicrophonePermissionResult> {
  try {
    if (Platform.OS === 'web') {
      // Web: Check permission status if available
      if ('permissions' in navigator && 'query' in navigator.permissions) {
        try {
          const result = await navigator.permissions.query({ name: 'microphone' as PermissionName });
          return { granted: result.state === 'granted' };
        } catch {
          // Permission API not supported or microphone permission not queryable
          // We'll have to request to know
          return { granted: false, canAskAgain: true };
        }
      }
      return { granted: false, canAskAgain: true };
    } else {
      // iOS and Android: Use expo-audio (SDK 52+)
      const result = await AudioModule.getRecordingPermissionsAsync();
      return { granted: result.granted, canAskAgain: result.canAskAgain };
    }
  } catch (error) {
    console.error('Error checking microphone permission:', error);
    return { granted: false };
  }
}

/**
 * Show appropriate error message when permission is denied
 */
export function showMicrophonePermissionDeniedAlert(canAskAgain: boolean = false) {
  const title = '마이크 접근 권한 필요';
  const message = canAskAgain
    ? '음성 채팅을 사용하려면 마이크 접근 권한이 필요합니다. 권한 요청이 뜰 때 허용해 주세요.'
    : '음성 채팅을 사용하려면 마이크 접근 권한이 필요합니다. 기기 설정에서 마이크 권한을 활성화해 주세요.';

  if (Platform.OS === 'web') {
    // Web: Show browser-specific instructions
    Modal.alert(
      title,
      '브라우저 설정에서 이 사이트의 마이크 사용 권한을 허용해 주세요. 주소창의 잠금 아이콘을 클릭한 뒤 마이크 권한을 켜야 할 수 있습니다.',
      [{ text: '확인' }]
    );
  } else {
    Modal.alert(title, message, [
      { text: '취소', style: 'cancel' },
      {
        text: '설정 열기',
        onPress: () => {
          // Opens app settings on iOS/Android
          Linking.openSettings();
        }
      }
    ]);
  }
}
