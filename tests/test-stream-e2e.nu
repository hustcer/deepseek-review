use std/assert
use std/testing *
use ../nu/common.nu [is-installed, windows?]

# End to end coverage for the two output paths of `deepseek-review`, driven by a
# throwaway HTTP server. Nushell cannot serve HTTP, so the mock is a dependency
# free `node:http` script — node ships with every GitHub hosted runner. When it
# is genuinely unavailable the suite reports and returns rather than failing.

const MOCK = 'tests/resources/mock-chat-server.mjs'

# Run the e2e tests one at a time: every test spawns a node mock plus a
# `deepseek-review` subprocess, and concurrent `job spawn`s of node intermittently
# fail to start — the log never gets its `PORT=` line, the review then hits an
# empty port and fails downstream. The suite is short enough that serial
# execution costs little.
# [strategy]
def e2e-serial []: nothing -> record {
  { threads: 1 }
}

# Start the mock in the requested mode and wait for it to publish its port
def start-mock [dir: string, mode: string, dump?: string] {
  let log = $dir | path join $'($mode)-(random chars -l 6).log'
  let dump_arg = $dump | default ''
  let job = job spawn { ^node $MOCK $mode ...(if ($dump_arg | is-empty) { [] } else { [$dump_arg] }) out+err> $log }

  mut port = ''
  for _ in 1..100 {
    sleep 100ms
    let text = try { open -r $log } catch { '' }
    if ($text | str contains 'PORT=') {
      $port = ($text | parse -r 'PORT=(?<p>\d+)' | get 0.p)
      break
    }
  }
  if ($port | is-empty) {
    # Fail with the mock's own output instead of a mysterious downstream
    # connection error — an empty log means the job never started, anything
    # else shows what node printed before dying.
    let tail = try { open -r $log | str trim } catch { '(log unreadable)' }
    error make { msg: $'mock server ($mode) did not publish PORT= in 10s; log: ($tail)' }
  }
  { job: $job, port: $port, log: $log }
}

# Run `deepseek-review` against the mock in a subprocess and capture the result
def run-review [port: string, args: string] {
  let url = $'http://127.0.0.1:($port)/v1/chat/completions'
  (
    ^$nu.current-exe -n -c $"
      # GitHub hosted runners set GITHUB_ACTIONS=true, which flips
      # deepseek-review into action mode: stream forced false and the
      # output mode becomes 'action', breaking every streaming assertion
      # below. Scrub it so the tested path is the local console one.
      $env.GITHUB_ACTIONS = null
      use nu/review.nu [deepseek-review]
      deepseek-review sk-mock-token --patch-cmd 'git show HEAD' --chat-url '($url)' ($args)
    " | complete
  )
}

@before-all
def setup [] {
  let dir = $nu.temp-dir | path join $'dsr-e2e-(random chars -l 8)'
  mkdir $dir
  { dir: $dir, node: (is-installed node), windows: (windows?) }
}

# Windows is skipped rather than made reliable: `job spawn`ing the node mock
# there intermittently yields a process that never comes up, so the log stays
# empty, `PORT=` never lands, and the test fails for reasons that have nothing to
# do with the code under test. Everything covered here — SSE parsing, file
# output, payload shape — is platform independent and stays covered by the Linux
# and macOS jobs.
def skip-e2e? [ctx: record]: nothing -> bool {
  if $ctx.windows { print 'the node mock is unreliable on Windows, skipping'; return true }
  if not $ctx.node { print 'node is not installed, skipping'; return true }
  false
}

@after-all
def teardown [] {
  let dir = $in.dir
  if ($dir | path exists) { rm -rf $dir }
}

@test
def 'streaming：prints reasoning and review under their own banners' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  let mock = start-mock $ctx.dir sse
  let result = run-review $mock.port ''
  job kill $mock.job

  assert equal $result.exit_code 0
  let out = $result.stdout | ansi strip
  assert ($out | str contains 'Reasoning Details:')
  assert ($out | str contains 'REASON-A REASON-B')
  assert ($out | str contains 'Review Details:')
  assert ($out | str contains 'REVIEW-BODY-END')
  # Keep-alive and terminator lines must be swallowed, not echoed at the user.
  assert equal ($out | str contains 'keep-alive') false
  assert equal ($out | str contains 'OPENROUTER PROCESSING') false
  assert equal ($out | str contains '[DONE]') false
}

@test
def 'streaming：each banner is printed exactly once' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  let mock = start-mock $ctx.dir sse
  let result = run-review $mock.port ''
  job kill $mock.job

  let lines = $result.stdout | ansi strip | lines
  assert equal ($lines | where $it =~ 'Reasoning Details:' | length) 1
  assert equal ($lines | where $it =~ 'Review Details:' | length) 1
}

