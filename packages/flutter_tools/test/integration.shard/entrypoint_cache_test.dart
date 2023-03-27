// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:process/process.dart';

import '../src/common.dart';

const FileSystem fileSystem = LocalFileSystem();
const ProcessManager processManager = LocalProcessManager();

final String flutterRootPath = getFlutterRoot();
final Directory flutterRoot = fileSystem.directory(flutterRootPath).absolute;

/// Matches only strings that a shell will always parse as a single literal word.
///
/// Some strings that a shell would in fact accept as a single literal word
/// will not match this pattern.  This pattern should only be used when
/// an error in that direction would be merely cosmetic.
final RegExp _definitelyShellLiteralWordRegExp = RegExp(r'^[a-zA-Z0-9./,_-]+$');

String shellEscapeArgument(String value) {
  if (_definitelyShellLiteralWordRegExp.hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}

String shellEscapeCommand(List<String> command) {
  return command.map(shellEscapeArgument).join(' ');
}

extension ProcessManagerExtension on ProcessManager {
  ProcessResult runSyncSuccess(
    List<String> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    // no runInShell; keep that always false
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    final ProcessResult result = runSync(
      command,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
    if (result.exitCode != 0) {
      throw Exception(
        'child process exited with code ${result.exitCode}\n'
        'command: ${shellEscapeCommand(command)}\n'
        'stdout: ================================================================\n'
        '${result.stdout}\n'
        'stderr: ================================================================\n'
        '${result.stderr}\n'
        'end ====================================================================',
      );
    }
    return result;
  }
}

String asShellOutput(String raw) {
  return raw.replaceFirst(RegExp(r'\n*$'), '');
}

extension FileExtension on File {
  String? readLikeShell() {
    try {
      return asShellOutput(readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }
}

extension ProcessResultExtension on ProcessResult {
  /// The command's output, as shell command substitution `$(…)` would take it.
  ///
  /// This is the result of removing from [stdout] any run of newlines at the
  /// end of the string.  For example, if [stdout] is any of 'a\nb', 'a\nb\n',
  /// or 'a\nb\n\n\n', then [shellOutput] will be 'a\nb'.
  ///
  /// TODO link reference
  String get shellOutput {
    final dynamic stdout = this.stdout;
    switch (stdout) {
      case String(): return asShellOutput(stdout);
      case List<int>(): throw UnimplementedError();
      default: throw Error(); // forbidden by contract of [output]
    }
  }
}

void rsyncTreesSync(Directory source, Directory target) {
  processManager.runSyncSuccess(<String>[
    'rsync', '-a', '--delete',
    source.path + Platform.pathSeparator,
    target.path + Platform.pathSeparator,
  ]);
}

/// A temporary copy of the Flutter tree, to be freely mutated for testing.
///
/// This is a real Git worktree in the real filesystem.
/// To save resources, it reuses the Git object and pack files from
/// the Flutter tree that these tests are found in.
///
/// Successive test cases can reuse the tree by calling [TestFlutterTree.take],
/// which will reset it to its original state.
///
/// After all tests have run, [TestFlutterTree.dispose] should be called
/// in order to delete the temporary tree.
class TestFlutterTree {
  /// Take the shared global tree, resetting it to a pristine state.
  factory TestFlutterTree.take() {
    return (_instance ??= TestFlutterTree._create()).._reset();
  }

  /// Take the shared global tree, resetting it to a warm-cache state.
  ///
  /// This is equivalent to [TestFlutterTree.take()] followed by a command
  /// that causes the entrypoint script to build the tool.  For example:
  /// ```dart
  ///   final TestFlutterTree tree = TestFlutterTree.take();
  ///   processManager.runSyncSuccess([tree.binFlutter]);
  /// ```
  ///
  /// This differs in that the tree is memoized and subsequently copied from
  /// the memoized version, which is much faster than compiling again.
  factory TestFlutterTree.takeWarm() {
    final TestFlutterTree tree = TestFlutterTree.take();
    if (_warmTree != null) {
      rsyncTreesSync(_warmTree!, tree.root);
      return tree;
    }

    assert(tree.flutterToolsStampFile.readLikeShell() == null);
    final String stampValue = flutterToolsStampValue(revision: tree.baseRevision);
    processManager.runSyncSuccess(<String>[tree.binFlutter]);
    assert(tree.flutterToolsStampFile.readLikeShell() == stampValue);

    _warmTree = fileSystem
      .systemTempDirectory.createTempSync('flutter_test_tree_warm.').absolute;
    rsyncTreesSync(tree.root, _warmTree!);
    return tree;
  }

  TestFlutterTree._(this.baseRevision, this.root);

  factory TestFlutterTree._create() {
    final String baseRevision = processManager.runSyncSuccess(<String>[
      'git', '-C', flutterRoot.path, 'rev-parse', 'HEAD',
    ]).shellOutput;
    final Directory root = fileSystem
      .systemTempDirectory.createTempSync('flutter_test_tree.').absolute;
    return TestFlutterTree._(baseRevision, root).._initialize();
  }

  static void dispose() {
    _instance?._dispose();
    _instance = null;
  }

  static TestFlutterTree? _instance;
  static Directory? _warmTree;

  final Directory root;
  final String baseRevision;

  void _initialize() {
    processManager.runSyncSuccess(<String>[
      'git', 'clone',
      '--shared',
      '--origin', 'origin',
      flutterRoot.childDirectory('.git').path,
      root.path,
    ]);
    _reset();
  }

  void _reset() {
    runSyncSuccess(<String>['git', 'checkout', '-B', 'main', baseRevision]);
    runSyncSuccess(<String>[
      'git', 'clean',
      '--quiet',
      '--force',
      '-d', // directories too
      '-x', // ignored files too
    ]);
  }

  void _dispose() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  }

  String get binDart => root.childDirectory('bin').childFile('dart').path;
  String get binFlutter => root.childDirectory('bin').childFile('flutter').path;

  Directory get toolsPackageDir => root.childDirectory('packages').childDirectory('flutter_tools');

  String headRevision() => runSyncSuccess(<String>['git', 'rev-parse', 'HEAD']).shellOutput;

  ProcessResult runSyncSuccess(
    List<String> command, {
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    // no runInShell; keep that always false
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    return processManager.runSyncSuccess(
      command,
      workingDirectory: root.path,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }
}

/// Some expected behavior of the entrypoint cache, in terms of [TestFlutterTree].
extension FlutterTreeCacheExtension on TestFlutterTree {
  Directory get binCacheDir => root.childDirectory('bin').childDirectory('cache');

  File get snapshotFile => binCacheDir.childFile('flutter_tools.snapshot');
  File get flutterToolsStampFile => binCacheDir.childFile('flutter_tools.stamp');
}

/// The value the entrypoint writes into `flutterToolsStampFile`.
String flutterToolsStampValue({required String revision, String toolArgs = ''}) {
  return '$revision:$toolArgs';
}

Future<void> main() async {
  tearDownAll(TestFlutterTree.dispose);

  test('when nothing changes, cache is hit', () async {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    final String stampValue = flutterToolsStampValue(revision: tree.baseRevision);
    expect(tree.flutterToolsStampFile.readLikeShell(), stampValue);

    final DateTime stampTime = tree.flutterToolsStampFile.lastModifiedSync();
    final DateTime snapshotTime = tree.snapshotFile.lastModifiedSync();
    processManager.runSyncSuccess(<String>[tree.binFlutter]);
    expect(tree.flutterToolsStampFile.readLikeShell(), stampValue);
    expect(tree.flutterToolsStampFile.lastModifiedSync(), stampTime);
    expect(tree.snapshotFile.lastModifiedSync(), snapshotTime);
  });

  test('a commit on pubspec.yaml invalidates cache', () async {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();

    tree.toolsPackageDir.childFile('pubspec.yaml').writeAsStringSync(
      '\n', mode: FileMode.append,
    );
    tree.runSyncSuccess(<String>['git', 'commit', '-am', 'touch pubspec.yaml']);

    final String revision = tree.headRevision();
    final String stampValue = flutterToolsStampValue(revision: revision);
    final DateTime oldStampTime = tree.flutterToolsStampFile.lastModifiedSync();
    final DateTime oldSnapshotTime = tree.snapshotFile.lastModifiedSync();
    // print(tree.runSyncSuccess(['ls', '-lrt', '--full-time', 'bin/cache']).stdout);
    processManager.runSyncSuccess(<String>[tree.binFlutter]);
    // print(tree.runSyncSuccess(['ls', '-lrt', '--full-time', 'bin/cache']).stdout);
    expect(tree.flutterToolsStampFile.readLikeShell(), stampValue);
    expect(tree.flutterToolsStampFile.lastModifiedSync().isAfter(oldStampTime), true);
    expect(tree.snapshotFile.lastModifiedSync().isAfter(oldSnapshotTime), true);
  });

  // TODO borrow bin/cache/dart-sdk/ from main tree, to save downloading
  // TODO copy uncommitted changes from main tree

  // TODO test commits to bin/flutter_tools.dart and to lib/
  // TODO test commits to test/, to framework, to examples
}
