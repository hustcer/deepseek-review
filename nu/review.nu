#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/01/29 13:02:15
# TODO:
#  [√] DeepSeek code review for GitHub PRs
#  [√] DeepSeek code review for local commit changes
#  [√] Debug mode
#  [√] Output token usage info
#  [√] Perform CR for changes that either include or exclude specific files
#  [√] Support streaming output for local code review
#  [√] Support using custom patch command to get diff content
#  [ ] Add more action outputs
# Description: A script to do code review by DeepSeek
# REF:
#   - https://docs.github.com/en/rest/issues/comments
#   - https://docs.github.com/en/rest/pulls/pulls
# Env vars:
#  GITHUB_TOKEN: Your GitHub API token
#  CHAT_TOKEN: Your DeepSeek API token
#  BASE_URL: DeepSeek API base URL
#  SYSTEM_PROMPT: System prompt message
#  USER_PROMPT: User prompt message
# Usage:
#  - Local Repo Review: just cr
#  - Local Repo Review: just cr -f HEAD~1 --debug
#  - Local PR Review: just cr -r hustcer/deepseek-review -n 32

use std-rfc/kv *
use diff.nu [get-diff]
use common.nu [
  ECODE, NO_TOKEN_TIP, hr-line, is-installed, windows?, mac?,
  compare-ver, compact-record, git-check, has-ref, GITHUB_API_BASE
]

const IGNORED_MESSAGES = {
  '-alive': true,                   # The server is alive
  'data: [DONE]': true,             # The end of the response
  ': OPENROUTER PROCESSING': true,  # OPENROUTER in PROCESSING message
}

# It takes longer to respond to requests made with unknown/rare user agents.
# When make http post pretend to be curl, it gets a response just as quickly as curl.
const HTTP_HEADERS = [User-Agent curl/8.9]

# Hidden HTML comment fingerprint embedded in every tracking review.
# Used to identify the AI's own review when reconciling across commits.
const TRACKER_MARKER_PREFIX = '<!-- dsr-tracker:'

def tracker-marker [pr_number: string, sha: string] {
  $"($TRACKER_MARKER_PREFIX)pr=($pr_number) sha=($sha) updated=(date now | format date '%Y-%m-%dT%H:%M:%SZ') -->"
}

# Find the existing tracking review for a PR (returns null if none).
# Walks the page of reviews until it sees a body containing the tracker marker.
def find-existing-review [
  repo: string,
  pr_number: string,
] {
  let headers = [
    Authorization $'Bearer ($env.GH_TOKEN)'
    Accept application/vnd.github+json
    X-GitHub-Api-Version '2022-11-28'
    ...$HTTP_HEADERS
  ]
  let base_url = $'($GITHUB_API_BASE)/repos/($repo)/pulls/($pr_number)/reviews'
  let page_size = 100

  # Helper: scan one page of reviews, return the first tracker-marked review (or null).
  def scan-page [headers: list, url: string] {
    let resp = (try { http get -H $headers $url } catch { return null })
    let items = if ($resp | describe) == 'list' { $resp } else { [$resp] }
    if ($items | is-empty) { return null }
    let marked = ($items | where { |r| (($r | get -o body | default '') | str contains $TRACKER_MARKER_PREFIX) })
    if ($marked | is-empty) { null } else { ($marked | first | upsert body ($marked | first | get -o body | default '')) }
  }

  let page1 = (scan-page $headers $'($base_url)?per_page=($page_size)&page=1')
  if $page1 != null { return $page1 }

  # Page 2-10 only if page 1 was full but had no marker
  let p1_count = (try {
    http get -H $headers $'($base_url)?per_page=($page_size)&page=1' | length
  } catch { 0 })
  if $p1_count < $page_size { return null }

  for page in 2..10 {
    let found = (scan-page $headers $'($base_url)?per_page=($page_size)&page=($page)')
    if $found != null { return $found }
  }
  null
}

