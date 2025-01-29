#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/01/29 12:56:56
# Description: Script to release deepseek-review
#
# TODO:
#   [√] Make sure the release tag does not exist;
#   [√] Make sure there are no uncommitted changes;
#   [√] Update change log if required;
#   [√] Create a release tag and push it to the remote repo;
# Usage:
#   Change `version` in meta.json and then run: `just release` OR `just release -u`

export def 'make-release' [
  --update-log(-u)    # Add flag to enable updating CHANGELOG.md
] {

  cd $env.DEEPSEEK_REVIEW_PATH
  let releaseVer = (open meta.json | get actionVer)

  if (has-ref $releaseVer) {
  	echo $'The version ($releaseVer) already exists, Please choose another version.(char nl)'
  	exit 5
  }
  let majorTag = $releaseVer | split row '.' | first
  let statusCheck = (git status --porcelain)
  if not ($statusCheck | is-empty) {
  	echo $'You have uncommitted changes, please commit them and try `release` again!(char nl)'
  	exit 5
  }
  if ($update_log) {
    git cliff --unreleased --tag $releaseVer --prepend CHANGELOG.md;
    git commit CHANGELOG.md -m $'update CHANGELOG.md for ($releaseVer)'
  }
  # Delete tags that not exist in remote repo
  git fetch origin --prune '+refs/tags/*:refs/tags/*'
  let commitMsg = $'A new release for version: ($releaseVer) created by Release command of deepseek-review.'
  git tag $releaseVer -am $commitMsg;
  # Remove local major version tag if exists and ignore errors
  do -i { git tag -d $majorTag | complete | ignore }
  git checkout $releaseVer; git tag $majorTag
  git push origin $majorTag $releaseVer --force
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
