import { Platform } from 'react-native';

// Shared spacing, sizing constants (DRY - used by both themes)
const sharedSpacing = {
    // Spacing scale (based on actual usage patterns in codebase)
    margins: {
        xs: 4,   // Tight spacing, status indicators
        sm: Platform.select({ web: 6, default: 8 }),   // Web is denser (desktop-like)
        md: Platform.select({ web: 10, default: 12 }),
        lg: Platform.select({ web: 12, default: 16 }),
        xl: Platform.select({ web: 16, default: 20 }),
        xxl: Platform.select({ web: 20, default: 24 }),
    },

    // Border radii (based on actual usage patterns in codebase)
    borderRadius: {
        sm: Platform.select({ web: 3, default: 4 }),
        md: Platform.select({ web: 6, default: 8 }),
        lg: Platform.select({ web: 8, default: 10 }),
        xl: Platform.select({ web: 10, default: 12 }),
        xxl: Platform.select({ web: 12, default: 16 }),
    },

    // Icon sizes (based on actual usage patterns)
    iconSize: {
        small: 12,
        medium: Platform.select({ web: 14, default: 16 }),
        large: Platform.select({ web: 18, default: 20 }),
        xlarge: Platform.select({ web: 22, default: 24 }),
    },
} as const;

export const lightTheme = {
    dark: false,
    colors: {

        //
        // Main colors
        //

        text: Platform.select({ web: '#1E1E1E', default: '#000000' }),
        textDestructive: Platform.select({ ios: '#FF3B30', default: '#F44336' }),
        textSecondary: Platform.select({ ios: '#8E8E93', web: '#6B6B6B', default: '#49454F' }),
        textLink: '#2BACCC',
        deleteAction: '#FF6B6B', // Delete/remove button color
        warningCritical: '#FF3B30',
        warning: Platform.select({ web: '#6B6B6B', default: '#8E8E93' }),
        success: '#34C759',
        // Light theme: white base with subtle gray panels.
        surface: Platform.select({ web: '#FFFFFF', default: '#ffffff' }),
        surfaceRipple: 'rgba(0, 0, 0, 0.08)',
        surfacePressed: Platform.select({ web: '#E8E8E8', default: '#f0f0f2' }),
        surfaceSelected: Platform.select({ ios: '#C6C6C8', web: '#DCDCDC', default: '#eaeaea' }),
        surfacePressedOverlay: Platform.select({ ios: '#D1D1D6', default: 'transparent' }),
        surfaceHigh: Platform.select({ web: '#F3F3F3', default: '#F8F8F8' }),
        surfaceHighest: Platform.select({ web: '#EDEDED', default: '#f0f0f0' }),
        divider: Platform.select({ ios: '#eaeaea', web: '#E1E1E1', default: '#eaeaea' }),
        chrome: {
            editorBackground: Platform.select({ web: '#FFFFFF', default: '#FFFFFF' }),
            sidebarBackground: Platform.select({ web: '#F3F3F3', default: '#F3F3F3' }),
            panelBorder: Platform.select({ web: '#E1E1E1', default: '#E1E1E1' }),
            accent: Platform.select({ web: '#0E639C', default: '#007AFF' }),
            listHoverBackground: Platform.select({ web: '#E8E8E8', default: '#E8E8E8' }),
            listActiveBackground: Platform.select({ web: '#DCDCDC', default: '#DCDCDC' }),
        },
        shadow: {
            color: Platform.select({ default: '#000000', web: 'rgba(0, 0, 0, 0.1)' }),
            opacity: 0.1,
        },

        //
        // System components
        //

        groupped: {
            // Web uses a more neutral gray, iOS keeps native grouped background.
            background: Platform.select({ ios: '#F2F2F7', web: '#FFFFFF', default: '#F5F5F5' }),
            chevron: Platform.select({ ios: '#C7C7CC', web: '#6B6B6B', default: '#49454F' }),
            sectionTitle: Platform.select({ ios: '#8E8E93', web: '#6B6B6B', default: '#49454F' }),
        },
        header: {
            background: Platform.select({ web: '#F3F3F3', default: '#ffffff' }),
            tint: '#18171C'
        },
        switch: {
            track: {
                active: Platform.select({ ios: '#34C759', default: '#1976D2' }),
                inactive: '#dddddd',
            },
            thumb: {
                active: '#FFFFFF',
                inactive: '#767577',
            },
        },
        fab: {
            background: '#000000',
            backgroundPressed: '#1a1a1a',
            icon: '#FFFFFF',
        },
        radio: {
            active: '#007AFF',
            inactive: '#C0C0C0',
            dot: '#007AFF',
        },
        modal: {
            border: 'rgba(0, 0, 0, 0.1)'
        },
        button: {
            primary: {
                background: Platform.select({ web: '#0E639C', default: '#000000' }), // Desktop-ish blue on web
                tint: '#FFFFFF',
                disabled: '#C0C0C0',
            },
            secondary: {
                tint: '#666666',
            }
        },
        input: {
            background: Platform.select({ web: '#FFFFFF', default: '#F5F5F5' }),
            text: Platform.select({ web: '#1E1E1E', default: '#000000' }),
            placeholder: Platform.select({ web: '#6B6B6B', default: '#999999' }),
        },
        box: {
            warning: {
                background: '#FFF8F0',
                border: '#FF9500',
                text: '#FF9500',
            },
            error: {
                background: '#FFF0F0',
                border: '#FF3B30',
                text: '#FF3B30',
            }
        },

        //
        // App components
        //

        status: {
            connected: '#34C759',
            connecting: '#007AFF',
            disconnected: '#999999',
            error: '#FF3B30',
            default: '#8E8E93',
        },

        // Permission mode colors
        permission: {
            default: '#8E8E93',
            acceptEdits: '#007AFF',
            bypass: '#FF9500',
            plan: '#34C759',
            readOnly: '#8B8B8D',
            safeYolo: '#FF6B35',
            yolo: '#DC143C',
        },

        // Permission button colors
        permissionButton: {
            allow: {
                background: '#34C759',
                text: '#FFFFFF',
            },
            deny: {
                background: '#FF3B30',
                text: '#FFFFFF',
            },
            allowAll: {
                background: '#007AFF',
                text: '#FFFFFF',
            },
            inactive: {
                background: '#E5E5EA',
                border: '#D1D1D6',
                text: '#8E8E93',
            },
            selected: {
                background: '#F2F2F7',
                border: '#D1D1D6',
                text: '#3C3C43',
            },
        },


        // Diff view
        diff: {
            outline: '#E0E0E0',
            success: '#28A745',
            error: '#DC3545',
            // Traditional diff colors
            addedBg: '#E6FFED',
            addedBorder: '#34D058',
            addedText: '#24292E',
            removedBg: '#FFEEF0',
            removedBorder: '#D73A49',
            removedText: '#24292E',
            contextBg: '#F6F8FA',
            // Keep context lines readable (GitHub-style)
            contextText: '#24292E',
            lineNumberBg: '#F6F8FA',
            lineNumberText: '#959DA5',
            hunkHeaderBg: '#F1F8FF',
            hunkHeaderText: '#005CC5',
            leadingSpaceDot: '#E8E8E8',
            inlineAddedBg: '#ACFFA6',
            inlineAddedText: '#0A3F0A',
            inlineRemovedBg: '#FFCECB',
            inlineRemovedText: '#5A0A05',
        },

        // Message View colors
        userMessageBackground: '#f0eee6',
        userMessageText: '#000000',
        agentMessageText: '#000000',
        agentEventText: '#666666',

        // Code/Syntax colors
        syntaxKeyword: '#1d4ed8',
        syntaxString: '#059669',
        syntaxComment: '#6b7280',
        syntaxNumber: '#0891b2',
        syntaxFunction: '#9333ea',
        syntaxBracket1: '#ff6b6b',
        syntaxBracket2: '#4ecdc4',
        syntaxBracket3: '#45b7d1',
        syntaxBracket4: '#f7b731',
        syntaxBracket5: '#5f27cd',
        syntaxDefault: '#374151',

        // Git status colors
        gitBranchText: '#6b7280',
        gitFileCountText: '#6b7280',
        gitAddedText: '#22c55e',
        gitRemovedText: '#ef4444',

        // Terminal/Command colors
        terminal: {
            // Keep terminal blocks consistent across platforms (PC-first).
            background: '#0B0B0C',
            prompt: '#32D74B',
            command: '#E0E0E0',
            stdout: '#E0E0E0',
            stderr: '#FFB86C',
            error: '#FF5555',
            emptyOutput: '#6272A4',
        },

    },

    ...sharedSpacing,
};

