# DeepSeek Code Review

[中文说明](README.zh-CN.md)

## Features

- Automate PR Reviews with DeepSeek via GitHub Action
- Review Remote GitHub PRs Directly from Your Local CLI
- Analyze Commit Changes with DeepSeek for Any Local Repository with CLI
- Fully Customizable: Choose Models, Base URLs, and Prompts
- Supports Self-Hosted DeepSeek Models for Enhanced Flexibility
- Perform Code Reviews for Changes That either Include or Exclude Specific Files
- Add `skip cr` or `skip review` to PR title or body to disable code review in GitHub Actions
- Cross-platform Support: Compatible with GitHub Runners across `macOS`, `Ubuntu`, and `Windows`.

## Planned Features

- [ ] **Trigger Code Review on Mention**: Automatically initiate code review when the `github-actions` bot is mentioned in a PR comment.

## Code Review with GitHub Action

### Initiate Code Review When PR was Created

Add a GitHub workflow with the following contents:

```yaml
name: Code Review
on:
  pull_request_target:
    types:
      - opened      # Triggers when a PR is opened
      - reopened    # Triggers when a PR is reopened
      - synchronize # Triggers when a commit is pushed to the PR

# fix: GraphQL: Resource not accessible by integration (addComment) error
permissions:
  pull-requests: write

jobs:
  setup-deepseek-review:
    runs-on: ubuntu-latest
    name: Code Review
    steps:
      - name: DeepSeek Code Review
        uses: hustcer/deepseek-review@v1
        with:
          chat-token: ${{ secrets.CHAT_TOKEN }}
```

<details>
  <summary>CHAT_TOKEN Config</summary>

  Follow these steps to config your `CHAT_TOKEN`:

  - Click on the "Settings" tab in your repository navigation bar.
  - In the left sidebar, click on "Secrets and variables" under "Security".
  - Click on "Actions" -> "New repository secret" button.
  - Enter `CHAT_TOKEN` in the "Name" field.
  - Enter the value of your `CHAT_TOKEN` in the "Secret" field.
  - Finally, click the "Add secret" button to save the secret.

</details>

When a PR is created, DeepSeek code review will be automatically triggered, and the review results(depend on your prompt) will be posted as comments on the corresponding PR. For example:
- [Example 1](https://github.com/hustcer/deepseek-review/pull/30) with [default prompts](https://github.com/hustcer/deepseek-review/blob/main/action.yaml#L35) & [Run Log](https://github.com/hustcer/deepseek-review/actions/runs/13043609677/job/36390331791#step:2:53).
- [Example 2](https://github.com/hustcer/deepseek-review/pull/68) with [this prompt](https://github.com/hustcer/deepseek-review/blob/eba892d969049caff00b51a31e5c093aeeb536e3/.github/workflows/cr.yml#L32)

### Trigger CR When a Specific Label was Added

If you don't want automatic review on PR creation, you can choose to trigger code review by adding a label. For example, create the following workflow:

```yaml
name: Code Review
on:
  pull_request_target:
    types:
      - labeled     # Triggers when a label is added to the PR

# fix: GraphQL: Resource not accessible by integration (addComment) error
permissions:
  pull-requests: write

jobs:
  setup-deepseek-review:
    runs-on: ubuntu-latest
    name: Code Review
    # Make sure the code review happens only when the PR has the label 'ai review'
    if: contains(github.event.pull_request.labels.*.name, 'ai review')
    steps:
      - name: DeepSeek Code Review
        uses: hustcer/deepseek-review@v1
        with:
          chat-token: ${{ secrets.CHAT_TOKEN }}
```

With this setup, DeepSeek code review will not run automatically upon PR creation. Instead, it will only be triggered when you manually add the `ai review` label.

## Input Parameters

| Name           | Type   | Description                                                             |
| -------------- | ------ | ----------------------------------------------------------------------- |
| chat-token     | String | Required, DeepSeek API Token                                            |
| model          | String | Optional, the model used for code review, defaults to `deepseek-chat`   |
| base-url       | String | Optional, DeepSeek API Base URL, defaults to `https://api.deepseek.com` |
| max-length     | Int    | Optional, Maximum length(Unicode width) of the content for review, if the content length exceeds this value, the review will be skipped. Default `0` means no limit. |
| sys-prompt     | String | Optional, system prompt corresponding to `$sys_prompt` in the payload, default value see note below |
| user-prompt    | String | Optional, user prompt corresponding to `$user_prompt` in the payload, default value see note below |
| include-patterns | String | Optional, The comma separated file patterns to include in the code review. No default |
| exclude-patterns | String | Optional, The comma separated file patterns to exclude in the code review. Default to `pnpm-lock.yaml,package-lock.json,*.lock` |
| github-token   | String | Optional, The `GITHUB_TOKEN` secret or personal access token to authenticate. Defaults to `github.token`. |

**DeepSeek API Call Payload**:

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

> [!NOTE]
>
> You can control the language of the code review results by the language of the
> Prompt. The default Prompt language is currently English. When you use a Chinese
> Prompt, the generated code review results will be in Chinese.

## Local Code Review

### Required Tools

To perform code reviews locally(should works for `macOS`, `Ubuntu`, and `Windows`), you need to install the following tools:

- [`Nushell`](https://www.nushell.sh/book/installation.html) & [`Just`](https://just.systems/man/en/packages.html). It is recommended to install the latest versions.
- Once the tools are installed, simply clone this repository to your local machine, navigate to the repository directory, and run `just code-review -h` or `just cr -h`. You should see an output similar to the following:

```console
Use DeepSeek AI to review code changes locally or in GitHub Actions

Usage:
  > deepseek-review {flags} (token)

Flags:
  -d, --debug: Debug mode
  -r, --repo <string>: GitHub repository name, e.g. hustcer/deepseek-review
  -n, --pr-number <string>: GitHub PR number
  -k, --gh-token <string>: Your GitHub token, fallback to GITHUB_TOKEN env var
  -t, --diff-to <string>: Diff to git REF
  -f, --diff-from <string>: Diff from git REF
  -l, --max-length <int>: Maximum length of the content for review, 0 means no limit.
  -m, --model <string>: Model name, deepseek-chat by default (default: 'deepseek-chat')
  -b, --base-url <string> (default: 'https://api.deepseek.com')
  -s, --sys-prompt <string>: Default to $DEFAULT_OPTIONS.SYS_PROMPT,
  -u, --user-prompt <string>: Default to $DEFAULT_OPTIONS.USER_PROMPT,
  -i, --include <string>: Comma separated file patterns to include in the code review
  -x, --exclude <string>: Comma separated file patterns to exclude in the code review
  -h, --help: Display the help message for this command

Parameters:
  token <string>: Your DeepSeek API token, fallback to CHAT_TOKEN env var (optional)

```

### Environment Configuration

To perform code reviews locally, you need to modify the configuration file. A sample configuration file `.env.example` is already provided in the repository. Copy it to `.env` and adjust it according to your actual setup.

> [!WARNING]
>
> The `.env` configuration file is only used locally and will not be utilized in GitHub
> Workflow. Please securely store any sensitive information in it and avoid committing
> it to the code repository.

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
