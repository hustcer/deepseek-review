#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/02/08 19:02:15
# Description: A wrapper for nu/review.nu as the main entry point of the project.

use nu/review.nu ['from env', ECODE]

# Use DeepSeek AI to review code changes locally or in GitHub Actions
def --wrapped main [...rest] {
  if not ('.env' | path exists) {
    print $'Please refer to (ansi g)`.env.example`(ansi reset) to create a (ansi r)`.env`(ansi reset) file in the root directory of the project.'
    exit $ECODE.MISSING_DEPENDENCY
  }
  open .env | load-env
  nu $'($env.FILE_PWD)/nu/review.nu' ...$rest
}
