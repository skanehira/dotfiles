# Claude Code Skills

This directory contains custom skills that extend Claude Code's capabilities for specific development workflows.

## Overview

Skills are specialized, self-contained modules that provide Claude with procedural knowledge for specific domains or tasks. These skills follow the workflow-based design, guiding Claude through different phases of the development lifecycle.

## Available Skills

### 1. requirements-analysis
**Phase**: Planning & Requirements
**Use when**: User requirements are ambiguous, large-scale features need planning, or detailed task decomposition is required.

Transforms vague requests into concrete, actionable implementation plans following MUST rules (TDD, Tidy First, etc.). Generates TODO.md and DESIGN.md files.

**Key Features**:
- Requirements clarification and analysis
- Technical feasibility verification
- Task decomposition with dependency management
- MUST rules compliance verification
- TODO.md and DESIGN.md generation

### 2. development
**Phase**: Implementation
**Use when**: Implementing new features, fixing bugs, or extending existing functionality.

Strictly follows Test-Driven Development (TDD) with RED→GREEN→REFACTOR cycle. Never writes production code without a failing test first.

**Key Features**:
- Kent Beck's TDD methodology enforcement
- RED→GREEN→REFACTOR cycle management
- Bug fixing process with test-first approach
- Quality assurance (lint, format, build, test)
- [BEHAVIORAL] commit creation

### 3. refactoring
**Phase**: Code Improvement
**Use when**: Code cleanup, removing duplication, improving readability, or reorganizing structure is needed.

Performs structural improvements without changing behavior, following Tidy First principles. All tests must remain green throughout.

**Key Features**:
- Structural-only improvements (no behavior changes)
- Refactoring pattern catalog (Extract Method, Rename, etc.)
- Tests-always-green validation
- [STRUCTURAL] commit creation
- Code smell detection

### 4. review
**Phase**: Quality Assurance
**Use when**: Reviewing GitHub PRs, analyzing local code, checking security, or evaluating architectural decisions.

Conducts comprehensive, systematic code reviews across six dimensions. Supports both GitHub PR reviews (with worktree management) and local file analysis.

**Key Features**:
- GitHub PR review with automatic worktree management
- Local code review
- Six-phase systematic evaluation (Quality, Design, Security, Testing, Operations, Documentation)
- Consistency analysis with existing codebase
- review_result.md generation in Japanese

### 5. commit
**Phase**: Version Control
**Use when**: Changes are ready to be committed.

Analyzes changes, automatically groups by concern, generates Conventional Commit format messages with emoji, and executes commits immediately.

**Key Features**:
- Automatic change analysis and grouping
- Conventional Commit format + emoji
- Multiple concerns = multiple commits (automatic splitting)
- Immediate execution (no user confirmation needed)
- Comprehensive emoji guide for situational selection

## Workflow Integration

These skills are designed to work together through the complete development lifecycle:

```
User Request
     ↓
[requirements-analysis] → Generate TODO.md/DESIGN.md
     ↓
[development] → Implement with TDD (RED→GREEN→REFACTOR)
     ↓
[refactoring] → Clean up code structure (optional)
     ↓
[review] → Comprehensive quality check
     ↓
[commit] → Create properly formatted commits
```

## Usage

Skills are automatically available after running `./install.sh`. Claude Code will suggest appropriate skills based on the task at hand.

### Direct Invocation Examples

```bash
# Requirements analysis for a new feature
"I want to build a user authentication system"
→ Triggers: requirements-analysis skill

# Feature implementation
"Implement the login endpoint"
→ Triggers: development skill (TDD)

# Code cleanup
"Refactor the authentication module to remove duplication"
→ Triggers: refactoring skill

# Code review
"Review this PR: https://github.com/owner/repo/pull/123"
→ Triggers: review skill

# Create commits
"Commit these changes"
→ Triggers: commit skill
```

## Relationship with Existing Commands/Agents

### Skills vs Commands
- **Commands** (`commands/`): Single-purpose, specific operations (e.g., `/search`)
- **Skills**: Comprehensive, workflow-oriented procedures with bundled resources

### Skills vs Agents
- **Agents** (`agents/`): Sub-agent delegation system for Task tool
- **Skills**: Standalone procedural knowledge modules

### Migration Strategy

This is a **gradual migration**. Existing `commands/` and `agents/` are preserved for compatibility:

**Migrated to Skills**:
- `agents/analyzer.md` → requirements-analysis skill
- `agents/tdd-enforcer.md` → development skill
- `agents/tidy-first.md` → refactoring skill
- `commands/review.md` + `agents/review.md` → review skill
- `agents/committer.md` → commit skill

**Remaining as Commands** (unchanged):
- `commands/search.md` - Single-purpose Gemini search
- `commands/must.md` - MUST rules reminder

**Remaining as Agents** (unchanged):
- `agents/developer.md` - General-purpose development agent
- `agents/base-rules.md` - Common rules reference

## Skill Structure

Each skill follows the standard structure:

```
skill-name/
├── SKILL.md              # Main skill definition with frontmatter
├── scripts/              # Executable automation scripts (optional)
├── references/           # Skill-specific detailed documentation
│   └── specific-guide.md # Skill-specific detailed guides
└── assets/               # Files for output (optional)
```

### Shared Resources

Common resources used by multiple skills are stored in `shared/`:

```
shared/
└── references/
    └── must-rules.md     # Common MUST rules referenced by all skills
```

Skills reference shared resources using relative paths: `../../shared/references/must-rules.md`

This approach follows the DRY principle - updates to MUST rules only need to be made in one place, ensuring consistency across all skills.

### Progressive Disclosure

Skills use a three-level loading system:

1. **Metadata** (name + description) - Always in context (~100 words)
2. **SKILL.md body** - When skill triggers (<5k words)
3. **Bundled resources** - As needed by Claude (scripts can execute without loading)

## Benefits

1. **Workflow-Aligned**: Organized by development phase, not tool type
2. **MUST Rules Integration**: Common rules embedded in each skill
3. **Reusability**: Each skill is independent and can be used standalone
4. **Backward Compatible**: Existing commands/agents remain functional
5. **Progressive Enhancement**: Gradual adoption with no breaking changes

## Installation

Skills are automatically installed via the main install script:

```bash
cd claude
./install.sh
```

This creates a symlink from `~/.claude/skills` to `$PWD/skills`.

## Validation

Each skill has been validated using the skill-creator tool:

```bash
# Validate a specific skill
~/.claude/plugins/marketplaces/anthropic-agent-skills/skill-creator/scripts/quick_validate.py skills/skill-name

# All skills in this directory have passed validation ✓
```

## Contributing

When adding new skills:

1. Use the skill-creator tool: `skill-creator/scripts/init_skill.py <name> --path skills/`
2. Follow the workflow-based design pattern
3. Include MUST rules in `references/must-rules.md`
4. Validate before committing
5. Update this README

## References

- [Anthropic Skill Creator](https://github.com/anthropics/anthropic-agent-skills/tree/main/skill-creator)
- [MUST Rules](../CLAUDE.md) - Global development rules
- [Existing Commands](../commands/) - Single-purpose commands
- [Existing Agents](../agents/) - Sub-agent system

---

**Last Updated**: 2025-10-31
**Skills Count**: 5 (requirements-analysis, development, refactoring, review, commit)
