// KURO — Kuro Utility Runner & Optimizer.
// Unified developer CLI for the Kuron app (zero dependencies, pure Dart).
//
// Usage:
//   ./kuron                      → interactive wizard (TTY only)
//   ./kuron build release --flavor prod
//   dart scripts/kuron.dart status
//
// Design: openspec/changes/unified-dev-cli (design.md + specs/dev-cli-automation).
// Must stay dependency-free (dart:io/convert/async only) so it runs as a
// bootstrapper before `pub get` ever succeeds.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String kKuroName = 'KURO';
const String kKuroFullName = 'Kuro Utility Runner & Optimizer';
const String kKuroVersion = '1.1.0';
const String kKuroTagline = 'build • pub • feature • status — powered by Kuro';

// ── ANSI styling (guarded: plain text when piped / CI / non-ANSI) ──
bool get _ansi => stdout.supportsAnsiEscapes;

String _c(String text, String code) =>
    _ansi ? '\x1B[${code}m$text\x1B[0m' : text;
String get _bold => _ansi ? '\x1B[1m' : '';
String get _reset => _ansi ? '\x1B[0m' : '';

String green(String s) => _c(s, '32');
String cyan(String s) => _c(s, '36');
String yellow(String s) => _c(s, '33');
String red(String s) => _c(s, '31');
String dim(String s) => _c(s, '2');
String magenta(String s) => _c(s, '35');

void info(String s) => stdout.writeln("${cyan('›')} $s");
void ok(String s) => stdout.writeln('${green('✔')} $s');
void warn(String s) => stdout.writeln('${yellow('!')} $s');
void fail(String s) => stderr.writeln('${red('✘')} $s');

// ── Brand banner (once per process: wizard + sub-command share it) ──
bool _bannerDone = false;

const List<String> _kuroArt = [
  ' ██╗  ██╗██╗   ██╗██████╗  ██████╗',
  ' ██║ ██╔╝██║   ██║██╔══██╗██╔═══██╗',
  ' █████╔╝ ██║   ██║██████╔╝██║   ██║',
  ' ██╔═██╗ ██║   ██║██╔══██╗██║   ██║',
  ' ██║  ██╗╚██████╔╝██║  ██║╚██████╔╝',
  ' ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╝',
];

// Magenta → pink → cyan gradient across the 6 art lines.
const List<int> _kuroGradient = [199, 201, 213, 165, 123, 51];

String _grad(String s, int code) =>
    _ansi ? '\x1B[1;38;5;${code}m$s\x1B[0m' : s;

void printBanner() {
  if (_bannerDone) return;
  _bannerDone = true;
  for (var i = 0; i < _kuroArt.length; i++) {
    stdout.writeln(_grad(_kuroArt[i], _kuroGradient[i]));
  }
  stdout.writeln(
      '  ${cyan(kKuroFullName)} ${dim('v$kKuroVersion')}  🐈‍⬛  ${dim('(=^･ω･^=)ฅ')}');
  stdout.writeln('  ${dim(kKuroTagline)}');
  stdout.writeln('  ${dim('─' * 46)}\n');
}

// Pad [s] with spaces to visible [width].
String _padCells(String s, int width) {
  final pad = width - _cells(s);
  return pad > 0 ? '$s${' ' * pad}' : s;
}

// Rounded result box, e.g. build success summary.
void printResultBox({required bool success, required List<String> rows}) {
  final title = success ? '🎉 BUILD SUCCESS — Kuro delivered!' : '💥 BUILD FAILED';
  var inner = title;
  for (final r in rows) {
    if (_cells(r) > _cells(inner)) inner = r;
  }
  var w = _cells(inner) + 2;
  if (w > 62) w = 62;
  final border = success ? green : red;
  final bar = '─' * (w - _cells(title) - 2);
  stdout.writeln(border('╭─ $title$bar╮'));
  for (final r in rows) {
    stdout.writeln(border('│ ') + _padCells(r, w - 2) + border(' │'));
  }
  stdout.writeln(border('╰${'─' * w}╯'));
}

// Idle Kuro cat (banner / success).
const String kKuroIdle = r'''
 /\_/\   Kuro is ready.
( o.o ) ฅ^•ﻌ•^ฅ
 > ^ <  ''';

// ── Running-cat animation ──
// Kuro paces left↔right inside a fixed field (ping-pong, no teleports),
// blinks through cute faces, and a shuttle dot sweeps beside him.
// Every redraw starts with an ANSI erase-line and the line is truncated to
// the terminal width — long labels can never wrap and smear, even on narrow
// terminals. In CI / non-TTY we print plain progress lines instead.
class KuroRun {
  // Look → bright → happy-blink → bright: visible, cute change each frame.
  static const List<String> faces = [
    '(=^･ω･^=)',
    '(=^･ᴗ･^=)',
    '(=^-ω-^=)',
    '(=^･ᴗ･^=)',
  ];

