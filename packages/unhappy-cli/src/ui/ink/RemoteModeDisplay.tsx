import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react'
import { Box, Text, useStdout, useInput } from 'ink'
import { MessageBuffer, type BufferedMessage } from './messageBuffer'
import { MessageFormatCache, takeLastMessages } from './rendering'
import { useBufferedMessages } from './useBufferedMessages'

interface RemoteModeDisplayProps {
    messageBuffer: MessageBuffer
    logPath?: string
    onExit?: () => void
    onSwitchToLocal?: () => void
}

export const RemoteModeDisplay: React.FC<RemoteModeDisplayProps> = ({ messageBuffer, logPath, onExit, onSwitchToLocal }) => {
    const [confirmationMode, setConfirmationMode] = useState<'exit' | 'switch' | null>(null)
    const [actionInProgress, setActionInProgress] = useState<'exiting' | 'switching' | null>(null)
    const confirmationTimeoutRef = useRef<NodeJS.Timeout | null>(null)
    const formatCacheRef = useRef(new MessageFormatCache())
    const { stdout } = useStdout()
    const terminalWidth = stdout.columns || 80
    const terminalHeight = stdout.rows || 24
    const maxVisibleMessages = Math.max(1, terminalHeight - 10)
    const maxLineLength = Math.max(1, terminalWidth - 10)
    const { messages, version } = useBufferedMessages(messageBuffer)

    useEffect(() => {
        return () => {
            if (confirmationTimeoutRef.current) {
                clearTimeout(confirmationTimeoutRef.current)
            }
        }
    }, [])

    const visibleMessages = useMemo(
        () => takeLastMessages(messages, maxVisibleMessages),
        [messages, version, maxVisibleMessages]
    )

    const renderedMessages = useMemo(() => {
        formatCacheRef.current.prune(visibleMessages)
        return visibleMessages.map((message) => ({
            message,
            formatted: formatCacheRef.current.format(message, maxLineLength)
        }))
    }, [visibleMessages, version, maxLineLength])

    const resetConfirmation = useCallback(() => {
        setConfirmationMode(null)
        if (confirmationTimeoutRef.current) {
            clearTimeout(confirmationTimeoutRef.current)
            confirmationTimeoutRef.current = null
        }
    }, [])

    const setConfirmationWithTimeout = useCallback((mode: 'exit' | 'switch') => {
        setConfirmationMode(mode)
        if (confirmationTimeoutRef.current) {
            clearTimeout(confirmationTimeoutRef.current)
        }
        confirmationTimeoutRef.current = setTimeout(() => {
            resetConfirmation()
        }, 15000) // 15 seconds timeout
    }, [resetConfirmation])

    useInput(useCallback(async (input, key) => {
        // Don't process input if action is in progress
        if (actionInProgress) return
        
        // Handle Ctrl-C
        if (key.ctrl && input === 'c') {
            if (confirmationMode === 'exit') {
                // Second Ctrl-C, exit
                resetConfirmation()
                setActionInProgress('exiting')
                // Small delay to show the status message
                await new Promise(resolve => setTimeout(resolve, 100))
                onExit?.()
            } else {
                // First Ctrl-C, show confirmation
                setConfirmationWithTimeout('exit')
            }
            return
        }

        // Handle double space
        if (input === ' ') {
            if (confirmationMode === 'switch') {
                // Second space, switch to local
                resetConfirmation()
                setActionInProgress('switching')
                // Small delay to show the status message
                await new Promise(resolve => setTimeout(resolve, 100))
                onSwitchToLocal?.()
            } else {
                // First space, show confirmation
                setConfirmationWithTimeout('switch')
            }
            return
        }

        // Any other key cancels confirmation
        if (confirmationMode) {
            resetConfirmation()
        }
    }, [confirmationMode, actionInProgress, onExit, onSwitchToLocal, setConfirmationWithTimeout, resetConfirmation]))

    const getMessageColor = (type: BufferedMessage['type']): string => {
        switch (type) {
            case 'user': return 'magenta'
            case 'assistant': return 'cyan'
            case 'system': return 'blue'
            case 'tool': return 'yellow'
            case 'result': return 'green'
            case 'status': return 'gray'
            default: return 'white'
        }
    }

    return (
        <Box flexDirection="column" width={terminalWidth} height={terminalHeight}>
            {/* Main content area with logs */}
            <Box 
                flexDirection="column" 
                width={terminalWidth}
                height={terminalHeight - 4}
                borderStyle="round"
                borderColor="gray"
                paddingX={1}
                overflow="hidden"
            >
                <Box flexDirection="column" marginBottom={1}>
                    <Text color="gray" bold>📡 Remote Mode - Claude Messages</Text>
                    <Text color="gray" dimColor>{'─'.repeat(Math.min(terminalWidth - 4, 60))}</Text>
                </Box>
                
                <Box flexDirection="column" height={terminalHeight - 10} overflow="hidden">
                    {renderedMessages.length === 0 ? (
                        <Text color="gray" dimColor>Waiting for messages...</Text>
                    ) : (
                        renderedMessages.map(({ message, formatted }) => (
                            <Box key={message.id} flexDirection="column" marginBottom={1}>
                                <Text color={getMessageColor(message.type)} dimColor>
                                    {formatted}
                                </Text>
                            </Box>
                        ))
                    )}
                </Box>
            </Box>

            {/* Modal overlay at the bottom */}
            <Box 
                width={terminalWidth}
                borderStyle="round"
                borderColor={
                    actionInProgress ? "gray" :
                    confirmationMode === 'exit' ? "red" : 
                    confirmationMode === 'switch' ? "yellow" : 
                    "green"
                }
                paddingX={2}
                justifyContent="center"
                alignItems="center"
                flexDirection="column"
            >
                <Box flexDirection="column" alignItems="center">
                    {actionInProgress === 'exiting' ? (
                        <Text color="gray" bold>
                            Exiting...
                        </Text>
                    ) : actionInProgress === 'switching' ? (
                        <Text color="gray" bold>
                            Switching to local mode...
                        </Text>
                    ) : confirmationMode === 'exit' ? (
                        <Text color="red" bold>
                            ⚠️  Press Ctrl-C again to exit completely
                        </Text>
                    ) : confirmationMode === 'switch' ? (
                        <Text color="yellow" bold>
                            ⏸️  Press space again to switch to local mode
                        </Text>
                    ) : (
                        <>
                            <Text color="green" bold>
                                📱 Press space to switch to local mode • Ctrl-C to exit
                            </Text>
                        </>
                    )}
                    {process.env.DEBUG && logPath && (
                        <Text color="gray" dimColor>
                            Debug logs: {logPath}
                        </Text>
                    )}
                </Box>
            </Box>
        </Box>
    )
}
