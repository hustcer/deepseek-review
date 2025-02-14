#!/usr/bin/env nu
# Author: hustcer
# Created: 2025/02/13 19:56:56
# Description: Validate and load the config.yml file.
#
# TODO:
#   [√] Check if the config.yml file exists.

use common.nu [ECODE, hr-line]

const SETTING_FILE = 'config.yml'

def file-exists [file: string] {
  if ($file | path exists) { return true }
  print $'The config file (ansi r)($file)(ansi reset) does not exist. '
  print $'Please copy the (ansi g)config.example.yml(ansi reset) file to create a new one.'
  exit $ECODE.MISSING_DEPENDENCY
}

# Check if the config.yml file exists and if it's valid
export def config-check [] {
  file-exists $SETTING_FILE
}

# Get model config information
def get-model-envs [settings: record, model?: string = ''] {
  let name = $settings.settings?.provider? | default ''
  let provider = $settings.providers
    | default []
    | where name == $name
    | get -i 0
    | default {}
  let model_name = $provider.models
    | default []
    | where {|it| if ($model | is-empty) {
        $it.enabled? | default false
      } else {
        $it.name == $model or $it.alias? == $model }
      }
    | get -i 0.name
    | default $model

  { CHAT_TOKEN: $provider.token?, BASE_URL: $provider.base-url?, CHAT_MODEL: $model_name }
}

# Load the config.yml file to the environment
export def --env config-load [
  --debug(-d),                # Print the loaded environment variables
  --repo(-r): string,         # Load the specified local repository by name
  --model(-m): string,        # Load the specified model by name
] {
  let all_settings = open $SETTING_FILE
  let settings = $all_settings | get settings? | default {}
  let local_repo = $all_settings.local-repos
    | default []
    | where name == ($repo | default $settings.default-local-repo? | default '')
    | get -i 0.path
    | default $repo

  let user_prompt = $all_settings.prompts?.user?
    | default []
    | where name == ($settings.user-prompt? | default '')
    | get -i 0.prompt

  let system_prompt = $all_settings.prompts?.system?
    | default []
    | where name == ($settings.system-prompt? | default '')
    | get -i 0.prompt

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
    DEFAULT_LOCAL_REPO: $local_repo,
    DEFAULT_GITHUB_REPO: $settings.default-github-repo,
  }
  load-env $env_vars
  if $debug {
    print 'Loaded Environment Variables:'; hr-line
    $env_vars | table -t psql | print
  }
}
