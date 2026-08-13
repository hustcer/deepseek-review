use std/assert
use std/testing *

# `source` rather than `use`: parse-line / coalesce-reasoning / validate-* /
# write-review-to-file are the real logic behind the streaming and file output
# paths, but they are private to the module. Sourcing brings them into scope
# without widening review.nu's public API just for the tests. Commands that
# `exit` on the failure path are exercised in a subprocess instead, so a
# failing assertion cannot take the whole test runner down with it.
source ../nu/review.nu

# Run a snippet against a freshly sourced review.nu and capture exit code + output
def run-review-snippet [snippet: string] {
  ^$nu.current-exe -n -c $"source nu/review.nu; ($snippet)" | complete
}

@before-all
def setup [] {
  let dir = $nu.temp-dir | path join $'dsr-review-(random chars -l 8)'
  mkdir $dir
  { dir: $dir }
}

@after-all
def teardown [] {
  let dir = $in.dir
  if ($dir | path exists) { rm -rf $dir }
}

@test
def 'coalesce-reasoning：prefers reasoning_content over reasoning' [] {
  # Providers disagree on the field name: DeepSeek sends `reasoning_content`,
  # OpenRouter and friends send `reasoning`.
  assert equal ({ reasoning_content: 'rc' } | coalesce-reasoning) 'rc'
  assert equal ({ reasoning: 'r' } | coalesce-reasoning) 'r'
  assert equal ({ reasoning_content: 'rc', reasoning: 'r' } | coalesce-reasoning) 'rc'
  assert equal ({ reasoning_content: null, reasoning: 'r' } | coalesce-reasoning) 'r'
}

@test
def 'coalesce-reasoning：is null when neither field is present' [] {
  assert equal ({ content: 'c' } | coalesce-reasoning) null
  assert equal ({} | coalesce-reasoning) null
}

@test
def 'coalesce-reasoning：an empty reasoning_content is not a fallback trigger' [] {
  # `default` only fires on null, so an explicit '' wins. The streaming loop
  # guards with `is-not-empty` afterwards, which is what makes this safe.
  assert equal ({ reasoning_content: '', reasoning: 'r' } | coalesce-reasoning) ''
}

@test
def 'parse-line：strips the SSE data prefix' [] {
  assert equal ('data: {"a":1}' | parse-line) { a: 1 }
  assert equal ('data: {"choices":[{"delta":{"content":"hi"}}]}' | parse-line | get choices.0.delta.content) 'hi'
}

@test
def 'parse-line：accepts bare JSON from local Ollama' [] {
  assert equal ('{"a":2}' | parse-line) { a: 2 }
  assert equal ('{"message":{"content":"hi"}}' | parse-line | get message.content) 'hi'
}

@test
def 'parse-line：only a leading data prefix is stripped' [] {
  # `str substring 6..` is unconditional once the `^data: ` anchor matches, so
  # a `data: ` appearing inside the payload must not be touched.
  assert equal ('{"a":"data: x"}' | parse-line | get a) 'data: x'
}

@test
def 'parse-line：unparsable content exits with SERVER_ERROR' [] {
  # A truncated SSE chunk is the realistic failure: the review must stop with a
  # diagnosable exit code rather than carry on against a half decoded payload.
  let result = run-review-snippet "'data: {oops' | parse-line"
  assert equal $result.exit_code 3
  assert ($result.stderr | str contains 'Unrecognized content')

  let bare = run-review-snippet "'[1,' | parse-line"
  assert equal $bare.exit_code 3
}

@test
def 'parse-line：from json is lenient about bare scalars' [] {
  # `from json` happily reads an unquoted word as a JSON string, so plain-text
  # error bodies come back as a string rather than raising. That is tolerable
  # only because `streaming-output` rejects non-SSE string responses wholesale
  # before any line reaches here — documented so the guard is not dropped.
  assert equal ('not json at all' | parse-line) 'not json at all'
  assert equal (('not json at all' | parse-line) | describe) 'string'
}

@test
def 'IGNORED_MESSAGES：the terminator line is filtered by exact match' [] {
  # The lookup in the streaming loop is an exact whole line match, so only a
  # line spelled exactly like a key is dropped here. Heartbeats whose text
  # varies (`: keep-alive`, `: OPENROUTER PROCESSING`) are handled by the SSE
  # comment rule instead — see the `str starts-with ':'` guard in review.nu and
  # the end to end cover in test-stream-e2e.nu.
  assert equal ($IGNORED_MESSAGES | get -o 'data: [DONE]') true
  assert equal ($IGNORED_MESSAGES | get -o 'data: {"a":1}') null
  # A near miss must NOT be swallowed, or real payloads would go missing.
  assert equal ($IGNORED_MESSAGES | get -o 'data: [DONE] ') null
}

