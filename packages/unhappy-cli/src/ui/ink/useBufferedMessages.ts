import { useEffect, useRef, useState } from 'react'
import { MessageBuffer, type BufferedMessage } from './messageBuffer'

export const DISPLAY_UPDATE_INTERVAL_MS = 16

interface BufferedMessagesState {
    messages: BufferedMessage[]
    version: number
}

/**
 * Throttles rapid MessageBuffer updates so Ink doesn't re-render for every token chunk.
 */
export function useBufferedMessages(
    messageBuffer: MessageBuffer,
    intervalMs: number = DISPLAY_UPDATE_INTERVAL_MS
): BufferedMessagesState {
    const [version, setVersion] = useState(0)
    const timerRef = useRef<NodeJS.Timeout | null>(null)
    const pendingRef = useRef(false)

    useEffect(() => {
        const flush = () => {
            timerRef.current = null
            if (!pendingRef.current) {
                return
            }
            pendingRef.current = false
            setVersion((prev) => prev + 1)
        }

        const schedule = () => {
            pendingRef.current = true
            if (timerRef.current) {
                return
            }
            timerRef.current = setTimeout(flush, intervalMs)
        }

        const unsubscribe = messageBuffer.onUpdate(() => {
            schedule()
        })

        // Sync once in case messages were added before subscription.
        setVersion((prev) => prev + 1)

        return () => {
            unsubscribe()
            pendingRef.current = false
            if (timerRef.current) {
                clearTimeout(timerRef.current)
                timerRef.current = null
            }
        }
    }, [messageBuffer, intervalMs])

    return {
        messages: messageBuffer.getMessages(),
        version
    }
}
