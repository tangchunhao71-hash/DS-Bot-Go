// Modified for DS Bot Go mobile compatibility on 2026-11-04 / 2026-11-05. Original DS Bot copyright and Apache-2.0 terms are retained; see LICENSE, NOTICE and the repository MODIFICATIONS.md.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { Context } from '@deepseek-ai/cordis'
import { Peer } from '@deepseek-ai/dsh-client-connection'
import { TypertRegistry } from '@deepseek-ai/dsh-typert-registry'
import { RemoteAccessService } from '@deepseek-ai/dsh-api-remote-access'
import { TypertGatewayService } from '@deepseek-ai/dsh-api-gateway'
import { remoteMethods } from '@deepseek-ai/dsh-typert-protocol'
import { RPC_NAMESPACE, REMOTE_ENDPOINTS, createRemoteService, feedEvents } from '../src/host/remote.js'

function fakeFeed() {
  const listeners = new Set()
  return {
    listeners,
    subscribe(listener) {
      listeners.add(listener)
      listener('hello', { revision: 1, api: 1, boot: 'b', seq: 0 })
      return () => listeners.delete(listener)
    },
    emit: (event, data) => { for (const listener of listeners) listener(event, data) },
  }
}

async function start(t) {
  const feed = fakeFeed()
  const calls = []
  const lifetime = new AbortController()
  const rt = {
    channelCall: async (endpoint, payload, signal) => {
      calls.push({ endpoint, payload, signal })
      return { ok: true, value: { endpoint, kept: payload.kept, dropped: undefined } }
    },
    subscribeFeed: feed.subscribe,
    feedSignal: lifetime.signal,
  }
  const ctx = new Context()
  const fibers = [ctx.plugin(TypertRegistry), ctx.plugin(RemoteAccessService)]
  await Promise.all(fibers)
  const gateway = ctx.plugin(TypertGatewayService)
  fibers.push(gateway)
  await gateway
  const fiber = ctx.plugin(createRemoteService(rt))
  fibers.push(fiber)
  await fiber
  const owner = new Peer(ctx, { principal: { kind: 'owner' }, interactions: 'none' })
  const guest = new Peer(ctx, { principal: { kind: 'mobile-test' }, interactions: 'none' })
  t.after(async () => {
    lifetime.abort()
    await Promise.all([owner.dispose(), guest.dispose()])
    for (const current of fibers.reverse()) await current.dispose()
  })
  const invoke = (endpoint, payload = {}, { peer = owner, signal, extra = {} } = {}) => ctx.typertGateway.invoke({
    namespace: RPC_NAMESPACE, method: 'call', args: { endpoint, payload, ...extra }, peer, signal,
  })
  const stream = ({ peer = owner, signal } = {}) => ctx.typertGateway.stream({
    namespace: RPC_NAMESPACE, method: 'feed', args: {}, peer, signal,
  })
  return { feed, rt, calls, ctx, owner, guest, invoke, stream, fiber, lifetime }
}

test('the real Gateway dispatches mobile methods with its authenticated owner invocation', async (t) => {
  const { ctx, invoke, stream, calls, feed, rt, fiber } = await start(t)
  const service = ctx.get(RPC_NAMESPACE)
  assert.equal(service.typertRemote.namespace, RPC_NAMESPACE)
  assert.deepEqual(remoteMethods(service).map(marker => [marker.method, marker.mode ?? 'unary']), [['call', 'unary'], ['feed', 'stream']])
  assert.equal(rt.remoteReady, true)
  assert.deepEqual(await invoke('hello', { kept: 1 }), { ok: true, value: { endpoint: 'hello', kept: 1 } })
  assert.equal(calls[0].signal instanceof AbortSignal, true)
  // A local Service reference has no authenticated invocation. Payload identity cannot supply one.
  await assert.rejects(service.call('hello', { principal: { kind: 'owner' } }), { code: 'gateway/invocation-unavailable' })

  const abort = new AbortController()
  const iterator = (await stream({ signal: abort.signal }))[Symbol.asyncIterator]()
  assert.deepEqual((await iterator.next()).value, { event: 'hello', data: { revision: 1, api: 1, boot: 'b', seq: 0 } })
  feed.emit('notice', { seq: 1, kind: 'message', text: 'hi', extra: undefined })
  assert.deepEqual((await iterator.next()).value, { event: 'notice', data: { seq: 1, kind: 'message', text: 'hi' } })
  const pending = iterator.next()
  abort.abort()
  await assert.rejects(pending, { code: 'gateway/cancelled' })
  assert.equal(feed.listeners.size, 0)
  await fiber.dispose()
  assert.equal(rt.remoteReady, false)
})

