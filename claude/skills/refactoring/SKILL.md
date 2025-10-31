---
name: refactoring
description: Perform structural improvements without changing behavior. This skill should be used when code cleanup, removing duplication, improving readability, or reorganizing structure is needed. Strictly follows Tidy First principles with [STRUCTURAL] commits only.
---

# Refactoring (Tidy First)

## Overview

Specialize in code cleanup and refactoring. Improve code structure and quality WITHOUT changing any behavior. Focus on making code more readable, maintainable, and well-organized while ensuring all tests remain green.

## When to Use This Skill

Use this skill when:
- Code cleanup and organization needed
- Duplication removal required
- Readability improvements desired
- Structural reorganization necessary
- Code smells need addressing
- Preparing codebase before behavioral changes

## Tidy First Principles

1. **No behavior changes** - Only improve structure
2. **Tests always green** - Verify before and after changes
3. **Small incremental improvements** - Don't change too much at once
4. **Clear intent** - Understand why each improvement matters

## What Qualifies as Structural Work

### 1. Naming Improvements
```javascript
// Before
const d = new Date();
const u = users.filter(x => x.a > 18);

// After
const currentDate = new Date();
const adultUsers = users.filter(user => user.age > 18);
```

### 2. Duplication Removal
```javascript
// Before
function calculateTax(amount) {
  return amount * 0.1;
}
function calculateFee(amount) {
  return amount * 0.1;
}

// After
const TAX_RATE = 0.1;
function calculatePercentage(amount, rate) {
  return amount * rate;
}
```

### 3. Method/Class Extraction
- Split long functions into smaller ones
- Group related functionality into classes
- Separate responsibilities

### 4. File Reorganization
- Move code to more appropriate modules
- Co-locate related code
- Improve project structure

### 5. Format Corrections
- Consistent indentation
- Appropriate whitespace
- Coding standards compliance

## Core Workflow

### Step 1: Current State Verification
```bash
# Run tests to ensure all pass
npm test
```

**REQUIREMENT**: All tests must be green before starting.

### Step 2: Refactoring Plan
```bash
TodoWrite:
- [ ] Verify current test state
- [ ] Identify refactoring targets
- [ ] Break into small change units
- [ ] Run tests after each change
```

### Step 3: Incremental Improvements
- Focus on one type of improvement at a time
- Run tests after each step
- Commit frequently

### Step 4: Validation
```bash
# Verify all tests still pass
npm test

# Review diff to ensure only structural changes
git diff
```

## Refactoring Patterns

### Extract Method
**When**: Function longer than 20 lines or doing multiple things

```javascript
// Before
function processOrder(order) {
  // Validate
  if (!order.items || order.items.length === 0) {
    throw new Error('No items');
  }
  // Calculate
  let total = 0;
  for (const item of order.items) {
    total += item.price * item.quantity;
  }
  // Apply discount
  if (total > 100) {
    total *= 0.9;
  }
  return total;
}

// After
function processOrder(order) {
  validateOrder(order);
  const subtotal = calculateSubtotal(order.items);
  return applyDiscount(subtotal);
}

function validateOrder(order) {
  if (!order.items || order.items.length === 0) {
    throw new Error('No items');
  }
}

function calculateSubtotal(items) {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}

function applyDiscount(amount) {
  return amount > 100 ? amount * 0.9 : amount;
}
```

### Rename for Clarity
**When**: Names are ambiguous or misleading

```javascript
// Before
function proc(d) {
  const x = d.filter(i => i.s === 'a');
  return x.map(i => i.v);
}

// After
function getActiveValues(data) {
  const activeItems = data.filter(item => item.status === 'active');
  return activeItems.map(item => item.value);
}
```

### Extract Class
**When**: Class has multiple responsibilities

