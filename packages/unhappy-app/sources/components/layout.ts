import { Dimensions, Platform } from 'react-native';
import { getDeviceType } from '@/utils/responsive';
import { isRunningOnMac } from '@/utils/platform';

// Calculate max width based on device type
function getMaxWidth(): number {
    const deviceType = getDeviceType();
    
    // For phones, use the max dimension (width or height)
    if (deviceType === 'phone' && Platform.OS !== 'web') {
        const { width, height } = Dimensions.get('window');
        return Math.max(width, height);
    }

    if (isRunningOnMac()) {
        return Number.POSITIVE_INFINITY;
    }

    // Web: avoid the "stretched mobile UI" feeling by allowing a bit more width on large screens,
    // but keep line-length reasonable for chat.
    if (Platform.OS === 'web') {
        const { width } = Dimensions.get('window');
        if (width >= 1440) return 1100;
        if (width >= 1024) return 960;
        return 800;
    }
    
    // Tablets: keep content reasonably narrow for readability.
    return 800;
}

// Calculate max width based on device type
function getMaxLayoutWidth(): number {
    const deviceType = getDeviceType();
    
    // For phones, use the max dimension (width or height)
    if (deviceType === 'phone' && Platform.OS !== 'web') {
        const { width, height } = Dimensions.get('window');
        return Math.max(width, height);
    }

    if (isRunningOnMac()) {
        return 1400;
    }

    if (Platform.OS === 'web') {
        const { width } = Dimensions.get('window');
        if (width >= 1440) return 1100;
        if (width >= 1024) return 960;
        return 800;
    }
    
    // Tablets: keep content reasonably narrow for readability.
    return 800;
}

export const layout = {
    maxWidth: getMaxLayoutWidth(),
    headerMaxWidth: getMaxWidth()
}
