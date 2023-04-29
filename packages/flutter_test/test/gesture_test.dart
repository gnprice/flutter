// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('No gesture state leak in draggables', () {
    Future<void> startDrag(WidgetTester tester, {required int pointer}) async {
      await tester.pumpWidget(MaterialApp(home: Column(children: <Widget>[
        LongPressDraggable<int>(
          feedback: GestureDetector(onTap: () {}, child: const SizedBox.shrink()),
          child: const Text('Target'),
        ),
      ])));

      await tester.startGesture(pointer: pointer, tester.getCenter(find.text('Target')));
      await tester.pump(kLongPressTimeout);
      // Leave the pointer still down at the end of the test.  This causes what
      // would be a state leak if the tester didn't automatically clean it up.
    }

    Future<void> completeDrag(WidgetTester tester, {required int pointer}) async {
      await tester.pumpWidget(MaterialApp(home: Column(children: <Widget>[
        const Draggable<int>(data: 1, feedback: SizedBox.shrink(), child: Text('Source')),
        DragTarget<int>(
          builder: (BuildContext _, List<int?> __, List<dynamic> ___) => const Text('Target'),
          onAccept: (int data) {},
        ),
      ])));

      final TestGesture gesture = await tester.startGesture(
          pointer: pointer, tester.getCenter(find.text('Source')));
      await gesture.moveTo(tester.getCenter(find.text('Target')));
      await gesture.up();
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
