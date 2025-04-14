#!/bin/bash

# Git Branch Manager - Version 2.0
# All configurations and settings are at the top of this file

# Color definitions
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# Project and branch configuration
MAIN_BRANCHES=("development" "staging" "master")
PROTECTED_BRANCHES=("development" "staging" "master" "qa")

# Branch naming configuration
# Check Bash version for associative array support
if ((BASH_VERSINFO[0] < 4)); then
    # For Bash < 4, use simple variables
    BRANCH_PREFIX_FEATURE="feat"
    BRANCH_PREFIX_BUGFIX="fix"
    BRANCH_PREFIX_HOTFIX="hotfix"
    
    get_branch_prefix() {
        local branch_type=$1
        case $branch_type in
            "feature") echo "$BRANCH_PREFIX_FEATURE";;
            "bugfix") echo "$BRANCH_PREFIX_BUGFIX";;
            "hotfix") echo "$BRANCH_PREFIX_HOTFIX";;
            *) echo "";;
        esac
    }
    
    # Function to check if branch type is valid
    is_valid_branch_type() {
        local branch_type=$1
        case $branch_type in
            "feature"|"bugfix"|"hotfix") return 0;;
            *) return 1;;
        esac
    }
else
    # For Bash >= 4, use associative array
    declare -A BRANCH_PREFIXES
    BRANCH_PREFIXES=(
        ["feature"]="feat"
        ["bugfix"]="fix"
        ["hotfix"]="hotfix"
    )
    
    get_branch_prefix() {
        local branch_type=$1
        echo "${BRANCH_PREFIXES[$branch_type]}"
    }
    
    # Function to check if branch type is valid
    is_valid_branch_type() {
        local branch_type=$1
        [[ -n "${BRANCH_PREFIXES[$branch_type]}" ]]
    }
fi

# Validation patterns
TICKET_PATTERN="^([A-Z0-9]+-)?[0-9]+$"
SUFFIX_PATTERN="^[a-zA-Z0-9][a-zA-Z0-9_-]*$"
PROHIBITED_KEYWORDS=("temp" "test" "wip" "draft" "tmp" "delete")

# Directory configuration
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
LOCK_DIR="$GIT_ROOT/.git/locks"
BACKUP_DIR="$GIT_ROOT/.git/branch-backups"
TEMP_DIR="/tmp/git-manager-$$"

# Operation settings
MAX_BACKUP_AGE=30  # days
MAX_LOCK_DURATION=72  # hours
MAX_BRANCH_AGE=90  # days

# Help function to display usage information
show_help() {
    echo "${BLUE}=== Git Branch Manager Help ===${RESET}"
    line_break
    echo "Usage: $(basename "$0") [OPTIONS]"
    line_break
    echo "Options:"
    echo "  -t TYPE     Branch type (feature, bugfix, hotfix)"
    echo "  -j TICKET   Ticket number (e.g., PROJ-123)"
    echo "  -s SUFFIX   Optional branch name suffix"
    echo "  -i          Interactive mode"
    echo "  -d BRANCH   Delete branch"
    echo "  -m SPEC     Merge branches (format: source:target:strategy)"
    echo "  -l FILTER   List branches with filter"
    echo "  -b BRANCH   Create backup of branch"
    echo "  -r BRANCH   Recover deleted branch"
    echo "  -f SPEC     Filter specification"
    echo "  -v FILTER   Visualize branches with filter"
    echo "  -H BRANCH   Health check for branch"
    echo "  -S TYPE     Show git status (basic, detailed, file:PATH)"
    echo "  -D TARGET   Show git diff (summary, detailed, file:PATH)"
    echo "  -L SPEC     Create lock (format: branch:reason:duration)"
    echo "  -U BRANCH   Remove lock from branch"
    echo "  -B SPEC     Backup management (format: branch:description or 'list' or 'clean')"
    echo "  -R ID       Restore from backup ID"
    echo "  -Q SPEC     Branch search (format: criteria:value:date_range)"
    echo "  -F CRITERIA Advanced filtering (format: criteria1,criteria2,...)"
    echo "  -X SPEC     Diff comparison (format: source:target)"
    echo "  -h          Show this help message"
    line_break
    echo "Examples:"
    echo "  $(basename "$0") -t feature -j PROJ-123 -s login-page"
    echo "  $(basename "$0") -i                           # Interactive mode"
    echo "  $(basename "$0") -m feature/PROJ-123:development:squash"
    echo "  $(basename "$0") -l \"feature\"                 # List feature branches"
    line_break
}

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null
}

# Set up trap for cleanup
trap cleanup EXIT
trap 'exit 1' INT TERM

# Create required directories
mkdir -p "$LOCK_DIR" "$BACKUP_DIR" "$TEMP_DIR"

# Validation function for Git repository
validate_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "${RED}Error: Not a git repository${RESET}"
        exit 1
    fi
}

# Function to validate user has required Git permissions
validate_git_permissions() {
    local branch=$1
    if [[ " ${PROTECTED_BRANCHES[@]} " =~ " ${branch} " ]]; then
        if ! git config "branch.${branch}.protect" > /dev/null 2>&1; then
            echo "${RED}Error: Insufficient permissions for branch: ${branch}${RESET}"
            return 1
        fi
    fi
    return 0
}

# Function to show error message and exit
die() {
    echo "${RED}Error: $1${RESET}" >&2
    exit 1
}

# Function to show warning message
warn() {
    echo "${YELLOW}Warning: $1${RESET}" >&2
}

# Function to show success message
success() {
    echo "${GREEN}Success: $1${RESET}"
}

# Function to show info message
info() {
    echo "${BLUE}Info: $1${RESET}"
}

# Function to show progress
show_progress() {
    echo -n "${BLUE}$1...${RESET}"
}

# Function to complete progress
complete_progress() {
    if [ "$1" -eq 0 ]; then
        echo "${GREEN}Done${RESET}"
    else
        echo "${RED}Failed${RESET}"
    fi
}

# Function to format output
line_break() {
    echo "------------------------------------------------------"
}

new_line() {
    echo ""
}

# Function to confirm action
confirm_action() {
    local message=$1
    local force=$2
    
    if [[ "$force" == "true" ]]; then
        return 0
    fi
    
    echo "${YELLOW}=== Confirmation Required ===${RESET}"
    echo "$message"
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    [[ "$confirm" == "yes" ]]
}

# Function to create new branch
create_branch() {
    local branch_type=$1
    local ticket=$2
    local suffix=$3
    local force=$4

    # Validate branch type
    if ! is_valid_branch_type "$branch_type"; then
        die "Invalid branch type. Allowed types: ${!BRANCH_PREFIXES[*]}"
    fi

    # Validate ticket
    if [[ ! $ticket =~ $TICKET_PATTERN ]]; then
        die "Invalid ticket format. Expected format: PROJ-123"
    fi

    # Generate branch name
    local prefix=$(get_branch_prefix "$branch_type")
    local branch_name="${prefix}/${ticket}"
    [[ -n "$suffix" ]] && branch_name="${branch_name}-${suffix}"

    # Validate branch name
    validate_branch_name "$branch_name" || exit 1

    # Check if branch exists
    if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
        if [[ "$force" != "true" ]]; then
            die "Branch ${branch_name} already exists"
        fi
        warn "Branch ${branch_name} exists and will be reset"
    fi

    # Determine base branch
    local base_branch="development"
    [[ "$branch_type" == "hotfix" ]] && base_branch="staging"

    # Confirm action
    if ! confirm_action "Create branch: ${branch_name} from ${base_branch}" "$force"; then
        die "Operation cancelled"
    fi

    # Create branch
    show_progress "Creating branch"
    if git checkout -b "$branch_name" "origin/$base_branch"; then
        complete_progress 0
        success "Created branch: ${branch_name}"
        
        # Push to remote if specified
        if [[ "$force" == "true" ]]; then
            show_progress "Pushing to remote"
            if git push -u origin "$branch_name"; then
                complete_progress 0
            else
                complete_progress 1
                warn "Failed to push to remote"
            fi
        fi
    else
        complete_progress 1
        die "Failed to create branch"
    fi
}

# Function to delete branch
delete_branch() {
    local branch_name=$1
    local delete_remote=$2
    local force=$3

    # Validate branch exists
    if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
        die "Branch ${branch_name} does not exist"
    fi

    # Check if branch is protected
    if [[ " ${PROTECTED_BRANCHES[@]} " =~ " ${branch_name} " ]]; then
        die "Cannot delete protected branch: ${branch_name}"
    fi

    # Check if branch is current
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "$branch_name" ]]; then
        die "Cannot delete current branch"
    fi

    # Confirm action
    if ! confirm_action "Delete branch: ${branch_name} (remote: ${delete_remote})" "$force"; then
        die "Operation cancelled"
    fi

    # Delete local branch
    show_progress "Deleting local branch"
    if git branch -D "$branch_name"; then
        complete_progress 0
        
        # Delete remote if specified
        if [[ "$delete_remote" == "true" ]]; then
            show_progress "Deleting remote branch"
            if git push origin --delete "$branch_name"; then
                complete_progress 0
            else
                complete_progress 1
                warn "Failed to delete remote branch"
            fi
        fi
    else
        complete_progress 1
        die "Failed to delete branch"
    fi
}

