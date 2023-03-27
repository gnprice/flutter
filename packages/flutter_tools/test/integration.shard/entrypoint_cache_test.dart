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

final Matcher isCacheHit = isNot(anyElement(anyOf(upgradeMatcherList)));
final Matcher isCacheMiss = containsAllInOrder(upgradeMatcherList);

void editFile(TestFlutterTree tree, File file) {
  file.writeAsStringSync('\n', mode: FileMode.append);
  tree.runSyncSuccess(<String>['git', 'commit', '-am', 'touch ${file.basename}']);
}

Future<void> main() async {
  tearDownAll(TestFlutterTree.dispose);

  test('change nothing -> hit cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    expect(tree.ensureToolWithFakeDart(), isCacheHit);
  });

  test('change tool pubspec.yaml -> invalidate cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    editFile(tree, tree.toolsPackageDir.childFile('pubspec.yaml')); // packages/flutter_tools/pubspec.yaml
    expect(tree.ensureToolWithFakeDart(), isCacheMiss);
  });

  test('change tool bin-dart script -> invalidate cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    editFile(tree, tree.toolsPackageDir.childDirectory('bin').childFile('flutter_tools.dart')); // packages/flutter_tools/bin/flutter_tools.dart
    expect(tree.ensureToolWithFakeDart(), isCacheMiss);
  });

  test('change some tool source file -> invalidate cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    final Directory toolsLibSrc = tree.toolsPackageDir.childDirectory('lib').childDirectory('src');
    final File srcFile = toolsLibSrc.childFile('device.dart'); // packages/flutter_tools/lib/src/device.dart
    editFile(tree, srcFile);
    expect(tree.ensureToolWithFakeDart(), isCacheMiss);
  });

  test('change tool tests -> hit cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    final Directory testDir = tree.toolsPackageDir.childDirectory('test'); // packages/flutter_tools/test/
    editFile(tree, testDir.childDirectory('src').childFile('common.dart'));
    editFile(tree, testDir.childDirectory('general.shard').childFile('compile_test.dart'));
    editFile(tree, testDir.childDirectory('data').childDirectory('asset_test').childDirectory('main').childFile('pubspec.yaml'));
    expect(tree.ensureToolWithFakeDart(), isCacheHit);
  });

  test('change framework -> hit cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    editFile(tree, tree.frameworkDir.childFile('pubspec.yaml'));
    editFile(tree, tree.frameworkDir.childDirectory('lib').childFile('foundation.dart'));
    editFile(tree, tree.frameworkDir.childDirectory('lib').childDirectory('src').childDirectory('widgets').childFile('framework.dart'));
    editFile(tree, tree.frameworkDir.childDirectory('test').childDirectory('rendering').childFile('box_test.dart'));
    expect(tree.ensureToolWithFakeDart(), isCacheHit);
  });

  // TODO copy uncommitted changes from main tree

  // TODO test commits to examples
}
