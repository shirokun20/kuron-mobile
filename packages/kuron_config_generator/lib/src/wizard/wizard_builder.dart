import '../models/wizard_question.dart';

// Builds the wizard question flow for config generation.
class WizardBuilder {
  // Create the full wizard flow for interactive config generation.
  static WizardFlow buildFlow() {
    return WizardFlow(sections: {
      'identity': _buildIdentityQuestions(),
      'features': _buildFeatureQuestions(),
      'api': _buildApiQuestions(),
      'scraper': _buildScraperQuestions(),
      'headers': _buildHeaderQuestions(),
    });
  }

  static List<WizardQuestion> _buildIdentityQuestions() {
    return [
      WizardQuestion(
        id: 'sourceId',
        prompt: 'Source ID (e.g., "mangadex", "nhentai"):',
        type: QuestionType.text,
        validator: (v) => v?.isEmpty ?? true ? 'Source ID required' : null,
      ),
      WizardQuestion(
        id: 'displayName',
        prompt: 'Display name:',
        type: QuestionType.text,
      ),
      WizardQuestion(
        id: 'version',
        prompt: 'Config version:',
        type: QuestionType.text,
        defaultValue: '1.0.0',
      ),
      WizardQuestion(
        id: 'homeUrl',
        prompt: 'Home URL (e.g., https://example.com):',
        type: QuestionType.text,
        validator: (v) =>
            v?.startsWith('http') ?? false ? null : 'Must be valid URL',
      ),
      WizardQuestion(
        id: 'contentType',
        prompt: 'Content type:',
        type: QuestionType.choice,
        choices: ['manga', 'doujin', 'novel', 'anime', 'other'],
        defaultValue: 'manga',
      ),
    ];
  }

  static List<WizardQuestion> _buildFeatureQuestions() {
    return [
      WizardQuestion(
        id: 'mode',
        prompt: 'Source mode:',
        type: QuestionType.choice,
        choices: ['rest_json', 'scraper'],
        defaultValue: 'rest_json',
      ),
      WizardQuestion(
        id: 'supportsSearch',
        prompt: 'Supports search?',
        type: QuestionType.yesNo,
        defaultValue: 'y',
      ),
      WizardQuestion(
        id: 'supportsChapters',
        prompt: 'Has chapters (vs single-gallery)?',
        type: QuestionType.yesNo,
        defaultValue: 'n',
      ),
      WizardQuestion(
        id: 'supportsComments',
        prompt: 'Has comments?',
        type: QuestionType.yesNo,
        defaultValue: 'n',
      ),
      WizardQuestion(
        id: 'searchFormPreset',
        prompt: 'Search form preset:',
        type: QuestionType.choice,
        choices: [
          'none',
          'madara-wp',
          'mangathemesia-wp',
          'foolslide',
          'mangabox',
          'custom',
        ],
        defaultValue: 'none',
      ),
    ];
  }

  static List<WizardQuestion> _buildApiQuestions() {
    return [
      WizardQuestion(
        id: 'apiBase',
        prompt: 'API base URL (or empty for scraper mode):',
        type: QuestionType.text,
        isRequired: false,
      ),
      WizardQuestion(
        id: 'listEndpoint',
        prompt: 'List endpoint (e.g., /api/list):',
        type: QuestionType.text,
        isRequired: false,
      ),
      WizardQuestion(
        id: 'detailEndpoint',
        prompt: 'Detail endpoint (e.g., /api/detail/{id}):',
        type: QuestionType.text,
        isRequired: false,
      ),
    ];
  }

  static List<WizardQuestion> _buildScraperQuestions() {
    return [
      WizardQuestion(
        id: 'listSelector',
        prompt: 'List item CSS selector (or empty for API mode):',
        type: QuestionType.text,
        isRequired: false,
      ),
      WizardQuestion(
        id: 'detailTitleSelector',
        prompt: 'Detail title CSS selector:',
        type: QuestionType.text,
        isRequired: false,
      ),
      WizardQuestion(
        id: 'genreSearchUrl',
        prompt: 'Genre archive URL pattern (empty = theme default):',
        type: QuestionType.text,
        isRequired: false,
      ),
      WizardQuestion(
        id: 'tagSearchUrl',
        prompt: 'Tag archive URL pattern (empty = theme default):',
        type: QuestionType.text,
        isRequired: false,
      ),
      WizardQuestion(
        id: 'authorSearchUrl',
        prompt: 'Author archive URL pattern (empty = theme default):',
        type: QuestionType.text,
        isRequired: false,
      ),
      WizardQuestion(
        id: 'artistSearchUrl',
        prompt: 'Artist archive URL pattern (empty = theme default):',
        type: QuestionType.text,
        isRequired: false,
      ),
    ];
  }

  static List<WizardQuestion> _buildHeaderQuestions() {
    return [
      WizardQuestion(
        id: 'needsHeaders',
        prompt: 'Requires custom headers (Referer, User-Agent)?',
        type: QuestionType.yesNo,
        defaultValue: 'n',
      ),
      WizardQuestion(
        id: 'referer',
        prompt: 'Referer header (if needed):',
        type: QuestionType.text,
        isRequired: false,
      ),
    ];
  }
}
