// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';

import '../src/common.dart';
import '../src/flutter_tree.dart';
import '../src/process.dart' hide runSyncSuccess;
import '../src/process.dart' as proc show runSyncSuccess;
import 'test_utils.dart';

/// The Flutter source tree that this program is part of.
///
/// The tree is the one located by [getFlutterRoot].
final FlutterTreeWithToolCache hostFlutterTree = FlutterTreeWithToolCache(
    fileSystem.directory(getFlutterRoot()).absolute);

/// The value the entrypoint writes into `flutterToolsStampFile`.
///
/// The [toolArgs] parameter corresponds to `FLUTTER_TOOL_ARGS`
/// in the entrypoint scripts.
String flutterToolsStampValue({required String revision, required String toolArgs}) {
  return '$revision:$toolArgs';
}

/// A [FlutterTree] with additional members which are helpful for [TestFlutterTree]
/// and its users.
class FlutterTreeWithToolCache extends FlutterTree {
  FlutterTreeWithToolCache(super.root);

  Directory get binCacheDir => root.childDirectory('bin').childDirectory('cache'); // bin/cache/
  File get snapshotFile => binCacheDir.childFile('flutter_tools.snapshot'); // bin/cache/flutter_tools.snapshot
  File get flutterToolsStampFile => binCacheDir.childFile('flutter_tools.stamp'); // bin/cache/flutter_tools.stamp
  Directory get dartSdkDir => binCacheDir.childDirectory('dart-sdk'); // bin/cache/dart-sdk/
  File get engineStampFile => binCacheDir.childFile('engine-dart-sdk.stamp'); // bin/cache/engine-dart-sdk.stamp

  String headRevision() => processResultShellOutput(runSyncSuccess(<String>['git', 'rev-parse', 'HEAD'])) as String;

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
      '--no-renames', // disables finding renames, and finding copies too
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

  /// Start a process at [root] and run it to completion, throwing an exception
  /// on failure.
  ///
  /// This is a convenience wrapper for [proc.runSyncSuccess],
  /// providing `workingDirectory`.
  ProcessResult runSyncSuccess(
    List<String> command, {
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    // no runInShell; keep that always false
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    return proc.runSyncSuccess(
      processManager,
      command,
      workingDirectory: root.path,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }
}

/// A temporary copy of the Flutter tree, to be freely mutated for testing.
///
/// This is a real Git worktree in the real filesystem.
/// Its contents are based on those of [hostFlutterTree]: the Git commit
/// [baseRevision] is the current HEAD of [hostFlutterTree], plus one
/// added commit for any changes in the [hostFlutterTree] worktree
/// that are not yet committed to Git.
///
/// To save resources, this tree reuses the Git object and pack files from
/// [hostFlutterTree].
///
/// Successive test cases can reuse the tree by calling
/// [TestFlutterTree.takeClean],
/// which will reset it to a known state.
///
/// After all tests have run, [TestFlutterTree.dispose] should be called
/// in order to delete the temporary tree.
///
/// See also:
/// * [hostFlutterTree], the Flutter tree that the running program
///   is itself part of.
class TestFlutterTree extends FlutterTreeWithToolCache {
  /// Take the shared global tree, resetting it to a pristine state.
  ///
  /// The tree will be on branch `main` at commit [baseRevision].
  /// There will be no files or directories in the tree except
  /// those put there by Git.
  ///
  /// Using this can be expensive because any operation involving the
  /// [binDart] or [binFlutter] entrypoint scripts may cause the Dart SDK
  /// to be downloaded from scratch and the tool snapshot to be recompiled.
  ///
  /// When using this, be sure to call [TestFlutterTree.dispose] after
  /// all tests have run, in order to avoid leaving a large temporary tree
  /// lying around in the filesystem.
  factory TestFlutterTree.takeClean() {
    return TestFlutterTree._take().._reset();
  }

  /// Take the shared global tree, in whatever state it currently is in.
  factory TestFlutterTree._take() {
    return _instance ??= TestFlutterTree._create();
  }

  TestFlutterTree._(this._origRevision, super.root);

  factory TestFlutterTree._create() {
    final String origRevision = hostFlutterTree.headRevision();
    final Directory root = fileSystem
      .systemTempDirectory.createTempSync('flutter_test_tree.').absolute;
    return TestFlutterTree._(origRevision, root).._initialize();
  }

  /// Delete the shared global temporary tree from the filesystem.
  static void dispose() {
    _instance?._dispose();
    _instance = null;
  }

  /// The shared global instance of [TestFlutterTree].
  static TestFlutterTree? _instance;

  /// The Git commit ID of this tree in its baseline state.
  ///
  /// This will be the current HEAD of [hostFlutterTree], plus one
  /// added commit for any changes in the [hostFlutterTree] worktree
  /// that are not yet committed to Git.
  late final String baseRevision;

  /// The Git commit ID that is HEAD in [hostFlutterTree].
  final String _origRevision;

  void _initialize() {
    proc.runSyncSuccess(processManager, <String>[
      'git', 'clone',
      '--shared',
      '--origin', 'origin',
      hostFlutterTree.root.childDirectory('.git').path,
      root.path,
    ]);
    runSyncSuccess(<String>['git', 'checkout', '-B', 'main', _origRevision]);

    // Sync uncommitted changes from [hostFlutterTree].
    final List<String> filesAdded = hostFlutterTree.gitModifiedFiles(diffFilter: 'A');
    final List<String> filesEdited = hostFlutterTree.gitModifiedFiles(diffFilter: 'MUT');
    final List<String> filesDeleted = hostFlutterTree.gitModifiedFiles(diffFilter: 'D');
    if (filesAdded.isNotEmpty || filesEdited.isNotEmpty) {
      hostFlutterTree.runSyncSuccess(<String>[
        'rsync', '-a', '--relative',
        ...filesAdded, ...filesEdited,
        root.path + Platform.pathSeparator,
      ]);
      if (filesAdded.isNotEmpty) {
        runSyncSuccess(<String>[
          'git', 'add', '--', ...filesAdded,
        ]);
      }
    }
    for (final String file in filesDeleted) {
      fileSystem.file(fileSystem.path.join(root.path, file)).deleteSync();
    }
    if (filesAdded.isNotEmpty || filesEdited.isNotEmpty || filesDeleted.isNotEmpty) {
      runSyncSuccess(<String>[
        'git', 'commit', '-am', 'uncommitted changes from host tree',
      ]);
      baseRevision = headRevision();
    } else {
      baseRevision = _origRevision;
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

  void _dispose() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  }
}
