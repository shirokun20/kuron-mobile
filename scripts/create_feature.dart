// ignore_for_file: avoid_print

import 'dart:io';

// Scaffolds a new feature in Kuron's FLAT Clean Architecture layout:
//
//   lib/domain/entities/<name>.dart
//   lib/domain/usecases/<name>/
//   lib/domain/repositories/            (add interface manually)
//   lib/data/models/<name>_model.dart
//   lib/data/repositories/<name>_repository_impl.dart
//   lib/presentation/cubits/<name>/
//   lib/presentation/pages/<name>/
//   lib/presentation/widgets/<name>/
//
// There is deliberately NO lib/features/ directory in this repo.
// Cubits MUST extend BaseCubit (see presentation/cubits/base/).
// New serializable models MUST use Freezed + JsonSerializable,
// then run: fvm flutter pub run build_runner build --delete-conflicting-outputs
// Finally register the cubit/usecase in core/di/service_locator.dart manually
// (no injectable in this repo).
void main(List<String> arguments) {
  if (arguments.isEmpty) {
    print('Error: Please provide a feature name.');
    print('Usage: dart scripts/create_feature.dart [feature_name]');
    exit(1);
  }

  final raw = arguments[0].toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  if (raw.isEmpty) {
    print('Error: feature name must contain [a-z0-9_].');
    exit(1);
  }
  final pascal = raw
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join();

  print('Scaffolding Clean Architecture for feature: "$raw"...\n');

  final directories = [
    'lib/domain/usecases/$raw',
    'lib/presentation/cubits/$raw',
    'lib/presentation/pages/$raw',
    'lib/presentation/widgets/$raw',
  ];

  for (final dirPath in directories) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      print('  Created: $dirPath');
    } else {
      print('  Exists: $dirPath');
    }
  }

  // Cubit stub extending BaseCubit (ctor: {initialState, logger}).
  final cubitFile = File('lib/presentation/cubits/$raw/${raw}_cubit.dart');
  if (!cubitFile.existsSync()) {
    cubitFile.writeAsStringSync('''
import 'package:logger/logger.dart';
import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';

class ${pascal}State extends BaseCubitState {
  const ${pascal}State();

  @override
  List<Object?> get props => [];
}

class ${pascal}Cubit extends BaseCubit<${pascal}State> {
  ${pascal}Cubit({required Logger logger})
      : super(initialState: const ${pascal}State(), logger: logger);
}
''');
    print('  Created: ${cubitFile.path}');
  } else {
    print('  Exists: ${cubitFile.path}');
  }

  print('\nDone. Next steps (manual):');
  print('  1. Add entity in lib/domain/entities/ + export in entities.dart');
  print('  2. Add repository interface in lib/domain/repositories/');
  print('  3. Add model + impl in lib/data/models/ + lib/data/repositories/');
  print('  4. Register cubit/usecase in lib/core/di/service_locator.dart');
}
