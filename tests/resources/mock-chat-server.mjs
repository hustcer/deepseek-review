// Mock chat completion endpoint used by tests/test-stream-e2e.nu.
//
// Nushell has no HTTP server, so the streaming path (`streaming-output`) could
// not be covered otherwise. Uses only `node:http` — no package.json, no deps.
//
// Usage: node mock-chat-server.mjs <mode> [request-dump-path]
//   sse     - a well formed SSE stream, reasoning first then content
//   sse1    - an SSE stream whose reasoning arrives as a single chunk
//   broken  - an SSE stream with a truncated JSON chunk in the middle
//   json    - a non streaming JSON completion, with reasoning_content
//   errjson - an error object instead of a completion
//
// When a request-dump-path is given the raw request body is written there, so
// tests can assert on the payload deepseek-review actually sends.
//
// Binds 127.0.0.1 on an ephemeral port and prints `PORT=<port>` on stdout so
// the caller never has to guess a free port. Exits on its own so no test has to
// kill it cross platform.
import { createServer } from 'node:http'
import { writeFileSync } from 'node:fs'

const mode = process.argv[2] ?? 'sse'
const dumpPath = process.argv[3]
const LIFETIME_MS = 20_000

const sse = (payload) => `data: ${JSON.stringify(payload)}\n\n`
const delta = (d) => ({ id: 'mock', model: 'mock-model', choices: [{ delta: d }] })

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

async function streamSse(res, { singleReasoningChunk = false, truncate = false }) {
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' })
  const reasoning = singleReasoningChunk ? ['REASON-ONLY-CHUNK '] : ['REASON-A ', 'REASON-B ']
  for (const chunk of reasoning) {
    res.write(sse(delta({ reasoning_content: chunk })))
    await sleep(10)
  }
  // Keep-alive and processing lines the real providers interleave; the review
  // must drop them instead of trying to parse them.
  res.write(': keep-alive\n\n')
  res.write(': OPENROUTER PROCESSING\n\n')
  if (truncate) {
    res.write('data: {"choices":[{"delta"\n\n')
    res.end()
    return
  }
  res.write(sse(delta({ content: 'REVIEW-BODY-' })))
  await sleep(10)
  res.write(`data: ${JSON.stringify({ ...delta({ content: 'END' }), usage: { total_tokens: 123 } })}\n\n`)
  res.write('data: [DONE]\n\n')
  res.end()
}

function sendJson(res, status, body) {
  const payload = JSON.stringify(body)
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) })
  res.end(payload)
}

const server = createServer(async (req, res) => {
  // Drain the request body so the client is never left waiting on backpressure
  const chunks = []
  for await (const chunk of req) chunks.push(chunk)
  if (dumpPath) writeFileSync(dumpPath, Buffer.concat(chunks))

  switch (mode) {
    case 'sse':
      return streamSse(res, {})
    case 'sse1':
      return streamSse(res, { singleReasoningChunk: true })
    case 'broken':
      return streamSse(res, { truncate: true })
    case 'json':
      return sendJson(res, 200, {
        id: 'mock',
        model: 'mock-model',
        choices: [{ message: { role: 'assistant', content: 'REVIEW-BODY-END', reasoning_content: 'REASON-A REASON-B' } }],
        usage: { total_tokens: 123 },
      })
    case 'errjson':
      return sendJson(res, 401, { error: { message: 'Authentication Fails', type: 'authentication_error' } })
    default:
      return sendJson(res, 500, { error: { message: `unknown mode ${mode}` } })
  }
})

server.listen(0, '127.0.0.1', () => {
  console.log(`PORT=${server.address().port}`)
})

setTimeout(() => process.exit(0), LIFETIME_MS)
