// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:file/file.dart';

import '../src/common.dart';
import 'test_flutter_tree.dart';

final List<Matcher> upgradeMatcherList = [
  startsWith('pub upgrade:'),
  startsWith('generate-snapshot:'),
];

Future<void> main() async {
  tearDownAll(TestFlutterTree.dispose);

  test('when nothing changes, cache is hit', () async {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    final List<String> log = tree.ensureToolWithFakeDart();
    expect(log, isNot(anyElement(anyOf(upgradeMatcherList))));
  });

  test('a commit on pubspec.yaml invalidates cache', () async {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();

    tree.toolsPackageDir.childFile('pubspec.yaml').writeAsStringSync(
      '\n', mode: FileMode.append,
    );
    tree.runSyncSuccess(<String>['git', 'commit', '-am', 'touch pubspec.yaml']);

    final List<String> log = tree.ensureToolWithFakeDart();
    expect(log, containsAllInOrder(upgradeMatcherList));
  });

  // TODO copy uncommitted changes from main tree

  // TODO test commits to bin/flutter_tools.dart and to lib/
  // TODO test commits to test/, to framework, to examples
}
