// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> startDrag(WidgetTester tester, {required int pointer}) async {
    bool onTap = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            LongPressDraggable<int>(
              ignoringFeedbackPointer: false,
              feedback: GestureDetector(
                onTap: () => onTap = true,
                child: const SizedBox(height: 50.0, child: Text('Draggable')),
              ),
              child: const SizedBox(height: 50.0, child: Text('Target')),
            ),
          ],
        ),
      ),
    );

    final Offset location = tester.getCenter(find.text('Target'));
    final TestGesture gesture = await tester.startGesture(location, pointer: pointer);
    await tester.pump(kLongPressTimeout);

    final Offset secondLocation = location + const Offset(7.0, 7.0);
    await gesture.moveTo(secondLocation);
    await tester.pump();

    await tester.tap(find.text('Draggable'));
    expect(onTap, true);
  }

  Future<void> completeDrag(WidgetTester tester, {required int pointer}) async {
    final List<int> accepted = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: <Widget>[
          const Draggable<Object>(
            data: 1,
            feedback: Text('Dragging'),
            child: Text('Source'),
          ),
          DragTarget<int>(
            builder: (BuildContext context, List<int?> data, List<dynamic> rejects) {
              return const SizedBox(height: 100.0, child: Text('Target'));
            },
            onAccept: accepted.add,
          ),
        ],
      ),
    ));

    expect(accepted, isEmpty);

    final Offset firstLocation = tester.getCenter(find.text('Source'));
    final TestGesture gesture = await tester.startGesture(firstLocation, pointer: pointer);
    await tester.pump();

    final Offset secondLocation = tester.getCenter(find.text('Target'));
    await gesture.moveTo(secondLocation);
    await tester.pump();

    await gesture.up();
    await tester.pump();

    expect(accepted, equals(<int>[1]));
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
