function checkout -d "Fuzzy-find and checkout a branch"
  git branch | string trim | fzf | read -l result; and git checkout "$result"
end