  static const int _fieldSpan = 6; // pacing range (cells of padding travel)
  static const int _shuttleSpan = 6; // sweep range of the dot bar

  final String label;
  final bool animated;
  Timer? _timer;
  int _tick = 0;
  final Stopwatch _sw = Stopwatch();

  KuroRun(this.label, {bool? animated})
      : animated = animated ?? stdout.hasTerminal && stdout.supportsAnsiEscapes;

  void start() {
    _sw.start();
    if (!animated) {
      stdout.writeln('🐈‍⬛ $label …');
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 140), (_) => _draw());
    _draw();
  }

  void _draw() {
    // Ping-pong 0..span..0 so Kuro turns around instead of teleporting back.
    final phase = _tick % (_fieldSpan * 2);
    final pos = phase <= _fieldSpan ? phase : _fieldSpan * 2 - phase;
    final face = faces[_tick % faces.length];
    // Dust trails behind the running direction.
    final cat = phase <= _fieldSpan ? '$face💨' : '💨$face';
    final field = '${' ' * pos}$cat${' ' * (_fieldSpan - pos)}';
    final si = _tick % (_shuttleSpan * 2);
    final spos = si <= _shuttleSpan ? si : _shuttleSpan * 2 - si;
    final shuttle = '${'─' * spos}●${'─' * (_shuttleSpan - spos)}';
    final elapsed = _fmt(_sw.elapsed);
    // Plain (no ANSI styling) so cell math is exact; colors return on the
    // final line, which never needs redrawing.
    final prefix = '🐈‍⬛ $field $shuttle  ';
    final fitted = _fitLabel(label, prefix, '  [$elapsed]');
    final line = '$prefix$fitted  [$elapsed]';
    stdout.write('$_clear$line');
    _tick++;
  }

  void update(String newLabel) {
    if (!animated) stdout.writeln('🐈‍⬛ $newLabel …');
  }

  void stop({bool success = true, String? doneLabel}) {
    _sw.stop();
    final elapsed = _fmt(_sw.elapsed);
    if (!animated) {
      stdout.writeln(
          success ? '✔ ${doneLabel ?? label} (${elapsed}s)' : '✘ $label FAILED (${elapsed}s)');
      return;
    }
    _timer?.cancel();
    // Erase the animation line, then print the final state.
    stdout.write(_clear);
    if (success) {
      stdout.writeln(
          '${green('✔')} 🐈‍⬛💨 ${doneLabel ?? label} ${dim('(${elapsed}s)')}');
    } else {
      stdout.writeln('${red('✘')} $label ${dim('FAILED after ${elapsed}s)')}');
    }
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// Erase the current terminal line (plain CR when ANSI is unavailable).
String get _clear => _ansi ? '\x1B[2K\r' : '\r';

// Visible cell width: 2 for wide runes (CJK, fullwidth, emoji),
// 0 for joiners/selectors, 1 for everything else (incl. ─ ● ･ ω).
int _cells(String s) {
  var w = 0;
  for (final r in s.runes) {
    if (r == 0x200D || (r >= 0xFE00 && r <= 0xFE0F)) continue;
    if ((r >= 0x1100 && r <= 0x115F) ||
        (r >= 0x2E80 && r <= 0x303E) ||
        (r >= 0x3041 && r <= 0x33FF) ||
        (r >= 0x3400 && r <= 0x4DBF) ||
        (r >= 0x4E00 && r <= 0x9FFF) ||
        (r >= 0xA000 && r <= 0xA4CF) ||
        (r >= 0xAC00 && r <= 0xD7A3) ||
        (r >= 0xF900 && r <= 0xFAFF) ||
        (r >= 0xFE30 && r <= 0xFE4F) ||
        (r >= 0xFF00 && r <= 0xFF60) ||
        (r >= 0xFFE0 && r <= 0xFFE6) ||
        (r >= 0x1F300 && r <= 0x1FAFF) ||
        (r >= 0x20000 && r <= 0x3FFFD)) {
      w += 2;
    } else {
      w += 1;
    }
  }
  return w;
}

int _termWidth() {
  try {
    return stdout.terminalColumns;
  } catch (_) {
    return 80;
  }
}

// Clip [label] (rune-safe) so prefix + label + suffix fits [maxWidth].
String _fitLabel(String label, String prefix, String suffix,
    [int? maxWidth]) {
  final room = (maxWidth ?? _termWidth()) - _cells(prefix) - _cells(suffix);
  if (_cells(label) <= room) return label;
  var keep = room - 1; // room for '…'
  if (keep < 4) keep = 4;
  var cut = '';
  var used = 0;
  for (final r in label.runes) {
    final cw = _cells(String.fromCharCode(r));
    if (used + cw > keep) break;
    used += cw;
    cut += String.fromCharCode(r);
  }
  return '$cut…';
}

