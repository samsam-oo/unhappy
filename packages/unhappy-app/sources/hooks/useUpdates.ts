import { useCallback, useEffect, useState } from 'react';
import { AppState, AppStateStatus, DevSettings, Platform, type NativeEventSubscription } from 'react-native';
import * as Updates from 'expo-updates';
import { Modal } from '@/modal';
import { t } from '@/text';

const ACTIVE_RECHECK_COOLDOWN_MS = 5 * 60 * 1000;

type SharedUpdateState = {
    updateAvailable: boolean;
    isChecking: boolean;
    lastCheckedAt: number;
};

const sharedState: SharedUpdateState = {
    updateAvailable: false,
    isChecking: false,
    lastCheckedAt: 0,
};

const listeners = new Set<() => void>();
let inFlightCheck: Promise<void> | null = null;
let appStateSubscription: NativeEventSubscription | null = null;
let currentAppState: AppStateStatus = AppState.currentState;
let hookSubscriberCount = 0;
let updatePromptInFlight: Promise<void> | null = null;
let didShowUpdatePromptThisSession = false;

const notifyListeners = () => {
    listeners.forEach((listener) => {
        listener();
    });
};

const reloadAppShared = async () => {
    if (Platform.OS === 'web') {
        window.location.reload();
        return;
    }

    try {
        await Updates.reloadAsync();
    } catch (error) {
        if (__DEV__) {
            try {
                DevSettings.reload();
                return;
            } catch (e) {
                console.error('DevSettings.reload failed:', e);
            }
        }
        console.error('Error reloading app:', error);
    }
};

const showUpdatePromptIfNeeded = async () => {
    if (Platform.OS === 'web' || !sharedState.updateAvailable || didShowUpdatePromptThisSession) {
        return;
    }

    if (updatePromptInFlight !== null) {
        return updatePromptInFlight;
    }

    updatePromptInFlight = (async () => {
        didShowUpdatePromptThisSession = true;

        const shouldApplyNow = await Modal.confirm(
            t('updateBanner.updateAvailable'),
            t('updateBanner.pressToApply'),
            {
                cancelText: t('common.cancel'),
                confirmText: t('settingsLanguage.restartNow'),
            }
        );

        if (shouldApplyNow) {
            await reloadAppShared();
        }
    })().finally(() => {
        updatePromptInFlight = null;
    });

    return updatePromptInFlight;
};

const checkForUpdatesShared = async (force: boolean = false): Promise<void> => {
    if (__DEV__ || Platform.OS === 'web') {
        return;
    }

    if (sharedState.updateAvailable) {
        return;
    }

    const now = Date.now();
    if (!force && now - sharedState.lastCheckedAt < ACTIVE_RECHECK_COOLDOWN_MS) {
        return;
    }

    if (inFlightCheck !== null) {
        return inFlightCheck;
    }

    sharedState.isChecking = true;
    notifyListeners();

    inFlightCheck = (async () => {
        try {
            const update = await Updates.checkForUpdateAsync();
            if (update.isAvailable) {
                await Updates.fetchUpdateAsync();
                sharedState.updateAvailable = true;
                void showUpdatePromptIfNeeded();
            }
        } catch (error) {
            console.error('Error checking for updates:', error);
        } finally {
            sharedState.lastCheckedAt = Date.now();
            sharedState.isChecking = false;
            inFlightCheck = null;
            notifyListeners();
        }
    })();

    return inFlightCheck;
};

const ensureAppStateListener = () => {
    if (appStateSubscription !== null) {
        return;
    }

    appStateSubscription = AppState.addEventListener('change', (nextAppState) => {
        const prevAppState = currentAppState;
        currentAppState = nextAppState;

        if (nextAppState === 'active' && (prevAppState === 'background' || prevAppState === 'inactive')) {
            void checkForUpdatesShared(false);
        }
    });
};

const teardownAppStateListener = () => {
    if (appStateSubscription === null) {
        return;
    }

    appStateSubscription.remove();
    appStateSubscription = null;
};

export function useUpdates() {
    const [updateAvailable, setUpdateAvailable] = useState(sharedState.updateAvailable);
    const [isChecking, setIsChecking] = useState(sharedState.isChecking);

    useEffect(() => {
        const syncFromSharedState = () => {
            setUpdateAvailable(sharedState.updateAvailable);
            setIsChecking(sharedState.isChecking);
        };

        listeners.add(syncFromSharedState);
        hookSubscriberCount += 1;
        ensureAppStateListener();

        if (sharedState.lastCheckedAt === 0 && !sharedState.updateAvailable) {
            void checkForUpdatesShared(true);
        } else if (sharedState.updateAvailable) {
            void showUpdatePromptIfNeeded();
        }

        syncFromSharedState();

        return () => {
            listeners.delete(syncFromSharedState);
            hookSubscriberCount = Math.max(0, hookSubscriberCount - 1);
            if (hookSubscriberCount === 0) {
                teardownAppStateListener();
            }
        };
    }, []);

    const checkForUpdates = useCallback(async () => {
        await checkForUpdatesShared(true);
    }, []);

    const reloadApp = async () => {
        await reloadAppShared();
    };

    return {
        updateAvailable,
        isChecking,
        checkForUpdates,
        reloadApp,
    };
}
