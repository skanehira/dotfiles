# TDD Guidelines Reference

This document provides detailed guidance on Test-Driven Development practices, patterns, and anti-patterns.

## Advanced Test Patterns

### Test Organization Strategies

#### 1. Arrange-Act-Assert (AAA) Pattern
```javascript
test('shouldCalculateTotalWithTax', () => {
  // Arrange: Set up test data and preconditions
  const cart = new ShoppingCart();
  cart.addItem({ price: 100, quantity: 2 });
  const taxRate = 0.1;

  // Act: Execute the behavior being tested
  const total = cart.calculateTotal(taxRate);

  // Assert: Verify the expected outcome
  expect(total).toBe(220);
});
```

#### 2. Test Fixtures and Setup
```javascript
describe('UserService', () => {
  let userService;
  let mockDatabase;

  beforeEach(() => {
    // Common setup for all tests
    mockDatabase = new MockDatabase();
    userService = new UserService(mockDatabase);
  });

  afterEach(() => {
    // Cleanup after each test
    mockDatabase.clear();
  });

  test('shouldCreateNewUser', () => {
    // Test implementation
  });
});
```

### Test Doubles

#### 1. Stubs - Provide predetermined responses
```javascript
const emailStub = {
  send: () => true  // Always returns success
};
```

#### 2. Mocks - Verify interactions
```javascript
const emailMock = {
  send: jest.fn()
};

userService.registerUser(user);
expect(emailMock.send).toHaveBeenCalledWith(user.email);
```

#### 3. Fakes - Working implementations
```javascript
class FakeDatabase {
  constructor() {
    this.data = new Map();
  }

  save(key, value) {
    this.data.set(key, value);
  }

  find(key) {
    return this.data.get(key);
  }
}
```

## Language-Specific TDD Examples

### JavaScript/TypeScript (Jest)
```javascript
// user.test.js
describe('User', () => {
  test('shouldHashPasswordOnCreation', () => {
    const user = new User('john@example.com', 'password123');
    expect(user.password).not.toBe('password123');
    expect(user.password.length).toBeGreaterThan(20);
  });
});
```

### Python (pytest)
```python
# test_user.py
def test_should_hash_password_on_creation():
    user = User('john@example.com', 'password123')
    assert user.password != 'password123'
    assert len(user.password) > 20
```

### Rust
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn should_hash_password_on_creation() {
        let user = User::new("john@example.com", "password123");
        assert_ne!(user.password, "password123");
        assert!(user.password.len() > 20);
    }
}
```

### Go
```go
func TestShouldHashPasswordOnCreation(t *testing.T) {
    user := NewUser("john@example.com", "password123")
    if user.Password == "password123" {
        t.Error("Password should be hashed")
    }
    if len(user.Password) <= 20 {
        t.Error("Hashed password should be longer than 20 characters")
    }
}
```

## Common TDD Anti-Patterns

### 1. Testing Implementation Instead of Behavior
❌ **Bad** - Tightly coupled to implementation:
```javascript
test('shouldCallValidateMethodThreeTimes', () => {
  const validator = new Validator();
  const spy = jest.spyOn(validator, 'validate');

  validator.processData(data);

  expect(spy).toHaveBeenCalledTimes(3);
});
```

✅ **Good** - Tests behavior:
```javascript
test('shouldRejectInvalidData', () => {
  const validator = new Validator();

  const result = validator.processData(invalidData);

  expect(result.isValid).toBe(false);
  expect(result.errors).toContain('Invalid email format');
});
```

### 2. Overly Complex Tests
❌ **Bad** - Test logic is too complex:
```javascript
test('shouldProcessOrders', () => {
  for (let i = 0; i < 10; i++) {
    const order = createOrder(i);
    if (order.total > 100) {
      expect(order.discount).toBeGreaterThan(0);
    } else {
      expect(order.discount).toBe(0);
    }
  }
});
```

✅ **Good** - Simple, focused tests:
```javascript
test('shouldApplyDiscountForOrdersOver100', () => {
  const order = createOrder({ total: 150 });
  expect(order.discount).toBeGreaterThan(0);
});

test('shouldNotApplyDiscountForOrdersUnder100', () => {
  const order = createOrder({ total: 50 });
  expect(order.discount).toBe(0);
});
```

### 3. Fragile Tests (Too Many Assertions)
❌ **Bad** - Too many assertions make test brittle:
```javascript
test('shouldCreateUser', () => {
  const user = createUser();

  expect(user.id).toBeDefined();
  expect(user.createdAt).toBeInstanceOf(Date);
  expect(user.updatedAt).toBeInstanceOf(Date);
  expect(user.roles).toEqual(['user']);
  expect(user.isActive).toBe(true);
  expect(user.emailVerified).toBe(false);
  // ... 10 more assertions
});
```

✅ **Good** - One concept per test:
```javascript
test('shouldAssignDefaultRoleOnCreation', () => {
  const user = createUser();
  expect(user.roles).toEqual(['user']);
});

