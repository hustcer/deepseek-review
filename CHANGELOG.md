# Changelog
All notable changes to this project will be documented in this file.

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
- Make action fail if no response returned from deepseek (#3)

### Documentation

- Update README.md (#16)

### Features

- Add Github PR code review support
- Add local code changes code review support

### Miscellaneous Tasks

- Update prompts to English (#5)
- Update prompts to English in action.yaml (#9)

