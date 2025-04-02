use common.nu [GITHUB_API_BASE, ECODE, git-check, has-ref]

# If the PR title or body contains any of these keywords, skip the review
const IGNORE_REVIEW_KEYWORDS = ['skip review' 'skip cr']

# Get the diff content from GitHub PR or local git changes and apply filters
export def get-diff [
  --repo: string,       # GitHub repository name
  --pr-number: string,  # GitHub PR number
  --diff-to: string,    # Diff to git ref
  --diff-from: string,  # Diff from git ref
  --include: string,    # Comma separated file patterns to include in the code review
  --exclude: string,    # Comma separated file patterns to exclude in the code review
  --patch-cmd: string,  # The `git show` or `git diff` command to get the diff content
] {
  let content = (
    get-diff-content --repo $repo --pr-number $pr_number --patch-cmd $patch_cmd
      --diff-to $diff_to --diff-from $diff_from --include $include --exclude $exclude)

  if ($content | is-empty) {
    print $'(ansi g)Nothing to review.(ansi reset)'
    exit $ECODE.SUCCESS
  }

  apply-file-filters $content --include $include --exclude $exclude
}

# Get diff content from GitHub PR or local git changes
def get-diff-content [
  --repo: string,       # GitHub repository name
  --pr-number: string,  # GitHub PR number
  --diff-to: string,    # Diff to git ref
  --diff-from: string,  # Diff from git ref
  --include: string,    # Comma separated file patterns to include in the code review
  --exclude: string,    # Comma separated file patterns to exclude in the code review
  --patch-cmd: string,  # The `git show` or `git diff` command to get the diff content
] {
  let local_repo = $env.PWD

  if ($pr_number | is-not-empty) {
    get-pr-diff --repo $repo $pr_number
  } else if ($diff_from | is-not-empty) {
    get-ref-diff $diff_from --diff-to $diff_to
  } else if not (git-check $local_repo --check-repo=1) {
    print $'Current directory ($local_repo) is (ansi r)NOT(ansi reset) a git repo, bye...(char nl)'
    exit $ECODE.CONDITION_NOT_SATISFIED
  } else if ($patch_cmd | is-not-empty) {
    get-patch-diff $patch_cmd
  } else {
    git diff
  }
}

# Get the diff content of the specified GitHub PR,
# if the PR description contains the skip keyword, exit
def get-pr-diff [
  --repo: string,       # GitHub repository name
  pr_number: string,    # GitHub PR number
] {
  let BASE_HEADER = [Authorization $'Bearer ($env.GH_TOKEN)' Accept application/vnd.github.v3+json]
  let DIFF_HEADER = [Authorization $'Bearer ($env.GH_TOKEN)' Accept application/vnd.github.v3.diff]

  if ($repo | is-empty) {
    print $'(ansi r)Please provide the GitHub repository name by `--repo` option.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }

  let description = http get -H $BASE_HEADER $'($GITHUB_API_BASE)/repos/($repo)/pulls/($pr_number)'
                    | select title body | values | str join "\n"

  # Check if the PR title or body contains keywords to skip the review
  if ($IGNORE_REVIEW_KEYWORDS | any {|it| $description =~ $it }) {
    print $'(ansi r)The PR title or body contains keywords to skip the review, bye...(ansi reset)'
    exit $ECODE.SUCCESS
  }

  # Get the diff content of the PR
  http get -H $DIFF_HEADER $'($GITHUB_API_BASE)/repos/($repo)/pulls/($pr_number)' | str trim
}

# Get diff content from local git changes
def get-ref-diff [
  diff_from: string,    # Diff from git REF
  --diff-to: string,    # Diff to git ref
] {
  # Validate the git refs
  if not (has-ref $diff_from) {
    print $'(ansi r)The specified git ref ($diff_from) does not exist, please check it again.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }

  if ($diff_to | is-not-empty) and not (has-ref $diff_to) {
    print $'(ansi r)The specified git ref ($diff_to) does not exist, please check it again.(ansi reset)'
    exit $ECODE.INVALID_PARAMETER
  }

  git diff $diff_from ($diff_to | default HEAD)
}

# Get the diff content from the specified git command
def get-patch-diff [
  cmd: string  # The `git show` or `git diff` command to get the diff content
] {
  let valid = is-safe-git $cmd
  if not $valid {
    exit $ECODE.INVALID_PARAMETER
  }

  # Get the diff content from the specified git command
  nu -c $cmd
}

# Apply file filters to the diff content to include or exclude specific files
def apply-file-filters [
  content: string,      # The diff content to filter
  --include: string,    # Comma separated file patterns to include in the code review
  --exclude: string,    # Comma separated file patterns to exclude in the code review
] {
  mut filtered_content = $content
  let awk_bin = (prepare-awk)
  let outdated_awk = $'If you are using an (ansi r)outdated awk version(ansi reset), please upgrade to the latest version or use gawk latest instead.'

  if ($include | is-not-empty) {
    let patterns = $include | split row ','
    $filtered_content = $filtered_content | try {
      ^$awk_bin (generate-include-regex $patterns)
    } catch {
      print $outdated_awk
      exit $ECODE.OUTDATED
    }
  }

  if ($exclude | is-not-empty) {
    let patterns = $exclude | split row ','
    $filtered_content = $filtered_content | try {
      ^$awk_bin (generate-exclude-regex $patterns)
    } catch {
      print $outdated_awk
      exit $ECODE.OUTDATED
    }
  }

  $filtered_content
}
