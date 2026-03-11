import { onShutdown } from "@/utils/shutdown";
import { auth } from "@/app/auth/auth";
import { db } from "@/storage/db";
import { log } from "@/utils/log";
import { randomUUID } from "node:crypto";
import { IncomingMessage } from "node:http";
import { Duplex } from "node:stream";
import WebSocket, { RawData, WebSocketServer } from "ws";
import {
    MACHINE_DATA_PLANE_DEFAULT_MAX_CHUNK_BYTES,
    MACHINE_DATA_PLANE_DEFAULT_MAX_IN_FLIGHT_STREAMS,
    MACHINE_DATA_PLANE_PROTOCOL_VERSION,
    MACHINE_DATA_PLANE_SUBPROTOCOL,
    MachineDataPlaneErrorFrameSchema,
    MachineDataPlaneFrameSchema,
    MachineDataPlaneFrameTypeSchema,
    MachineDataPlaneHelloAckFrameSchema,
    MachineDataPlaneHelloFrame,
    MachineDataPlaneHelloFrameSchema,
    MachineDataPlaneRoleSchema,
} from "./machineDataPlaneProtocol";
import type { Fastify } from "../types";

export type MachineDataPlaneRole = "native" | "daemon";

type ConnectionState = {
    socket: WebSocket;
    userId: string;
    machineId: string;
    sessionId: string;
    role: MachineDataPlaneRole | null;
    hello: MachineDataPlaneHelloFrame | null;
    ready: boolean;
    handshakeTimeout: ReturnType<typeof setTimeout> | null;
};

type StreamState = {
    initiatorRole: MachineDataPlaneRole;
};

type StreamTerminationTarget = {
    streamId: string;
    recipientRole: MachineDataPlaneRole;
};

type MachineRouteState = {
    native?: ConnectionState;
    daemon?: ConnectionState;
    streams: Map<string, StreamState>;
};

const machinePathPattern = /^\/v1\/machines\/([^/]+)\/data-plane\/?$/;
const NATIVE_HANDSHAKE_TIMEOUT_MS = 10_000;

export function machineDataPlaneNativeHandshakeTimeoutMs(): number {
    return NATIVE_HANDSHAKE_TIMEOUT_MS;
}

export function machineDataPlaneOutstandingStreamTerminationTargets(
    streams: Iterable<readonly [string, { initiatorRole: MachineDataPlaneRole }]>,
    disconnectedRole: MachineDataPlaneRole
): StreamTerminationTarget[] {
    const targets: StreamTerminationTarget[] = [];
    const recipientRole: MachineDataPlaneRole = disconnectedRole === "native" ? "daemon" : "native";

    for (const [streamId, stream] of streams) {
        if (stream.initiatorRole === disconnectedRole) {
            continue;
        }
        targets.push({
            streamId,
            recipientRole,
        });
    }

    return targets;
}

function machineKey(userId: string, machineId: string): string {
    return `${userId}:${machineId}`;
}

function sendJSONFrame(socket: WebSocket, payload: unknown): void {
    if (socket.readyState !== WebSocket.OPEN) return;
    socket.send(JSON.stringify(payload));
}

function rejectUpgrade(socket: Duplex, statusCode: number, message: string): void {
    socket.write(
        `HTTP/1.1 ${statusCode} ${message}\r\n` +
        "Connection: close\r\n" +
        "Content-Type: text/plain; charset=utf-8\r\n" +
        `Content-Length: ${Buffer.byteLength(message, "utf8")}\r\n` +
        "\r\n" +
        message
    );
    socket.destroy();
}

function getBearerToken(request: IncomingMessage): string | null {
    const header = request.headers.authorization;
    if (typeof header !== "string") return null;
    const [scheme, token] = header.split(/\s+/, 2);
    if (!scheme || !token) return null;
    if (scheme.toLowerCase() !== "bearer") return null;
    const normalizedToken = token.trim();
    return normalizedToken.length > 0 ? normalizedToken : null;
}

