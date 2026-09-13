# Common test runner utilities for unit tests

# Run a single test and return the result
export def run_test [test: record<name: string, execute: closure>]: nothing -> record<name: string, result: string, error: string> {
  try {
    do ($test.execute)
    { result: 'PASS', name: $test.name, error: '' }
  } catch { |error|
    { result: 'FAIL', name: $test.name, error: $'($error.msg)' }
  }
}

# Print test results table
export def print_results [results: list<record<name: string, result: string>>] {
  # The suite runner captures stdout with `complete`, so auto mode strips table colors.
  $env.config.use_ansi_coloring = true
  let display_table = $results | update result { |row|
    match $row.result {
      PASS => $'(ansi g)√ PASS(ansi rst)',
      SKIP => $'(ansi y)- SKIP(ansi rst)',
      _ => $'(ansi r)× ($row.result)(ansi rst)',
    }
  }

  if ('GITHUB_ACTIONS' in $env) {
    print ($display_table | to md --pretty)
  } else {
    print $display_table
  }

  let failed = $results | where result == 'FAIL'
  for test in $failed {
    print $"\n($test.name): ($test.error)"
  }
}

# Print test summary and return success status
export def print_summary [results: list<record<name: string, result: string>>] {
  let success = $results | where ($it.result == 'PASS') | length
  let failure = $results | where ($it.result == 'FAIL') | length
  let count = $results | length
  let skipped = $results | where result == 'SKIP' | length

  if ($failure == 0) {
    print $"\n(ansi g)Testing completed: ($success) of ($count) were successful(ansi rst)\n"
  } else {
    print $"\n(ansi r)Testing completed: ($failure) of ($count) failed(ansi rst)\n"
  }
  if $skipped > 0 { print $'Skipped: ($skipped)' }
}

# Run all tests and exit with appropriate code
export def run_tests [
  file: string,
  tests: list<record<name: string, execute: closure>>,
  --cleanup: closure,
  --skip, # Report this suite as skipped without executing its tests
] {
  $env.config.table.mode = 'psql'
  print $'-----------------------------------------------------------------------------------'
  let display_file = $file | path basename
  print $'  (ansi g)Running tests of ($display_file) ...(ansi rst)'
  print $'-----------------------------------------------------------------------------------'

  let results = $tests | each { |test|
    if $skip { { result: 'SKIP', name: $test.name, error: '' } } else { run_test $test }
  }
  if $cleanup != null { do $cleanup }

  if ($env.TEST_REPORT_DIR? | is-not-empty) {
    $results | to json | save ($env.TEST_REPORT_DIR | path join $'($display_file).json')
  }

  print -n (char nl)
  print_results $results
  print_summary $results

  if ($results | any { |test| $test.result == 'FAIL' }) {
    exit 1
  }
}
