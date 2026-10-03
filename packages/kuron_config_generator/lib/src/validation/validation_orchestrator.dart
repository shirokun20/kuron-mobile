// ignore_for_file: avoid_print

import 'dart:io';

import 'backup_manager.dart';
import 'fix_suggestion.dart';
import 'report_parser.dart';
import 'report_printer.dart';
import 'validator_runner.dart';

// Orchestrates the validation lifecycle: run validator, parse report,
// display results, and manage the interactive revalidation loop.
class ValidationOrchestrator {
  // Run a single validation cycle on [configPath].
  // Returns parsed report on success, null if validator unavailable or
  // report cannot be parsed.
  Future<ParsedReport?> runValidator(String configPath) async {
    final jsonString = await ValidatorRunner.run(configPath);
    if (jsonString == null) return null;

    try {
      return ReportParser.parse(jsonString);
    } on FormatException catch (e) {
      stderr.writeln('Warning: Failed to parse validation report: $e');
      return null;
    }
  }

  // Run the full interactive validation loop.
  ///
  // Creates a backup of the config, then iterates up to 20 times,
  // prompting the user to edit and revalidate after each run.
  ///
  // [reportFormat] controls display format (text/json/markdown).
  // [showAllSuggestions] shows fix suggestions even when compatible.
  Future<ParsedReport?> runValidationLoop({
    required String configPath,
    String reportFormat = 'text',
    bool showAllSuggestions = false,
  }) async {
    // R8.1–R8.4: Backup on first entry only
    await BackupManager.createBackup(configPath);
    ParsedReport? last;

    for (var i = 0; i < 20; i++) {
      // R4.6: Check config file still exists
      if (!File(configPath).existsSync()) {
        stderr.writeln(
          'Error: Config file deleted or unreadable — exiting validation loop.',
        );
        break;
      }

      final parsed = await runValidator(configPath);
      if (parsed == null) {
        // Validator fatal error — warning already printed by runValidator
        stderr.writeln(
          'Validation loop ended due to validator error.',
        );
        break;
      }
      last = parsed;
      final suggestions = FixSuggestionMapper.map(parsed.diagnostics);

      // R4.1: Display report using the formatter
      ReportPrinter.printReport(
        parsed,
        suggestions,
        format: reportFormat,
        showAllSuggestions: showAllSuggestions,
      );

      // R4.4: Compatible → exit loop
      if (parsed.overallStatus == 'compatible') {
        break;
      }

      // R4.7: Max iterations reached
      if (i == 19) {
        print(
          'Maximum validation iterations (20) reached — exiting loop.',
        );
        break;
      }

      // R4.1–R4.3, R4.8: User prompt
      while (true) {
        stdout.write(
          'Validation found issues. Review the report above, edit the config, '
          'then press Enter to revalidate, or type \'q\' to quit: ',
        );
        final input = stdin.readLineSync()?.trim() ?? '';

        if (input.isEmpty) {
          // Enter → continue loop
          break;
        }
        if (input.toLowerCase() == 'q') {
          print('Validation loop ended. Generated config at: $configPath');
          return last; // exit loop (R4.3)
        }
        // R4.8: Other input → re-prompt
      }
    }
    return last;
  }
}
