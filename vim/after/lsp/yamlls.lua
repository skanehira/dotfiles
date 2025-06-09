return {
  settings = {
    yaml = {
      schemas = {
        ['https://json.schemastore.org/github-workflow.json'] = "/.github/workflows/*",
        ['https://json.schemastore.org/github-action.json'] = '/.github/actions/*',
        ['https://json.schemastore.org/dependabot-2.0.json'] = '/.github/dependabot.y*ml',
        ['https://goreleaser.com/static/schema.json'] = '.goreleaser.*',
        ['https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json'] =
        "*compose.y*ml"
      }
    }
  }
}
