const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');
const deviceId = process.argv[2] || 'emulator-5554';
if (!/^[a-zA-Z0-9._:-]+$/.test(deviceId)) {
  throw new Error(`Identificador de dispositivo inválido: ${deviceId}`);
}
const isWindows = process.platform === 'win32';
const flutterCommand = isWindows ? process.env.ComSpec || 'cmd.exe' : 'flutter';
const flutterArguments = isWindows
  ? ['/d', '/s', '/c', `flutter run --machine -d ${deviceId}`]
  : ['run', '--machine', '-d', deviceId];

let appId;
let commandId = 0;
let reloadTimer;
let pendingFullRestart = false;

const flutter = spawn(
  flutterCommand,
  flutterArguments,
  {
    cwd: projectRoot,
    env: process.env,
    stdio: ['pipe', 'pipe', 'pipe'],
  },
);

function send(method, params) {
  if (!flutter.stdin.writable) return;
  flutter.stdin.write(`${JSON.stringify([{ id: ++commandId, method, params }])}\n`);
}

function scheduleReload(fullRestart, changedPath) {
  pendingFullRestart ||= fullRestart;
  clearTimeout(reloadTimer);
  reloadTimer = setTimeout(() => {
    if (!appId) {
      console.log(`[sync] Cambio detectado; se aplicará cuando la app termine de iniciar: ${changedPath}`);
      return;
    }
    const restart = pendingFullRestart;
    pendingFullRestart = false;
    console.log(`[sync] ${restart ? 'Hot restart' : 'Hot reload'}: ${changedPath}`);
    send('app.restart', {
      appId,
      fullRestart: restart,
      pause: false,
      reason: 'HomeWallet source change',
      debounce: true,
    });
  }, 500);
}

function watch(relativePath, fullRestart = false) {
  const target = path.join(projectRoot, relativePath);
  if (!fs.existsSync(target)) return;
  fs.watch(target, { recursive: fs.statSync(target).isDirectory() }, (_event, filename) => {
    if (!filename || filename.includes('.dart_tool') || filename.includes('build')) return;
    scheduleReload(fullRestart, path.join(relativePath, filename));
  });
}

let stdoutBuffer = '';
flutter.stdout.setEncoding('utf8');
flutter.stdout.on('data', (chunk) => {
  stdoutBuffer += chunk;
  const lines = stdoutBuffer.split(/\r?\n/);
  stdoutBuffer = lines.pop() || '';
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const messages = JSON.parse(line);
      for (const message of messages) {
        if (message.event === 'app.start') {
          appId = message.params.appId;
          console.log(`[sync] HomeWallet iniciada en ${deviceId}. Sincronización automática activa.`);
        } else if (message.event === 'app.stop') {
          appId = undefined;
        } else if (message.event === 'app.log') {
          console.log(message.params.log || '');
        } else if (message.event === 'app.progress' && message.params.finished === false) {
          console.log(`[flutter] ${message.params.message || message.params.progressId}`);
        } else if (message.error) {
          console.error(`[flutter] ${message.error}`);
        }
      }
    } catch {
      console.log(line);
    }
  }
});

flutter.stderr.pipe(process.stderr);
flutter.on('error', (error) => {
  console.error(`[sync] No se pudo iniciar Flutter: ${error.message}`);
  process.exitCode = 1;
});
flutter.on('exit', (code) => {
  console.log(`[sync] Flutter terminó con código ${code}.`);
  process.exitCode = code || 0;
});

watch('lib', false);
watch('assets', true);
watch('pubspec.yaml', true);

function shutdown() {
  send('app.stop', { appId });
  setTimeout(() => flutter.kill(), 500);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
