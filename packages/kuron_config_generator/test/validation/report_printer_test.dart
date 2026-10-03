import 'dart:convert';

import 'package:test/test.dart';
import 'package:kuron_config_generator/src/validation/report_printer.dart';
import 'package:kuron_config_generator/src/validation/report_parser.dart';
import 'package:kuron_config_generator/src/validation/fix_suggestion.dart';

void main() {
  final compatibleReport = ParsedReport(
    sourceId: 'mangadex',
    overallStatus: 'compatible',
    featureStatuses: {'home': 'compatible', 'search': 'compatible'},
  );

  final errorReport = ParsedReport(
    sourceId: 'testsite',
    overallStatus: 'configError',
    featureStatuses: {'home': 'compatible', 'reader': 'configError'},
    diagnostics: [
      ReportDiagnostic(
        severity: 'error',
        code: 'reader.configError',
        message: 'No image selector matched.',
        feature: 'reader',
      ),
    ],
  );

  final suggestions = [
    FixSuggestion(
      diagnosticCode: 'reader.configError',
      suggestionText: 'Check reader selector.',
      targetFeature: 'reader',
      configField: 'scraper.selectors.reader',
    ),
  ];

  group('ReportPrinter.formatText (R5.1)', () {
    test('formats compatible report with status', () {
      final output = ReportPrinter.formatText(compatibleReport, []);
      expect(output, contains('[compatible] mangadex'));
      expect(output, contains('home: compatible'));
      expect(output, contains('Config is valid!'));
    });

    test('formats configError report with diagnostics', () {
      final output = ReportPrinter.formatText(errorReport, suggestions);
      expect(output, contains('[configError] testsite'));
      expect(output, contains('reader: configError'));
      expect(output, contains('[error] reader.configError'));
      expect(output, contains('No image selector matched.'));
      expect(output, contains('Fix suggestions:'));
      expect(output, contains('1. [reader.configError]'));
      expect(output, contains('Check reader selector.'));
      expect(output, contains('scraper.selectors.reader'));
    });

    test('hides suggestions for compatible when showAllSuggestions=false', () {
      final output = ReportPrinter.formatText(
        compatibleReport,
        suggestions,
        showAllSuggestions: false,
      );
      expect(output, contains('Config is valid!'));
      expect(output, isNot(contains('Fix suggestions:')));
    });

    test('shows suggestions for compatible when showAllSuggestions=true (R5.4)',
        () {
      final output = ReportPrinter.formatText(
        compatibleReport,
        suggestions,
        showAllSuggestions: true,
      );
      expect(output, contains('Fix suggestions:'));
      expect(output, contains('Check reader selector.'));
    });
  });

  group('ReportPrinter.formatJson (R5.2)', () {
    test('formats valid JSON', () {
      final output = ReportPrinter.formatJson(errorReport, suggestions);
      expect(output, startsWith('{'));
      final parsed = jsonDecode(output) as Map<String, dynamic>;
      expect(parsed['sourceId'], 'testsite');
      expect(parsed['overallStatus'], 'configError');
      expect(parsed['diagnostics'], hasLength(1));
      expect(parsed['fixSuggestions'], hasLength(1));
      expect(parsed['diagnostics'][0]['code'], 'reader.configError');
      expect(parsed['fixSuggestions'][0]['configField'],
          'scraper.selectors.reader');
    });

    test('JSON includes featureStatuses', () {
      final output = ReportPrinter.formatJson(compatibleReport, []);
      final parsed = jsonDecode(output) as Map<String, dynamic>;
      expect(parsed['featureStatuses']['home'], 'compatible');
    });

    test('JSON carries contract schemaVersion', () {
      final output = ReportPrinter.formatJson(compatibleReport, []);
      final parsed = jsonDecode(output) as Map<String, dynamic>;
      expect(parsed['schemaVersion'], '1.0');
    });
  });

  group('ReportPrinter.formatMarkdown (R5.3)', () {
    test('formats markdown with headers and tables', () {
      final output = ReportPrinter.formatMarkdown(errorReport, suggestions);
      expect(output, contains('# Validation Report: testsite'));
      expect(output, contains('**Overall Status:** `configError`'));
      expect(output, contains('## Feature Statuses'));
      expect(output, contains('| home | compatible |'));
      expect(output, contains('## Diagnostics'));
      expect(output, contains('**[error]** `reader.configError`'));
      expect(output, contains('## Fix Suggestions'));
      expect(output, contains('Check reader selector.'));
    });

    test('markdown for compatible report includes checkmark', () {
      final output = ReportPrinter.formatMarkdown(compatibleReport, []);
      expect(output, contains('Config is valid!'));
    });
  });
}
