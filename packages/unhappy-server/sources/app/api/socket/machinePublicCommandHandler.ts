import { findConnectedMachine, invokePublicCommand } from "@/app/api/routes/codexPublicCommands";
import { buildMachineActivityEphemeral, eventRouter } from "@/app/events/eventRouter";
import { db } from "@/storage/db";
import { log } from "@/utils/log";
import { Socket } from "socket.io";

const ALLOWED_MACHINE_COMMANDS = new Set<string>([
    "bash",
    "readFile",
    "writeFile",
    "listDirectory",
    "getDirectoryTree",
    "ripgrep",
    "open-project",
    "close-project",
    "list-projects",
    "list-models",
    "codex-list-threads",
    "codex-open-thread",
    "codex-list-messages",
    "codex-send-message",
    "codex-set-thread-name",
    "claude-list-sessions",
    "claude-list-messages",
    "claude-send-message",
    "gemini-list-sessions",
    "gemini-list-messages",
    "gemini-send-message",
    "spawn-provider-session",
    "stop-daemon",
    "update-daemon",
]);

export function machinePublicCommandHandler(userId: string, socket: Socket) {
    socket.on(
        "machine-public-command",
        async (
            data: {
                machineId?: string;
                command?: string;
                params?: unknown;
            },
            callback?: (response: any) => void
        ) => {
            if (typeof callback !== "function") {
                return;
            }

            try {
                const machineId = typeof data?.machineId === "string"
                    ? data.machineId.trim()
                    : "";
                if (!machineId) {
                    callback({ success: false, error: "machineId is required" });
                    return;
                }

                const command = typeof data?.command === "string"
                    ? data.command.trim()
                    : "";
                if (!command) {
                    callback({ success: false, error: "command is required" });
                    return;
                }

                if (!ALLOWED_MACHINE_COMMANDS.has(command)) {
                    callback({ success: false, error: `Unsupported machine command: ${command}` });
                    return;
                }

                const target = findConnectedMachine(userId, machineId);
                if (!target) {
                    callback({ success: false, error: "Machine daemon is not connected" });
                    return;
                }

                const result = await invokePublicCommand(target, {
                    command,
                    params: data?.params ?? {},
                });

                if (command === "stop-daemon") {
                    const normalizedResult = typeof result === "object" && result !== null
                        ? result as Record<string, unknown>
                        : null;
                    const failed = normalizedResult?.success === false ||
                        (
                            typeof normalizedResult?.error === "string" &&
                            normalizedResult.error.trim().length > 0 &&
                            normalizedResult?.success !== true
                        );

                    if (!failed) {
                        const stoppedAt = Date.now();
                        await db.machine.updateMany({
                            where: {
                                accountId: userId,
                                id: machineId,
                            },
                            data: {
                                active: false,
                                lastActiveAt: new Date(stoppedAt),
                            },
                        });

                        eventRouter.emitEphemeral({
                            userId,
                            payload: buildMachineActivityEphemeral(machineId, false, stoppedAt),
                            recipientFilter: { type: "user-scoped-only" },
                        });
                    }
                }

                callback(result);
            } catch (error) {
                log({ module: "websocket", level: "error" }, `Error in machine-public-command: ${error}`);
                callback({
                    success: false,
                    error: error instanceof Error ? error.message : "Machine command failed",
                });
            }
        }
    );
}