test('shouldStartAsActiveUser', () => {
  const user = createUser();
  expect(user.isActive).toBe(true);
});
```

## Integration Testing with TDD

### Database Integration Tests
```javascript
describe('UserRepository Integration', () => {
  let database;
  let repository;

  beforeAll(async () => {
    database = await createTestDatabase();
    repository = new UserRepository(database);
  });

  afterAll(async () => {
    await database.close();
  });

  beforeEach(async () => {
    await database.clear();
  });

  test('shouldPersistUserToDatabase', async () => {
    const user = new User('john@example.com');

    await repository.save(user);
    const retrieved = await repository.findByEmail('john@example.com');

    expect(retrieved.email).toBe('john@example.com');
  });
});
```

### API Integration Tests
```javascript
describe('POST /api/users', () => {
  test('shouldCreateNewUser', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({
        email: 'john@example.com',
        password: 'password123'
      });

    expect(response.status).toBe(201);
    expect(response.body).toHaveProperty('id');
    expect(response.body.email).toBe('john@example.com');
  });

  test('shouldReturn400ForInvalidEmail', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({
        email: 'invalid-email',
        password: 'password123'
      });

    expect(response.status).toBe(400);
    expect(response.body.error).toContain('Invalid email');
  });
});
```

## E2E Testing with TDD

### Browser-Based E2E Tests
```javascript
describe('User Registration Flow', () => {
  test('shouldCompleteRegistrationSuccessfully', async () => {
    // Navigate to registration page
    await page.goto('http://localhost:3000/register');

    // Fill in form
    await page.fill('[name="email"]', 'john@example.com');
    await page.fill('[name="password"]', 'password123');
    await page.fill('[name="confirmPassword"]', 'password123');

    // Submit form
    await page.click('button[type="submit"]');

    // Verify redirect to success page
    await expect(page).toHaveURL('http://localhost:3000/registration-success');
    await expect(page.locator('h1')).toContainText('Welcome!');
  });
});
```

## Test Coverage Guidelines

### What to Measure
- **Line Coverage**: Percentage of code lines executed
- **Branch Coverage**: Percentage of decision branches taken
- **Function Coverage**: Percentage of functions called
- **Statement Coverage**: Percentage of statements executed

### Coverage Targets
- **Unit Tests**: Aim for 80-90% coverage
- **Integration Tests**: Focus on critical paths
- **E2E Tests**: Cover main user journeys

### Coverage ≠ Quality
```javascript
// 100% coverage but poor test quality
test('shouldRunAllCode', () => {
  const result = complexFunction(input);
  expect(result).toBeDefined();  // Weak assertion
});

// Better approach
test('shouldCalculateCorrectResult', () => {
  const result = complexFunction({ x: 5, y: 10 });
  expect(result.total).toBe(15);
  expect(result.status).toBe('success');
});
```

## Continuous Testing Workflow

### Watch Mode Development
```bash
# Run tests in watch mode during development
npm test -- --watch

# Run only tests related to changed files
npm test -- --watch --onlyChanged
```

### Pre-Commit Hooks
```json
{
  "husky": {
    "hooks": {
      "pre-commit": "npm test",
      "pre-push": "npm test && npm run lint"
    }
  }
}
```

### CI/CD Integration
```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          npm install
          npm test
          npm run test:coverage
```

## TDD in Different Contexts

### Legacy Code
When adding features to legacy code:
1. Write characterization tests (document current behavior)
2. Refactor with safety net of tests
3. Add new feature using TDD

### Spike Solutions
When exploring new technologies:
1. Create time-boxed spike without TDD
2. Discard spike code
3. Implement production version with TDD using learnings

### Performance-Critical Code
1. Write functional tests first (correctness)
2. Add performance benchmarks as tests
3. Optimize while keeping tests green

## Resources and Further Reading

### Books
- "Test-Driven Development: By Example" - Kent Beck
- "Growing Object-Oriented Software, Guided by Tests" - Freeman & Pryce
- "Working Effectively with Legacy Code" - Michael Feathers

### Online Resources
- Test-driven-development.com
- Martin Fowler's articles on testing
- Uncle Bob's Clean Code blog

### Tools by Language
- **JavaScript/TypeScript**: Jest, Mocha, Vitest
- **Python**: pytest, unittest
- **Java**: JUnit, TestNG
- **C#**: NUnit, xUnit
- **Ruby**: RSpec, Minitest
- **Go**: testing package
- **Rust**: built-in test framework
