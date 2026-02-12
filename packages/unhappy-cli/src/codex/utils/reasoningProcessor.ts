/**
 * Codex Reasoning Processor
 *
 * Handles streaming reasoning deltas and identifies reasoning tools for Codex.
 * Extends BaseReasoningProcessor with Codex-specific configuration.
 */

import {
    BaseReasoningProcessor,
    ReasoningToolCall,
    ReasoningToolResult,
    ReasoningMessage,
    ReasoningOutput
} from '@/utils/BaseReasoningProcessor';

// Re-export types for backwards compatibility
export type { ReasoningToolCall, ReasoningToolResult, ReasoningMessage, ReasoningOutput };

const MIN_MEANINGFUL_OVERLAP_CHARS = 8;

function findSuffixPrefixOverlap(left: string, right: string): number {
    const maxOverlap = Math.min(left.length, right.length);
    for (let len = maxOverlap; len > 0; len--) {
        if (left.slice(-len) === right.slice(0, len)) {
            return len;
        }
    }
    return 0;
}

/**
 * Codex-specific reasoning processor.
 */
export class ReasoningProcessor extends BaseReasoningProcessor {
    private mergedReasoningText = '';

    protected getToolName(): string {
        return 'CodexReasoning';
    }

    protected getLogPrefix(): string {
        return '[ReasoningProcessor]';
    }

    private resetMergedReasoningText(): void {
        this.mergedReasoningText = '';
    }

    private normalizeDelta(delta: string): string {
        if (!delta) {
            return '';
        }

        const current = this.mergedReasoningText;
        if (!current) {
            const trimmed = delta.trimStart();
            if (!trimmed) {
                return '';
            }
            this.mergedReasoningText = trimmed;
            return trimmed;
        }

        // Snapshot deltas may carry the same leading whitespace that was
        // trimmed from the very first delta.  Use trimmed form for matching.
        const trimmedDelta = delta.trimStart();

        if (delta === current || trimmedDelta === current) {
            return '';
        }

        // Some app-server streams resend the full reasoning snapshot each tick.
        if (delta.startsWith(current)) {
            const incremental = delta.slice(current.length);
            this.mergedReasoningText = delta;
            return incremental;
        }
        if (trimmedDelta.startsWith(current)) {
            const incremental = trimmedDelta.slice(current.length);
            this.mergedReasoningText = trimmedDelta;
            return incremental;
        }

        // Suppress obvious retransmits of already-emitted long chunks.
        if (
            delta.length >= MIN_MEANINGFUL_OVERLAP_CHARS &&
            current.endsWith(delta)
        ) {
            return '';
        }

        // Handle overlap where the tail of previous text is repeated at the front.
        const overlap = findSuffixPrefixOverlap(current, delta);
        if (overlap >= MIN_MEANINGFUL_OVERLAP_CHARS) {
            const incremental = delta.slice(overlap);
            this.mergedReasoningText = `${current}${incremental}`;
            return incremental;
        }

        this.mergedReasoningText = `${current}${delta}`;
        return delta;
    }

    /**
     * Process a reasoning delta and accumulate content.
     */
    processDelta(delta: string): void {
        const normalizedDelta = this.normalizeDelta(delta);
        if (!normalizedDelta) {
            return;
        }
        this.processInput(normalizedDelta);
    }

    /**
     * Complete the reasoning section with final text.
     */
    complete(fullText?: string): void {
        this.completeReasoning(fullText);
        this.resetMergedReasoningText();
    }

    override handleSectionBreak(): void {
        super.handleSectionBreak();
        this.resetMergedReasoningText();
    }

    override abort(): void {
        super.abort();
        this.resetMergedReasoningText();
    }
}
