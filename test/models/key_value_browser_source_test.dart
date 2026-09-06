import 'package:flutter_inspector_kit/src/models/key_value_browser_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal host-side implementation, mirroring what a consumer would write.
/// Its existence is the compile-time proof that the interface is implementable.
class _FakeKeyValueSource implements KeyValueBrowserSource {
  final List<String> calls = <String>[];

  @override
  String get name => 'Fake';

  @override
  Future<List<KeyValueEntry>> listAll() async {
    calls.add('listAll');
    return const [
      KeyValueEntry(key: 'token', value: 'abc', type: KeyValueType.string),
    ];
  }

  @override
  Future<void> setValue(String key, Object? value) async {
    calls.add('setValue:$key=$value');
  }

  @override
  Future<void> remove(String key) async {
    calls.add('remove:$key');
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
  }
}

void main() {
  group('KeyValueBrowserSource contract', () {
    test('a host implementation satisfies the interface', () async {
      final KeyValueBrowserSource source = _FakeKeyValueSource();

      expect(source.name, 'Fake');
      expect(await source.listAll(), hasLength(1));
      await source.setValue('token', 'xyz');
      await source.remove('token');
      await source.clear();

      expect(
        (source as _FakeKeyValueSource).calls,
        ['listAll', 'setValue:token=xyz', 'remove:token', 'clear'],
      );
    });
  });

  group('KeyValueEntry', () {
    test('equal when all fields match', () {
      const a = KeyValueEntry(
        key: 'token',
        value: 'abc',
        type: KeyValueType.string,
      );
      const b = KeyValueEntry(
        key: 'token',
        value: 'abc',
        type: KeyValueType.string,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when key differs', () {
      const a = KeyValueEntry(
        key: 'token',
        value: 'abc',
        type: KeyValueType.string,
      );
      const b = KeyValueEntry(
        key: 'other',
        value: 'abc',
        type: KeyValueType.string,
      );

      expect(a, isNot(b));
    });

    test('not equal when value differs', () {
      const a = KeyValueEntry(key: 'n', value: 1, type: KeyValueType.int);
      const b = KeyValueEntry(key: 'n', value: 2, type: KeyValueType.int);

      expect(a, isNot(b));
    });

    test('not equal when type differs', () {
      const a = KeyValueEntry(key: 'n', value: 1, type: KeyValueType.int);
      const b = KeyValueEntry(key: 'n', value: 1, type: KeyValueType.double);

      expect(a, isNot(b));
    });

    test('equal by content for stringList values', () {
      final a = KeyValueEntry(
        key: 'tags',
        value: ['a', 'b'],
        type: KeyValueType.stringList,
      );
      final b = KeyValueEntry(
        key: 'tags',
        value: ['a', 'b'],
        type: KeyValueType.stringList,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when stringList contents differ', () {
      final a = KeyValueEntry(
        key: 'tags',
        value: ['a', 'b'],
        type: KeyValueType.stringList,
      );
      final b = KeyValueEntry(
        key: 'tags',
        value: ['a', 'c'],
        type: KeyValueType.stringList,
      );

      expect(a, isNot(b));
    });

    test('holds a null value', () {
      const entry = KeyValueEntry(
        key: 'missing',
        value: null,
        type: KeyValueType.string,
      );

      expect(entry.value, isNull);
    });

    test('toString contains key and type', () {
      const entry = KeyValueEntry(
        key: 'token',
        value: 'abc',
        type: KeyValueType.string,
      );

      expect(entry.toString(), contains('token'));
      expect(entry.toString(), contains('string'));
    });
  });

  group('parseKeyValueInput', () {
    test('string accepts any input, including empty', () {
      expect(parseKeyValueInput('abc', KeyValueType.string), 'abc');
      expect(parseKeyValueInput('', KeyValueType.string), '');
      // Never trimmed: leading/trailing spaces can be part of a real value.
      expect(parseKeyValueInput('  a  ', KeyValueType.string), '  a  ');
    });

    test('int parses digits and rejects non-integers', () {
      expect(parseKeyValueInput('42', KeyValueType.int), 42);
      expect(parseKeyValueInput('-7', KeyValueType.int), -7);
      expect(parseKeyValueInput('abc', KeyValueType.int), isNull);
      expect(parseKeyValueInput('4.2', KeyValueType.int), isNull);
      expect(parseKeyValueInput('', KeyValueType.int), isNull);
    });

    test('int tolerates surrounding whitespace', () {
      expect(parseKeyValueInput(' 42 ', KeyValueType.int), 42);
    });

    test('double parses decimals and whole numbers', () {
      expect(parseKeyValueInput('4.2', KeyValueType.double), 4.2);
      expect(parseKeyValueInput('42', KeyValueType.double), 42.0);
      expect(parseKeyValueInput(' -0.5 ', KeyValueType.double), -0.5);
      expect(parseKeyValueInput('abc', KeyValueType.double), isNull);
      expect(parseKeyValueInput('', KeyValueType.double), isNull);
    });

    test('bool accepts only true/false, case-insensitively', () {
      expect(parseKeyValueInput('true', KeyValueType.bool), true);
      expect(parseKeyValueInput('TRUE', KeyValueType.bool), true);
      expect(parseKeyValueInput(' False ', KeyValueType.bool), false);
      // '1'/'0' rejected: ambiguous with int, and silently wrong is worse.
      expect(parseKeyValueInput('1', KeyValueType.bool), isNull);
      expect(parseKeyValueInput('yes', KeyValueType.bool), isNull);
      expect(parseKeyValueInput('', KeyValueType.bool), isNull);
    });

    test('stringList splits on newlines', () {
      expect(parseKeyValueInput('a\nb', KeyValueType.stringList), ['a', 'b']);
      expect(parseKeyValueInput('solo', KeyValueType.stringList), ['solo']);
    });

    test('stringList maps empty input to an empty list, not a failure', () {
      expect(parseKeyValueInput('', KeyValueType.stringList), isEmpty);
      expect(parseKeyValueInput('', KeyValueType.stringList), isNotNull);
    });
  });

  group('KeyValueType', () {
    test('covers the five SharedPreferences types', () {
      expect(KeyValueType.values, hasLength(5));
      expect(
        KeyValueType.values,
        containsAll(<KeyValueType>[
          KeyValueType.string,
          KeyValueType.int,
          KeyValueType.double,
          KeyValueType.bool,
          KeyValueType.stringList,
        ]),
      );
    });
  });
}
