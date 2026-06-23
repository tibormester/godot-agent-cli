# Godot Agent CLI

Godot Agent CLI is an agent-facing Godot 4 addon plus a dependency-free Node.js client.

- CLI manual: `cli/README.md`
- Plugin authoring guide: `cli/docs/PLUGINS.md`
- Bundled Codex skills: `skills/`
- Example plugin and demo scene: `res://addons/gdli_plugin_example/demo/main.tscn`

From a project that has this addon installed:

```sh
node addons/godot_agent_cli/cli/bin/gdli.js launch
node addons/godot_agent_cli/cli/bin/gdli.js check
```

When installed as an npm package, use the `gdli` binary directly.