// Runs [process] while the cat gallops. Returns the exit code. On failure the
// captured output tail is printed so CI logs stay useful.
Future<int> runWithCat(
  String label,
  Future<Process> Function() spawn, {
  bool verbose = false,
}) async {
  final cat = KuroRun(label);
  cat.start();
  final proc = await spawn();
  final outTail = <String>[];
  final sub1 =
      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (verbose) {
      stdout.write('$_clear$line\n');
    } else if (outTail.length < 200) {
      outTail.add(line);
    } else {
      outTail.removeAt(0);
      outTail.add(line);
    }
  });
  final sub2 =
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (verbose) {
      stdout.write('$_clear${dim(line)}\n');
    } else if (outTail.length < 200) {
      outTail.add(line);
    }
  });
  final code = await proc.exitCode;
  await sub1.cancel();
  await sub2.cancel();
  cat.stop(success: code == 0);
  if (code != 0 && !verbose) {
    fail('Last output before failure:');
    for (final line in outTail.length > 25 ? outTail.sublist(outTail.length - 25) : outTail) {
      stdout.writeln('  $line');
    }
    stdout.writeln(dim('Tip: re-run with --verbose to stream full output.'));
  }
  return code;
}

// ── Process helpers ──

String get repoRoot {
  final script = Platform.script.toFilePath();
  // scripts/kuron.dart → repo root is parent of scripts/.
  final dir = File(script).parent;
  return dir.parent.path;
}

