// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'fix_suggestion.dart';
import 'report_parser.dart';

// Formats and prints validation reports in various output formats.
///
// Supported formats: text (R5.1), json (R5.2), markdown (R5.3).
class ReportPrinter {
  // Prints a validation report in the specified [format].
  ///
  // [format] must be one of `text`, `json`, `markdown`.
  // If [format] is invalid, prints error to stderr and exits with code 64 (R5.5).
  static void printReport(
    ParsedReport report,
    List<FixSuggestion> suggestions, {
    String format = 'text',
    bool showAllSuggestions = false,
  }) {
    switch (format) {
      case 'text':
        print(formatText(report, suggestions,
            showAllSuggestions: showAllSuggestions));
      case 'json':
        print(formatJson(report, suggestions));
      case 'markdown':
        print(formatMarkdown(report, suggestions,
            showAllSuggestions: showAllSuggestions));
      default:
        stderr.writeln('Error: Invalid report format "$format". '
            'Allowed: text, json, markdown.');
        exit(64); // R5.5
    }
  }

  // Formats the report as plain text (R5.1).
  static String formatText(
    ParsedReport report,
    List<FixSuggestion> suggestions, {
    bool showAllSuggestions = false,
  }) {
    final sb = StringBuffer();

    sb.writeln('[${report.overallStatus}] ${report.sourceId}');

    if (report.featureStatuses.isNotEmpty) {
      for (final e in report.featureStatuses.entries) {
        sb.writeln('  ${e.key}: ${e.value}');
      }
    }

    if (report.diagnostics.isNotEmpty) {
      sb.writeln();
      sb.writeln('Diagnostics:');
      for (final d in report.diagnostics) {
        sb.writeln('  [${d.severity}] ${d.code}: ${d.message}');
      }
    }

    if (suggestions.isNotEmpty &&
        (showAllSuggestions || report.overallStatus != 'compatible')) {
      sb.writeln();
      sb.writeln('Fix suggestions:');
      for (var i = 0; i < suggestions.length; i++) {
        final s = suggestions[i];
        sb.writeln('  ${i + 1}. [${s.diagnosticCode}] ${s.suggestionText}');
        if (s.configField != null) {
          sb.writeln('     -> Config field: ${s.configField}');
        }
      }
    }

    if (report.overallStatus == 'compatible') {
      sb.writeln();
      sb.writeln('Config is valid!');
    }

    return sb.toString();
  }

  // Formats the report as JSON (R5.2).
  static String formatJson(
    ParsedReport report,
    List<FixSuggestion> suggestions,
  ) {
    final output = <String, Object?>{
      'schemaVersion': '1.0',
      'sourceId': report.sourceId,
      'overallStatus': report.overallStatus,
      'featureStatuses': report.featureStatuses,
      'diagnostics': report.diagnostics
          .map((d) => {
                'severity': d.severity,
                'code': d.code,
                'message': d.message,
                if (d.feature != null) 'feature': d.feature,
              })
          .toList(),
      'fixSuggestions': suggestions
          .map((s) => {
                'diagnosticCode': s.diagnosticCode,
                'suggestionText': s.suggestionText,
                if (s.targetFeature != null) 'targetFeature': s.targetFeature,
                if (s.configField != null) 'configField': s.configField,
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(output);
  }

  // Formats the report as Markdown (R5.3).
  static String formatMarkdown(
    ParsedReport report,
    List<FixSuggestion> suggestions, {
    bool showAllSuggestions = false,
  }) {
    final sb = StringBuffer();

    sb.writeln('# Validation Report: ${report.sourceId}');
    sb.writeln();
    sb.writeln('**Overall Status:** `${report.overallStatus}`');
    sb.writeln();

    if (report.featureStatuses.isNotEmpty) {
      sb.writeln('## Feature Statuses');
      sb.writeln();
      sb.writeln('| Feature | Status |');
      sb.writeln('|---------|--------|');
      for (final e in report.featureStatuses.entries) {
        sb.writeln('| ${e.key} | ${e.value} |');
      }
      sb.writeln();
    }

    if (report.diagnostics.isNotEmpty) {
      sb.writeln('## Diagnostics');
      sb.writeln();
      for (final d in report.diagnostics) {
        final featureTag = d.feature != null ? ' (`${d.feature}`)' : '';
        sb.writeln(
            '- **[${d.severity}]** `${d.code}`$featureTag: ${d.message}');
      }
      sb.writeln();
    }

    if (suggestions.isNotEmpty &&
        (showAllSuggestions || report.overallStatus != 'compatible')) {
      sb.writeln('## Fix Suggestions');
      sb.writeln();
      for (var i = 0; i < suggestions.length; i++) {
        final s = suggestions[i];
        sb.writeln('### ${i + 1}. `${s.diagnosticCode}`');
        sb.writeln();
        sb.writeln(s.suggestionText);
        if (s.configField != null) {
          sb.writeln('- Config field: `${s.configField}`');
        }
        if (s.targetFeature != null) {
          sb.writeln('- Target feature: `${s.targetFeature}`');
        }
        sb.writeln();
      }
    }

    if (report.overallStatus == 'compatible') {
      sb.writeln('---');
      sb.writeln('**Config is valid!**');
    }

    return sb.toString();
  }
}
