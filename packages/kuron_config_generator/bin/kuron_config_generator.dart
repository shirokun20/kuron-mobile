#!/usr/bin/env dart
// CLI entry point for Kuron config generator.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:kuron_config_generator/src/commands/generate_command.dart';
import 'package:kuron_config_generator/src/commands/validate_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>(
    'kuron_config_generator',
    'Generate and validate Kuron source configs.',
  )
    ..addCommand(GenerateCommand())
    ..addCommand(ValidateCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    stderr.writeln(e.usage);
    exit(64);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
