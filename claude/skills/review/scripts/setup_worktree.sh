#!/bin/bash
# Worktree setup automation script for PR reviews
# Usage: ./setup_worktree.sh <branch-name> <identifier>

set -e

BRANCH_NAME=$1
IDENTIFIER=$2

if [ -z "$BRANCH_NAME" ] || [ -z "$IDENTIFIER" ]; then
    echo "Usage: $0 <branch-name> <identifier>"
    echo "Example: $0 feature/auth pr-123"
    exit 1
fi

# Create worktree name (sanitize identifier)
WORKTREE_NAME=$(echo "$IDENTIFIER" | tr '/' '-' | tr '[:upper:]' '[:lower:]')
WORKTREE_PATH=".git/worktrees/$WORKTREE_NAME"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
    echo "❌ Worktree already exists at $WORKTREE_PATH"
    echo "To remove it: git worktree remove $WORKTREE_PATH"
    exit 1
fi

echo "🚀 Creating worktree for branch: $BRANCH_NAME"
echo "📁 Worktree path: $WORKTREE_PATH"

# Create worktree
git worktree add "$WORKTREE_PATH" "origin/$BRANCH_NAME"

echo "✅ Worktree created successfully"
echo "📂 Changing to worktree directory..."

cd "$WORKTREE_PATH"

echo "✅ Now in worktree directory: $(pwd)"
echo ""
echo "To cleanup after review:"
echo "  cd $(git rev-parse --show-toplevel)"
echo "  git worktree remove $WORKTREE_PATH"
