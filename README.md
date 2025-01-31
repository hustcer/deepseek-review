# Deepseek Code Review

[中文说明](README.zh-CN.md)

## Features

- Automate PR Reviews with Deepseek via GitHub Action
- Review Remote GitHub PRs Directly from Your Local CLI
- Analyze Commit Changes with Deepseek for Any Local Repository with CLI
- Fully Customizable: Choose Models, Base URLs, and Prompts
- Supports Self-Hosted Deepseek Models for Enhanced Flexibility
- Add `skip cr` or `skip review` to PR title or body to disable code review

## Planned Features

- [ ] **Trigger Code Review on Mention**: Automatically initiate code review when the `github-actions` bot is mentioned in a PR comment.
- [ ] **Exclude Specific File Changes**: Ignore changes to specified files, such as `Cargo.lock`, `pnpm-lock.yaml`, and others.

## Code Review with GitHub Action

```yaml
name: Code Review
on:
  pull_request_target:
    types: [opened]

# fix: GraphQL: Resource not accessible by integration (addComment) error
permissions:
  pull-requests: write

jobs:
  setup-deepseek-review:
    runs-on: ubuntu-latest
    name: Code Review
    steps:
      - name: Deepseek Code Review
        uses: hustcer/deepseek-review@v1
        with:
          chat-token: ${{ secrets.CHAT_TOKEN }}
```

## Input Parameters

| Name           | Type   | Description                                                             |
| -------------- | ------ | ----------------------------------------------------------------------- |
| chat-token     | String | Required, Deepseek API Token                                            |
| model          | String | Optional, the model used for code review, defaults to `deepseek-chat`   |
| base-url       | String | Optional, Deepseek API Base URL, defaults to `https://api.deepseek.com` |
| max-length     | Int    | Optional, Maximum length of the content for review, if the content length exceeds this value, the review will be skipped. Default `0` means no limit. |
| sys-prompt     | String | Optional, system prompt corresponding to `$sys_prompt` in the payload, default value see note below |
| user-prompt    | String | Optional, user prompt corresponding to `$user_prompt` in the payload, default value see note below |
| github-token   | String | Optional, The `GITHUB_TOKEN` secret or personal access token to authenticate. Defaults to `github.token`. |

**Deepseek API Call Payload**:

```js
{
  // `$model` default value: deepseek-chat
  model: $model,
  stream: false,
  messages: [
    // `$sys_prompt` default value: You are a professional code review assistant responsible for
    // analyzing code changes in GitHub Pull Requests. Identify potential issues such as code
    // style violations, logical errors, security vulnerabilities, and provide improvement
    // suggestions. Clearly list the problems and recommendations in a concise manner.
    { role: 'system', content: $sys_prompt },
    // `$user_prompt` default value: Please review the following code changes
    // `diff_content` will be the code changes of current PR
    { role: 'user', content: $"($user_prompt):\n($diff_content)" }
  ]
}
```

## Local Code Review

### Required Tools

To perform code reviews locally, you need to install the following tools:

- [`Nushell`](https://www.nushell.sh/book/installation.html) & [`Just`](https://just.systems/man/en/packages.html). It is recommended to install the latest versions.
- If you need to review GitHub PRs locally, you also need to install [`gh`](https://cli.github.com/).
- Once the tools are installed, simply clone this repository to your local machine, navigate to the repository directory, and run `just code-review -h` or `just cr -h`. You should see an output similar to the following:

```console
Use Deepseek AI to review code changes locally or in GitHub Actions

Usage:
  > deepseek-review {flags} (token)

Flags:
  -d, --debug: Debug mode
  -r, --repo <string>: GitHub repository name, e.g. hustcer/deepseek-review
  -n, --pr-number <string>: GitHub PR number
  --gh-token <string>: Your GitHub token, fallback to GITHUB_TOKEN env var
  -t, --diff-to <string>: Diff to git REF
  -f, --diff-from <string>: Diff from git REF
  -l, --max-length <int>: Maximum length of the content for review, 0 means no limit.
  -m, --model <string>: Model name, deepseek-chat by default (default: 'deepseek-chat')
  --base-url <string> (default: 'https://api.deepseek.com')
  -s, --sys-prompt <string> (default: 'You are a professional code review assistant responsible for analyzing code changes in GitHub Pull Requests. Identify potential issues such as code style violations, logical errors, security vulnerabilities, and provide improvement suggestions. Clearly list the problems and recommendations in a concise manner.')
  -u, --user-prompt <string> (default: 'Please review the following code changes:')
  -h, --help: Display the help message for this command

Parameters:
  token <string>: Your Deepseek API token, fallback to CHAT_TOKEN env var (optional)

```

### Environment Configuration

To perform code reviews locally, you need to modify the configuration file. A sample configuration file `.env.example` is already provided in the repository. Copy it to `.env` and adjust it according to your actual setup.

### Usage Examples

```sh
# Perform code review on the `git diff` changes in the local DEFAULT_LOCAL_REPO repo
just cr
# Perform code review on the `git diff f536acc` changes in the local DEFAULT_LOCAL_REPO repo
just cr --diff-from f536acc
# Perform code review on the `git diff f536acc 0dd0eb5` changes in the local DEFAULT_LOCAL_REPO repo
just cr --diff-from f536acc --diff-to 0dd0eb5
# Perform code review on PR #31 in the remote DEFAULT_GITHUB_REPO repo
just cr --pr-number 31
# Perform code review on PR #31 in the remote hustcer/deepseek-review repo
just cr --pr-number 31 --repo hustcer/deepseek-review
```

## License

Licensed under:

* MIT license ([LICENSE](LICENSE) or http://opensource.org/licenses/MIT)