# Parse the previous tracking review body into a record:
#   { sha, findings: list<{severity, file, line, message, suggestion}> }
# Findings are parsed from the per-finding markdown list items.
export def parse-tracking-body [body: string] {
  # Pattern: capture the SHA from `<!-- dsr-tracker:pr=... sha=<SHA> updated=... -->`
  let sha_pattern = '<!-- dsr-tracker:pr=\S+ sha=(\S+)'
  let sha_match = ($body | parse --regex $sha_pattern)
  let sha = if ($sha_match | is-empty) { '' } else { ($sha_match | first | get capture0) }

  # Parse findings from our own generated body. Each finding line looks like:
  #   "- <severity> `path:line` — message  → suggestion"
  # We split on " — " first (which separates severity+location from message),
  # then split the prefix on " `" to get severity and `path:line`.
  mut findings = []
  for line in ($body | lines) {
    let trimmed = ($line | str trim)
    # Only consider lines that look like findings (start with "- <severity>")
    if not ($trimmed | str starts-with '- ') { continue }
    # Strip leading "- "
    let content = ($trimmed | str substring 2..)
    # Split on " — " (em-dash) to separate [severity `path:line`] from [message [+ suggestion]]
    let parts = ($content | split row ' — ')
    if ($parts | length) < 2 { continue }
    let head = ($parts | first | str trim)
    let rest = ($parts | skip 1 | str join ' — ' | str trim)
    # head looks like:  high `nu/review.nu:120`
    let head_parts = ($head | split row ' `')
    if ($head_parts | length) < 2 { continue }
    let severity = ($head_parts | first | str trim | str downcase)
    let loc_raw  = ($head_parts | get 1 | str trim)
    # Strip trailing backtick (last char if it's '`'). substring 0..end is
    # INCLUSIVE on the right in Nushell 0.113, so to drop the last char we
    # need 0..(n-2), not 0..(n-1).
    let loc_clean = if ($loc_raw | str ends-with '`') {
      let n = ($loc_raw | str length)
      $loc_raw | str substring 0..(($n) - 2) | str trim
    } else { $loc_raw }
    # Split loc on the LAST ":" (file paths may themselves contain ":")
    let last_colon = ($loc_clean | str index-of --end ':')
    let file = if $last_colon < 0 { $loc_clean } else { $loc_clean | str substring 0..(($last_colon) - 1) | str trim }
    let line_str = if $last_colon < 0 { '' } else { $loc_clean | str substring (($last_colon) + 1).. | str trim }
    let line_num = (try { $line_str | into int } catch { 0 })
    # Split rest on " → " to get message and suggestion
    let rest_parts = ($rest | split row ' → ')
    let message = ($rest_parts | first | str trim)
    let suggestion = if ($rest_parts | length) > 1 { ($rest_parts | get 1 | str trim) } else { '' }
    $findings = ($findings | append {
      severity: $severity,
      file: $file,
      line: $line_num,
      message: $message,
      suggestion: $suggestion,
    })
  }
  { sha: $sha, findings: $findings }
}

# Reconcile old vs new findings, classify each as:
#   resolved  - was in old, not in new (the diff no longer mentions it)
#   still_open - was in old, still in new
#   new_issues - was not in old, is in new
def finding-key [f: record] { $'($f.file):($f.line)' }

export def reconcile-findings [old_findings: list, new_findings: list] {
  let old_keys = ($old_findings | each { |f| (finding-key $f) })
  let new_keys = ($new_findings | each { |f| (finding-key $f) })
  let resolved   = ($old_findings | where { |f| ((finding-key $f) not-in $new_keys) })
  let still_open = ($old_findings | where { |f| ((finding-key $f) in $new_keys) })
  let new_issues = ($new_findings | where { |f| ((finding-key $f) not-in $old_keys) })
  { resolved: $resolved, still_open: $still_open, new_issues: $new_issues }
}

