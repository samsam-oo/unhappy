import type { BufferedMessage } from './messageBuffer'

const MODEL_TAG_REGEX = /^\[MODEL:(.+?)\]$/

interface FormatCacheEntry {
    content: string
    maxLineLength: number
    formatted: string
}

export class MessageFormatCache {
    private cache = new Map<string, FormatCacheEntry>()

    format(message: BufferedMessage, maxLineLength: number): string {
        const cached = this.cache.get(message.id)
        if (
            cached &&
            cached.content === message.content &&
            cached.maxLineLength === maxLineLength
        ) {
            return cached.formatted
        }

        const formatted = wrapMessageForTerminal(message.content, maxLineLength)
        this.cache.set(message.id, {
            content: message.content,
            maxLineLength,
            formatted
        })

        return formatted
    }

    prune(activeMessages: readonly BufferedMessage[]): void {
        const activeIds = new Set(activeMessages.map((message) => message.id))
        for (const id of this.cache.keys()) {
            if (!activeIds.has(id)) {
                this.cache.delete(id)
            }
        }
    }
}

export function wrapMessageForTerminal(
    content: string,
    maxLineLength: number
): string {
    const lines = content.split('\n')
    return lines
        .map((line) => {
            if (line.length <= maxLineLength) return line
            const chunks: string[] = []
            for (let i = 0; i < line.length; i += maxLineLength) {
                chunks.push(line.slice(i, i + maxLineLength))
            }
            return chunks.join('\n')
        })
        .join('\n')
}

export function takeLastMessages(
    messages: readonly BufferedMessage[],
    maxCount: number
): BufferedMessage[] {
    if (maxCount <= 0 || messages.length === 0) {
        return []
    }
    const start = Math.max(0, messages.length - maxCount)
    return messages.slice(start)
}

export function extractModelFromMessage(
    message: BufferedMessage | undefined
): string | undefined {
    if (!message || message.type !== 'system') {
        return undefined
    }

    const match = message.content.match(MODEL_TAG_REGEX)
    if (!match || !match[1]) {
        return undefined
    }
    return match[1]
}

export function findLatestModelInMessages(
    messages: readonly BufferedMessage[]
): string | undefined {
    for (let i = messages.length - 1; i >= 0; i--) {
        const model = extractModelFromMessage(messages[i])
        if (model) {
            return model
        }
    }
    return undefined
}

export function isVisibleGeminiMessage(message: BufferedMessage): boolean {
    // Empty system messages are used as internal UI triggers.
    if (message.type === 'system' && !message.content.trim()) {
        return false
    }

    // Internal model markers are consumed by the status bar only.
    if (message.type === 'system' && message.content.startsWith('[MODEL:')) {
        return false
    }

    // Redundant with status bar; keep reasoning messages like "Thinking...".
    if (message.type === 'system' && message.content.startsWith('Using model:')) {
        return false
    }

    return true
}

export function takeLastVisibleGeminiMessages(
    messages: readonly BufferedMessage[],
    maxCount: number
): BufferedMessage[] {
    if (maxCount <= 0 || messages.length === 0) {
        return []
    }

    const visible: BufferedMessage[] = []
    for (let i = messages.length - 1; i >= 0; i--) {
        const message = messages[i]
        if (!isVisibleGeminiMessage(message)) {
            continue
        }

        visible.push(message)
        if (visible.length >= maxCount) {
            break
        }
    }

    visible.reverse()
    return visible
}
