// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:process/process.dart';

/// Matches only strings that a shell will always parse as a single literal word.
///
/// Some strings that a shell would in fact accept as a single literal word
/// will not match this pattern.  This pattern should only be used when
/// an error in that direction would be merely cosmetic.
final RegExp _definitelyShellLiteralWordRegExp = RegExp(r'^[a-zA-Z0-9./,_-]+$');

/// A string which a shell would parse as the given string value.
///
/// This method makes some effort to return the value unchanged,
/// for the sake of a clean appearance, when doing so meets the requirements.
/// For example, `shellEscapeString("asdf") == "asdf"`.
///
/// See also [_shellEscapeCommand], for operating on a whole command line.
String _shellEscapeString(String value) {
  if (_definitelyShellLiteralWordRegExp.hasMatch(value)) {
    return value;
  }

  // Escape the string for shell syntax in the simplest possible way
  // that always works: use single-quotes.  In a single-quoted string,
  // the only character that has any special meaning at all is the next
  // single-quote, which ends it:
  //   https://www.gnu.org/software/bash/manual/bash.html#Single-Quotes
  // Then if the original string has any single-quotes, we write those
  // as backslash-escapes.
  //
  // For example, for `shellEscapeString(r"isn't")` we return `r"'isn'\''t'"`.
  // The shell parses this as a single-quoted string `'isn'`, an escape `\'`,
  // and a single-quoted string `'t'`, with values `isn`, `'`, `t`, making `isn't`.
  return "'${value.replaceAll("'", r"'\''")}'";
}

/// A string which a shell would parse as the given command.
///
/// Useful for printing a command unambiguously, or for printing
/// a command the user might want to copy-paste and run.
///
/// This method makes some effort to print the command's elements
/// verbatim, for the sake of a clean appearance, where possible.
/// For example, `shellEscapeCommand(['git', 'commit', '-am', 'a commit'])`
/// returns `git commit -am 'a commit'`.
///
/// See also [_shellEscapeString], for operating on an individual
/// argument of a command.
String _shellEscapeCommand(List<String> command) {
  return command.map(_shellEscapeString).join(' ');
}

/// Start a process and run it to completion, throwing an exception on failure.
///
/// Like [ProcessManager.runSync], this blocks until the child process terminates.
///
/// If the child process exits with failure (a nonzero [ProcessResult.exitCode]),
/// this method throws an exception with details of the command and its output.
ProcessResult runSyncSuccess(
  ProcessManager processManager,
  List<String> command, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  // no runInShell; keep that always false
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
}) {
  final ProcessResult result = processManager.runSync(
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
      'command: ${_shellEscapeCommand(command)}\n'
      'stdout: ================================================================\n'
      '${result.stdout}\n'
      'stderr: ================================================================\n'
      '${result.stderr}\n'
      'end ====================================================================',
    );
  }
  return result;
}
