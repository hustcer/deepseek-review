
use std/assert

use ../nu/review.nu [is-safe-git, generate-include-regex, generate-exclude-regex]

[before-all]
def setup [] {
  let patch = open -r tests/resources/diff.patch
  print 'Mock patch creation from commit: 22e7b71'
  { patch: $patch, SHA: 22e7b71 }
}

#[test]
def 'is-safe-git：should work as expected' [] {
  assert equal (is-safe-git 'git diff') true
  assert equal (is-safe-git 'git show') true
  assert equal (is-safe-git 'git show 0dd0eb5') true
  assert equal (is-safe-git 'git show HEAD') true
  assert equal (is-safe-git 'git diff HEAD~2') true
  assert equal (is-safe-git 'git diff head~3 main') true
  assert equal (is-safe-git 'git diff f536acc 0dd0eb5') true
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
  let patch = open -r tests/resources/diff.patch
  assert equal ($patch | awk (generate-include-regex [*]) | length) 8133
  assert equal ($patch | awk (generate-include-regex [nu/*]) | length) 2577
  assert equal ($patch | awk (generate-include-regex [nu/*, **/*.yaml]) | length) 3670
  assert equal ($patch | awk (generate-include-regex [.env*, *.md, nu/*]) | length) (7020 + 20)
}

#[test]
def 'generate-exclude-regex：should work as expected' [] {
  let patch = open -r tests/resources/diff.patch
  assert equal ($patch | awk (generate-exclude-regex [*]) | length) 357
  assert equal ($patch | awk (generate-exclude-regex [.env*, *.md, nu/*]) | length) (1350 + 100)
}

#[test]
def 'both include and exclude should work as expected' [] {
  let patch = open -r tests/resources/diff.patch
  assert equal ($patch
    | awk (generate-include-regex [nu/*, **/*.yaml])
    | awk (generate-exclude-regex [**/*.yaml])
    | length) 2577
}

#[test]
def 'both exclude and include should work as expected' [] {
  let patch = open -r tests/resources/diff.patch
  assert equal ($patch
    | awk (generate-exclude-regex [**/*.yaml])
    | awk (generate-include-regex [nu/*])
    | length) 2577
}
