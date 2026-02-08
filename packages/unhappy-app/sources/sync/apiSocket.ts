import { io, Socket } from 'socket.io-client';
import { TokenStorage } from '@/auth/tokenStorage';
import { Encryption } from './encryption/encryption';

//
// Types
//

export interface SyncSocketConfig {
    endpoint: string;
    token: string;
}

export interface SyncSocketState {
    isConnected: boolean;
    connectionStatus: 'disconnected' | 'connecting' | 'connected' | 'error';
    lastError: Error | null;
}

export type SyncSocketListener = (state: SyncSocketState) => void;

//
// Main Class
//

class ApiSocket {

    // State
    private socket: Socket | null = null;
    private config: SyncSocketConfig | null = null;
    private encryption: Encryption | null = null;
    private messageHandlers: Map<string, (data: any) => void> = new Map();
    private reconnectedListeners: Set<() => void> = new Set();
    private statusListeners: Set<(status: 'disconnected' | 'connecting' | 'connected' | 'error') => void> = new Set();
    private currentStatus: 'disconnected' | 'connecting' | 'connected' | 'error' = 'disconnected';
    private connectPromise: Promise<void> | null = null;
    private readonly DEBUG_SOCKET = __DEV__ || process.env.EXPO_PUBLIC_DEBUG === '1';
    private dlog(...args: any[]) {
        if (!this.DEBUG_SOCKET) return;
        console.log('[ApiSocket]', ...args, {
            status: this.currentStatus,
            hasSocket: !!this.socket,
            connected: this.socket?.connected ?? false,
            recovered: (this.socket as any)?.recovered,
            endpoint: this.config?.endpoint,
        });
    }

    //
    // Initialization
    //

    initialize(config: SyncSocketConfig, encryption: Encryption) {
        this.config = config;
        this.encryption = encryption;
        this.connect();
    }

    //
    // Connection Management
    //

    connect() {
        if (!this.config) {
            return;
        }

        // If we already have a socket instance, force a reconnect if needed.
        if (this.socket) {
            if (!this.socket.connected) {
                this.updateStatus('connecting');
                this.dlog('connect: existing socket, calling socket.connect()');
                this.socket.connect();
            }
            return;
        }

        this.updateStatus('connecting');
        this.dlog('connect: creating new socket');

        this.socket = io(this.config.endpoint, {
            path: '/v1/updates',
            auth: {
                token: this.config.token,
                clientType: 'user-scoped' as const
            },
            transports: ['websocket'],
            reconnection: true,
            reconnectionDelay: 1000,
            reconnectionDelayMax: 5000,
            reconnectionAttempts: Infinity
        });

        this.setupEventHandlers();
    }

    /**
     * Best-effort reconnect helper for foreground/resume flows.
     * Many UI actions (like permission approvals) should "just work" after app resumes.
     */
    private async ensureConnected(timeoutMs: number = 5000): Promise<void> {
        if (!this.config) {
            throw new Error('SyncSocket not initialized');
        }

        // Create or poke the socket.
        this.connect();
        if (!this.socket) {
            throw new Error('Socket not connected');
        }
        if (this.socket.connected) {
            this.dlog('ensureConnected: already connected');
            return;
        }

        // Deduplicate concurrent waiters.
        if (this.connectPromise) {
            this.dlog('ensureConnected: awaiting existing connectPromise');
            return await this.connectPromise;
        }

        this.updateStatus('connecting');
        this.dlog('ensureConnected: waiting for connect');
        this.socket.connect();

        this.connectPromise = new Promise<void>((resolve, reject) => {
            const socket = this.socket!;
            if (socket.connected) {
                this.dlog('ensureConnected: connected after connect() call');
                resolve();
                return;
            }
            let done = false;
            let timer: ReturnType<typeof setTimeout> | null = null;

            const cleanup = () => {
                socket.off('connect', onConnect);
                socket.off('connect_error', onError);
                socket.off('error', onError);
                if (timer) {
                    clearTimeout(timer);
                    timer = null;
                }
            };

            const finish = (fn: () => void) => {
                if (done) return;
                done = true;
                cleanup();
                fn();
            };

            const onConnect = () => {
                this.dlog('ensureConnected: socket connect event');
                finish(resolve);
            };
            const onError = (err: any) => {
                this.dlog('ensureConnected: socket error event', err instanceof Error ? err.message : err);
                finish(() => reject(err instanceof Error ? err : new Error(String(err))));
            };

            socket.once('connect', onConnect);
            socket.once('connect_error', onError);
            socket.once('error', onError);

            timer = setTimeout(() => {
                this.dlog('ensureConnected: timeout');
                finish(() => reject(new Error('Socket not connected')));
            }, timeoutMs);
        }).finally(() => {
            this.connectPromise = null;
        });

        return await this.connectPromise;
    }

