---
name: review
description: Perform comprehensive code reviews for GitHub PRs or local code changes. This skill should be used when reviewing pull requests, analyzing code quality, checking security, or evaluating architectural decisions. Supports both PR reviews (with worktree management) and local file reviews. Outputs review_result.md in Japanese.
---

# Code Review

## Overview

Conduct systematic, comprehensive code reviews following industry best practices. Support both GitHub PR reviews (with automatic worktree management) and local code analysis. Evaluate code across six dimensions: quality, design, security, testing, operations, and documentation.

## When to Use This Skill

Use this skill when:
- Reviewing GitHub Pull Requests
- Analyzing local code changes or specific files
- Evaluating code quality before merge
- Checking for security vulnerabilities
- Assessing architectural decisions
- Verifying coding standards compliance

## Review Type Decision Tree

```
User provides GitHub PR URL? → YES → GitHub PR Review (with worktree)
                             → NO  → Local Code Review

GitHub PR Review:
├─ Extract PR info via `gh pr view`
├─ Create isolated worktree
├─ Change to worktree directory
├─ Perform 6-phase review
├─ Generate review_result.md
└─ Optional: cleanup worktree

Local Code Review:
├─ Identify scope (files/directories/git diff)
├─ Read target files
├─ Analyze git history if needed
├─ Perform relevant review phases
└─ Generate review_result.md
```

## Six-Phase Review Framework

### Phase 0: Context Collection (REQUIRED - Cannot proceed without this)

**1. User Context Collection (MUST):**
Ask user for relevant context BEFORE starting review:
- Design documents, architectural decisions
- API specifications, interface contracts
- Coding guidelines, style guides
- Related tickets, issues, or discussions
- Any other relevant context

If user provides no context, explicitly document this.

**2. Existing Implementation Analysis (Automatic):**
Search for similar functionality (3-5 files) to verify:
- Naming convention consistency
- Architecture pattern alignment
- Library/framework usage consistency
- Error handling pattern uniformity
- Logging approach alignment

### Phase 1: Code Quality Review
- Readability: naming conventions, comments, complexity
- Maintainability: DRY principles, modularity, dependency management
- Performance: algorithm efficiency, memory usage, bottleneck identification

### Phase 2: Design & Architecture Review
- SOLID Principles compliance (SRP, OCP, DIP)
- Design Patterns: appropriate usage, avoiding over-abstraction
- API Design: interface consistency, backward compatibility

### Phase 3: Security Review
- Input Validation: SQL injection, XSS prevention
- Authentication & Authorization: permission checks, session management
- Data Protection: encryption, sensitive information exposure prevention

### Phase 4: Test Review
- Test Coverage: unit, integration, E2E test analysis
- Edge Cases: boundary values, error scenarios, exception handling
- Test Quality: independence, readability, maintainability

### Phase 5: Operations Review
- Logging: appropriate levels, debug information
- Monitoring: metrics, alerts, health checks
- Deployment: configuration management, rollback strategies

### Phase 6: Documentation Review
- Code Comments: intent explanation, complex logic documentation
- API Documentation: endpoints, parameters, responses
- Change Documentation: breaking changes, migration procedures

## GitHub PR Review Workflow

### Step 1: Input Analysis & Fetch
```bash
# Fetch latest remote info
git fetch

# If PR URL provided, extract info
gh pr view <pr-number> --json baseRefName,headRefName
```

### Step 2: Target Branch Determination
- Try automatic detection: `gh pr view --json baseRefName`
- If fails, prompt user with available branches
- Show common defaults (main, master, develop)

### Step 3: Worktree Creation
Use `scripts/setup_worktree.sh` for automation:
```bash
scripts/setup_worktree.sh <branch-name> <pr-number-or-name>
```

Script automatically:
- Creates worktree at `.git/worktrees/<name>`
- Checks out specified branch
- Changes to worktree directory

### Step 4: Context Collection (Phase 0)
- MUST ask user for documentation/context
- Automatically search similar implementations
- Analyze consistency with existing patterns

### Step 5: Diff Analysis
```bash
# Within worktree: analyze full diff
git diff <target-branch>...HEAD
```

### Step 6: Execute Six-Phase Review
Systematically evaluate all six phases listed above

### Step 7: Generate Review Report
Create `review_result.md` in Japanese with comprehensive findings

### Step 8: Cleanup (Optional)
```bash
# Remove worktree after completion
git worktree remove .git/worktrees/<name>
```

## Local Code Review Workflow

### Step 1: Scope Identification
```bash
# Option 1: Specific files provided
Read(file_path="src/components/auth.js")

# Option 2: Directory provided
Glob(pattern="src/components/**/*.js")

# Option 3: No paths - use git diff
git diff
git status
```

### Step 2: Code Reading & Analysis
```bash
# Read target files
Read(file_path="...")

# Search for patterns
Grep(pattern="...", path="...")

# Analyze structure
Glob(pattern="...")
```

### Step 3: Git History Analysis (Optional)
```bash
git diff                           # Uncommitted changes
git log -p <file>                  # File history
git log --since="1 week ago"       # Recent changes
git blame <file>                   # Authorship
```

### Step 4: Execute Relevant Review Phases
Based on scope, execute appropriate phases from the six-phase framework

### Step 5: Generate Review Report
Create `review_result.md` in Japanese with findings

## Review Output Format

All reviews generate `review_result.md` in Japanese:

```markdown
# Code Review Report

**Date**: [Current Date]
**Scope**: [Files/Directories/PR Reviewed]
**Reviewer**: Claude Code

## 概要
[Executive summary in Japanese]

## 詳細な評価結果

### Phase 1: コード品質
[Code quality findings]

### Phase 2: 設計・アーキテクチャ
[Design & architecture findings]

### Phase 3: セキュリティ
[Security findings]

### Phase 4: テスト
[Test findings]

### Phase 5: 運用性
[Operations findings]

### Phase 6: ドキュメント
[Documentation findings]

## 一貫性分析
[Consistency analysis with existing codebase]

## 優先度別の推奨事項

### Critical(必須対応)
[Must-fix issues]

### Important(重要)
[Should-fix issues]

### Suggestion(提案)
[Nice-to-have improvements]

### Compliant(適合)
[Aspects that meet/exceed standards]

## コード例
[Specific examples with file:line references]
```

## Evaluation Criteria

- **Critical**: Issues that must be addressed before merge
- **Important**: Significant improvements that should be addressed
- **Suggestion**: Nice-to-have improvements for future consideration
- **Compliant**: Aspects that meet or exceed standards

## Prerequisites

### For GitHub PR Reviews
- GitHub CLI (`gh`) installed and authenticated
- Git repository with remote configured
- Sufficient permissions to fetch branches
- Target branches must exist on remote origin

### For Local Reviews
- Git repository (for history analysis)
- Read access to target files/directories

## Resources

### scripts/setup_worktree.sh
Automation script for PR worktree management:
- Creates isolated worktree from branch
- Handles naming conventions
- Auto-navigates to worktree directory
- Provides cleanup instructions

Usage:
```bash
./scripts/setup_worktree.sh <branch-name> <identifier>
```

### references/review-checklist.md
Comprehensive review checklists:
- Detailed criteria for each phase
- Common issues to look for by category
- Language-specific considerations
- Security vulnerability patterns
- Performance anti-patterns
- Best practices by domain

Refer to this file for detailed evaluation criteria during reviews.

---

**Remember: Thorough, context-aware reviews maintain codebase quality and prevent technical debt.**