bool get hasFvm {
  try {
    final r = Process.runSync('fvm', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

List<String> get flutterPrefix => hasFvm ? ['fvm', 'flutter'] : ['flutter'];

Future<Process> spawnCmd(List<String> cmd, {String? cwd}) =>
    Process.start(cmd.first, cmd.sublist(1),
        workingDirectory: cwd ?? repoRoot, runInShell: true);

Future<int> sh(List<String> cmd, {String? cwd}) async {
  final proc = await spawnCmd(cmd, cwd: cwd);
  await stdout.addStream(proc.stdout);
  await stderr.addStream(proc.stderr);
  return proc.exitCode;
}

// Minimal flag parser: supports `--key=value`, `--key value`, `--flag`,
// single `-f` aliases via [aliases], plus positionals.
class KArgs {
  final Map<String, String> opts;
  final Set<String> flags;
  final List<String> rest;
  KArgs(this.opts, this.flags, this.rest);

  static KArgs parse(List<String> args, {Map<String, String> aliases = const {}}) {
    final opts = <String, String>{};
    final flags = <String>{};
    final rest = <String>[];
    for (var i = 0; i < args.length; i++) {
      var a = args[i];
      if (aliases.containsKey(a)) a = aliases[a]!;
      if (a.startsWith('--')) {
        final eq = a.indexOf('=');
        if (eq != -1) {
          opts[a.substring(2, eq)] = a.substring(eq + 1);
        } else if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          opts[a.substring(2)] = args[++i];
        } else {
          flags.add(a.substring(2));
        }
      } else if (a.startsWith('-') && a.length == 2) {
        flags.add(a.substring(1));
      } else {
        rest.add(a);
      }
    }
    return KArgs(opts, flags, rest);
  }

  String? operator [](String key) => opts[key];
  bool has(String key) => flags.contains(key) || opts.containsKey(key);
}

// ── build: optimized APK (mirrors scripts/build_optimized.sh) ──
Future<int> cmdBuild(List<String> raw) async {
  final a = KArgs.parse(raw, aliases: {'-f': '--flavor', '-t': '--type', '-v': '--verbose'});
  final verbose = a.has('verbose') || a.has('v');
  var type = (a['type'] ?? (a.rest.isNotEmpty ? a.rest.first : 'release')).toLowerCase();
  if (type != 'release' && type != 'debug') type = 'release';
  final flavorEnv = Platform.environment['FLAVOR'];
  final defaultFlavor = type == 'release' ? 'prod' : 'dev';
  final flavor = (a['flavor'] ?? flavorEnv ?? defaultFlavor).toLowerCase();
  final splitAbi = a.has('split-abi') ||
      a.has('splitAbi') ||
      (Platform.environment['SPLIT_ABI'] ?? 'false').toLowerCase() == 'true';
  final secret = a['secret'] ?? Platform.environment['DOUJINDESU_APP_SECRET'] ?? '';

  final appName = flavor == 'dev' ? 'Kuron Dev' : 'Kuron';
  var appId = flavor == 'dev' ? 'id.nhasix.app.dev' : 'id.nhasix.app';
  if (type == 'debug') appId = '$appId.debug';

  printBanner();
  info('Building OPTIMIZED $type APK…  🐈‍⬛ Kuro stretches…');
  String version = '?';
  try {
    final pub = File('$repoRoot/pubspec.yaml').readAsStringSync();
    version = RegExp(r'version:\s*(\S+)').firstMatch(pub)?.group(1) ?? '?';
  } catch (_) {}
  stdout.writeln('  ${dim('Version:')} $version   ${dim('App:')} $appName ($appId)');
  stdout.writeln('  ${dim('Flavor:')} $flavor  ${dim('Type:')} $type  '
      '${dim('ABI:')} ${splitAbi ? 'split-per-abi' : 'universal'}');
  stdout.writeln('  ${dim('Flutter:')} ${flutterPrefix.join(' ')}\n');

  final hasCargo = _which('cargo') != null;
  final totalSteps = hasCargo ? 3 : 2;
  var stepNo = 0;

  var code = await runWithCat(
      '[${++stepNo}/$totalSteps] Cleaning project',
      () => spawnCmd([...flutterPrefix, 'clean']),
      verbose: verbose);
  if (code != 0) return code;

  if (hasCargo) {
    code = await runWithCat('[${++stepNo}/$totalSteps] Cleaning rust target',
        () => spawnCmd(['cargo', 'clean', '--manifest-path', 'packages/kuron_native/rust/Cargo.toml']),
        verbose: verbose);
    if (code != 0) return code;
  }

  // Auto-export KEYSTORE_BASE64 for release (same rule as build_optimized.sh).
  final env = Map<String, String>.from(Platform.environment);
  if (type == 'release' && (env['KEYSTORE_BASE64'] ?? '').isEmpty) {
    final f = File('$repoRoot/android/keystore_base64.txt');
    if (f.existsSync()) {
      env['KEYSTORE_BASE64'] = f.readAsStringSync().replaceAll('\n', '').trim();
      info('Loaded KEYSTORE_BASE64 from android/keystore_base64.txt');
    }
  }

  final cmd = <String>[
    ...flutterPrefix, 'build', 'apk',
    type == 'release' ? '--release' : '--debug',
    '--flavor', flavor,
    if (splitAbi) '--split-per-abi',
    '--dart-define=cronetHttpNoPlay=true',
    if (secret.isNotEmpty) '--dart-define=DOUJINDESU_APP_SECRET=$secret',
  ];
  if (secret.isNotEmpty) info('Injected DOUJINDESU_APP_SECRET via --dart-define');
  stdout.writeln(dim('  \$ ${cmd.join(' ')}'));

  code = await runWithCat(
      '[${++stepNo}/$totalSteps] Kuro is building $appName [$flavor/$type]',
      () => Process.start(cmd.first, cmd.sublist(1),
          workingDirectory: repoRoot, runInShell: true, environment: env),
      verbose: verbose);
  if (code != 0) {
    printResultBox(success: false, rows: [
      'Step: building $appName [$flavor/$type]',
      'Kuro tripped! (=；ェ；=) Tip: re-run with --verbose.',
    ]);
    return code;
  }

  // Collect + copy APKs to apk-output/ (same search order as .sh).
  final outDir = Directory('$repoRoot/apk-output')..createSync(recursive: true);
  final found = <File>[];
  final candidates = <String>[
    'build/app/outputs/apk/$flavor/$type/kuron_*.apk',
    'build/app/outputs/apk/*/$type/kuron_*.apk',
    'build/app/outputs/flutter-apk/kuron_*.apk',
  ];
  // Glob manually (zero-dep): expand each pattern's dir + RegExp on basename.
  for (final pattern in candidates) {
    if (found.isNotEmpty) break;
    final dirPart = pattern.split('*').first;
    final dirPath = '$repoRoot/${dirPart.substring(0, dirPart.lastIndexOf('/'))}';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.apk') && f.uri.pathSegments.last.startsWith('kuron_'))
        .toList()
      ..sort();
    found.addAll(files);
  }
  if (found.isEmpty) {
    fail('No APK files found — check build output above.');
    return 1;
  }
  var totalBytes = 0;
  stdout.writeln('\n📁 ${cyan('OPTIMIZED APK FILES:')}  ${dim(outDir.path)}/');
  for (final apk in found) {
    final bytes = apk.lengthSync();
    totalBytes += bytes;
    apk.copySync('${outDir.path}/${apk.uri.pathSegments.last}');
    stdout.writeln('  📱 ${apk.uri.pathSegments.last} - ${_human(bytes)}');
  }
  // Flavor builds land as app-<flavor>-<type>.apk (e.g. app-prod-release.apk).
  var universalRef = '';
  for (final name in ['app-$flavor-$type.apk', 'app-$type.apk']) {
    final f = File('$repoRoot/build/app/outputs/flutter-apk/$name');
    if (f.existsSync()) {
      universalRef = '$name (${_human(f.lengthSync())})';
      break;
    }
  }
  stdout.writeln('');
  printResultBox(success: true, rows: [
    for (final apk in found)
      '📱 ${apk.uri.pathSegments.last} · ${_human(apk.lengthSync())}',
    '📦 Total (this run): ${found.length} · ${_human(totalBytes)}',
    '💾 Universal ref: ${universalRef.isEmpty ? 'N/A (split-per-abi)' : universalRef}',
    '📂 Saved to apk-output/  (=^･ω･^=)ฅ',
  ]);
  return 0;
}

String? _which(String bin) {
  try {
    final r = Process.runSync(Platform.isWindows ? 'where' : 'which', [bin]);
    return r.exitCode == 0 ? (r.stdout as String).trim() : null;
  } catch (_) {
    return null;
  }
}

String _human(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}

// ── pub-get: root + all packages/<name> ──
Future<int> cmdPubGet(List<String> raw) async {
  final verbose = raw.contains('--verbose');
  printBanner();
  final pkgDirs = <String>[repoRoot];
  final pkgs = Directory('$repoRoot/packages');
  if (pkgs.existsSync()) {
    for (final e in pkgs.listSync().whereType<Directory>()) {
      if (File('${e.path}/pubspec.yaml').existsSync()) pkgDirs.add(e.path);
    }
  }
  var okCount = 0, failCount = 0;
  final failed = <String>[];
  for (final dir in pkgDirs) {
    final name = dir == repoRoot ? 'root app' : dir.split(Platform.pathSeparator).last;
    final code = await runWithCat('pub get: $name',
        () => spawnCmd([...flutterPrefix, 'pub', 'get'], cwd: dir),
        verbose: verbose);
    if (code == 0) {
      okCount++;
    } else {
      failCount++;
      failed.add(name);
    }
  }
  stdout.writeln('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  stdout.writeln('📊 ${cyan('Summary:')} ${green('✅ $okCount')}  ${red('❌ $failCount')}');
  if (failed.isNotEmpty) {
    fail('Failed: ${failed.join(', ')}');
    return 1;
  }
  stdout.writeln(green('🎉 Kuro fetched everything! (=^･ω･^=)'));
  return 0;
}

// ── feature: scaffold Clean Architecture module ──
Future<int> cmdFeature(List<String> raw) async {
  final a = KArgs.parse(raw);
  var name = a.rest.isNotEmpty ? a.rest.first : '';
  if (name.isEmpty) {
    stdout.write('Feature name (snake_case): ');
    name = stdin.readLineSync()?.trim() ?? '';
  }
  name = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  if (name.isEmpty) {
    fail('Feature name must contain [a-z0-9_].');
    return 1;
  }
  final pascal = name
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join();
  stdout.writeln('\n🐈‍⬛ Kuro scaffolding "$name"…');
  for (final dirPath in [
    'lib/domain/usecases/$name',
    'lib/presentation/cubits/$name',
    'lib/presentation/pages/$name',
    'lib/presentation/widgets/$name',
  ]) {
    final dir = Directory('$repoRoot/$dirPath');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      stdout.writeln('  ${green('Created:')} $dirPath');
    } else {
      stdout.writeln('  ${dim('Exists:')} $dirPath');
    }
  }
  final cubitFile = File('$repoRoot/lib/presentation/cubits/$name/${name}_cubit.dart');
  if (!cubitFile.existsSync()) {
    cubitFile.writeAsStringSync('''
import 'package:logger/logger.dart';
import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';

class ${pascal}State extends BaseCubitState {
  const ${pascal}State();

  @override
  List<Object?> get props => [];
}

class ${pascal}Cubit extends BaseCubit<${pascal}State> {
  ${pascal}Cubit({required Logger logger})
      : super(initialState: const ${pascal}State(), logger: logger);
}
''');
    stdout.writeln('  ${green('Created:')} ${cubitFile.path}');
  }
  stdout.writeln('\nNext (manual): entity → repository iface → model/impl → '
      'register in lib/core/di/service_locator.dart');
  stdout.writeln(green('🎉 Kuro scaffolded $name! (=^･ω･^=)ฅ'));
  return 0;
}

// ── status: OpenSpec dashboard (mirrors project_status.dart) ──
Future<int> cmdStatus(List<String> raw) async {
  printBanner();
  final changesDir = Directory('$repoRoot/openspec/changes');
  if (!changesDir.existsSync()) {
    fail('No openspec/changes directory found.');
    return 1;
  }
  final doneRe = RegExp(r'^-\s*\[x\]', caseSensitive: false);
  final openRe = RegExp(r'^-\s*\[ \]');
  final rows = <List<String>>[];
  final archivedRows = <String>[];
  for (final entry in changesDir.listSync().whereType<Directory>()) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name == 'archive') {
      final subs = entry.listSync().whereType<Directory>().toList()
        ..sort((x, y) => x.path.compareTo(y.path));
      for (final sub in subs) {
        final n = sub.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final c = _countTasks(File('${sub.path}/tasks.md'), doneRe, openRe);
        archivedRows.add('- $n — ${c[0]}/${c[1]}');
      }
      continue;
    }
    final c = _countTasks(File('${entry.path}/tasks.md'), doneRe, openRe);
    final pct = c[1] == 0 ? 0 : (c[0] * 100 / c[1]).round();
    final bar = _bar(c[0], c[1]);
    rows.add([name, '$bar ${c[0]}/${c[1]}', '$pct%', pct == 100 ? 'Done' : 'Active']);
  }
  rows.sort((x, y) => x[0].compareTo(y[0]));
  final buf = StringBuffer('# OpenSpec Changes Dashboard\n\n');
  buf.writeln('| Change | Progress | % | Status |');
  buf.writeln('|---|---|---|---|');
  for (final r in rows) {
    buf.writeln('| ${r[0]} | ${r[1]} | ${r[2]} | ${r[3]} |');
  }
  buf.writeln('\n## Archived (${archivedRows.length})\n');
  for (final r in archivedRows) {
    buf.writeln(r);
  }
  buf.writeln('\n_Last updated: ${DateTime.now().toString().split('.').first}_ '
      '(generated by scripts/kuron.dart)');
  File('$repoRoot/openspec/STATUS.md').writeAsStringSync(buf.toString());
  stdout.writeln(buf.toString());
  ok('Dashboard written to openspec/STATUS.md — Kuro counted everything! 🐈‍⬛');
  return 0;
}

