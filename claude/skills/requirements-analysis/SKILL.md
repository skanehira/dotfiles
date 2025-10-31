---
name: requirements-analysis
description: Analyze user requirements and break them down into implementable tasks. This skill should be used when user requests are ambiguous, large-scale feature development is needed, or detailed task decomposition is required. Generate TODO.md and DESIGN.md files following MUST rules.
---

# Requirements Analysis

## Overview

Transform vague user requests into concrete, actionable implementation plans. Deeply understand requirements, verify technical feasibility, structure tasks with dependency consideration, and generate detailed TODO lists that developers can follow without confusion.

## When to Use This Skill

Use this skill when:
- User requirements are ambiguous or unclear
- Large-scale feature development requires planning
- Complex tasks need decomposition into smaller steps
- Implementation plan needs to be established
- TODO.md and DESIGN.md documentation is needed

## Core Workflow

### Step 0: MUST Rules Verification (REQUIRED)

Before starting any analysis, verify all MUST rules from `references/must-rules.md`:
- Test-Driven Development (TDD) is MANDATORY
- Tidy First Approach is MANDATORY
- Handling Uncertainties is MANDATORY
- Background Process Management is MANDATORY
- Documentation Search is MANDATORY
- Commit Discipline is MANDATORY

All task decomposition must comply with these rules.

### Step 1: Understanding and Analyzing Requirements

Analyze user requests from multiple dimensions:

**What to Build (What)**
- Core functionality identification
- Feature scope definition
- User interface requirements

**Purpose and Value (Why)**
- Business value analysis
- Problem being solved
- Success metrics

**Usage Patterns (How)**
- User interaction flows
- Integration points
- Performance requirements

**Timeline (When)**
- Delivery expectations
- Milestone planning
- Dependency timing

**Target Users (Who)**
- User personas
- Access patterns
- Skill level considerations

### Step 2: Resolving Uncertainties

**MANDATORY: Never make assumptions**

Use available tools to investigate existing implementations:
```bash
# Search for related implementations
Grep(pattern="relevant-keyword")
Read(file_path="related-file")
Glob(pattern="**/*.{js,ts,py}")
```

When information is missing, explicitly list unknowns:
```
「以下の点について確認が必要です:
- Point 1: Regarding ○○
- Point 2: Specification of △△
- Point 3: Constraint of □□」
```

### Step 3: Requirements Definition Creation

Structure requirements clearly:

#### Functional Requirements
- Required features (MUST have)
- Optional features (NICE to have)
- Future extensibility considerations

#### Non-Functional Requirements
- Performance targets
- Security requirements
- Maintainability standards
- Scalability needs

#### Constraints
- Technical constraints (language, framework, dependencies)
- Time constraints (deadlines, milestones)
- Resource constraints (team size, infrastructure)

### Step 4: Task Decomposition (MUST Rules Compliant)

Break down work into phases following TDD and Tidy First principles:

**Phase 1: Foundation**
- Project structure design
- Package selection
- Basic setup

**Phase 2: Core Implementation (TDD Compliant)**
Each feature follows RED→GREEN→REFACTOR cycle:
```markdown
- [ ] [RED] Write failing test for feature X
- [ ] [GREEN] Minimal implementation to pass test
- [ ] [GREEN] Adjust implementation until tests pass
- [ ] [REFACTOR] Eliminate duplication, improve code quality
- [ ] [RED] Write failing test for next feature
- [ ] [GREEN] Minimal implementation
- [ ] [GREEN] Pass all tests
- [ ] [REFACTOR] Code improvement
```

**Phase 3: Quality Enhancement (Tidy First Compliant)**
```markdown
- [ ] [STRUCTURAL] Code cleanup and refactoring (no behavior change)
- [ ] [BEHAVIORAL] Error handling tests and implementation
- [ ] Performance testing
```

### Step 5: TODO List Generation

