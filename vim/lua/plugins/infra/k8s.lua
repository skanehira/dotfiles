return {
  'skanehira/k8s.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
  },
  cmd = {
    'K8s'
  },
  keys = {
    { '<Leader>k', '<cmd>K8s<CR>', desc = 'Kubernetes Dashboard' },
  },
  opts = {
    transparent = true,
  }
}
