import {
    eventRouter,
    MachineScopedConnection
} from "@/app/events/eventRouter";
import { log } from "@/utils/log";

type PublicCommandPayload = {
    command: string;
    params?: unknown;
};

const MESSAGE_LOAD_COMMANDS = new Set([
    "codex-list-messages",
    "claude-list-messages",
    "gemini-list-messages",
]);

export function findConnectedMachine(userId: string, machineId: string): MachineScopedConnection | null {
    const connections = eventRouter.getConnections(userId);
    if (!connections) {
        return null;
    }

    for (const connection of connections) {
        if (
            connection.connectionType === 'machine-scoped' &&
            connection.machineId === machineId &&
            connection.socket.connected
        ) {
            return connection;
        }
    }

    return null;
}

export async function invokePublicCommand(
    target: MachineScopedConnection,
    payload: PublicCommandPayload,
    timeoutMs = resolvePublicCommandTimeoutMs(payload.command)
): Promise<any> {
    const startedAt = Date.now();
    try {
        return await target.socket.timeout(timeoutMs).emitWithAck('public-command', payload);
    } catch (error) {
        log(
            { module: "machine-public-command", level: "warn" },
            `Public command ${payload.command} failed after ${Date.now() - startedAt}ms: ${
                error instanceof Error ? error.message : "Command dispatch failed"
            }`
        );
        return {
            success: false,
            error: error instanceof Error ? error.message : 'Command dispatch failed'
        };
    }
}

function resolvePublicCommandTimeoutMs(command: string): number {
    if (MESSAGE_LOAD_COMMANDS.has(command)) {
        return 8_000;
    }
    return 30_000;
}
