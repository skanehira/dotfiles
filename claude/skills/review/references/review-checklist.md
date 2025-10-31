# Review Checklist Reference

Comprehensive checklists for each review phase with common issues and best practices.

## Phase 1: Code Quality Checklist

### Readability
- [ ] Variable names clearly convey purpose
- [ ] Function names describe what they do (verb-based)
- [ ] Class names represent concepts (noun-based)
- [ ] Magic numbers replaced with named constants
- [ ] Complex expressions extracted to well-named variables
- [ ] Comments explain "why" not "what"
- [ ] Code organized in logical sections

### Maintainability
- [ ] No code duplication (DRY principle)
- [ ] Functions under 20-30 lines
- [ ] Classes have single responsibility
- [ ] Dependencies are explicit, not hidden
- [ ] Error messages are informative
- [ ] Configuration externalized from code

### Performance
- [ ] No premature optimization
- [ ] Algorithms have reasonable time complexity
- [ ] Database queries optimized (no N+1)
- [ ] Large datasets handled efficiently
- [ ] Resource cleanup (connections, files, memory)
- [ ] Caching used appropriately

### Common Issues
- Long methods (>30 lines)
- Deep nesting (>3 levels)
- Too many parameters (>4)
- God classes (doing too much)
- Primitive obsession (using primitives instead of objects)

## Phase 2: Design & Architecture Checklist

### SOLID Principles
- [ ] Single Responsibility: Each class has one reason to change
- [ ] Open-Closed: Open for extension, closed for modification
- [ ] Liskov Substitution: Subtypes are substitutable for base types
- [ ] Interface Segregation: No fat interfaces with unused methods
- [ ] Dependency Inversion: Depend on abstractions, not concretions

### Design Patterns
- [ ] Appropriate pattern selection (not over-engineered)
- [ ] Pattern implementation correct
- [ ] Pattern documented in comments
- [ ] No anti-patterns (god object, singleton abuse, etc.)

### API Design
- [ ] Consistent naming across API
- [ ] Backward compatible (or breaking changes documented)
- [ ] Input validation at boundaries
- [ ] Clear error responses
- [ ] Versioning strategy in place

### Common Issues
- Tight coupling between modules
- Circular dependencies
- Leaky abstractions
- Over-engineering with unnecessary patterns
- Inconsistent API design across endpoints

## Phase 3: Security Checklist

### Input Validation
- [ ] All user inputs validated
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (output encoding)
- [ ] Path traversal prevention
- [ ] Command injection prevention
- [ ] File upload restrictions

### Authentication & Authorization
- [ ] Authentication required for protected endpoints
- [ ] Authorization checks on all resources
- [ ] Session management secure
- [ ] Password hashing (bcrypt, Argon2)
- [ ] No credentials in code/logs
- [ ] Rate limiting on login endpoints

### Data Protection
- [ ] Sensitive data encrypted at rest
- [ ] TLS/SSL for data in transit
- [ ] No sensitive data in logs
- [ ] Secrets in environment variables
- [ ] PII handling compliant with regulations
- [ ] Secure random number generation

### Common Vulnerabilities
- SQL Injection
- Cross-Site Scripting (XSS)
- Cross-Site Request Forgery (CSRF)
- Insecure Direct Object References
- Security Misconfiguration
- Sensitive Data Exposure
- Missing Access Control

## Phase 4: Test Checklist

### Test Coverage
- [ ] Unit tests for business logic
- [ ] Integration tests for component interaction
- [ ] E2E tests for critical user flows
- [ ] Edge cases covered
- [ ] Error scenarios tested
- [ ] Coverage >80% for critical code

### Test Quality
- [ ] Tests are independent (can run in any order)
- [ ] Tests are fast (<100ms for unit tests)
- [ ] Test names describe behavior
- [ ] Arrange-Act-Assert pattern used
- [ ] No logic in tests
- [ ] Test data factories for complex objects

