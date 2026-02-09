#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/02/12 19:05:20
# Description: Common helpers for DeepSeek-Review
#

use std-rfc/kv ['kv set', 'kv get']

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

export const GITHUB_API_BASE = 'https://api.github.com'

# If current host is Windows
export def windows? [] {
  # Windows / Darwin
  (sys host | get name) == 'Windows'
}

# If current host is macOS
export def mac? [] {
  # Windows / Darwin
  (sys host | get name) == 'Darwin'
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
    let x = $a | get -o $i | default 0
    let y = $b | get -o $i | default 0
    if $x > $y { return 1    }
    if $x < $y { return (-1) }
  }
  0
}

# Check nushell version and notify user to upgrade it if outdated
# Check version once daily and cache the result
export def check-nushell [--debug] {
  const _DATE_FMT = '%Y.%m.%d'
  const V_KEY = 'NU-VERSION-CHECK@DEEPSEEK-REVIEW'
  let version_cached = kv get -u $V_KEY
  let today = date now | format date $_DATE_FMT
  let check = if ($version_cached | is-empty) or $version_cached.date? != $today {
    let $check = try { ({ ...(version check), date: $today }) } catch { ({ current: true }) }
    if $debug { print 'Checking for the latest Nushell version...'; $check | print }
    kv set -u $V_KEY $check --return value
  } else {
    $version_cached
  }
  # If the current version is the latest after user upgrade, return
  if $check.current or (compare-ver $check.latest (version).version) == 0 { return }
  print $'(char nl)                      (ansi yr) WARNING: (ansi reset) Your Nushell is (ansi r)OUTDATED(ansi reset)'
  print $' ------------> Please upgrade Nushell to the latest version: (ansi g)($check.latest)(ansi reset) <------------'
  print -n (char nl)
}

# Converts a .env file into a record
# May be used like this: open .env | load-env
# Works with quoted and unquoted .env files
export def "from env" []: string -> record {
  let input = $in

  # Process escape sequences in double-quoted values using str replace chain
  # Use NUL char as placeholder to avoid replacement conflicts
  let process_escapes = {|content: string|
    $content
      | str replace -a '\\' (char nul)   # Placeholder for \\ to avoid conflicts
      | str replace -a '\n' (char nl)
      | str replace -a '\r' (char cr)
      | str replace -a '\t' (char tab)
      | str replace -a '\"' '"'
      | str replace -a (char nul) '\'    # Restore \\ to single \
  }

  # Parse double-quoted value with escape sequence support
  let parse_double_quoted = {|val: string|
    let matched = ($val | parse -r '^"(?P<content>(?:[^"\\]|\\.)*)"')
    if ($matched | is-empty) { $val | str trim -c '"' } else { do $process_escapes $matched.0.content }
  }

  # Parse single-quoted value (no escape processing)
  let parse_single_quoted = {|val: string|
    let matched = ($val | parse -r "^'(?P<content>[^']*)'")
    if ($matched | is-empty) { $val | str trim -c "'" } else { $matched.0.content }
  }

  # Parse unquoted value: handle escaped hash (\#) and strip inline comments
  let parse_unquoted = {|val: string|
    $val
      | str replace -a '\#' (char nul)    # Placeholder for \#
      | split row '#'                     # Split by comment delimiter
      | first                             # Take content before first #
      | str replace -a (char nul) '#'     # Restore \# to #
      | str trim
  }

  # Parse value based on its format
  let parse_value = {|val: string|
    match $val {
      $v if ($v | str starts-with '"') => { do $parse_double_quoted $v }
      $v if ($v | str starts-with "'") => { do $parse_single_quoted $v }
      _ => { do $parse_unquoted $val }
    }
  }

  let parsed = $input | lines
    | str trim
    | compact -e
    | where {|line| not ($line | str starts-with '#') }
    | parse "{key}={value}"
    | update key {|row| $row.key | str trim | str replace -r '^export\s+' '' }
    | update value {|row| do $parse_value ($row.value | str trim) }

  if ($parsed | is-empty) { {} } else { $parsed | transpose -r -d -l }
}

# Compact the record by removing empty columns
export def compact-record []: record -> record {
  let record = $in
  let empties = $record | columns | where {|it| $record | get $it | is-empty }
  $record | reject ...$empties
}

# Check if some command available in current shell
export def is-installed [ app: string ] {
  (which $app | length) > 0
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
      # Put `complete` inside `do` block to avoid pipefail error in Nushell 0.110+
      do { git rev-parse --is-inside-work-tree | complete }
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
  # Put `complete` inside `do` block to avoid pipefail error in Nushell 0.110+
  let parse = (do { git rev-parse --verify -q $ref | complete })
  if ($parse.stdout | is-empty) { false } else { true }
}

# Notify the user that the `CHAT_TOKEN` hasn't been configured
export const NO_TOKEN_TIP = (
  "**Notice:** It looks like you're using [`hustcer/deepseek-review`](https://github.com/hustcer/deepseek-review), but the `CHAT_TOKEN` hasn't " +
  "been configured in your repo's **Variables/Secrets**. Please ensure this token is set for proper functionality. For step-by-step guidance, refer " +
  "to the **CHAT_TOKEN Config** section of [README](https://github.com/hustcer/deepseek-review/blob/main/README.md#code-review-with-github-action).")
