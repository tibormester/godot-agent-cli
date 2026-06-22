import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const distDir = path.join(repoRoot, 'dist');
const pkg = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
const version = pkg.version;

fs.rmSync(distDir, { recursive: true, force: true });
fs.mkdirSync(distDir, { recursive: true });

console.log(`packaging godot-agent-cli v${version}`);

// 1. npm tarball (offline-safe: just tars the package.json "files" list from the working tree).
execFileSync('npm', ['pack', '--pack-destination', 'dist'], { cwd: repoRoot, shell: true, stdio: 'inherit' });

// 2. Asset Library zip — built from the committed tree with `git archive`, which writes forward-slash
// entries (Godot's installer requires them; PowerShell's Compress-Archive writes backslashes and breaks
// the manual in-editor install). The addon is self-contained (cli/ nested, skills/, LICENSE), so one
// extract drops a ready `addons/godot_agent_cli/` into a project. NOTE: this reflects HEAD — commit the
// release before packaging. (The official Asset Library registry install pulls the GitHub repo archive
// at your tag and gets this same tree; this zip is for GitHub Releases / manual installs.)
const zipPath = path.join(distDir, `godot-agent-cli-${version}.zip`);
execFileSync(
  'git',
  ['archive', '--format=zip', '--prefix=addons/godot_agent_cli/', '-o', zipPath, 'HEAD:addons/godot_agent_cli'],
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
