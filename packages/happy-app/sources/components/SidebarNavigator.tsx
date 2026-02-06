import { useAuth } from '@/auth/AuthContext';
import * as React from 'react';
import { Drawer } from 'expo-router/drawer';
import { useIsTablet } from '@/utils/responsive';
import { SidebarView } from './SidebarView';
import { Slot } from 'expo-router';
import { useWindowDimensions } from 'react-native';
import { useUnistyles } from 'react-native-unistyles';

export const SidebarNavigator = React.memo(() => {
    const auth = useAuth();
    const { theme } = useUnistyles();
    const isTablet = useIsTablet();
    const showPermanentDrawer = auth.isAuthenticated && isTablet;
    const { width: windowWidth } = useWindowDimensions();

    // Calculate drawer width only when needed
    const drawerWidth = React.useMemo(() => {
        if (!showPermanentDrawer) return 260; // Default width for hidden drawer
        // Slightly narrower + tighter clamp for a more compact desktop feel (VSCode-ish).
        return Math.min(Math.max(Math.floor(windowWidth * 0.26), 240), 320);
    }, [windowWidth, showPermanentDrawer]);

    const drawerNavigationOptions = React.useMemo(() => {
        if (!showPermanentDrawer) {
            // When drawer is hidden, use minimal configuration
            return {
                lazy: false,
                headerShown: false,
                drawerType: 'front' as const,
                swipeEnabled: false,
                drawerStyle: {
                    width: 0,
                    display: 'none' as const,
                },
            };
        }
        
        // When drawer is permanent
        return {
            lazy: false,
            headerShown: false,
            drawerType: 'permanent' as const,
            drawerStyle: {
                backgroundColor: theme.colors.chrome.sidebarBackground,
                borderRightWidth: 1,
                borderRightColor: theme.colors.chrome.panelBorder,
                width: drawerWidth,
            },
            swipeEnabled: false,
            drawerActiveTintColor: 'transparent',
            drawerInactiveTintColor: 'transparent',
            drawerItemStyle: { display: 'none' as const },
            drawerLabelStyle: { display: 'none' as const },
        };
    }, [showPermanentDrawer, drawerWidth, theme.colors.chrome.sidebarBackground, theme.colors.chrome.panelBorder]);

    // Always render SidebarView but hide it when not needed
    const drawerContent = React.useCallback(
        () => <SidebarView />,
        []
    );

    return (
        <Drawer
            screenOptions={drawerNavigationOptions}
            drawerContent={showPermanentDrawer ? drawerContent : undefined}
        />
    )
});