export const darkTheme = {
    dark: true,
    colors: {

        //
        // Main colors
        //

        // Dark theme: light text on near-black surfaces (web).
        text: '#D4D4D4',
        textDestructive: '#FF453A',
        textSecondary: '#9D9D9D',
        textLink: '#2BACCC',
        deleteAction: '#FF6B6B', // Delete/remove button color (same in both themes)
        warningCritical: '#FF453A',
        warning: '#9D9D9D',
        success: '#32D74B',
        // PC-first dark palette: keep mobile aligned with web/desktop.
        // Base: near-black with subtle surface steps (VS Code-ish).
        surface: '#101112',
        surfaceRipple: 'rgba(255, 255, 255, 0.08)',
        surfacePressed: '#17181A',
        surfaceSelected: '#1B1C1E',
        surfacePressedOverlay: 'rgba(255, 255, 255, 0.06)',
        // iOS dark theme is #1c1c1e for items, and #000 for the background
        surfaceHigh: '#141516',
        surfaceHighest: '#1B1C1E',
        divider: '#202023',
        chrome: {
            editorBackground: '#0B0B0C',
            sidebarBackground: '#0F0F10',
            panelBorder: '#202023',
            accent: '#007ACC',
            listHoverBackground: '#141516',
            listActiveBackground: '#1B1C1E',
        },
        shadow: {
            color: Platform.select({ default: '#000000', web: 'rgba(0, 0, 0, 0.1)' }),
            opacity: 0.1,
        },

        //
        // System components
        //

        header: {
            background: '#0F0F10',
            tint: '#CCCCCC'
        },
        switch: {
            track: {
                active: Platform.select({ ios: '#34C759', default: '#1976D2' }),
                inactive: '#3a393f',
            },
            thumb: {
                active: '#FFFFFF',
                inactive: '#767577',
            },
        },
        groupped: {
            background: '#0B0B0C',
            chevron: '#9D9D9D',
            sectionTitle: '#9D9D9D',
        },
        fab: {
            background: '#FFFFFF',
            backgroundPressed: '#f0f0f0',
            icon: '#000000',
        },
        radio: {
            active: '#0A84FF',
            inactive: '#48484A',
            dot: '#0A84FF',
        },
        modal: {
            border: 'rgba(255, 255, 255, 0.1)'
        },
        button: {
            primary: {
                background: '#0E639C',
                tint: '#FFFFFF',
                disabled: '#C0C0C0',
            },
            secondary: {
                tint: '#8E8E93',
            }
        },
        input: {
            background: '#141516',
            text: '#D4D4D4',
            placeholder: '#9D9D9D',
        },
        box: {
            warning: {
                background: 'rgba(255, 159, 10, 0.15)',
                border: '#FF9F0A',
                text: '#FFAB00',
            },
            error: {
                background: 'rgba(255, 69, 58, 0.15)',
                border: '#FF453A',
                text: '#FF6B6B',
            }
        },

        //
        // App components
        //

        status: { // App Connection Status
            connected: '#34C759',
            connecting: '#FFFFFF',
            disconnected: '#8E8E93',
            error: '#FF453A',
            default: '#8E8E93',
        },

        // Permission mode colors
        permission: {
            default: '#8E8E93',
            acceptEdits: '#0A84FF',
            bypass: '#FF9F0A',
            plan: '#32D74B',
            readOnly: '#98989D',
            safeYolo: '#FF7A4C',
            yolo: '#FF453A',
        },

        // Permission button colors
        permissionButton: {
            allow: {
                background: '#32D74B',
                text: '#FFFFFF',
            },
            deny: {
                background: '#FF453A',
                text: '#FFFFFF',
            },
            allowAll: {
                background: '#0A84FF',
                text: '#FFFFFF',
            },
            inactive: {
                background: '#2C2C2E',
                border: '#38383A',
                text: '#8E8E93',
            },
            selected: {
                background: '#1C1C1E',
                border: '#38383A',
                text: '#FFFFFF',
            },
        },


        // Diff view
        diff: {
            outline: '#30363D',
            success: '#3FB950',
            error: '#F85149',
            // Traditional diff colors for dark mode
            addedBg: '#0D2E1F',
            addedBorder: '#3FB950',
            addedText: '#C9D1D9',
            removedBg: '#3F1B23',
            removedBorder: '#F85149',
            removedText: '#C9D1D9',
            contextBg: '#161B22',
            // Match GitHub dark diff text (avoid low-contrast muted gray)
            contextText: '#C9D1D9',
            lineNumberBg: '#161B22',
            lineNumberText: '#6E7681',
            hunkHeaderBg: '#161B22',
            hunkHeaderText: '#58A6FF',
            leadingSpaceDot: '#2A2A2A',
            inlineAddedBg: '#2A5A2A',
            inlineAddedText: '#7AFF7A',
            inlineRemovedBg: '#5A2A2A',
            inlineRemovedText: '#FF7A7A',
        },

        // Message View colors
        userMessageBackground: '#141516',
        userMessageText: '#FFFFFF',
        agentMessageText: '#FFFFFF',
        agentEventText: '#8E8E93',

        // Code/Syntax colors (brighter for dark mode)
        syntaxKeyword: '#569CD6',
        syntaxString: '#CE9178',
        syntaxComment: '#6A9955',
        syntaxNumber: '#B5CEA8',
        syntaxFunction: '#DCDCAA',
        syntaxBracket1: '#FFD700',
        syntaxBracket2: '#DA70D6',
        syntaxBracket3: '#179FFF',
        syntaxBracket4: '#FF8C00',
        syntaxBracket5: '#00FF00',
        syntaxDefault: '#D4D4D4',

        // Git status colors
        gitBranchText: '#8E8E93',
        gitFileCountText: '#8E8E93',
        gitAddedText: '#34C759',
        gitRemovedText: '#FF453A',

        // Terminal/Command colors
        terminal: {
            // Keep terminal blocks consistent across platforms (PC-first).
            background: '#0B0B0C',
            prompt: '#32D74B',
            command: '#E0E0E0',
            stdout: '#E0E0E0',
            stderr: '#FFB86C',
            error: '#FF6B6B',
            emptyOutput: '#7B7B93',
        },

    },

    ...sharedSpacing,
} satisfies typeof lightTheme;

export type Theme = typeof lightTheme;
