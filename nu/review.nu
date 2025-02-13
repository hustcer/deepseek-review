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

use kv.nu *

# Commonly used exit codes
export const ECODE = {
  SUCCESS: 0,
  OUTDATED: 1,
  AUTH_FAILED: 2,
  SERVER_ERROR: 3,
  MISSING_BINARY: 5,
  INVALID_PARAMETER: 6,
  MISSING_DEPENDENCY: 7,
  CONDITION_NOT_SATISFIED: 8,
}

const RESPONSE_END = 'data: [DONE]'

const GITHUB_API_BASE = 'https://api.github.com'

# It takes longer to respond to requests made with unknown/rare user agents.
# When make http post pretend to be curl, it gets a response just as quickly as curl.
const HTTP_HEADERS = [User-Agent curl/8.9]

const DEFAULT_OPTIONS = {
  MODEL: 'deepseek-chat',
  TEMPERATURE: 1.0,
  BASE_URL: 'https://api.deepseek.com',
  USER_PROMPT: 'Please review the following code changes:',
  SYS_PROMPT: 'You are a professional code review assistant responsible for analyzing code changes in GitHub Pull Requests. Identify potential issues such as code style violations, logical errors, security vulnerabilities, and provide improvement suggestions. Clearly list the problems and recommendations in a concise manner.',
}

# If the PR title or body contains any of these keywords, skip the review
const IGNORE_REVIEW_KEYWORDS = ['skip review' 'skip cr']

