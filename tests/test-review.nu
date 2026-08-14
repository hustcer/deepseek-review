
use std/assert
use std/testing *
use ../nu/diff.nu [get-diff]
use ../nu/common.nu [ECODE]
use ../nu/util.nu [is-safe-git, prepare-awk, generate-include-regex, generate-exclude-regex]
use ../nu/review.nu [deepseek-review]

# Get the unicode width of the input string
def get-uw [] { $in | str stats | get unicode-width }

@before-all
def setup [] {
  let awk_bin = (prepare-awk)
  let patch = open -r tests/resources/diff.patch
  print 'Mock patch creation from commit: 22e7b71'
  { patch: $patch, awk: $awk_bin, SHA: 22e7b71 }
}

@test
def 'is-safe-git：should work as expected' [] {
  assert equal (is-safe-git 'git diff') true
  assert equal (is-safe-git 'git show') true
  assert equal (is-safe-git 'git log') false
  assert equal (is-safe-git 'git checkout') false
  assert equal (is-safe-git 'git show 0dd0eb5') true
  assert equal (is-safe-git 'git show HEAD') true
  assert equal (is-safe-git 'git show head~1') true
  assert equal (is-safe-git 'git diff HEAD~2') true
  assert equal (is-safe-git 'git diff head~3 main') true
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5') true
  assert equal (is-safe-git 'git show 2393375 | less') false
  assert equal (is-safe-git 'git show 2393375>diff.patch') false
  assert equal (is-safe-git 'git show 2393375 o+e>diff.patch') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 nu/*') true
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/*') true
  assert equal (is-safe-git 'git diff --output tmp.patch') false
  assert equal (is-safe-git 'git diff --ext-diff HEAD') false
  assert equal (is-safe-git 'git diff --no-index a b') false
  # Options must be rejected even when they appear AFTER a ref/pathspec, not just
  # right after the subcommand: the ref char class accepts leading dashes, so the
  # grammar regex alone would pass `--ext-diff` (external diff driver → arbitrary
  # command execution) and `--output` (overwrites a file). The token scan catches
  # them wherever they sit.
  assert equal (is-safe-git 'git diff head~3 --ext-diff') false
  assert equal (is-safe-git 'git show head~1 --output x') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/*; rm -rf abc') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/* && rm -rf abc') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/* || rm -rf abc') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/*; rm ./*') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/*; rm -f ./*') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/*; rm -rf ./*') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/* > out.txt') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/* >> out.txt') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/* < in.txt') false
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5 :!nu/* << in.txt') false
  assert equal (is-safe-git 'git show head:nu/common.nu') true
  assert equal (is-safe-git 'git show HEAD:nu/common.nu') true
  # Injected newlines / control chars must be rejected: a second line would run
  # as its own command in the patch-cmd executor, and line-oriented matchers
  # (e.g. `find -r`) can mask it by matching only the first line (S1).
  assert equal (is-safe-git $'git diff abc(char nl)rm -rf abc') false
  assert equal (is-safe-git $'git show(char nl)whoami') false
  assert equal (is-safe-git $'git diff(char cr)rm -rf abc') false
  assert equal (is-safe-git $'git diff(char tab)HEAD') false
}

@test
def 'generate-include-regex：should work as expected' [] {
  let patch = $in.patch
  let awk_bin = $in.awk
  assert equal ($patch | ^$awk_bin (generate-include-regex [*]) | get-uw) (7959 + 5)
  assert equal ($patch | ^$awk_bin (generate-include-regex [nu/*]) | get-uw) 2576
  assert equal ($patch | ^$awk_bin (generate-include-regex [nu/*, **/*.yaml]) | get-uw) 3669
  assert equal ($patch | ^$awk_bin (generate-include-regex [.env*, *.md, nu/*]) | get-uw) 6871
}

@test
def 'generate-include-regex：escapes regex metacharacters' [] {
  # C1: metacharacters in patterns must be escaped so they match literally; `*`
  # expands to `.*`. Previously the escape map never fired (keys had a spurious
  # leading backslash), leaving `.`, `+`, etc. as live regex operators.
  assert equal (generate-include-regex ['*.nu']) '/^diff --git/{p=/^diff --git a\/(.*\.nu) b\//}p'
  assert equal (generate-include-regex ['a+b.rs']) '/^diff --git/{p=/^diff --git a\/(a\+b\.rs) b\//}p'
  assert equal (generate-exclude-regex ['*.nu']) '/^diff --git/{p=/^diff --git a\/(.*\.nu) b\//}!p'
}

@test
def 'generate-include-regex：matches complete diff header path' [] {
  let awk_bin = $in.awk
  let nu_patch = "diff --git a/foo.nu b/foo.nu\nindex 000..111 100644\n--- a/foo.nu\n+++ b/foo.nu\n@@ -1 +1 @@\n-a\n+b\n"
  let nux_patch = "diff --git a/foo.nux b/foo.nux\nindex 000..111 100644\n--- a/foo.nux\n+++ b/foo.nux\n@@ -1 +1 @@\n-a\n+b\n"

  assert equal ($nu_patch | ^$awk_bin (generate-include-regex ['*.nu']) | is-not-empty) true
  assert equal ($nux_patch | ^$awk_bin (generate-include-regex ['*.nu']) | is-empty) true
}

@test
def 'generate-include-regex：double-star matches root and nested paths' [] {
  let awk_bin = $in.awk
  let root_patch = "diff --git a/action.yaml b/action.yaml\nindex 000..111 100644\n--- a/action.yaml\n+++ b/action.yaml\n@@ -1 +1 @@\n-a\n+b\n"
  let nested_patch = "diff --git a/.github/workflows/action.yaml b/.github/workflows/action.yaml\nindex 000..111 100644\n--- a/.github/workflows/action.yaml\n+++ b/.github/workflows/action.yaml\n@@ -1 +1 @@\n-a\n+b\n"

  assert equal ($root_patch | ^$awk_bin (generate-include-regex ['**/*.yaml']) | is-not-empty) true
  assert equal ($nested_patch | ^$awk_bin (generate-include-regex ['**/*.yaml']) | is-not-empty) true
}

@test
def 'generate-exclude-regex：double-star excludes root and nested paths' [] {
  let awk_bin = $in.awk
  let root_patch = "diff --git a/action.yaml b/action.yaml\nindex 000..111 100644\n--- a/action.yaml\n+++ b/action.yaml\n@@ -1 +1 @@\n-a\n+b\n"
  let nested_patch = "diff --git a/.github/workflows/action.yaml b/.github/workflows/action.yaml\nindex 000..111 100644\n--- a/.github/workflows/action.yaml\n+++ b/.github/workflows/action.yaml\n@@ -1 +1 @@\n-a\n+b\n"

  assert equal ($root_patch | ^$awk_bin (generate-exclude-regex ['**/*.yaml']) | is-empty) true
  assert equal ($nested_patch | ^$awk_bin (generate-exclude-regex ['**/*.yaml']) | is-empty) true
}

@test
def 'generate-exclude-regex：should work as expected' [] {
  let patch = $in.patch
  let awk_bin = $in.awk
  assert equal ($patch | ^$awk_bin (generate-exclude-regex [*]) | get-uw) 356
  assert equal ($patch | ^$awk_bin (generate-exclude-regex [.env*, *.md, nu/*]) | get-uw) (1350 + 99)
}

@test
def 'both include and exclude should work as expected' [] {
  let patch = $in.patch
  let awk_bin = $in.awk
  assert equal ($patch
    | ^$awk_bin (generate-include-regex [nu/*, **/*.yaml])
    | ^$awk_bin (generate-exclude-regex [**/*.yaml])
    | get-uw) 2576
}

@test
def 'both exclude and include should work as expected' [] {
  let patch = $in.patch
  let awk_bin = $in.awk
  assert equal ($patch
    | ^$awk_bin (generate-exclude-regex [**/*.yaml])
    | ^$awk_bin (generate-include-regex [nu/*])
    | get-uw) 2576
}

@test
def 'get-diff：get patch from remote PR should work' [] {
  $env.GH_TOKEN = $env.GITHUB_TOKEN?
  const repo = 'hustcer/deepseek-review'
  if ($env.GH_TOKEN | is-empty) { print '$env.GH_TOKEN is empty'; return }
  let patch = get-diff --pr-number 93 --repo $repo
  assert equal ($patch | lines | skip 1
                  | str join "\n" | get-uw) 7923
}

@test
def 'get-diff：get patch from remote PR with include should work' [] {
  $env.GH_TOKEN = $env.GITHUB_TOKEN?
  const repo = 'hustcer/deepseek-review'
  if ($env.GH_TOKEN | is-empty) { print '$env.GH_TOKEN is empty'; return }
  let patch = get-diff --pr-number 93 --repo $repo --include nu/*
  assert equal ($patch | get-uw) 2576
}

@test
def 'get-diff：get patch from remote PR with exclude should work' [] {
  $env.GH_TOKEN = $env.GITHUB_TOKEN?
  const repo = 'hustcer/deepseek-review'
  if ($env.GH_TOKEN | is-empty) { print '$env.GH_TOKEN is empty'; return }
  let patch = get-diff --pr-number 93 --repo $repo --exclude **/*.yaml,**/*.nu,*.md
  assert equal ($patch | get-uw) 555
}

@test
def 'get-diff：get patch from remote PR with exclude & include should work' [] {
  $env.GH_TOKEN = $env.GITHUB_TOKEN?
  const repo = 'hustcer/deepseek-review'
  if ($env.GH_TOKEN | is-empty) { print '$env.GH_TOKEN is empty'; return }
  let patch = get-diff --pr-number 93 --repo $repo --exclude **/*.yaml,*.md --include **/*.nu
  assert equal ($patch | get-uw) 2576
}

@test
def 'get-diff：should read patch from file with --patch-file' [] {
  let expected = open --raw tests/resources/diff.patch
  let content = get-diff --patch-file tests/resources/diff.patch
  # Compare sizes first so a wrong source fails with two readable numbers rather
  # than dumping both 8KB blobs; the equality below is what actually pins it down.
  assert equal ($content | get-uw) ($expected | get-uw)
  assert equal $content $expected
}

@test
def 'get-diff：--patch-file takes priority over --patch-cmd' [] {
  # Assert on the exact content, not on a `diff --git` substring: `git show HEAD`
  # emits that marker too, so a `str contains` check passes even when --patch-cmd
  # wins, which is precisely the regression this test exists to catch.
  let expected = open --raw tests/resources/diff.patch
  let content = get-diff --patch-file tests/resources/diff.patch --patch-cmd 'git show HEAD'
  assert equal ($content | get-uw) ($expected | get-uw)
  assert equal $content $expected
}

# Both rejections run in a subprocess because they end in `exit`, which would
# otherwise take the whole test run with them.
@test
def 'get-diff：--patch-file rejects a missing path and a directory' [] {
  let run = {|path: string|
    ^$nu.current-exe -n -c $"use nu/diff.nu [get-diff]; get-diff --patch-file '($path)'" | complete
  }

  let missing = do $run 'tests/resources/no-such-file.patch'
  assert equal $missing.exit_code $ECODE.INVALID_PARAMETER
  assert ($missing.stdout | str contains 'does not exist')

  # `path exists` is true for a directory, so without the `path type` guard this
  # one escapes as a raw `nu::shell::io::is_a_directory` error instead.
  let dir = do $run 'tests/resources'
  assert equal $dir.exit_code $ECODE.INVALID_PARAMETER
  assert ($dir.stdout | str contains 'not a regular file')
}

# Smoke test: both entry points must parse. The module import above already
# fails this file's load when nu/review.nu breaks (exit 1 even without --fail);
# the subprocess assert below covers `cr`, whose parse error would otherwise be
# invisible because nothing in the suite imports it. Guards against regressions
# like `--flag: bool` annotations (see PR #261).
@test
def 'deepseek-review：module parses and registers entry command with expected flags' [] {
  let entry = scope commands | where name == 'deepseek-review' | get -o 0
  assert ($entry | is-not-empty)
  let flags = $entry.signatures.nothing | where parameter_type == 'named' | get -o parameter_name
  assert ('temperature' in $flags)
}

@test
def 'cr：entry script must parse' [] {
  let result = (^$nu.current-exe -n -c 'source cr; print PARSE-OK' | complete)
  assert equal $result.exit_code 0
  assert ($result.stdout | str contains 'PARSE-OK')
}

@test
def 'glob-to-regex：alternation is grouped so every pattern stays anchored' [] {
  # Regression: the alternation used to be spliced in ungrouped, so
  # `a\/x|y b\/` parsed as `(a\/x)|(y b\/)`. Every branch but the last lost the
  # ` b/` anchor and every branch but the first lost the `^diff --git a/`
  # anchor, which silently pulled unrelated files into `--include` and dropped
  # wanted ones from `--exclude`. Only reproducible with 2+ patterns.
  let awk_bin = $in.awk
  def hdr [path: string] {
    $"diff --git a/($path) b/($path)\nindex 0..1 100644\n--- a/($path)\n+++ b/($path)\n@@ -1 +1 @@\n-a\n+b\n"
  }

  # `*.nu` must not match `foo.nu.txt` — the lost ` b/` suffix anchor.
  assert equal (hdr 'foo.nu.txt' | ^$awk_bin (generate-include-regex ['*.nu', '*.rs']) | is-empty) true
  # `nu/*` is rooted, so it must not match a nested `vendor/nu/lib.rs` — the
  # lost `^diff --git a/` prefix anchor.
  assert equal (hdr 'vendor/nu/lib.rs' | ^$awk_bin (generate-include-regex ['*.md', 'nu/*']) | is-empty) true
  # Same defect seen from the exclude side: the file used to be dropped.
  assert equal (hdr 'vendor/nu/lib.rs' | ^$awk_bin (generate-exclude-regex ['*.md', 'nu/*']) | is-not-empty) true

  # Patterns that genuinely match still do, from either side of the alternation.
  assert equal (hdr 'foo.nu' | ^$awk_bin (generate-include-regex ['*.nu', '*.rs']) | is-not-empty) true
  assert equal (hdr 'foo.rs' | ^$awk_bin (generate-include-regex ['*.nu', '*.rs']) | is-not-empty) true
  assert equal (hdr 'nu/lib.rs' | ^$awk_bin (generate-include-regex ['*.md', 'nu/*']) | is-not-empty) true
}

@test
def 'glob-to-regex：single char wildcard and empty pattern list' [] {
  assert equal (generate-include-regex ['a?.nu']) '/^diff --git/{p=/^diff --git a\/(a.\.nu) b\//}p'
  # An empty list yields the bare prefix/suffix, which matches no diff header —
  # callers guard on `is-not-empty` before ever passing an empty list.
  assert equal (generate-include-regex []) '/^diff --git/{p=/^diff --git a\/ b\//}p'
}

@test
def 'glob-to-regex：double star prefix is optional, not required' [] {
  let awk_bin = $in.awk
  def hdr [path: string] {
    $"diff --git a/($path) b/($path)\nindex 0..1 100644\n--- a/($path)\n+++ b/($path)\n@@ -1 +1 @@\n-a\n+b\n"
  }
  # `**/` expands to `(.*\/)?` — zero or more leading directories.
  assert equal (hdr 'a.yaml' | ^$awk_bin (generate-include-regex ['**/*.yaml']) | is-not-empty) true
  assert equal (hdr 'x/y/z/a.yaml' | ^$awk_bin (generate-include-regex ['**/*.yaml']) | is-not-empty) true
  assert equal (hdr 'a.yml' | ^$awk_bin (generate-include-regex ['**/*.yaml']) | is-empty) true
}

@test
def 'is-safe-git：rejects command substitution and expansion syntax' [] {
  # None of `$ ( ) { } ` ' "` are in the allowed token character class, so the
  # grammar match is what stops these — keep it that way.
  assert equal (is-safe-git 'git diff $(whoami)') false
  assert equal (is-safe-git 'git diff `whoami`') false
  assert equal (is-safe-git 'git diff ${IFS}') false
  assert equal (is-safe-git 'git show HEAD --pretty="%h"') false
  assert equal (is-safe-git "git show 'HEAD'") false
  assert equal (is-safe-git 'git diff HEAD & rm -rf x') false
}

@test
def 'is-safe-git：only show and diff subcommands are allowed' [] {
  assert equal (is-safe-git '') false
  assert equal (is-safe-git 'git') false
  assert equal (is-safe-git 'git status') false
  assert equal (is-safe-git 'git stash show') false
  assert equal (is-safe-git 'gitdiff') false
  assert equal (is-safe-git 'diff') false
  # Not `git` at all — must not be waved through by a substring match.
  assert equal (is-safe-git 'mygit diff') false
  assert equal (is-safe-git 'rm -rf / git diff') false
}

@test
def 'is-safe-git：normalizes case and surrounding whitespace' [] {
  assert equal (is-safe-git '  git diff HEAD  ') true
  assert equal (is-safe-git 'GIT DIFF HEAD') true
  assert equal (is-safe-git 'git  diff   HEAD') true
}

@test
def 'is-safe-git：caps the number of accepted arguments' [] {
  # The grammar allows at most 3 ref-ish tokens plus 2 pathspecs.
  assert equal (is-safe-git 'git diff a b c') true
  assert equal (is-safe-git 'git diff a b c nu/* :!tests/*') true
  assert equal (is-safe-git 'git diff a b c d e f') false
}