```python
# Before
class User:
    def __init__(self, email, password):
        self.email = email
        self.password = password

    def save_to_database(self):
        # Database logic
        pass

    def send_welcome_email(self):
        # Email logic
        pass

# After
class User:
    def __init__(self, email, password):
        self.email = email
        self.password = password

class UserRepository:
    def save(self, user):
        # Database logic
        pass

class UserNotifier:
    def send_welcome_email(self, user):
        # Email logic
        pass
```

### Remove Duplication
**When**: Same pattern appears 3+ times

```javascript
// Before
const userAge = calculateAge(user.birthDate);
const managerAge = calculateAge(manager.birthDate);
const adminAge = calculateAge(admin.birthDate);

function calculateAge(birthDate) {
  return new Date().getFullYear() - birthDate.getFullYear();
}

// After
function calculateAge(person) {
  return new Date().getFullYear() - person.birthDate.getFullYear();
}

const userAge = calculateAge(user);
const managerAge = calculateAge(manager);
const adminAge = calculateAge(admin);
```

### Move Method
**When**: Method belongs in different class

```javascript
// Before
class Order {
  calculateShipping() {
    return this.customer.country === 'US' ? 5 : 10;
  }
}

// After
class Customer {
  getShippingCost() {
    return this.country === 'US' ? 5 : 10;
  }
}

class Order {
  calculateShipping() {
    return this.customer.getShippingCost();
  }
}
```

## Commit Guidelines

**ALWAYS use `[STRUCTURAL]` prefix:**

```bash
git commit -m "[STRUCTURAL] refactor: clarify authentication function names"
git commit -m "[STRUCTURAL] refactor: extract authentication logic into UserService class"
git commit -m "[STRUCTURAL] style: apply ESLint formatting rules"
```

## Quality Assurance

### Pre-Refactoring Checklist
- [ ] All tests passing
- [ ] No pending changes (clean working directory)
- [ ] Clear refactoring goal identified

### During Refactoring
- [ ] Small, incremental changes
- [ ] Tests run after each change
- [ ] Tests remain green throughout

### Post-Refactoring Verification
```bash
# Final verification
git diff --stat  # Review changed files
git diff         # Ensure only structural changes
npm test         # All tests must still pass
```

## Prohibited Actions

❌ Adding new features
❌ Fixing bugs (that's development skill's job)
❌ Changing behavior
❌ Adding/modifying tests (structural improvements only)
❌ Changing externally visible behavior
❌ Committing without user permission

## When to Refactor

Consider refactoring when:
- **Intent unclear**: Code purpose not obvious
- **Rule of three**: Same pattern 3+ times
- **Long functions**: Functions over 20 lines
- **Multiple responsibilities**: Class doing too much
- **Ambiguous names**: Names don't convey meaning

## Refactoring Decision Tree

```
Need to change behavior? → NO → Refactoring (this skill)
                        → YES → Development skill (TDD)

Tests passing? → NO → Fix tests first (development skill)
             → YES → Safe to refactor

Large change needed? → Split into small steps
                    → Refactor incrementally
```

## Required Compliance

**Important**: Refer to `references/must-rules.md` for common rules:
- Background process management (use ghost)
- Uncertainty handling (no assumptions)
- Commit rules ([STRUCTURAL] prefix, tests must pass)
- Error handling
- Work progression (use TodoWrite)

### Refactoring-Specific QA
```bash
# Final checks
git diff --stat  # Review file changes
git diff         # Verify only structural changes
npm test         # All tests must pass
```

## Resources

### references/refactoring-patterns.md
Detailed refactoring patterns including:
- Comprehensive pattern catalog
- Before/after examples for each pattern
- Anti-patterns to avoid
- Language-specific refactoring techniques
- Code smell detection guide

### ../../shared/references/must-rules.md
Common MUST rules shared across all skills:
- Background process management (ghost)
- Uncertainty handling
- Commit discipline
- Work cycle guidelines

Refer to these files for comprehensive refactoring guidance.

---

**Remember: Structural beauty improves code understandability and maintainability. Never change behavior during refactoring.**
