#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/02/12 19:05:20
# Description: Common helpers for DeepSeek-Review
#

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
    let x = $a | get -i $i | default 0
    let y = $b | get -i $i | default 0
    if $x > $y { return 1    }
    if $x < $y { return (-1) }
  }
  0
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

# Notify the user that the `CHAT_TOKEN` hasn't been configured
export const NO_TOKEN_TIP = (
  "**Notice:** It looks like you're using [`hustcer/deepseek-review`](https://github.com/hustcer/deepseek-review), but the `CHAT_TOKEN` hasn't" +
  "been configured in your repo's Variables/Secrets. Please ensure this token is set for proper functionality. For step-by-step guidance, refer" +
  "to the **CHAT_TOKEN Config** section of [README](https://github.com/hustcer/deepseek-review/blob/main/README.md#code-review-with-github-action).")