# Use DeepSeek AI to review code changes locally or in GitHub Actions
export def --env deepseek-review [
  token?: string,           # Your DeepSeek API token, fallback to CHAT_TOKEN env var
  --debug(-d),              # Debug mode
  --repo(-r): string,       # GitHub repository name, e.g. hustcer/deepseek-review
  --pr-number(-n): string,  # GitHub PR number
  --gh-token(-k): string,   # Your GitHub token, fallback to GITHUB_TOKEN env var
  --diff-to(-t): string,    # Diff to git REF
  --diff-from(-f): string,  # Diff from git REF
  --patch-cmd(-c): string,  # The `git show` or `git diff` command to get the diff content, for local CR only
  --max-length(-l): int,    # Maximum length of the content for review, 0 means no limit.
  --model(-m): string,      # Model name, or read from CHAT_MODEL env var, `deepseek-chat` by default
  --base-url(-b): string,   # DeepSeek API base URL, fallback to BASE_URL env var
  --sys-prompt(-s): string  # Default to $DEFAULT_OPTIONS.SYS_PROMPT,
  --user-prompt(-u): string # Default to $DEFAULT_OPTIONS.USER_PROMPT,
  --include(-i): string,    # Comma separated file patterns to include in the code review
  --exclude(-x): string,    # Comma separated file patterns to exclude in the code review
  --temperature(-T): float, # Temperature for the model, between `0` and `2`, default value `1.0`, Only for V3
]: nothing -> nothing {

  $env.config.table.mode = 'psql'
  let is_action = ($env.GITHUB_ACTIONS? == 'true')
  let stream = if $is_action { false } else { true }
  let token = $token | default $env.CHAT_TOKEN?
  let repo = $repo | default $env.DEFAULT_GITHUB_REPO?
  let CHAT_HEADER = [Authorization $'Bearer ($token)']
  let local_repo = $env.DEFAULT_LOCAL_REPO? | default (pwd)
  let model = $model | default $env.CHAT_MODEL? | default $DEFAULT_OPTIONS.MODEL
  let base_url = $base_url | default $env.BASE_URL? | default $DEFAULT_OPTIONS.BASE_URL
  let max_length = try { $max_length | default ($env.MAX_LENGTH? | default 0 | into int) } catch { 0 }
  let temperature = try { $temperature | default $env.TEMPERATURE? | default $DEFAULT_OPTIONS.TEMPERATURE | into float } catch { $DEFAULT_OPTIONS.TEMPERATURE }
  if ($temperature < 0) or ($temperature > 2) {
    print $'(ansi r)Invalid temperature value, should be in the range of 0 to 2.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
  let url = $'($base_url)/chat/completions'
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

  if ($token | is-empty) {
    print $'(ansi r)Please provide your DeepSeek API token by setting `CHAT_TOKEN` or passing it as an argument.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
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
  let sys_prompt = $sys_prompt | default (load-prompt-from-env SYSTEM_PROMPT) | default $DEFAULT_OPTIONS.SYS_PROMPT
  let user_prompt = $user_prompt | default (load-prompt-from-env USER_PROMPT) | default $DEFAULT_OPTIONS.USER_PROMPT
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
  print $'(char nl)Waiting for response from (ansi g)($base_url)(ansi reset) ...'
  if $stream { streaming-output $url $payload --headers $CHAT_HEADER --debug=$debug; return }

  let response = http post -e -H $CHAT_HEADER -t application/json $url $payload
  if ($response | is-empty) {
    print $'(ansi r)Oops, No response returned from ($base_url) ...(ansi reset)'
    exit $ECODE.SERVER_ERROR
  }
  if $debug { print $'DeepSeek Model Response:'; hr-line; $response | table -e | print }
  if ($response | describe) == 'string' {
    print $'✖️ Code review failed！Error: '; hr-line; print $response
    exit $ECODE.SERVER_ERROR
  }
  let reason = $response | get -i choices.0.message.reasoning_content
  let review = $response | get -i choices.0.message.content
  let result = ['<details>' '<summary> Reasoning Details</summary>' $reason "</details>\n" $review] | str join "\n"
  if ($review | is-empty) {
    print $'✖️ Code review failed！No review result returned from ($base_url) ...'
    exit $ECODE.SERVER_ERROR
  }
  let result = if ($reason | is-empty) { $review } else { $result }
  if not $is_action {
    print $'Code Review Result:'; hr-line; print $result
  } else {
    let BASE_HEADER = [Authorization $'Bearer ($env.GH_TOKEN)' Accept application/vnd.github.v3+json ...$HTTP_HEADERS]
    http post -t application/json -H $BASE_HEADER $'($GITHUB_API_BASE)/repos/($repo)/issues/($pr_number)/comments' { body: $result }
    print $'✅ Code review finished！PR (ansi g)#($pr_number)(ansi reset) review result was posted as a comment.'
  }
  print $'(char nl)Token Usage:'; hr-line
  $response.usage | table -e | print
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
        let other_error  = $type =~ '^string' and $res !~ 'data: '
        if $record_error or $other_error {
          $res | table -e | print
          exit $ECODE.SERVER_ERROR
        }
      }
    | try { lines } catch { print $'(ansi r)Error Happened ...(ansi reset)'; exit $ECODE.SERVER_ERROR }
    | each {|line|
        if $line == $RESPONSE_END { return }
        if ($line | is-empty) { return }
        let $last = $line | str substring 6.. | from json
        if $last == '-alive' { print $last; return }
        if $debug { $last | to json | kv set last-reply }
        $last | get -i choices.0.delta | if ($in | is-not-empty) {
          let delta = $in
          if ($delta.reasoning_content? | is-not-empty) { kv set reasoning ((kv get reasoning) + 1) }
          if (kv get reasoning) == 1 { print $'(char nl)Reasoning Details:'; hr-line }
          if ($delta.content | is-not-empty) { kv set content ((kv get content) + 1) }
          if (kv get content) == 1 { print $'(char nl)Review Details:'; hr-line }
          print -n ($delta.reasoning_content? | default $delta.content)
        }
      }

  if $debug and (kv get last-reply | is-not-empty) {
    print $'(char nl)(char nl)Model & Token Usage:'; hr-line
    kv get last-reply | from json | select -i model usage | table -e | print
  }
}

# Load the prompt content from the specified env var
export def load-prompt-from-env [
  prompt_key: string,
] {
  let prompt = $env | get -i $prompt_key | default ''
  if ($prompt !~ '.ya?ml') { return $prompt }
  let parts = $prompt | split row :
  if ($parts | length) != 2 {
    print $'(ansi r)Invalid prompt format: expected path:key for YAML files.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
  let key = $parts | last
  let path = $parts | first
  try { open $path | get -i $key } catch {
    print $'(ansi r)Failed to load the prompt content from ($path), please check it again.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
}

# Get the diff content from GitHub PR or local git changes
export def get-diff [
  --repo: string,       # GitHub repository name
  --pr-number: string,  # GitHub PR number
  --diff-to: string,    # Diff to git ref
  --diff-from: string,  # Diff from git ref
  --include: string,    # Comma separated file patterns to include in the code review
  --exclude: string,    # Comma separated file patterns to exclude in the code review
  --patch-cmd: string,  # The `git show` or `git diff` command to get the diff content
] {
  let BASE_HEADER = [Authorization $'Bearer ($env.GH_TOKEN)' Accept application/vnd.github.v3+json]
  let DIFF_HEADER = [Authorization $'Bearer ($env.GH_TOKEN)' Accept application/vnd.github.v3.diff]
  let local_repo = $env.DEFAULT_LOCAL_REPO? | default (pwd)
  if not ($local_repo | path exists) {
    print $'(ansi r)The directory ($local_repo) does not exist.(ansi reset)'
    exit $ECODE.CONDITION_NOT_SATISFIED
  }
  cd $local_repo
  mut content = if ($pr_number | is-not-empty) {
    if ($repo | is-empty) {
      print $'(ansi r)Please provide the GitHub repository name by `--repo` option.(ansi reset)'
      exit $ECODE.INVALID_PARAMETER
    }
    # TODO: Ignore keywords checking when triggering by mentioning the bot
    let description = http get -H $BASE_HEADER $'($GITHUB_API_BASE)/repos/($repo)/pulls/($pr_number)'
                                        | select title body | values | str join "\n"
    if ($IGNORE_REVIEW_KEYWORDS | any {|it| $description =~ $it }) {
      print $'(ansi r)The PR title or body contains keywords to skip the review, bye...(ansi reset)'
      exit $ECODE.SUCCESS
    }
    http get -H $DIFF_HEADER $'($GITHUB_API_BASE)/repos/($repo)/pulls/($pr_number)' | str trim
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
  } else if ($patch_cmd | is-not-empty) {
    let valid = is-safe-git $patch_cmd
    if not $valid { exit $ECODE.INVALID_PARAMETER }
    nu -c $patch_cmd
  } else { git diff }

  if ($content | is-empty) {
    print $'(ansi g)Nothing to review.(ansi reset)'; exit $ECODE.SUCCESS
  }
  let awk_bin = (prepare-awk)
  let outdated_awk = $'If you are using an (ansi r)outdated awk version(ansi reset), please upgrade to the latest version or use gawk latest instead.'
  if ($include | is-not-empty) {
    let patterns = $include | split row ','
    $content = $content | try { ^$awk_bin (generate-include-regex $patterns) } catch { print $outdated_awk; exit $ECODE.OUTDATED }
  }
  if ($exclude | is-not-empty) {
    let patterns = $exclude | split row ','
    $content = $content | try { ^$awk_bin (generate-exclude-regex $patterns) } catch { print $outdated_awk; exit $ECODE.OUTDATED }
  }
  $content
}

# Prepare gawk for macOS
export def prepare-awk [] {
  const MIN_GAWK_VERSION = '5.3.1'
  const MIN_AWK_VERSION = '20250116'
  let awk_installed = is-installed awk
  let gawk_installed = is-installed gawk

  if $awk_installed {
    # AWK family version check for both awk and gawk
    #  awk: awk version 20250116 -> 20250116
    # gawk: GNU Awk 5.3.1, API 4.0, (GNU MPFR 4.2.1, GNU MP 6.3.0) -> 5.3.1
    let awk_version = awk --version | lines | first | split row , | first | split row ' ' | last
    print $'Current awk version: ($awk_version)'
    if (compare-ver $awk_version $MIN_AWK_VERSION) >= 0 { return 'awk' }
  }
  if $gawk_installed {
    let gawk_version = gawk --version | lines | first | split row , | first | split row ' ' | last
    print $'Current gawk version: ($gawk_version)'
    if (compare-ver $gawk_version $MIN_GAWK_VERSION) >= 0 { return 'gawk' }
  }
  if (sys host | get name) == 'Darwin' and (is-installed brew) {
    brew install gawk
    print $'Current gawk version: (gawk --version | lines | first)'
    return 'gawk'
  }
  if (not $awk_installed) and (not $gawk_installed) {
    print $'(ansi r)Neither `awk` nor `gawk` is installed, please install the latest version of `gawk`.(ansi reset)'
    exit $ECODE.MISSING_BINARY
  }
  'awk'
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
    if not (is-repo) {
      print $'Current directory is (ansi r)NOT(ansi reset) a git repo, bye...(char nl)'
      exit $ECODE.CONDITION_NOT_SATISFIED
    }
  }
  true
}

# Check if current directory is a git repo
export def is-repo [] {
  let checkRepo = try {
      do -i { git rev-parse --is-inside-work-tree } | complete
    } catch {
      ({ stdout: 'false' })
    }
  if ($checkRepo.stdout =~ 'true') { true } else { false }
}

# Check if a git repo has the specified ref: could be a branch or tag, etc.
export def has-ref [
  ref: string   # The git ref to check
] {
  if not (is-repo) { return false }
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
  if $blank_line { char nl | print -n }
}

# Convert glob patterns to regex patterns
# Pass in *.nu directly as a regular expression does not work, because * in
# a regular expression needs to be attached to the previous pattern, the correct
# form should be .* So we should convert each glob pattern to a regex pattern:
# 1. Convert * to .*
# 2. Convert ? to . (optional, as needed)
# 3. Convert / to \/
def glob-to-regex [patterns: list<string>] {
  $patterns
    | each { |pat|
        $pat | str replace "*" ".*" | str replace "?" "." | str replace "/" "\\/"
      }
    | str join "|"
}

# Generate the awk include regex pattern string for the specified patterns
export def generate-include-regex [patterns: list<string>] {
  let pattern = glob-to-regex $patterns
  $"/^diff --git/{p=/^diff --git a\\/($pattern)/}p"
}

# Generate the awk exclude regex pattern string for the specified patterns
export def generate-exclude-regex [patterns: list<string>] {
  let pattern = glob-to-regex $patterns
  $"/^diff --git/{p=/^diff --git a\\/($pattern)/}!p"
}

# Converts a .env file into a record
# may be used like this: open .env | load-env
# works with quoted and unquoted .env files
export def 'from env' []: string -> record {
  lines
    | split column '#' # remove comments
    | get column1
    | parse '{key}={value}'
    | update value {
        str trim                        # Trim whitespace between value and inline comments
          | str trim -c '"'             # unquote double-quoted values
          | str trim -c "'"             # unquote single-quoted values
          | str replace -a "\\n" "\n"   # replace `\n` with newline char
          | str replace -a "\\r" "\r"   # replace `\r` with carriage return
          | str replace -a "\\t" "\t"   # replace `\t` with tab
      }
    | transpose -r -d
}

# Compare two version number, return `1` if first one is higher than second one,
# Return `0` if they are equal, otherwise return `-1`
# Format: Expects semantic version strings (major.minor.patch)
#   - Optional 'v' prefix
#   - Pre-release suffixes (-beta, -rc, etc.) are ignored
#   - Missing segments default to 0
export def compare-ver [v1: string, v2: string] {
  # Parse the version number: remove pre-release and build information,
  # only take the main version part, and convert it to a list of numbers
  def parse-ver [v: string] {
    $v | str downcase | str trim -c v | str trim
       | split row - | first | split row . | each { into int }
  }
  let a = parse-ver $v1
  let b = parse-ver $v2
  # Compare the major, minor, and patch parts; fill in the missing parts with 0
  # If you want to compare more parts use the following code:
  # for i in 0..([2 ($a | length) ($b | length)] | math max)
  for i in 0..2 {
    let x = $a | get -i $i | default 0
    let y = $b | get -i $i | default 0
    if $x > $y { return 1    }
    if $x < $y { return (-1) }
  }
  0
}

# Check if the git command is safe to run in the shell
# Validate command examples:
#  - git show
#  - git diff
#  - git show head~1
#  - git diff --since=2025-02-09 HEAD
#  - git diff 2393375 71f5a31
#  - git diff 2393375 71f5a31 nu/*
#  - git diff 2393375 71f5a31 :!nu/*
export def is-safe-git [cmd: string] {
  # Normalize the command string by trimming and converting to lowercase
  let normalized_cmd = ($cmd | str trim | str downcase)

  # More strict regex for git commands, allow:
  # 1. --since parameter with ISO date format
  # 2. File path patterns with or without colon (e.g. :!nu/*, nu/*)
  let allowed_regex = '^git\s+(show|diff)(?:\s+(?:--since=\d{4}-\d{2}-\d{2}|[a-zA-Z0-9_\-\.~/]+))*(?:\s+(?::[!]?)?[a-zA-Z0-9_\-\.\*\/]+)?$'

  # Dangerous patterns to check (expanded list)
  let dangerous_patterns = [
    # Command chaining/injection
    ';', '&&', '||', '|',
    # Shell expansion
    '?', '[', ']', '{', '}',
    # Command substitution
    '`', '$(',
    # IO redirection
    '>', '>>', '<', '<<',
    # Special characters
    '\n', '\r', '\t',
    # Path traversal
    '..',
    # Environment variables
    '$', '%',
    # Quotes that might be used for injection
    '"', "'"
  ]

  # First check: Command must match the allowed pattern
  if ($normalized_cmd | find -r $allowed_regex | is-empty) {
    print $'ERROR: Invalid git command format. (ansi r)Only simple `git show` or `git diff` commands are allowed(ansi reset).'
    return false
  }

  # Second check: No dangerous patterns allowed
  for pattern in $dangerous_patterns {
    if ($cmd | str contains $pattern) {
      print $'(ansi r)ERROR: Dangerous pattern detected: `($pattern)`(ansi reset)'
      return false
    }
  }

  # Third check: Command parts validation (increased limit to accommodate path patterns)
  let cmd_parts = $normalized_cmd | split row ' '
  if ($cmd_parts | length) > 6 {
    print $'ERROR: Command too complex. (ansi r)Only simple `git show` or `git diff` commands are allowed(ansi reset).'
    return false
  }

  true
}

alias main = deepseek-review
