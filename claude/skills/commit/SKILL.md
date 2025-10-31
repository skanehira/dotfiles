---
name: commit
description: Analyze changes and create Git commits with Conventional Commit format and emoji. This skill should be used when changes are ready to be committed. Automatically analyzes changes, groups by concern, generates appropriate commit messages, and executes commits immediately.
---

# Git Commit Creation

## Overview

Specialize in Git commit creation. Analyze staged and unstaged changes, automatically group them by concern (separate commits for each), generate Conventional Commit format messages with emoji, and execute commits immediately without user confirmation.

## When to Use This Skill

Use this skill when:
- Changes are ready to be committed
- Multiple changes need to be split into logical commits
- Conventional Commit format is required
- Automatic commit message generation is desired

## Core Responsibilities

1. **Change Analysis**: Analyze `git status` and `git diff` to understand modifications
2. **Message Generation**: Create Conventional Commit format + emoji messages
3. **Automatic Grouping**: Split multiple concerns into separate commits
4. **Immediate Execution**: Commit changes without asking for confirmation

## Workflow

### Step 1: Analyze Changes

```bash
# Check staging status
git status

# If no staged changes, stage everything
git add .

# View changes to commit
git diff --staged
```

### Step 2: Group by Concern

If changes contain multiple concerns, automatically split them:

**Example Concerns:**
- Concern 1: New feature added → Stage related files → Commit
- Concern 2: Documentation updated → Stage docs → Commit
- Concern 3: Dependencies updated → Stage package.json → Commit

**Process:**
```bash
# For each concern:
1. Stage files: git add <files-for-concern>
2. Generate commit message
3. Execute commit immediately
4. Move to next concern
```

### Step 3: Generate Commit Message

#### Format
```
<emoji> <type>: <description>

<optional body>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

#### Type and Emoji Mapping

| Type | Emoji | Description |
|------|-------|-------------|
| `feat` | ✨ | New feature |
| `fix` | 🐛 | Bug fix |
| `docs` | 📝 | Documentation |
| `style` | 💄 | Formatting/style |
| `refactor` | ♻️ | Refactoring |
| `perf` | ⚡️ | Performance |
| `test` | ✅ | Tests |
| `chore` | 🔧 | Tools/config |
| `ci` | 🚀 | CI/CD |
| `revert` | 🗑️ | Revert changes |

See `references/commit-emoji-guide.md` for comprehensive emoji list.

### Step 4: Execute Commits

For each concern, execute commit using HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
✨ feat: add user authentication system

Implement JWT-based authentication with refresh tokens.
Includes login, logout, and token refresh endpoints.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 5: Final Verification

```bash
# Verify all changes committed
git status

# Show recent commits
git log --oneline -n 5
```

## Commit Message Guidelines

### Best Practices
- **Present tense, imperative**: "add" not "added"
- **Concise first line**: Under 72 characters
- **Explain why, not what**: Describe reasoning
- **Atomic commits**: One logical change per commit

### Examples

```
✨ feat: add user authentication system
🐛 fix: resolve memory leak in rendering process
📝 docs: update API documentation with new endpoints
♻️ refactor: simplify error handling logic in parser
🚨 fix: resolve linter warnings in component files
🧑‍💻 chore: improve developer tooling setup process
👔 feat: implement business logic for transaction validation
🩹 fix: address minor styling inconsistency in header
🚑️ fix: patch critical security vulnerability in auth flow
🎨 style: reorganize component structure for better readability
🔥 fix: remove deprecated legacy code
🦺 feat: add input validation for user registration form
💚 fix: resolve failing CI pipeline tests
📈 feat: implement analytics tracking for user engagement
🔒️ fix: strengthen authentication password requirements
♿️ feat: improve form accessibility for screen readers
```

## Automatic Commit Splitting

When changes contain multiple concerns, automatically split and commit separately:

### Example Scenario
```
Changes detected:
- src/auth.js (new feature)
- docs/API.md (documentation)
- package.json (dependencies)
- test/auth.test.js (tests)

Automatic splitting:
1st commit: ✨ feat: add authentication endpoints to API
2nd commit: 📝 docs: document new authentication endpoints
3rd commit: 🔧 chore: update authentication library dependencies
4th commit: ✅ test: add unit tests for authentication features
```

## Prohibited Actions

❌ Asking user for commit approval (always commit immediately)
❌ Proposing commit splits (just do it automatically)
❌ Waiting for confirmation
❌ Creating work-in-progress commits
❌ Committing secrets or sensitive files

## Quality Assurance

Before committing:
- [ ] Review `git diff --staged` to understand changes
- [ ] Ensure each commit is logically atomic
- [ ] Verify commit messages accurately reflect changes
- [ ] Check for any accidentally staged files

Warn user if detecting:
- `.env` files
- `credentials.json`
- Private keys
- Other potential secrets

## Required Compliance

Refer to `references/must-rules.md` for:
- Commit discipline standards
- Quality assurance requirements
- When commits should be created

## Resources

### references/commit-emoji-guide.md
Comprehensive emoji guide including:
- Complete type → emoji mapping
- Situational emoji selection
- Context-specific emoji usage
- Examples for each emoji
- Edge case handling

### ../../shared/references/must-rules.md
Commit discipline requirements:
- When to commit (tests passing, no warnings)
- Commit message format requirements
- Atomic commit principles
- Prohibited practices

Refer to these files for detailed commit creation guidance.

---

**Remember: Analyze changes, group by concern, create appropriate messages, and commit immediately. Multiple concerns = multiple commits.**
