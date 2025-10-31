---
name: development
description: Implement new features and fix bugs following Test-Driven Development (TDD) methodology. This skill should be used when implementing new functionality, fixing bugs, or extending existing features. Strictly follows RED→GREEN→REFACTOR cycle with test-first approach.
---

# Development (TDD)

## Overview

Implement all production code using Kent Beck's Test-Driven Development methodology. Write failing tests first, implement minimal code to pass tests, then refactor for quality. Never write production code without a failing test.

## When to Use This Skill

Use this skill when:
- Implementing new features or functionality
- Fixing bugs in existing code
- Extending or modifying existing features
- Any production code changes requiring behavioral modifications

## TDD Absolute Rules

1. **No code without tests** - No exceptions
2. **Follow RED→GREEN→REFACTOR cycle** - Strictly enforced
3. **Minimal implementation** - Only write code to pass current test
4. **Refactor only when green** - Tests must pass before refactoring

## Core Workflow

### Step 1: Work Planning (Using TodoWrite)

Create a structured task list before starting:

```bash
# Example: User authentication feature
- [ ] Write test for authentication failure
- [ ] Minimal implementation to pass test
- [ ] Write test for authentication success
- [ ] Extend implementation
- [ ] Refactor (delegate to tidy-first if needed)
```

### Step 2: RED Phase - Write Failing Test

**Requirements:**
- Clear, descriptive test name (e.g., `shouldReturnErrorWhenPasswordIsInvalid`)
- Test only one behavior at a time
- Verify test failure (RED)

**Example:**
```javascript
describe('UserAuthentication', () => {
  test('shouldReturnErrorWhenPasswordIsInvalid', () => {
    const auth = new UserAuthentication();
    const result = auth.login('user@example.com', 'wrong_password');
    expect(result.error).toBe('Invalid credentials');
  });
});
```

**Run test and confirm it fails:**
```bash
npm test  # or appropriate test command
# Test should FAIL - this is expected and required
```

### Step 3: GREEN Phase - Make Test Pass

**Requirements:**
- Write ONLY minimal code to pass the test
- Hard-coding is acceptable (will refactor later)
- Ensure all tests pass

**Example (minimal implementation):**
```javascript
class UserAuthentication {
  login(email, password) {
    // Minimal implementation - just make test pass
    return { error: 'Invalid credentials' };
  }
}
```

**Run tests again:**
```bash
npm test
# All tests should PASS - GREEN phase complete
```

### Step 4: REFACTOR Phase - Improve Quality

**Only proceed when all tests are green.**

For simple refactoring, proceed directly. For significant structural changes, delegate to tidy-first:

```bash
# Delegate complex refactoring to tidy-first skill
Task(
    subagent_type="tidy-first",
    prompt="Remove duplication in authentication logic and improve structure",
    description="Code cleanup"
)
```

**After refactoring:**
```bash
npm test
# All tests must still PASS
```

## Bug Fixing Process

### Step 1: Reproduce Bug with Test
Write a test that demonstrates the bug (test should FAIL):

```javascript
test('shouldHandleNullEmailGracefully', () => {
  const auth = new UserAuthentication();
  const result = auth.login(null, 'password');
  expect(result.error).toBe('Email is required');
});
```

### Step 2: Fix with Minimal Changes
Implement the smallest fix to make test pass:

```javascript
class UserAuthentication {
  login(email, password) {
    if (!email) {
      return { error: 'Email is required' };
    }
    // ... existing logic
  }
}
```

### Step 3: Add Edge Case Tests
Cover additional scenarios discovered during fix:

```javascript
test('shouldHandleEmptyEmailString', () => {
  const auth = new UserAuthentication();
  const result = auth.login('', 'password');
  expect(result.error).toBe('Email is required');
});
```

### Step 4: Refactor if Needed
Once all tests pass, improve code quality if necessary.

## Meaningful Test Guidelines

### What Tests Should Verify

**Test behavior (what code does), not initialization:**

❌ **Bad test** (only checks initialization):
```rust
#[test]
fn test_new() {
    let profiler = CpuProfiler::new();
    assert_eq!(profiler.frequency, 997);
}
```

✅ **Good test** (verifies actual behavior and output):
```rust
#[test]
fn test_profiler_captures_function_samples() {
    let profiler = CpuProfiler::new();

    // Test actual behavior
    let report = profiler.profile_workload(|| {
        fibonacci(30);
    }).unwrap();

    // Verify expected output
    assert!(report.contains_function("fibonacci"));
    assert!(report.sample_count() > 0);
}
```

### Test Design Principles

1. **Start with minimal meaningful behavior**
2. **Clear input → processing → output flow**
3. **Specific expected results**
4. **Clear failure reasons**

## Commit Guidelines

Use `[BEHAVIORAL]` prefix for feature additions and bug fixes:

```bash
# Good commit messages
[BEHAVIORAL] feat: add user authentication system
[BEHAVIORAL] fix: resolve null pointer error in login
[BEHAVIORAL] feat: implement password validation
```

## Quality Assurance (MANDATORY)

After implementation, ALWAYS run these commands:

```bash
# 1. Run linter
npm run lint     # or appropriate lint command
# Fix any errors before proceeding

# 2. Run formatter
npm run format   # or appropriate format command

# 3. Run build
npm run build    # or appropriate build command
# Fix any build errors

# 4. Run tests
npm test         # or appropriate test command
# All tests must pass
```

**IMPORTANT**: Task is not complete until all quality checks pass.

If commands are unknown, check package.json or README, or ask the user.

## Prohibited Actions

❌ Writing tests "later"
❌ Implementing before writing tests
❌ Refactoring when tests are RED
❌ Implementing multiple features simultaneously
❌ Committing without passing tests
❌ Writing meaningless tests that only check initialization

## Required Compliance

**Important**: Refer to `references/must-rules.md` for common rules:
- Background process management (use ghost)
- Uncertainty handling (no assumptions)
- Commit rules (tests must pass)
- Error handling
- Work progression (use TodoWrite)

## Collaboration Patterns

1. **Large features** → Split into small tasks and apply TDD
2. **Refactoring needed** → Delegate to tidy-first skill
3. **Unclear specifications** → Research or ask before starting TDD

## Resources

### references/tdd-guidelines.md
Detailed TDD guidelines including:
- Advanced test patterns
- Test organization strategies
- Common TDD anti-patterns
- Language-specific TDD examples
- Integration and E2E testing approaches

### ../../shared/references/must-rules.md
Common MUST rules shared across all skills:
- Background process management (ghost)
- Uncertainty handling
- Commit discipline
- Work cycle guidelines

Refer to these files for comprehensive guidance during development.

---

**Remember: All implementation must be test-driven. No exceptions. This is non-negotiable.**
