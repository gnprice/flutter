// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/src/rendering/sliver.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class Wrapper extends StatelessWidget {
  const Wrapper({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class StatefulWrapper extends StatefulWidget {
  const StatefulWrapper({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  StatefulWrapperState createState() => StatefulWrapperState();
}

class StatefulWrapperState extends State<StatefulWrapper> {

  void trigger() {
    setState(() { /* for test purposes */ });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  testWidgets('Moving global key inside a LayoutBuilder', (WidgetTester tester) async {
    final GlobalKey<StatefulWrapperState> key = GlobalKey<StatefulWrapperState>();
    await tester.pumpWidget(
      LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        return Wrapper(
          child: StatefulWrapper(key: key, child: Container(height: 100.0)),
        );
      }),
    );
    await tester.pumpWidget(
      LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        key.currentState!.trigger();
        return StatefulWrapper(key: key, child: Container(height: 100.0));
      }),
    );

    expect(tester.takeException(), null);
  });

  testWidgets('Moving GlobalKeys out of LayoutBuilder', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/146379.
    final GlobalKey widgetKey = GlobalKey(debugLabel: 'widget key');
    final Widget widgetWithKey = Builder(builder: (BuildContext context) {
      Directionality.of(context);
      return SizedBox(key: widgetKey);
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) => widgetWithKey,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) => const Placeholder(),
            ),
            widgetWithKey,
          ],
        ),
      ),
    );

    expect(tester.takeException(), null);
    expect(find.byKey(widgetKey), findsOneWidget);
  });

  testWidgets('Moving LayoutBuilder after already dirty', (WidgetTester tester) async {
    int built = 0;
    final GlobalKey key = GlobalKey();
    final Widget target = LayoutBuilder(
      key: key,
      builder: (BuildContext context, BoxConstraints constraints) {
        built += 1;
        MediaQuery.of(context);
        return const SizedBox();
      },
    );
    expect(built, 0);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(400.0, 300.0)),
      child: SizedBox(child: SizedBox(child: target)),
    ));
    expect(built, 1);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(300.0, 400.0)),
      child: SizedBox(child: target),
    ));
    expect(built, 2);
  });

  testWidgets('Moving LayoutBuilder down after already dirty', (WidgetTester tester) async {
    int built = 0;
    final GlobalKey key = GlobalKey();
    final Widget target = LayoutBuilder(
      key: key,
      builder: (BuildContext context, BoxConstraints constraints) {
        built += 1;
        MediaQuery.of(context);
        return const SizedBox();
      },
    );
    expect(built, 0);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(400.0, 300.0)),
      child: SizedBox(child: target),
    ));
    expect(built, 1);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(300.0, 400.0)),
      child: SizedBox(child: SizedBox(child: target)),
    ));
    expect(built, 2);
  });

  testWidgets('Moving global key inside a SliverLayoutBuilder', (WidgetTester tester) async {
    final GlobalKey<StatefulWrapperState> key = GlobalKey<StatefulWrapperState>();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverLayoutBuilder(
              builder: (BuildContext context, SliverConstraints constraint) {
                return SliverToBoxAdapter(
                  child: Wrapper(child: StatefulWrapper(key: key, child: Container(height: 100.0))),
                );
              },
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverLayoutBuilder(
              builder: (BuildContext context, SliverConstraints constraint) {
                key.currentState!.trigger();
                return SliverToBoxAdapter(
                  child: StatefulWrapper(key: key, child: Container(height: 100.0)),
                );
              },
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), null);
  });
}