### Common Issues
- Testing implementation instead of behavior
- Tests dependent on execution order
- Slow tests (database/network in unit tests)
- Brittle tests (too many assertions)
- Missing negative test cases
- No tests for error handling

## Phase 5: Operations Checklist

### Logging
- [ ] Appropriate log levels (ERROR, WARN, INFO, DEBUG)
- [ ] Structured logging (JSON format)
- [ ] Request IDs for tracing
- [ ] No sensitive data in logs
- [ ] Meaningful error messages
- [ ] Log retention policy considered

### Monitoring
- [ ] Key metrics instrumented
- [ ] Health check endpoint
- [ ] Performance metrics tracked
- [ ] Error rate monitoring
- [ ] Alerting thresholds defined
- [ ] Dashboard for key metrics

### Deployment
- [ ] Configuration externalized
- [ ] Database migrations included
- [ ] Rollback strategy defined
- [ ] Zero-downtime deployment possible
- [ ] Feature flags for risky changes
- [ ] CI/CD pipeline updated

### Common Issues
- Logging too much or too little
- No structured logging
- Missing health checks
- No rollback plan
- Hard-coded configuration
- Missing error alerts

## Phase 6: Documentation Checklist

### Code Comments
- [ ] Complex logic explained
- [ ] "Why" decisions documented
- [ ] API contracts documented
- [ ] No commented-out code
- [ ] TODOs tracked (or removed)

### API Documentation
- [ ] Endpoints documented
- [ ] Request/response schemas defined
- [ ] Authentication requirements clear
- [ ] Error codes documented
- [ ] Examples provided
- [ ] Postman/OpenAPI spec updated

### Change Documentation
- [ ] Breaking changes clearly marked
- [ ] Migration guide for breaking changes
- [ ] CHANGELOG updated
- [ ] README updated if needed
- [ ] Architecture decisions recorded (ADRs)

### Common Issues
- Outdated comments
- Missing API documentation
- Undocumented breaking changes
- No migration guide
- Commented-out code left behind

## Language-Specific Considerations

### JavaScript/TypeScript
- [ ] TypeScript types used (no `any`)
- [ ] Async/await over callbacks
- [ ] Error handling with try-catch
- [ ] ESLint rules followed
- [ ] Package versions pinned

### Python
- [ ] Type hints used
- [ ] PEP 8 compliance
- [ ] Virtual environment specified
- [ ] Requirements.txt/poetry.lock updated
- [ ] Exception handling appropriate

### Java
- [ ] No checked exceptions abuse
- [ ] Stream API used appropriately
- [ ] Resource management with try-with-resources
- [ ] Optional used for nullable values
- [ ] Immutability preferred

### Go
- [ ] Error handling explicit
- [ ] Goroutine leaks prevented
- [ ] Context used for cancellation
- [ ] Defer for cleanup
- [ ] Interface segregation

### Rust
- [ ] No unsafe code without justification
- [ ] Error handling with Result
- [ ] Ownership/borrowing correct
- [ ] No clippy warnings
- [ ] Documentation tests included

## Review Report Template

Use this template structure for consistency:

```markdown
# Code Review Report

**Date**: YYYY-MM-DD
**Scope**: [What was reviewed]
**Reviewer**: Claude Code

## 概要
[2-3 sentences summarizing findings]

## Phase 1: コード品質
### 良い点
- [Positive findings]

### 改善点
- [Issues found with severity]

## Phase 2: 設計・アーキテクチャ
[Same structure]

## Phase 3: セキュリティ
[Same structure]

## Phase 4: テスト
[Same structure]

## Phase 5: 運用性
[Same structure]

## Phase 6: ドキュメント
[Same structure]

## 一貫性分析
[Consistency with existing codebase]

## 優先度別の推奨事項

### Critical
1. [Issue with file:line reference]

### Important
1. [Issue with file:line reference]

### Suggestion
1. [Improvement with file:line reference]

## コード例
[Specific before/after examples]
```