@test
def 'validate-temperature：accepts the whole documented range' [] {
  assert equal (validate-temperature 0.0) 0.0
  assert equal (validate-temperature 0.3) 0.3
  assert equal (validate-temperature 2.0) 2.0
}

@test
def 'validate-temperature：rejects values outside 0..2' [] {
  assert equal (run-review-snippet 'validate-temperature (-0.1)' | get exit_code) 6
  assert equal (run-review-snippet 'validate-temperature 2.1' | get exit_code) 6
  let result = run-review-snippet 'validate-temperature 100.0'
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'Invalid temperature value')
}

@test
def 'validate-token：passes the token through, rejects an empty one' [] {
  assert equal (validate-token 'sk-abc') 'sk-abc'
  # Without a PR number nothing is posted to GitHub, so this stays offline.
  let result = run-review-snippet "validate-token ''"
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'CHAT_TOKEN')
}

@test
def 'write-review-to-file：appends .md only when it is missing' [] {
  let dir = $in.dir
  let plain = $dir | path join 'no-ext'
  let with_ext = $dir | path join 'has-ext.md'
  write-review-to-file $plain {} 'BODY' {}
  write-review-to-file $with_ext {} 'BODY' {}
  assert equal ($'($plain).md' | path exists) true
  assert equal ($with_ext | path exists) true
  assert equal ($'($with_ext).md' | path exists) false
}

@test
def 'write-review-to-file：writes the review body and settings, hides the repo' [] {
  let dir = $in.dir
  let file = $dir | path join 'full.md'
  let setting = { repo: 'hustcer/secret-repo', model: 'deepseek-v4-flash', temperature: 0.3, include: null }
  write-review-to-file $file $setting 'THE REVIEW BODY' { usage: { total_tokens: 42 } }

  let content = open -r $file
  assert ($content | str contains '# DeepSeek Code Review Result')
  assert ($content | str contains '## Review Detail')
  assert ($content | str contains 'THE REVIEW BODY')
  assert ($content | str contains 'deepseek-v4-flash')
  assert ($content | str contains '## Token Usage')
  assert ($content | str contains '42')
  # `reject -o repo` keeps the repo out of a file users routinely paste around.
  assert equal ($content | str contains 'secret-repo') false
  # `compact-record` drops the unset options instead of printing empty rows.
  assert equal ($content | str contains 'include') false
}

@test
def 'write-review-to-file：omits the token usage section when usage is absent' [] {
  let dir = $in.dir
  let file = $dir | path join 'no-usage.md'
  write-review-to-file $file { model: 'm' } 'BODY' {}
  let content = open -r $file
  assert ($content | str contains 'BODY')
  assert equal ($content | str contains '## Token Usage') false
}

@test
def 'DEFAULT_OPTIONS：defaults stay in sync with action.yaml' [] {
  # `action.yaml` hard codes the same defaults for GitHub Action users. When one
  # side is bumped and the other is not, local and CI reviews silently run
  # against different models.
  let inputs = open action.yaml | get inputs
  assert equal $DEFAULT_OPTIONS.MODEL $inputs.model.default
  assert equal $DEFAULT_OPTIONS.BASE_URL $inputs.base-url.default
  assert equal $DEFAULT_OPTIONS.TEMPERATURE ($inputs.temperature.default | into float)
  assert equal $DEFAULT_OPTIONS.SYS_PROMPT $inputs.sys-prompt.default
}

# Run the entry command itself in a subprocess. Every guard below fires before
# any HTTP request, so these stay offline.
def run-review [args: string] {
  ^$nu.current-exe -n -c $"use nu/review.nu [deepseek-review]; deepseek-review ($args)" | complete
}

@test
def 'deepseek-review：refuses to start without a token' [] {
  let result = run-review ''
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'CHAT_TOKEN')
}

@test
def 'deepseek-review：validates the temperature before doing any work' [] {
  # Ordered ahead of `get-diff` so a typo is reported instantly rather than
  # after a PR download.
  let high = run-review 'tok --temperature 5.0'
  assert equal $high.exit_code 6
  assert ($high.stdout | str contains 'Invalid temperature value')

  assert equal (run-review 'tok --temperature (-1.0)' | get exit_code) 6
}

@test
def 'deepseek-review：an env token satisfies the token check' [] {
  # The guard must accept `CHAT_TOKEN` as documented, not just the positional
  # argument — so this run has to get past it and fail later, on the temperature.
  let result = (
    ^$nu.current-exe -n -c '$env.CHAT_TOKEN = "sk-from-env"
      use nu/review.nu [deepseek-review]
      deepseek-review --temperature 5.0' | complete
  )
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'Invalid temperature value')
  assert equal ($result.stdout | str contains 'Please provide your DeepSeek API token') false
}
