# Deepseek Code Review

## 特性

- 通过 GitHub Action 使用 Deepseek 进行自动化 PR 审查
- 通过本地 CLI 直接审查远程 GitHub PR
- 通过本地 CLI 使用 Deepseek 分析任何本地仓库的提交变更
- 完全可定制：选择模型、基础 URL 和提示词
- 支持自托管 Deepseek 模型，提供更强的灵活性

## 本地 Code Review

未完待续 ...

Use Deepseek AI to review code changes

Usage:
  > deepseek-review {flags} (token)

Flags:
  -d, --debug: Debug mode
  -r, --repo <string>: GitHub repository name, e.g. hustcer/deepseek-review
  -n, --pr-number <string>: GitHub PR number
  --gh-token <string>: Your GitHub token, GITHUB_TOKEN by default
  -t, --diff-to <string>: Diff to git REF
  -f, --diff-from <string>: Diff from git REF
  -m, --model <string>: Model name, deepseek-chat by default (default: 'deepseek-chat')
  --base-url <string> (default: 'https://api.deepseek.com')
  -s, --sys-prompt <string> (default: 'You are a professional code review assistant responsible for analyzing code changes in GitHub Pull Requests. Identify potential issues such as code style violations, logical errors, security vulnerabilities, and provide improvement suggestions. Clearly list the problems and recommendations in a concise manner.')
  -u, --user-prompt <string> (default: 'Please review the following code changes:')
  -h, --help: Display the help message for this command

Parameters:
  token <string>: Your Deepseek API token, fallback to DEEPSEEK_TOKEN (optional)

Input/output types:
  ╭───┬───────┬────────╮
  │ # │ input │ output │
  ├───┼───────┼────────┤
  │ 0 │ any   │ any    │
  ╰───┴───────┴────────╯

## 通过 GitHub Action 进行代码审核

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
          deepseek-token: ${{ secrets.DEEPSEEK_TOKEN }}
```

## 输入参数

| 名称           | 类型   | 描述                                                           |
| -------------- | ------ | -------------------------------------------------------------- |
| deepseek-token | String | 必填，Deepseek API Token                                       |
| model          | String | 可选，配置代码审核选用的模型，默认为 `deepseek-chat`           |
| base-url       | String | 可选，Deepseek API Base URL, 默认为 `https://api.deepseek.com` |
| sys-prompt     | String | 可选，系统 Prompt 对应入参中的 `$sys_prompt`, 默认值见后文注释      |
| user-prompt    | String | 可选，用户 Prompt 对应入参中的 `$user_prompt`, 默认值见后文注释     |

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

## 许可

Licensed under:

- MIT license ([LICENSE](LICENSE) or http://opensource.org/licenses/MIT)
