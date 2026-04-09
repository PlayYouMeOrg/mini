import 'package:flutter_test/flutter_test.dart';

import 'package:mini/session_domain.dart';

void main() {
  group('parseDatingPromptCatalog', () {
    test('parses bundled prompt JSON shape', () {
      final catalog = parseDatingPromptCatalog({
        'mini': {
          'prompts': {
            'icebreakers_level1': {
              'prompts': [
                {'id': 'p1', 'text': 'Prompt 1'},
                {'id': 'p2', 'text': 'Prompt 2'},
              ],
            },
            'activities_level1': {
              'prompts': [
                {'id': 'p3', 'text': 'Prompt 3'},
              ],
            },
          },
        },
      });

      expect(catalog.sets.keys, containsAll(['icebreakers_level1', 'activities_level1']));
      expect(catalog.itemsById['p1']?.text, 'Prompt 1');
      expect(catalog.itemsById['p3']?.text, 'Prompt 3');
    });

    test('parses raw RTDB prompt payload shape', () {
      final catalog = parseDatingPromptCatalog({
        'icebreakers_level1': {
          'prompts': [
            {'id': 'p1', 'text': 'Prompt 1'},
            {'id': 'p2', 'prompt': 'Prompt 2'},
          ],
        },
        'Story': {
          'playerPrompt': 'Choose one from each card.',
          'categories': {
            'Vibe': {
              'items': ['Playful', 'Bold', 'Cozy'],
            },
          },
        },
      });

      expect(catalog.sets.keys, contains('icebreakers_level1'));
      expect(catalog.sets.keys, isNot(contains('Story')));
      expect(catalog.itemsById['p1']?.text, 'Prompt 1');
      expect(catalog.itemsById['p2']?.text, 'Prompt 2');
    });
  });
}