function getMachineIdFromRequest(request: IncomingMessage): string | null {
    const rawURL = typeof request.url === "string" ? request.url : "";
    const pathname = rawURL.split("?", 1)[0] ?? "";
    const match = pathname.match(machinePathPattern);
    return match?.[1] ? decodeURIComponent(match[1]) : null;
}

function getSubprotocol(request: IncomingMessage): string | null {
    const header = request.headers["sec-websocket-protocol"];
    if (typeof header !== "string") return null;
    const values = header
        .split(",")
        .map((value) => value.trim())
        .filter((value) => value.length > 0);
    return values.includes(MACHINE_DATA_PLANE_SUBPROTOCOL)
        ? MACHINE_DATA_PLANE_SUBPROTOCOL
        : null;
}

export function startMachineDataPlaneSocket(app: Fastify) {
    const wss = new WebSocketServer({
        noServer: true,
        clientTracking: false,
    });
    const machineRoutes = new Map<string, MachineRouteState>();
    const socketStates = new WeakMap<WebSocket, ConnectionState>();

    function clearHandshakeTimeout(state: ConnectionState | undefined): void {
        if (!state?.handshakeTimeout) return;
        clearTimeout(state.handshakeTimeout);
        state.handshakeTimeout = null;
    }

    function getRouteState(userId: string, machineId: string): MachineRouteState {
        const key = machineKey(userId, machineId);
        const existing = machineRoutes.get(key);
        if (existing) return existing;
        const created: MachineRouteState = { streams: new Map() };
        machineRoutes.set(key, created);
        return created;
    }

    function cleanupState(state: ConnectionState): void {
        clearHandshakeTimeout(state);
        const key = machineKey(state.userId, state.machineId);
        const routeState = machineRoutes.get(key);
        if (!routeState) return;

        if (routeState.native?.socket === state.socket) {
            routeState.native = undefined;
        }
        if (routeState.daemon?.socket === state.socket) {
            routeState.daemon = undefined;
        }

        if (state.role) {
            terminateOutstandingStreams(
                routeState,
                state.role,
                "peer_disconnected",
                "Peer data-plane connection closed before the stream completed",
                true
            );
        }

        if (!routeState.native && !routeState.daemon) {
            machineRoutes.delete(key);
        }
    }

    function sendStreamError(
        state: ConnectionState,
        streamId: string,
        code: string,
        message: string,
        retryable: boolean
    ): void {
        const payload = MachineDataPlaneErrorFrameSchema.parse({
            v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
            t: "error",
            streamId,
            code,
            message,
            retryable,
        });
        sendJSONFrame(state.socket, payload);
    }

    function terminateOutstandingStreams(
        routeState: MachineRouteState,
        disconnectedRole: MachineDataPlaneRole,
        code: string,
        message: string,
        retryable: boolean
    ): void {
        const targets = machineDataPlaneOutstandingStreamTerminationTargets(
            routeState.streams.entries(),
            disconnectedRole
        );

        for (const target of targets) {
            const recipient = target.recipientRole === "native" ? routeState.native : routeState.daemon;
            if (!recipient?.ready) {
                continue;
            }
            sendStreamError(recipient, target.streamId, code, message, retryable);
        }

        routeState.streams.clear();
    }

    function tryFinishHandshake(routeState: MachineRouteState): void {
        const native = routeState.native;
        const daemon = routeState.daemon;
        if (!native?.hello || !daemon?.hello) return;
        if (native.ready && daemon.ready) return;

        const maxChunkBytes = MACHINE_DATA_PLANE_DEFAULT_MAX_CHUNK_BYTES;
        const maxInFlightStreams = MACHINE_DATA_PLANE_DEFAULT_MAX_IN_FLIGHT_STREAMS;
        const idleTimeoutSeconds = 45;

        const nativeAck = MachineDataPlaneHelloAckFrameSchema.parse({
            v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
            t: "hello-ack",
            connectionId: native.hello.connectionId,
            sessionId: native.sessionId,
            keyExchange: daemon.hello.keyExchange,
            maxChunkBytes,
            maxInFlightStreams,
            idleTimeoutSeconds,
        });
        const daemonAck = MachineDataPlaneHelloAckFrameSchema.parse({
            v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
            t: "hello-ack",
            connectionId: daemon.hello.connectionId,
            sessionId: daemon.sessionId,
            keyExchange: native.hello.keyExchange,
            maxChunkBytes,
            maxInFlightStreams,
            idleTimeoutSeconds,
        });

        sendJSONFrame(native.socket, nativeAck);
        sendJSONFrame(daemon.socket, daemonAck);
        native.ready = true;
        daemon.ready = true;
        clearHandshakeTimeout(native);
        clearHandshakeTimeout(daemon);
    }

    function scheduleNativeHandshakeTimeout(routeState: MachineRouteState, state: ConnectionState): void {
        clearHandshakeTimeout(state);
        state.handshakeTimeout = setTimeout(() => {
            const currentNative = routeState.native;
            if (!currentNative || currentNative.socket !== state.socket || currentNative.ready) {
                return;
            }
            if (routeState.daemon?.ready) {
                return;
            }
            log(
                { module: "machine-data-plane", level: "warn" },
                `Native data-plane handshake timed out for machine ${state.machineId}`
            );
            state.socket.close(1013, "Daemon data-plane connection timed out");
        }, NATIVE_HANDSHAKE_TIMEOUT_MS);
    }

    function dropPeerForRenegotiation(
        routeState: MachineRouteState,
        peerRole: MachineDataPlaneRole,
        reason: string
    ): void {
        const peer = peerRole === "native" ? routeState.native : routeState.daemon;
        if (!peer) return;

        terminateOutstandingStreams(
            routeState,
            peerRole,
            "peer_renegotiating",
            reason,
            true
        );
        if (peerRole === "native") {
            routeState.native = undefined;
        } else {
            routeState.daemon = undefined;
        }
        peer.socket.close(1012, reason);
    }

    function registerHello(state: ConnectionState, hello: MachineDataPlaneHelloFrame): void {
        const routeState = getRouteState(state.userId, state.machineId);
        const role = MachineDataPlaneRoleSchema.parse(hello.role);
        state.role = role;
        state.hello = hello;
        state.ready = false;

        const existing = role === "native" ? routeState.native : routeState.daemon;
        if (existing && existing.socket !== state.socket) {
            terminateOutstandingStreams(
                routeState,
                role,
                "peer_superseded",
                "Peer data-plane connection was superseded by a newer connection",
                true
            );
            existing.socket.close(1012, "Superseded by a newer data-plane connection");
        }

        const peerRole = role === "native" ? "daemon" : "native";
        const peer = peerRole === "native" ? routeState.native : routeState.daemon;
        if (peer?.ready) {
            dropPeerForRenegotiation(
                routeState,
                peerRole,
                "Peer reconnected; renegotiating data-plane session"
            );
        }

        if (role === "native") {
            routeState.native = state;
            if (!routeState.daemon?.ready) {
                scheduleNativeHandshakeTimeout(routeState, state);
            }
        } else {
            routeState.daemon = state;
        }

        tryFinishHandshake(routeState);
    }

    function routeFrame(state: ConnectionState, rawFrame: unknown): void {
        if (!state.role) {
            state.socket.close(1008, "Handshake required");
            return;
        }

        const parsed = MachineDataPlaneFrameSchema.safeParse(rawFrame);
        if (!parsed.success) {
            state.socket.close(1008, "Invalid data-plane frame");
            return;
        }

        const frame = parsed.data;
        if (frame.t === "hello" || frame.t === "hello-ack") {
            state.socket.close(1008, "Handshake frame not allowed after initialization");
            return;
        }

        const routeState = getRouteState(state.userId, state.machineId);
        const peer = state.role === "native" ? routeState.daemon : routeState.native;

        if (!peer?.ready) {
            if ("streamId" in frame) {
                sendStreamError(
                    state,
                    frame.streamId,
                    "peer_not_connected",
                    "Peer data-plane connection is not ready",
                    true
                );
                return;
            }
            state.socket.close(1013, "Peer data-plane connection is not ready");
            return;
        }

        switch (frame.t) {
        case "request":
            routeState.streams.set(frame.streamId, { initiatorRole: state.role });
            sendJSONFrame(peer.socket, frame);
            return;

        case "ack": {
            const stream = routeState.streams.get(frame.streamId);
            if (!stream) {
                return;
            }
            if (stream.initiatorRole !== state.role) {
                state.socket.close(1008, "Only stream initiator may acknowledge chunks");
                return;
            }
            sendJSONFrame(peer.socket, frame);
            return;
        }

        case "chunk":
        case "complete":
        case "error": {
            const stream = routeState.streams.get(frame.streamId);
            if (!stream) {
                return;
            }
            if (stream.initiatorRole === state.role) {
                state.socket.close(1008, "Only responder may stream results");
                return;
            }
            const initiator = stream.initiatorRole === "native" ? routeState.native : routeState.daemon;
            if (initiator?.ready) {
                sendJSONFrame(initiator.socket, frame);
            }
            if (frame.t === "complete" || frame.t === "error") {
                routeState.streams.delete(frame.streamId);
            }
            return;
        }

        default:
            state.socket.close(1008, "Unsupported data-plane frame");
        }
    }

    async function authorizeUpgrade(request: IncomingMessage): Promise<{ userId: string; machineId: string } | null> {
        const machineId = getMachineIdFromRequest(request);
        if (!machineId) return null;
        if (getSubprotocol(request) !== MACHINE_DATA_PLANE_SUBPROTOCOL) {
            return null;
        }

        const token = getBearerToken(request);
        if (!token) return null;

        const verified = await auth.verifyToken(token);
        if (!verified) return null;

        const machine = await db.machine.findFirst({
            where: {
                accountId: verified.userId,
                id: machineId,
            },
            select: { id: true },
        });
        if (!machine) return null;
        return { userId: verified.userId, machineId };
    }

    app.server.on("upgrade", async (request, socket, head) => {
        const machineId = getMachineIdFromRequest(request);
        if (!machineId) {
            return;
        }

        try {
            const authorized = await authorizeUpgrade(request);
            if (!authorized) {
                rejectUpgrade(socket, 401, "Unauthorized");
                return;
            }

            wss.handleUpgrade(request, socket, head, (ws: WebSocket) => {
                const state: ConnectionState = {
                    socket: ws,
                    userId: authorized.userId,
                    machineId: authorized.machineId,
                    sessionId: randomUUID(),
                    role: null,
                    hello: null,
                    ready: false,
                    handshakeTimeout: null,
                };
                socketStates.set(ws, state);

                ws.on("message", (raw: RawData) => {
                    const currentState = socketStates.get(ws);
                    if (!currentState) return;

                    let decoded: unknown;
                    try {
                        const text = typeof raw === "string" ? raw : raw.toString("utf8");
                        decoded = JSON.parse(text);
                    } catch {
                        ws.close(1008, "Invalid JSON frame");
                        return;
                    }

                    if (!currentState.hello) {
                        const hello = MachineDataPlaneHelloFrameSchema.safeParse(decoded);
                        if (!hello.success) {
                            ws.close(1008, "Expected hello frame");
                            return;
                        }
                        registerHello(currentState, hello.data);
                        return;
                    }

                    routeFrame(currentState, decoded);
                });

                ws.on("close", () => {
                    const currentState = socketStates.get(ws);
                    if (!currentState) return;
                    cleanupState(currentState);
                });

                ws.on("error", (error: Error) => {
                    log({ module: "machine-data-plane", level: "error" }, `Socket error: ${error}`);
                });
            });
        } catch (error) {
            log({ module: "machine-data-plane", level: "error" }, `Upgrade failed: ${error}`);
            rejectUpgrade(socket, 500, "Internal Server Error");
        }
    });

    onShutdown("machine-data-plane", async () => {
        for (const routeState of machineRoutes.values()) {
            routeState.native?.socket.close(1001, "Server shutdown");
            routeState.daemon?.socket.close(1001, "Server shutdown");
        }
        await new Promise<void>((resolve) => {
            wss.close(() => resolve());
        });
    });
}