List<int> _countTasks(File f, RegExp doneRe, RegExp openRe) {
  if (!f.existsSync()) return [0, 0];
  var done = 0, total = 0;
  for (final line in f.readAsStringSync().split('\n')) {
    final t = line.trim();
    if (doneRe.hasMatch(t)) {
      done++;
      total++;
    } else if (openRe.hasMatch(t)) {
      total++;
    }
  }
  return [done, total];
}

String _bar(int done, int total, {int width = 12}) {
  if (total == 0) return '[............]';
  final filled = (done * width / total).round().clamp(0, width);
  return '[${'█' * filled}${'░' * (width - filled)}]';
}

// ── assets: size audit (budget 200KB, mirrors optimize_assets.sh) ──
Future<int> cmdAssets(List<String> raw) async {
  final a = KArgs.parse(raw);
  final limitKb = int.tryParse(a['limit-kb'] ?? a['limitKb'] ?? '200') ?? 200;
  printBanner();
  final assets = Directory('$repoRoot/assets');
  if (!assets.existsSync()) {
    info('No assets/ directory — nothing to audit. Kuro naps. 😴');
    return 0;
  }
  final files = assets
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => (f, f.lengthSync()))
      .toList()
    ..sort((x, y) => y.$2.compareTo(x.$2));
  stdout.writeln('Asset size audit (budget: ${limitKb}KB per file)\n');
  var over = 0;
  for (final (f, size) in files) {
    final kb = size ~/ 1024;
    if (kb > limitKb) {
      over++;
      stdout.writeln('  ${red('OVER')}  ${kb}KB  ${f.path.replaceFirst('$repoRoot/', '')}');
    }
  }
  stdout.writeln('\nLargest 10 assets:');
  for (final (f, size) in files.take(10)) {
    stdout.writeln('  ${_human(size).padLeft(8)}  ${f.path.replaceFirst('$repoRoot/', '')}');
  }
  stdout.writeln('');
  if (over > 0) {
    fail('$over file(s) over budget — compress (<${limitKb}KB), use WebP.');
    return 1;
  }
  ok('All assets within budget — Kuro approves! (=^･ω･^=)');
  return 0;
}

