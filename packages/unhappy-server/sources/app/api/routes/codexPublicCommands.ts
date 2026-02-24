import {
    eventRouter,
    MachineScopedConnection,
    SessionScopedConnection
} from "@/app/events/eventRouter";

type PublicCommandPayload = {
    command: string;
    params?: unknown;
};

export function findConnectedSession(userId: string, sessionId: string): SessionScopedConnection | null {
    const connections = eventRouter.getConnections(userId);
    if (!connections) {
        return null;
    }

    for (const connection of connections) {
        if (
            connection.connectionType === 'session-scoped' &&
            connection.sessionId === sessionId &&
            connection.socket.connected
        ) {
            return connection;
        }
    }

    return null;
}

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
    target: SessionScopedConnection | MachineScopedConnection,
    payload: PublicCommandPayload,
    timeoutMs = 30_000
): Promise<any> {
    try {
        return await target.socket.timeout(timeoutMs).emitWithAck('public-command', payload);
    } catch (error) {
        return {
            success: false,
            error: error instanceof Error ? error.message : 'Command dispatch failed'
        };
    }
}
