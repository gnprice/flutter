// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('No gesture state leak in draggables', () {
    Future<void> startDrag(WidgetTester tester, {required int pointer}) async {
      await tester.pumpWidget(const MaterialApp(home: Column(children: <Widget>[
        Draggable<String>(data: 'before', feedback: SizedBox.shrink(), child: Text('Target')),
      ])));

      await tester.startGesture(pointer: pointer, tester.getCenter(find.text('Target')));
      // Leave the pointer still down at the end of the test, so that the
      // drag gesture recognizer stays active.  This would be a state leak
      // if the tester didn't automatically clean it up.
    }

    Future<void> completeDrag(WidgetTester tester, {required int pointer}) async {
      final List<String> results = <String>[];
      await tester.pumpWidget(MaterialApp(home: Column(children: <Widget>[
        const Draggable<String>(data: 'after', feedback: SizedBox.shrink(), child: Text('Source')),
        DragTarget<String>(
          onAccept: results.add,
          builder: (BuildContext _, List<String?> __, List<dynamic> ___) => const Text('Target'),
        ),
      ])));

      final TestGesture gesture = await tester.startGesture(
          pointer: pointer, tester.getCenter(find.text('Source')));
      await gesture.moveTo(tester.getCenter(find.text('Target')));
      await gesture.up();

      expect(results, ['after']);
    }

    // Logically these tests consist of startDrag in one test,
    // then completeDrag in the other, on the same pointer.
    // Using two pointers makes the tests effective in either order.

    testWidgets('side A', (WidgetTester tester) async {
      await startDrag(tester, pointer: 7);
      await completeDrag(tester, pointer: 8);
    });

    testWidgets('side B', (WidgetTester tester) async {
      await completeDrag(tester, pointer: 7);
      await startDrag(tester, pointer: 8);
    });
  });
}
