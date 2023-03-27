// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:process/process.dart';

/// Matches only strings that a shell will always parse as a single literal word.
///
/// Some strings that a shell would in fact accept as a single literal word
/// will not match this pattern.  This pattern should only be used when
/// an error in that direction would be merely cosmetic.
final RegExp _definitelyShellLiteralWordRegExp = RegExp(r'^[a-zA-Z0-9./,_-]+$');

String shellEscapeArgument(String value) {
  if (_definitelyShellLiteralWordRegExp.hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}

String shellEscapeCommand(List<String> command) {
  return command.map(shellEscapeArgument).join(' ');
}

extension ProcessManagerExtension on ProcessManager {
  ProcessResult runSyncSuccess(
    List<String> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    // no runInShell; keep that always false
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    final ProcessResult result = runSync(
      command,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
    if (result.exitCode != 0) {
      throw Exception(
        'child process exited with code ${result.exitCode}\n'
        'command: ${shellEscapeCommand(command)}\n'
        'stdout: ================================================================\n'
        '${result.stdout}\n'
        'stderr: ================================================================\n'
        '${result.stderr}\n'
        'end ====================================================================',
      );
    }
    return result;
  }
}

String asShellOutput(String raw) {
  return raw.replaceFirst(RegExp(r'\n*$'), '');
}

extension FileExtension on File {
  String? readLikeShell() {
    try {
      return asShellOutput(readAsStringSync());
    } on FileSystemException {
      return null;
    }
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
      case String(): return asShellOutput(stdout);
      case List<int>(): throw UnimplementedError();
      default: throw Error(); // forbidden by contract of [output]
    }
  }
}
