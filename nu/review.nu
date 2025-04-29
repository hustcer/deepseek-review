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

const DEFAULT_OPTIONS = {
  MODEL: 'deepseek-chat',
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
  --model(-m): string,      # Model name, or read from CHAT_MODEL env var, `deepseek-chat` by default
  --base-url(-b): string,   # DeepSeek API base URL, fallback to BASE_URL env var
  --chat-url(-U): string,   # DeepSeek Model chat full API URL, e.g. http://localhost:11535/api/chat
  --sys-prompt(-s): string  # Default to $DEFAULT_OPTIONS.SYS_PROMPT,
  --user-prompt(-u): string # Default to $DEFAULT_OPTIONS.USER_PROMPT,
  --include(-i): string,    # Comma separated file patterns to include in the code review
  --exclude(-x): string,    # Comma separated file patterns to exclude in the code review
  --temperature(-T): float, # Temperature for the model, between `0` and `2`, default value `0.3`
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

  validate-token $token --pr-number $pr_number --repo $repo
  let hint = if not $is_action and ($pr_number | is-empty) {
    $'🚀 Initiate the code review by DeepSeek AI for local changes ...'
  } else {
    $'🚀 Initiate the code review by DeepSeek AI for PR (ansi g)#($pr_number)(ansi reset) in (ansi g)($repo)(ansi reset) ...'
  }
  print $hint; print -n (char nl)
  if ($pr_number | is-empty) {
    print 'Current Settings:'; hr-line
    $setting | compact-record | reject -i repo | print; print -n (char nl)
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
  let payload = {
    model: $model,
    stream: $stream,
    temperature: $temperature,
    messages: [
      { role: 'system', content: $sys_prompt },
      { role: 'user', content: $"($user_prompt):\n($content)" }
    ]
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
  let message = $response | get -i choices.0.message
  let reason = $message | coalesce-reasoning
  let review = $message.content? | default ($response | get -i message.content)
  let result = ['<details>' '<summary> Reasoning Details</summary>' $reason "</details>\n" $review] | str join "\n"
  if ($review | is-empty) {
    print $'✖️ Code review failed！No review result returned from ($base_url) ...'
    exit $ECODE.SERVER_ERROR
  }
  let result = if ($reason | is-empty) { $review } else { $result }

  match $output_mode {
    'action' => {
      post-comments-to-pr $repo $pr_number $result
      print $'✅ Code review finished！PR (ansi g)#($pr_number)(ansi reset) review result was posted as a comment.'
    }
    'file' => { write-review-to-file $output $setting $result $response }
    _ => { print $'Code Review Result:'; hr-line; print $result }
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
    ($setting | compact-record | reject -i repo | transpose key val | to md --pretty)
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
    if ($pr_number | is-not-empty) { post-comments-to-pr $repo $pr_number $NO_TOKEN_TIP }
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

# Post review comments to GitHub PR
def post-comments-to-pr [
  repo: string,        # GitHub repository name, e.g. hustcer/deepseek-review
  pr_number: string,   # GitHub PR number
  comments: string,    # Comments content to post
] {
  let comment_url = $'($GITHUB_API_BASE)/repos/($repo)/issues/($pr_number)/comments'
  let BASE_HEADER = [Authorization $'Bearer ($env.GH_TOKEN)' Accept application/vnd.github.v3+json ...$HTTP_HEADERS]
  try {
    http post -t application/json -H $BASE_HEADER $comment_url { body: $comments }
  } catch {|err|
    print $'(ansi r)Failed to post comments to PR: (ansi reset)'
    $err | table -e | print
    exit $ECODE.SERVER_ERROR
  }
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
        if ($IGNORED_MESSAGES | get -i $line | default false) { return }
        let $last = $line | parse-line
        if $debug { $last | to json | kv set last-reply }
        $last | get -i choices.0.delta | default ($last | get -i message) | if ($in | is-not-empty) {
          let delta = $in
          if ($delta | coalesce-reasoning | is-not-empty) { kv set reasoning ((kv get reasoning) + 1) }
          if (kv get reasoning) == 1 { print $'(char nl)Reasoning Details:'; hr-line }
          if ($delta.content | is-not-empty) { kv set content ((kv get content) + 1) }
          if (kv get content) == 1 { print $'(char nl)Review Details:'; hr-line }
          print -n ($delta | coalesce-reasoning | default $delta.content)
        }
      }

  if $debug and (kv get last-reply | is-not-empty) {
    print $'(char nl)(char nl)Model & Token Usage:'; hr-line
    kv get last-reply | from json | select -i model usage | table -e | print
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
