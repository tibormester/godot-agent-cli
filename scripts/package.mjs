import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

execFileSync(
  process.execPath,
  [path.join(repoRoot, 'addons', 'godot_agent_cli', 'scripts', 'package.mjs')],
  { cwd: repoRoot, stdio: 'inherit' }
);
