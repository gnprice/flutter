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
/// Successive test cases can reuse the tree by calling [TestFlutterTree.take],
/// which will reset it to its original state.
///
/// After all tests have run, [TestFlutterTree.dispose] should be called
/// in order to delete the temporary tree.
class TestFlutterTree extends FlutterTree {
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
  ///   processManager.runSyncSuccess([tree.binFlutter.path]);
  /// ```
  ///
  /// This differs in that the tree is memoized and subsequently copied from
  /// the memoized version, which is much faster than compiling again.
  factory TestFlutterTree.takeWarm() {
    return TestFlutterTree.take().._warm();
  }

  TestFlutterTree._(this.baseRevision, super.root);

  factory TestFlutterTree._create() {
    final String baseRevision = processManager.runSyncSuccess(<String>[
      'git', '-C', hostFlutterTree.root.path, 'rev-parse', 'HEAD',
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

  final String baseRevision;
  Directory? _warmTree;

  void _initialize() {
    processManager.runSyncSuccess(<String>[
      'git', 'clone',
      '--shared',
      '--origin', 'origin',
      hostFlutterTree.root.childDirectory('.git').path,
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

  void _warm() {
    if (_warmTree != null) {
      _rsyncTreesSync(_warmTree!, root);
      return;
    }

    assert(flutterToolsStampFile.readLikeShell() == null);
    final String stampValue = flutterToolsStampValue(revision: baseRevision);
    processManager.runSyncSuccess(<String>[binFlutter.path]);
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
}
