import 'package:characters/characters.dart';

/// About half a chapter, ending at a paragraph/word when possible.
String chapterPreview(String body) {
  final graphemes = body.characters;
  if (graphemes.length <= 1) return body;
  var text = graphemes.take(graphemes.length ~/ 2).toString();
  final paragraph = text.lastIndexOf('\n\n');
  if (paragraph >= text.length * .8) {
    text = text.substring(0, paragraph);
  } else {
    final word = text.lastIndexOf(RegExp(r'\s'));
    if (word >= text.length * .9) text = text.substring(0, word);
  }
  return text.trimRight();
}
