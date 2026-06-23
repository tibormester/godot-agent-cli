import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

const addonRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(addonRoot, '..', '..');
const distDir = path.join(addonRoot, 'dist');
const pkg = JSON.parse(fs.readFileSync(path.join(addonRoot, 'package.json'), 'utf8'));
const version = pkg.version;

fs.rmSync(distDir, { recursive: true, force: true });
fs.mkdirSync(distDir, { recursive: true });

console.log(`packaging godot-agent-cli v${version}`);

// 1. npm tarball. The npm package is rooted at addons/godot_agent_cli so the
// CLI can still copy the bundled addon from cli/src/install.js.
execFileSync('npm', ['pack', '--pack-destination', 'dist'], { cwd: addonRoot, shell: true, stdio: 'inherit' });

// 2. Manual Asset Library zip. It includes the core addon plus the optional
// example addon, and uses git archive so paths use forward slashes.
//
// This reflects HEAD. Commit the release before packaging.
const zipPath = path.join(distDir, `godot-agent-cli-${version}.zip`);
execFileSync(
  'git',
  ['archive', '--format=zip', '-o', zipPath, 'HEAD', 'addons/godot_agent_cli', 'addons/gdli_plugin_example'],
  { cwd: repoRoot, stdio: 'inherit' }
);

const artifacts = fs
  .readdirSync(distDir)
  .filter((f) => f.endsWith('.tgz') || f.endsWith('.zip'))
  .map((f) => path.join(distDir, f));

console.log('\nproduced:');
for (const f of artifacts) {
  const kb = (fs.statSync(f).size / 1024).toFixed(1);
  console.log(`  ${f}  (${kb} KB)`);
}
