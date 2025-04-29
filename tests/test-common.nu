
use std/assert
use std/testing *

use ../nu/common.nu [
  compare-ver, 'from env', is-installed, has-ref,
  git-check, compact-record, is-repo, windows?, mac?,
]

@test
def 'compare-ver：v1.0.0 is greater than v0.999.0' [] {
  assert equal (compare-ver 1.0.0 0.999.0) 1
  assert equal (compare-ver v1.0.0 v0.999.0) 1
}

@test
def 'compare-ver：v1.0.1 is equal to v1.0.1' [] {
  assert equal (compare-ver 1.0.1 1.0.1) 0
}

@test
def 'compare-ver：v1.0.0 is equal to v1' [] {
  assert equal (compare-ver v1.0.0 v1) 0
}

@test
def 'compare-ver：v1.0.1 is greater than v1' [] {
  assert equal (compare-ver v1.0.1 v1) 1
}

@test
def 'compare-ver：v1.0.1 is lower than v1.1.0' [] {
  assert less (compare-ver 1.0.1 v1.1) 0
  assert equal (compare-ver 1.0.1 1.1.0) (-1)
}

@test
def 'from-env：.env load should work' [] {
  open tests/resources/.env.test | from env | load-env
  assert equal $env.CHAT_MODEL deepseek-chat
  assert equal $env.BASE_URL https://api.deepseek.ai
  assert equal $env.TEMPERATURE '1.0'
  assert equal $env.MAX_LENGTH '0'
  assert equal $env.USER_PROMPT 'Please review the following code changes'
}

@test
def 'is-installed：binary install check should work' [] {
  assert equal (is-installed git) true
  assert equal (is-installed abc) false
}

@test
def 'has-ref：git repo should has HEAD ref' [] {
  assert equal (has-ref HEAD) true
  assert equal (has-ref 0000) false
}

@test
def 'is-repo：current dir is a git repo' [] {
  assert equal (is-repo) true
}

@test
def 'git-check：current dir is a git repo' [] {
  assert equal (git-check (pwd) --check-repo=1) true
}

@test
def 'compact-record：should work as expected' [] {
  assert equal ({a: null, b: '', c: 'abc' } | compact-record) { c: 'abc' }
  assert equal ({a: null, b: 0, c: 1, e: { f: 'g' } } | compact-record) { b: 0, c: 1, e: { f: 'g' } }
}

@test
def 'OS check should work as expected' [] {
  # `$env.RUNNER_OS` Possible values are Linux, Windows, or macOS in GitHub Actions
  match $nu.os-info.name {
    'windows' => {
      assert equal (mac?) false
      assert equal (windows?) true
      if ($env.RUNNER_OS? | is-not-empty) {
        assert equal $env.RUNNER_OS Windows
      }
    }
    'macos' => {
      assert equal (mac?) true
      assert equal (windows?) false
      if ($env.RUNNER_OS? | is-not-empty) {
        assert equal $env.RUNNER_OS macOS
      }
    }
    _ => {
      assert equal (mac?) false
      assert equal (windows?) false
      if ($env.RUNNER_OS? | is-not-empty) {
        assert equal $env.RUNNER_OS Linux
      }
    }
  }
}
