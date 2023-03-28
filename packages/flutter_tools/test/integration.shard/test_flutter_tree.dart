// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:process/process.dart';

import '../src/flutter_tree.dart';
import '../src/process.dart';

const FileSystem fileSystem = LocalFileSystem();
const ProcessManager processManager = LocalProcessManager();

/// The value the entrypoint writes into `flutterToolsStampFile`.
String flutterToolsStampValue({required String revision, String toolArgs = ''}) {
  return '$revision:$toolArgs';
}

extension FlutterTreeExtension on FlutterTree {
  Directory get binCacheDir => root.childDirectory('bin').childDirectory('cache');
  File get snapshotFile => binCacheDir.childFile('flutter_tools.snapshot');
  File get flutterToolsStampFile => binCacheDir.childFile('flutter_tools.stamp');
  Directory get dartSdkDir => binCacheDir.childDirectory('dart-sdk');
  File get engineStampFile => binCacheDir.childFile('engine-dart-sdk.stamp');

  String headRevision() => runSyncSuccess(<String>['git', 'rev-parse', 'HEAD']).shellOutput;

  /// List the files where the worktree differs from the HEAD revision.
  ///
  /// Each file is represented as a path relative to [root].
  ///
  /// By default this includes files that have been added, deleted,
  /// or in any way modified.  If `diffFilter` is provided, it will be
  /// passed to `git diff --diff-filter=…` to filter the files
  /// by type of change.
  ///
  /// No rename detection is performed; if a file was renamed, it will appear
  /// as a deletion and an addition (as further filtered by `diffFilter`).
  List<String> gitModifiedFiles({String? diffFilter}) {
    final List<String> command = <String>[
      'git', 'diff',
      '--no-renames', // disables finding renames and finding copies, too
      '--name-only', '-z',
      if (diffFilter != null)
        '--diff-filter=$diffFilter',
      'HEAD',
    ];
    return (runSyncSuccess(command).stdout as String).split('\x00')..removeLast();
  }

  /// Run a trivial command with the tree's `bin/dart`, to ensure the cache
  /// is up to date.
  ///
  /// This happens to update all the same caches as [ensureToolSync],
  /// but in principle in the future it might not.
  void ensureDartSync() {
    // `dart --version` is faster than simply `dart`
    runSyncSuccess(<String>[binDart.path, '--version']);
  }

