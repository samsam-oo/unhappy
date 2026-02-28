import { findConnectedMachine, findConnectedSession, invokePublicCommand } from "@/app/api/routes/codexPublicCommands";
import { db } from "@/storage/db";
import { log } from "@/utils/log";
import { Socket } from "socket.io";

type SessionPublicCommandInput = {
    sessionId?: string;
    command?: string;
    params?: unknown;
    allowMachineFallback?: boolean;
};

type InvokeResult =
    | { ok: true; result: any }
    | { ok: false; statusCode: number; error: string };

const ALLOWED_SESSION_COMMANDS = new Set<string>([
    "spawn-unhappy-session",
    "abort",
    "permission",
    "switch",
    "sendMessage",
    "listMessages",
    "bash",
    "readFile",
    "writeFile",
    "listDirectory",
    "getDirectoryTree",
    "ripgrep",
    "difftastic",
    "killSession",
    "codex-list-threads",
    "claude-list-sessions",
]);

const MACHINE_FALLBACK_COMMANDS = new Set<string>([
    "codex-list-threads",
    "claude-list-sessions",
]);

async function ensureSessionBelongsToUser(userId: string, sessionId: string): Promise<boolean> {
    const session = await db.session.findFirst({
        where: {
            id: sessionId,
            accountId: userId,
        },
        select: { id: true },
    });
    return Boolean(session);
}

async function findConnectedMachineForSession(userId: string, sessionId: string): Promise<string | null> {
    const accessKeys = await db.accessKey.findMany({
        where: {
            accountId: userId,
            sessionId,
        },
        orderBy: {
            updatedAt: "desc",
        },
        take: 10,
        select: {
            machineId: true,
        },
    });

    for (const key of accessKeys) {
        const target = findConnectedMachine(userId, key.machineId);
        if (target) {
            return key.machineId;
        }
    }

    return null;
}

async function invokeSessionCommand(
    userId: string,
    sessionId: string,
    command: string,
    params: unknown
): Promise<InvokeResult> {
    const sessionTarget = findConnectedSession(userId, sessionId);
    if (sessionTarget) {
        const result = await invokePublicCommand(sessionTarget, { command, params });
        return { ok: true, result };
    }

    return {
        ok: false,
        statusCode: 409,
        error: "Session RPC is not connected",
    };
}

async function invokeMachineFallbackCommand(
    userId: string,
    sessionId: string,
    command: string,
    params: unknown
): Promise<InvokeResult> {
    const fallbackMachineId = await findConnectedMachineForSession(userId, sessionId);
    if (!fallbackMachineId) {
        return {
            ok: false,
            statusCode: 409,
            error: "Machine daemon is not connected",
        };
    }

    const machineTarget = findConnectedMachine(userId, fallbackMachineId);
    if (!machineTarget) {
        return {
            ok: false,
            statusCode: 409,
            error: "Machine daemon is not connected",
        };
    }

    const result = await invokePublicCommand(machineTarget, { command, params });
    return { ok: true, result };
}

function success(body: any) {
    return { ok: true, body };
}

function failure(statusCode: number, error: string) {
    return { ok: false, statusCode, error };
}