test('non-owner, missing, disposed and forged invocation identities never dispatch or subscribe', async (t) => {
  const { invoke, stream, guest, owner, calls, feed } = await start(t)
  for (const endpoint of ['hello', 'schedules', 'schedule-create', 'schedule-delete']) {
    await assert.rejects(invoke(endpoint, {}, { peer: guest }), { code: 'remote-access/denied' })
  }
  await assert.rejects(stream({ peer: guest }), { code: 'remote-access/denied' })
  // A direct caller violating the Gateway's required Peer type also fails before dispatch.
  await assert.rejects(invoke('hello', {}, { peer: null }), { name: 'TypeError' })
  await assert.rejects(invoke('hello', {}, { extra: { peer: { principal: { kind: 'owner' } } } }), error => error.code.startsWith('gateway/'))
  assert.equal((await invoke('hello', { principal: { kind: 'owner' } })).error.code, 'bot/invalid')
  await owner.dispose()
  await assert.rejects(invoke('hello'), { code: 'gateway/peer-disposed' })
  assert.equal(calls.length, 0)
  assert.equal(feed.listeners.size, 0)
})

test('the Remote channel admits the mobile actions and refuses settings, secrets and persistent approvals', async (t) => {
  const { invoke, calls } = await start(t)
  assert.equal(REMOTE_ENDPOINTS.length, 32)
  for (const endpoint of REMOTE_ENDPOINTS) {
    const answer = await invoke(endpoint, endpoint === 'approval-answer' ? { choice: 'allow' } : {})
    assert.equal(answer.ok, true, endpoint)
  }
  for (const endpoint of ['provider-key', 'secret-set', 'settings-update', 'im-action', 'browser-command', 'unknown']) {
    assert.equal((await invoke(endpoint)).error.code, 'bot/forbidden', endpoint)
  }
  for (const choice of ['always', 'allow_session', 'allowed-once', null]) {
    assert.equal((await invoke('approval-answer', { choice })).error.code, 'bot/invalid')
  }
  assert.equal((await invoke('hello', [])).error.code, 'bot/invalid')
  assert.equal(calls.length, 32)
})

test('schedule list, create and delete preserve the native view and dispatch once', async (t) => {
  const { invoke, rt, calls } = await start(t)
  const task = { id: 'task-1', sessionId: 'bot-session', botId: 'bot-1', title: 'Fixture task', prompt: 'Fixture prompt', kind: 'daily', time: '09:00', timeZone: 'Asia/Shanghai', status: 'active', state: 'scheduled' }
  const full = { available: true, tasks: [task] }
  const empty = { available: true, tasks: [] }
  const cases = [
    ['schedules', {}, full],
    ['schedule-create', { target: 'bot-1', title: task.title, prompt: task.prompt, when: { kind: 'daily', time: task.time, timeZone: task.timeZone } }, full],
    ['schedule-delete', { sessionId: task.sessionId, id: task.id }, empty],
  ]
  for (const [endpoint, payload, value] of cases) {
    rt.channelCall = async (operation, body, signal) => {
      calls.push({ endpoint: operation, payload: body, signal })
      return { ok: true, value }
    }
    const before = calls.length
    assert.deepEqual(await invoke(endpoint, payload), { ok: true, value }, endpoint)
    assert.equal(calls.length, before + 1, endpoint)
    assert.equal(calls.at(-1).endpoint, endpoint)
    assert.deepEqual(calls.at(-1).payload, payload)
    assert.equal(calls.at(-1).signal instanceof AbortSignal, true)
  }
})

