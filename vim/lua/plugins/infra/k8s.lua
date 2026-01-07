return {
  dir = '~/dev/github.com/skanehira/k8s.nvim',
  dev = true,
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
