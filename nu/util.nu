#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/04/02 20:02:15
#

use common.nu [ECODE, is-installed, compare-ver, windows?, mac?]

# AWK family version check for both awk and gawk
#  awk: awk version 20250116 -> 20250116
# gawk: GNU Awk 5.3.1, API 4.0, (GNU MPFR 4.2.1, GNU MP 6.3.0) -> 5.3.1
def get-awk-ver [awk_bin: string] {
  ^$awk_bin --version | lines | first | split row , | first | split row ' ' | last
}

# Prepare gawk for macOS
export def prepare-awk [] {
  const MIN_GAWK_VERSION = '5.3.1'
  const MIN_AWK_VERSION = '20250116'
  let awk_installed = is-installed awk
  let gawk_installed = is-installed gawk

  if $awk_installed {
    let awk_version = get-awk-ver awk
    if (compare-ver $awk_version $MIN_AWK_VERSION) >= 0 {
      print $'Current awk version: ($awk_version)'
      return 'awk'
    }
  }
  if $gawk_installed {
    let gawk_version = get-awk-ver gawk
    if (compare-ver $gawk_version $MIN_GAWK_VERSION) >= 0 {
      print $'Current gawk version: ($gawk_version)'
      return 'gawk'
    } else if (windows?) and ($env.GITHUB_ACTIONS? == 'true') {
      let awk_info = (install-gawk-for-actions)
      print $'Current gawk version: ($awk_info.version)'
      return $awk_info.awk_bin
    }
  }
  if (mac?) and (is-installed brew) {
    brew install gawk
    print $'Current gawk version: (get-awk-ver gawk)'
    return 'gawk'
  }
  if (not $awk_installed) and (not $gawk_installed) {
    print $'(ansi r)Neither `awk` nor `gawk` is installed, please install the latest version of `gawk`.(ansi reset)'
    exit $ECODE.MISSING_BINARY
  }
  print $'Current awk version: (get-awk-ver awk)'
  'awk'
}

# Convert glob patterns to regex patterns
# Pass in *.nu directly as a regular expression does not work, because * in
# a regular expression needs to be attached to the previous pattern, the correct
# form should be .* So we should convert each glob pattern to a regex pattern:
# 1. Convert * to .*
# 2. Convert ? to . (optional, as needed)
# 3. Convert / to \/
def glob-to-regex [patterns: list<string>] {
  # Handle empty patterns list
  if ($patterns | length) == 0 { return '' }

  # Define a mapping of characters to escape
  let regex_escapes = {
    # Escape special regex characters first
    "\\.": "\\\\.",
    "\\+": "\\\\+",
    "\\^": "\\\\^",
    "\\$": "\\\\$",
    "\\(": "\\\\(",
    "\\)": "\\\\)",
    "\\[": "\\\\[",
    "\\]": "\\\\]",
    "\\{": "\\\\{",
    "\\}": "\\\\}",
    "\\|": "\\\\|",
    # Then convert glob patterns to regex patterns
    "*": ".*",
    "?": ".",
    "/": "\\/",
  }

  $patterns
    | each { |pat|
        $regex_escapes | columns | reduce -f $pat { |k, acc|
          $acc | str replace -a $k ($regex_escapes | get $k)
        }
      }
    | str join '|'
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

# Check if the git command is safe to run in the shell
# Validate command examples:
#  - git show
#  - git diff
#  - git show head~1
#  - git diff 2393375 71f5a31
#  - git diff 2393375 71f5a31 nu/*
#  - git diff 2393375 71f5a31 :!nu/*
export def is-safe-git [cmd: string] {
  let normalized_cmd = ($cmd | str trim | str downcase)

  # Define allowed command patterns with named capture groups for better validation
  let git_cmd_pattern = '^git\s+(show|diff)(?:\s+(?:[a-zA-Z0-9_\-\.~/]+(?::[a-zA-Z0-9_\-\.\*\/]+)?)){0,3}(?:\s+(?::[!]?)?[a-zA-Z0-9_\-\.\*\/]+){0,2}$'

  if ($normalized_cmd | find -r $git_cmd_pattern | is-empty) {
    print $'(ansi r)Invalid git command format. (ansi g)Only simple `git show` or `git diff` commands are allowed.(ansi reset)'
    return false
  }
  true
}

# Setup scoop and install gawk for GitHub Windows runners
# This command is essential for resolving the issue of simultaneously
# applying include and exclude patterns on GitHub's Windows runners.
def install-gawk-for-actions [] {
  # Install scoop using PowerShell
  pwsh -c r#'
    Invoke-Expression (New-Object System.Net.WebClient).DownloadString("https://get.scoop.sh")
    $env:Path = "$env:USERPROFILE\scoop\shims;" + $env:Path; scoop update; scoop install gawk
    '# | complete | get stdout | print
  let awk_bin = $'($nu.home-dir)/scoop/shims/gawk.exe'
  let version = get-awk-ver $awk_bin
  { awk_bin: $awk_bin, version: $version }
}