# Function to merge branches
merge_branch() {
    local source_branch=$1
    local target_branch=$2
    local strategy=$3
    local force=$4

    # Validate branches exist
    for branch in "$source_branch" "$target_branch"; do
        if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
            die "Branch ${branch} does not exist"
        fi
    done

    # Validate strategy
    if [[ "$strategy" != "merge" && "$strategy" != "rebase" && "$strategy" != "squash" ]]; then
        die "Invalid merge strategy. Allowed: merge, rebase, squash"
    fi

    # Check for conflicts
    local conflicts=$(git merge-tree $(git merge-base $source_branch $target_branch) $source_branch $target_branch | grep -A3 "changed in both")
    if [[ -n "$conflicts" && "$force" != "true" ]]; then
        warn "Potential conflicts detected:"
        echo "$conflicts"
        if ! confirm_action "Continue despite conflicts?" false; then
            die "Operation cancelled"
        fi
    fi

    # Create backup before merge
    create_backup "$target_branch" "Auto-backup before merge from $source_branch"

    # Perform merge based on strategy
    show_progress "Performing ${strategy}"
    case $strategy in
        "merge")
            if git checkout "$target_branch" && git merge "$source_branch"; then
                complete_progress 0
            else
                complete_progress 1
                die "Merge failed"
            fi
            ;;
        "rebase")
            if git checkout "$source_branch" && git rebase "$target_branch" && \
               git checkout "$target_branch" && git merge "$source_branch"; then
                complete_progress 0
            else
                complete_progress 1
                die "Rebase failed"
            fi
            ;;
        "squash")
            if git checkout "$target_branch" && git merge --squash "$source_branch" && \
               git commit -m "Squashed merge from $source_branch"; then
                complete_progress 0
            else
                complete_progress 1
                die "Squash merge failed"
            fi
            ;;
    esac

    success "Successfully merged ${source_branch} into ${target_branch}"
}

