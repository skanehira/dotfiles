# Commit Emoji Guide

Comprehensive guide for selecting appropriate emojis in Conventional Commit messages.

## Primary Type Mappings

| Type | Emoji | Use When |
|------|-------|----------|
| `feat` | ✨ | Adding new features or functionality |
| `fix` | 🐛 | Fixing bugs or defects |
| `docs` | 📝 | Documentation changes only |
| `style` | 💄 | Code formatting, missing semi-colons, etc. |
| `refactor` | ♻️ | Code refactoring without behavior change |
| `perf` | ⚡️ | Performance improvements |
| `test` | ✅ | Adding or updating tests |
| `chore` | 🔧 | Build process, tools, configuration |
| `ci` | 🚀 | CI/CD configuration changes |
| `revert` | 🗑️ | Reverting previous changes |

## Specific Situational Emojis

### Testing
- 🧪 **failing test** - Add a failing test (TDD RED phase)
- ✅ **test** - Add or update passing tests
- 🤡 **mock** - Add or update mocks

### Bug Fixes
- 🐛 **fix** - General bug fix
- 🚑️ **hotfix** - Critical hotfix
- 🩹 **simple-fix** - Simple fix for non-critical issue
- 🥅 **catch-errors** - Catch errors, add error handling
- 👽️ **update-api** - Update code due to external API changes
- 💚 **fix-ci** - Fix CI build

### Features
- ✨ **feat** - New feature
- 🔍️ **seo** - Improve SEO
- 🏷️ **types** - Add or update types
- 💬 **text** - Add or update text and literals
- 🌐 **i18n** - Internationalization and localization
- 👔 **business-logic** - Add or update business logic
- 📱 **responsive** - Work on responsive design
- 🚸 **ux** - Improve user experience / usability
- 🧵 **concurrency** - Add or update multithreading/concurrency
- 📈 **analytics** - Add or update analytics
| 🦺 **validation** - Add or update validation
| ♿️ **accessibility** - Improve accessibility
| ✈️ **offline** - Work on offline support/functionality

### Code Quality
- 🎨 **style** - Improve structure / format of code
- ♻️ **refactor** - Refactor code
- 🚚 **move** - Move or rename resources (files, paths, routes)
- 🏗️ **architectural** - Make architectural changes
- 🔥 **remove** - Remove code or files
- ⚰️ **dead-code** - Remove dead code

### Dependencies
- ➕ **add-dep** - Add a dependency
- ➖ **remove-dep** - Remove a dependency
- ⬆️ **upgrade-dep** - Upgrade dependencies
- ⬇️ **downgrade-dep** - Downgrade dependencies
- 📌 **pin-dep** - Pin dependencies to specific versions

### Configuration & Build
- 🔧 **chore** - Add or update configuration files
- 👷 **ci** - Add or update CI build system
- 📦️ **package** - Add or update compiled files or packages
- 🔨 **scripts** - Add or update development scripts
- 🌱 **seed** - Add or update seed files

### Security
- 🔒️ **security** - Fix security issues
- 🔐 **secrets** - Add or update secrets
- 🛡️ **permissions** - Add or update permissions

### Documentation
- 📝 **docs** - Add or update documentation
- 💡 **comments** - Add or update source code comments
- 📄 **license** - Add or update license
- 📸 **snapshots** - Add or update snapshots

### Logs & Monitoring
- 🔊 **add-logs** - Add or update logs
- 🔇 **remove-logs** - Remove logs
- 📊 **metrics** - Add or update analytics or tracking code

### Developer Experience
- 🧑‍💻 **dx** - Improve developer experience
- 🚧 **wip** - Work in progress
- 🎉 **init** - Begin a project
- 🔖 **release** - Release / version tags
- 🙈 **gitignore** - Add or update a .gitignore file

### Warnings & Alerts
- 🚨 **lint** - Fix compiler / linter warnings
- 💥 **breaking** - Introduce breaking changes

### Assets & Media
- 🍱 **assets** - Add or update assets
- 🎨 **design** - Add or update UI and style files
- 💫 **animation** - Add or update animations and transitions