    disconnect() {
        if (this.socket) {
            this.socket.disconnect();
            this.socket = null;
        }
        this.updateStatus('disconnected');
    }

    //
    // Listener Management
    //

    onReconnected = (listener: () => void) => {
        this.reconnectedListeners.add(listener);
        return () => this.reconnectedListeners.delete(listener);
    };

    onStatusChange = (listener: (status: 'disconnected' | 'connecting' | 'connected' | 'error') => void) => {
        this.statusListeners.add(listener);
        // Immediately notify with current status
        listener(this.currentStatus);
        return () => this.statusListeners.delete(listener);
    };

    //
    // Message Handling
    //

    onMessage(event: string, handler: (data: any) => void) {
        this.messageHandlers.set(event, handler);
        return () => this.messageHandlers.delete(event);
    }

    offMessage(event: string, handler: (data: any) => void) {
        this.messageHandlers.delete(event);
    }

    /**
     * RPC call for sessions - uses session-specific encryption
     */
    async sessionRPC<R, A>(sessionId: string, method: string, params: A): Promise<R> {
        this.dlog('sessionRPC: start', { sessionId, method });
        await this.ensureConnected();
        const socket = this.socket;
        if (!socket) {
            throw new Error('Socket not connected');
        }
        if (!this.encryption) {
            throw new Error('SyncSocket not initialized');
        }

        const sessionEncryption = this.encryption.getSessionEncryption(sessionId);
        if (!sessionEncryption) {
            throw new Error(`Session encryption not found for ${sessionId}`);
        }
        
        const ackTimeoutMs =
            method === 'bash'
                ? (typeof (params as any)?.timeout === 'number' && (params as any).timeout > 0
                    ? (params as any).timeout + 60000
                    : 10 * 60 * 1000)
                : 30000;

        const result: any = await socket.timeout(ackTimeoutMs).emitWithAck('rpc-call', {
            method: `${sessionId}:${method}`,
            params: await sessionEncryption.encryptRaw(params)
        });
        
        if (result && typeof result === 'object' && result.ok) {
            this.dlog('sessionRPC: ok', { sessionId, method });
            return await sessionEncryption.decryptRaw(result.result) as R;
        }
        const err =
            result && typeof result === 'object' && typeof result.error === 'string' && result.error.trim()
                ? result.error.trim()
                : 'RPC call failed';
        const endpoint = this.config?.endpoint ? ` @ ${this.config.endpoint}` : '';
        this.dlog('sessionRPC: failed', { sessionId, method, err });
        throw new Error(`RPC call failed (session:${sessionId}:${method})${endpoint}: ${err}`);
    }

