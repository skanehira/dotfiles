# MUST Rules Reminder

## 🚨 IMPORTANT: You MUST follow these MUST rules strictly

Please strictly follow the MUST rules documented in the global CLAUDE.md (~/.config/claude/CLAUDE.md):

### Sections to Reference

1. **Background Process Management is MANDATORY**
   - MUST use ghost for all background processes
   - MUST NOT use traditional background methods (&, nohup, etc.)
   - See "Background Process Management is MANDATORY" section in `CLAUDE.md` for details

2. **Test-Driven Development (TDD) is MANDATORY**
   - MUST follow RED → GREEN → REFACTOR cycle
   - MUST NEVER write production code without a failing test first
   - See "Test-Driven Development (TDD) is MANDATORY" section in `CLAUDE.md` for details

3. **Tidy First Approach is MANDATORY**
   - MUST separate structural and behavioral changes
   - MUST ALWAYS make structural changes before behavioral changes
   - See "Tidy First Approach is MANDATORY" section in `CLAUDE.md` for details

4. **Handling Uncertainties is MANDATORY**
   - MUST NEVER make assumptions or guess
   - MUST ALWAYS explicitly state uncertainties
   - MUST research first, ask for clarification, and be transparent
   - See "Handling Uncertainties is MANDATORY" section in `CLAUDE.md` for details

5. **Documentation Search is MANDATORY**
   - MUST use context7 for library/framework documentation searches
   - MUST first call resolve-library-id, then get-library-docs
   - MUST NEVER use web search when context7 has the documentation
   - See "Documentation Search is MANDATORY" section in `CLAUDE.md` for details

6. **Commit Discipline is MANDATORY**
   - MUST ONLY commit when all tests pass
   - MUST use [STRUCTURAL] or [BEHAVIORAL] prefix in commit messages
   - See "Commit Discipline is MANDATORY" section in `CLAUDE.md` for details

7. **Avoiding Ambiguous Responses is MANDATORY**
   - MUST research and verify information before responding
   - MUST provide only confirmed information
   - MUST answer "I don't know" when uncertain
   - MUST always cite sources when available
   - MUST avoid speculation-based responses

**NOTE**: For detailed rules and specific procedures, always refer to the global `~/.config/claude/CLAUDE.md` file.
