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

use common.nu [ECODE, has-ref]

export def 'make-release' [
  --update-log(-u)    # Add flag to enable updating CHANGELOG.md
] {

  cd $env.DEEPSEEK_REVIEW_PATH
  let release_ver = (open meta.json | get actionVer)

  if (has-ref $release_ver) {
    print $'The version ($release_ver) already exists, Please choose another version.(char nl)'
    exit $ECODE.CONDITION_NOT_SATISFIED
  }
  let major_tag = $release_ver | split row '.' | first
  let status_check = (git status --porcelain)
  if not ($status_check | is-empty) {
    print $'You have uncommitted changes, please commit them and try `release` again!(char nl)'
    exit $ECODE.CONDITION_NOT_SATISFIED
  }
  if ($update_log) {
    git cliff --unreleased --tag $release_ver --prepend CHANGELOG.md;
    git commit CHANGELOG.md -m $'update CHANGELOG.md for ($release_ver)'
  }
  # Delete tags that not exist in remote repo
  git fetch origin --prune '+refs/tags/*:refs/tags/*'
  let commit_msg = $'A new release for version: ($release_ver) created by Release command of deepseek-review.'
  git tag $release_ver -am $commit_msg;
  # Remove local major version tag if exists and ignore errors
  do -i { git tag -d $major_tag | complete | ignore }
  git checkout $release_ver; git tag $major_tag
  git push origin $major_tag $release_ver --force
}
