# Deepseek Code Review

[中文说明](README.zh-CN.md)

## Features

- Automate PR Reviews with Deepseek via GitHub Action
- Review Remote GitHub PRs Directly from Your Local CLI
- Analyze Commit Changes with Deepseek for Any Local Repository with CLI
- Fully Customizable: Choose Models, Base URLs, and Prompts
- Supports Self-Hosted Deepseek Models for Enhanced Flexibility

## Local Code Review

To be updated ...

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
          deepseek-token: ${{ secrets.DEEPSEEK_TOKEN }}
```

## Input Parameters

| Name           | Type   | Description                                                             |
| -------------- | ------ | ----------------------------------------------------------------------- |
| deepseek-token | String | Required, Deepseek API Token                                            |
| model          | String | Optional, the model used for code review, defaults to `deepseek-chat`   |
| base-url       | String | Optional, Deepseek API Base URL, defaults to `https://api.deepseek.com` |
| sys-prompt     | String | Optional, system prompt corresponding to `$sys_prompt` in the input, default value see note below |
| user-prompt    | String | Optional, user prompt corresponding to `$user_prompt` in the input, default value see note below |

**API Call Input**:

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

## License

Licensed under:

* MIT license ([LICENSE](LICENSE) or http://opensource.org/licenses/MIT)
