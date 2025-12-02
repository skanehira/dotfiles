---
name: skill-reviewer
description: Review Claude Code skills against official best practices. Use when reviewing SKILL.md files, checking skill quality, validating skill structure, or getting improvement suggestions. Triggers on requests like "review this skill", "check skill quality", "validate SKILL.md", or "improve this skill".
---

# Skill Reviewer

Review skills against Claude's official best practices and provide actionable improvement suggestions.

## Review Workflow

### Step 1: Identify Target Skill

Locate the SKILL.md file to review:
- User specifies path directly
- Search current directory for SKILL.md
- Ask user to specify if multiple skills exist

### Step 2: Read and Analyze

1. Read the target SKILL.md file completely
2. Read [best-practices.md](references/best-practices.md) for checklist
3. Parse YAML frontmatter (name, description)
4. Analyze body content structure

### Step 3: Check Against Best Practices

Evaluate each category:

**Frontmatter Checks**
- name: length, format, naming convention
- description: completeness, specificity, triggers

**Body Checks**
- Line count (target: <500 lines)
- Structure clarity
- Progressive disclosure usage
- Workflow design quality

**Content Checks**
- Terminology consistency
- Example quality
- Template appropriateness

**Anti-Pattern Detection**
- Multiple options without defaults
- Windows-style paths
- Time-sensitive information
- Magic constants

### Step 4: Generate Review Report

Output format (in Japanese):

```markdown
# Skill Review Report: {skill-name}

## Summary
- Overall: {PASS | NEEDS_IMPROVEMENT | CRITICAL_ISSUES}
- Critical: {count}
- Warning: {count}
- Info: {count}

## Critical Issues
{List critical issues that must be fixed}

## Warnings
{List recommended improvements}

## Suggestions
{List optional enhancements}

## Specific Recommendations
{Concrete action items with examples}
```

### Step 5: Interactive Improvement

After presenting the report:
1. Ask if user wants to fix issues
2. Prioritize critical issues first
3. Apply fixes incrementally
4. Re-validate after each fix

## Severity Classification

### Critical
Issues that prevent proper skill functioning:
- Empty or missing description
- Body exceeds 500 lines significantly
- Security vulnerabilities in scripts
- Missing error handling in scripts

### Warning
Issues that reduce skill effectiveness:
- Progressive disclosure not applied
- Insufficient examples
- Inconsistent terminology
- Unclear workflows

### Info
Opportunities for improvement:
- Can be more concise
- Structure optimization
- Additional examples beneficial

## Example Review Session

User: "Review my pdf-processor skill"

```
1. Read: skills/pdf-processor/SKILL.md
2. Load: references/best-practices.md
3. Analyze against checklist
4. Generate report in Japanese
5. Offer to fix issues
```

## Output Language

All review reports are generated in Japanese for clarity.
