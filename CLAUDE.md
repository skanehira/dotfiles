# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository for managing development environment configurations across macOS and Linux systems. The repository uses a modular structure where each tool has its own directory with configuration files and an installation script.

## Repository Structure

- **git/** - Git configuration with GPG signing, aliases, and difftastic integration
- **vim/** - Extensive Neovim configuration using Lua and lazy.nvim plugin manager
- **zsh/** - Z shell configuration with custom aliases, functions, and key bindings
- **tmux/** - Terminal multiplexer configuration with platform-specific variants
- **wezterm/** - WezTerm terminal emulator configuration
- **karabiner/** - macOS keyboard remapping configuration
- **claude/** - Claude Code custom commands and configuration

## Installation and Setup

### Full Installation
```bash
# Clone repository
git clone https://github.com/skanehira/dotfiles.git
cd dotfiles

# Run individual installers (main install.sh is incomplete)
cd git && ./install.sh
cd ../vim && ./install.sh
cd ../tmux && ./install.sh
cd ../zsh && ./install.sh
cd ../wezterm && ./install.sh
cd ../karabiner && ./install.sh  # macOS only
cd ../claude && ./install.sh
```

### Key Dependencies
- Homebrew (package manager)
- Neovim
- Zsh with zsh-autosuggestions
- asdf (version manager)
- fzf, ripgrep, bat, lsd, delta, ghq, lazygit
- Docker, kubectl, terraform (for development)

## Common Commands and Workflows

### Essential Aliases
- `v` - Open Neovim
- `lg` - Launch lazygit
- `gs` - Git status
- `ll` - List files with details (using lsd)
- `k` - kubectl
- `d` - docker compose
- `t` - terraform

### Key Bindings
- `Ctrl+g` - Fuzzy search and switch to ghq-managed repositories
- `Ctrl+k` - Interactive git branch switcher with preview
- `Ctrl+q` - Toggle tmux popup window

### Development Paths
- Go binaries: `$HOME/go/bin`
- ghq repositories: `$HOME/dev`
- Deno binaries: `$HOME/.deno/bin`

## Neovim Configuration

### Plugin Management
Uses lazy.nvim as the plugin manager. Configuration files are in `vim/lua/plugins/`.

### LSP Support
LSP configurations are in `vim/after/` for:
- Deno, TypeScript, Rust, Lua, YAML

### Key Features
- AI integration: Copilot, Copilot Chat, Claude Code
- Git integration: Gina, Gitsigns, Diffview
- Fuzzy finding: Telescope
- Code templates: SonicTemplate
- LSP enhancements: tiny-code-action, tiny-inline-diagnostic
- Quickfix improvements: bqf, quicker

## Working with This Repository

### When modifying configurations:
1. Each tool's configuration is self-contained in its directory
2. Test changes by running the tool's install script to update symlinks
3. Platform-specific code should check for Darwin (macOS) or Linux

### When adding new tools:
1. Create a new directory for the tool
2. Add configuration files
3. Create an `install.sh` script that symlinks configurations to appropriate locations
4. Update the main `install.sh` or `install_linux.sh` if needed

### Important Notes
- Git is configured with GPG signing - ensure GPG is set up
- The repository assumes `$HOME/dev` as the base for ghq-managed repositories
- Tmux prefix is remapped to `Ctrl+s` (not the default `Ctrl+b`)
- Many tools expect modern CLI replacements (lsd for ls, delta for diff, etc.)

## Claude Code Integration

### Custom Commands
The `claude/` directory contains custom slash commands for Claude Code:
- `/commit` - Intelligent commit creation with conventional commit format and emoji
- `/review` - Comprehensive PR review with automated worktree management

### Command Features
- **Commit Command**: Automated pre-commit checks (lint, build, docs), conventional commit format with emoji, automatic commit splitting for complex changes
- **Review Command**: Systematic 6-phase review process, automatic worktree creation, consistency analysis with existing codebase

### Installation
Run `cd claude && ./install.sh` to install Claude Code custom commands to `~/.config/claude/`