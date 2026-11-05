# DS Bot mobile API over Remote

This local compatibility change enables the existing `DsBotRpcTransport` through
the encrypted Remote carrier. It requires a Host with DS Bot mobile API v1 and a
Remote Host plugin that permits `dsBot/call` and `dsBot/feed`. Older Hosts continue
to report their refusal; adding the two client endpoints does not grant access to
unlisted methods or replace the Host's device authentication and Bot action policy.

`dsBot/call` can create Bots, send messages, change memory and answer approvals.
When a Host reports `RESPONSE_TOO_LARGE`, it has already invoked the operation.
The carrier therefore surfaces this error without replaying the call through the
chunked-transfer path. A caller must inspect the resulting state before deciding
whether to try a mutation again. Requests that were initially large still use one
transfer and one invocation.

The Remote tests exercise the public Bot API through the existing synthetic
account, Noise handshake and encrypted tunnel: API v1 negotiation, typed group
messages, feed delivery/cancellation, reconnect with a fresh hello, legacy Host
refusal, and an oversized mutation response that executes exactly once. The fake
Host clears its publishing socket before awaiting close so late stream cleanup
does not publish to a closing test socket.

Validation uses the pinned package lockfiles and Dart 3.13.7. Native Android,
PRoot and real-account connection behavior still require an APK/device check;
pure Dart test results do not establish those boundaries.
