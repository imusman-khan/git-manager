# Git Branch Manager

A comprehensive tool for managing Git branches with advanced features and safety checks.

## Overview

The Git Branch Manager is a powerful Bash script that provides both interactive and command-line interfaces for managing Git branches. It offers a wide range of features including branch creation, merging, backup management, recovery operations, and more. The script is designed to be user-friendly while maintaining the power and flexibility of Git.

## Key Features

1. Interactive Mode
   - Guided workflows
   - Clear prompts and confirmations
   - Help available at each step
   - Operation previews

2. Command Line Mode
   - Direct operations
   - Multiple options
   - Batch processing
   - Automation support

3. Safety Features
   - Operation validation
   - Automatic backups
   - Conflict detection
   - Clear confirmations

## Prerequisites

- Git installed and configured
- Bash shell
- A Unix-like environment (Linux, macOS, WSL)
- Write permissions to the git repository

## Installation

1. Clone or download the script to your project directory
2. Make the script executable:
```bash
chmod +x script.sh
```

3. Add the script to your PATH (optional):
```bash
sudo ln -s $(pwd)/script.sh /usr/local/bin/git-manager
```

## Usage

### Interactive Mode

Run the script without any arguments to enter interactive mode:
```bash
./script.sh
```

### Command Line Mode

The script can also be used with command-line arguments for automation:

```bash
./script.sh [OPTIONS]
```

Available options:
- `-t TYPE`: Branch type (feature, bugfix, hotfix)
- `-j TICKET`: Ticket number (e.g., PROJ-123)
- `-s SUFFIX`: Optional branch name suffix
- `-i`: Interactive mode
- `-d BRANCH`: Delete branch
- `-m SPEC`: Merge branches (format: source:target:strategy)
- `-l FILTER`: List branches with filter
- `-b BRANCH`: Create backup of branch
- `-r BRANCH`: Recover deleted branch
- `-f SPEC`: Filter specification
- `-v FILTER`: Visualize branches with filter
- `-H BRANCH`: Health check for branch
- `-S TYPE`: Show git status (basic, detailed, file:PATH)
- `-D TARGET`: Show git diff (summary, detailed, file:PATH)
- `-L SPEC`: Create lock (format: branch:reason:duration)
- `-U BRANCH`: Remove lock from branch
- `-B SPEC`: Backup management (format: branch:description or 'list' or 'clean')
- `-R ID`: Restore from backup ID
- `-Q SPEC`: Branch search (format: criteria:value:date_range)
- `-F CRITERIA`: Advanced filtering (format: criteria1,criteria2,...)
- `-X SPEC`: Diff comparison (format: source:target)
- `-h`: Show help message

## Detailed Feature Documentation

### 1. Branch Creation

#### Interactive Mode
Run the script without arguments and select option 1:
```bash
./script.sh
```

The interactive creation mode will:
1. Show branch type options
2. Prompt for ticket number
3. Allow optional suffix
4. Show confirmation summary

#### Command Line Mode
```bash
./script.sh -t {branch_type} -j {ticket} [-s {suffix}]
```

#### Branch Creation Rules

1. **Feature Branches**
   - Created from: `development` branch
   - Naming format: `feature/{ticket}[-{suffix}]`
   - Base branch is automatically checked out and updated

2. **Bugfix Branches**
   - Created from: `development` branch
   - Naming format: `bugfix/{ticket}[-{suffix}]`
   - Base branch is automatically checked out and updated

3. **Hotfix Branches**
   - Created from: `staging` branch only
   - Naming format: `hotfix/{ticket}[-{suffix}]`
   - Base branch is automatically checked out and updated

#### Validation Rules

1. Branch Type Validation:
   - Must be one of: `feature`, `bugfix`, or `hotfix`
   - Case sensitive

2. Ticket Validation:
   - Must match format: `PROJECT-NUMBER`
   - Example: `PROJ-123`

3. Suffix Validation (if provided):
   - Cannot contain spaces
   - Only letters, numbers, hyphens, and underscores allowed
   - Optional

4. Base Branch Validation:
   - Cannot create branches from `qa`
   - Hotfix branches only from `staging`
   - Feature and bugfix branches only from `development`

### 2. Branch Deletion

