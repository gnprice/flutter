import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pumpBenchmark preserves stack trace', () async {
    final TestBinding binding = TestBinding();
    await benchmarkWidgets((WidgetTester tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmark;

      int frame = 1;
      Future<void> pump() => tester.pumpBenchmark(Duration(milliseconds: frame++ * 16));

      await pump();

      binding.beginFrameError = Exception('oops');
      await expectLater(pump(), throwsException);

      // TODO write tests

      binding.beginFrameError = null;
      binding.drawFrameError = null;
    }, mayRunWithAsserts: true);
  });
}

class TestBinding extends LiveTestWidgetsFlutterBinding {
  Object? beginFrameError;
  Object? drawFrameError;

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    if (beginFrameError != null) {
      throw beginFrameError!; // ignore: only_throw_errors
    }
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void handleDrawFrame() {
    if (drawFrameError != null) {
      throw drawFrameError!; // ignore: only_throw_errors
    }
    super.handleDrawFrame();
  }
}
