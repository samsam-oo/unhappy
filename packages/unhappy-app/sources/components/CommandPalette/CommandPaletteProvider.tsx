import React, { useCallback, useMemo } from 'react';
import { Platform } from 'react-native';
import { useRouter } from 'expo-router';
import { Modal } from '@/modal';
import { CommandPalette } from './CommandPalette';
import { Command } from './types';
import { useGlobalKeyboard } from '@/hooks/useGlobalKeyboard';
import { useAuth } from '@/auth/AuthContext';
import { storage } from '@/sync/storage';
import { useShallow } from 'zustand/react/shallow';
import { useNavigateToSession } from '@/hooks/useNavigateToSession';
import { t } from '@/text';
import { getSessionName } from '@/utils/sessionUtils';

export function CommandPaletteProvider({ children }: { children: React.ReactNode }) {
    const router = useRouter();
    const { logout } = useAuth();
    const sessions = storage(useShallow((state) => state.sessions));
    const commandPaletteEnabled = storage(useShallow((state) => state.localSettings.commandPaletteEnabled));
    const navigateToSession = useNavigateToSession();

    // Define available commands
    const commands = useMemo((): Command[] => {
        const cmds: Command[] = [
            // Navigation commands
            {
                id: 'new-session',
                title: '새 세션',
                subtitle: '새 채팅 세션 시작',
                icon: 'add-circle-outline',
                category: t('tabs.sessions'),
                shortcut: '⌘N',
                action: () => {
                    router.push('/new');
                }
            },
            {
                id: 'sessions',
                title: '모든 세션 보기',
                subtitle: '채팅 기록 보기',
                icon: 'chatbubbles-outline',
                category: t('tabs.sessions'),
                action: () => {
                    router.push('/');
                }
            },
            {
                id: 'settings',
                title: '설정',
                subtitle: '환경설정 변경',
                icon: 'settings-outline',
                category: t('settings.title'),
                shortcut: '⌘,',
                action: () => {
                    router.push('/settings');
                }
            },
            {
                id: 'account',
                title: '계정',
                subtitle: '계정 관리',
                icon: 'person-circle-outline',
                category: t('settings.title'),
                action: () => {
                    router.push('/settings/account');
                }
            },
            {
                id: 'connect',
                title: '기기 연결',
                subtitle: '웹으로 새 기기 연결',
                icon: 'link-outline',
                category: t('settings.title'),
                action: () => {
                    router.push('/terminal/connect');
                }
            },
        ];

        // Add session-specific commands
        const recentSessions = Object.values(sessions)
            .sort((a, b) => b.updatedAt - a.updatedAt)
            .slice(0, 5);

        recentSessions.forEach(session => {
            const sessionName = getSessionName(session);
            cmds.push({
                id: `session-${session.id}`,
                title: sessionName,
                subtitle: session.metadata?.path || '세션으로 전환',
                icon: 'time-outline',
                category: t('tabs.sessions'),
                action: () => {
                    navigateToSession(session.id);
                }
            });
        });

        // System commands
        cmds.push({
            id: 'sign-out',
                title: '로그아웃',
                subtitle: '계정에서 로그아웃',
            icon: 'log-out-outline',
            category: t('common.error'),
            action: async () => {
                await logout();
            }
        });

        // Dev commands (if in development)
        if (__DEV__) {
            cmds.push({
                id: 'dev-menu',
                title: '개발자 메뉴',
                subtitle: '개발자 도구 열기',
                icon: 'code-slash-outline',
                category: t('settings.developer'),
                action: () => {
                    router.push('/dev');
                }
            });
        }

        return cmds;
    }, [router, logout, sessions]);

    const showCommandPalette = useCallback(() => {
        if (Platform.OS !== 'web' || !commandPaletteEnabled) return;
        
        Modal.show({
            component: CommandPalette,
            props: {
                commands,
            }
        } as any);
    }, [commands, commandPaletteEnabled]);

    // Set up global keyboard handler only if feature is enabled
    useGlobalKeyboard(commandPaletteEnabled ? showCommandPalette : () => {});

    return <>{children}</>;
}
