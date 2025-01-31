# Deepseek 代码审核

## 特性

- 通过 GitHub Action 使用 Deepseek 进行自动化 PR 审查
- 通过本地 CLI 直接审查远程 GitHub PR
- 通过本地 CLI 使用 Deepseek 分析任何本地仓库的提交变更
- 完全可定制：选择模型、基础 URL 和提示词
- 支持自托管 Deepseek 模型，提供更强的灵活性
- 在 PR 的标题或描述中添加 `skip cr` or `skip review` 可跳过 GitHub Actions 里的代码审查
- 跨平台：支持 GitHub `macOS`, `Ubuntu` & `Windows` Runners

## 计划支持特性

- [ ] **通过提及触发代码审查**：当 PR 评论中提及 `github-actions bot` 时，自动触发代码审查
- [ ] **忽略指定文件变更**：忽略对指定文件的更改，例如 `Cargo.lock`、`pnpm-lock.yaml` 等

## 通过 GitHub Action 进行代码审核

### 创建 PR 时自动触发代码审核

创建一个 GitHub workflow 内容如下：

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
      - name: Deepseek Code Review
        uses: hustcer/deepseek-review@v1
        with:
          chat-token: ${{ secrets.CHAT_TOKEN }}
```

当 PR 创建的时候会自动触发 Deepseek 代码审核，并将审核结果以评论的方式发布到对应的 PR 上。比如：[示例](https://github.com/hustcer/deepseek-review/pull/30) & [运行日志](https://github.com/hustcer/deepseek-review/actions/runs/13043609677/job/36390331791#step:2:53)

### 当 PR 添加指定 Label 时触发审核

如果你不希望创建 PR 时自动审核可以选择通过添加标签时触发代码审核，比如创建如下 Workflow：

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
      - name: Deepseek Code Review
        uses: hustcer/deepseek-review@v1
        with:
          chat-token: ${{ secrets.CHAT_TOKEN }}
```

如此以来当 PR 创建的时候不会自动触发 Deepseek 代码审核，只有你手工添加 `ai review` 标签的时候才会触发审核。

## 输入参数

| 名称           | 类型   | 描述                                                           |
| -------------- | ------ | -------------------------------------------------------------- |
| chat-token     | String | 必填，Deepseek API Token                                       |
| model          | String | 可选，配置代码审核选用的模型，默认为 `deepseek-chat`           |
| base-url       | String | 可选，Deepseek API Base URL, 默认为 `https://api.deepseek.com` |
| max-length     | Int    | 可选，待审核内容的最大 Unicode 长度, 默认 `0` 表示没有限制，超过非零值则跳过审核 |
| sys-prompt     | String | 可选，系统 Prompt 对应入参中的 `$sys_prompt`, 默认值见后文注释      |
| user-prompt    | String | 可选，用户 Prompt 对应入参中的 `$user_prompt`, 默认值见后文注释     |
| github-token   | String | 可选，用于访问 API 进行 PR 管理的 GitHub Token，默认为 `${{ github.token }}` |

Deepseek 接口调用入参:

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

## 本地代码审核

### 依赖工具

在本地进行代码审核，支持 `macOS`, `Ubuntu` & `Windows` 不过需要安装以下工具：

- [`Nushell`](https://www.nushell.sh/book/installation.html) & [`Just`](https://just.systems/man/en/packages.html), 建议安装最新版本
- 如果你需要在本地审核 GitHub PRs 还需要安装 [`gh`](https://cli.github.com/)
- 接下来只需要把本仓库代码克隆到本地，然后进入仓库目录执行 `just code-review -h` 或者 `just cr -h` 即可看到类似如下输出:

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

### 环境配置

在本地进行代码审核需要先修改配置文件，仓库里已经有了 `.env.example` 配置文件示例，将其拷贝到 `.env` 然后根据自己的实际情况进行修改即可。

### 使用举例

```sh
# 对本地 DEFAULT_LOCAL_REPO 仓库 `git diff` 修改内容进行代码审核
just cr
# 对本地 DEFAULT_LOCAL_REPO 仓库 `git diff f536acc` 修改内容进行代码审核
just cr --diff-from f536acc
# 对本地 DEFAULT_LOCAL_REPO 仓库 `git diff f536acc 0dd0eb5` 修改内容进行代码审核
just cr --diff-from f536acc --diff-to 0dd0eb5
# 对远程 DEFAULT_GITHUB_REPO 仓库编号为 31 的 PR 进行代码审核
just cr --pr-number 31
# 对远程 hustcer/deepseek-review 仓库编号为 31 的 PR 进行代码审核
just cr --pr-number 31 --repo hustcer/deepseek-review
```

## 许可

Licensed under:

- MIT license ([LICENSE](LICENSE) or http://opensource.org/licenses/MIT)