# Build the final tracking review body with a fingerprint marker + status sections.
export def format-finding [f: record] {
  let loc = if ($f.line | default 0) > 0 { $'`($f.file):($f.line)`' } else { $'`($f.file)`' }
  let suggestion = if ($f.suggestion | default '') == '' { '' } else { $'  → ($f.suggestion)' }
  $'- ($f.severity) (ansi reset)($loc)(ansi reset) — ($f.message)(ansi reset)($suggestion)'
}

export def build-tracking-body [
  pr_number: string,
  latest_sha: string,
  update_count: int,
  reconciled: record,
] {
  let resolved_block   = if ($reconciled.resolved   | is-empty) { '_(none yet)_' } else { ($reconciled.resolved   | each { |f| (format-finding $f) } | str join "\n") }
  let still_open_block = if ($reconciled.still_open | is-empty) { '_(none)_' }        else { ($reconciled.still_open | each { |f| (format-finding $f) } | str join "\n") }
  let new_issues_block = if ($reconciled.new_issues | is-empty) { '_(none)_' }        else { ($reconciled.new_issues | each { |f| (format-finding $f) } | str join "\n") }

  let marker = (tracker-marker $pr_number $latest_sha)
  let sha_short = if ($latest_sha | str length) > 0 { ($latest_sha | str substring 0..6) } else { 'no-sha' }
  let title = $"## 🤖 AI Code Review — update #($update_count)  ·  SHA: (ansi reset)($sha_short)(ansi reset)"

  [
    $marker
    $title
    ''
    '### ✅ Resolved (previously flagged, no longer in diff)'
    $resolved_block
    ''
    '### 🆕 Newly introduced'
    $new_issues_block
    ''
    '### ❌ Still open (flagged in previous review, still present)'
    $still_open_block
    ''
    '_Generated by DeepSeek-Review single-review mode. Each commit re-runs the review and updates this comment in place._'
  ] | str join "\n"
}

# Parse DeepSeek's free-form review output into structured findings.
# The model is instructed (via sys-prompt injection in this function) to output
# a "FINDINGS:" block where each line is `- <severity> <file>:<line> — <message> → <suggestion>`.
export def parse-deepseek-findings [review: string, original_diff: string] {
  # Try to extract a structured "FINDINGS:" block if the model followed the instruction
  let findings_block = (
    if ($review | str contains 'FINDINGS:') {
      $review | str substring ((($review | str index-of 'FINDINGS:') + 9)..)
    } else {
      ''
    }
  )
  mut findings = []
  if ($findings_block | str trim | is-not-empty) {
    for line in ($findings_block | lines) {
      let trimmed = ($line | str trim)
      if ($trimmed | is-empty) { continue }
      if not ($trimmed | str starts-with '- ') { continue }
      # Strip leading "- "
      let content = ($trimmed | str substring 2..)
      # Format: "<severity> `path:line` — message  → suggestion"
      let parts = ($content | split row ' — ')
      if ($parts | length) < 2 { continue }
      let head = ($parts | first | str trim)
      let rest = ($parts | skip 1 | str join ' — ' | str trim)
      let head_parts = ($head | split row ' `')
      if ($head_parts | length) < 2 { continue }
      let severity = ($head_parts | first | str trim | str downcase)
      let loc_raw  = ($head_parts | get 1 | str trim)
      let loc_clean = if ($loc_raw | str ends-with '`') {
        let n = ($loc_raw | str length)
        $loc_raw | str substring 0..(($n) - 2) | str trim
      } else { $loc_raw }
      let last_colon = ($loc_clean | str index-of --end ':')
      let file = if $last_colon < 0 { $loc_clean } else { $loc_clean | str substring 0..(($last_colon) - 1) | str trim }
      let line_str = if $last_colon < 0 { '' } else { $loc_clean | str substring (($last_colon) + 1).. | str trim }
      let line_num = (try { $line_str | into int } catch { 0 })
      let rest_parts = ($rest | split row ' → ')
      let message = ($rest_parts | first | str trim)
      let suggestion = if ($rest_parts | length) > 1 { ($rest_parts | get 1 | str trim) } else { '' }
      $findings = ($findings | append {
        severity: $severity,
        file: $file,
        line: $line_num,
        message: $message,
        suggestion: $suggestion,
      })
    }
  }
  # Fallback: if the model didn't follow the structured format, surface the
  # whole review as a single "low"-severity entry so we never lose content.
  if ($findings | is-empty) {
    $findings = [{
      severity: 'low'
      file: '(see review)'
      line: 0
      message: ($review | str substring 0..200)
      suggestion: 'See full review body for details.'
    }]
  }
  $findings
}

