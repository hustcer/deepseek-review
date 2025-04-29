# DeepSeek Code Review

![Tests](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fgist.githubusercontent.com%2Fhustcer%2Fb99391ee59016b17d0befe3331387e89%2Fraw%2Ftest-summary.json&query=%24.total&label=Tests)
![Passed](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fgist.githubusercontent.com%2Fhustcer%2Fb99391ee59016b17d0befe3331387e89%2Fraw%2Ftest-summary.json&query=%24.passed&label=Passed&color=%2331c654)
![Failed](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fgist.githubusercontent.com%2Fhustcer%2Fb99391ee59016b17d0befe3331387e89%2Fraw%2Ftest-summary.json&query=%24.failed&label=Failed&color=red)
![Skipped](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fgist.githubusercontent.com%2Fhustcer%2Fb99391ee59016b17d0befe3331387e89%2Fraw%2Ftest-summary.json&query=%24.skipped&label=Skipped&color=yellow)

[中文说明](README.zh-CN.md)

`deepseek-review` also offers seamless integration with DeepSeek models on SiliconCloud. [Sign Up Now](https://cloud.siliconflow.cn/i/rqCdIxzS) to **Claim Your Free 20 Million Tokens** and start exploring its capabilities!

## Features

### GitHub Action

- Automate PR Reviews with DeepSeek via GitHub Action
- Add `skip cr` or `skip review` to PR Title or Body to Disable Code Review in GitHub Actions
- Cross-platform Support: Compatible with GitHub Runners across `macOS`, `Ubuntu`, and `Windows`.

### Local Code Review

- Streaming Output Support for Local Code Review
- Review Remote GitHub PRs Directly from Your Local CLI
- Review Commit Changes with DeepSeek for Any Local Repository by CLI
- Support On-demand Changes Generation via `git show`/`git diff` Command for Further Code Review
- Output Code Review Result to Specified File in Markdown Format
- Cross-platform Compatibility: Designed to function seamlessly across all platforms capable of running [Nushell](https://github.com/nushell/nushell)

### Both GH Action & Local

- Support Both DeepSeek's `V3` & `R1` Models
- Fully Customizable: Choose Models, Base URLs, and Prompts
- Supports Self-Hosted DeepSeek Models for Enhanced Flexibility
- Perform Code Reviews for Changes That either Include or Exclude Specific Files

## Planned Features

- [ ] **Trigger Code Review on Mention**: Automatically initiate code review when the `github-actions` bot is mentioned in a PR comment.
- [ ] **Generate Commit Message Locally**: Generate a commit message for the code changes in any local repository.

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
| model          | String | Optional, The model used for code review, defaults to `deepseek-chat`   |
| base-url       | String | Optional, DeepSeek API Base URL, defaults to `https://api.deepseek.com` |
| max-length     | Int    | Optional, Maximum length(Unicode width) of the content for review, if the content length exceeds this value, the review will be skipped. Default `0` means no limit. |
| sys-prompt     | String | Optional, System prompt corresponding to `$sys_prompt` in the payload, default value see note below |
| user-prompt    | String | Optional, User prompt corresponding to `$user_prompt` in the payload, default value see note below |
| temperature    | Number | Optional, The temperature for the model to generate the response, between `0` and `2`, default value `0.3` |
| include-patterns | String | Optional, The comma separated file patterns to include in the code review. No default |
| exclude-patterns | String | Optional, The comma separated file patterns to exclude in the code review. Default to `pnpm-lock.yaml,package-lock.json,*.lock` |
| github-token   | String | Optional, The `GITHUB_TOKEN` secret or personal access token to authenticate. Defaults to `${{ github.token }}`. |

**DeepSeek API Call Payload**:

```js
{
  // `$model` default value: deepseek-chat
  model: $model,
  stream: false,
  temperature: $temperature,
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

- [`Nushell`](https://www.nushell.sh/book/installation.html). It is recommended to install the latest versions(min version required: `0.103`).
- The latest version of [`awk`](https://github.com/onetrueawk/awk) or [`gawk`](https://www.gnu.org/software/gawk/) is required, with `gawk` being the preferred choice.
- Clone this repository to your local machine, navigate to the repository directory, and run `nu cr -h`. You should see an output similar to the following:

```console
Use DeepSeek AI to review code changes locally or in GitHub Actions

Usage:
  > nu cr {flags} (token)

Flags:
  -d, --debug: Debug mode
  -r, --repo <string>: GitHub repo name, e.g. hustcer/deepseek-review
  -n, --pr-number <string>: GitHub PR number
  -k, --gh-token <string>: Your GitHub token, fallback to GITHUB_TOKEN env var
  -f, --diff-from <string>: Git diff starting commit SHA
  -t, --diff-to <string>: Git diff ending commit SHA
  -c, --patch-cmd <string>: The `git show` or `git diff` command to get the diff content, for local CR only
  -l, --max-length <int>: Maximum length of the content for review, 0 means no limit.
  -m, --model <string>: Model name, or read from CHAT_MODEL env var, `deepseek-chat` by default
  -b, --base-url <string>: DeepSeek API base URL, fallback to BASE_URL env var
  -U, --chat-url <string>: DeepSeek Model chat full API URL, e.g. http://localhost:11535/api/chat
  -s, --sys-prompt <string>: Default to $DEFAULT_OPTIONS.SYS_PROMPT,
  -u, --user-prompt <string>: Default to $DEFAULT_OPTIONS.USER_PROMPT,
  -i, --include <string>: Comma separated file patterns to include in the code review
  -x, --exclude <string>: Comma separated file patterns to exclude in the code review
  -T, --temperature <float>: Temperature for the model, between `0` and `2`, default value `0.3`
  -C, --config <string>: Config file path, default to `config.yml`
  -o, --output <string>: Output file path
  -h, --help: Display the help message for this command

Parameters:
  token <string>: Your DeepSeek API token, fallback to CHAT_TOKEN env var (optional)

```

### Environment Configuration

To perform code review locally, you need to modify the configuration file. The repository already provides a configuration example [`config.example.yml`](https://github.com/hustcer/deepseek-review/blob/main/config.example.yml). Copy it to `config.yml` and modify it according to your actual needs. ​**Read the comments in the configuration file carefully**, as they explain the purpose of each configuration item.

> [!WARNING]
>
> The `config.yml` configuration file is ​**only used locally** and will not be utilized in GitHub Workflow. ​**Sensitive information** in this file should be properly secured and ​**never committed** to the code repository.
>

**Create Command Alias**

For convenience in performing code review across any local repository, create a command alias. For example:

```sh
# For Nushell: Modify config.nu and add:
alias cr = nu /absolute/path/to/deepseek-review/cr --config /absolute/path/to/deepseek-review/config.yml

# Modify ~/.zshrc for zsh or ~/.bashrc for bash or ~/.config/fish/config.fish for fish and add:
alias cr="nu /absolute/path/to/deepseek-review/cr --config /absolute/path/to/deepseek-review/config.yml"

# After sourcing the modified profile, use `cr` for code review

# For Windows powershell users please set cr alias by editing $PROFILE and add:
function cr {
  nu D:\absolute\path\to\deepseek-review\cr --config D:\absolute\path\to\deepseek-review\config.yml @args
}

# Then restart the terminal or run `. $PROFILE` in pwsh to make `cr` work
```

### Review Local Repository

To review a local repository:

- Navigate to the Git repository directory.
- Use the `cr` command to review current modifications, ​provided that `config.yml` is correctly configured.

**Usage Examples**

```sh
# Perform code review on the `git diff` changes in current directory
cr
# Perform code review on the `git diff f536acc` changes in current directory
cr --diff-from f536acc
# Perform code review on the `git diff f536acc` changes and output result to review.md
cr --diff-from f536acc --output review.md
# Perform code review on the `git diff f536acc 0dd0eb5` changes in current directory
cr --diff-from f536acc --diff-to 0dd0eb5
# Review the changes in current directory using the `--patch-cmd` flag
cr --patch-cmd 'git diff head~3'
cr -c 'git show head~3'
cr -c 'git diff 2393375 71f5a31'
cr -c 'git diff 2393375 71f5a31 nu/*'
cr -c 'git diff 2393375 71f5a31 :!nu/*'
# Dangerous commands like `cr -c 'git show head~3; rm ./*'` will not be allowed
```

### Review Remote GitHub PR Locally

When reviewing a remote GitHub PR locally:

- Always specify the PR number via `--pr-number`
- Use `--repo` to indicate the target repository (e.g., `hustcer/deepseek-review`). If `--repo` is omitted, the tool reads `settings.default-github-repo` from `config.yml`.

**Usage Examples**

```sh
# Perform code review on PR #31 in the remote DEFAULT_GITHUB_REPO repo
cr --pr-number 31
# Perform code review on PR #31 in the remote hustcer/deepseek-review repo
cr --pr-number 31 --repo hustcer/deepseek-review
# Perform code review on PR #31 and exclude changes of pnpm-lock.yaml
cr --pr-number 31 --exclude pnpm-lock.yaml
```

## License

Licensed under:

* MIT license ([LICENSE](LICENSE) or http://opensource.org/licenses/MIT)
