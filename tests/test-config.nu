use std/assert
use std/testing *
use ../nu/config.nu [config-check, config-load]

# `config-check` reports every problem by printing a hint and calling `exit`, so
# each invalid fixture is run in a subprocess and asserted on its exit code.
def check-config [file: string] {
  ^$nu.current-exe -n -c $"use nu/config.nu [config-check]; config-check --config '($file)'" | complete
}

# A config.yml that passes every check, used as the base for the invalid variants
def valid-config [] {
  {
    settings: {
      provider: 'DeepSeek',
      'max-length': 0,
      temperature: 0.3,
      'user-prompt': 'default',
      'system-prompt': 'default',
      'github-token': 'gh-token',
      'default-github-repo': 'hustcer/deepseek-review',
      'include-patterns': '',
      'exclude-patterns': '*.lock',
    },
    providers: [
      {
        name: 'DeepSeek',
        token: 'ds-token',
        'base-url': 'https://api.deepseek.com',
        models: [
          { name: 'deepseek-v4-flash', alias: 'v4', enabled: true },
          { name: 'deepseek-reasoner', alias: 'r1', enabled: false },
        ],
      },
      {
        name: 'ollama-local',
        token: 'empty',
        'chat-url': 'http://localhost:11555/api/chat',
        models: [{ name: 'deepseek-r1', alias: 'r1', enabled: true }],
      },
    ],
    prompts: {
      user: [{ name: 'default', prompt: 'USER PROMPT' }],
      system: [{ name: 'default', prompt: 'SYSTEM PROMPT' }],
    },
  }
}

@before-all
def setup [] {
  let dir = $nu.temp-dir | path join $'dsr-config-(random chars -l 8)'
  mkdir $dir

  # Write one fixture per failure mode, each a minimal mutation of the valid one
  let write = {|name: string, config: any|
    let path = $dir | path join $'($name).yml'
    $config | to yaml | save --force $path
    $path
  }
  let base = valid-config

  {
    dir: $dir,
    valid: (do $write valid $base),
    no_prompt_key: (do $write no-prompt-key ($base | update settings { reject 'user-prompt' })),
    unknown_prompt: (do $write unknown-prompt ($base | update settings { update 'user-prompt' 'nope' })),
    no_prompts: (do $write no-prompts ($base | reject prompts)),
    no_provider_key: (do $write no-provider-key ($base | update settings { reject provider })),
    unknown_provider: (do $write unknown-provider ($base | update settings { update provider 'Nope' })),
    no_providers: (do $write no-providers ($base | reject providers)),
    empty_token: (do $write empty-token ($base | update providers.0.token '')),
    no_enabled: (do $write no-enabled ($base | update providers.0.models.0.enabled false)),
    two_enabled: (do $write two-enabled ($base | update providers.0.models.1.enabled true)),
    nameless_model: (do $write nameless-model ($base | update providers.0.models.1 { reject name })),
    bare_settings: (do $write bare-settings ($base | update settings {
      { provider: 'DeepSeek', 'user-prompt': 'default', 'system-prompt': 'default' }
    })),
  }
}

@after-all
def teardown [] {
  let dir = $in.dir
  if ($dir | path exists) { rm -rf $dir }
}

@test
def 'config-check：accepts a fully populated config' [] {
  assert equal (check-config $in.valid | get exit_code) 0
}

@test
def 'config-check：the shipped config.example.yml is valid' [] {
  # Users are told to copy this file verbatim. If it ever drifts out of the
  # rules `config-check` enforces (two enabled models in a group, a renamed
  # prompt, ...) every new user hits the error on their first run.
  assert equal (check-config 'config.example.yml' | get exit_code) 0
}

@test
def 'config-check：a missing config file reports MISSING_DEPENDENCY' [] {
  let result = check-config ($in.dir | path join 'does-not-exist.yml')
  assert equal $result.exit_code 7
  assert ($result.stdout | str contains 'does not exist')
}

@test
def 'config-check：rejects a missing or unknown prompt key' [] {
  let ctx = $in
  let missing = check-config $ctx.no_prompt_key
  assert equal $missing.exit_code 6
  assert ($missing.stdout | str contains 'user prompt key is missing')

  let unknown = check-config $ctx.unknown_prompt
  assert equal $unknown.exit_code 6
  assert ($unknown.stdout | str contains 'is missing in `prompts.user`')
}

@test
def 'config-check：a config without a prompts section fails gracefully' [] {
  # Regression: `$options.prompts` used to be a hard cell path, so omitting the
  # section raised a raw `Cannot find column` instead of the intended hint.
  let result = check-config $in.no_prompts
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'is missing in `prompts.user`')
  assert equal ($result.stderr | str contains 'Cannot find column') false
}

