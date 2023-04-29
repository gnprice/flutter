// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Drag and drop 1', (WidgetTester tester) async {
    bool dragAnchorStrategyCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: <Widget>[
          Draggable<int>(
            feedback: const Text('Feedback'),
            dragAnchorStrategy: (Draggable<Object> widget, BuildContext context, Offset position) {
              dragAnchorStrategyCalled = true;
              return Offset.zero;
            },
            child: const Text('Source'),
          ),
        ],
      ),
    ));

    final Offset location = tester.getCenter(find.text('Source'));
    await tester.startGesture(location, pointer: 7);

    expect(dragAnchorStrategyCalled, true);
  });

  testWidgets('Drag and drop 2', (WidgetTester tester) async {
    bool dragAnchorStrategyCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: <Widget>[
          Draggable<int>(
            feedback: const Text('Feedback'),
            dragAnchorStrategy: (Draggable<Object> widget, BuildContext context, Offset position) {
              dragAnchorStrategyCalled = true;
              return Offset.zero;
            },
            child: const Text('Source'),
          ),
        ],
      ),
    ));

    final Offset location = tester.getCenter(find.text('Source'));
    await tester.startGesture(location, pointer: 7);

    expect(dragAnchorStrategyCalled, true);
  });

}