# Inject the structured-output instruction into the user-prompt so the model
# emits a parseable FINDINGS: block alongside its free-form review.
def inject-findings-instruction [user_prompt: string] {
  let instructions = $'(char nl)(char nl)---(char nl)STRUCTURED OUTPUT (required for single-review mode):(char nl)After your human-readable review, append a `FINDINGS:` section where each line is EXACTLY in this format so the tool can track resolution across commits:(char nl)'
  $'- <severity> `<file>:<line>` — <one-line problem> → <one-line fix>(char nl)'
  let example = 'Example: `- high `nu/review.nu:120` — def --env deprecation warning → use with-env block`'
  [
    $user_prompt
    $instructions
    $'- <severity> `<file>:<line>` — <one-line problem> → <one-line fix>'
    $example
    ''
    'Use severity ∈ {critical, high, med, low, info}.'
    'Only include findings you can ground in a specific `path:line` from the diff. Do NOT list findings without a file:line anchor.'
  ] | str join "\n"
}

def submit-review-to-pr [
  repo: string,
  pr_number: string,
  review_body: string,
] {
  if ($repo | is-empty) or ($pr_number | is-empty) {
    print $'(ansi r)Repo or PR number is empty, cannot submit review.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }

  let review_url = $'($GITHUB_API_BASE)/repos/($repo)/pulls/($pr_number)/reviews'
  let headers = [
    Authorization $'Bearer ($env.GH_TOKEN)'
    Accept application/vnd.github+json
    X-GitHub-Api-Version '2022-11-28'
    ...$HTTP_HEADERS
  ]

  print $'Posting review to: (ansi g)($review_url)(ansi reset)'

  try {
    let response = http post -e -f -t application/json -H $headers $review_url {
      event: 'COMMENT'
      body: $review_body
    }

    let status = $response | get -o status | default 0

    if $status >= 200 and $status < 300 {
      print $'Review submitted successfully! HTTP (ansi g)($status)(ansi reset)'
    } else {
      print $'(ansi r)Failed to submit review. HTTP Status: ($status)(ansi reset)'
      let err_body = $response | get -o body | default ''
      if ($err_body | is-not-empty) {
        print $'(ansi r)Response body:(ansi reset)'
        print $err_body
      }
      exit $ECODE.SERVER_ERROR
    }
  } catch {|err|
    print $'(ansi r)Failed to submit review to PR — network or connection error:(ansi reset)'
    $err | table -e | print
    exit $ECODE.SERVER_ERROR
  }
}

# Update an existing review's body via PATCH.
def update-review-body [
  repo: string,
  pr_number: string,
  review_id: int,
  new_body: string,
] {
  if ($repo | is-empty) or ($pr_number | is-empty) or ($review_id <= 0) {
    print $'(ansi r)Repo/PR/review_id is empty, cannot update review.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
  let url = $'($GITHUB_API_BASE)/repos/($repo)/pulls/($pr_number)/reviews/($review_id)'
  let headers = [
    Authorization $'Bearer ($env.GH_TOKEN)'
    Accept application/vnd.github+json
    X-GitHub-Api-Version '2022-11-28'
    ...$HTTP_HEADERS
  ]
  print $'Patching existing review: (ansi g)($url)(ansi reset)'
  try {
    let response = http patch -e -f -t application/json -H $headers $url { body: $new_body }
    let status = $response | get -o status | default 0
    if $status >= 200 and $status < 300 {
      print $'Review updated successfully! HTTP (ansi g)($status)(ansi reset)'
    } else {
      print $'(ansi r)Failed to update review. HTTP Status: ($status)(ansi reset)'
      let err_body = $response | get -o body | default ''
      if ($err_body | is-not-empty) { print $err_body }
      exit $ECODE.SERVER_ERROR
    }
  } catch {|err|
    print $'(ansi r)Failed to update review — network error:(ansi reset)'
    $err | table -e | print
    exit $ECODE.SERVER_ERROR
  }
}

def is-pr-locked [
  repo: string,
  pr_number: string,
] {
  let url = $'($GITHUB_API_BASE)/repos/($repo)/pulls/($pr_number)'
  let headers = [
    Authorization $'Bearer ($env.GH_TOKEN)'
    Accept application/vnd.github+json
    X-GitHub-Api-Version '2022-11-28'
    ...$HTTP_HEADERS
  ]

  try {
    let response = http get -H $headers $url
    ($response | get -o locked | default false)
  } catch {
    false
  }
}

const DEFAULT_OPTIONS = {
  MODEL: 'deepseek-v4-flash',
  TEMPERATURE: 0.3,
  BASE_URL: 'https://api.deepseek.com',
  USER_PROMPT: 'Please review the following code changes:',
  SYS_PROMPT: 'You are a professional code review assistant responsible for analyzing code changes in GitHub Pull Requests. Identify potential issues such as code style violations, logical errors, security vulnerabilities, and provide improvement suggestions. Clearly list the problems and recommendations in a concise manner.',
}

# Use DeepSeek AI to review code changes locally or in GitHub Actions
export def --env deepseek-review [
  token?: string,           # Your DeepSeek API token, fallback to CHAT_TOKEN env var
  --debug(-d),              # Debug mode
  --repo(-r): string,       # GitHub repo name, e.g. hustcer/deepseek-review, or local repo path / alias
  --output(-o): string,     # Output file path
  --pr-number(-n): string,  # GitHub PR number
  --gh-token(-k): string,   # Your GitHub token, fallback to GITHUB_TOKEN env var
  --diff-to(-t): string,    # Git diff ending commit SHA
  --diff-from(-f): string,  # Git diff starting commit SHA
  --patch-cmd(-c): string,  # The `git show` or `git diff` command to get the diff content, for local CR only
  --max-length(-l): int,    # Maximum length of the content for review, 0 means no limit.
  --model(-m): string,      # Model name, or read from CHAT_MODEL env var, `deepseek-v4-flash` by default
  --base-url(-b): string,   # DeepSeek API base URL, fallback to BASE_URL env var
  --chat-url(-U): string,   # DeepSeek Model chat full API URL, e.g. http://localhost:11535/api/chat
  --sys-prompt(-s): string  # Default to $DEFAULT_OPTIONS.SYS_PROMPT,
  --user-prompt(-u): string # Default to $DEFAULT_OPTIONS.USER_PROMPT,
  --include(-i): string,    # Comma separated file patterns to include in the code review
  --exclude(-x): string,    # Comma separated file patterns to exclude in the code review
  --temperature(-T): float, # Temperature for the model, between `0` and `2`, default value `0.3`
  --comment: string,       # Additional comment text from a PR comment mention trigger
  --single-review = false, # Single-review mode: keep one AI review per PR and update it in place across commits
]: nothing -> nothing {

  $env.config.table.mode = 'psql'
  let local_repo = $env.PWD
  let write_file = ($output | is-not-empty)
  let is_action = ($env.GITHUB_ACTIONS? == 'true')
  let token = $token | default $env.CHAT_TOKEN?
  let repo = $repo | default $env.DEFAULT_GITHUB_REPO?
  let CHAT_HEADER = [Authorization $'Bearer ($token)']
  let stream = if $is_action or $write_file { false } else { true }
  let model = $model | default $env.CHAT_MODEL? | default $DEFAULT_OPTIONS.MODEL
  let base_url = $base_url | default $env.BASE_URL? | default $DEFAULT_OPTIONS.BASE_URL
  let url = $chat_url | default $env.CHAT_URL? | default $'($base_url)/chat/completions'
  let max_length = try { $max_length | default ($env.MAX_LENGTH? | default 0 | into int) } catch { 0 }
  let temperature = try { $temperature | default $env.TEMPERATURE? | default $DEFAULT_OPTIONS.TEMPERATURE | into float } catch { $DEFAULT_OPTIONS.TEMPERATURE }
  # Determine output mode
  let output_mode = if $is_action { 'action' } else if ($output | is-not-empty) { 'file' } else { 'console' }

  validate-temperature $temperature
  let setting = {
    repo: $repo,
    model: $model,
    chat_url: $url,
    include: $include,
    exclude: $exclude,
    diff_to: $diff_to,
    diff_from: $diff_from,
    patch_cmd: $patch_cmd,
    pr_number: $pr_number,
    max_length: $max_length,
    local_repo: $local_repo,
    temperature: $temperature,
  }
  $env.GH_TOKEN = $gh_token | default $env.GITHUB_TOKEN?

  if $is_action and ($pr_number | is-not-empty) and ($repo | is-not-empty) and (is-pr-locked $repo $pr_number) {
    print $'(ansi y)PR #($pr_number) is locked, skipping review.(ansi reset)'
    exit $ECODE.SUCCESS
  }

  validate-token $token --pr-number $pr_number --repo $repo
  let hint = if not $is_action and ($pr_number | is-empty) {
    $'🚀 Initiate the code review by DeepSeek AI for local changes ...'
  } else {
    $'🚀 Initiate the code review by DeepSeek AI for PR (ansi g)#($pr_number)(ansi reset) in (ansi g)($repo)(ansi reset) ...'
  }
  print $hint; print -n (char nl)
  if ($pr_number | is-empty) {
    print 'Current Settings:'; hr-line
    $setting | compact-record | reject -o repo | print; print -n (char nl)
  }

  let content = (
    get-diff --pr-number $pr_number --repo $repo --diff-to $diff_to
             --diff-from $diff_from --include $include --exclude $exclude --patch-cmd $patch_cmd)
  let length = $content | str stats | get unicode-width
  if ($max_length != 0) and ($length > $max_length) {
    print $'(char nl)(ansi r)The content length ($length) exceeds the maximum limit ($max_length), review skipped.(ansi reset)'
    exit $ECODE.SUCCESS
  }
  print $'Review content length: (ansi g)($length)(ansi reset), current max length: (ansi g)($max_length)(ansi reset)'
  let sys_prompt = $sys_prompt | default $env.SYSTEM_PROMPT? | default $DEFAULT_OPTIONS.SYS_PROMPT
  let user_prompt = $user_prompt | default $env.USER_PROMPT? | default $DEFAULT_OPTIONS.USER_PROMPT
  # In single-review mode, inject the structured-output instruction so the
  # model emits a parseable FINDINGS: block alongside its free-form review.
  let user_prompt = if $single_review { (inject-findings-instruction $user_prompt) } else { $user_prompt }
  let user_content = if ($comment | is-not-empty) {
    $"($user_prompt):\n($content)\n\nAdditional context from PR comment (char lp)enclosed in <comment> tags(char rp):\n<comment>\n($comment)\n</comment>"
  } else {
    $"($user_prompt):\n($content)"
  }
  let payload = {
    model: $model,
    stream: $stream,
    temperature: $temperature,
    messages: [
      { role: 'system', content: $sys_prompt },
      { role: 'user', content: $user_content }
    ],
    thinking: { type: 'disabled' }
  }
  if $debug { print $'(char nl)Code Changes:'; hr-line; print $content }
  print $'(char nl)Waiting for response from (ansi g)($url)(ansi reset) ...'
  if $stream { streaming-output $url $payload --headers $CHAT_HEADER --debug=$debug; return }

  let response = http post -e -H $CHAT_HEADER -t application/json $url $payload
  if ($response | is-empty) {
    print $'(ansi r)Oops, No response returned from ($url) ...(ansi reset)'
    exit $ECODE.SERVER_ERROR
  }
  if $debug { print $'DeepSeek Model Response:'; hr-line; $response | table -e | print }
  if ($response | describe) == 'string' {
    print $'✖️ Code review failed！Error: '; hr-line; print $response
    exit $ECODE.SERVER_ERROR
  }
  let message = $response | get -o choices.0.message
  let reason = $message | coalesce-reasoning
  let review = $message.content? | default ($response | get -o message.content)
  # In single-review mode, do NOT fold reasoning into <details> — it would break
  # the structured FINDINGS: parser (it can confuse < > → inside the folded block).
  let result = if ($reason | is-empty) or $single_review {
    $review
  } else {
    ['<details>' '<summary> Reasoning Details</summary>' $reason "</details>\n" $review] | str join "\n"
  }
  if ($review | is-empty) {
    print $'✖️ Code review failed！No review result returned from ($base_url) ...'
    exit $ECODE.SERVER_ERROR
  }

  # In single-review mode, reconcile with any existing review on the PR.
  if $single_review and $is_action and ($pr_number | is-not-empty) and ($repo | is-not-empty) {
    let existing = (find-existing-review $repo $pr_number)
    let new_findings = (parse-deepseek-findings $review $content)
    let old_findings = (
      if $existing == null {
        []
      } else {
        let prev_body = ($existing | get body)
        let prev_parsed = (parse-tracking-body $prev_body)
        $prev_parsed.findings
      }
    )
    let update_count = (($old_findings | length) + 1)   # rough: increment each run
    let reconciled = (reconcile-findings $old_findings $new_findings)
    # Latest commit SHA comes from env var (set by action.yaml from github.event.head_sha)
    let latest_sha = ($env.HEAD_SHA? | default '')
    let tracking_body = (build-tracking-body $pr_number $latest_sha $update_count $reconciled)
    if $existing == null {
      submit-review-to-pr $repo $pr_number $tracking_body
      print $'✅ Code review finished！Tracking review created on PR (ansi g)#($pr_number)(ansi reset).'
    } else {
      let review_id = ($existing | get id)
      update-review-body $repo $pr_number $review_id $tracking_body
      print $'✅ Code review finished！Tracking review updated on PR (ansi g)#($pr_number)(ansi reset) (review id: ($review_id)).'
    }
  } else {
    match $output_mode {
      'action' => {
        submit-review-to-pr $repo $pr_number $result
        print $'✅ Code review finished！PR (ansi g)#($pr_number)(ansi reset) review result was submitted as a review.'
      }
      'file' => { write-review-to-file $output $setting $result $response }
      _ => { print $'Code Review Result:'; hr-line; print $result }
    }
  }

  if ($response.usage? | is-not-empty) {
    print $'(char nl)Token Usage:'; hr-line
    $response.usage? | table -e | print
  }
}

# Write the code review result to a file
def write-review-to-file [
  file: string,           # Output file path
  setting: record,        # Review settings
  result: string,         # Review result
  response: record,       # DeepSeek API response
] {
  let file = (if not ($file | str ends-with '.md') { $'($file).md' } else { $file })
  let token_usage = if ($response.usage? | is-empty) { [] } else {
    ['## Token Usage', '', ($response.usage? | transpose key val | to md --pretty)]
  }
  # Generate content sections
  let content_sections = [
    '# DeepSeek Code Review Result', ''
    $"Generated at: (date now | format date '%Y/%m/%d %H:%M:%S')", ''
    '## Code Review Settings', ''
    ($setting | compact-record | reject -o repo | transpose key val | to md --pretty)
    '', '## Review Detail', '', $result, '', ...$token_usage
  ]
  try {
    $content_sections | str join (char nl) | save --force $file
    print $'Code Review Result saved to (ansi g)($file)(ansi reset)'
  } catch {|err|
    print $'(ansi r)Failed to save review result: (ansi reset)'
    $err | table -e | print
  }
}

# Validate the DeepSeek API token
def validate-token [token?: string, --pr-number: string, --repo: string] {
  if ($token | is-empty) {
    print $'(ansi r)Please provide your DeepSeek API token by setting `CHAT_TOKEN` or passing it as an argument.(ansi reset)'
    if ($pr_number | is-not-empty) { submit-review-to-pr $repo $pr_number $NO_TOKEN_TIP }
    exit $ECODE.INVALID_PARAMETER
  }
  $token
}

# Validate the temperature value
def validate-temperature [temp: float] {
  if ($temp < 0) or ($temp > 2) {
    print $'(ansi r)Invalid temperature value, should be in the range of 0 to 2.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
  $temp
}

# Output the streaming response of review result from DeepSeek API
def streaming-output [
  url: string,        # The Full DeepSeek API URL
  payload: record,    # The payload to send to DeepSeek API
  --debug,            # Debug mode
  --headers: list,    # The headers to send to DeepSeek API
] {
  print -n (char nl)
  kv set content 0
  kv set reasoning 0
  http post -e -H $headers -t application/json $url $payload
    | tee {
        let res = $in
        let type = $res | describe
        let record_error = $type =~ '^record'
        let other_error  = $type =~ '^string' and $res !~ 'data: ' and $res !~ 'done'
        if $record_error or $other_error {
          $res | table -e | print
          exit $ECODE.SERVER_ERROR
        }
      }
    | try { lines } catch { print $'(ansi r)Error Happened ...(ansi reset)'; exit $ECODE.SERVER_ERROR }
    | each {|line|
        if ($line | is-empty) { return }
        if ($IGNORED_MESSAGES | get -o $line | default false) { return }
        let $last = $line | parse-line
        if $debug { $last | to json | kv set last-reply }
        $last | get -o choices.0.delta | default ($last | get -o message) | if ($in | is-not-empty) {
          let delta = $in
          if ($delta | coalesce-reasoning | is-not-empty) { kv set reasoning ((kv get reasoning) + 1) }
          if (kv get reasoning) == 1 { print $'(char nl)Reasoning Details:'; hr-line }
          if ($delta.content? | is-not-empty) { kv set content ((kv get content) + 1) }
          if (kv get content) == 1 { print $'(char nl)Review Details:'; hr-line }
          print -n ($delta | coalesce-reasoning | default ($delta.content? | default ''))
        }
      }

  if $debug and (kv get last-reply | is-not-empty) {
    print $'(char nl)(char nl)Model & Token Usage:'; hr-line
    kv get last-reply | from json | select -o model usage | table -e | print
  }
}

# Parse the line from the streaming response
def parse-line [] {
  let $line = $in
  # DeepSeek Response vs Local Ollama Response
  try {
    if $line =~ '^data: ' {
      $line | str substring 6.. | from json
    } else {
      $line | from json
    }
  } catch {
    print -e $'(ansi r)Unrecognized content:(ansi reset) ($line)'
    exit $ECODE.SERVER_ERROR
  }
}

# Coalesce the reasoning content
def coalesce-reasoning [] {
  let msg = $in
  $msg.reasoning_content? | default $msg.reasoning?
}

alias main = deepseek-review
