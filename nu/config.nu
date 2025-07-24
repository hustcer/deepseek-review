#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/02/13 19:56:56
# Description: Validate and load the config.yml file.
#
# TODO:
#   [√] Check if the config.yml file exists.
#   [√] Check if the prompt config keys exist.

use common.nu [ECODE, hr-line]

# Config file name
const SETTING_FILE = 'config.yml'

# Check if the config.yml file exists.
def file-exists [file: string] {
  if ($file | path exists) { return true }
  print $'The config file (ansi r)($file)(ansi reset) does not exist. '
  print $'Please copy the (ansi g)config.example.yml(ansi reset) file to create a new one.'
  exit $ECODE.MISSING_DEPENDENCY
}

# Check if the prompt keys exist in the config.yml file
def check-prompts [options: record] {
  check-prompt $options user
  check-prompt $options system
}

# Check if the specified type of prompt key exists in the config.yml file
def check-prompt [options: record, type: string] {
  let prompt_key = $options.settings | get -o $'($type)-prompt' | default ''
  if ($prompt_key | is-empty) {
    print $'(ansi r)The ($type) prompt key is missing in `settings.($type)-prompt` config.yml file.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
  let prompt = $options.prompts | get -o $type
    | default []
    | where name == $prompt_key
    | get -o 0.prompt
  if ($prompt | is-empty) {
    print $'The ($type) prompt (ansi r)($prompt_key)(ansi reset) is missing in `prompts.($type)` of config.yml file.'
    exit $ECODE.INVALID_PARAMETER
  }
}

# Check if the model providers and models are correctly configured in config.yml
def check-providers [options: record] {
  # settings.provider correctly configured and related provider exists
  let provider_name = $options.settings.provider
  if ($provider_name | is-empty) {
    print $'(ansi r)The provider name is missing in `settings.provider` of config.yml file.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
  let provider_exists = $options.providers
    | where name == $provider_name
    | is-not-empty
  if not $provider_exists {
    print $'(ansi r)The provider ($provider_name) does not exist in `providers` of config.yml file.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }
  # Each provider should have name, token and models field
  $options.providers | each {|p|
    let empties = [name token models] | where { |field| $p | get -o $field | is-empty }
    if ($empties | is-not-empty) {
      print $'Field (ansi r)`($empties | str join ,)`(ansi reset) should not be empty for provider:'
      $p | table -e -t psql | print
      exit $ECODE.INVALID_PARAMETER
    }
  }
}

# Check if the models are correctly configured in config.yml
def check-models [options: record] {
  # Each model group should have one and only one enabled model
  $options.providers | each {|provider|
    let enabled_models = $provider.models | default false enabled | where enabled | length
    if ($enabled_models != 1) {
      print $'Model group (ansi r)`($provider.name)`(ansi reset) should have one and only one enabled model.'
      exit $ECODE.INVALID_PARAMETER
    }
  }
  # All models should have a name field
  $options.providers | each {|provider|
    $provider.models | enumerate | each {|e|
      if ($e.item.name? | is-empty) {
        print $'Model name is missing for provider (ansi r)`($provider.name)` model #($e.index)(ansi reset)...'
        exit $ECODE.INVALID_PARAMETER
      }
    }
  }
}

# Check if the config.yml file exists and if it's valid
export def config-check [--config: string = $SETTING_FILE] {
  file-exists $config
  let options = open $config
  check-prompts $options
  check-providers $options
  check-models $options
}

# Get model config information
def get-model-envs [settings: record, model?: string = ''] {
  let name = $settings.settings?.provider? | default ''
  let provider = $settings.providers
    | default []
    | where name == $name
    | get -o 0
    | default {}
  let model_name = $provider.models
    | default []
    | where {|it| if ($model | is-empty) {
        $it.enabled? | default false
      } else {
        $it.name == $model or $it.alias? == $model }
      }
    | get -o 0.name
    | default $model

  { CHAT_TOKEN: $provider.token?, BASE_URL: $provider.base-url?, CHAT_URL: $provider.chat-url?, CHAT_MODEL: $model_name }
}

# Load the config.yml file to the environment
export def --env config-load [
  --debug(-d),                # Print the loaded environment variables
  --config(-C): string,       # The config file path, default to `config.yml`
  --model(-m): string,        # Load the specified model by name
] {
  let all_settings = open ($config | default $SETTING_FILE)
  let settings = $all_settings | get settings? | default {}

  let user_prompt = $all_settings.prompts?.user?
    | default []
    | where name == ($settings.user-prompt? | default '')
    | get -o 0.prompt

  let system_prompt = $all_settings.prompts?.system?
    | default []
    | where name == ($settings.system-prompt? | default '')
    | get -o 0.prompt

  let model_envs = get-model-envs $all_settings $model

  let env_vars = {
    ...$model_envs,
    USER_PROMPT: $user_prompt,
    SYSTEM_PROMPT: $system_prompt,
    MAX_LENGTH: $settings.max-length,
    TEMPERATURE: $settings.temperature,
    GITHUB_TOKEN: $settings.github-token,
    EXCLUDE_PATTERNS: $settings.exclude-patterns,
    INCLUDE_PATTERNS: $settings.include-patterns,
    DEFAULT_GITHUB_REPO: $settings.default-github-repo,
  }
  load-env $env_vars
  if $debug {
    print 'Loaded Environment Variables:'; hr-line
    $env_vars | table -t psql | print
  }
}
