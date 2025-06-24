# Review

Comprehensive code review for GitHub PRs with automated worktree management and deep analysis.

## Usage
```
/review <GitHub PR URL>                    # Review PR from URL
/review <branch-name>                      # Review branch directly
/review <GitHub PR URL> <branch-name>      # Review specific branch from PR context
```

## Description
This command performs a comprehensive code review of GitHub Pull Requests or branches by automatically creating a git worktree, analyzing changes, and conducting systematic quality evaluation across multiple dimensions.

## What it does
1. **Input Analysis & Setup**: 
   - Analyzes input to determine if it's a GitHub PR URL, branch name, or both
   - Runs `git fetch` to update remote branch information
   - For PR URLs: extracts repository and PR number using `gh pr view`
   - For branch names: uses the specified branch directly

2. **Target Branch Determination**:
   - Attempts to determine merge target branch using `gh pr view --json baseRefName`
   - If GitHub CLI fails or branch name is provided directly, prompts user to specify target branch
   - Shows available remote branches (`git branch -r`) with common defaults (main, master, develop)

3. **Worktree Creation & Setup**:
   - Creates isolated worktree directly from specified branch: `git worktree add .git/worktrees/{name} origin/{branch}`
   - Changes directory to the worktree (branch is already checked out)
   - All subsequent operations performed within the worktree environment

4. **Phase 0: Context Collection & Consistency Check** (REQUIRED - Cannot proceed without this step)
   - **User Context Collection (MUST)**: MUST ask user for relevant documentation and context before proceeding:
     - Design documents, architectural decisions
     - API specifications, interface contracts
     - Coding guidelines, style guides
     - Related tickets, issues, or discussions
     - Any other context that would help understand the changes
     - If user provides no context, still MUST acknowledge and document this explicitly
   - **Existing Implementation Analysis**: Automatically searches for similar functionality in codebase (3-5 files)
     - Naming convention consistency
     - Architecture pattern alignment
     - Library/framework usage consistency
     - Error handling pattern uniformity
     - Logging approach alignment

5. **Diff Analysis**: Reviews complete diff against target merge branch (using fetched latest state, performed within worktree)

6. **Systematic Review Execution** (all performed within worktree):

### Phase 1: Code Quality Review
- **Readability**: Naming conventions, comments, complexity analysis
- **Maintainability**: DRY principles, modularity, dependency management
- **Performance**: Algorithm efficiency, memory usage, bottleneck identification

### Phase 2: Design & Architecture Review
- **SOLID Principles**: Single responsibility, open-closed, dependency inversion compliance
- **Design Patterns**: Appropriate pattern usage, avoiding over-abstraction
- **API Design**: Interface consistency, backward compatibility

### Phase 3: Security Review
- **Input Validation**: SQL injection, XSS prevention
- **Authentication & Authorization**: Permission checks, session management
- **Data Protection**: Encryption, sensitive information exposure prevention

### Phase 4: Test Review
- **Test Coverage**: Unit, integration, E2E test analysis
- **Edge Cases**: Boundary values, error scenarios, exception handling
- **Test Quality**: Independence, readability, maintainability

### Phase 5: Operations Review
- **Logging**: Appropriate levels, debug information
- **Monitoring**: Metrics, alerts, health checks
- **Deployment**: Configuration management, rollback strategies

### Phase 6: Documentation Review
- **Code Comments**: Intent explanation, complex logic documentation
- **API Documentation**: Endpoints, parameters, responses
- **Change Documentation**: Breaking changes, migration procedures

7. **Comprehensive Evaluation**: 
   - Consolidates results from all phases
   - Provides prioritized improvement recommendations
   - Evaluates consistency with existing implementation patterns

8. **Cleanup**: Optional worktree removal after review completion

## Review Framework

### Consistency Analysis (Phase 0)
When user context is limited, the command automatically:
- Searches for similar implementations using glob/grep patterns
- Analyzes existing code patterns for:
  - Variable, function, class naming conventions
  - Architectural approaches (MVC, layered architecture, etc.)
  - Technology stack alignment
  - Error handling mechanisms
  - Logging formats and levels

### Quality Dimensions
Each phase evaluates specific aspects:
- **Code Quality**: Focuses on immediate code health
- **Architecture**: Evaluates long-term design decisions
- **Security**: Identifies potential vulnerabilities
- **Testing**: Assesses test completeness and quality
- **Operations**: Reviews production readiness
- **Documentation**: Ensures knowledge transfer

### Evaluation Criteria
- **Critical**: Issues that must be addressed before merge
- **Important**: Significant improvements that should be addressed
- **Suggestion**: Nice-to-have improvements for future consideration
- **Compliant**: Aspects that meet or exceed standards

## Best Practices Applied

### Automated Context Discovery
- Identifies similar functionality automatically
- Learns from existing codebase patterns
- Reduces reviewer burden for context gathering

### Systematic Coverage
- No aspect overlooked through structured phases
- Consistent evaluation criteria across reviews
- Comprehensive reporting format

### Non-Intrusive Environment
- Isolated worktree prevents main branch contamination
- Safe exploration of PR changes
- Easy cleanup after review

## Prerequisites
- GitHub CLI (`gh`) installed and authenticated (for PR URL functionality)
- Git repository with remote configured
- Sufficient permissions to fetch branches
- Target branches must exist on remote origin

## Example Workflows

### PR URL Review
1. User runs: `/review https://github.com/owner/repo/pull/123`
2. Command fetches remote info and extracts PR branch
3. Attempts to get target branch via `gh pr view --json baseRefName`
4. Creates worktree at `.git/worktrees/pr-123` directly from PR branch
5. Changes to worktree directory
6. Prompts for documentation references
7. Analyzes existing similar implementations
8. Reviews diff against target branch within worktree
9. Executes 6-phase systematic review
10. Provides comprehensive evaluation report
11. Optionally cleans up worktree

### Branch Name Review
1. User runs: `/review feature/new-auth`
2. Command fetches remote info
3. Prompts user to specify target branch (shows available options)
4. Creates worktree at `.git/worktrees/feature-new-auth` directly from specified branch
5. Changes to worktree directory
6. Continues with review process within worktree

### Combined Review
1. User runs: `/review https://github.com/owner/repo/pull/123 feature/alternative-impl`
2. Uses PR context but reviews the specified branch instead
3. Follows similar workflow within dedicated worktree

## Output Format
- **Executive Summary**: High-level findings and recommendations
- **Phase-by-Phase Results**: Detailed analysis for each review dimension
- **Consistency Analysis**: Alignment with existing codebase patterns
- **Prioritized Action Items**: Critical → Important → Suggestions
- **Code Examples**: Specific recommendations with before/after samples

This command ensures thorough, consistent, and context-aware code reviews that maintain codebase quality and consistency standards.