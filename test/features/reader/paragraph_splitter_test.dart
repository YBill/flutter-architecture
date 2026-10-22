import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/reader/logic/paragraph_splitter.dart';

void main() {
  test(
    'English chunks do not split ordinary words and preserve source offsets',
    () {
      final body =
          'A paragraph with complete English words, sentences and spaces. ' *
          50;
      final result = splitParagraphs(body);
      expect(result.texts.join(), body);
      for (var i = 0; i < result.texts.length - 1; i++) {
        final end = result.starts[i] + result.texts[i].length;
        expect(
          RegExp(r'[A-Za-z]').hasMatch(body[end - 1]) &&
              RegExp(r'[A-Za-z]').hasMatch(body[end]),
          isFalse,
        );
      }
    },
  );
  test('空行分段，段内软换行保留', () {
    final result = splitParagraphs('　　first\n\n　　second\nline2\n\nthird');

    expect(result.texts, ['　　first', '　　second\nline2', 'third']);
    expect(result.starts, [0, 9, 25]);
  });

  test('indexForOffset 定位段首，空行归属下一段', () {
    final result = splitParagraphs('　　first\n\n　　second\nline2\n\nthird');

    expect(result.indexForOffset(0), 0);
    expect(result.indexForOffset(6), 0);
    expect(result.indexForOffset(7), 1);
    expect(result.indexForOffset(8), 1);
    expect(result.indexForOffset(9), 1);
    expect(result.indexForOffset(22), 1);
    expect(result.indexForOffset(24), 2);
    expect(result.indexForOffset(25), 2);
    expect(result.indexForOffset(999), 2);
  });

  test('空正文没有段落', () {
    final result = splitParagraphs('');

    expect(result.isEmpty, isTrue);
    expect(result.indexForOffset(0), -1);
  });

  test('保留解析期插入的零宽空格缩进守卫', () {
    final result = splitParagraphs('\u200b　　首段\n\n\u200b　　次段');

    expect(result.texts, ['\u200b　　首段', '\u200b　　次段']);
    expect(result.starts, [0, 7]);
  });

  test('超长段落分块保留全文和原始偏移，续块不增加段距，也不切开字素', () {
    final body = '👨‍👩‍👧‍👦e\u0301𠮷' * 250;
    final result = splitParagraphs(body);
    expect(result.texts.length, greaterThan(1));
    expect(result.texts.join(), body);
    expect(result.endsParagraph.where((end) => end), hasLength(1));
    expect(result.endsParagraph.last, isTrue);
    final boundaries = <int>{0};
    var boundary = 0;
    for (final character in body.characters) {
      boundary += character.length;
      boundaries.add(boundary);
    }
    var offset = 0;
    for (var i = 0; i < result.texts.length; i++) {
      expect(result.starts[i], offset);
      expect(boundaries, contains(offset));
      offset += result.texts[i].length;
    }
  });
}
