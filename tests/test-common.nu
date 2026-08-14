
use std/assert
use std/testing *

use ../nu/common.nu [
  compare-ver, 'from env', is-installed, has-ref,
  git-check, compact-record, is-repo, windows?, mac?,
  ECODE, GITHUB_API_BASE, NO_TOKEN_TIP,
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
  assert equal $env.CHAT_MODEL deepseek-v4-flash
  assert equal $env.BASE_URL https://api.deepseek.com
  assert equal $env.TEMPERATURE '1.0'
  assert equal $env.MAX_LENGTH '0'
  assert equal $env.THINKING 'false'
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

@test
def 'compare-ver：pre-release suffixes are ignored' [] {
  # Documented behavior: everything after the first `-` is dropped, so a
  # pre-release compares equal to its final release. `check-nushell` relies on
  # this to avoid nagging users running a nightly of the latest version.
  assert equal (compare-ver 1.0.0-beta 1.0.0) 0
  assert equal (compare-ver v1.0.0-rc.1 v1.0.0) 0
  assert equal (compare-ver 0.114.2-nightly.32 0.114.1) 1
  assert equal (compare-ver 0.114.0-nightly.1 0.115.0) (-1)
}

@test
def 'compare-ver：is case insensitive and tolerates whitespace' [] {
  assert equal (compare-ver V1.2.3 v1.2.3) 0
  assert equal (compare-ver ' v1.2.3 ' '1.2.3') 0
}

@test
def 'compare-ver：only the first three segments are significant' [] {
  # `for i in 0..2` caps the comparison at major.minor.patch — a fourth segment
  # never breaks the tie. Locked in so a future rewrite is a conscious choice.
  assert equal (compare-ver 1.2.3.4 1.2.3.9) 0
  assert equal (compare-ver 1.2.3.4 1.2.4.0) (-1)
}

@test
def 'compare-ver：handles awk style date versions' [] {
  # `prepare-awk` feeds this command bare `awk` versions like `20250116`,
  # which have a single segment and are far outside semver range.
  assert equal (compare-ver 20250116 20250116) 0
  assert equal (compare-ver 20260101 20250116) 1
  assert equal (compare-ver 20240101 20250116) (-1)
}

@test
def 'from-env：quoted values and escape sequences' [] {
  # Double quotes process escapes, single quotes do not.
  assert equal (r#'X="a\nb"'# | from env | get X) "a\nb"
  assert equal (r#'X="a\tb"'# | from env | get X) "a\tb"
  assert equal (r#'X="a\"b"'# | from env | get X) 'a"b'
  assert equal (r#'X="a\\b"'# | from env | get X) 'a\b'
  assert equal (r#'Y='a\nb''# | from env | get Y) 'a\nb'
  assert equal (r#'Q="a b c"'# | from env | get Q) 'a b c'
}

@test
def 'from-env：strips inline comments but keeps escaped hashes' [] {
  assert equal ('Z=abc # comment' | from env | get Z) 'abc'
  assert equal (r#'W=ab\#c'# | from env | get W) 'ab#c'
  # A `#` inside quotes is data, not a comment.
  assert equal (r#'S='a#b''# | from env | get S) 'a#b'
}

@test
def 'from-env：handles export prefix, comments, blanks and empty values' [] {
  assert equal ('export FOO=bar' | from env) { FOO: 'bar' }
  assert equal ("# a comment\n\nA=1\n" | from env) { A: '1' }
  assert equal ('E=' | from env) { E: '' }
  assert equal ('  K  =  v  ' | from env) { K: 'v' }
  # Lines without `=` are dropped rather than aborting the parse.
  assert equal ("no-equals-here\nA=1" | from env) { A: '1' }
}

@test
def 'from-env：only the first equals sign splits key from value' [] {
  # Connection strings and JWTs routinely carry `=` in the value.
  assert equal ('DSN=postgres://u:p@h/db?a=b&c=d' | from env | get DSN) 'postgres://u:p@h/db?a=b&c=d'
}

@test
def 'from-env：empty input yields an empty record' [] {
  assert equal ('' | from env) {}
  assert equal ("\n\n# only comments\n" | from env) {}
}

@test
def 'from-env：later duplicate keys win' [] {
  assert equal ("A=1\nA=2" | from env) { A: '2' }
}

@test
def 'compact-record：drops empty lists and records too' [] {
  # `is-empty` is true for '', [], {} and null — but false for 0 and false,
  # which must survive so `max-length: 0` is not silently dropped.
  assert equal ({ a: [], b: {}, c: [1] } | compact-record) { c: [1] }
  assert equal ({ a: false, b: 0, c: '' } | compact-record) { a: false, b: 0 }
  assert equal ({} | compact-record) {}
}

@test
def 'ECODE：exit codes are stable and unique' [] {
  # These leak into CI as process exit codes and into the README, so they are
  # part of the public contract.
  assert equal $ECODE.SUCCESS 0
  assert equal $ECODE.OUTDATED 1
  assert equal $ECODE.AUTH_FAILED 2
  assert equal $ECODE.SERVER_ERROR 3
  assert equal $ECODE.MISSING_BINARY 5
  assert equal $ECODE.INVALID_PARAMETER 6
  assert equal $ECODE.MISSING_DEPENDENCY 7
  assert equal $ECODE.CONDITION_NOT_SATISFIED 8
  let codes = $ECODE | values
  assert equal ($codes | length) ($codes | uniq | length)
}

@test
def 'constants：GitHub API base and no-token tip are well formed' [] {
  assert equal $GITHUB_API_BASE 'https://api.github.com'
  # The tip is posted verbatim as a PR comment when CHAT_TOKEN is missing.
  assert ($NO_TOKEN_TIP | str contains 'CHAT_TOKEN')
  assert ($NO_TOKEN_TIP | str contains 'https://github.com/hustcer/deepseek-review')
}

@test
def 'has-ref：resolves branches, short SHAs and rejects garbage' [] {
  # CI checks out a single branch at depth 1, so a hardcoded branch name would
  # fail there. PR checkouts are DETACHED (the merge commit), where no branch
  # is checked out at all — so the branch assertion only runs when HEAD is
  # actually attached to one.
  let branch = (do { git symbolic-ref -q --short HEAD | complete } | get stdout | str trim)
  assert equal (has-ref HEAD) true
  assert equal (has-ref (git rev-parse --short HEAD | str trim)) true
  if ($branch | is-not-empty) {
    assert equal (has-ref $"refs/heads/($branch)") true
  }
  assert equal (has-ref 'no/such/ref') false
  assert equal (has-ref '') false
}

@test
def 'is-installed：rejects empty and unknown names' [] {
  assert equal (is-installed git) true
  assert equal (is-installed '') false
  assert equal (is-installed 'definitely-not-a-real-binary-xyz') false
}
