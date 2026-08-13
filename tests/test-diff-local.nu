use std/assert
use std/testing *
use ../nu/diff.nu [get-diff]
use ../nu/util.nu [prepare-awk]

# All of these run against a throwaway repo built in a temp dir rather than
# against deepseek-review itself: CI checks the project out at depth 1, so
# `HEAD~1` and friends simply do not exist there.

# Enter the fixture repo and neutralize the developer's global/system git config
# — a `diff.external` driver, a signing key or a global hooksPath would all
# change what `git diff` emits here.
def --env enter-repo [dir: string] {
  $env.GIT_CONFIG_GLOBAL = ($dir | path join 'no-such-gitconfig')
  $env.GIT_CONFIG_SYSTEM = ($dir | path join 'no-such-gitconfig')
  cd $dir
}

# Run a snippet inside the fixture repo in a subprocess, for the paths that `exit`
def run-in-repo [dir: string, snippet: string] {
  let root = $env.PWD
  (
    ^$nu.current-exe -n -c $"
      $env.GITHUB_ACTIONS = null
      $env.GIT_CONFIG_GLOBAL = '($dir | path join 'no-such-gitconfig')'
      $env.GIT_CONFIG_SYSTEM = '($dir | path join 'no-such-gitconfig')'
      cd '($root)'
      use nu/diff.nu [get-diff]
      cd '($dir)'
      ($snippet)
    " | complete
  )
}

@before-all
def setup [] {
  let dir = $nu.temp-dir | path join $'dsr-diff-(random chars -l 8)'
  mkdir $dir
  let awk_bin = (prepare-awk)

  enter-repo $dir
  git -c init.defaultBranch=main init -q .
  git config user.email 'tests@deepseek-review.invalid'
  git config user.name 'DeepSeek Review Tests'
  git config commit.gpgsign false

  mkdir ($dir | path join nu) ($dir | path join docs) ($dir | path join vendor nu)
  'let a = 1' | save -f ($dir | path join nu lib.nu)
  '# Docs'    | save -f ($dir | path join docs readme.md)
  'on: push'  | save -f ($dir | path join action.yaml)
  'fn a() {}' | save -f ($dir | path join vendor nu deep.rs)
  git add -A
  git commit -q -m 'first commit'
  let first = git rev-parse HEAD | str trim

  'let a = 2' | save -f ($dir | path join nu lib.nu)
  '# Docs v2' | save -f ($dir | path join docs readme.md)
  'on: pull_request' | save -f ($dir | path join action.yaml)
  'fn b() {}' | save -f ($dir | path join vendor nu deep.rs)
  git add -A
  git commit -q -m 'second commit'
  let second = git rev-parse HEAD | str trim

  { dir: $dir, awk: $awk_bin, first: $first, second: $second }
}

@after-all
def teardown [] {
  let dir = $in.dir
  if ($dir | path exists) { rm -rf $dir }
}

# Collect the paths named by the `diff --git a/<path> b/<path>` headers
def diff-paths []: string -> list<string> {
  $in | lines | where $it starts-with 'diff --git ' | each {|line|
    $line | parse 'diff --git a/{path} b/{other}' | get -o 0.path
  } | sort
}

@test
def 'get-diff：diffs two local refs' [] {
  let ctx = $in
  enter-repo $ctx.dir
  let paths = get-diff --diff-from $ctx.first --diff-to $ctx.second | diff-paths
  assert equal $paths ['action.yaml', 'docs/readme.md', 'nu/lib.nu', 'vendor/nu/deep.rs']
}

@test
def 'get-diff：diff-to defaults to HEAD' [] {
  let ctx = $in
  enter-repo $ctx.dir
  let with_to = get-diff --diff-from $ctx.first --diff-to HEAD
  let without = get-diff --diff-from $ctx.first
  assert equal ($without | diff-paths) ($with_to | diff-paths)
}

@test
def 'get-diff：include keeps only the matching files' [] {
  let ctx = $in
  enter-repo $ctx.dir
  let paths = get-diff --diff-from $ctx.first --diff-to $ctx.second --include 'nu/*' | diff-paths
  # `nu/*` is rooted: `vendor/nu/deep.rs` must not sneak in.
  assert equal $paths ['nu/lib.nu']
}

@test
def 'get-diff：exclude drops only the matching files' [] {
  let ctx = $in
  enter-repo $ctx.dir
  let paths = get-diff --diff-from $ctx.first --diff-to $ctx.second --exclude '**/*.md,**/*.yaml' | diff-paths
  assert equal $paths ['nu/lib.nu', 'vendor/nu/deep.rs']
}