#### Interactive Mode
Run the script without arguments and select option 2:
```bash
./script.sh
```

The interactive deletion mode will:
1. Show a list of available local branches
2. Allow you to select a branch by number
3. Ask if you want to delete the remote branch as well
4. Show a confirmation summary before proceeding

#### Command Line Mode
```bash
./script.sh -d branch-name [-r]
```

#### Safety Features
- Verification that the branch exists
- Prevention of deleting the currently checked out branch
- Warning and confirmation for unmerged branches
- Confirmation before remote deletion
- Error handling for remote deletion failures

### 3. Branch Merging

#### Interactive Mode
Run the script without arguments and select option 4:
```bash
./script.sh
```

The interactive merge mode will:
1. Show a list of available branches
2. Allow you to select source and target branches
3. Choose between merge strategies:
   - Standard merge
   - Rebase
   - Squash merge
4. Show a confirmation summary before proceeding

#### Command Line Mode
```bash
./script.sh -m source-branch:target-branch:strategy
```

#### Merge Features
- Automatic stashing of local changes
- Conflict detection and handling
- Branch validation
- Status check before operation
- Interactive branch selection
- Choice between merge strategies

### 4. Health Checking

#### Interactive Mode
Run the script without arguments and select option 5:
```bash
./script.sh
```

The interactive health check mode will:
1. Show a list of available branches
2. Allow you to select a branch to check
3. Choose a base branch for comparison
4. Display comprehensive health status

#### Command Line Mode
```bash
./script.sh -H branch-name
```

#### Health Check Features
1. **Remote Sync Status**
   - Checks if branch exists remotely
   - Verifies local and remote are in sync
   - Shows required sync actions if needed

2. **Base Branch Status**
   - Checks if branch is up to date with base branch
   - Shows number of commits ahead/behind
   - Indicates if update is needed

3. **Conflict Detection**
   - Identifies potential merge conflicts
   - Lists files that may have conflicts
   - Provides early warning before operations

4. **Working Directory Status**
   - Checks for uncommitted changes
   - Ensures clean working state
   - Warns about pending commits

### 5. Stash Management

#### Interactive Mode
Run the script without arguments and select option 6:
```bash
./script.sh
```

The interactive stash management mode provides:
1. View list of existing stashes
2. Save current changes to stash
3. Apply/Pop existing stashes
4. Automatic stash detection before operations

#### Command Line Mode
```bash
./script.sh -S list    # List all stashes
./script.sh -S save    # Save current changes
./script.sh -S pop     # Pop most recent stash
```

#### Stash Features
1. **Automatic Stash Detection**
   - Detects uncommitted changes before operations
   - Prompts to stash changes when needed
   - Provides option to proceed without stashing

2. **Stash Management**
   - List all existing stashes
   - Save changes with custom descriptions
   - Apply/Pop specific stashes
   - Handle stash conflicts

### 6. Branch Visualization

#### Interactive Mode
Run the script without arguments and select option 7:
```bash
./script.sh
```

The interactive visualization mode offers:
1. Branch graph view
2. Compact branch tree
3. Branch relationship analysis
4. Filtered visualization options

#### Command Line Mode
```bash
./script.sh -v [filter]     # Show branch graph with optional filter
./script.sh -V branch-name  # Show branch relationships
```

#### Visualization Types
1. **Branch Graph**
   - Shows commit history with branch points
   - Indicates current HEAD position
   - Displays commit authors and times
   - Supports filtering by branch name

2. **Branch Tree**
   - Shows hierarchical branch structure
   - Indicates branch depths
   - Highlights current branch
   - Shows parent-child relationships

### 7. Differential Analysis

#### Interactive Mode
Run the script without arguments and select option 8:
```bash
./script.sh
```

The interactive differential analysis mode offers:
1. Generate change summaries between branches
2. Create patch files
3. Apply existing patches
4. Conflict detection

#### Command Line Mode
```bash
# Generate change summary
./script.sh -D source-branch:target-branch

# Create patch file
./script.sh -P source-branch:target-branch

# Apply patch
./script.sh -A patch-file
```

#### Analysis Features
1. **Change Summary**
   - Shows commit count
   - Lists changed files
   - Categorizes changes
   - Shows line modifications