  /// Run a trivial command with the tree's `bin/flutter`, to ensure the cache
  /// is up to date.
  void ensureToolSync() {
    // plain `flutter` is faster than `flutter --version`
    runSyncSuccess(<String>[binFlutter.path]);
  }

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

/// Use `rsync` to copy one directory tree to another, exactly,
/// deleting stray files.
///
/// For each file or directory found under [source], there will be a
/// corresponding entity at the same relative path under [target],
/// with the same contents and same last-modified time and other metadata.
/// Any entities under [target] that do not correspond to an entity under
/// [source] will be deleted.
///
/// This is equivalent to the shell command
/// `rsync -a --delete "${source}/" "${target}/"`.
void _rsyncTreesSync(Directory source, Directory target) {
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
/// Successive test cases can reuse the tree by calling [TestFlutterTree.takeClean],
/// which will reset it to its original state.
///
/// After all tests have run, [TestFlutterTree.dispose] should be called
/// in order to delete the temporary tree.
class TestFlutterTree extends FlutterTree {
  /// Take the shared global tree, resetting it to a pristine state.
  factory TestFlutterTree.takeClean() {
    return TestFlutterTree._take().._reset();
  }

  /// Take the shared global tree, resetting it to a warm-cache state.
  ///
  /// This is equivalent to [TestFlutterTree.takeClean] followed by
  /// [ensureToolSync], but differs in that the tree is memoized and
  /// subsequently copied from the memoized version, which is much faster than
  /// compiling again.
  factory TestFlutterTree.takeWarm() {
    return TestFlutterTree._take().._warm();
  }

  /// Take the shared global tree, in whatever state it currently is in.
  factory TestFlutterTree._take() {
    return _instance ??= TestFlutterTree._create();
  }

  TestFlutterTree._(this.origRevision, super.root);

  factory TestFlutterTree._create() {
    final String origRevision = hostFlutterTree.headRevision();
    final Directory root = fileSystem
      .systemTempDirectory.createTempSync('flutter_test_tree.').absolute;
    return TestFlutterTree._(origRevision, root).._initialize();
  }

  static void dispose() {
    _instance?._dispose();
    _instance = null;
  }

  static TestFlutterTree? _instance;

  final String origRevision;
  late final String baseRevision;
  Directory? _warmTree;

  void _initialize() {
    processManager.runSyncSuccess(<String>[
      'git', 'clone',
      '--shared',
      '--origin', 'origin',
      hostFlutterTree.root.childDirectory('.git').path,
      root.path,
    ]);
    runSyncSuccess(<String>['git', 'checkout', '-B', 'main', origRevision]);

    // Sync uncommitted changes from [hostFlutterTree].
    bool hadChanges = false;
    final List<String> nonDeleteChanges = hostFlutterTree.gitModifiedFiles(diffFilter: 'AMU');
    if (nonDeleteChanges.isNotEmpty) {
      hostFlutterTree.runSyncSuccess(<String>[
        'rsync', '-a', '--relative',
        ...nonDeleteChanges,
        root.path + Platform.pathSeparator,
      ]);
      hadChanges = true;
    }
    for (final String file in hostFlutterTree.gitModifiedFiles(diffFilter: 'D')) {
      fileSystem.file(fileSystem.path.join(root.path, file)).deleteSync();
      hadChanges = true;
    }
    if (hadChanges) {
      runSyncSuccess(<String>[
        'git', 'commit', '-am', 'uncommitted changes from host tree',
      ]);
    }
  }

  void _reset({bool keepDartSdk = false}) {
    runSyncSuccess(<String>['git', 'checkout', '-B', 'main', baseRevision]);
    runSyncSuccess(<String>[
      'git', 'clean',
      '--quiet',
      '--force',
      '-d', // directories too
      '-x', // ignored files too
      if (keepDartSdk)
        '--exclude=bin/cache/dart-sdk/', // dartSdkDir but relative to root
    ]);
  }

  void _warm() {
    if (_warmTree != null) {
      _rsyncTreesSync(_warmTree!, root);
      return;
    }

    _reset();

    // Borrow the Dart SDK from the host tree.
    // This saves having to download it again.
    hostFlutterTree.ensureDartSync();
    dartSdkDir.createSync(recursive: true);
    _rsyncTreesSync(hostFlutterTree.dartSdkDir, dartSdkDir);
    hostFlutterTree.engineStampFile.copySync(engineStampFile.path);

    // Warm the rest of the cache directly in the test tree.
    assert(flutterToolsStampFile.readLikeShell() == null);
    final String stampValue = flutterToolsStampValue(revision: baseRevision);
    ensureToolWithFakeDart();
    assert(flutterToolsStampFile.readLikeShell() == stampValue);

    _warmTree = fileSystem
      .systemTempDirectory.createTempSync('flutter_test_tree_warm.').absolute;
    _rsyncTreesSync(root, _warmTree!);
  }

  void _dispose() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
    try {
      _warmTree?.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  }

  File get fakeDartLog => binCacheDir.childFile('fake-dart.log'); // bin/cache/fake-dart.log
  File get dartBinary => dartSdkDir.childDirectory('bin').childFile('dart'); // bin/cache/dart-sdk/bin/dart
  File get dartBinaryOrig => dartSdkDir.childDirectory('bin').childFile('dart.orig'); // bin/cache/dart-sdk/bin/dart.orig

  List<String> ensureToolWithFakeDart() {
    fakeDartLog.writeAsStringSync('');
    dartBinary.renameSync(dartBinaryOrig.path);
    _writeFakeDart();
    ensureToolSync();
    dartBinaryOrig.renameSync(dartBinary.path);
    return fakeDartLog.readAsLinesSync();
  }

  void _writeFakeDart() {
    dartBinary.writeAsStringSync('''
#!/usr/bin/env bash

full_command="dart \$*"

function log_command() {
  local description="\$1"
  echo "\$description: \$full_command" >>${shellEscapeArgument(fakeDartLog.path)}
}

case "\$*" in
  *" --disable-dart-dev "*" --snapshot-kind=app-jit "*)
    # This is the command to generate the snapshot,
    # in the upgrade_flutter function in bin/internal/shared.sh .
    # Fake generating the snapshot, by copying from the host tree.
    cp ${shellEscapeArgument(hostFlutterTree.snapshotFile.path)} \\
      ${shellEscapeArgument(snapshotFile.path)}
    log_command generate-snapshot
    ;;

  "pub upgrade "*)
    # This is a `dart pub upgrade` command, as in pub_upgrade_with_retry .
    # Just update the last-modified time on the pubspec.lock .
    touch pubspec.lock
    log_command "pub upgrade"
    ;;

  *" --disable-dart-dev "*" "${shellEscapeArgument(snapshotFile.path)} \\
  | *" --disable-dart-dev "*" "${shellEscapeArgument(snapshotFile.path)}" "*)
    # This looks like the "flutter" case at the end of shared::execute.
    # Do nothing.
    log_command flutter
    ;;

  *)
    log_command other
esac
''');
    processManager.runSyncSuccess(<String>['chmod', '+x', '--', dartBinary.path]); // https://github.com/dart-lang/sdk/issues/15078
  }
}
