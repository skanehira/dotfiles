## MUST Rules

### Background Process Management is MANDATORY

**All background processes MUST be managed using ghost:**

1. **MUST use ghost MCP**: Always use ghost-mcp tools (`mcp__ghost-mcp__ghost_run`, `mcp__ghost-mcp__ghost_list`, etc.) for running background processes
2. **NO traditional methods**: Do NOT use `&`, `nohup`, `screen`, `tmux`, or other traditional background process methods

**Why ghost is required:**
- Provides proper process management and monitoring
- Ensures consistent behavior across different environments
- Prevents orphaned processes and resource leaks

### Test-Driven Development (TDD) is MANDATORY

**Every piece of production code MUST be written using Kent Beck's TDD methodology:**

#### The TDD Cycle
1. **RED Phase (MUST)**: Write a failing test FIRST before any implementation
   - Start with the simplest failing test that defines a small increment of functionality
   - Use meaningful test names that describe behavior (e.g., "shouldSumTwoPositiveNumbers")
   - Make test failures clear and informative
2. **GREEN Phase (MUST)**: Write ONLY the minimum code needed to make the test pass
   - Implement just enough code - no more
   - Focus only on making the current test pass
3. **REFACTOR Phase (MUST)**: Improve code quality ONLY after tests are green
   - Eliminate duplication ruthlessly
   - Express intent clearly through naming and structure
   - Keep methods small and focused on a single responsibility
   - Make dependencies explicit
   - Minimize state and side effects
   - Use the simplest solution that works

#### Defect Fixing Process (MUST)
When fixing a defect:
1. First write an API-level failing test that demonstrates the bug
2. Write the smallest possible test that replicates the problem
3. Get both tests to pass with minimal code changes

#### Testing Trophy
Prioritize tests in this order:
- **Unit Tests** (Base): Fast, focused, numerous
- **Integration Tests** (Middle): Verify component interactions
- **E2E Tests** (Top): Minimal but critical user flows

#### TDD Principles
- **Test Behavior, Not Implementation**: Focus on what the code does, not how

**Violations of TDD approach are NOT acceptable:**
- ❌ Writing production code without a failing test
- ❌ Writing more code than needed to pass the test
- ❌ Refactoring when tests are not green
- ❌ Skipping tests with the intention to "add them later"
- ❌ Mixing structural and behavioral changes in the same commit

**Remember: No test, no code. This is non-negotiable.**

#### Test Coverage
- **Edge Cases**: Include tests for boundary conditions
- **Error Scenarios**: Test error handling paths

#### Test Organization
- **Co-location**: Keep test files near the code they test
- **Isolated Tests**: Each test should be independent
- **Fast Execution**: Keep tests fast and focused

### Tidy First Approach is MANDATORY

**All changes MUST be separated into two distinct types:**

1. **STRUCTURAL CHANGES**: Rearranging code without changing behavior
   - Renaming variables, methods, or classes
   - Extracting methods or classes
   - Moving code between files
   - Reformatting code
   - MUST be validated by running all tests before and after changes

2. **BEHAVIORAL CHANGES**: Adding or modifying actual functionality
   - Adding new features
   - Fixing bugs
   - Changing business logic
   - MUST be driven by failing tests first

**Tidy First Rules:**
- **NEVER mix structural and behavioral changes in the same commit**
- **ALWAYS make structural changes first when both are needed**
- **VALIDATE structural changes do not alter behavior by running tests**
- **Each commit MUST clearly state whether it contains structural or behavioral changes**

### Handling Uncertainties is MANDATORY

**When encountering unclear requirements or unknown information:**

1. **NEVER make assumptions**: Do not guess or fill in gaps with assumptions
2. **ALWAYS explicitly state uncertainties**: Clearly communicate what is unclear or unknown
3. **MANDATORY actions when uncertain**:
   - **Research first**: Use available tools to search and understand the codebase
   - **Ask for clarification**: Request specific information from the user
   - **State limitations**: Explicitly say "I don't know" or "I'm uncertain about..."
   - **Provide options**: When unsure, present multiple approaches with trade-offs

**Examples of proper uncertainty handling:**
- ✅ "I'm not sure which testing framework this project uses. Let me search for test files to understand the setup."
- ✅ "The requirements for this feature are unclear. Could you specify whether you want X or Y?"
- ✅ "I don't know the exact API structure. I'll need to examine the existing code first."

**Violations are NOT acceptable:**
- ❌ Making up file paths or function names
- ❌ Assuming project structure without verification
- ❌ Guessing at requirements instead of asking
- ❌ Implementing features based on assumptions

**Remember: It's always better to ask than to assume. Transparency builds trust.**

### Documentation Search is MANDATORY

**When searching for library or framework documentation:**

1. **MUST use context7**: Always use the context7 MCP server for documentation searches
2. **Proper usage flow**:
   - First call `resolve-library-id` to get the Context7-compatible library ID
   - Then call `get-library-docs` with the resolved ID
   - Exception: If user explicitly provides a library ID in `/org/project` format

**Examples of proper documentation search:**
- ✅ "Let me search for React documentation using context7"
- ✅ "I'll use context7 to find the latest Next.js API documentation"
- ✅ "Using context7 to get Supabase documentation for this feature"

**Violations are NOT acceptable:**
- ❌ Using web search for official documentation when context7 has it
- ❌ Guessing API methods without checking documentation
- ❌ Using outdated documentation from memory

**Remember: Always use the most up-to-date documentation available through context7.**

### Commit Discipline is MANDATORY

**Only commit when ALL of the following conditions are met:**

1. **ALL tests are passing** - No exceptions
2. **ALL compiler/linter warnings have been resolved**
3. **The change represents a single logical unit of work**
4. **Commit messages clearly state:**
   - Whether the commit contains structural OR behavioral changes
   - The specific purpose of the change
   - Format: `[STRUCTURAL]` or `[BEHAVIORAL]` prefix followed by description

**Commit Rules:**
- Use small, frequent commits rather than large, infrequent ones
- Each commit should be reversible without breaking functionality
- Never commit work-in-progress code
- Keep commits focused on a single purpose

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
