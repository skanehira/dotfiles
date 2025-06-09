local utils = require('utils')
local nmap = utils.keymaps.nmap

local config = function()
  local k8s_pods_keymap = function()
    nmap('<CR>', '<Plug>(k8s:pods:containers)', { buffer = true })
    nmap('<C-g><C-l>', '<Plug>(k8s:pods:logs)', { buffer = true })
    nmap('<C-g><C-d>', '<Plug>(k8s:pods:describe)', { buffer = true })
    -- nmap('D', '<Plug>(k8s:pods:delete)', { buffer = true })
    -- nmap('K', '<Plug>(k8s:pods:kill)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:pods:yaml)', { buffer = true })
    nmap('<C-e>', '<Plug>(k8s:pods:events)', { buffer = true })
    nmap('s', '<Plug>(k8s:pods:shell)', { buffer = true })
    nmap('e', '<Plug>(k8s:pods:exec)', { buffer = true })
    -- nmap('E', '<Plug>(k8s:pods:edit)', { buffer = true })
  end

  local k8s_nodes_keymap = function()
    nmap('<C-g><C-d>', '<Plug>(k8s:nodes:describe)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:nodes:yaml)', { buffer = true })
    nmap('<CR>', '<Plug>(k8s:nodes:pods)', { buffer = true })
    nmap('E', '<Plug>(k8s:nodes:edit)', { buffer = true })
  end

  local k8s_containers_keymap = function()
    nmap('s', '<Plug>(k8s:pods:containers:shell)', { buffer = true })
    nmap('e', '<Plug>(k8s:pods:containers:exec)', { buffer = true })
  end

  local k8s_deployments_keymap = function()
    nmap('<C-g><C-d>', '<Plug>(k8s:deployments:describe)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:deployments:yaml)', { buffer = true })
    nmap('E', '<Plug>(k8s:deployments:edit)', { buffer = true })
    nmap('<CR>', '<Plug>(k8s:deployments:pods)', { buffer = true })
    nmap('D', '<Plug>(k8s:deployments:delete)', { buffer = true })
  end

  local k8s_services_keymap = function()
    nmap('<CR>', '<Plug>(k8s:svcs:pods)', { buffer = true })
    nmap('<C-g><C-d>', '<Plug>(k8s:svcs:describe)', { buffer = true })
    nmap('D', '<Plug>(k8s:svcs:delete)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:svcs:yaml)', { buffer = true })
    nmap('E', '<Plug>(k8s:svcs:edit)', { buffer = true })
  end

  local k8s_secrets_keymap = function()
    nmap('<C-g><C-d>', '<Plug>(k8s:secrets:describe)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:secrets:yaml)', { buffer = true })
    nmap('E', '<Plug>(k8s:secrets:edit)', { buffer = true })
    nmap('D', '<Plug>(k8s:secrets:delete)', { buffer = true })
  end

  local k8s_keymaps = {
    { ft = 'k8s-pods',        fn = k8s_pods_keymap },
    { ft = 'k8s-nodes',       fn = k8s_nodes_keymap },
    { ft = 'k8s-containers',  fn = k8s_containers_keymap },
    { ft = 'k8s-deployments', fn = k8s_deployments_keymap },
    { ft = 'k8s-services',    fn = k8s_services_keymap },
    { ft = 'k8s-secrets',     fn = k8s_secrets_keymap },
  }

  local k8s_keymap_group = vim.api.nvim_create_augroup("k8sInit", { clear = true })

  for _, m in pairs(k8s_keymaps) do
    vim.api.nvim_create_autocmd('FileType', {
      pattern = m.ft,
      callback = m.fn,
      group = k8s_keymap_group,
    })
  end
end

local k8s = {
  'skanehira/k8s.vim',
  config = config,
}

return k8s
