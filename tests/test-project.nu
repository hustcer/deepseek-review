use std/assert
use std/testing *

# Project level consistency checks: things that are not any single command's
# behavior but silently rot when one file is updated and its twin is not.

# Parse a file in a fresh subprocess and report the result
def parse-check [snippet: string] {
  ^$nu.current-exe -n -c $"($snippet); print PARSE-OK" | complete
}

@test
def 'modules：every nu module parses on its own' [] {
  # `nu/release.nu` is imported by the Justfile only, so nothing else in the
  # suite would notice a parse error in it until someone tried to cut a release.
  let modules = ls nu/*.nu | get name | sort
  assert (($modules | length) >= 6)
  for module in $modules {
    # Quote the path: on Windows `ls` yields backslash separated paths.
    let result = parse-check $"use '($module)' *"
    assert equal $result.exit_code 0 $"($module) failed to parse: ($result.stderr)"
  }
}

@test
def 'flags：every cr flag is documented in both READMEs' [] {
  # Read the signature out of a subprocess so `main` is not defined into this
  # suite's scope; cwd is the repo root, same as the other entry point checks.
  let flags = (
    ^$nu.current-exe -n -c 'source cr
      scope commands | where name == main | get 0.signatures.any
        | where parameter_type == named | get parameter_name | to json'
    | from json
    | where $it != help
  )

  assert (($flags | length) > 10)
  for readme in ['README.md', 'README.zh-CN.md'] {
    let content = open -r $readme
    let undocumented = $flags | where {|f| not ($content | str contains $'--($f)') }
    assert equal $undocumented [] $'($readme) is missing flags: ($undocumented | str join ", ")'
  }
}

@test
def 'action：every declared input is consumed by the composite step' [] {
  # An input that nothing reads is a silently ignored option for every user of
  # the action.
  let action = open action.yaml
  let steps = $action.runs.steps | to json
  let unused = $action.inputs | columns | where {|i| not ($steps | str contains $'inputs.($i)') }
  assert equal $unused [] $'unused action inputs: ($unused | str join ", ")'
}

@test
def 'action：required inputs and branding stay declared' [] {
  let action = open action.yaml
  assert equal $action.inputs.chat-token.required true
  # `runs.using` must stay composite: the shell steps below assume it.
  assert equal $action.runs.using 'composite'
  # Every step that runs Nu code needs the shell to be nu.
  let nu_steps = $action.runs.steps | where {|s| $s.run? | is-not-empty }
  assert (($nu_steps | length) > 0)
  for step in $nu_steps { assert equal $step.shell 'nu {0}' }
}

@test
def 'meta：the action tag matches the package version' [] {
  # `make-release` tags with `actionVer` and derives the floating major tag from
  # it, so a mismatch here ships a release under the wrong tag.
  let meta = open meta.json
  let parts = $meta.version | split row '.'
  assert equal $meta.actionVer $'v($parts.0).($parts.1)'
  assert equal $meta.name 'deepseek-review'
}

@test
def 'meta：the READMEs point at the current major tag' [] {
  let meta = open meta.json
  let major = $meta.actionVer | split row '.' | first
  for readme in ['README.md', 'README.zh-CN.md'] {
    let content = open -r $readme
    assert ($content | str contains $'hustcer/deepseek-review@($major)') $'($readme) does not reference ($major)'
  }
}
