import WebSocket, { type RawData } from 'ws'

import { configuration } from '@/configuration'
import { logger } from '@/ui/logger'
import {
  createMachineDataPlaneHello,
  deriveMachineDataPlaneSessionKey,
  isMachineDataPlaneHelloAckFrame,
  machineDataPlaneCompleteAAD,
  machineDataPlaneRequestAAD,
  openMachineDataPlaneJSON,
  sealMachineDataPlaneJSON,
} from './machineDataPlaneCrypto'
import {
  MACHINE_DATA_PLANE_PROTOCOL_VERSION,
  MACHINE_DATA_PLANE_SUBPROTOCOL,
  type MachineDataPlaneCompleteFrame,
  type MachineDataPlaneErrorFrame,
  type MachineDataPlaneFrame,
  type MachineDataPlaneRequestFrame,
} from './machineDataPlaneProtocol'

type MachineDataPlaneClientOptions = {
  token: string
  machineId: string
  machineDataKey: Uint8Array
  invokeLocal: (method: string, params: unknown) => Promise<unknown>
}

const REQUEST_OPERATION_TO_METHOD: Record<string, string> = {
  'codex.listMessages': 'codex-list-messages',
}

export class MachineDataPlaneClient {
  private socket: WebSocket | null = null
  private sessionKey: Uint8Array | null = null
  private reconnectTimer: NodeJS.Timeout | null = null
  private shouldRun = false
  private localHandshake = createMachineDataPlaneHello('daemon')

  constructor(private readonly options: MachineDataPlaneClientOptions) {}

  connect(): void {
    if (this.shouldRun) {
      return
    }
    this.shouldRun = true
    this.openSocket()
  }

  shutdown(): void {
    this.shouldRun = false
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    this.sessionKey = null
    if (this.socket) {
      this.socket.close()
      this.socket = null
    }
  }

  private openSocket(): void {
    const url = new URL(configuration.serverUrl)
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'
    url.pathname = `/v1/machines/${encodeURIComponent(this.options.machineId)}/data-plane`
    url.search = ''

    this.localHandshake = createMachineDataPlaneHello('daemon')
    const socket = new WebSocket(url, MACHINE_DATA_PLANE_SUBPROTOCOL, {
      headers: {
        Authorization: `Bearer ${this.options.token}`,
      },
    })
    this.socket = socket

    socket.on('open', () => {
      logger.debug('[MACHINE DP] Connected websocket')
      socket.send(JSON.stringify(this.localHandshake.hello))
    })

    socket.on('message', async (raw: RawData) => {
      const text = typeof raw === 'string' ? raw : raw.toString('utf8')
      let frame: MachineDataPlaneFrame | unknown
      try {
        frame = JSON.parse(text)
      } catch (error) {
        logger.debug('[MACHINE DP] Failed to parse frame', error)
        return
      }

      try {
        await this.handleFrame(frame)
      } catch (error) {
        logger.debug('[MACHINE DP] Failed to handle frame', error)
      }
    })

    socket.on('close', () => {
      logger.debug('[MACHINE DP] Data-plane websocket closed')
      this.sessionKey = null
      this.socket = null
      if (!this.shouldRun) {
        return
      }
      this.reconnectTimer = setTimeout(() => {
        this.reconnectTimer = null
        this.openSocket()
      }, 1_000)
      this.reconnectTimer.unref?.()
    })

    socket.on('error', (error: Error) => {
      logger.debug('[MACHINE DP] Data-plane websocket error', error)
    })
  }

  private async handleFrame(frame: unknown): Promise<void> {
    if (isMachineDataPlaneHelloAckFrame(frame)) {
      this.sessionKey = deriveMachineDataPlaneSessionKey({
        machineDataKey: this.options.machineDataKey,
        localPrivateKey: this.localHandshake.localHandshake.privateKey,
        localNonceBase64URL: this.localHandshake.localHandshake.nonceBase64URL,
        peerKeyExchange: frame.keyExchange,
        role: 'daemon',
      })
      logger.debug('[MACHINE DP] Handshake complete', { sessionId: frame.sessionId })
      return
    }

    if (!this.sessionKey) {
      return
    }

    const candidate = frame as Partial<MachineDataPlaneFrame>
    if (candidate.t !== 'request' || typeof candidate.streamId !== 'string') {
      return
    }

    await this.handleRequest(candidate as MachineDataPlaneRequestFrame)
  }

  private async handleRequest(frame: MachineDataPlaneRequestFrame): Promise<void> {
    const socket = this.socket
    const sessionKey = this.sessionKey
    if (!socket || socket.readyState !== WebSocket.OPEN || !sessionKey) {
      return
    }

    const method = REQUEST_OPERATION_TO_METHOD[frame.op]
    if (!method) {
      const errorFrame: MachineDataPlaneErrorFrame = {
        v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
        t: 'error',
        streamId: frame.streamId,
        code: 'unsupported_operation',
        message: `Unsupported operation: ${frame.op}`,
        retryable: false,
      }
      socket.send(JSON.stringify(errorFrame))
      return
    }

    try {
      const params = openMachineDataPlaneJSON<Record<string, unknown>>(
        frame.body,
        sessionKey,
        machineDataPlaneRequestAAD(frame),
      )
      const result = await this.options.invokeLocal(method, params)

      const completeHeader: Omit<MachineDataPlaneCompleteFrame, 'body'> = {
        v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
        t: 'complete',
        streamId: frame.streamId,
        seq: 0,
        hasMore: typeof (result as { hasNext?: unknown })?.hasNext === 'boolean'
          ? Boolean((result as { hasNext?: unknown }).hasNext)
          : undefined,
        nextCursor: typeof (result as { nextCursor?: unknown })?.nextCursor === 'string'
          ? String((result as { nextCursor?: unknown }).nextCursor)
          : undefined,
      }
      const sealedBody = sealMachineDataPlaneJSON(
        result,
        sessionKey,
        machineDataPlaneCompleteAAD(completeHeader),
      )
      const completeFrame: MachineDataPlaneCompleteFrame = {
        ...completeHeader,
        body: sealedBody,
      }
      socket.send(JSON.stringify(completeFrame))
    } catch (error) {
      const errorFrame: MachineDataPlaneErrorFrame = {
        v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
        t: 'error',
        streamId: frame.streamId,
        code: 'request_failed',
        message: error instanceof Error ? error.message : 'Machine data-plane request failed',
        retryable: false,
      }
      socket.send(JSON.stringify(errorFrame))
    }
  }
}
