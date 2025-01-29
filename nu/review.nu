#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/01/29 13:02:15
# TODO:
#   [√] Deepseek code review for GitHub PRs
#   [√] Deepseek code review for local commit changes
#   [√] Debug mode
#   [√] Output token usage info
#   [ ] Add more action outputs
# Description: A script to do code review by deepseek
# Env vars:
#  GITHUB_TOKEN: Your GitHub API token
#  DEEPSEEK_TOKEN: Your Deepseek API token
# Usage:
#  1. Local: just cr
#  2. Local: just cr -f HEAD~1 --debug
#

const DEFAULT_OPTIONS = {
  MODEL: 'deepseek-chat',
  BASE_URL: 'https://api.deepseek.com',
  USER_PROMPT: 'Please review the following code changes:',
  SYS_PROMPT: 'You are a professional code review assistant responsible for analyzing code changes in GitHub Pull Requests. Identify potential issues such as code style violations, logical errors, security vulnerabilities, and provide improvement suggestions. Clearly list the problems and recommendations in a concise manner.',
}

# Use Deepseek AI to review code changes
export def deepseek-review [
  token?: string,       # Your Deepseek API token, fallback to DEEPSEEK_TOKEN
  --debug(-d),          # Debug mode
  --repo: string,       # GitHub repository name, e.g. hustcer/deepseek-review
  --pr-number: string,  # GitHub PR number
  --gh-token: string,   # Your GitHub token, GITHUB_TOKEN by default
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
    $'🚀 Initiate the code review by Deepseek AI for local changes ...'
  } else {
    $'🚀 Initiate the code review by Deepseek AI for PR (ansi g)#($pr_number)(ansi reset) in (ansi g)($repo)(ansi reset) ...'
  }
  print $hint; print -n (char nl)
  $env.GITHUB_TOKEN = $gh_token | default $env.GITHUB_TOKEN?
  let diff_content = if ($pr_number | is-not-empty) {
      gh pr diff $pr_number --repo $repo | str trim
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
    exit 1
    return
  }
  if $debug {
    print $'Deepseek Response:'; hr-line
    $response | table -e | print
  }
  if ($response | describe) == 'string' {
    print $'❌ Code review failed！Error: '; hr-line; print $response
    exit 1
    return
  }
  let review = $response | get -i choices.0.message.content
  if ($env.GITHUB_ACTIONS? != 'true') {
    print $'Code Review Result:'; hr-line
    print $review
  } else {
    gh pr comment $pr_number --body $review --repo $repo
    print $'✅ Code review finished！PR (ansi g)#($pr_number)(ansi reset) review result was posted as a comment.'
  }
  print $'(char nl)Token Usage Info:'; hr-line
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
