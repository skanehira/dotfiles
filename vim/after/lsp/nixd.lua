---@type vim.lsp.Config
local flake = vim.env.HOME .. "/dev/github.com/skanehira/dotfiles/nix"

local options = {}

if vim.fn.has("mac") == 1 then
  options.nix_darwin = {
    expr = string.format(
      '(builtins.getFlake "%s").darwinConfigurations.skanehira.options',
      flake
    ),
  }
  options.home_manager = {
    expr = string.format(
      '(builtins.getFlake "%s").darwinConfigurations.skanehira.options.home-manager.users.type.getSubOptions []',
      flake
    ),
  }
else
  -- aarch64 Linux は flake output 名が変わる
  local suffix = vim.uv.os_uname().machine == "aarch64" and "-aarch64" or ""
  options.home_manager = {
    expr = string.format(
      '(builtins.getFlake "%s").homeConfigurations."skanehira%s".options',
      flake, suffix
    ),
  }
end

return {
  settings = {
    nixd = {
      nixpkgs = {
        expr = string.format(
          'import (builtins.getFlake "%s").inputs.nixpkgs { }',
          flake
        ),
      },
      options = options,
      formatting = { command = { "nixfmt" } },
    },
  },
}
