import 'package:flutter_test/flutter_test.dart';

void main() {
  test('action count reaches 3 before interstitial eligibility', () {
    int count = 0;
    for (int i = 0; i < 5; i++) {
      count++;
      if (count >= 3) {
        // eligible
        count = 0;
      }
    }
    expect(count, 2);
  });
}