@test
def 'get-diff：include and exclude compose' [] {
  let ctx = $in
  enter-repo $ctx.dir
  let paths = (get-diff --diff-from $ctx.first --diff-to $ctx.second
                 --include '**/*.nu,**/*.rs,**/*.md' --exclude '**/*.md' | diff-paths)
  assert equal $paths ['nu/lib.nu', 'vendor/nu/deep.rs']
}

@test
def 'get-diff：multi pattern includes stay anchored per pattern' [] {
  let ctx = $in
  enter-repo $ctx.dir
  # End to end cover for the glob alternation grouping fix: with two patterns
  # the rooted `nu/*` used to also match the nested `vendor/nu/deep.rs`.
  let paths = (get-diff --diff-from $ctx.first --diff-to $ctx.second
                 --include '*.yaml,nu/*' | diff-paths)
  assert equal $paths ['action.yaml', 'nu/lib.nu']
}

@test
def 'get-diff：patch-cmd runs an allow listed git command' [] {
  let ctx = $in
  enter-repo $ctx.dir
  let paths = get-diff --patch-cmd $'git show ($ctx.second)' | diff-paths
  assert equal $paths ['action.yaml', 'docs/readme.md', 'nu/lib.nu', 'vendor/nu/deep.rs']
}

@test
def 'get-diff：patch-cmd arguments reach git verbatim' [] {
  let ctx = $in
  enter-repo $ctx.dir
  # The command is split on spaces and executed argv-style, never through a
  # shell — pathspecs such as `nu/*` must still arrive intact.
  let paths = get-diff --patch-cmd $'git diff ($ctx.first) ($ctx.second) nu/*' | diff-paths
  assert equal $paths ['nu/lib.nu']
}

@test
def 'get-diff：falls back to the working tree diff' [] {
  let ctx = $in
  enter-repo $ctx.dir
  'let a = 3' | save -f ($ctx.dir | path join nu lib.nu)
  let paths = get-diff | diff-paths
  git checkout -q -- nu/lib.nu
  assert equal $paths ['nu/lib.nu']
}

@test
def 'get-diff：an unknown ref exits with INVALID_PARAMETER' [] {
  let ctx = $in
  let from = run-in-repo $ctx.dir 'get-diff --diff-from 0123456789abcdef'
  assert equal $from.exit_code 6
  assert ($from.stdout | str contains 'does not exist')

  let to = run-in-repo $ctx.dir $'get-diff --diff-from ($ctx.first) --diff-to no/such/ref'
  assert equal $to.exit_code 6
}

@test
def 'get-diff：an unsafe patch-cmd exits with INVALID_PARAMETER' [] {
  let ctx = $in
  let result = run-in-repo $ctx.dir "get-diff --patch-cmd 'git log'"
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'Invalid git command')

  # The rejection must happen before git ever runs, so nothing is created.
  let inject = run-in-repo $ctx.dir "get-diff --patch-cmd 'git show HEAD > pwned.txt'"
  assert equal $inject.exit_code 6
  assert equal (($ctx.dir | path join 'pwned.txt') | path exists) false
}

@test
def 'get-diff：an empty diff exits successfully with a notice' [] {
  let ctx = $in
  # `HEAD` against itself produces nothing — the review is skipped, not failed.
  let result = run-in-repo $ctx.dir $'get-diff --diff-from ($ctx.second) --diff-to ($ctx.second)'
  assert equal $result.exit_code 0
  assert ($result.stdout | str contains 'Nothing to review')
}

@test
def 'get-diff：filtering everything out also exits successfully' [] {
  let ctx = $in
  let result = run-in-repo $ctx.dir $'get-diff --diff-from ($ctx.first) --include "*.does-not-exist"'
  assert equal $result.exit_code 0
}

@test
def 'deepseek-review：skips the review when the diff exceeds max-length' [] {
  let ctx = $in
  # The length guard must fire before the API call, so this needs no token
  # beyond a placeholder and never reaches the network.
  let result = run-in-repo $ctx.dir $'
    use nu/review.nu [deepseek-review]
    deepseek-review sk-placeholder --diff-from ($ctx.first) --max-length 1'
  assert equal $result.exit_code 0
  assert ($result.stdout | str contains 'exceeds the maximum limit')
}

@test
def 'deepseek-review：a max-length of 0 means no limit' [] {
  let ctx = $in
  # 0 must not be treated as "empty" and must not short circuit the review; the
  # run gets as far as the HTTP request, which is where we stop caring.
  let result = run-in-repo $ctx.dir $'
    use nu/review.nu [deepseek-review]
    deepseek-review sk-placeholder --diff-from ($ctx.first) --max-length 0 --chat-url http://127.0.0.1:1/nope'
  assert equal ($result.stdout | str contains 'exceeds the maximum limit') false
  assert ($result.stdout | str contains 'Waiting for response')
}
