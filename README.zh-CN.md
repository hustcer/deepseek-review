# DeepSeek 代码审查

## 特性

- 通过 GitHub Action 使用 DeepSeek 进行自动化 PR 审查
- 通过本地 CLI 直接审查远程 GitHub PR
- 通过本地 CLI 使用 DeepSeek 分析任何本地仓库的提交变更
- 完全可定制：选择模型、基础 URL 和提示词
- 支持自托管 DeepSeek 模型，提供更强的灵活性
- 在 PR 的标题或描述中添加 `skip cr` or `skip review` 可跳过 GitHub Actions 里的代码审查
- 对指定文件变更进行包含/排除式代码审查
- 跨平台：支持 GitHub `macOS`, `Ubuntu` & `Windows` Runners

## 计划支持特性

- [ ] **通过提及触发代码审查**：当 PR 评论中提及 `github-actions bot` 时，自动触发代码审查

## 通过 GitHub Action 进行代码审查

### 创建 PR 时自动触发代码审查

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
      - name: DeepSeek Code Review
        uses: hustcer/deepseek-review@v1
        with:
          chat-token: ${{ secrets.CHAT_TOKEN }}
```

<details>
  <summary>CHAT_TOKEN 配置</summary>

  按照以下步骤配置你的 `CHAT_TOKEN`：

  1. 点击仓库导航栏中的 "Settings" 选项卡
  2. 在左侧边栏中，点击 "Security" 下的 "Secrets and variables"
  3. 点击 "Actions" -> "New repository secret" 按钮
  4. 在 "Name" 字段中输入 `CHAT_TOKEN`
  5. 在 "Secret" 字段中输入你的 `CHAT_TOKEN` 值
  6. 最后，点击 "Add secret"按钮保存密钥

</details>

当 PR 创建的时候会自动触发 DeepSeek 代码审查，并将审查结果（依赖于提示词）以评论的方式发布到对应的 PR 上。比如：
- [示例 1](https://github.com/hustcer/deepseek-review/pull/30) 基于[默认提示词](https://github.com/hustcer/deepseek-review/blob/main/action.yaml#L35) & [运行日志](https://github.com/hustcer/deepseek-review/actions/runs/13043609677/job/36390331791#step:2:53).
- [示例 2](https://github.com/hustcer/deepseek-review/pull/68) 基于[这个提示词](https://github.com/hustcer/deepseek-review/blob/eba892d969049caff00b51a31e5c093aeeb536e3/.github/workflows/cr.yml#L32)

### 当 PR 添加指定 Label 时触发审查

如果你不希望创建 PR 时自动审查可以选择通过添加标签时触发代码审查，比如创建如下 Workflow：

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

如此以来当 PR 创建的时候不会自动触发 DeepSeek 代码审查，只有你手工添加 `ai review` 标签的时候才会触发审查。

## 输入参数

| 名称           | 类型   | 描述                                                           |
| -------------- | ------ | -------------------------------------------------------------- |
| chat-token     | String | 必填，DeepSeek API Token                                       |
| model          | String | 可选，配置代码审查选用的模型，默认为 `deepseek-chat`           |
| base-url       | String | 可选，DeepSeek API Base URL, 默认为 `https://api.deepseek.com` |
| max-length     | Int    | 可选，待审查内容的最大 Unicode 长度, 默认 `0` 表示没有限制，超过非零值则跳过审查 |
| sys-prompt     | String | 可选，系统提示词对应入参中的 `$sys_prompt`, 默认值见后文注释      |
| user-prompt    | String | 可选，用户提示词对应入参中的 `$user_prompt`, 默认值见后文注释     |
| include-patterns | String | 可选，代码审查中要包含的以逗号分隔的文件模式，无默认值 |
| exclude-patterns | String | 可选，代码审查中要排除的以逗号分隔的文件模式，默认值为 `pnpm-lock.yaml,package-lock.json,*.lock` |
| github-token   | String | 可选，用于访问 API 进行 PR 管理的 GitHub Token，默认为 `${{ github.token }}` |

DeepSeek 接口调用入参:

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
> 可以通过提示词的语言来控制代码审查结果的语言，当前默认的提示词语言是英文的，
> 当你使用中文提示词的时候生成的代码审查结果就是中文的

## 本地代码审查

### 依赖工具

在本地进行代码审查，支持 `macOS`, `Ubuntu` & `Windows` 不过需要安装以下工具：

- [`Nushell`](https://www.nushell.sh/book/installation.html), 建议安装最新版本
- 接下来只需要把本仓库代码克隆到本地，然后进入仓库目录执行 `nu cr -h` 即可看到类似如下输出:

```console
Use DeepSeek AI to review code changes locally or in GitHub Actions

Usage:
  > cr {flags} (token)

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

### 环境配置

在本地进行代码审查需要先修改配置文件，仓库里已经有了 `.env.example` 配置文件示例，将其拷贝到 `.env` 然后根据自己的实际情况进行修改即可。

> [!WARNING]
>
> `.env` 配置文件仅在本地使用，在 GitHub Workflow 里面不会使用，里面的敏感信息请
> 妥善保存，不要提交到代码仓库里面

### 使用举例

```sh
# 对本地 DEFAULT_LOCAL_REPO 仓库 `git diff` 修改内容进行代码审查
nu cr
# 对本地 DEFAULT_LOCAL_REPO 仓库 `git diff f536acc` 修改内容进行代码审查
nu cr --diff-from f536acc
# 对本地 DEFAULT_LOCAL_REPO 仓库 `git diff f536acc 0dd0eb5` 修改内容进行代码审查
nu cr --diff-from f536acc --diff-to 0dd0eb5
# 对远程 DEFAULT_GITHUB_REPO 仓库编号为 31 的 PR 进行代码审查
nu cr --pr-number 31
# 对远程 hustcer/deepseek-review 仓库编号为 31 的 PR 进行代码审查
nu cr --pr-number 31 --repo hustcer/deepseek-review
```

## 许可

Licensed under:

- MIT license ([LICENSE](LICENSE) or http://opensource.org/licenses/MIT)
