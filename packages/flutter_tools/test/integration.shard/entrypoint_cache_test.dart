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

extension TestFlutterTreeExtension on TestFlutterTree {
  void makeCommit() {
    runSyncSuccess(<String>['git', 'commit', '-am', 'test commit']);
  }
}

void mungeFile(File file) {
  file.writeAsStringSync('\n', mode: FileMode.append);
}

Future<void> main() async {
  tearDownAll(TestFlutterTree.dispose);

  test('change nothing -> hit cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    expect(tree.ensureToolWithFakeDart(), isCacheHit);
  });

  test('change tool pubspec.yaml -> invalidate cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    mungeFile(tree.toolsPackageDir.childFile('pubspec.yaml')); // packages/flutter_tools/pubspec.yaml
    tree.makeCommit();
    expect(tree.ensureToolWithFakeDart(), isCacheMiss);
  });

  test('change tool bin-dart script -> invalidate cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    mungeFile(tree.toolsPackageDir.childDirectory('bin').childFile('flutter_tools.dart')); // packages/flutter_tools/bin/flutter_tools.dart
    tree.makeCommit();
    expect(tree.ensureToolWithFakeDart(), isCacheMiss);
  });

  test('change some tool source file -> invalidate cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    final Directory toolsLibSrc = tree.toolsPackageDir.childDirectory('lib').childDirectory('src');
    mungeFile(toolsLibSrc.childFile('device.dart')); // packages/flutter_tools/lib/src/device.dart
    tree.makeCommit();
    expect(tree.ensureToolWithFakeDart(), isCacheMiss);
  });

  test('change tool tests -> hit cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    final Directory testDir = tree.toolsPackageDir.childDirectory('test'); // packages/flutter_tools/test/
    mungeFile(testDir.childDirectory('src').childFile('common.dart'));
    mungeFile(testDir.childDirectory('general.shard').childFile('compile_test.dart'));
    mungeFile(testDir.childDirectory('data').childDirectory('asset_test').childDirectory('main').childFile('pubspec.yaml'));
    tree.makeCommit();
    expect(tree.ensureToolWithFakeDart(), isCacheHit);
  });

  test('change framework -> hit cache', () {
    final TestFlutterTree tree = TestFlutterTree.takeWarm();
    mungeFile(tree.frameworkDir.childFile('pubspec.yaml'));
    mungeFile(tree.frameworkDir.childDirectory('lib').childFile('foundation.dart'));
    mungeFile(tree.frameworkDir.childDirectory('lib').childDirectory('src').childDirectory('widgets').childFile('framework.dart'));
    mungeFile(tree.frameworkDir.childDirectory('test').childDirectory('rendering').childFile('box_test.dart'));
    tree.makeCommit();
    expect(tree.ensureToolWithFakeDart(), isCacheHit);
  });

  // TODO test deleting file, or adding new one, in both hit and miss
  // TODO test commits to examples
}