Use TodoWrite to create structured task list:
```javascript
TodoWrite({
  todos: [
    {
      id: "1",
      content: "Project structure design and initial setup",
      status: "pending"
    },
    {
      id: "2",
      content: "[RED] Write behavior test for user authentication",
      status: "pending"
    },
    {
      id: "3",
      content: "[GREEN] Minimal implementation to pass auth test",
      status: "pending"
    },
    {
      id: "4",
      content: "[GREEN] Adjust implementation until auth tests pass",
      status: "pending"
    },
    {
      id: "5",
      content: "[REFACTOR] Improve auth code quality",
      status: "pending"
    },
    {
      id: "6",
      content: "[STRUCTURAL] Code cleanup (no behavior change)",
      status: "pending"
    }
    // Continue with detailed TDD cycle tasks
  ]
})
```

### Step 6: Documentation Output

Generate two key documents:

#### docs/TODO.md
```markdown
# TODO: [Project Name]

Generated: [Date]
Generator: requirements-analysis

## Overview
[Project overview and objectives]

## Implementation Tasks (MUST Rules Compliant)

### Phase 1: Foundation
- [ ] Project structure design and initial setup
- [ ] Development environment setup (ghost for background processes)

### Phase 2: TDD-Compliant Core Implementation
- [ ] [RED] Write behavior test for Feature A
- [ ] [GREEN] Minimal implementation to pass test
- [ ] [GREEN] Adjust until tests pass
- [ ] [REFACTOR] Eliminate duplication and improve quality
- [ ] [RED] Write behavior test for Feature B
- [ ] [GREEN] Minimal implementation
- [ ] [GREEN] Pass all tests
- [ ] [REFACTOR] Code quality improvement

### Phase 3: Quality Enhancement (Tidy First Compliant)
- [ ] [STRUCTURAL] Code cleanup and refactoring (no behavior change)
- [ ] [BEHAVIORAL] Error handling tests and implementation
- [ ] Run all tests and verify quality

## Implementation Notes (MUST Rules Compliant)
- TDD: Always test-first (RED → GREEN → REFACTOR)
- Tidy First: Separate structural and behavioral changes in commits
- Background Process: Use ghost (禁止: &, nohup, etc.)
- Uncertainties: Ask and investigate, never assume
- Commits: [STRUCTURAL] or [BEHAVIORAL] prefix required

## References
- Design Document: docs/DESIGN.md
- Related Documentation: [Links]
```

#### docs/DESIGN.md
```markdown
# [Project Name] Design Document

Generated: [Date]
Generator: requirements-analysis

## System Overview
[System purpose and overall picture]

## Architecture Design
[System configuration and technology choices]

## Detailed Design
[Component design, API design, etc.]

## Data Design
[Data model, data flow]

## Security Design
[Security requirements and countermeasures]

## Performance Design
[Performance requirements and optimization policy]
```

### Step 7: File Output

Write documentation files:
```javascript
// Output TODO.md to docs directory
Write(
    file_path="docs/TODO.md",
    content=todoContent
)

// Output DESIGN.md to docs directory
Write(
    file_path="docs/DESIGN.md",
    content=designContent
)
```

## Task Decomposition Principles

### SMART Principles
- **Specific**: Clear and concrete
- **Measurable**: Clear completion criteria
- **Achievable**: Realistically achievable
- **Relevant**: Related to objectives
- **Time-bound**: Time-estimable

### Dependency Clarification
```
Task A → Task B → Task C
         ↗
Task D ↗
```

### Task Sizing
- 1 task = 1-4 hours completable
- If too large, split into subtasks
- If too small, consolidate

## Quality Checklist

Before completing analysis:
- [ ] All requirements reflected in specifications
- [ ] Technical feasibility verified
- [ ] Task dependencies are clear
- [ ] Each task has clear completion criteria
- [ ] Priorities appropriately set
- [ ] All MUST rules compliance verified
- [ ] TODO.md and DESIGN.md generated

## Resources

### ../../shared/references/must-rules.md
Detailed MUST rules extracted from CLAUDE.md, including:
- TDD methodology details
- Tidy First principles
- Uncertainty handling guidelines
- Background process management
- Documentation search procedures
- Commit discipline standards

Refer to this file for comprehensive rule details during analysis.
