#!/usr/bin/env nu
# Run every standalone test suite. Optionally write the README badge summary.
# Usage: nu --no-config-file tests/run.nu --summary test-summary.json

def main [--summary: path] {
  cd ($env.FILE_PWD | path dirname)
  let report_dir = mktemp --directory
  let suites = glob tests/test-*.nu | sort
  mut failed_suites = []
  for suite in $suites {
    let result = with-env { TEST_REPORT_DIR: $report_dir } {
      ^$nu.current-exe --no-config-file $suite | complete
    }
    print -n $result.stdout
    if ($result.stderr | is-not-empty) { print -e -n $result.stderr }
    if $result.exit_code != 0 {
      $failed_suites = $failed_suites | append ($suite | path basename)
    }
  }
  # Keep native path separators and glob metacharacters out of the pattern.
  let results = do {
    cd $report_dir
    glob '*.json' | each { open $in } | flatten
  }
  let totals = {
    total: ($results | length),
    passed: ($results | where result == 'PASS' | length),
    failed: ($results | where result == 'FAIL' | length),
    skipped: ($results | where result == 'SKIP' | length),
  }
  rm -r $report_dir
  print $totals
  if $summary != null { $totals | to json | save --force $summary }
  if ($failed_suites | is-not-empty) {
    print -e $'Failed suites: ($failed_suites | str join ", ")'
    exit 1
  }
}