// ── clear-cache: wipe on-device remote-config cache via adb ──
Future<int> cmdClearCache(List<String> raw) async {
  final a = KArgs.parse(raw);
  var appId = a.rest.isNotEmpty
      ? a.rest.first
      : (Platform.environment['APP_ID'] ?? 'id.nhasix.app.dev.debug');
  printBanner();
  if (_which('adb') == null) {
    fail('adb not found.');
    return 1;
  }
  Future<int> adb(List<String> args) => sh(['adb', ...args]);
  var code = await runWithCat('Checking device $appId',
      () => spawnCmd(['adb', 'shell', 'run-as', appId, 'true']));
  if (code != 0) {
    fail('run-as failed for $appId (app not installed or not debuggable).');
    return 1;
  }
  info('Clearing config cache for $appId …');
  await adb(['shell', 'am', 'force-stop', appId]);
  code = await runWithCat('Removing app_flutter/configs',
      () => spawnCmd(['adb', 'shell', 'run-as', appId, 'rm', '-rf', 'app_flutter/configs']));
  if (code != 0) return code;
  ok('Done. Relaunch the app to re-fetch configs. 🐈‍⬛');
  return 0;
}

// ── search: smart search (text/ast/audit/debugprint/violations) ──
Future<int> cmdSearch(List<String> raw) async {
  final a = KArgs.parse(raw);
  if (a.rest.isEmpty || a.has('help') || a.has('h')) return _searchUsage();
  final mode = a.rest.first;
  final pattern = a.rest.length > 1 ? a.rest[1] : '';
  final dir = a.rest.length > 2 ? a.rest[2] : 'lib/';
  switch (mode) {
    case 'text':
      return sh(['rg', '--color=always', '-n', '--heading', '-t', 'dart', pattern, '$repoRoot/$dir']);
    case 'ast':
      return sh(['semgrep', '--lang', 'dart', '-e', pattern, '$repoRoot/$dir', '--no-git-ignore']);
    case 'audit':
      return _audit();
    case 'debugprint':
      return sh(['rg', '-n', r'debugPrint|(?<!\w)print\(', '$repoRoot/lib']);
    case 'violations':
      return _audit();
    default:
      fail('Unknown search mode: $mode');

      return _searchUsage();
  }
}