@test
def 'streaming：a single reasoning chunk does not repeat the banner' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  # Regression: the banner was printed whenever the chunk counter *equalled* 1
  # rather than when it first reached 1, so a provider that sends its reasoning
  # in one chunk re-printed `Reasoning Details:` before every later chunk.
  let mock = start-mock $ctx.dir sse1
  let result = run-review $mock.port ''
  job kill $mock.job

  let lines = $result.stdout | ansi strip | lines
  assert equal ($lines | where $it =~ 'Reasoning Details:' | length) 1
  assert equal ($lines | where $it =~ 'Review Details:' | length) 1
  assert ($result.stdout | ansi strip | str contains 'REASON-ONLY-CHUNK')
}

@test
def 'streaming：a malformed chunk exits with SERVER_ERROR' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  # Regression: `parse-line` calls `exit`, and Nushell does not propagate `exit`
  # out of an `each` closure — the run used to end with a bare exit code 1 and
  # an internal `Eval block failed` dump instead of the documented code.
  let mock = start-mock $ctx.dir broken
  let result = run-review $mock.port ''
  job kill $mock.job

  assert equal $result.exit_code 3
  assert ($result.stderr | ansi strip | str contains 'Unrecognized content')
  assert equal ($result.stderr | str contains 'Eval block failed') false
}

@test
def 'streaming：an error object response exits with SERVER_ERROR' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  let mock = start-mock $ctx.dir errjson
  let result = run-review $mock.port ''
  job kill $mock.job

  assert equal $result.exit_code 3
}

@test
def 'streaming：sends stream true and the configured model and prompts' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  let dump = $ctx.dir | path join 'stream-request.json'
  let mock = start-mock $ctx.dir sse $dump
  let result = run-review $mock.port "--model my-model --temperature 1.25 --sys-prompt 'SYS-X' --user-prompt 'USER-X'"
  job kill $mock.job

  assert equal $result.exit_code 0
  let payload = open $dump
  assert equal $payload.stream true
  assert equal $payload.model 'my-model'
  assert equal $payload.temperature 1.25
  assert equal $payload.thinking.type 'disabled'
  assert equal $payload.messages.0.role 'system'
  assert equal $payload.messages.0.content 'SYS-X'
  assert equal $payload.messages.1.role 'user'
  assert ($payload.messages.1.content | str starts-with 'USER-X')
  # The diff itself has to reach the model, not just the prompt.
  assert ($payload.messages.1.content | str contains 'diff --git')
}

# An unset temperature must not reach the wire at all, so the provider's own
# default applies. Only the key's absence proves it: a null-valued key would
# still serialize as `"temperature": null` and be rejected by strict providers.
@test
def 'streaming：temperature is omitted from the payload when not set' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  let dump = $ctx.dir | path join 'no-temperature-request.json'
  let mock = start-mock $ctx.dir sse $dump
  let result = run-review $mock.port ''
  job kill $mock.job

  assert equal $result.exit_code 0
  assert equal ('temperature' in (open $dump | columns)) false
}

# 0 is a legitimate temperature, not an "unset" marker — the omission above keys
# off `== null` precisely so an explicit 0.0 still reaches the provider. Pin it,
# because a rewrite that keys off falsiness instead would silently drop it.
@test
def 'streaming：an explicit temperature of 0 is still sent' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  let dump = $ctx.dir | path join 'zero-temperature-request.json'
  let mock = start-mock $ctx.dir sse $dump
  let result = run-review $mock.port '--temperature 0.0'
  job kill $mock.job

  assert equal $result.exit_code 0
  assert equal (open $dump | get temperature) 0.0
}

@test
def 'streaming：a PR comment is passed through in its own tags' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  let dump = $ctx.dir | path join 'comment-request.json'
  let mock = start-mock $ctx.dir sse $dump
  let result = run-review $mock.port "--comment 'PLEASE FOCUS ON TESTS'"
  job kill $mock.job

  assert equal $result.exit_code 0
  let content = open $dump | get messages.1.content
  assert ($content | str contains '<comment>')
  assert ($content | str contains 'PLEASE FOCUS ON TESTS')
  assert ($content | str contains '</comment>')
}

@test
def 'file output：writes the review, the reasoning details and the token usage' [] {
  let ctx = $in
  if (skip-e2e? $ctx) { return }
  let out_file = $ctx.dir | path join 'review-result.md'
  let dump = $ctx.dir | path join 'file-request.json'
  let mock = start-mock $ctx.dir json $dump
  let result = run-review $mock.port $"--output '($out_file)'"
  job kill $mock.job

  assert equal $result.exit_code 0
  assert equal ($out_file | path exists) true
  let content = open -r $out_file
  assert ($content | str contains 'REVIEW-BODY-END')
  # Reasoning is folded away rather than dropped, so the review stays readable.
  assert ($content | str contains '<details>')
  assert ($content | str contains 'REASON-A REASON-B')
  assert ($content | str contains '## Token Usage')
  assert ($content | str contains '123')

  # Writing to a file must switch the request out of streaming mode.
  assert equal (open $dump | get stream) false
}
