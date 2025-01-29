#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/01/29 13:02:15
# TODO:
#   [√] Deepseek code reivew for Github PRs
#   [√] Deepseek code reivew for local commit changes
#   [√] Debug mode
#   [√] Output usage info
# Description: A script to do code review by deepseek
# Env vars:
#  GITHUB_TOKEN: Your Github API token
#  DEEPSEEK_TOKEN: Your Deepseek API token
# Usage:
#  1. Local: just cr
#  2. Local: just cr -f HEAD~1 --debug
#

const DEFAULT_OPTIONS = {
  MODEL: 'deepseek-chat',
  BASE_URL: 'https://api.deepseek.com',
  USER_PROMPT: '请分析以下代码变更：',
  SYS_PROMPT: '你是一个专业的代码审查助手，负责分析GitHub Pull Request的代码变更，指出潜在的问题，如代码风格、逻辑错误、安全漏洞，并提供改进建议。请用简洁明了的语言列出问题及建议。',
}

# Use Deepseek AI to review code changes
export def deepseek-review [
  token?: string,       # Your Deepseek API token, fallback to DEEPSEEK_TOKEN
  --debug(-d),          # Debug mode
  --repo: string,       # Github repository name, e.g. hustcer/deepseek-review
  --pr-number: string,  # Github PR number
  --gh-token: string,   # Your Github token, GITHUB_TOKEN by default
  --diff-to(-t): string,       # Diff to git ref
  --diff-from(-f): string,     # Diff from git ref
  --model: string = $DEFAULT_OPTIONS.MODEL,   # Model name, deepseek-chat by default
  --base-url: string = $DEFAULT_OPTIONS.BASE_URL,
  --sys-prompt: string = $DEFAULT_OPTIONS.SYS_PROMPT,
  --user-prompt: string = $DEFAULT_OPTIONS.USER_PROMPT,
] {

  let token = $token | default $env.DEEPSEEK_TOKEN?
  $env.GH_TOKEN = $gh_token | default $env.GITHUB_TOKEN?
  if ($token | is-empty) {
    print $'(ansi r)Please provide your Deepseek API token by setting `DEEPSEEK_TOKEN` or passing it as an argument.(ansi reset)'
    return
  }
  let hint = if ($env.GITHUB_ACTIONS? != 'true') {
    $'🚀 Start code review for local changes by Deepseek AI ...'
  } else {
    $'🚀 Start code review for PR #($pr_number) in ($repo) by Deepseek AI ...'
  }
  print $hint; print -n (char nl)
  $env.GITHUB_TOKEN = $gh_token | default $env.GITHUB_TOKEN?
  let diff_content = if ($pr_number | is-not-empty) {
      GH_TOKEN=$env.GH_TOKEN gh pr diff $pr_number --repo $repo | str trim
    } else if ($diff_from | is-not-empty) {
      git diff $diff_from ($diff_to | default HEAD)
    } else { git diff }
  if ($diff_content | is-empty) {
    print $'(ansi r)Please provide the diff content by passing `--pr-number`.(ansi reset)'
    return
  }
  let payload = {
    model: $model,
    stream: false,
    messages: [
      { role: 'system', content: $sys_prompt },
      { role: 'user', content: $"($user_prompt):\n($diff_content)" }
    ]
  }
  if $debug {
    print $'Code Changes:'; hr-line; print $diff_content
  }
  let header = [Authorization $'Bearer ($token)']
  let url = $'($base_url)/chat/completions'
  print $'(char nl)(ansi g)Waiting for response from Deepseek ...(ansi reset)'
  let response = http post -e -H $header -t application/json $url $payload
  if ($response | is-empty) {
    print $'(ansi r)Oops, No response returned from Deepseek API.(ansi reset)'
    return
  }
  if $debug {
    print $'Deepseek Response:'; hr-line
    $response | table -e | print
  }
  if ($response | describe) == 'string' {
    print $'❌ Code review failed！Error: '; hr-line; print $response
    return
  }
  let review = $response | get -i choices.0.message.content
  if ($env.GITHUB_ACTIONS? != 'true') {
    print $'Code review result:'; hr-line
    print $review
  } else {
    GH_TOKEN=$env.GH_TOKEN gh pr comment $pr_number --body $review --repo $repo
    print $'✅ Code review finished！PR #($pr_number) review result was posted as a comment.'
  }
  print '(char nl)Usage Info:'; hr-line
  $response.usage | table -e | print
}

# Check if some command available in current shell
export def is-installed [ app: string ] {
  (which $app | length) > 0
}

export def hr-line [
  width?: int = 90,
  --color(-c): string = 'g',
  --blank-line(-b),
  --with-arrow(-a),
] {
  # Create a line by repeating the unit with specified times
  def build-line [
    times: int,
    unit: string = '-',
  ] {
    0..<$times | reduce -f '' { |i, acc| $unit + $acc }
  }

  print $'(ansi $color)(build-line $width)(if $with_arrow {'>'})(ansi reset)'
  if $blank_line { char nl }
}

alias main = deepseek-review