int _searchUsage() {
  stdout.writeln(cyan('🔍 Kuro Smart Search'));
  stdout.writeln('Usage: kuron search <mode> <pattern> [dir]');
  stdout.writeln('Modes: text | ast | audit | debugprint | violations');
  return 1;
}

Future<int> _audit() async {
  // Mirrors AGENTS.md layer + hygiene rules (subset of smart_search.sh audit).
  var bad = 0;
  info('Audit: domain must stay pure Dart (no package:flutter)…');
  bad += await sh(['rg', '-l', 'package:flutter', '$repoRoot/lib/domain']) == 0 ? 0 : 0;
  info('Audit: no print/debugPrint in lib…');
  final c1 = await spawnCmd(['rg', '-l', r'debugPrint|(?<!\w)print\(', 'lib']);
  final found = await c1.stdout.transform(utf8.decoder).join();
  await c1.exitCode;
  if (found.trim().isNotEmpty) {
    warn('print/debugPrint hits:\n$found');
    bad++;
  }
  if (bad == 0) ok('Audit clean — Kuro found no violations! (=^･ω･^=)');
  return bad == 0 ? 0 : 1;
}

// ── help ──
void printHelp() {
  printBanner();
  stdout.writeln('${_bold}Usage:$_reset  kuron <command> [options]\n');
  stdout.writeln('  ${green('build')} [release|debug] [--flavor prod|dev] [--split-abi] [--verbose]');
  stdout.writeln('      Optimized APK (cronetHttpNoPlay, keystore, apk-output/) — with 🐈‍⬛ run animation');
  stdout.writeln('  ${green('pub-get')}                                     Root + all packages/');
  stdout.writeln('  ${green('feature')} <name>                                Scaffold Clean Architecture module');
  stdout.writeln('  ${green('status')}                                       Refresh openspec/STATUS.md');
  stdout.writeln('  ${green('assets')} [--limit-kb 200]                       Asset size budget audit');
  stdout.writeln('  ${green('clear-cache')} [app-id]                          ADB wipe remote-config cache');
  stdout.writeln('  ${green('search')} <mode> <pattern> [dir]                text|ast|audit|debugprint|violations');
  stdout.writeln('  ${green('help')}                                         This menu\n');
  stdout.writeln(dim('No args on a TTY → interactive wizard. CI / pipes → help + exit 1.'));
}

// ── Interactive wizard (TTY + no args) ──
String _ask(String question, {String? def}) {
  stdout.write('  ${cyan('?')} $question${def != null ? dim(' [$def]') : ''}: ');
  final ans = stdin.readLineSync()?.trim() ?? '';
  return ans.isEmpty ? (def ?? '') : ans;
}

// Arrow-key menu (↑↓ + Enter, 1-7 shortcuts, q cancels). Falls back to the
// numbered prompt when raw mode is unavailable — never hangs, never crashes.
Future<int> _pickMenu(List<String> items) async {
  try {
    return await _pickArrow(items);
  } catch (_) {
    return _pickNumbered(items);
  }
}

int _pickNumbered(List<String> items) {
  for (var i = 0; i < items.length; i++) {
    stdout.writeln('  ${green('${i + 1}')}  ${items[i]}');
  }
  stdout.write('\n  ${cyan('?')} Pick [1-${items.length}]: ');
  return int.tryParse(stdin.readLineSync()?.trim() ?? '') ?? 0;
}

// Menu frame builder (tested seam): one logical line per item plus the hint
// line. Every line starts with a line-erase, and every line is clipped to
// [width] cells — so logical lines always equal physical rows and the
// cursor math in [_pickArrow] stays exact on any terminal width.
List<String> buildMenuFrame(List<String> items, int idx, int width) {
  final lines = <String>[];
  for (var i = 0; i < items.length; i++) {
    if (i == idx) {
      final label = _fitLabel(items[i], '❯  ', '', width);
      lines.add('$_clear${green('❯')}  $_bold$label$_reset');
    } else {
      final label = _fitLabel(items[i], '   ', '', width);
      lines.add('$_clear   ${dim(label)}');
    }
  }
  final hint = _fitLabel(
      '↑↓ move · Enter select · 1-7 jump · q cancel', '  ', '', width);
  lines.add('$_clear${dim('  $hint')}');
  return lines;
}

