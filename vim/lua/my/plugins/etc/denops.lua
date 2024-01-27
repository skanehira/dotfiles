local config = function()
  vim.g['denops#server#deno_args'] = {
    '-q',
    '--no-lock',
    '-A',
    '--unstable-ffi'
  }
end

local denops = {
  'vim-denops/denops.vim',
  config = config,
}

return denops
