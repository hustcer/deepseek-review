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
#  CHAT_TOKEN: Your Deepseek API token
#  BASE_URL: Deepseek API base URL
#  SYSTEM_PROMPT: System prompt message
#  USER_PROMPT: User prompt message
# Usage:
#  1. Local: just cr
#  2. Local: just cr -f HEAD~1 --debug
#

# Commonly used exit codes
const ECODE = {
  SUCCESS: 0,
  OUTDATED: 1,
  MISSING_BINARY: 2,
  MISSING_DEPENDENCY: 3,
  CONDITION_NOT_SATISFIED: 5,
  SERVER_ERROR: 6,
  INVALID_PARAMETER: 7,
  AUTH_FAILED: 8,
}

const DEFAULT_OPTIONS = {
  MODEL: 'deepseek-chat',
  BASE_URL: 'https://api.deepseek.com',
  USER_PROMPT: 'Please review the following code changes:',
  SYS_PROMPT: 'You are a professional code review assistant responsible for analyzing code changes in GitHub Pull Requests. Identify potential issues such as code style violations, logical errors, security vulnerabilities, and provide improvement suggestions. Clearly list the problems and recommendations in a concise manner.',
}

# Use Deepseek AI to review code changes locally or in GitHub Actions
export def --env deepseek-review [
  token?: string,           # Your Deepseek API token, fallback to CHAT_TOKEN env var
  --debug(-d),              # Debug mode
  --repo(-r): string,       # GitHub repository name, e.g. hustcer/deepseek-review
  --pr-number(-n): string,  # GitHub PR number
  --gh-token: string,       # Your GitHub token, fallback to GITHUB_TOKEN env var
  --diff-to(-t): string,    # Diff to git REF
  --diff-from(-f): string,  # Diff from git REF
  --max-length(-l): int,    # Maximum length of the content for review, 0 means no limit.
  --model(-m): string = $DEFAULT_OPTIONS.MODEL,   # Model name, deepseek-chat by default
  --base-url: string = $DEFAULT_OPTIONS.BASE_URL,
  --sys-prompt(-s): string = $DEFAULT_OPTIONS.SYS_PROMPT,
  --user-prompt(-u): string = $DEFAULT_OPTIONS.USER_PROMPT,
]: nothing -> nothing {
  $env.config.table.mode = 'psql'
  print $max_length
  let is_action = ($env.GITHUB_ACTIONS? == 'true')
  let token = $token | default $env.CHAT_TOKEN?
  let repo = $repo | default $env.DEFAULT_GITHUB_REPO?
  let header = [Authorization $'Bearer ($token)']
  let url = $'($base_url)/chat/completions'
  let local_repo = $env.DEFAULT_LOCAL_REPO? | default (pwd)
  let max_length = $max_length | default ($env.MAX_LENGTH? | default 0 | into int)
  let setting = {
    repo: $repo,
    diff_to: $diff_to,
    diff_from: $diff_from,
    pr_number: $pr_number,
    max_length: $max_length,
    local_repo: $local_repo,
  }
  $env.GH_TOKEN = $gh_token | default $env.GITHUB_TOKEN?
  if ($token | is-empty) {
    print $'(ansi r)Please provide your Deepseek API token by setting `CHAT_TOKEN` or passing it as an argument.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
  if $is_action and not (is-installed gh) {
    print $'(ansi r)Please install GitHub CLI from https://cli.github.com (ansi reset)'
    exit $ECODE.MISSING_BINARY
  }
  let hint = if not $is_action and ($pr_number | is-empty) {
    $'🚀 Initiate the code review by Deepseek AI for local changes ...'
  } else {
    $'🚀 Initiate the code review by Deepseek AI for PR (ansi g)#($pr_number)(ansi reset) in (ansi g)($repo)(ansi reset) ...'
  }
  print $hint; print -n (char nl)
  if ($pr_number | is-empty) { $setting | compact-record | reject repo | print }

  let diff_content = get-diff --pr-number $pr_number --repo $repo --diff-to $diff_to --diff-from $diff_from
  let length = $diff_content | str stats | get unicode-width
  if ($max_length != 0) and ($length > $max_length) {
    print $'(char nl)(ansi r)The content length ($length) exceeds the maximum limit ($max_length), review skipped.(ansi reset)'
    # Must return here? Or the action won't stop
    exit $ECODE.SUCCESS; return
  }
  print $'Review content length: (ansi g)($length)(ansi reset), current max length: (ansi g)($max_length)(ansi reset)'
  let payload = {
    model: $model,
    stream: false,
    messages: [
      { role: 'system', content: $sys_prompt },
      { role: 'user', content: $"($user_prompt):\n($diff_content)" }
    ]
  }
  if $debug { print $'Code Changes:'; hr-line; print $diff_content }
  print $'(char nl)(ansi g)Waiting for response from Deepseek ...(ansi reset)'
  let response = http post -e -H $header -t application/json $url $payload
  if ($response | is-empty) {
    print $'(ansi r)Oops, No response returned from Deepseek API.(ansi reset)'
    exit $ECODE.SERVER_ERROR
  }
  if $debug { print $'Deepseek Response:'; hr-line; $response | table -e | print }
  if ($response | describe) == 'string' {
    print $'❌ Code review failed！Error: '; hr-line; print $response
    exit $ECODE.SERVER_ERROR
  }
  let review = $response | get -i choices.0.message.content
  if not $is_action {
    print $'Code Review Result:'; hr-line; print $review
  } else {
    gh pr comment $pr_number --body $review --repo $repo
    print $'✅ Code review finished！PR (ansi g)#($pr_number)(ansi reset) review result was posted as a comment.'
  }
  print $'(char nl)Token Usage Info:'; hr-line
  $response.usage | table -e | print
}

# Get the diff content from GitHub PR or local git changes
export def get-diff [
  --repo: string,       # GitHub repository name
  --pr-number: string,  # GitHub PR number
  --diff-to: string,    # Diff to git ref
  --diff-from: string,  # Diff from git ref
] {
  let local_repo = $env.DEFAULT_LOCAL_REPO? | default (pwd)
  if not ($local_repo | path exists) {
    print $'(ansi r)The directory ($local_repo) does not exist.(ansi reset)'
    exit $ECODE.CONDITION_NOT_SATISFIED
  }
  cd $local_repo
  let diff_content = if ($pr_number | is-not-empty) {
      if ($repo | is-empty) {
        print $'(ansi r)Please provide the GitHub repository name by `--repo` option.(ansi reset)'
        exit $ECODE.INVALID_PARAMETER
      }
      gh pr diff $pr_number --repo $repo | str trim
    } else if ($diff_from | is-not-empty) {
      if not (has-ref $diff_from) {
        print $'(ansi r)The specified git ref ($diff_from) does not exist, please check it again.(ansi reset)'
        exit $ECODE.INVALID_PARAMETER
      }
      if ($diff_to | is-not-empty) and not (has-ref $diff_to) {
        print $'(ansi r)The specified git ref ($diff_to) does not exist, please check it again.(ansi reset)'
        exit $ECODE.INVALID_PARAMETER
      }
      git diff $diff_from ($diff_to | default HEAD)
    } else if not (git-check $local_repo --check-repo=1) {
      print $'Current directory ($local_repo) is (ansi r)NOT(ansi reset) a git repo, bye...(char nl)'
      exit $ECODE.CONDITION_NOT_SATISFIED
    } else { git diff }

  if ($diff_content | is-empty) {
    print $'(ansi g)Nothing to review.(ansi reset)'; exit $ECODE.SUCCESS
  }
  $diff_content
}

# Compact the record by removing empty columns
export def compact-record []: record -> record {
  let record = $in
  let empties = $record | columns | filter {|it| $record | get $it | is-empty }
  $record | reject ...$empties
}

# Check if some command available in current shell
export def is-installed [ app: string ] {
  (which $app | length) > 0
}

# Check if git was installed and if current directory is a git repo
export def git-check [
  dest: string,        # The dest dir to check
  --check-repo: int,   # Check if current directory is a git repo
] {
  cd $dest
  if not (is-installed git) {
    print $'You should (ansi r)INSTALL git(ansi reset) first to run this command, bye...'
    exit $ECODE.MISSING_BINARY
  }
  # If we don't need repo check just quit now
  if ($check_repo != 0) {
    let checkRepo = (do -i { git rev-parse --is-inside-work-tree } | complete)
    if not ($checkRepo.stdout =~ 'true') {
      print $'Current directory is (ansi r)NOT(ansi reset) a git repo, bye...(char nl)'
      exit $ECODE.CONDITION_NOT_SATISFIED
    }
  }
  true
}

# Check if a git repo has the specified ref: could be a branch or tag, etc.
export def has-ref [
  ref: string   # The git ref to check
] {
  let checkRepo = (do -i { git rev-parse --is-inside-work-tree } | complete)
  if not ($checkRepo.stdout =~ 'true') { return false }
  # Brackets were required here, or error will occur
  let parse = (do -i { git rev-parse --verify -q $ref } | complete)
  if ($parse.stdout | is-empty) { false } else { true }
}

export def hr-line [
  width?: int = 90,
  --blank-line(-b),
  --with-arrow(-a),
  --color(-c): string = 'g',
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
