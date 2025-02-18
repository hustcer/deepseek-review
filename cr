#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/02/08 19:02:15
# Description: A wrapper for nu/review.nu as the main entry point of the project.

use nu/config.nu *
use nu/common.nu [hr-line, check-nushell, ECODE]
use nu/review.nu [deepseek-review]

# Use DeepSeek AI to review code changes locally or in GitHub Actions
def main [
  token?: string,           # Your DeepSeek API token, fallback to CHAT_TOKEN env var
  --debug(-d),              # Debug mode
  --repo(-r): string,       # GitHub repo name, e.g. hustcer/deepseek-review, or local repo path / alias
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
] {

  check-nushell
  config-check
  config-load --debug=$debug --repo=$repo --model=$model
  (
    deepseek-review $token
      --repo=$repo
      --debug=$debug
      --include=$include
      --exclude=$exclude
      --model=$env.CHAT_MODEL
      --base-url=$base_url
      --gh-token=$gh_token
      --diff-to=$diff_to
      --diff-from=$diff_from
      --patch-cmd=$patch_cmd
      --pr-number=$pr_number
      --max-length=$max_length
      --sys-prompt=$sys_prompt
      --user-prompt=$user_prompt
      --temperature=$temperature
  )
}