### Experimental & Features
- ⚗️ **experiment** - Perform experiments
- 🚩 **feature-flag** - Add, update, or remove feature flags

### Database
- 🗃️ **database** - Perform database related changes
- 🔀 **merge** - Merge branches
- 👥 **contributors** - Add or update contributor(s)

## Selection Guide

### By Change Category

**New Functionality:**
1. General feature → ✨ feat
2. Business logic → 👔 feat
3. UI/UX improvement → 🚸 feat
4. Accessibility → ♿️ feat
5. Internationalization → 🌐 feat

**Bug Fixes:**
1. General bug → 🐛 fix
2. Critical bug → 🚑️ fix
3. Simple fix → 🩹 fix
4. Security fix → 🔒️ fix
5. CI failure → 💚 fix

**Code Improvements:**
1. Refactoring → ♻️ refactor
2. Performance → ⚡️ perf
3. Code formatting → 🎨 style
4. Remove code → 🔥 fix/refactor

**Development Process:**
1. Tests → ✅ test
2. CI/CD → 🚀 ci
3. Dependencies → ➕/➖/⬆️ chore
4. Configuration → 🔧 chore
5. Scripts → 🔨 chore

**Documentation:**
1. Docs files → 📝 docs
2. Code comments → 💡 docs
3. License → 📄 chore

## Decision Tree

```
Is it a new feature?
├─ YES → Is it business logic specific?
│        ├─ YES → 👔 feat
│        └─ NO → ✨ feat
└─ NO → Is it a bug fix?
         ├─ YES → Is it critical?
         │        ├─ YES → 🚑️ fix
         │        └─ NO → 🐛 fix
         └─ NO → Is it refactoring?
                  ├─ YES → ♻️ refactor
                  └─ NO → See other categories
```

## Examples by Scenario

### Feature Development
```bash
✨ feat: add user authentication system
👔 feat: implement order processing business rules
🌐 feat: add French language support
🚸 feat: improve checkout flow usability
♿️ feat: add screen reader support to forms
```

### Bug Fixes
```bash
🐛 fix: resolve null pointer exception in user service
🚑️ fix: patch critical SQL injection vulnerability
🩹 fix: correct typo in email template
💚 fix: resolve failing test in CI pipeline
🥅 fix: add error handling for network timeouts
```

### Code Quality
```bash
♻️ refactor: extract user validation logic to separate service
⚡️ perf: optimize database query with indexes
🎨 style: format code according to ESLint rules
🔥 fix: remove deprecated API endpoints
⚰️ refactor: remove unused helper functions
```

### Development Process
```bash
✅ test: add unit tests for authentication service
🧪 test: add failing test for password validation (RED phase)
🚀 ci: add automated deployment to staging
➕ chore: add lodash dependency
📌 chore: pin React version to 18.2.0
🔧 chore: update webpack configuration
```

### Documentation
```bash
📝 docs: update API documentation with new endpoints
💡 docs: add comments explaining algorithm complexity
📄 chore: update MIT license year
```

## Common Mistakes to Avoid

❌ **Wrong**: `🐛 feat: add new login page` (bug emoji with feat type)
✅ **Correct**: `✨ feat: add new login page`

❌ **Wrong**: `✨ fix: resolve login bug` (feat emoji with fix type)
✅ **Correct**: `🐛 fix: resolve login bug`

❌ **Wrong**: `🔧 feat: add user dashboard` (chore emoji with feat type)
✅ **Correct**: `✨ feat: add user dashboard`

## Tips for Selection

1. **Match emoji to type first** - The primary type (feat, fix, etc.) determines base emoji
2. **Use specific emoji for special cases** - 🚑️ for hotfixes, 👔 for business logic
3. **Consistency matters** - Use the same emoji for similar changes
4. **When in doubt, use the primary** - ✨ for features, 🐛 for bugs is always safe

## Reference

This guide is based on [gitmoji](https://gitmoji.dev/) and Conventional Commits specification, adapted for Claude Code workflow.