export function sessionPublicCommandHandler(userId: string, socket: Socket) {
    socket.on(
        "session-public-command",
        async (data: SessionPublicCommandInput, callback?: (response: any) => void) => {
            if (typeof callback !== "function") {
                return;
            }

            try {
                const sessionId = typeof data?.sessionId === "string" ? data.sessionId.trim() : "";
                if (!sessionId) {
                    callback(failure(400, "sessionId is required"));
                    return;
                }

                const command = typeof data?.command === "string" ? data.command.trim() : "";
                if (!command) {
                    callback(failure(400, "command is required"));
                    return;
                }
                if (!ALLOWED_SESSION_COMMANDS.has(command)) {
                    callback(failure(400, "Unsupported session command"));
                    return;
                }
                const allowMachineFallback = data?.allowMachineFallback === true;

                const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
                if (!sessionExists) {
                    callback(failure(404, "Session not found"));
                    return;
                }

                if (command === "spawn-unhappy-session") {
                    const fallbackMachineId = await findConnectedMachineForSession(userId, sessionId);
                    if (!fallbackMachineId) {
                        callback(failure(409, "Machine daemon is not connected"));
                        return;
                    }
                    const machineTarget = findConnectedMachine(userId, fallbackMachineId);
                    if (!machineTarget) {
                        callback(failure(409, "Machine daemon is not connected"));
                        return;
                    }

                    const rawParams =
                        data?.params && typeof data.params === "object" && !Array.isArray(data.params)
                            ? (data.params as Record<string, unknown>)
                            : {};
                    const result = await invokePublicCommand(machineTarget, {
                        command: "spawn-unhappy-session",
                        params: {
                            ...rawParams,
                            sessionId,
                            machineId: undefined,
                        },
                    });

                    if (result?.type === "requestToApproveDirectoryCreation") {
                        callback(success({
                            success: false,
                            requiresUserApproval: true,
                            actionRequired: "CREATE_DIRECTORY",
                            directory: result.directory,
                        }));
                        return;
                    }
                    if (result?.type === "success" && typeof result?.sessionId === "string") {
                        callback(success({
                            success: true,
                            sessionId: result.sessionId,
                        }));
                        return;
                    }

                    callback(
                        failure(
                            502,
                            typeof result?.error === "string"
                                ? result.error
                                : typeof result?.errorMessage === "string"
                                    ? result.errorMessage
                                    : "Failed to spawn session"
                        )
                    );
                    return;
                }

                let invoked = await invokeSessionCommand(
                    userId,
                    sessionId,
                    command,
                    data?.params ?? {}
                );

                if (
                    !invoked.ok &&
                    allowMachineFallback &&
                    MACHINE_FALLBACK_COMMANDS.has(command)
                ) {
                    invoked = await invokeMachineFallbackCommand(
                        userId,
                        sessionId,
                        command,
                        data?.params ?? {}
                    );
                }

                if (!invoked.ok) {
                    if (command === "killSession" && invoked.error === "Session RPC is not connected") {
                        callback(success({ success: true, message: "Session is already unavailable" }));
                        return;
                    }
                    callback(failure(invoked.statusCode, invoked.error));
                    return;
                }

                const result = invoked.result;
                if (command === "abort") {
                    if (result?.success === false) {
                        callback(failure(502, typeof result?.error === "string" ? result.error : "Failed to abort session task"));
                        return;
                    }
                    callback(success({ success: true }));
                    return;
                }

                if (command === "permission") {
                    if (result?.success === false) {
                        callback(
                            failure(
                                502,
                                typeof result?.error === "string"
                                    ? result.error
                                    : "Failed to respond to permission request"
                            )
                        );
                        return;
                    }
                    callback(success({ success: true }));
                    return;
                }

                if (command === "switch") {
                    if (result?.success === false) {
                        callback(failure(502, typeof result?.error === "string" ? result.error : "Failed to switch session mode"));
                        return;
                    }
                    callback(success({
                        success: true,
                        switched: typeof result === "boolean" ? result : undefined,
                    }));
                    return;
                }

                if (command === "sendMessage") {
                    if (result?.success === false) {
                        callback(failure(502, typeof result?.error === "string" ? result.error : "Failed to send message"));
                        return;
                    }
                    const queuedMessages = Array.isArray(result?.queuedMessages)
                        ? result.queuedMessages
                            .filter((item: unknown): item is string => typeof item === "string")
                            .map((item: string) => item.trim())
                            .filter((item: string) => item.length > 0)
                        : [];
                    const queueCountRaw = typeof result?.queueCount === "number" ? result.queueCount : undefined;
                    const queueCount = typeof queueCountRaw === "number"
                        ? Math.max(0, Math.floor(queueCountRaw))
                        : queuedMessages.length;
                    callback(success({
                        success: true,
                        queueCount,
                        queuedMessages,
                    }));
                    return;
                }

                if (command === "killSession") {
                    if (result?.success === false) {
                        callback(
                            failure(
                                502,
                                typeof result?.error === "string"
                                    ? result.error
                                    : "Failed to kill session process"
                            )
                        );
                        return;
                    }
                    const message =
                        typeof result?.message === "string" && result.message.trim().length > 0
                            ? result.message.trim()
                            : "Session killed";
                    callback(success({ success: true, message }));
                    return;
                }

                if (command === "codex-list-threads") {
                    if (!result?.success) {
                        callback(failure(502, typeof result?.error === "string" ? result.error : "Failed to list Codex threads"));
                        return;
                    }
                    callback(success(result));
                    return;
                }

                if (command === "claude-list-sessions") {
                    if (!result?.success) {
                        callback(
                            failure(
                                502,
                                typeof result?.error === "string"
                                    ? result.error
                                    : "Failed to list Claude sessions"
                            )
                        );
                        return;
                    }
                    callback(success(result));
                    return;
                }

                callback(success(result));
            } catch (error) {
                log({ module: "websocket", level: "error" }, `Error in session-public-command: ${error}`);
                callback(failure(500, error instanceof Error ? error.message : "Session command failed"));
            }
        }
    );
}
