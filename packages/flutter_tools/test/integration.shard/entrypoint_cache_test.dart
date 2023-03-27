// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:file/file.dart';

import '../src/common.dart';
import '../src/process.dart';
import 'test_flutter_tree.dart';

Future<void> main() async {
  tearDownAll(TestFlutterTree.dispose);

  test('when nothing changes, cache is hit', () async {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    final String stampValue = flutterToolsStampValue(revision: tree.baseRevision);
    expect(tree.flutterToolsStampFile.readLikeShell(), stampValue);

    final DateTime stampTime = tree.flutterToolsStampFile.lastModifiedSync();
    final DateTime snapshotTime = tree.snapshotFile.lastModifiedSync();
    tree.ensureToolWithFakeDart();
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
    tree.ensureToolWithFakeDart();
    // print(tree.runSyncSuccess(['ls', '-lrt', '--full-time', 'bin/cache']).stdout);
    expect(tree.flutterToolsStampFile.readLikeShell(), stampValue);
    expect(tree.flutterToolsStampFile.lastModifiedSync().isAfter(oldStampTime), true);
    expect(tree.snapshotFile.lastModifiedSync().isAfter(oldSnapshotTime), true);
  });

  // TODO copy uncommitted changes from main tree

  // TODO test commits to bin/flutter_tools.dart and to lib/
  // TODO test commits to test/, to framework, to examples
}
