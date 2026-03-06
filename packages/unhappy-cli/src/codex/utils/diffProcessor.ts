/**
 * Diff Processor - Handles turn_diff messages and tracks unified_diff changes
 *
 * This processor tracks changes to the unified_diff field in turn_diff messages
 * and forwards a single normalized latest-style event when the diff changes.
 */

import { randomUUID } from 'node:crypto';
import { logger } from '@/ui/logger';

export interface DiffUpdateMessage {
    type: 'turn_diff';
    unified_diff: string;
    id: string;
}

export class DiffProcessor {
    private previousDiff: string | null = null;
    private onMessage: ((message: any) => void) | null = null;

    constructor(onMessage?: (message: any) => void) {
        this.onMessage = onMessage || null;
    }

    /**
     * Process a turn_diff message and check if the unified_diff has changed
     */
    processDiff(unifiedDiff: string): void {
        // Check if the diff has changed from the previous value
        if (this.previousDiff !== unifiedDiff) {
            logger.debug('[DiffProcessor] Unified diff changed, forwarding normalized turn_diff event');

            const diffUpdate: DiffUpdateMessage = {
                type: 'turn_diff',
                unified_diff: unifiedDiff,
                id: randomUUID()
            };

            this.onMessage?.(diffUpdate);
        }
        
        // Update the stored diff value
        this.previousDiff = unifiedDiff;
        logger.debug('[DiffProcessor] Updated stored diff');
    }

    /**
     * Reset the processor state (called on task_complete or turn_aborted)
     */
    reset(): void {
        logger.debug('[DiffProcessor] Resetting diff state');
        this.previousDiff = null;
    }

    /**
     * Set the message callback for sending messages directly
     */
    setMessageCallback(callback: (message: any) => void): void {
        this.onMessage = callback;
    }

    /**
     * Get the current diff value
     */
    getCurrentDiff(): string | null {
        return this.previousDiff;
    }
}
