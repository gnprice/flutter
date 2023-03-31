// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// TODO(gspencergoog): Remove this tag once this test's state leaks/test
// dependencies have been fixed.
// https://github.com/flutter/flutter/issues/85160
// Fails with "flutter test --test-randomize-ordering-seed=20210721"
@Tags(<String>['no-shuffle'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: deprecated_member_use
import 'package:test_api/test_api.dart' as test_package;

void main() {
  final AutomatedTestWidgetsFlutterBinding binding = AutomatedTestWidgetsFlutterBinding();

  /// Run the callback with [TestWidgetsFlutterBinding.inTest] true, but
  /// don't clean up invariants afterward.
  // Arguably this is exploiting a glitch in the [TestWidgetsFlutterBinding] API,
  // but it sure is handy for these tests.
  Future<void> runInTestWithoutCleanup(Future<void> Function() callback) async {
    await binding.runTest(() async {}, () {});
    await callback();
    binding.postTest();
  }

  group(TestViewConfiguration, () {
    test('is initialized with top-level window if one is not provided', () {
      // The code below will throw without the default.
      TestViewConfiguration(size: const Size(1280.0, 800.0));
    });
  });

  group(AutomatedTestWidgetsFlutterBinding, () {
    test('allows setting defaultTestTimeout to 5 minutes', () {
      binding.defaultTestTimeout = const test_package.Timeout(Duration(minutes: 5));
      expect(binding.defaultTestTimeout.duration, const Duration(minutes: 5));
    });
  });

  group('testTextInput', () {
    // These three tests must run in order -- first using `test`, then `testWidgets`, then `test` again.
    int order = 0;

    test('Initializes httpOverrides and testTextInput', () async {
      assert(order == 0);
      expect(binding.testTextInput, isNotNull);
      expect(binding.testTextInput.isRegistered, isFalse);
      expect(HttpOverrides.current, isNotNull);
      order += 1;
    });

    testWidgets('Registers testTextInput', (WidgetTester tester) async {
      assert(order == 1);
      expect(tester.testTextInput.isRegistered, isTrue);
      order += 1;
    });

    test('Unregisters testTextInput', () async {
      assert(order == 2);
      expect(binding.testTextInput.isRegistered, isFalse);
      order += 1;
    });
  });

  group('setSurfaceSize reset', () {
    int order = 0;
    late final Size defaultSurfaceSize;
    const Size alternateSize = Size(400, 300);

    test('call setSurfaceSize with a non-default value', () async {
      assert(order == 0);
      defaultSurfaceSize = binding.renderView.size;
      assert(defaultSurfaceSize != alternateSize);
      runInTestWithoutCleanup(() async {
        // Set the surface size, without it getting reset at the end of the test,
        // so the next test can confirm it gets reset at the start of that one.
        // In a normal test suite, this is what happens if a test fails after
        // setting the surface size.  Using [runInTestWithoutCleanup] lets us
        // simulate that effect without having a failing test.
        await binding.setSurfaceSize(alternateSize);
      });
      order += 1;
    });

    testWidgets('setSurfaceSize reset to default at start of widget test', (WidgetTester tester) async {
      assert(order == 1);
      expect(binding.renderView.size, defaultSurfaceSize);
      await binding.setSurfaceSize(alternateSize);
      order += 1;
    });

    test('setSurfaceSize reset to default at end of widget test', () {
      assert(order == 2);
      expect(binding.renderView.size, defaultSurfaceSize);
      order += 1;
    });
  });

  group('elapseBlocking', () {
    testWidgets('timer is not called', (WidgetTester tester) async {
      bool timerCalled = false;
      Timer.run(() => timerCalled = true);

      binding.elapseBlocking(const Duration(seconds: 1));

      expect(timerCalled, false);
      binding.idle();
    });

    testWidgets('can use to simulate slow build', (WidgetTester tester) async {
      final DateTime beforeTime = binding.clock.now();

      await tester.pumpWidget(Builder(builder: (_) {
        bool timerCalled = false;
        Timer.run(() => timerCalled = true);

        binding.elapseBlocking(const Duration(seconds: 1));

        // if we use `delayed` instead of `elapseBlocking`, such as
        // binding.delayed(const Duration(seconds: 1));
        // the timer will be called here. Surely, that violates how
        // a flutter widget build works
        expect(timerCalled, false);

        return Container();
      }));

      expect(binding.clock.now(), beforeTime.add(const Duration(seconds: 1)));
      binding.idle();
    });
  });

  testWidgets('Assets in the tester can be loaded without turning event loop', (WidgetTester tester) async {
    bool responded = false;
    // The particular asset does not matter, as long as it exists.
    rootBundle.load('AssetManifest.json').then((ByteData data) {
      responded = true;
    });
    expect(responded, true);
  });
}
