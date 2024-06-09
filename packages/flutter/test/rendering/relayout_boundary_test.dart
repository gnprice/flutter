// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: dead_code, avoid_print, flutter_style_todos

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('relayout boundary change does O(1) work', (WidgetTester tester) async {
    late StateSetter setState;
    Brightness brightness = Brightness.light;
    const int depth = 8;

    const Size size = Size.square(100);
    Widget inner = SizedBox.fromSize(size: size);
    for (int i = 0; i < depth; i++) {
      inner = SizedBox(child: inner);
    }
    inner = Align(child: inner);
    inner = _LayoutBoundarySometimes(parity: false, size: size, child: inner);
    Widget outer = StatefulBuilder(builder: (BuildContext context, StateSetter setter) {
      setState = setter;
      final MediaQueryData data = MediaQueryData(platformBrightness: brightness);
      return MediaQuery(data: data, child: inner);
    });
    outer = Align(child: outer);
    outer = SizedBox.fromSize(size: size, child: outer);
    outer = Align(child: outer);

    await tester.pumpWidget(outer);
    await tester.pump(const Duration(seconds: 1));

    for (int i = 0; i < 4; i++) {
      print('\ni = $i');
      setState(() {
        brightness = i.isEven ? Brightness.dark : Brightness.light;
      });
      await tester.pump();
    }

    // TODO this test doesn't actually check anything; was useful in combination
    //   with some debug-printing, toward developing a microbenchmark:
    //   //dev/benchmarks/microbenchmarks/lib/layout/relayout_boundary_test.dart
  });
  return;

  testWidgets('relayout boundary change does not trigger relayout', (WidgetTester tester) async {
    final RenderLayoutCount renderLayoutCount = RenderLayoutCount();
    final Widget layoutCounter = Center(
      key: GlobalKey(),
      child: WidgetToRenderBoxAdapter(renderBox: renderLayoutCount),
    );

    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: Center(
                child: layoutCounter,
              ),
            ),
          ),
        ),
      ),
    );

    expect(renderLayoutCount.layoutCount, 1);

    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: layoutCounter,
        ),
      ),
    );

    expect(renderLayoutCount.layoutCount, 1);
  });
}

class _LayoutBoundarySometimes extends StatelessWidget {
  const _LayoutBoundarySometimes({
    required this.parity,
    required this.size,
    required this.child,
  });

  final bool parity;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    print('$parity, $brightness, ${parity != (brightness == Brightness.light)}');
    if (parity != (brightness == Brightness.light)) {
      return SizedBox.fromSize(size: size, child: child);
    } else {
      return SizedBox(child: child);
    }
  }
}

// This class is needed because LayoutBuilder's RenderObject does not always
// call the builder method in its PerformLayout method.
class RenderLayoutCount extends RenderBox {
  int layoutCount = 0;

  @override
  void performLayout() {
    layoutCount += 1;
    size = constraints.biggest;
  }
}