# Function to validate branch name
validate_branch_name() {
    local branch_name=$1
    local errors=()

    # Check length
    if [[ ${#branch_name} -gt 100 ]]; then
        errors+=("Branch name is too long (max 100 characters)")
    fi

    # Check for prohibited keywords
    for keyword in "${PROHIBITED_KEYWORDS[@]}"; do
        if [[ $branch_name =~ $keyword ]]; then
            errors+=("Branch name contains prohibited keyword: $keyword")
        fi
    done

    # Check for spaces and special characters
    if [[ $branch_name =~ [[:space:]] ]]; then
        errors+=("Branch name cannot contain spaces")
    fi

    if [[ $branch_name =~ [^a-zA-Z0-9_/-] ]]; then
        errors+=("Branch name can only contain letters, numbers, hyphens, and underscores")
    fi

    # Check for consecutive special characters
    if [[ $branch_name =~ [-_]{2,} ]]; then
        errors+=("Branch name cannot contain consecutive special characters")
    fi

    # Return errors if any
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "${RED}Branch naming validation failed:${RESET}"
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# Function to check branch health
check_branch_health() {
    local branch=$1
    local base_branch=${2:-development}
    local issues=0
    
    # Set fallback value for MAX_BRANCH_AGE if not defined
    local max_age=${MAX_BRANCH_AGE:-90}  # Default to 90 days if not set

    echo "${BLUE}=== Branch Health Check: ${branch} ===${RESET}"
    line_break

    # Check if branch exists
    if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
        die "Branch ${branch} does not exist"
    fi

    # Fetch latest changes
    show_progress "Fetching latest changes"
    git fetch --quiet origin
    complete_progress $?

    # Check remote status
    show_progress "Checking remote status"
    if git ls-remote --heads origin "$branch" | grep -q "$branch"; then
        echo "${GREEN}Remote branch: Found${RESET}"
        
        # Check if local is behind remote
        local_commit=$(git rev-parse "$branch")
        remote_commit=$(git rev-parse "origin/$branch")
        if [[ "$local_commit" != "$remote_commit" ]]; then
            echo "${RED}Local/Remote sync: Out of sync${RESET}"
            echo "Action needed: Run 'git pull origin $branch'"
            ((issues++))
        else
            echo "${GREEN}Local/Remote sync: In sync${RESET}"
        fi
    else
        echo "${YELLOW}Remote branch: Not found${RESET}"
    fi

    # Check base branch status
    local behind_count=$(git rev-list --count $branch..$base_branch)
    local ahead_count=$(git rev-list --count $base_branch..$branch)

    if [[ $behind_count -gt 0 ]]; then
        echo "${RED}Base branch status: Behind by $behind_count commits${RESET}"
        echo "Action needed: Update from $base_branch"
        ((issues++))
    else
        echo "${GREEN}Base branch status: Up to date${RESET}"
    fi

    if [[ $ahead_count -gt 0 ]]; then
        echo "${YELLOW}Commit status: Ahead by $ahead_count commits${RESET}"
    fi

    # Check for stale branches
    local last_commit_date=$(git log -1 --format=%ct "$branch")
    local current_date=$(date +%s)
    local days_since_last_commit=$(( (current_date - last_commit_date) / 86400 ))
    
    if [[ $days_since_last_commit -gt $max_age ]]; then
        echo "${RED}Branch age: $days_since_last_commit days old (stale)${RESET}"
        echo "Action needed: Consider removing or updating branch"
        ((issues++))
    else
        echo "${GREEN}Branch age: $days_since_last_commit days${RESET}"
    fi

    # Check for uncommitted changes
    if ! git diff --quiet HEAD; then
        echo "${RED}Working directory: Uncommitted changes present${RESET}"
        git status --short
        ((issues++))
    else
        echo "${GREEN}Working directory: Clean${RESET}"
    fi

    # Check for potential conflicts
    local conflicts=$(git merge-tree $(git merge-base $branch $base_branch) $branch $base_branch | grep -A3 "changed in both")
    if [[ -n "$conflicts" ]]; then
        echo "${RED}Conflict check: Potential conflicts detected${RESET}"
        echo "Files with potential conflicts:"
        echo "$conflicts" | grep -E "^[+-]" | cut -d' ' -f2 | sort | uniq
        ((issues++))
    else
        echo "${GREEN}Conflict check: No potential conflicts${RESET}"
    fi

    line_break
    if [[ $issues -gt 0 ]]; then
        echo "${RED}Found $issues issue(s) that need attention${RESET}"
        return 1
    else
        echo "${GREEN}Branch is healthy${RESET}"
        return 0
    fi
}

# Function to get branch status
get_branch_status() {
    local branch=$1
    local base_branch=${2:-development}

    # Get ahead/behind counts
    if git rev-parse --verify $branch >/dev/null 2>&1; then
        local ahead=$(git rev-list --count $base_branch..$branch 2>/dev/null)
        local behind=$(git rev-list --count $branch..$base_branch 2>/dev/null)
        
        if [[ $ahead -eq 0 && $behind -eq 0 ]]; then
            echo "${GREEN}Up to date${RESET}"
        elif [[ $ahead -gt 0 && $behind -eq 0 ]]; then
            echo "${YELLOW}Ahead by $ahead${RESET}"
        elif [[ $ahead -eq 0 && $behind -gt 0 ]]; then
            echo "${RED}Behind by $behind${RESET}"
        else
            echo "${RED}Diverged: +$ahead -$behind${RESET}"
        fi
    else
        echo "${RED}Invalid branch${RESET}"
    fi
}

# Function to list branches
list_branches() {
    local filter=$1
    local show_details=${2:-false}

    echo "${BLUE}=== Branch List ===${RESET}"
    line_break

    # Update remote branches
    show_progress "Updating remote information"
    git fetch --quiet
    complete_progress $?

    # Show current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Current branch: ${YELLOW}${current_branch}${RESET}"
    line_break

    # Header
    printf "%-40s %-20s %-20s\n" "Branch Name" "Last Commit" "Status"
    line_break

    # List branches
    git for-each-ref --sort='-committerdate' refs/heads/ --format='%(refname:short)' | while read branch; do
        # Apply filter if specified
        if [[ -n $filter && ! $branch =~ $filter ]]; then
            continue
        fi

        # Get branch details
        local last_commit=$(git log -1 --format=%cr $branch)
        local status=$(get_branch_status $branch)

        # Format output
        if [[ $branch == $current_branch ]]; then
            printf "%-40s %-20s %-20s\n" "${GREEN}* $branch${RESET}" "$last_commit" "$status"
        else
            printf "%-40s %-20s %-20s\n" "  $branch" "$last_commit" "$status"
        fi

        # Show additional details if requested
        if [[ "$show_details" == "true" ]]; then
            local author=$(git log -1 --format='%an' $branch)
            local commit_msg=$(git log -1 --format='%s' $branch)
            echo "  Author: $author"
            echo "  Last commit message: $commit_msg"
            echo
        fi
    done
}

# Function to visualize branch relationships
visualize_branches() {
    local max_count=${1:-20}
    local filter=$2

    echo "${BLUE}=== Branch Visualization ===${RESET}"
    line_break

    if [[ -n $filter ]]; then
        git log \
            --graph \
            --color \
            --abbrev-commit \
            --decorate \
            --format=format:"%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)" \
            --all \
            -n $max_count \
            --branches="*$filter*"
    else
        git log \
            --graph \
            --color \
            --abbrev-commit \
            --decorate \
            --format=format:"%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)" \
            --all \
            -n $max_count
    fi
}

# Function to create branch lock
create_lock() {
    local branch=$1
    local reason=$2
    local duration=${3:-$MAX_LOCK_DURATION}
    local force=${4:-false}

    # Validate branch exists
    if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
        die "Branch ${branch} does not exist"
    fi

    local lock_file="$LOCK_DIR/${branch//\//_}.lock"
    local current_user=$(git config user.name)
    local current_email=$(git config user.email)
    local expiry_timestamp=$(( $(date +%s) + duration * 3600 ))

    # Check if branch is already locked
    if [[ -f "$lock_file" && "$force" != "true" ]]; then
        source "$lock_file"
        if [[ $(date +%s) -lt $EXPIRY_TIMESTAMP ]]; then
            die "Branch is already locked by $LOCKED_BY until $(date -d "@$EXPIRY_TIMESTAMP" '+%Y-%m-%d %H:%M:%S')"
        fi
    fi

    # Create lock file
    cat > "$lock_file" << EOF
BRANCH=$branch
LOCKED_BY=$current_user
EMAIL=$current_email
REASON=$reason
LOCKED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EXPIRY_TIMESTAMP=$expiry_timestamp
EOF

    success "Branch '$branch' has been locked until $(date -d "@$expiry_timestamp" '+%Y-%m-%d %H:%M:%S')"
}

# Function to remove branch lock
remove_lock() {
    local branch=$1
    local force=${2:-false}
    local lock_file="$LOCK_DIR/${branch//\//_}.lock"
    local current_user=$(git config user.name)

    if [[ ! -f "$lock_file" ]]; then
        die "Branch '$branch' is not locked"
    fi

    source "$lock_file"

    # Check if user has permission to remove lock
    if [[ "$current_user" != "$LOCKED_BY" && "$force" != "true" ]]; then
        die "Only $LOCKED_BY can remove this lock"
    fi

    rm -f "$lock_file"
    success "Lock removed from branch '$branch'"
}

# Function to check branch lock status
check_lock() {
    local branch=$1
    local lock_file="$LOCK_DIR/${branch//\//_}.lock"

    if [[ ! -f "$lock_file" ]]; then
        echo "${GREEN}Branch '$branch' is not locked${RESET}"
        return 0
    fi

    source "$lock_file"
    local current_time=$(date +%s)

    if [[ $current_time -gt $EXPIRY_TIMESTAMP ]]; then
        rm -f "$lock_file"
        echo "${GREEN}Branch '$branch' is not locked (previous lock expired)${RESET}"
        return 0
    fi

    echo "${YELLOW}Branch '$branch' is locked${RESET}"
    echo "Locked by: $LOCKED_BY ($EMAIL)"
    echo "Reason: $REASON"
    echo "Locked at: $(date -d "@$LOCKED_AT" '+%Y-%m-%d %H:%M:%S')"
    echo "Expires at: $(date -d "@$EXPIRY_TIMESTAMP" '+%Y-%m-%d %H:%M:%S')"
    return 1
}

# Function to list all locks
list_locks() {
    echo "${BLUE}=== Active Branch Locks ===${RESET}"
    line_break

    if [[ ! -d "$LOCK_DIR" ]] || [[ -z "$(ls -A "$LOCK_DIR")" ]]; then
        echo "No active locks found"
        return 0
    fi

    for lock_file in "$LOCK_DIR"/*.lock; do
        if [[ -f "$lock_file" ]]; then
            source "$lock_file"
            local current_time=$(date +%s)

            if [[ $current_time -gt $EXPIRY_TIMESTAMP ]]; then
                rm -f "$lock_file"
                continue
            fi

            echo "Branch: ${YELLOW}$BRANCH${RESET}"
            echo "  Locked by: $LOCKED_BY"
            echo "  Reason: $REASON"
            echo "  Expires: $(date -d "@$EXPIRY_TIMESTAMP" '+%Y-%m-%d %H:%M:%S')"
            echo
        fi
    done
}

# Function to create branch backup
create_backup() {
    local branch=$1
    local description=$2
    local force=${3:-false}

    # Validate branch exists
    if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
        die "Branch ${branch} does not exist"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_id="${branch//\//_}_${timestamp}"
    local backup_file="$BACKUP_DIR/$backup_id"

    # Create backup bundle
    show_progress "Creating backup bundle"
    if ! git bundle create "${backup_file}.bundle" $branch --all; then
        complete_progress 1
        die "Failed to create backup bundle"
    fi
    complete_progress 0

    # Save metadata
    cat > "${backup_file}.meta" << EOF
BRANCH=$branch
BACKUP_ID=$backup_id
DESCRIPTION=$description
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
COMMIT_HASH=$(git rev-parse $branch)
CREATED_BY=$(git config user.name)
EOF

    success "Created backup of '$branch' (ID: $backup_id)"
}

# Function to restore from backup
restore_backup() {
    local backup_id=$1
    local force=${2:-false}
    local backup_file="$BACKUP_DIR/$backup_id"

    if [[ ! -f "${backup_file}.bundle" || ! -f "${backup_file}.meta" ]]; then
        die "Backup not found: $backup_id"
    fi

    source "${backup_file}.meta"

    # Confirm restoration
    if ! confirm_action "Restore branch '$BRANCH' to state from $CREATED_AT?" "$force"; then
        die "Restore cancelled"
    fi

    # Create temporary branch
    local temp_branch="restore_${BACKUP_ID}"

    show_progress "Restoring from backup"
    if git bundle verify "${backup_file}.bundle" && \
       git bundle unbundle "${backup_file}.bundle" $temp_branch && \
       git checkout -B "$BRANCH" $temp_branch && \
       git branch -D $temp_branch; then
        complete_progress 0
        success "Restored branch '$BRANCH' from backup"
    else
        complete_progress 1
        die "Failed to restore from backup"
    fi
}

# Function to list backups
list_backups() {
    echo "${BLUE}=== Available Branch Backups ===${RESET}"
    line_break

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR")" ]]; then
        echo "No backups found"
        return 0
    fi

    for meta_file in "$BACKUP_DIR"/*.meta; do
        if [[ -f "$meta_file" ]]; then
            source "$meta_file"
            echo "Backup ID: ${YELLOW}${BACKUP_ID}${RESET}"
            echo "  Branch: $BRANCH"
            echo "  Description: $DESCRIPTION"
            echo "  Created: $CREATED_AT"
            echo "  Created by: $CREATED_BY"
            echo
        fi
    done
}

# Function to clean old backups
clean_backups() {
    local days=${1:-$MAX_BACKUP_AGE}
    local count=0

    for backup_file in "$BACKUP_DIR"/*.bundle; do
        if [[ -f "$backup_file" ]]; then
            local file_age=$(( ($(date +%s) - $(stat -c %Y "$backup_file")) / 86400 ))
            if [[ $file_age -gt $days ]]; then
                local backup_id=$(basename "$backup_file" .bundle)
                rm -f "$backup_file" "${BACKUP_DIR}/${backup_id}.meta"
                ((count++))
            fi
        fi
    done

    if [[ $count -gt 0 ]]; then
        success "Removed $count old backup(s)"
    else
        info "No old backups to remove"
    fi
}

# Function to search branches
search_branches() {
    local criteria=$1
    local value=$2
    local date_range=$3

    echo "${BLUE}=== Branch Search Results ===${RESET}"
    line_break

    case $criteria in
        "creator")
            echo "Searching for branches by creator: $value"
            git for-each-ref --format='%(refname:short)|%(creator)' refs/heads/ | \
                grep -i "|.*$value" | cut -d'|' -f1 | while read branch; do
                    echo "${YELLOW}$branch${RESET}"
                    show_branch_details "$branch"
                done
            ;;
        "date")
            echo "Searching for branches by date range: $date_range"
            local start_date=$(date -d "$date_range" +%s 2>/dev/null)
            if [[ $? -ne 0 ]]; then
                die "Invalid date format"
            fi
            git for-each-ref --format='%(refname:short)|%(creatordate:unix)|%(creatordate:iso)' refs/heads/ | \
                while IFS='|' read branch timestamp date; do
                    if [[ $timestamp -ge $start_date ]]; then
                        echo "${YELLOW}$branch${RESET}"
                        show_branch_details "$branch"
                    fi
                done
            ;;
        "commit")
            echo "Searching for branches containing commit message: $value"
            git branch --list | while read branch; do
                if git log --format=%s ${branch#* } | grep -qi "$value"; then
                    echo "${YELLOW}${branch#* }${RESET}"
                    show_branch_details "${branch#* }"
                fi
            done
            ;;
        "ticket")
            echo "Searching for branches by ticket: $value"
            git branch --list | grep -i "$value" | while read branch; do
                echo "${YELLOW}${branch#* }${RESET}"
                show_branch_details "${branch#* }"
            done
            ;;
        *)
            die "Invalid search criteria"
            ;;
    esac
}

# Function to show branch details
show_branch_details() {
    local branch=$1
    local last_commit=$(git log -1 --format="%h - %s" "$branch")
    local author=$(git log -1 --format="%an" "$branch")
    local date=$(git log -1 --format="%cr" "$branch")
    local status=$(get_branch_status "$branch")
    
    echo "  Last commit: $last_commit"
    echo "  Author: $author"
    echo "  Date: $date"
    echo "  Status: $status"
    echo
}

# Function to filter branches by multiple criteria
filter_branches() {
    local type=$1
    local age=$2
    local status=$3
    local author=$4
    
    echo "${BLUE}=== Filtered Branch List ===${RESET}"
    line_break

    git for-each-ref refs/heads/ --format='%(refname:short)' | while read branch; do
        local include=true

        # Filter by type
        if [[ -n $type && ! $branch =~ ^$type/ ]]; then
            include=false
        fi

        # Filter by age
        if [[ -n $age ]]; then
            local commit_date=$(git log -1 --format=%ct "$branch")
            local age_days=$(( ($(date +%s) - commit_date) / 86400 ))
            if [[ $age_days -gt $age ]]; then
                include=false
            fi
        fi

        # Filter by status
        if [[ -n $status ]]; then
            local branch_status=$(get_branch_status "$branch")
            case $status in
                "ahead") [[ ! $branch_status =~ "Ahead" ]] && include=false ;;
                "behind") [[ ! $branch_status =~ "Behind" ]] && include=false ;;
                "diverged") [[ ! $branch_status =~ "Diverged" ]] && include=false ;;
            esac
        fi

        # Filter by author
        if [[ -n $author ]]; then
            local branch_author=$(git log -1 --format="%an" "$branch")
            if [[ ! $branch_author =~ $author ]]; then
                include=false
            fi
        fi

        # Show branch if it matches all filters
        if [[ $include == true ]]; then
            echo "${YELLOW}$branch${RESET}"
            show_branch_details "$branch"
        fi
    done
}

# Function to recover deleted branch
recover_deleted_branch() {
    local branch_name=$1
    local commit_hash=$2
    local force=${3:-false}

    echo "${BLUE}=== Recovering Deleted Branch ===${RESET}"
    line_break

    # If no commit hash provided, try to find it in reflog
    if [[ -z "$commit_hash" ]]; then
        show_progress "Searching for deleted branch in reflog"
        commit_hash=$(git reflog --no-abbrev | grep "branch: deleted $branch_name" | head -n1 | cut -d' ' -f1)
        if [[ -z "$commit_hash" ]]; then
            complete_progress 1
            die "Could not find deleted branch in reflog"
        fi
        complete_progress 0
    fi

    # Validate commit hash exists
    if ! git rev-parse --quiet --verify "$commit_hash^{commit}" >/dev/null; then
        die "Invalid commit hash: $commit_hash"
    fi

    # Confirm recovery
    if ! confirm_action "Recover branch '$branch_name' at commit $commit_hash?" "$force"; then
        die "Recovery cancelled"
    fi

    show_progress "Recovering branch"
    if git branch "$branch_name" "$commit_hash"; then
        complete_progress 0
        success "Recovered branch '$branch_name' at commit $commit_hash"
    else
        complete_progress 1
        die "Failed to recover branch"
    fi
}

# Function to fix common Git issues
fix_git_issue() {
    local issue_type=$1
    local branch=$2
    local force=${3:-false}

    echo "${BLUE}=== Fixing Git Issue ===${RESET}"
    line_break

    case $issue_type in
        "wrong_branch")
            # Save changes and switch to correct branch
            if [[ -z "$branch" ]]; then
                die "Target branch must be specified"
            fi

            show_progress "Stashing changes"
            if git stash; then
                complete_progress 0
                
                show_progress "Switching to target branch"
                if git checkout "$branch" && git stash pop; then
                    complete_progress 0
                    success "Successfully moved changes to $branch"
                else
                    complete_progress 1
                    die "Failed to apply changes to target branch"
                fi
            else
                complete_progress 1
                die "Failed to stash changes"
            fi
            ;;

        "bad_commit")
            # Undo last commit but keep changes
            show_progress "Undoing last commit"
            if git reset --soft HEAD^; then
                complete_progress 0
                success "Successfully undid last commit, changes are staged"
            else
                complete_progress 1
                die "Failed to undo commit"
            fi
            ;;

        "reset_hard")
            # Recover from hard reset
            show_progress "Finding last known good state"
            local last_hash=$(git reflog | grep -m1 "moving from" | cut -d' ' -f1)
            if [[ -n "$last_hash" ]]; then
                if ! confirm_action "Restore to commit $last_hash?" "$force"; then
                    die "Recovery cancelled"
                fi
                
                show_progress "Restoring to previous state"
                if git reset --hard "$last_hash"; then
                    complete_progress 0
                    success "Successfully recovered from hard reset"
                else
                    complete_progress 1
                    die "Failed to recover"
                fi
            else
                complete_progress 1
                die "Could not find recovery point"
            fi
            ;;

        *)
            die "Unknown issue type: $issue_type"
            ;;
    esac
}

# Function to undo last merge
undo_last_merge() {
    local branch=$1
    local force=${2:-false}

    echo "${BLUE}=== Undoing Last Merge ===${RESET}"
    line_break

    # Find last merge commit
    show_progress "Finding last merge commit"
    local merge_commit=$(git log --merges -n1 --format="%H")
    if [[ -z "$merge_commit" ]]; then
        complete_progress 1
        die "No merge commits found"
    fi
    complete_progress 0

    echo "Last merge commit: $(git show --format="%h - %s" $merge_commit)"

    # Confirm undo
    if ! confirm_action "Undo this merge?" "$force"; then
        die "Operation cancelled"
    fi

    # Create backup before undoing merge
    create_backup "$branch" "Auto-backup before undoing merge"

    show_progress "Reverting merge commit"
    if git revert -m 1 "$merge_commit"; then
        complete_progress 0
        success "Successfully undid merge"
    else
        complete_progress 1
        die "Failed to undo merge"
    fi
}

# Interactive menu functions
show_main_menu() {
    clear
    echo "${BLUE}=== Git Branch Manager ===${RESET}"
    line_break
    echo "1) Create new branch"
    echo "2) Delete branch"
    echo "3) List branches"
    echo "4) Merge branches"
    echo "5) Health check"
    echo "6) Manage stashes"
    echo "7) Visualize branches"
    echo "8) Differential analysis"
    echo "9) Manage locks"
    echo "10) Manage backups"
    echo "11) Recovery operations"
    echo "12) Search branches"
    echo "13) Git Diff Viewer"
    echo "14) Help"
    echo "15) Exit"
    line_break
    read -p "Select an option (1-15): " choice
    echo
    return $choice
}

interactive_create_branch() {
    clear
    echo "${BLUE}=== Create New Branch ===${RESET}"
    line_break

    # Step 1: Select branch type
    echo "Select branch type:"
    echo "1) Feature (from development)"
    echo "2) Bugfix (from development)"
    echo "3) Hotfix (from staging)"
    echo "4) Back to main menu"
    read -p "Enter choice (1-4): " type_choice

    case $type_choice in
        1) branch_type="feature";;
        2) branch_type="bugfix";;
        3) branch_type="hotfix";;
        4) return 0;;
        *) die "Invalid branch type selection";;
    esac

    # Step 2: Get ticket number
    echo
    echo "Ticket number format:"
    echo "- Must start with project code (e.g., PROJ-123)"
    echo "- Can be just numbers (e.g., 123)"
    echo "- No spaces or special characters"
    while true; do
        read -p "Enter ticket number: " ticket
        if [[ $ticket =~ $TICKET_PATTERN ]]; then
            break
        fi
        echo "${RED}Invalid ticket format. Please try again.${RESET}"
    done

    # Step 3: Optional suffix
    echo
    echo "Suffix rules:"
    echo "- Optional but recommended for clarity"
    echo "- Use lowercase letters, numbers, and hyphens"
    echo "- No spaces or special characters"
    echo "- Keep it short and descriptive"
    read -p "Add descriptive suffix? (y/n): " add_suffix
    if [[ $add_suffix == "y" ]]; then
        while true; do
            read -p "Enter suffix: " suffix
            if [[ $suffix =~ $SUFFIX_PATTERN ]]; then
                break
            fi
            echo "${RED}Invalid suffix format. Please try again.${RESET}"
        done
    fi

    # Step 4: Show summary
    echo
    echo "${BLUE}=== Branch Creation Summary ===${RESET}"
    line_break
    echo "Branch Type: ${YELLOW}$branch_type${RESET}"
    echo "Ticket: ${YELLOW}$ticket${RESET}"
    [[ -n "$suffix" ]] && echo "Suffix: ${YELLOW}$suffix${RESET}"
    echo "Base Branch: ${YELLOW}$([[ "$branch_type" == "hotfix" ]] && echo "staging" || echo "development")${RESET}"
    line_break

    # Step 5: Confirm action
    if ! confirm_action "Create branch with these settings?" false; then
        echo "Operation cancelled"
        return 1
    fi

    # Step 6: Execute action
    create_branch "$branch_type" "$ticket" "$suffix" false
}

interactive_delete_branch() {
    clear
    echo "${BLUE}=== Delete Branch ===${RESET}"
    line_break

    # Step 1: Show available branches with more details
    echo "Available branches:"
    list_branches "" true  # Show detailed branch list
    echo
    echo "Note: Protected branches (${PROTECTED_BRANCHES[*]}) cannot be deleted"
    line_break

    # Step 2: Get branch to delete
    while true; do
        read -p "Enter branch name to delete (or 'q' to quit): " branch_name
        [[ "$branch_name" == "q" ]] && return 0
        
        # Validate branch exists
        if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
            echo "${RED}Branch ${branch_name} does not exist. Please try again.${RESET}"
            continue
        fi

        # Step 3: Check if branch is protected
        if [[ " ${PROTECTED_BRANCHES[@]} " =~ " ${branch_name} " ]]; then
            echo "${RED}Cannot delete protected branch: ${branch_name}${RESET}"
            continue
        fi

        # Step 4: Check if branch is current
        if [[ "$(git rev-parse --abbrev-ref HEAD)" == "$branch_name" ]]; then
            echo "${RED}Cannot delete current branch. Please switch to another branch first.${RESET}"
            continue
        fi

        break
    done

    # Step 5: Show branch details before deletion
    echo
    echo "${BLUE}=== Branch Details ===${RESET}"
    line_break
    echo "Branch: ${YELLOW}$branch_name${RESET}"
    echo "Last commit: $(git log -1 --format="%h - %s" "$branch_name")"
    echo "Author: $(git log -1 --format="%an" "$branch_name")"
    echo "Date: $(git log -1 --format="%cr" "$branch_name")"
    line_break

    # Step 6: Ask about remote deletion
    read -p "Delete remote branch too? (y/n): " delete_remote
    local delete_remote_flag=$([[ $delete_remote == "y" ]] && echo true || echo false)

    # Step 7: Show summary
    echo
    echo "${BLUE}=== Deletion Summary ===${RESET}"
    line_break
    echo "Branch to delete: ${YELLOW}$branch_name${RESET}"
    echo "Delete remote: ${YELLOW}$([[ $delete_remote_flag == "true" ]] && echo "Yes" || echo "No")${RESET}"
    echo "Warning: This action cannot be undone!"
    line_break

    # Step 8: Confirm action
    if ! confirm_action "Are you absolutely sure you want to delete this branch?" false; then
        echo "Operation cancelled"
        return 1
    fi

    # Step 9: Execute action
    delete_branch "$branch_name" "$delete_remote_flag" false
}

interactive_merge_branches() {
    clear
    echo "${BLUE}=== Merge Branches ===${RESET}"
    line_break

    # Step 1: Show available branches with more details
    echo "Available branches:"
    list_branches "" true  # Show detailed branch list
    line_break

    # Step 2: Get source branch
    while true; do
        read -p "Enter source branch name (or 'q' to quit): " source_branch
        [[ "$source_branch" == "q" ]] && return 0
        
        if ! git show-ref --verify --quiet "refs/heads/${source_branch}"; then
            echo "${RED}Source branch ${source_branch} does not exist. Please try again.${RESET}"
            continue
        fi
        break
    done

    # Step 3: Get target branch
    while true; do
        read -p "Enter target branch name (or 'q' to quit): " target_branch
        [[ "$target_branch" == "q" ]] && return 0
        
        if ! git show-ref --verify --quiet "refs/heads/${target_branch}"; then
            echo "${RED}Target branch ${target_branch} does not exist. Please try again.${RESET}"
            continue
        fi
        break
    done

    # Step 4: Show branch details
    echo
    echo "${BLUE}=== Branch Details ===${RESET}"
    line_break
    echo "Source Branch: ${YELLOW}$source_branch${RESET}"
    echo "Last commit: $(git log -1 --format="%h - %s" "$source_branch")"
    echo "Author: $(git log -1 --format="%an" "$source_branch")"
    echo "Date: $(git log -1 --format="%cr" "$source_branch")"
    echo
    echo "Target Branch: ${YELLOW}$target_branch${RESET}"
    echo "Last commit: $(git log -1 --format="%h - %s" "$target_branch")"
    echo "Author: $(git log -1 --format="%an" "$target_branch")"
    echo "Date: $(git log -1 --format="%cr" "$target_branch")"
    line_break

    # Step 5: Select merge strategy
    echo "Select merge strategy:"
    echo "1) Standard merge (preserves history, creates merge commit)"
    echo "2) Rebase (linear history, no merge commit)"
    echo "3) Squash merge (single commit, clean history)"
    echo "4) Back to main menu"
    read -p "Enter choice (1-4): " strategy_choice

    case $strategy_choice in
        1) strategy="merge";;
        2) strategy="rebase";;
        3) strategy="squash";;
        4) return 0;;
        *) die "Invalid strategy selection";;
    esac

    # Step 6: Check for conflicts
    echo
    echo "${BLUE}=== Conflict Analysis ===${RESET}"
    line_break
    local conflicts=$(git merge-tree $(git merge-base $source_branch $target_branch) $source_branch $target_branch | grep -A3 "changed in both")
    if [[ -n "$conflicts" ]]; then
        echo "${RED}Potential conflicts detected:${RESET}"
        echo "$conflicts" | grep -E "^[+-]" | cut -d' ' -f2 | sort | uniq | sed 's/^/  /'
        echo
        echo "${YELLOW}Warning: These files have changes in both branches${RESET}"
    else
        echo "${GREEN}No potential conflicts detected${RESET}"
    fi
    line_break

    # Step 7: Show summary
    echo "${BLUE}=== Merge Summary ===${RESET}"
    line_break
    echo "Source Branch: ${YELLOW}$source_branch${RESET}"
    echo "Target Branch: ${YELLOW}$target_branch${RESET}"
    echo "Merge Strategy: ${YELLOW}$strategy${RESET}"
    echo "Warning: This action will modify the target branch!"
    line_break

    # Step 8: Confirm action
    if ! confirm_action "Proceed with merge?" false; then
        echo "Operation cancelled"
        return 1
    fi

    # Step 9: Execute action
    merge_branch "$source_branch" "$target_branch" "$strategy" false
}

interactive_health_check() {
    clear
    echo "${BLUE}=== Branch Health Check ===${RESET}"
    line_break

    # Step 1: Show available branches with details
    echo "Available branches:"
    list_branches "" true  # Show detailed branch list
    line_break

    # Step 2: Get branch to check
    while true; do
        read -p "Enter branch name to check (or 'q' to quit): " branch_name
        [[ "$branch_name" == "q" ]] && return 0
        
        if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
            echo "${RED}Branch ${branch_name} does not exist. Please try again.${RESET}"
            continue
        fi
        break
    done

    # Step 3: Get base branch
    echo
    echo "Base branch options:"
    echo "1) development (default)"
    echo "2) staging"
    echo "3) master"
    echo "4) Custom branch"
    read -p "Select base branch option (1-4): " base_choice

    case $base_choice in
        1) base_branch="development";;
        2) base_branch="staging";;
        3) base_branch="master";;
        4)
            while true; do
                read -p "Enter custom base branch name: " base_branch
                if ! git show-ref --verify --quiet "refs/heads/${base_branch}"; then
                    echo "${RED}Base branch ${base_branch} does not exist. Please try again.${RESET}"
                    continue
                fi
                break
            done
            ;;
        *) base_branch="development";;
    esac

    # Step 4: Show branch details
    echo
    echo "${BLUE}=== Branch Details ===${RESET}"
    line_break
    echo "Branch to check: ${YELLOW}$branch_name${RESET}"
    echo "Base branch: ${YELLOW}$base_branch${RESET}"
    echo "Last commit: $(git log -1 --format="%h - %s" "$branch_name")"
    echo "Author: $(git log -1 --format="%an" "$branch_name")"
    echo "Date: $(git log -1 --format="%cr" "$branch_name")"
    line_break

    # Step 5: Execute health check
    check_branch_health "$branch_name" "$base_branch"
}

interactive_manage_locks() {
    clear
    echo "${BLUE}=== Lock Management ===${RESET}"
    line_break

    # Step 1: Show available branches
    echo "Available branches:"
    list_branches "" true  # Show detailed branch list
    line_break

    # Step 2: Show menu options
    echo "Lock Management Options:"
    echo "1) Create lock"
    echo "2) Remove lock"
    echo "3) Check lock status"
    echo "4) List all locks"
    echo "5) Back to main menu"
    read -p "Select option (1-5): " lock_choice

    case $lock_choice in
        1)
            # Create lock
            while true; do
                read -p "Enter branch name (or 'q' to quit): " branch_name
                [[ "$branch_name" == "q" ]] && return 0
                
                if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
                    echo "${RED}Branch ${branch_name} does not exist. Please try again.${RESET}"
                    continue
                fi
                break
            done

            echo
            echo "Lock duration options:"
            echo "1) 24 hours"
            echo "2) 48 hours"
            echo "3) 72 hours"
            echo "4) Custom duration"
            read -p "Select duration option (1-4): " duration_choice

            case $duration_choice in
                1) duration=24;;
                2) duration=48;;
                3) duration=72;;
                4)
                    while true; do
                        read -p "Enter custom duration in hours: " duration
                        if [[ ! $duration =~ ^[0-9]+$ ]]; then
                            echo "${RED}Invalid duration. Please enter a number.${RESET}"
                            continue
                        fi
                        break
                    done
                    ;;
                *) duration=$MAX_LOCK_DURATION;;
            esac

            echo
            echo "Common lock reasons:"
            echo "1) Code review in progress"
            echo "2) Testing in progress"
            echo "3) Deployment in progress"
            echo "4) Custom reason"
            read -p "Select reason option (1-4): " reason_choice

            case $reason_choice in
                1) reason="Code review in progress";;
                2) reason="Testing in progress";;
                3) reason="Deployment in progress";;
                4)
                    read -p "Enter custom reason: " reason
                    ;;
                *) reason="Locked by user";;
            esac

            # Show summary
            echo
            echo "${BLUE}=== Lock Creation Summary ===${RESET}"
            line_break
            echo "Branch: ${YELLOW}$branch_name${RESET}"
            echo "Duration: ${YELLOW}$duration hours${RESET}"
            echo "Reason: ${YELLOW}$reason${RESET}"
            line_break

            if ! confirm_action "Create lock with these settings?" false; then
                echo "Operation cancelled"
                return 1
            fi

            create_lock "$branch_name" "$reason" "$duration" false
            ;;
        2)
            # Remove lock
            list_locks
            if [[ $? -eq 0 ]]; then
                while true; do
                    read -p "Enter branch name to unlock (or 'q' to quit): " branch_name
                    [[ "$branch_name" == "q" ]] && return 0
                    
                    if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
                        echo "${RED}Branch ${branch_name} does not exist. Please try again.${RESET}"
                        continue
                    fi
                    break
                done

                remove_lock "$branch_name" false
            fi
            ;;
        3)
            # Check lock status
            while true; do
                read -p "Enter branch name to check (or 'q' to quit): " branch_name
                [[ "$branch_name" == "q" ]] && return 0
                
                if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
                    echo "${RED}Branch ${branch_name} does not exist. Please try again.${RESET}"
                    continue
                fi
                break
            done

            check_lock "$branch_name"
            ;;
        4)
            # List all locks
            list_locks
            ;;
        5)
            return 0
            ;;
        *)
            die "Invalid option"
            ;;
    esac
}

interactive_manage_backups() {
    clear
    echo "${BLUE}=== Backup Management ===${RESET}"
    line_break

    # Step 1: Show available branches
    echo "Available branches:"
    list_branches "" true  # Show detailed branch list
    line_break

    # Step 2: Show menu options
    echo "Backup Management Options:"
    echo "1) Create backup"
    echo "2) Restore from backup"
    echo "3) List backups"
    echo "4) Clean old backups"
    echo "5) Back to main menu"
    read -p "Select option (1-5): " backup_choice

    case $backup_choice in
        1)
            # Create backup
            while true; do
                read -p "Enter branch name to backup (or 'q' to quit): " branch_name
                [[ "$branch_name" == "q" ]] && return 0
                
                if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
                    echo "${RED}Branch ${branch_name} does not exist. Please try again.${RESET}"
                    continue
                fi
                break
            done

            echo
            echo "Common backup descriptions:"
            echo "1) Pre-merge backup"
            echo "2) Pre-deployment backup"
            echo "3) Pre-refactoring backup"
            echo "4) Custom description"
            read -p "Select description option (1-4): " desc_choice

            case $desc_choice in
                1) description="Pre-merge backup";;
                2) description="Pre-deployment backup";;
                3) description="Pre-refactoring backup";;
                4)
                    read -p "Enter custom description: " description
                    ;;
                *) description="Manual backup";;
            esac

            # Show summary
            echo
            echo "${BLUE}=== Backup Creation Summary ===${RESET}"
            line_break
            echo "Branch: ${YELLOW}$branch_name${RESET}"
            echo "Description: ${YELLOW}$description${RESET}"
            line_break

            if ! confirm_action "Create backup with these settings?" false; then
                echo "Operation cancelled"
                return 1
            fi

            create_backup "$branch_name" "$description" false
            ;;
        2)
            # Restore from backup
            list_backups
            if [[ $? -eq 0 ]]; then
                while true; do
                    read -p "Enter backup ID to restore (or 'q' to quit): " backup_id
                    [[ "$backup_id" == "q" ]] && return 0
                    
                    if [[ ! -f "$BACKUP_DIR/${backup_id}.bundle" ]]; then
                        echo "${RED}Backup ${backup_id} does not exist. Please try again.${RESET}"
                        continue
                    fi
                    break
                done

                # Show backup details
                source "$BACKUP_DIR/${backup_id}.meta"
                echo
                echo "${BLUE}=== Backup Details ===${RESET}"
                line_break
                echo "Branch: ${YELLOW}$BRANCH${RESET}"
                echo "Description: ${YELLOW}$DESCRIPTION${RESET}"
                echo "Created at: ${YELLOW}$CREATED_AT${RESET}"
                echo "Created by: ${YELLOW}$CREATED_BY${RESET}"
                line_break

                if ! confirm_action "Restore this backup?" false; then
                    echo "Operation cancelled"
                    return 1
                fi

                restore_backup "$backup_id" false
            fi
            ;;
        3)
            # List backups
            list_backups
            ;;
        4)
            # Clean old backups
            echo
            echo "Cleanup options:"
            echo "1) Remove backups older than 30 days"
            echo "2) Remove backups older than 60 days"
            echo "3) Remove backups older than 90 days"
            echo "4) Custom age"
            read -p "Select cleanup option (1-4): " cleanup_choice

            case $cleanup_choice in
                1) days=30;;
                2) days=60;;
                3) days=90;;
                4)
                    while true; do
                        read -p "Enter age in days: " days
                        if [[ ! $days =~ ^[0-9]+$ ]]; then
                            echo "${RED}Invalid age. Please enter a number.${RESET}"
                            continue
                        fi
                        break
                    done
                    ;;
                *) days=$MAX_BACKUP_AGE;;
            esac

            if ! confirm_action "Remove backups older than $days days?" false; then
                echo "Operation cancelled"
                return 1
            fi

            clean_backups "$days"
            ;;
        5)
            return 0
            ;;
        *)
            die "Invalid option"
            ;;
    esac
}

interactive_recovery() {
    clear
    echo "${BLUE}=== Recovery Operations ===${RESET}"
    line_break

    # Step 1: Show available branches
    echo "Available branches:"
    list_branches "" true  # Show detailed branch list
    line_break

    # Step 2: Show menu options
    echo "Recovery Options:"
    echo "1) Recover deleted branch"
    echo "2) Undo merge"
    echo "3) Fix wrong commit"
    echo "4) Recover from hard reset"
    echo "5) Back to main menu"
    read -p "Select option (1-5): " recovery_choice

    case $recovery_choice in
        1)
            # Recover deleted branch
            echo
            echo "Recent deleted branches:"
            git reflog --date=local | grep "branch: Created from" | head -n 10
            line_break

            while true; do
                read -p "Enter branch name to recover (or 'q' to quit): " branch_name
                [[ "$branch_name" == "q" ]] && return 0
                
                if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
                    echo "${RED}Branch ${branch_name} already exists. Please try again.${RESET}"
                    continue
                fi
                break
            done

            # Show recovery details
            echo
            echo "${BLUE}=== Recovery Details ===${RESET}"
            line_break
            echo "Branch to recover: ${YELLOW}$branch_name${RESET}"
            echo "This will create a new branch with the same name"
            line_break

            if ! confirm_action "Recover this branch?" false; then
                echo "Operation cancelled"
                return 1
            fi

            recover_deleted_branch "$branch_name"
            ;;
        2)
            # Undo merge
            while true; do
                read -p "Enter branch name to undo merge (or 'q' to quit): " branch_name
                [[ "$branch_name" == "q" ]] && return 0
                
                if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
                    echo "${RED}Branch ${branch_name} does not exist. Please try again.${RESET}"
                    continue
                fi
                break
            done

            # Show merge history
            echo
            echo "Recent merges:"
            git log --merges --oneline -n 5
            line_break

            while true; do
                read -p "Enter merge commit hash (or 'q' to quit): " commit_hash
                [[ "$commit_hash" == "q" ]] && return 0
                
                if ! git rev-parse --verify --quiet "$commit_hash" >/dev/null; then
                    echo "${RED}Invalid commit hash. Please try again.${RESET}"
                    continue
                fi
                break
            done

            # Show undo details
            echo
            echo "${BLUE}=== Undo Merge Details ===${RESET}"
            line_break
            echo "Branch: ${YELLOW}$branch_name${RESET}"
            echo "Merge commit: ${YELLOW}$commit_hash${RESET}"
            echo "This will revert the merge commit and create a new commit"
            line_break

            if ! confirm_action "Undo this merge?" false; then
                echo "Operation cancelled"
                return 1
            fi

            undo_merge "$branch_name" "$commit_hash"
            ;;
        3)
            # Fix wrong commit
            while true; do
                read -p "Enter branch name (or 'q' to quit): " branch_name
                [[ "$branch_name" == "q" ]] && return 0
                
                if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
                    echo "${RED}Branch ${branch_name} does not exist. Please try again.${RESET}"
                    continue
                fi
                break
            done

            # Show recent commits
            echo
            echo "Recent commits:"
            git log --oneline -n 10
            line_break

            while true; do
                read -p "Enter commit hash to fix (or 'q' to quit): " commit_hash
                [[ "$commit_hash" == "q" ]] && return 0
                
                if ! git rev-parse --verify --quiet "$commit_hash" >/dev/null; then
                    echo "${RED}Invalid commit hash. Please try again.${RESET}"
                    continue
                fi
                break
            done

            # Show fix options
            echo
            echo "Fix options:"
            echo "1) Amend commit message"
            echo "2) Add/remove files"
            echo "3) Change author"
            read -p "Select fix option (1-3): " fix_choice

            case $fix_choice in
                1)
                    read -p "Enter new commit message: " new_message
                    fix_wrong_commit "$branch_name" "$commit_hash" "message" "$new_message"
                    ;;
                2)
                    echo "Modified files:"
                    git diff --name-only "$commit_hash^" "$commit_hash"
                    read -p "Enter files to add (space-separated): " files_to_add
                    read -p "Enter files to remove (space-separated): " files_to_remove
                    fix_wrong_commit "$branch_name" "$commit_hash" "files" "$files_to_add" "$files_to_remove"
                    ;;
                3)
                    read -p "Enter new author name: " new_author
                    read -p "Enter new author email: " new_email
                    fix_wrong_commit "$branch_name" "$commit_hash" "author" "$new_author" "$new_email"
                    ;;
                *)
                    die "Invalid option"
                    ;;
            esac
            ;;
        4)
            # Recover from hard reset
            echo
            echo "Recent commits (including lost ones):"
            git reflog --date=local | head -n 10
            line_break

            while true; do
                read -p "Enter commit hash to recover to (or 'q' to quit): " commit_hash
                [[ "$commit_hash" == "q" ]] && return 0
                
                if ! git rev-parse --verify --quiet "$commit_hash" >/dev/null; then
                    echo "${RED}Invalid commit hash. Please try again.${RESET}"
                    continue
                fi
                break
            done

            # Show recovery details
            echo
            echo "${BLUE}=== Hard Reset Recovery Details ===${RESET}"
            line_break
            echo "Recovering to commit: ${YELLOW}$commit_hash${RESET}"
            echo "This will move the current branch pointer to this commit"
            echo "Warning: This operation cannot be undone"
            line_break

            if ! confirm_action "Recover to this commit?" false; then
                echo "Operation cancelled"
                return 1
            fi

            recover_from_hard_reset "$commit_hash"
            ;;
        5)
            return 0
            ;;
        *)
            die "Invalid option"
            ;;
    esac
}

interactive_search() {
    clear
    echo "${BLUE}=== Branch Search ===${RESET}"
    line_break

    echo "1) Search by creator"
    echo "2) Search by date"
    echo "3) Search by commit message"
    echo "4) Search by ticket"
    echo "5) Advanced filtering"
    read -p "Select search type (1-5): " search_choice

    case $search_choice in
        1)
            read -p "Enter creator name: " creator
            search_branches "creator" "$creator"
            ;;
        2)
            read -p "Enter date range (e.g., '7 days ago'): " date_range
            search_branches "date" "" "$date_range"
            ;;
        3)
            read -p "Enter commit message: " message
            search_branches "commit" "$message"
            ;;
        4)
            read -p "Enter ticket: " ticket
            search_branches "ticket" "$ticket"
            ;;
        5)
            echo "Enter filter criteria (comma-separated):"
            echo "Format: type:value,age:days,status:state,author:name"
            read -p "> " filters
            IFS=',' read -ra filter_array <<< "$filters"
            filter_branches "${filter_array[@]}"
            ;;
        *)
            die "Invalid option"
            ;;
    esac
}

# Function to manage stashes interactively
interactive_manage_stashes() {
    clear
    echo "${BLUE}=== Stash Management ===${RESET}"
    line_break

    echo "1) View stash list"
    echo "2) Save current changes to stash"
    echo "3) Apply/Pop stash"
    echo "4) Drop stash"
    echo "5) Back to main menu"
    
    read -p "Select option (1-5): " stash_choice

    case $stash_choice in
        1)
            clear
            echo "${BLUE}=== Stash List ===${RESET}"
            line_break
            git stash list
            ;;
        2)
            if ! git diff --quiet HEAD; then
                read -p "Enter description for stash: " stash_desc
                if git stash push -m "$stash_desc"; then
                    success "Changes stashed successfully"
                else
                    die "Failed to stash changes"
                fi
            else
                info "No changes to stash"
            fi
            ;;
        3)
            clear
            echo "${BLUE}=== Available Stashes ===${RESET}"
            line_break
            git stash list
            
            if [[ $(git stash list | wc -l) -gt 0 ]]; then
                read -p "Enter stash number to apply (0 is most recent): " stash_num
                
                echo "Select action:"
                echo "1) Pop stash (apply and remove)"
                echo "2) Apply stash (keep in stash list)"
                read -p "Choose action (1-2): " action_choice

                case $action_choice in
                    1)
                        if git stash pop "stash@{$stash_num}"; then
                            success "Stash popped successfully"
                        else
                            die "Failed to pop stash. Resolve conflicts manually"
                        fi
                        ;;
                    2)
                        if git stash apply "stash@{$stash_num}"; then
                            success "Stash applied successfully"
                        else
                            die "Failed to apply stash. Resolve conflicts manually"
                        fi
                        ;;
                    *)
                        die "Invalid choice"
                        ;;
                esac
            else
                info "No stashes found"
            fi
            ;;
        4)
            clear
            echo "${BLUE}=== Available Stashes ===${RESET}"
            line_break
            git stash list
            
            if [[ $(git stash list | wc -l) -gt 0 ]]; then
                read -p "Enter stash number to drop (0 is most recent): " stash_num
                
                if ! confirm_action "Drop stash@{$stash_num}?" false; then
                    die "Operation cancelled"
                fi

                if git stash drop "stash@{$stash_num}"; then
                    success "Stash dropped successfully"
                else
                    die "Failed to drop stash"
                fi
            else
                info "No stashes found"
            fi
            ;;
        5)
            return 0
            ;;
        *)
            die "Invalid option"
            ;;
    esac
}

# Function to check for uncommitted changes and offer to stash
check_and_stash() {
    if ! git diff --quiet HEAD; then
        echo "${YELLOW}Uncommitted changes detected${RESET}"
        read -p "Would you like to stash these changes? (yes/no): " stash_choice
        
        if [[ $stash_choice == "yes" ]]; then
            read -p "Enter description for stash: " stash_desc
            if git stash push -m "$stash_desc"; then
                success "Changes stashed successfully"
                return 0
            else
                die "Failed to stash changes"
            fi
        fi
    fi
    return 0
}

# Function to restore stash if needed
restore_stash() {
    local latest_stash=$(git stash list | head -n1 | cut -d: -f1)
    
    if [[ -n $latest_stash ]]; then
        read -p "Would you like to restore your stashed changes? (yes/no): " restore_choice
        
        if [[ $restore_choice == "yes" ]]; then
            if git stash pop; then
                success "Stash restored successfully"
            else
                warn "Conflicts occurred while restoring stash. Please resolve manually"
            fi
        fi
    fi
}

# Function to handle interactive differential analysis
interactive_diff_analysis() {
    clear
    echo "${BLUE}=== Differential Analysis ===${RESET}"
    line_break

    echo "1) Generate change summary"
    echo "2) Create patch file"
    echo "3) Apply patch file"
    echo "4) Back to main menu"

    read -p "Select option (1-4): " diff_choice

    case $diff_choice in
        1)
            clear
            echo "${BLUE}=== Generate Change Summary ===${RESET}"
            line_break
            
            # Show available branches
            echo "Available branches:"
            git branch | sed 's/^[ *]*//' | nl
            
            read -p "Enter source branch number: " source_num
            source_branch=$(git branch | sed 's/^[ *]*//' | sed -n "${source_num}p")
            
            read -p "Enter target branch number: " target_num
            target_branch=$(git branch | sed 's/^[ *]*//' | sed -n "${target_num}p")
            
            if [[ -n $source_branch && -n $target_branch ]]; then
                echo
                echo "${BLUE}=== Change Summary ===${RESET}"
                line_break
                
                # Show commit count
                local commit_count=$(git rev-list --count $target_branch..$source_branch)
                echo "Total commits: $commit_count"
                echo
                
                # Show file statistics
                echo "File changes:"
                git diff --stat $target_branch...$source_branch
                echo
                
                # Show detailed changes by type
                echo "Changed files by type:"
                echo "${GREEN}Added files:${RESET}"
                git diff --name-only --diff-filter=A $target_branch...$source_branch | sed 's/^/  /'
                echo
                echo "${YELLOW}Modified files:${RESET}"
                git diff --name-only --diff-filter=M $target_branch...$source_branch | sed 's/^/  /'
                echo
                echo "${RED}Deleted files:${RESET}"
                git diff --name-only --diff-filter=D $target_branch...$source_branch | sed 's/^/  /'
                echo
                
                # Show potential conflicts
                echo "Conflict analysis:"
                local conflicts=$(git merge-tree $(git merge-base $source_branch $target_branch) $source_branch $target_branch | grep -A3 "changed in both")
                if [[ -n "$conflicts" ]]; then
                    echo "${RED}Potential conflicts detected in:${RESET}"
                    echo "$conflicts" | grep -E "^[+-]" | cut -d' ' -f2 | sort | uniq | sed 's/^/  /'
                else
                    echo "${GREEN}No potential conflicts detected${RESET}"
                fi
            else
                die "Invalid branch selection"
            fi
            ;;
        2)
            clear
            echo "${BLUE}=== Create Patch File ===${RESET}"
            line_break
            
            # Show available branches
            echo "Available branches:"
            git branch | sed 's/^[ *]*//' | nl
            
            read -p "Enter source branch number: " source_num
            source_branch=$(git branch | sed 's/^[ *]*//' | sed -n "${source_num}p")
            
            read -p "Enter target branch number: " target_num
            target_branch=$(git branch | sed 's/^[ *]*//' | sed -n "${target_num}p")
            
            if [[ -n $source_branch && -n $target_branch ]]; then
                # Create patches directory if it doesn't exist
                mkdir -p patches
                
                # Generate timestamp for patch file
                local timestamp=$(date +%Y%m%d_%H%M%S)
                local patch_file="patches/patch_${source_branch//\//_}_${timestamp}.patch"
                
                # Generate patch
                if git diff $target_branch...$source_branch > "$patch_file"; then
                    success "Generated patch file: $patch_file"
                    echo
                    echo "Patch statistics:"
                    git diff --stat $target_branch...$source_branch
                else
                    die "Failed to generate patch file"
                fi
            else
                die "Invalid branch selection"
            fi
            ;;
        3)
            clear
            echo "${BLUE}=== Apply Patch File ===${RESET}"
            line_break
            
            # Show available patch files
            echo "Available patches:"
            ls -1 patches/*.patch 2>/dev/null | nl
            
            if [[ $? -eq 0 ]]; then
                read -p "Enter patch number to apply: " patch_num
                patch_file=$(ls -1 patches/*.patch 2>/dev/null | sed -n "${patch_num}p")
                
                if [[ -f "$patch_file" ]]; then
                    echo
                    echo "Patch contents:"
                    git apply --stat "$patch_file"
                    
                    if ! confirm_action "Apply this patch?" false; then
                        die "Operation cancelled"
                    fi
                    
                    # Check if patch can be applied
                    if ! git apply --check "$patch_file"; then
                        die "Patch cannot be applied cleanly"
                    fi
                    
                    # Apply patch
                    if git apply "$patch_file"; then
                        success "Successfully applied patch"
                    else
                        die "Failed to apply patch"
                    fi
                else
                    die "Invalid patch selection"
                fi
            else
                info "No patch files found in patches directory"
            fi
            ;;
        4)
            return 0
            ;;
        *)
            die "Invalid option"
            ;;
    esac
}

# Function to show detailed git diff
show_detailed_diff() {
    local target=${1:-HEAD}
    local show_all=${2:-false}
    local specific_file=$3

    echo "${BLUE}=== Git Diff Analysis ===${RESET}"
    line_break

    # Get current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Current branch: ${YELLOW}${current_branch}${RESET}"
    line_break

    if [[ -n "$specific_file" ]]; then
        # Show changes for specific file
        if [[ -f "$specific_file" ]]; then
            echo "${BLUE}Changes in file: ${specific_file}${RESET}"
            line_break
            git diff --color "$target" -- "$specific_file"
        else
            die "File not found: $specific_file"
        fi
        return
    fi

    # Summary of changes
    echo "${BLUE}Change Summary:${RESET}"
    local total_files=$(git diff --name-only "$target" | wc -l)
    local added_files=$(git diff --name-only --diff-filter=A "$target" | wc -l)
    local modified_files=$(git diff --name-only --diff-filter=M "$target" | wc -l)
    local deleted_files=$(git diff --name-only --diff-filter=D "$target" | wc -l)
    
    echo "Total changed files: $total_files"
    echo "${GREEN}Added files: $added_files${RESET}"
    echo "${YELLOW}Modified files: $modified_files${RESET}"
    echo "${RED}Deleted files: $deleted_files${RESET}"
    line_break

    # Show stat summary
    echo "${BLUE}File Statistics:${RESET}"
    git diff --stat "$target"
    line_break

    if [[ "$show_all" == "true" ]]; then
        # Show full diff
        echo "${BLUE}Detailed Changes:${RESET}"
        git diff --color "$target"
    else
        # Show list of changed files
        echo "${BLUE}Changed Files:${RESET}"
        echo "${GREEN}Added:${RESET}"
        git diff --name-only --diff-filter=A "$target" | sed 's/^/  + /'
        
        echo "${YELLOW}Modified:${RESET}"
        git diff --name-only --diff-filter=M "$target" | sed 's/^/  ~ /'
        
        echo "${RED}Deleted:${RESET}"
        git diff --name-only --diff-filter=D "$target" | sed 's/^/  - /'
        
        line_break
        echo "Use 'View specific file' option to see detailed changes"
    fi
}

# Function to show git status
show_git_status() {
    local detailed=${1:-false}

    echo "${BLUE}=== Git Status ===${RESET}"
    line_break

    # Get current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Current branch: ${YELLOW}${current_branch}${RESET}"
    line_break

    if [[ "$detailed" == "true" ]]; then
        # Show detailed status
        git status -v
    else
        # Show concise status
        git status -s
        
        # Show summary
        local staged=$(git diff --staged --name-only | wc -l)
        local modified=$(git diff --name-only | wc -l)
        local untracked=$(git ls-files --others --exclude-standard | wc -l)
        
        echo
        echo "Summary:"
        echo "${GREEN}Staged changes: $staged${RESET}"
        echo "${YELLOW}Modified files: $modified${RESET}"
        echo "${BLUE}Untracked files: $untracked${RESET}"
    fi
}

# Function to handle interactive diff viewing
interactive_diff_viewer() {
    clear
    echo "${BLUE}=== Git Diff Viewer ===${RESET}"
    line_break

    echo "1) Show summary of changes"
    echo "2) Show all changes in detail"
    echo "3) View specific file changes"
    echo "4) Compare with specific commit/branch"
    echo "5) Back to main menu"

    read -p "Select option (1-5): " diff_choice

    case $diff_choice in
        1)
            clear
            show_detailed_diff "HEAD" false
            ;;
        2)
            clear
            show_detailed_diff "HEAD" true
            ;;
        3)
            clear
            echo "${BLUE}Changed files:${RESET}"
            line_break
            git status --short | nl
            
            if [[ $(git status --short | wc -l) -gt 0 ]]; then
                read -p "Enter file number to view (0 to cancel): " file_num
                if [[ $file_num -gt 0 ]]; then
                    local selected_file=$(git status --short | sed -n "${file_num}p" | cut -c4-)
                    clear
                    show_detailed_diff "HEAD" false "$selected_file"
                fi
            else
                info "No changed files found"
            fi
            ;;
        4)
            clear
            echo "${BLUE}Available branches and commits:${RESET}"
            line_break
            echo "Recent commits:"
            git log --oneline -n 5
            echo
            echo "Branches:"
            git branch | sed 's/^[ *]*//' | nl
            
            read -p "Enter commit hash or branch name to compare with: " target
            if git rev-parse --verify "$target" >/dev/null 2>&1; then
                clear
                show_detailed_diff "$target" false
            else
                die "Invalid commit/branch: $target"
            fi
            ;;
        5)
            return 0
            ;;
        *)
            die "Invalid option"
            ;;
    esac
}

