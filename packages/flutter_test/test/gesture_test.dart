// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> startDrag(WidgetTester tester, {required int pointer}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            LongPressDraggable<int>(
              feedback: GestureDetector(
                onTap: () {},
                child: const SizedBox.shrink(),
              ),
              child: const Text('Target'),
            ),
          ],
        ),
      ),
    );

    await tester.startGesture(pointer: pointer, tester.getCenter(find.text('Target')));
    await tester.pump(kLongPressTimeout);
  }

  Future<void> completeDrag(WidgetTester tester, {required int pointer}) async {
    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: <Widget>[
          const Draggable<int>(data: 1, feedback: SizedBox.shrink(), child: Text('Source')),
          DragTarget<int>(
            builder: (BuildContext _, List<int?> __, List<dynamic> ___) => const Text('Target'),
            onAccept: (int data) {},
          ),
        ],
      ),
    ));

    final TestGesture gesture = await tester.startGesture(
      pointer: pointer, tester.getCenter(find.text('Source')));
    await gesture.moveTo(tester.getCenter(find.text('Target')));
    await gesture.up();
  }

  testWidgets('Start drag vs. complete drag, side A', (WidgetTester tester) async {
    await startDrag(tester, pointer: 7);
    await completeDrag(tester, pointer: 8);
  });

  testWidgets('Start drag vs. complete drag, side B', (WidgetTester tester) async {
    await startDrag(tester, pointer: 8);
    await completeDrag(tester, pointer: 7);
  });
}
