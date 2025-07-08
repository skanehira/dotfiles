## MUST Rules

### Background Process Management is MANDATORY

**All background processes MUST be managed using ghost:**

1. **MUST use ghost**: Always use https://github.com/skanehira/ghost for running background processes
2. **NO traditional methods**: Do NOT use `&`, `nohup`, `screen`, `tmux`, or other traditional background process methods
3. **Reference documentation**: Always refer to ghost's README.md for detailed usage instructions

**Why ghost is required:**
- Provides proper process management and monitoring
- Ensures consistent behavior across different environments
- Prevents orphaned processes and resource leaks

### Test-Driven Development (TDD) is MANDATORY

**Every piece of production code MUST be written using TDD methodology:**

1. **RED Phase (MUST)**: Write a failing test FIRST before any implementation
2. **GREEN Phase (MUST)**: Write ONLY the minimum code needed to make the test pass
3. **REFACTOR Phase (MUST)**: Improve code quality ONLY after tests are green

**Violations of TDD approach are NOT acceptable:**
- ❌ Writing production code without a failing test
- ❌ Writing more code than needed to pass the test
- ❌ Refactoring when tests are not green
- ❌ Skipping tests with the intention to "add them later"

**Remember: No test, no code. This is non-negotiable.**

## Work Cycle

### 1. Task Management
- **Sequential Processing**: Work on tasks one at a time, not in parallel
- **Task Tracking**: Maintain a task list with clear status tracking
- **Atomic Changes**: Each task should result in a self-contained, testable change

### 2. Quality Assurance Cycle
After completing each task, run the following verification steps:
- **Unit Tests**: Ensure all tests pass
- **Code Linting**: Verify code meets quality standards
- **Code Formatting**: Apply consistent formatting

### 3. Review Process
- **Completion Notification**: Clearly communicate when a task is complete
- **Await Approval**: Wait for review before proceeding to the next task
- **Incorporate Feedback**: Address any review comments before moving forward

### 4. Version Control
- **Clear Messages**: Write descriptive commit messages
- **Logical Grouping**: Keep commits focused on a single purpose

## Code Quality Standards

### Type Safety
- **No Type Casting**: Avoid using type assertions (`as`) 
- **Explicit Types**: Define clear return types for functions
- **Type Guards**: Use proper type guards for runtime checks
- **Type Inference**: Let the type system infer types where appropriate

### Code Comments
Follow the "Code Tells You How, Comments Tell You Why" principle:
- **Self-Documenting Code**: Use clear variable and function names
- **Why, Not What**: Comments should explain the reasoning behind decisions
- **Business Logic**: Document complex business rules and edge cases
- **Non-Obvious Implementations**: Explain unusual or clever solutions

### Dependency Management
- **Official Sources**: Use official package registries
- **Version Pinning**: Lock dependencies to specific versions
- **Security Updates**: Regularly update dependencies for security patches
- **Minimal Dependencies**: Only add dependencies that provide significant value

## Testing Strategy

### Test-Driven Development (TDD)
Follow t-wada's TDD approach with the Testing Trophy principle:

#### The TDD Cycle
1. **Red**: Write a failing test first
2. **Green**: Write the minimum code to make the test pass
3. **Refactor**: Improve the code while keeping tests green

#### Testing Trophy (by t-wada)
Prioritize tests in this order:
- **Unit Tests** (Base): Fast, focused, numerous
- **Integration Tests** (Middle): Verify component interactions
- **E2E Tests** (Top): Minimal but critical user flows

#### TDD Principles
- **Test First**: Always write tests before implementation
- **Small Steps**: Make tiny changes and run tests frequently
- **Refactoring**: Clean up code only when all tests are green
- **No Production Code Without Tests**: Every line of production code should be driven by a test

### Test Coverage
- **Unit Tests**: Test individual functions and components
- **Integration Tests**: Verify component interactions
- **Edge Cases**: Include tests for boundary conditions
- **Error Scenarios**: Test error handling paths

### Test Organization
- **Co-location**: Keep test files near the code they test
- **Descriptive Names**: Use clear test descriptions
- **Isolated Tests**: Each test should be independent
- **Fast Execution**: Keep tests fast and focused

## Documentation

### Code Documentation
- **JSDoc Comments**: Use standardized documentation formats
- **API Documentation**: Document public interfaces thoroughly
- **Examples**: Include usage examples where helpful
- **Maintenance Notes**: Document any special maintenance requirements

### Project Documentation
- **README**: Maintain an up-to-date project overview
- **Architecture**: Document system design decisions
- **Setup Guide**: Provide clear installation instructions
- **Contributing Guide**: Explain how to contribute to the project

## Continuous Improvement

### Regular Reviews
- **Code Reviews**: Review all changes before merging
- **Architecture Reviews**: Periodically review system design
- **Performance Reviews**: Monitor and optimize performance
- **Security Reviews**: Regular security assessments

### Feedback Loop
- **Team Retrospectives**: Regular team improvement discussions
- **Process Refinement**: Continuously improve workflows
- **Tool Evaluation**: Assess and adopt better tools
- **Knowledge Sharing**: Share learnings across the team
