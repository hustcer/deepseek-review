
use std/assert
use ../nu/diff.nu [get-diff]
use ../nu/util.nu [is-safe-git, prepare-awk, generate-include-regex, generate-exclude-regex]

# Get the unicode width of the input string
def get-uw [] { $in | str stats | get unicode-width }

#[before-all]
def setup [] {
  let awk_bin = (prepare-awk)
  let patch = open -r tests/resources/diff.patch
  print 'Mock patch creation from commit: 22e7b71'
  { patch: $patch, awk: $awk_bin, SHA: 22e7b71 }
}

#[test]
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
}

#[test]
def 'generate-include-regex：should work as expected' [] {
  let patch = $in.patch
  let awk_bin = $in.awk
  assert equal ($patch | ^$awk_bin (generate-include-regex [*]) | get-uw) (7959 + 5)
  assert equal ($patch | ^$awk_bin (generate-include-regex [nu/*]) | get-uw) 2576
  assert equal ($patch | ^$awk_bin (generate-include-regex [nu/*, **/*.yaml]) | get-uw) 3669
  assert equal ($patch | ^$awk_bin (generate-include-regex [.env*, *.md, nu/*]) | get-uw) 6871
}

#[test]
def 'generate-exclude-regex：should work as expected' [] {
  let patch = $in.patch
  let awk_bin = $in.awk
  assert equal ($patch | ^$awk_bin (generate-exclude-regex [*]) | get-uw) 356
  assert equal ($patch | ^$awk_bin (generate-exclude-regex [.env*, *.md, nu/*]) | get-uw) (1350 + 99)
}

#[test]
def 'both include and exclude should work as expected' [] {
  let patch = $in.patch
  let awk_bin = $in.awk
  assert equal ($patch
    | ^$awk_bin (generate-include-regex [nu/*, **/*.yaml])
    | ^$awk_bin (generate-exclude-regex [**/*.yaml])
    | get-uw) 2576
}

#[test]
def 'both exclude and include should work as expected' [] {
  let patch = $in.patch
  let awk_bin = $in.awk
  assert equal ($patch
    | ^$awk_bin (generate-exclude-regex [**/*.yaml])
    | ^$awk_bin (generate-include-regex [nu/*])
    | get-uw) 2576
}

#[test]
def 'get-diff：get patch from remote PR should work' [] {
  $env.GH_TOKEN = $env.GITHUB_TOKEN?
  const repo = 'hustcer/deepseek-review'
  if ($env.GH_TOKEN | is-empty) { print '$env.GH_TOKEN is empty'; return }
  let patch = get-diff --pr-number 93 --repo $repo
  assert equal ($patch | lines | skip 1
                  | str join "\n" | get-uw) 7923
}

#[test]
def 'get-diff：get patch from remote PR with include should work' [] {
  $env.GH_TOKEN = $env.GITHUB_TOKEN?
  const repo = 'hustcer/deepseek-review'
  if ($env.GH_TOKEN | is-empty) { print '$env.GH_TOKEN is empty'; return }
  let patch = get-diff --pr-number 93 --repo $repo --include nu/*
  assert equal ($patch | get-uw) 2576
}

#[test]
def 'get-diff：get patch from remote PR with exclude should work' [] {
  $env.GH_TOKEN = $env.GITHUB_TOKEN?
  const repo = 'hustcer/deepseek-review'
  if ($env.GH_TOKEN | is-empty) { print '$env.GH_TOKEN is empty'; return }
  let patch = get-diff --pr-number 93 --repo $repo --exclude **/*.yaml,**/*.nu,*.md
  assert equal ($patch | get-uw) 555
}

#[test]
def 'get-diff：get patch from remote PR with exclude & include should work' [] {
  $env.GH_TOKEN = $env.GITHUB_TOKEN?
  const repo = 'hustcer/deepseek-review'
  if ($env.GH_TOKEN | is-empty) { print '$env.GH_TOKEN is empty'; return }
  let patch = get-diff --pr-number 93 --repo $repo --exclude **/*.yaml,*.md --include **/*.nu
  assert equal ($patch | get-uw) 2576
}
