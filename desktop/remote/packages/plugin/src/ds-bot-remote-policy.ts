import { z } from 'zod'
import { RpcError } from './safe-error.js'

/** DSH Go's reviewed mobile API v1; other Bot control operations stay local. */
export const DS_BOT_REMOTE_OPERATIONS = [
  'hello', 'state', 'avatar', 'chat', 'room-chat', 'notices', 'usage-summary',
  'send', 'file-text', 'folders',
  'duplicate-bot', 'create-bot', 'update-bot', 'delete-bot', 'set-main',
  'create-room', 'update-room', 'delete-room', 'room-continue', 'stop-member-work',
  'approval-answer', 'answer-question', 'dismiss-question', 'view-reply', 'dismiss-view',
  'memory-view', 'memory-forget', 'memory-edit', 'memory-add',
  'schedules', 'schedule-create', 'schedule-delete',
] as const

const operations = new Set<string>(DS_BOT_REMOTE_OPERATIONS)
const argsSchema = z.object({
  endpoint: z.string().min(1).max(128),
  payload: z.record(z.string(), z.unknown()),
}).strict()
const callSchema = z.object({ args: argsSchema }).strict()
const feedSchema = z.object({ args: z.object({}).strict() }).strict()

/** A multiplexed Bot call must not turn one allowed namespace into arbitrary control. */
export function checkDsBotRemote(endpoint: string, payload: unknown, stream: boolean): void {
  if (endpoint !== 'dsBot/call' && endpoint !== 'dsBot/feed') return
  if ((endpoint === 'dsBot/feed') !== stream) {
    throw new RpcError('METHOD_NOT_ALLOWED', 'Use the declared call or stream form for this DS Bot endpoint.')
  }
  const parsed = (stream ? feedSchema : callSchema).safeParse(payload)
  if (!parsed.success) throw new RpcError('INVALID_MESSAGE', 'The DS Bot Remote arguments are invalid.')
  if (stream) return
  const { args } = callSchema.parse(payload)
  if (!operations.has(args.endpoint)) {
    throw new RpcError('METHOD_NOT_ALLOWED', 'This DS Bot operation is not allowed over Remote.')
  }
  if (Object.hasOwn(args.payload, 'peer') || Object.hasOwn(args.payload, 'principal')) {
    throw new RpcError('INVALID_MESSAGE', 'The caller identity is provided by the authenticated connection.')
  }
  if (args.endpoint === 'approval-answer' && args.payload.choice !== 'allow' && args.payload.choice !== 'reject') {
    throw new RpcError('PERMISSION_DENIED', 'Only one-time approval or rejection is supported.')
  }
}