test('a refused schedule mutation or an unknown completion is never replayed', async (t) => {
  const { invoke, rt, calls } = await start(t)
  for (const endpoint of ['schedule-create', 'schedule-delete']) {
    const refusal = { ok: false, error: { code: 'bot/read-only', message: 'Team is read-only.', details: {} } }
    rt.channelCall = async (operation, payload, signal) => {
      calls.push({ endpoint: operation, payload, signal })
      return refusal
    }
    let before = calls.length
    assert.deepEqual(await invoke(endpoint, {}), refusal)
    assert.equal(calls.length, before + 1)
    rt.channelCall = async (operation, payload, signal) => {
      calls.push({ endpoint: operation, payload, signal })
      throw new Error('Fixture completion unknown after dispatch')
    }
    before = calls.length
    await assert.rejects(invoke(endpoint, {}))
    await new Promise(resolve => setImmediate(resolve))
    assert.equal(calls.length, before + 1, `${endpoint} must not be retried`)
  }
})

test('peer disposal, plugin disposal and pre-aborted calls end their own work', async (t) => {
  const { invoke, stream, owner, feed, calls, lifetime } = await start(t)
  const abort = AbortSignal.abort()
  await assert.rejects(invoke('send', {}, { signal: abort }), error => error.code === 'gateway/cancelled' || error.name === 'AbortError')
  assert.equal(calls.length, 0)

  const iterator = (await stream())[Symbol.asyncIterator]()
  await iterator.next()
  const pending = iterator.next()
  await owner.dispose()
  await assert.rejects(pending, { code: 'gateway/cancelled' })
  assert.equal(feed.listeners.size, 0)

  const source = feedEvents(feed.subscribe, lifetime.signal)[Symbol.asyncIterator]()
  await source.next()
  const wait = source.next()
  lifetime.abort()
  assert.equal((await wait).done, true)
  assert.equal(feed.listeners.size, 0)
})

test('a slow reader is unsubscribed at the queue bound, then reconnects with a fresh hello', async () => {
  const feed = fakeFeed()
  const iterator = feedEvents(feed.subscribe, new AbortController().signal)[Symbol.asyncIterator]()
  assert.equal((await iterator.next()).value.event, 'hello')
  for (let index = 0; index < 600; index += 1) feed.emit('live', {})
  assert.equal(feed.listeners.size, 0)
  let count = 0
  while (!(await iterator.next()).done) count += 1
  assert.equal(count > 0 && count <= 512, true)
  const fresh = feedEvents(feed.subscribe, new AbortController().signal)[Symbol.asyncIterator]()
  assert.equal((await fresh.next()).value.event, 'hello')
  await fresh.return()
  assert.equal(feed.listeners.size, 0)
})

test('an already cancelled feed never subscribes', async () => {
  const feed = fakeFeed()
  const iterator = feedEvents(feed.subscribe, AbortSignal.abort())[Symbol.asyncIterator]()
  assert.equal((await iterator.next()).done, true)
  assert.equal(feed.listeners.size, 0)
})

test('the normal Host maintenance waterfall can refuse Remote calls and feed admission', async (t) => {
  const { ctx, invoke, stream, calls, feed } = await start(t)
  const admitted = []
  ctx.on('connection/request', (request, response) => {
    admitted.push([request.method, request.url, request.headers['x-ds-bot-carrier']])
    response.statusCode = 503
    response.end()
  })
  await assert.rejects(invoke('send', { text: 'must not run' }), { code: 'gateway/invocation-unavailable' })
  const blocked = (await stream())[Symbol.asyncIterator]()
  await assert.rejects(blocked.next(), { code: 'gateway/invocation-unavailable' })
  assert.deepEqual(admitted, [['POST', '/api/bot', 'dsh-go-remote'], ['GET', '/api/bot/feed', 'dsh-go-remote']])
  assert.equal(calls.length, 0)
  assert.equal(feed.listeners.size, 0)
})

test('cancelling a call held by maintenance prevents later dispatch when the gate resumes', async (t) => {
  const { ctx, invoke, calls } = await start(t)
  let entered
  let resume
  const waiting = new Promise(resolve => { entered = resolve })
  ctx.on('connection/request', (_request, _response, next) => new Promise((resolve, reject) => {
    resume = () => Promise.resolve().then(next).then(resolve, reject)
    entered()
  }))
  const abort = new AbortController()
  const pending = invoke('send', { text: 'must not run' }, { signal: abort.signal })
  await waiting
  abort.abort()
  await assert.rejects(pending, error => error.code === 'gateway/cancelled' || error.name === 'AbortError')
  await resume()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(calls.length, 0)
})
