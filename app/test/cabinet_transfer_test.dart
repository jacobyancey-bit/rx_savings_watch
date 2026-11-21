import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/services/cabinet_transfer_service.dart';

void main() {
  group('CabinetTransferService', () {
    test('builds zero-server hash fragment transfer link and deduplicates', () {
      final link = CabinetTransferService.buildTransferLink(
        ['197361', '6809', '197361', 'invalid!'],
        baseUrl: 'https://rx.dangling-dice-studios.com/',
      );
      expect(link, 'https://rx.dangling-dice-studios.com/#import=197361,6809');
    });

    test('parses full URL with #import fragment', () {
      final parsed = CabinetTransferService.parseRxcuisFromInput(
        'https://rx.dangling-dice-studios.com/#import=197361,6809,11289',
      );
      expect(parsed, ['197361', '6809', '11289']);
    });

    test('parses RXW short code and strips non-numeric values', () {
      final parsed = CabinetTransferService.parseRxcuisFromInput(
        'RXW:29046, 6918, abc, 29046',
      );
      expect(parsed, ['29046', '6918']);
    });

    test('returns empty list for invalid or empty input', () {
      expect(CabinetTransferService.parseRxcuisFromInput(''), isEmpty);
      expect(CabinetTransferService.parseRxcuisFromInput('hello world'), isEmpty);
    });
  });
}