# Function to process filter specifications
process_filter_spec() {
    local filter_spec=$1
    
    # Parse filter specification (format: type:value:criteria)
    IFS=':' read -r filter_type filter_value filter_criteria <<< "$filter_spec"
    
    case $filter_type in
        "branch")
            list_branches "$filter_value" true
            ;;
        "age")
            if [[ -n $filter_value ]]; then
                filter_branches "" "$filter_value" "" ""
            else
                die "Age filter requires a value (days)"
            fi
            ;;
        "commit")
            search_branches "commit" "$filter_value" ""
            ;;
        "user")
            search_branches "creator" "$filter_value" ""
            ;;
        *)
            die "Invalid filter type: $filter_type"
            ;;
    esac
}

# Main execution
main() {
    # Validate git repository
    validate_git_repo

    # Parse command line arguments if any
    if [[ $# -gt 0 ]]; then
        while getopts "t:j:s:hid:m:l:b:r:f:v:H:S:D:L:U:B:R:Q:F:X:" opt; do
            case $opt in
                t) branch_type="$OPTARG";;
                j) ticket="$OPTARG";;
                s) suffix="$OPTARG";;
                h) show_help; exit 0;;
                i) INTERACTIVE=true;;
                d) DELETE_BRANCH="$OPTARG";;
                m) MERGE_SPEC="$OPTARG";;
                l) LIST_FILTER="$OPTARG";;
                b) BACKUP_BRANCH="$OPTARG";;
                r) RECOVER_BRANCH="$OPTARG";;
                f) FILTER_SPEC="$OPTARG";;
                v) VISUALIZE_FILTER="$OPTARG";;
                H) HEALTH_CHECK_BRANCH="$OPTARG";;
                S) STATUS_TYPE="$OPTARG";;      # Git Status
                D) DIFF_TARGET="$OPTARG";;      # Git Diff
                L) LOCK_SPEC="$OPTARG";;        # Lock Management
                U) UNLOCK_BRANCH="$OPTARG";;    # Lock Removal
                B) BACKUP_SPEC="$OPTARG";;      # Backup Management
                R) RESTORE_BACKUP="$OPTARG";;   # Backup Restoration
                Q) SEARCH_SPEC="$OPTARG";;      # Branch Search
                F) FILTER_CRITERIA="$OPTARG";;  # Advanced Filtering
                X) DIFF_COMPARE="$OPTARG";;     # Diff Comparison
                *) die "Invalid option: -$OPTARG";;
            esac
        done

        # Process command line operations
        if [[ -n $branch_type && -n $ticket ]]; then
            create_branch "$branch_type" "$ticket" "$suffix" false
        fi

        # Branch deletion
        [[ -n $DELETE_BRANCH ]] && delete_branch "$DELETE_BRANCH" true false

        # Branch merging
        if [[ -n $MERGE_SPEC ]]; then
            IFS=':' read -r source target strategy <<< "$MERGE_SPEC"
            merge_branch "$source" "$target" "${strategy:-merge}" false
        fi

        # Branch listing
        [[ -n $LIST_FILTER ]] && list_branches "$LIST_FILTER" true

        # Git Status
        if [[ -n $STATUS_TYPE ]]; then
            case $STATUS_TYPE in
                "basic") show_git_status false;;
                "detailed") show_git_status true;;
                file:*) git diff --color "${STATUS_TYPE#file:}";;
                *) show_git_status false;;
            esac
        fi

        # Git Diff
        if [[ -n $DIFF_TARGET ]]; then
            case $DIFF_TARGET in
                "summary") show_detailed_diff "HEAD" false;;
                "detailed") show_detailed_diff "HEAD" true;;
                file:*) show_detailed_diff "HEAD" false "${DIFF_TARGET#file:}";;
                *) show_detailed_diff "$DIFF_TARGET" false;;
            esac
        fi

        # Diff Comparison
        if [[ -n $DIFF_COMPARE ]]; then
            IFS=':' read -r source target <<< "$DIFF_COMPARE"
            show_detailed_diff "$source" false "$target"
        fi

        # Lock Management
        if [[ -n $LOCK_SPEC ]]; then
            IFS=':' read -r branch reason duration <<< "$LOCK_SPEC"
            create_lock "$branch" "$reason" "${duration:-24}" false
        fi

        # Lock Removal
        [[ -n $UNLOCK_BRANCH ]] && remove_lock "$UNLOCK_BRANCH" false

        # Backup Management
        if [[ -n $BACKUP_SPEC ]]; then
            if [[ $BACKUP_SPEC == "list" ]]; then
                list_backups
            elif [[ $BACKUP_SPEC == "clean" ]]; then
                clean_backups
            else
                IFS=':' read -r branch description <<< "$BACKUP_SPEC"
                create_backup "$branch" "$description" false
            fi
        fi

        # Backup Restoration
        [[ -n $RESTORE_BACKUP ]] && restore_backup "$RESTORE_BACKUP" false

        # Branch Search
        if [[ -n $SEARCH_SPEC ]]; then
            IFS=':' read -r criteria value date_range <<< "$SEARCH_SPEC"
            search_branches "$criteria" "$value" "$date_range"
        fi

        # Advanced Filtering
        if [[ -n $FILTER_CRITERIA ]]; then
            IFS=',' read -ra filters <<< "$FILTER_CRITERIA"
            filter_branches "${filters[@]}"
        fi

        # Additional operations
        [[ -n $BACKUP_BRANCH ]] && create_backup "$BACKUP_BRANCH" "CLI backup" false
        [[ -n $RECOVER_BRANCH ]] && recover_deleted_branch "$RECOVER_BRANCH" "" false
        [[ -n $FILTER_SPEC ]] && process_filter_spec "$FILTER_SPEC"
        [[ -n $VISUALIZE_FILTER ]] && visualize_branches 20 "$VISUALIZE_FILTER"
        [[ -n $HEALTH_CHECK_BRANCH ]] && check_branch_health "$HEALTH_CHECK_BRANCH"
        
        exit 0
    fi

    # Interactive mode
    while true; do
        show_main_menu
        choice=$?

        case $choice in
            1) interactive_create_branch;;
            2) interactive_delete_branch;;
            3) list_branches;;
            4) interactive_merge_branches;;
            5) interactive_health_check;;
            6) interactive_manage_stashes;;
            7) visualize_branches;;
            8) interactive_diff_analysis;;
            9) interactive_manage_locks;;
            10) interactive_manage_backups;;
            11) interactive_recovery;;
            12) interactive_search;;
            13) interactive_diff_viewer;;  # New Git Diff Viewer
            14) show_help;;
            15) echo "Exiting..."; exit 0;;
            *) echo "${RED}Invalid choice${RESET}";;
        esac

        echo
        read -p "Press Enter to continue..."
    done
}

# Start execution
main "$@"