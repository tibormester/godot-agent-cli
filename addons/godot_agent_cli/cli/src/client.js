const net = require('net');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const HOST = '127.0.0.1';
const PORT_GAME = parseInt(process.env.GDLI_PORT_GAME, 10) || 9900;
const PORT_EDITOR = parseInt(process.env.GDLI_PORT_EDITOR, 10) || 9910;

function probe(port, host = HOST, timeout = 600) {
  return new Promise((resolve) => {
    const sock = new net.Socket();
    let done = false;
    const finish = (up) => {
      if (done) return;
      done = true;
      sock.destroy();
      resolve(up);
    };
    sock.setTimeout(timeout);
    sock.once('connect', () => finish(true));
    sock.once('timeout', () => finish(false));
    sock.once('error', () => finish(false));
    sock.connect(port, host);
  });
}

function send(port, cmd, params = {}, host = HOST) {
  return new Promise((resolve, reject) => {
    const id = crypto.randomUUID();
    const sock = new net.Socket();
    let buffer = '';
    let settled = false;
    const fail = (e) => {
      if (settled) return;
      settled = true;
      sock.destroy();
      reject(e);
    };
    sock.setTimeout(30000);
    sock.once('error', fail);
    sock.once('timeout', () => fail(new Error('request timed out')));
    sock.connect(port, host, () => {
      sock.write(JSON.stringify({ id, cmd, params }) + '\n');
    });
    sock.on('data', (chunk) => {
      buffer += chunk.toString('utf8');
      const idx = buffer.indexOf('\n');
      if (idx === -1) return;
      const line = buffer.slice(0, idx);
      settled = true;
      sock.destroy();
      let msg;
      try {
        msg = JSON.parse(line);
      } catch (e) {
        return reject(new Error('invalid response from server: ' + line));
      }
      resolve(msg);
    });
    sock.once('close', () => {
      if (!settled) fail(new Error('connection closed before response'));
    });
  });
}

// Walk up from cwd to the dir containing project.godot (the Godot project root).
function projectRoot(cwd) {
  let dir = path.resolve(cwd || process.cwd());
  while (true) {
    if (fs.existsSync(path.join(dir, 'project.godot'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return path.resolve(cwd || process.cwd());
    dir = parent;
  }
}

// Resolve this project's game/editor ports from the per-mode port files the server writes,
// falling back to the fixed defaults when no file is present.
function resolvePorts(cwd) {
  const root = projectRoot(cwd);
  const read = (mode, fallback) => {
    try {
      const v = parseInt(fs.readFileSync(path.join(root, '.gdli', `${mode}.port`), 'utf8').trim(), 10);
      return Number.isInteger(v) && v > 0 ? v : fallback;
    } catch (e) {
      return fallback;
    }
  };
  return { game: read('game', PORT_GAME), editor: read('editor', PORT_EDITOR) };
}

module.exports = { probe, send, HOST, PORT_GAME, PORT_EDITOR, projectRoot, resolvePorts };