@test
def 'config-check：rejects a missing or unknown provider' [] {
  let ctx = $in
  # Regression: `$options.settings.provider` was a hard cell path too.
  let missing = check-config $ctx.no_provider_key
  assert equal $missing.exit_code 6
  assert ($missing.stdout | str contains 'provider name is missing')
  assert equal ($missing.stderr | str contains 'Cannot find column') false

  let unknown = check-config $ctx.unknown_provider
  assert equal $unknown.exit_code 6
  assert ($unknown.stdout | str contains 'does not exist in `providers`')
}

@test
def 'config-check：a config without a providers section fails gracefully' [] {
  let result = check-config $in.no_providers
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'does not exist in `providers`')
  assert equal ($result.stderr | str contains 'Cannot find column') false
}

@test
def 'config-check：every provider needs a name, token and models' [] {
  let result = check-config $in.empty_token
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'token')
}

@test
def 'config-check：each model group needs exactly one enabled model' [] {
  let ctx = $in
  let none = check-config $ctx.no_enabled
  assert equal $none.exit_code 6
  assert ($none.stdout | str contains 'one and only one enabled model')

  let two = check-config $ctx.two_enabled
  assert equal $two.exit_code 6
  assert ($two.stdout | str contains 'one and only one enabled model')
}

@test
def 'config-check：every model needs a name' [] {
  let result = check-config $in.nameless_model
  assert equal $result.exit_code 6
  assert ($result.stdout | str contains 'Model name is missing')
}

@test
def 'config-load：exports the settings as environment variables' [] {
  config-load --config $in.valid
  assert equal $env.CHAT_TOKEN 'ds-token'
  assert equal $env.BASE_URL 'https://api.deepseek.com'
  assert equal $env.CHAT_MODEL 'deepseek-v4-flash'
  assert equal $env.USER_PROMPT 'USER PROMPT'
  assert equal $env.SYSTEM_PROMPT 'SYSTEM PROMPT'
  assert equal $env.MAX_LENGTH 0
  assert equal $env.TEMPERATURE 0.3
  assert equal $env.GITHUB_TOKEN 'gh-token'
  assert equal $env.EXCLUDE_PATTERNS '*.lock'
  assert equal $env.DEFAULT_GITHUB_REPO 'hustcer/deepseek-review'
}

@test
def 'config-load：picks the enabled model of the selected provider only' [] {
  # `ollama-local` also has an enabled model; only the provider named in
  # `settings.provider` may contribute one.
  config-load --config $in.valid
  assert equal $env.CHAT_MODEL 'deepseek-v4-flash'
  assert equal $env.CHAT_URL null
}

@test
def 'config-load：resolves a model by name or by alias' [] {
  let file = $in.valid
  config-load --config $file --model 'deepseek-reasoner'
  assert equal $env.CHAT_MODEL 'deepseek-reasoner'

  config-load --config $file --model r1
  assert equal $env.CHAT_MODEL 'deepseek-reasoner'

  config-load --config $file --model v4
  assert equal $env.CHAT_MODEL 'deepseek-v4-flash'
}

@test
def 'config-load：an unknown model name is passed through untouched' [] {
  # Lets users try a model that is not in their config without editing it first.
  config-load --config $in.valid --model 'some/brand-new-model'
  assert equal $env.CHAT_MODEL 'some/brand-new-model'
}

@test
def 'config-load：optional settings keys may be omitted' [] {
  # Regression: `$settings.max-length` and friends were hard cell paths, so a
  # trimmed down config.yml crashed with `Cannot find column`. Missing keys must
  # come through as null and let the `default` chains in review.nu take over.
  config-load --config $in.bare_settings
  assert equal $env.MAX_LENGTH null
  assert equal $env.TEMPERATURE null
  assert equal $env.GITHUB_TOKEN null
  assert equal $env.INCLUDE_PATTERNS null
  assert equal $env.EXCLUDE_PATTERNS null
  assert equal $env.DEFAULT_GITHUB_REPO null
  assert equal $env.CHAT_MODEL 'deepseek-v4-flash'
}

@test
def 'config-load：an unresolvable provider yields null model envs' [] {
  # `config-check` normally rejects this first, but `config-load` is callable on
  # its own and must not blow up on a record without a `models` column.
  config-load --config $in.unknown_provider
  assert equal $env.CHAT_TOKEN null
  assert equal $env.BASE_URL null
  # No `--model` was given, so there is nothing to fall back to either.
  assert equal $env.CHAT_MODEL null
}
