const fs = require('fs');
const path = require('path');

// The CLI ships nested inside the addon (this module is addons/godot_agent_cli/cli/src/install.js),
// so the addon to copy is two levels up. One source of truth, identical for the npm and Asset
// Library install paths.
const SRC_ADDON = path.resolve(__dirname, '..', '..');

function install(opts, rest) {
  const dir = (rest && rest[0]) || opts.cwd || process.cwd();
  if (!fs.existsSync(SRC_ADDON)) {
    return { line: `bundled addon not found at ${SRC_ADDON}`, ok: false };
  }
  const dest = path.resolve(dir, 'addons', 'godot_agent_cli');
  // Guard the degenerate case (e.g. `gdli install .` from inside this repo): copying the bundled
  // addon onto itself would recurse. Nothing to do — it's already there.
  if (dest === SRC_ADDON) {
    return { line: `addon already present at ${dest} (source == destination)`, ok: true, dest, overwrote: false };
  }
  const existed = fs.existsSync(dest);
  fs.cpSync(SRC_ADDON, dest, { recursive: true });
  const lines = [
    `${existed ? 'overwrote' : 'copied'} addon -> ${dest}`,
    'Now enable the plugin in Godot: Project > Project Settings > Plugins > Godot Agent CLI.',
  ];
  return { line: lines.join('\n'), ok: true, dest, overwrote: existed };
}

module.exports = { install, SRC_ADDON };
