# MUST Rules Reminder

## 🚨 IMPORTANT: You MUST follow these MUST rules strictly

Please strictly follow the MUST rules documented in the global CLAUDE.md (~/.config/claude/CLAUDE.md):

### Sections to Reference

1. **Background Process Management is MANDATORY**
   - MUST use ghost for all background processes
   - DO NOT use traditional background methods (&, nohup, etc.)
   - See "Background Process Management is MANDATORY" section in `CLAUDE.md` for details

2. **Test-Driven Development (TDD) is MANDATORY**
   - MUST follow RED → GREEN → REFACTOR cycle
   - NEVER write production code without a failing test first
   - See "Test-Driven Development (TDD) is MANDATORY" section in `CLAUDE.md` for details

3. **Tidy First Approach is MANDATORY**
   - MUST separate structural and behavioral changes
   - ALWAYS make structural changes before behavioral changes
   - See "Tidy First Approach is MANDATORY" section in `CLAUDE.md` for details

4. **Handling Uncertainties is MANDATORY**
   - NEVER make assumptions or guess
   - ALWAYS explicitly state uncertainties
   - MUST research first, ask for clarification, and be transparent
   - See "Handling Uncertainties is MANDATORY" section in `CLAUDE.md` for details

5. **Commit Discipline is MANDATORY**
   - ONLY commit when all tests pass
   - MUST use [STRUCTURAL] or [BEHAVIORAL] prefix in commit messages
   - See "Commit Discipline is MANDATORY" section in `CLAUDE.md` for details

**NOTE**: For detailed rules and specific procedures, always refer to the global `~/.config/claude/CLAUDE.md` file.