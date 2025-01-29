# Author: hustcer
# Create: 2025/01/29 13:05:20
# Description:
#   Some helper task for deepseek-review
# Ref:
#   1. https://github.com/casey/just
#   2. https://www.nushell.sh/book/

set shell := ['nu', '-c']

# The export setting causes all just variables
# to be exported as environment variables.

set export := true
set dotenv-load := true

# If positional-arguments is true, recipe arguments will be
# passed as positional arguments to commands. For linewise
# recipes, argument $0 will be the name of the recipe.

set positional-arguments := true

# Just commands aliases
alias cr := code-review

# Use `just --evaluate` to show env vars

# Used to handle the path separator issue
DEEPSEEK_REVIEW_PATH := parent_directory(justfile())
NU_DIR := parent_directory(`(which nu).path.0`)
_query_plugin := if os_family() == 'windows' { 'nu_plugin_query.exe' } else { 'nu_plugin_query' }

# To pass arguments to a dependency, put the dependency
# in parentheses along with the arguments, just like:
# default: (sh-cmd "main")

# List available commands by default
default:
  @just --list --list-prefix "··· "

# Release a new version for `deepseek-review`
release *OPTIONS:
  @overlay use {{ join(DEEPSEEK_REVIEW_PATH, 'nu', 'release.nu') }}; \
    make-release {{OPTIONS}}

# Code review for GitHub PRs or local changes
code-review *OPTIONS:
  @overlay use {{ join(DEEPSEEK_REVIEW_PATH, 'nu', 'review.nu') }}; \
    deepseek-review {{OPTIONS}}

# Plugins need to be registered only once after nu v0.61
_setup:
  @register -e json {{ join(NU_DIR, _query_plugin) }}