2. **Patch Generation**
   - Creates timestamped patch files
   - Includes file statistics
   - Shows potential conflicts
   - Stores in dedicated patches directory

### 8. Branch Locking

#### Interactive Mode
Run the script without arguments and select option 9:
```bash
./script.sh
```

The interactive lock management mode offers:
1. Lock a branch
2. Remove lock
3. Show lock status
4. List all active locks

#### Command Line Mode
```bash
# Lock a branch
./script.sh -L branch-name:reason:duration

# Remove lock
./script.sh -U branch-name

# Show lock information
./script.sh -I branch-name
```

#### Lock Features
1. **Lock Creation**
   - Specify lock duration
   - Add lock reason
   - Automatic expiration
   - User identification

2. **Lock Information**
   - Lock creator details
   - Lock reason
   - Creation timestamp
   - Expiration time
   - Current status

### 9. Backup Management

#### Interactive Mode
Run the script without arguments and select option 10:
```bash
./script.sh
```

The interactive backup management mode offers:
1. Create branch backup
2. Restore from backup
3. List backups
4. Delete backup

#### Command Line Mode
```bash
# Create backup
./script.sh -B branch-name:description

# Restore from backup
./script.sh -R backup-id

# Delete backup
./script.sh -X backup-id
```

#### Backup Features
1. **Backup Creation**
   - Unique backup IDs
   - Custom descriptions
   - Timestamp information
   - Bundle-based storage

2. **Backup Information**
   - Branch name
   - Creation timestamp
   - Creator details
   - Commit hash
   - Custom description

### 10. Recovery Operations

#### Interactive Mode
Run the script without arguments and select option 11:
```bash
./script.sh
```

The interactive recovery mode offers:
1. Recover deleted branches
2. Undo last merge
3. Fix common mistakes
4. View operation history

#### Command Line Mode
```bash
# Recover deleted branch
./script.sh -Z branch-name[:commit-hash]

# Undo last merge
./script.sh -Y branch-name

# Show operation history
./script.sh -H
```

#### Recovery Features
1. **Branch Recovery**
   - Automatic reflog search
   - Optional commit specification
   - Safe branch restoration
   - Operation logging

2. **Merge Undo**
   - Last merge identification
   - Automatic backup creation
   - Clean revert process
   - Conflict handling

### 11. Advanced Search

#### Interactive Mode
Run the script without arguments and select option 12:
```bash
./script.sh
```

The interactive search mode offers:
1. Search by creator
2. Search by date
3. Search by commit message
4. Search by ticket
5. Advanced filtering
6. Combined criteria search

#### Command Line Mode
```bash
# Simple search
./script.sh -Q criteria:value[:date-range]

# Advanced filtering
./script.sh -F filter1,filter2,filter3
```

#### Search Features
1. **Search by Metadata**
   - Creator name
   - Creation date
   - Last commit
   - JIRA tickets

2. **Date-Based Search**
   - Created within timeframe
   - Modified within timeframe
   - Custom date ranges
   - Relative dates

### 12. Git Diff Viewer

#### Interactive Mode
Run the script without arguments and select option 13:
```bash
./script.sh
```

The interactive diff viewer offers:
1. Show summary of changes
2. Show all changes in detail
3. View specific file changes
4. Compare with specific commit/branch

#### Command Line Mode
```bash
./script.sh -D [target] [options]
```

#### Diff Viewer Features
1. **Summary View**
   - Changed files list
   - File statistics
   - Change categories
   - Quick overview

2. **Detailed View**
   - Complete diff output
   - Colored changes
   - Line-by-line comparison
   - Context information

## Best Practices

1. Always use the interactive mode for complex operations
2. Review summaries before confirming actions
3. Use backups before critical operations
4. Check branch health regularly
5. Use locks when working on shared branches
6. Keep backups clean and organized

## Troubleshooting

1. **Permission Issues**
   - Ensure script is executable
   - Check Git permissions
   - Verify repository access

2. **Validation Errors**
   - Follow naming conventions
   - Check branch existence
   - Verify input formats

3. **Operation Failures**
   - Check Git status
   - Verify branch states
   - Review error messages

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

[Specify your license here]

## Support

For support, please [create an issue](repository-issues-url) or contact [support contact].
