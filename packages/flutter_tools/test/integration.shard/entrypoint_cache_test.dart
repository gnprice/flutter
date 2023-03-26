// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:process/process.dart';

import '../src/common.dart';

const FileSystem fileSystem = LocalFileSystem();
const ProcessManager processManager = LocalProcessManager();

final String flutterRootPath = getFlutterRoot();
final Directory flutterRoot = fileSystem.directory(flutterRootPath).absolute;

extension ProcessManagerExtension on ProcessManager {
  ProcessResult runSyncSuccess(List<String> command) {
    final result = runSync(command);
    expect(result.exitCode, 0,
      reason: 'child process exited with code ${result.exitCode}\n'
        'command: $command\n'
        'stdout: ================================================================\n'
        '${result.stdout}\n'
        'stderr: ================================================================\n'
        '${result.stderr}\n'
        'end ===================================================================='
    );
    return result;
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
      case String(): return stdout.replaceFirst(RegExp(r'\n*$'), '');
      case List<int>(): throw UnimplementedError();
      default: throw Error(); // forbidden by contract of [output]
    }
  }
}

class TestFlutterTree {
  factory TestFlutterTree.take() {
    return (_instance ??= TestFlutterTree._create()).._reset();
  } 

  TestFlutterTree._(this._baseRevision, this.root);

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

  final Directory root;
  final String _baseRevision;

  void _initialize() {
    processManager.runSyncSuccess(<String>[
      'git', 'clone', '--mirror',
      '--shared',
      '--origin', 'origin',
      flutterRoot.childDirectory('.git').path,
      root.path,
    ]);
    _reset();
  }

  void _reset() {
    runGitSuccess(<String>['checkout', '-B', 'main', _baseRevision]);
    runGitSuccess(<String>[
      'clean',
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

  ProcessResult runGitSuccess(List<String> command) {
    return processManager.runSyncSuccess(<String>['git', '-C', root.path, ...command]);
  }
}

Future<void> main() async {
  tearDownAll(TestFlutterTree.dispose);

  test('when nothing changes, cache is hit', () async {
    final tree = TestFlutterTree.take();

    print(tree.root);
    await Future.delayed(Duration(seconds: 1000));
    // TODO write test
  });
}
