// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/local.dart';

import 'common.dart';

class FlutterTree {
  FlutterTree(this.root);

  final Directory root;

  Directory get binDir => root.childDirectory('bin');
  File get binDart => binDir.childFile('dart');
  File get binFlutter => binDir.childFile('flutter');

  Directory get packagesDir => root.childDirectory('packages');
  Directory get toolsPackageDir => packagesDir.childDirectory('flutter_tools');
}

final FlutterTree hostFlutterTree = FlutterTree(
  const LocalFileSystem().directory(getFlutterRoot()).absolute);
