// Modified for DS Bot Go mobile compatibility on 2026-11-04 / 2026-11-05. Original DS Bot copyright and Apache-2.0 terms are retained; see LICENSE, NOTICE and the repository MODIFICATIONS.md.
import { IncomingMessage, ServerResponse } from 'node:http'
import { Duplex } from 'node:stream'
import { RemoteError } from '@deepseek-ai/dsh-typert-protocol'

const refused = () => new RemoteError('gateway/invocation-unavailable', 'The Host did not admit the mobile operation.', {})

// Remote calls have no HTTP request, but still enter the Host's public request
// waterfall so profile maintenance can hold or refuse them before admission.
// No socket is opened and authentication is already fixed by invocation.peer.
export async function withMobileMaintenance(ctx, dispatch, { signal, feed = false } = {}) {
  signal?.throwIfAborted()
  const socket = new Duplex({ read() {}, write(_chunk, _encoding, done) { done() } })
  socket.on('error', () => {})
  const request = new IncomingMessage(socket)
  request.method = feed ? 'GET' : 'POST'
  request.url = feed ? '/api/bot/feed' : '/api/bot'
  request.headers = { 'x-ds-bot-carrier': 'dsh-go-remote' }
  request.complete = true
  request.push(null)
  const response = new ServerResponse(request)
  response.on('error', () => {})
  response.assignSocket(socket)
  let delegated = false
  let completed = false
  let value
  let abortListener
  try {
    const work = Promise.resolve().then(() => ctx.waterfall('connection/request', request, response, async () => {
      signal?.throwIfAborted()
      if (delegated || response.headersSent || response.writableEnded || response.statusCode >= 400) throw refused()
      delegated = true
      value = await dispatch()
      completed = true
      if (!response.writableEnded) response.end()
    }))
    const aborted = new Promise((_, reject) => {
      abortListener = () => reject(signal.reason)
      signal?.addEventListener('abort', abortListener, { once: true })
      if (signal?.aborted) abortListener()
    })
    try { await (signal ? Promise.race([work, aborted]) : work) }
    catch (error) {
      // A later middleware failure cannot retract an operation already admitted.
      if (!completed) throw error
    }
    if (!delegated || !completed) throw refused()
    return value
  } finally {
    signal?.removeEventListener('abort', abortListener)
    request.destroy()
    response.destroy()
    socket.destroy()
  }
}
