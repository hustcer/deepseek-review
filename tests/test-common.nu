
use std/assert

use ../nu/common.nu [compare-ver, 'from env', is-installed, has-ref, git-check]

#[test]
def 'compare-ver：v1.0.0 is greater than v0.999.0' [] {
  assert equal (compare-ver 1.0.0 0.999.0) 1
  assert equal (compare-ver v1.0.0 v0.999.0) 1
}

#[test]
def 'compare-ver：v1.0.1 is equal to v1.0.1' [] {
  assert equal (compare-ver 1.0.1 1.0.1) 0
}

#[test]
def 'compare-ver：v1.0.0 is equal to v1' [] {
  assert equal (compare-ver v1.0.0 v1) 0
}

#[test]
def 'compare-ver：v1.0.1 is greater than v1' [] {
  assert equal (compare-ver v1.0.1 v1) 1
}

#[test]
def 'compare-ver：v1.0.1 is lower than v1.1.0' [] {
  assert equal (compare-ver 1.0.1 1.1.0) (-1)
}

#[test]
def 'from-env：.env load should work' [] {
  open tests/resources/.env.test | from env | load-env
  assert equal $env.CHAT_MODEL deepseek-chat
  assert equal $env.BASE_URL https://api.deepseek.ai
  assert equal $env.TEMPERATURE '1.0'
  assert equal $env.MAX_LENGTH '0'
  assert equal $env.USER_PROMPT 'Please review the following code changes'
}

#[test]
def 'is-installed：binary install check should work' [] {
  assert equal (is-installed git) true
  assert equal (is-installed abc) false
}

#[test]
def 'has-ref：git repo should has HEAD ref' [] {
  assert equal (has-ref HEAD) true
  assert equal (has-ref 0000) false
}

#[test]
def 'git-check：current dir is a git repo' [] {
  assert equal (git-check (pwd) --check-repo=1) true
}