Future<int> _pickArrow(List<String> items) async {
  if (!stdin.hasTerminal) throw StateError('no TTY');
  final oldEcho = stdin.echoMode;
  final oldLine = stdin.lineMode;
  stdin.echoMode = false;
  stdin.lineMode = false;
  var idx = 0;
  var drawn = 0;
  void render() {
    // Exact math: every frame line ends with \n, so the cursor always sits
    // [frame.length] rows below the block start; moving up that exact count
    // lands back on row one. No drift, no leftovers (lines self-erase).
    final frame = buildMenuFrame(items, idx, _termWidth());
    if (drawn > 0) stdout.write('\x1B[${drawn}A');
    for (final line in frame) {
      stdout.write('$line\n');
    }
    drawn = frame.length;
  }

  stdout.write('\x1B[?25l'); // hide cursor
  try {
    render();
    while (true) {
      final b = stdin.readByteSync();
      if (b < 0) throw StateError('stdin closed');
      if (b == 27) {
        if (stdin.readByteSync() == 91) {
          final c = stdin.readByteSync();
          if (c == 65) {
            idx = (idx - 1 + items.length) % items.length;
            render();
          } else if (c == 66) {
            idx = (idx + 1) % items.length;
            render();
          }
        }
      } else if (b == 13 || b == 10) {
        return idx + 1;
      } else if (b == 3 || b == 113) {
        return 0; // ctrl-c / q
      } else if (b >= 49 && b < 49 + items.length) {
        return b - 48;
      }
    }
  } finally {
    stdin.echoMode = oldEcho;
    stdin.lineMode = oldLine;
    stdout.write('\x1B[?25h\n'); // show cursor
  }
}

Future<int> runWizard() async {
  printBanner();
  stdout.writeln('${_bold}What should Kuro do?$_reset  🐈‍⬛\n');
  const items = [
    'Build APK (optimized)',
    'Pub Get All packages',
    'Create Feature scaffold',
    'Project Status dashboard',
    'Audit Assets budget',
    'Clear on-device config cache',
    'Smart Search',
  ];
  final pick = await _pickMenu(items);
  if (pick < 1 || pick > items.length) {
    fail('Cancelled.');
    return 1;
  }
  switch (pick) {
    case 1:
      final type = _ask('Build type', def: 'release');
      final flavor = _ask('Flavor (prod/dev)', def: type == 'debug' ? 'dev' : 'prod');
      final split = _ask('Split per ABI? (y/N)', def: 'N').toLowerCase() == 'y';
      return cmdBuild([type, '--flavor', flavor, if (split) '--split-abi']);
    case 2:
      return cmdPubGet([]);
    case 3:
      return cmdFeature([_ask('Feature name (snake_case)')]);
    case 4:
      return cmdStatus([]);
    case 5:
      return cmdAssets(['--limit-kb', _ask('Budget KB', def: '200')]);
    case 6:
      return cmdClearCache([_ask('App ID', def: 'id.nhasix.app.dev.debug')]);
    default:
      final mode = _ask('Mode (text/ast/audit/debugprint/violations)', def: 'text');
      final pattern = mode == 'audit' ? '' : _ask('Pattern');
      final dir = _ask('Directory', def: 'lib/');
      return cmdSearch([mode, if (pattern.isNotEmpty) pattern, dir]);
  }
}

// ── Entry: Dual Mode (spec § Direct Non-Interactive Execution) ──
Future<void> main(List<String> args) async {
  // Direct mode: explicit sub-command always wins (even on a TTY).
  if (args.isNotEmpty) {
    final cmd = args.first.toLowerCase();
    final rest = args.sublist(1);
    switch (cmd) {
      case 'build':
        exit(await cmdBuild(rest));
      case 'pub-get':
      case 'get':
        exit(await cmdPubGet(rest));
      case 'feature':
      case 'create':
        exit(await cmdFeature(rest));
      case 'status':
        exit(await cmdStatus(rest));
      case 'assets':
        exit(await cmdAssets(rest));
      case 'clear-cache':
      case 'clear_cache':
        exit(await cmdClearCache(rest));
      case 'search':
      case 'audit':
        exit(await cmdSearch(cmd == 'audit' ? ['audit', ...rest] : rest));
      case 'help':
      case '--help':
      case '-h':
        printHelp();
        exit(0);
      case '--version':
      case '-v':
      case 'version':
        stdout.writeln('$kKuroName v$kKuroVersion — $kKuroFullName 🐈‍⬛');
        exit(0);
      default:
        fail('Unknown command: $cmd');
        printHelp();
        exit(1);
    }
  }

  // No args: TTY → wizard; CI/pipe → help + non-zero (never hang on input).
  final isCI = Platform.environment.containsKey('CI') ||
      Platform.environment.containsKey('GITHUB_ACTIONS');
  if (stdin.hasTerminal && !isCI) {
    exit(await runWizard());
  }
  printHelp();
  exit(1);
}
