# Deepseek Code Review

## 在本机进行 Code Review

未完待续 ...

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

接口调用入参:

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
