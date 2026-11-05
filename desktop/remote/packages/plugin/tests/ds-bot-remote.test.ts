import { randomUUID } from 'node:crypto'
import { createEvent, createRpcRequest, type RemoteMessage } from '@dsh-remote/protocol'
import { describe, expect, it, vi } from 'vitest'
import { runScenarios } from '../../../scripts/test-scenarios.mjs'
import { ConnectionController } from '../src/connection-controller.js'
import { HarnessRemoteBridge } from '../src/harness-remote-bridge.js'
import { RpcRouter } from '../src/rpc-router.js'
import type { IdentityStore } from '../src/identity-store.js'
import type { LocalTypertGateway } from '../src/typert-gateway-contract.js'
import type { AuthenticatedPeerChannel } from '../src/types.js'

const hello = { event: 'hello', data: { api: 1, revision: 4, boot: 'boot-1', seq: 0 } }
const botCall = (endpoint: string, payload: Record<string, unknown> = {}) => ({
  endpoint: 'dsBot/call', payload: { args: { endpoint, payload } },
})

describe('DS Bot Remote mobile API', () => {
  it('preserves native handshake, mutations and Bot refusals without replay', async () => {
    await runScenarios([
      { name: 'handshake', endpoint: 'hello', body: { api: [1] }, value: { ok: true, value: { api: 1, capabilities: ['chat', 'rpc'] } } },
      { name: 'send once', endpoint: 'send', body: { sessionId: 'bot-1', text: 'fixture message' }, value: { ok: true, value: true } },
      { name: 'edit memory', endpoint: 'memory-edit', body: { botId: 'bot-1', text: 'before', next: 'after' }, value: { ok: true, value: { entries: [] } } },
      { name: 'approve once', endpoint: 'approval-answer', body: { id: 'approval-1', choice: 'allow' }, value: { ok: true, value: true } },
      { name: 'read-only Bot', endpoint: 'create-bot', body: { name: 'fixture' }, value: { ok: false, error: { code: 'bot/read-only', message: 'Team is read-only.' } } },
      { name: 'list scheduled tasks', endpoint: 'schedules', body: {}, value: { ok: true, value: { available: true, tasks: [{ id: 'task-1', sessionId: 'bot-session', botId: 'bot-1', state: 'scheduled' }] } } },
      { name: 'create scheduled task once', endpoint: 'schedule-create', body: { target: 'bot-1', title: 'Fixture task', prompt: 'Fixture prompt', when: { kind: 'daily', time: '09:00', timeZone: 'Asia/Shanghai' } }, value: { ok: true, value: { available: true, tasks: [{ id: 'task-1', sessionId: 'bot-session' }] } } },
      { name: 'delete scheduled task once', endpoint: 'schedule-delete', body: { sessionId: 'bot-session', id: 'task-1' }, value: { ok: true, value: { available: true, tasks: [] } } },
      { name: 'schedule service unavailable', endpoint: 'schedules', body: {}, value: { ok: true, value: { available: false, tasks: [] } } },
      { name: 'read-only schedule refusal', endpoint: 'schedule-create', body: { target: 'bot-1' }, value: { ok: false, error: { code: 'bot/read-only', message: 'Team is read-only.' } } },
    ].map(({ name, endpoint, body, value }) => ({ name, run: async () => {
      const nativeResult = { ok: true as const, value }
      const dispatch = vi.fn(async () => nativeResult)
      const bridge = new HarnessRemoteBridge(gateway({ dispatch }), vi.fn())
      const request = botCall(endpoint, body)
      await expect(bridge.call(request)).resolves.toEqual(nativeResult)
      expect(dispatch).toHaveBeenCalledOnce()
      expect(dispatch).toHaveBeenCalledWith('dsBot/call', request.payload, expect.any(AbortSignal))
    } })))
  })

  it('rejects private actions, identity injection, persistent approval and wrong call forms before dispatch', async () => {
    await runScenarios([
      { name: 'unlisted Remote method', request: { endpoint: 'dsBot/arbitrary', payload: { args: {} } }, code: 'METHOD_NOT_ALLOWED' },
      { name: 'secret action', request: botCall('secret-set', { value: 'fixture' }), code: 'METHOD_NOT_ALLOWED' },
      { name: 'connector action', request: botCall('connector-connect'), code: 'METHOD_NOT_ALLOWED' },
      { name: 'browser control', request: botCall('browser-click'), code: 'METHOD_NOT_ALLOWED' },
      { name: 'persistent approval', request: botCall('approval-answer', { id: 'approval-1', choice: 'allow_session' }), code: 'PERMISSION_DENIED' },
      { name: 'carrier principal', request: { ...botCall('hello'), payload: { args: { endpoint: 'hello', payload: {} }, principal: { kind: 'owner' } } }, code: 'INVALID_MESSAGE' },
      { name: 'argument peer', request: { ...botCall('hello'), payload: { args: { endpoint: 'hello', payload: {}, peer: { principal: { kind: 'owner' } } } } }, code: 'INVALID_MESSAGE' },
      { name: 'payload principal', request: botCall('send', { principal: { kind: 'owner' } }), code: 'INVALID_MESSAGE' },
      { name: 'payload peer', request: botCall('send', { peer: { principal: { kind: 'owner' } } }), code: 'INVALID_MESSAGE' },
      { name: 'array body', request: { endpoint: 'dsBot/call', payload: { args: { endpoint: 'hello', payload: [] } } }, code: 'INVALID_MESSAGE' },
      { name: 'feed through unary', request: { endpoint: 'dsBot/feed', payload: { args: {} } }, code: 'METHOD_NOT_ALLOWED' },
    ].map(({ name, request, code }) => ({ name, run: async () => {
      const dispatch = vi.fn()
      const bridge = new HarnessRemoteBridge(gateway({ dispatch }), vi.fn())
      await expect(bridge.call(request)).rejects.toMatchObject({ code })
      expect(dispatch).not.toHaveBeenCalled()
    } })))
    await runScenarios([
      { name: 'call through stream', endpoint: 'dsBot/call', payload: { args: { endpoint: 'hello', payload: {} } }, code: 'METHOD_NOT_ALLOWED' },
      { name: 'feed with principal', endpoint: 'dsBot/feed', payload: { args: { principal: { kind: 'owner' } } }, code: 'INVALID_MESSAGE' },
    ].map(({ name, endpoint, payload, code }) => ({ name, run: async () => {
      const open = vi.fn()
      const bridge = new HarnessRemoteBridge(gateway({ open }), vi.fn())
      await expect(bridge.openStream({ streamId: 'fixture', endpoint, payload })).rejects.toMatchObject({ code })
      expect(open).not.toHaveBeenCalled()
    } })))
  })

  it('applies the same Bot policy to chunked calls and consumes a mutation transfer only once', async () => {
    await runScenarios([
      { name: 'valid transferred mutation', request: botCall('send', { sessionId: 'bot-1', text: 'fixture' }), code: undefined },
      { name: 'transferred schedule list', request: botCall('schedules'), code: undefined },
      { name: 'transferred schedule create', request: botCall('schedule-create', { target: 'bot-1', title: 'Fixture', prompt: 'Fixture', when: { kind: 'daily', time: '09:00' } }), code: undefined },
      { name: 'transferred schedule delete', request: botCall('schedule-delete', { sessionId: 'bot-session', id: 'task-1' }), code: undefined },
      { name: 'transferred private action', request: botCall('secret-set'), code: 'METHOD_NOT_ALLOWED' },
      { name: 'transferred caller injection', request: botCall('send', { principal: { kind: 'owner' } }), code: 'INVALID_MESSAGE' },
      { name: 'transferred persistent approval', request: botCall('approval-answer', { choice: 'allow_session' }), code: 'PERMISSION_DENIED' },
    ].map(({ name, request, code }) => ({ name, run: async () => {
      const dispatch = vi.fn(async () => ({ ok: true as const, value: { ok: true, value: true } }))
      const bridge = new HarnessRemoteBridge(gateway({ dispatch }), vi.fn())
      const transferId = randomUUID()
      const bytes = Buffer.from(JSON.stringify(request))
      bridge.openTransfer({ transferId, totalBytes: bytes.byteLength, totalChunks: 1 })
      bridge.appendTransfer({ transferId, index: 0, data: bytes.toString('base64') })
      if (code === undefined) {
        await expect(bridge.commitTransfer({ transferId })).resolves.toMatchObject({ kind: 'inline', response: { ok: true } })
        expect(dispatch).toHaveBeenCalledOnce()
      } else {
        await expect(bridge.commitTransfer({ transferId })).rejects.toMatchObject({ code })
        expect(dispatch).not.toHaveBeenCalled()
      }
      await expect(bridge.commitTransfer({ transferId })).rejects.toMatchObject({ code: 'TRANSFER_NOT_FOUND' })
      expect(dispatch).toHaveBeenCalledTimes(code === undefined ? 1 : 0)
    } })))
  })

  it('does not replay schedule mutations with unknown completion, including consumed transfers', async () => {
    await runScenarios(['schedule-create', 'schedule-delete'].flatMap(endpoint => [false, true].map(transferred => ({
      name: `${endpoint} unknown completion${transferred ? ' through transfer' : ''}`,
      run: async () => {
        const lost = new Error('Fixture completion unknown after dispatch')
        const dispatch = vi.fn(async () => { throw lost })
        const bridge = new HarnessRemoteBridge(gateway({ dispatch }), vi.fn())
        const request = botCall(endpoint, endpoint === 'schedule-delete'
          ? { sessionId: 'bot-session', id: 'task-1' }
          : { target: 'bot-1', title: 'Fixture', prompt: 'Fixture', when: { kind: 'daily', time: '09:00' } })
        if (transferred) {
          const transferId = randomUUID()
          const bytes = Buffer.from(JSON.stringify(request))
          bridge.openTransfer({ transferId, totalBytes: bytes.byteLength, totalChunks: 1 })
          bridge.appendTransfer({ transferId, index: 0, data: bytes.toString('base64') })
          await expect(bridge.commitTransfer({ transferId })).rejects.toBe(lost)
          await expect(bridge.commitTransfer({ transferId })).rejects.toMatchObject({ code: 'TRANSFER_NOT_FOUND' })
        } else {
          await expect(bridge.call(request)).rejects.toBe(lost)
        }
        await new Promise(resolve => setImmediate(resolve))
        expect(dispatch).toHaveBeenCalledOnce()
      },
    }))))
  })

  it('keeps Bot admission behind Noise, membership and local trust', async () => {
    await runScenarios([
      { name: 'missing Noise', security: undefined, trusted: true, code: 'SECURE_CHANNEL_FAILED' },
      { name: 'missing membership', security: { protocol: 'Noise_IK_25519_ChaChaPoly_SHA256', connectionId: 'fixture', membershipId: '' }, trusted: true, code: 'SECURE_CHANNEL_FAILED' },
      { name: 'untrusted device', security: { protocol: 'Noise_IK_25519_ChaChaPoly_SHA256', connectionId: 'fixture', membershipId: 'membership-1' }, trusted: false, code: 'PEER_IDENTITY_MISMATCH' },
    ].map(({ name, security, trusted, code }) => ({ name, run: async () => {
      const dispatch = vi.fn()
      const factory = vi.fn(() => new RpcRouter(128, undefined, undefined, new HarnessRemoteBridge(gateway({ dispatch }), vi.fn())))
      const controller = new ConnectionController({ isTrusted: () => trusted } as unknown as IdentityStore, factory)
      const channel = fakeChannel('fixture', 'phone')
      Object.assign(channel, { security })
      await expect(controller.accept(channel)).rejects.toMatchObject({ code })
      channel.push(createRpcRequest('harness.remote.call', botCall('hello')))
      expect(factory).not.toHaveBeenCalled()
      expect(dispatch).not.toHaveBeenCalled()
      expect(channel.close).toHaveBeenCalledWith(code)
      await controller.close()
    } })))
  })

  it('isolates Bot feeds by authenticated connection and releases them on cancel or disconnect', async () => {
    const subscriptions = new Map<string, { signal: AbortSignal; released: boolean }>()
    const controller = new ConnectionController(
      { isTrusted: () => true } as unknown as IdentityStore,
      ({ connectionId }, send) => {
        const open = async (_endpoint: string, _payload: unknown, signal: AbortSignal) => {
          const own = { signal, released: false }
          subscriptions.set(connectionId, own)
          return (async function* () {
            try {
              yield hello
              yield { event: 'notice', data: { seq: 1, kind: 'message', botId: 'bot-1', text: 'fixture' } }
              if (!signal.aborted) await new Promise<void>(resolve => signal.addEventListener('abort', () => resolve(), { once: true }))
            } finally { own.released = true }
          })()
        }
        return new RpcRouter(128, undefined, undefined, new HarnessRemoteBridge(
          gateway({ open }), (event, data) => send(createEvent(event, data)),
        ))
      },
    )
    const phone = fakeChannel('phone-link', 'phone')
    const tablet = fakeChannel('tablet-link', 'tablet')
    try {
      await controller.accept(phone)
      await controller.accept(tablet)
      const open = () => createRpcRequest('harness.remote.stream.open', { streamId: 'same-id', endpoint: 'dsBot/feed', payload: { args: {} } })
      phone.push(open())
      await vi.waitFor(() => expect(phone.send).toHaveBeenCalledWith(expect.objectContaining({
        payload: { event: 'harness.remote.frame', data: { streamId: 'same-id', hasValue: true, value: hello } },
      })))
      expect(tablet.send).not.toHaveBeenCalled()
      tablet.push(open())
      await vi.waitFor(() => expect(subscriptions.size).toBe(2))
      const tabletFrames = tablet.send.mock.calls.length
      phone.push(createRpcRequest('harness.remote.stream.close', { streamId: 'same-id' }))
      await vi.waitFor(() => expect(subscriptions.get('phone-link')?.released).toBe(true))
      expect(subscriptions.get('phone-link')?.signal.aborted).toBe(true)
      expect(subscriptions.get('tablet-link')?.signal.aborted).toBe(false)
      expect(tablet.send.mock.calls.length).toBeGreaterThanOrEqual(tabletFrames)
      await controller.closeConnection('tablet-link', 'CONNECTION_FAILED')
      await vi.waitFor(() => expect(subscriptions.get('tablet-link')?.released).toBe(true))
      expect(subscriptions.get('tablet-link')?.signal.aborted).toBe(true)
      expect(tablet.close).toHaveBeenCalledWith('CONNECTION_FAILED')
    } finally { await controller.close() }
  })
})

function gateway(overrides: Partial<LocalTypertGateway> = {}): LocalTypertGateway {
  return {
    invoke: async () => undefined,
    dispatch: async () => ({ ok: true }),
    open: async () => (async function* () { return })(),
    failure: () => ({ code: 'internal', message: 'Request failed.', details: {} }),
    supportsCarrier: true,
    ...overrides,
  }
}

function fakeChannel(connectionId: string, peerDeviceId: string): AuthenticatedPeerChannel & {
  send: ReturnType<typeof vi.fn>
  push(message: RemoteMessage): void
} {
  let handler: (message: RemoteMessage) => void = () => undefined
  return {
    security: { protocol: 'Noise_IK_25519_ChaChaPoly_SHA256', connectionId, membershipId: 'membership-1' },
    peerDeviceId,
    peerIdentityKey: `key-${peerDeviceId}`,
    send: vi.fn(async () => undefined),
    close: vi.fn(async () => undefined),
    onMessage: next => { handler = next; return () => { handler = () => undefined } },
    push: message => handler(message),
  }
}
