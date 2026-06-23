const fs = require('fs');
const path = require('path');
const { projectRoot } = require('./client');

const DEFAULT_TIMEOUT_MS = 30000;
const DEFAULT_WARNING_MS = 0;
const IDLE_FRAME_ALLOWANCE_MS = 34;
const PHYSICS_FRAME_ALLOWANCE_MS = 17;

function timingPath(root) {
  return path.join(root, '.gdli', 'timing.json');
}

function parseDurationMs(value, label) {
  if (value == null || value === '') {
    const e = new Error(`${label} expects a duration like 500ms, 5s, or 2m`);
    e.client = true;
    throw e;
  }
  const raw = String(value).trim().toLowerCase();
  const m = raw.match(/^(\d+(?:\.\d+)?)(ms|s|m)?$/);
  if (!m) {
    const e = new Error(`${label} expects a duration like 500ms, 5s, or 2m`);
    e.client = true;
    throw e;
  }
  const n = Number(m[1]);
  const unit = m[2] || 's';
  const ms = unit === 'm' ? n * 60000 : unit === 's' ? n * 1000 : n;
  if (!Number.isFinite(ms) || ms < 0) {
    const e = new Error(`${label} must be a non-negative duration`);
    e.client = true;
    throw e;
  }
  return Math.round(ms);
}

function loadSessionTiming(cwd) {
  const root = projectRoot(cwd);
  try {
    const parsed = JSON.parse(fs.readFileSync(timingPath(root), 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (e) {
    return {};
  }
}

function saveSessionTiming(cwd, mode, timing) {
  const root = projectRoot(cwd);
  const file = timingPath(root);
  const current = loadSessionTiming(root);
  current[mode] = {
    timeoutMs: timing.timeoutMs,
    warningMs: timing.warningMs,
  };
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(current, null, 2) + '\n');
}

function targetMode(opts, target) {
  if (opts.editor || target === 'editor') return 'editor';
  if (opts.game || target === 'game') return 'game';
  return null;
}

function resolveTiming(opts, target) {
  const session = loadSessionTiming(opts.cwd);
  const mode = targetMode(opts, target);
  const defaults = mode && session[mode] ? session[mode] : {};
  return {
    timeoutMs: opts.timeoutMs ?? defaults.timeoutMs ?? DEFAULT_TIMEOUT_MS,
    warningMs: opts.warningMs ?? defaults.warningMs ?? DEFAULT_WARNING_MS,
  };
}

function numberAfter(tokens, flag, coerce) {
  let value = null;
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] !== flag) continue;
    if (i + 1 >= tokens.length) continue;
    const parsed = coerce(String(tokens[i + 1]));
    if (Number.isFinite(parsed) && parsed >= 0) value = parsed;
  }
  return value;
}

function hasSettleConsumer(tokens) {
  return tokens.includes('--mark') || tokens.includes('--diff');
}

function settleAllowanceMs(tokens = []) {
  if (!Array.isArray(tokens) || !hasSettleConsumer(tokens)) return 0;
  const seconds = numberAfter(tokens, '--time', Number);
  if (seconds != null) return Math.round(seconds * 1000);
  const physicsFrames = numberAfter(tokens, '--physics', (v) => parseInt(v, 10));
  if (physicsFrames != null) return physicsFrames * PHYSICS_FRAME_ALLOWANCE_MS;
  const idleFrames = numberAfter(tokens, '--ticks', (v) => parseInt(v, 10));
  if (idleFrames != null) return idleFrames * IDLE_FRAME_ALLOWANCE_MS;
  return 0;
}

function withAllowance(base, allowanceMs) {
  return {
    timeoutMs: base.timeoutMs + allowanceMs,
    warningMs: base.warningMs > 0 ? base.warningMs + allowanceMs : 0,
    baseTimeoutMs: base.timeoutMs,
    baseWarningMs: base.warningMs,
    settleAllowanceMs: allowanceMs,
  };
}

function warningHandler(opts) {
  return (elapsedMs, info = {}) => {
    if (!opts.json) {
      const allowance = Number(info.settleAllowanceMs || 0);
      const suffix = allowance > 0 ? ` (includes ${allowance}ms requested settle allowance)` : '';
      process.stderr.write(`warning: command still running after ${Math.round(elapsedMs)}ms${suffix}\n`);
    }
  };
}

function sendOptions(opts, target, tokens = []) {
  const base = resolveTiming(opts, target);
  const timing = withAllowance(base, settleAllowanceMs(tokens));
  return {
    ...timing,
    onWarning: warningHandler(opts),
  };
}

module.exports = {
  DEFAULT_TIMEOUT_MS,
  DEFAULT_WARNING_MS,
  IDLE_FRAME_ALLOWANCE_MS,
  PHYSICS_FRAME_ALLOWANCE_MS,
  parseDurationMs,
  resolveTiming,
  saveSessionTiming,
  sendOptions,
  settleAllowanceMs,
};
