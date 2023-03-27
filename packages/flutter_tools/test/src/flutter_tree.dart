// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/local.dart';

import 'common.dart';

class FlutterTree {
  FlutterTree(this.root);

  final Directory root;

  // When adding more file and subdirectory getters,
  // include their full relative paths as comments.
  // This helps make them discoverable as references to these files/directories.

  Directory get binDir => root.childDirectory('bin'); // bin/
  File get binDart => binDir.childFile('dart'); // bin/dart
  File get binFlutter => binDir.childFile('flutter'); // bin/flutter

  Directory get binInternalDir => binDir.childDirectory('internal'); // bin/internal/
  File get engineVersionFile => binInternalDir.childFile('engine.version'); // bin/internal/engine.version

  Directory get packagesDir => root.childDirectory('packages'); // packages/
  Directory get toolsPackageDir => packagesDir.childDirectory('flutter_tools'); // packages/flutter_tools/
}

final FlutterTree hostFlutterTree = FlutterTree(
  const LocalFileSystem().directory(getFlutterRoot()).absolute);
