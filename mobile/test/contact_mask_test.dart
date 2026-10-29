import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/ops/ops_logic.dart';

void main() {
  test('a Kenyan mobile number is masked until the reveal', () {
    expect(maskPhone('0712345123'), '07•• ••• 123');
    expect(maskPhone('0712 345 123'), '07•• ••• 123');
    expect(maskPhone('+254 712 345 123'), '•••••••••123');
  });

  test('empty and unknown shapes never show the middle digits', () {
    expect(maskPhone(''), '');
    expect(maskPhone('123'), '123');
    expect(maskPhone('5551234'), '••••234');
  });
}