    /**
     * RPC call for machines - uses legacy/global encryption (for now)
     */
    async machineRPC<R, A>(machineId: string, method: string, params: A): Promise<R> {
        this.dlog('machineRPC: start', { machineId, method });
        await this.ensureConnected();
        const socket = this.socket;
        if (!socket) {
            throw new Error('Socket not connected');
        }
        if (!this.encryption) {
            throw new Error('SyncSocket not initialized');
        }

        const machineEncryption = this.encryption.getMachineEncryption(machineId);
        if (!machineEncryption) {
            throw new Error(`Machine encryption not found for ${machineId}`);
        }

        const ackTimeoutMs =
            method === 'bash'
                ? (typeof (params as any)?.timeout === 'number' && (params as any).timeout > 0
                    ? (params as any).timeout + 60000
                    : 10 * 60 * 1000)
                : 30000;

        const result: any = await socket.timeout(ackTimeoutMs).emitWithAck('rpc-call', {
            method: `${machineId}:${method}`,
            params: await machineEncryption.encryptRaw(params)
        });

        if (result && typeof result === 'object' && result.ok) {
            this.dlog('machineRPC: ok', { machineId, method });
            return await machineEncryption.decryptRaw(result.result) as R;
        }
        const err =
            result && typeof result === 'object' && typeof result.error === 'string' && result.error.trim()
                ? result.error.trim()
                : 'RPC call failed';
        const endpoint = this.config?.endpoint ? ` @ ${this.config.endpoint}` : '';
        this.dlog('machineRPC: failed', { machineId, method, err });
        throw new Error(`RPC call failed (machine:${machineId}:${method})${endpoint}: ${err}`);
    }

    send(event: string, data: any) {
        this.socket!.emit(event, data);
        return true;
    }

    async emitWithAck<T = any>(event: string, data: any): Promise<T> {
        if (!this.socket) {
            throw new Error('Socket not connected');
        }
        return await this.socket.emitWithAck(event, data);
    }

    //
    // HTTP Requests
    //

    async request(path: string, options?: RequestInit): Promise<Response> {
        if (!this.config) {
            throw new Error('SyncSocket not initialized');
        }

        const credentials = await TokenStorage.getCredentials();
        if (!credentials) {
            throw new Error('No authentication credentials');
        }

        const url = `${this.config.endpoint}${path}`;
        const headers = {
            'Authorization': `Bearer ${credentials.token}`,
            ...options?.headers
        };

        return fetch(url, {
            ...options,
            headers
        });
    }

    //
    // Token Management
    //

    updateToken(newToken: string) {
        if (this.config && this.config.token !== newToken) {
            this.config.token = newToken;

            if (this.socket) {
                this.disconnect();
                this.connect();
            }
        }
    }

    //
    // Private Methods
    //

    private updateStatus(status: 'disconnected' | 'connecting' | 'connected' | 'error') {
        if (this.currentStatus !== status) {
            this.currentStatus = status;
            this.statusListeners.forEach(listener => listener(status));
        }
    }

    private setupEventHandlers() {
        if (!this.socket) return;

        // Connection events
        this.socket.on('connect', () => {
            // console.log('🔌 SyncSocket: Connected, recovered: ' + this.socket?.recovered);
            // console.log('🔌 SyncSocket: Socket ID:', this.socket?.id);
            this.updateStatus('connected');
            this.dlog('socket connect', { recovered: (this.socket as any)?.recovered });
            if (!this.socket?.recovered) {
                this.reconnectedListeners.forEach(listener => listener());
            }
        });

        this.socket.on('disconnect', (reason) => {
            // console.log('🔌 SyncSocket: Disconnected', reason);
            this.updateStatus('disconnected');
            this.dlog('socket disconnect', { reason });
        });

        // Error events
        this.socket.on('connect_error', (error) => {
            // console.error('🔌 SyncSocket: Connection error', error);
            this.updateStatus('error');
            this.dlog('socket connect_error', error instanceof Error ? error.message : error);
        });

        this.socket.on('error', (error) => {
            // console.error('🔌 SyncSocket: Error', error);
            this.updateStatus('error');
            this.dlog('socket error', error instanceof Error ? error.message : error);
        });

        // Message handling
        this.socket.onAny((event, data) => {
            // console.log(`📥 SyncSocket: Received event '${event}':`, JSON.stringify(data).substring(0, 200));
            const handler = this.messageHandlers.get(event);
            if (handler) {
                // console.log(`📥 SyncSocket: Calling handler for '${event}'`);
                handler(data);
            } else {
                // console.log(`📥 SyncSocket: No handler registered for '${event}'`);
            }
        });
    }
}

//
// Singleton Export
//

export const apiSocket = new ApiSocket();
