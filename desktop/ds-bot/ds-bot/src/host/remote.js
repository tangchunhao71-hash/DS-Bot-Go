// Modified for DS Bot Go mobile compatibility on 2026-11-04 / 2026-11-05. Original DS Bot copyright and Apache-2.0 terms are retained; see LICENSE, NOTICE and the repository MODIFICATIONS.md.
// DSH Go's mobile channel carried by the existing authenticated Typert Gateway.
import { Remote, RemoteError, TypertRemoteService } from '@deepseek-ai/dsh-typert-protocol'
import { withMobileMaintenance } from './mobile-maintenance.js'

export const RPC_NAMESPACE = 'dsBot'
export const REMOTE_ENDPOINTS = Object.freeze([
  'hello', 'state', 'avatar', 'chat', 'room-chat', 'send', 'file-text', 'duplicate-bot',
  'create-bot', 'update-bot', 'folders', 'update-room', 'delete-bot', 'set-main',
  'create-room', 'delete-room', 'room-continue', 'stop-member-work', 'approval-answer',
  'answer-question', 'dismiss-question', 'view-reply', 'dismiss-view', 'memory-view',
  'memory-forget', 'memory-edit', 'memory-add', 'usage-summary', 'notices',
  'schedules', 'schedule-create', 'schedule-delete',
])
const allowed = new Set(REMOTE_ENDPOINTS)
const MAX_QUEUED = 512
const fail = (code, message) => ({ ok: false, error: { code, message, details: {} } })
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value)
const plain = value => (value === undefined ? null : JSON.parse(JSON.stringify(value)))

function decorate(Class, name, decorator) {
  const initializers = []
  decorator(Class.prototype[name], {
    kind: 'method', name, static: false, private: false, metadata: {}, addInitializer: initializer => initializers.push(initializer),
  })
  return initializers
}

// The Gateway supplies invocation on the derived receiver Context, never in wire args.
function ownerSignal(ctx, signal, lifetime) {
  const invocation = ctx.invocation
  if (invocation?.peer?.principal?.kind !== 'owner') {
    throw new RemoteError('gateway/invocation-unavailable', 'An authenticated owner Peer is required.', {})
  }
  const signals = [invocation.signal, invocation.peer.signal, signal, lifetime].filter(Boolean)
  const combined = AbortSignal.any(signals)
  combined.throwIfAborted()
  return combined
}

export async function* feedEvents(subscribe, signal) {
  if (signal?.aborted) return
  const queue = []
  let wake
  let overflow = false
  let unsubscribe
  unsubscribe = subscribe((event, data) => {
    if (queue.length >= MAX_QUEUED) {
      overflow = true
      unsubscribe?.()
    }
    else queue.push({ event, data: plain(data) })
    wake?.()
  })
  if (overflow) unsubscribe()
  const aborted = () => wake?.()
  signal?.addEventListener('abort', aborted, { once: true })
  try {
    while (signal?.aborted !== true && !overflow) {
      if (queue.length === 0) await new Promise((resolve) => { wake = resolve })
      wake = undefined
      while (queue.length > 0 && signal?.aborted !== true) yield queue.shift()
    }
  } finally {
    signal?.removeEventListener('abort', aborted)
    unsubscribe()
  }
}

export function createRemoteService(rt) {
  class DsBotRemote extends TypertRemoteService {
    constructor(ctx) {
      super(ctx, RPC_NAMESPACE)
      for (const initializer of initializers) initializer.call(this)
      ctx.effect(() => {
        rt.remoteReady = true
        return () => { rt.remoteReady = false }
      }, 'ds-bot: mobile Remote availability')
    }

    async call(endpoint, payload, signal) {
      const lifetime = ownerSignal(this.ctx, signal)
      if (!allowed.has(endpoint)) return fail('bot/forbidden', 'This operation is not available through the mobile Remote API.')
      const body = payload ?? {}
      if (!object(body) || ['peer', 'principal', 'invocation'].some(key => Object.hasOwn(body, key))) {
        return fail('bot/invalid', 'The mobile payload must be an object without caller identity fields.')
      }
      if (endpoint === 'approval-answer' && !['allow', 'reject'].includes(body.choice)) {
        return fail('bot/invalid', 'Mobile approval answers allow or reject this request only.')
      }
      return withMobileMaintenance(this.ctx, async () => plain(await rt.channelCall(endpoint, body, lifetime)), { signal: lifetime })
    }

    async *feed(signal) {
      const lifetime = ownerSignal(this.ctx, signal, rt.feedSignal)
      yield* await withMobileMaintenance(this.ctx, () => feedEvents(rt.subscribeFeed, lifetime), { signal: lifetime, feed: true })
    }
  }
  const initializers = [...decorate(DsBotRemote, 'call', Remote), ...decorate(DsBotRemote, 'feed', Remote({ mode: 'stream' }))]
  return DsBotRemote
}

export function install(rt) {
  if (typeof rt.ctx.inject !== 'function') return
  // Do not return the fork: Cordis would await it before starting its dependency.
  rt.ctx.inject(['typertGateway'], (ctx) => { ctx.plugin(createRemoteService(rt)) })
}
