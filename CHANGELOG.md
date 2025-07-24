# Changelog
All notable changes to this project will be documented in this file.

## [1.19.0] - 2025-07-23

### Bug Fixes

- Fix "variable not found" error (#185)
- Fix getting Nu binary path for Nushell 0.106

### Deps

- Upgrade Nu to v0.106 (#186)

## [1.18.0] - 2025-06-11

### Features

- Set default `temperature` to **0.3** for code review (#181)

### Miscellaneous Tasks

- Refine diff flag descriptions in docs and scripts (#177)
- Upgrade `Nu` to 0.105 and pin [`hustcer/setup-nu`](https://github.com/hustcer/setup-nu) to v3.19 (#183)

### Deps

- Upgrade `nutest` to v1.1.0 (#179)

## [1.17.0] - 2025-04-11

### Bug Fixes

- Read default `include` and `exclude` patterns from config for local code review (#170)

### Features

All the following changes are for local code review only:

- Add code review for `git show head:path/to/file` patch command support (#171)
- Add write code review result to file by `--output` flag support (#172)

## [1.16.0] - 2025-04-05

### Documentation

- Add alias setup guide for `powershell` (#163)

### Features

- Add OpenRouter deepseek model support (#167)

### Miscellaneous Tasks

- Add alias setup guide for `fish`
- Add openrouter.ai config example
- Set minimum required `nushell` version to v0.103

### Refactor

- Refactor `get-diff` custom command (#164)
- Refactor diff handling by moving logic to separate module (#165)
- Replace custom `kv.nu` module with `std-rfc/kv` for key-value functionality (#166)

## [1.15.0] - 2025-03-23

### Features

- Add example code review prompts for frontend, java and rust to `config.example.yml` (#138)
- Post a comment to the PR to notify the user when no `CHAT_TOKEN` is provided (#143)
- Add nushell version check and notify for update (#144)
- Add `--config` option to specify config file path for local code review (#146)
- Support local DeepSeek model running on Ollama (#152)
- Add repo of current directory code review support (#161)

### Miscellaneous Tasks

- Publish test summary (#133)
- Update tests status badge to README
- Update code review prompt for current nushell repo (#139)
- Use SiliconFlow's DeepSeek API
- Some code refactor (#149)
- Add `just test` task to run tests locally

### Refactor

- Simplify `is-safe-git` common util (#150)
- Enhance the glob pattern handling in `glob-to-regex` function (#151)

### Deps

- Upgrade `Nushell` to `v0.103.0`

## [1.12.0] - 2025-02-16

### Bug Fixes

- Fix `include` and `exclude` on GitHub Windows runners and related tests (#131)

### Documentation

- Update README (#126)

### Features

- Use `config.yml` instead of `.env` as the local code review config file (#123)

### Miscellaneous Tasks

- Try to add tests workflow and some common tests (#125)
- Add review related tests (#129)
- Add tests for `get-diff` command in review module
- Add `ubuntu-22.04-arm` to test matrix
- Fix `gawk` installation for GitHub Windows runners (#132)

## [1.11.0] - 2025-02-13

### Bug Fixes

- Do not show reasoning parts if reviewed by DeepSeek V3 model (#121)
- Fix `reasoning_content` field may not exists error
- Fix `include` & `exclude` pattern matching error (#122)

## [1.10.0] - 2025-02-12

### Features

- Separate the reasoning and the content part of the output (#115)

### Bug Fixes

- Improve error handling of API response for streaming-output (#117)

### Miscellaneous Tasks

- Make `awk` version check works for both `awk` and `gawk` (#109)
- Refine DeepSeek review output, clarify debug logs, and adjust error messaging for better context (#111)

### Performance

- Save the last reply of the model to db instead of a file (#113)

## [1.9.0] - 2025-02-12

### Bug Fixes

- Fix no repo column error for local code review (#102)

### Features

- Add streaming output support for local code review (#103)
- Add support for custom patch commands by `-c, --patch-cmd` flag in local code review (#106)
- Add DeepSeek R1 model support (#107)

## [1.8.0] - 2025-02-10

### Bug Fixes

- Add check for empty DeepSeek review response with error handling (#90)
- Add `awk` binary missing check (#92)

### Features

- Add version validation for `awk`/`gawk` and implement robust semantic version comparison for compatibility checks (#91)
- Add support for configurable `temperature` parameter in DeepSeek model setup (#93)

### Miscellaneous Tasks

- Update README add `awk` or `gawk` as required tools

### Refactor

- Streamline main wrapper and simplify argument handling for `nu/review.nu` integration (#88)

## [1.7.0] - 2025-02-08

### Features

- Remove the dependency on `just` for local code review (#84)

### Bug Fixes

- Fix possible GitHub comment posting errors

### Refactor

- Improve prompts loading helper (#82)

## [1.6.0] - 2025-02-07

### Features

- Read `CHAT_MODEL` and `BASE_URL` from `.env` for local code review (#80)

### Miscellaneous Tasks

- Use SiliconFlow's DeepSeek model
- Remove the dependency on `gh` (#78)

### Deps

- Upgrade `Nushell` to v0.102 (#76)

## [1.5.1] - 2025-02-01

### Bug Fixes

- Fix `awk` error on `macOS` runner (#71)

## [1.5.0] - 2025-02-01

### Documentation

- Update README (#61)

### Features

- Add example of triggering code review by adding `ai review` label (#60)
- Load multi-line prompts from yaml config for local code reviewing (#67)
- Add `include` and `exclude` for file pattern filtering support (#68)

### Miscellaneous Tasks

- Update prompts for current repo's workflow (#63)

### Refactor

- Extracted git repo check into `is-repo` custom command (#64)

## [1.3.0] - 2025-01-31

### Documentation

- Update CLI help output (#53)
- Polish documents (#57)

### Features

- Add `github-token` input (#55)
- Add `skip cr` or `skip review` to PR title or body to disable code review in GitHub Actions (#56)

### Miscellaneous Tasks

- Increase `max-length` in review workflow (#54)

## [1.2.0] - 2025-01-31

### Breaking Changes

- Change `DEEPSEEK_TOKEN` to `CHAT_TOKEN` (#50)

### Features

- Add `max-length` input (#52)

### Miscellaneous Tasks

- Update action name, description and icon (#49)

## [1.1.0] - 2025-01-30

### Bug Fixes

- Do not override `GITHUB_TOKEN` env var (#30)
- Check `gh` installation status in GitHub Action (#31)
- Add git repo and git ref checking (#32)
- Add repo checking for GitHub PR review (#34)
- Polish CLI output for local code review (#44)

### Documentation

- Add features description to README (#29)
- Add CLI help doc (#36)
- Add planed features to doc (#39)
- Add local code review guide (#41)

### Features

- Add dot env conf for local code review (#33)
- Add more CLI short flags (#35)
- Add `DEFAULT_GITHUB_REPO` & `DEFAULT_LOCAL_REPO` config for local code review (#42)

### Miscellaneous Tasks

- Use `v1` in README docs (#17)

## [1.0.0] - 2025-01-29

### Bug Fixes

- Fix gh token error
- Fix add comment error
- Make action fail if no response returned from DeepSeek (#3)

### Documentation

- Update README.md (#16)

### Features

- Add Github PR code review support
- Add local code changes code review support

### Miscellaneous Tasks

- Update prompts to English (#5)
- Update prompts to English in action.yaml (#9)

