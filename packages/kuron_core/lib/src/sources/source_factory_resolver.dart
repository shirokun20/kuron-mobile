import 'dart:developer';
import 'content_source.dart';
import 'source_factory.dart';

// Resolves the raw JSON configuration to the appropriate [SourceFactory]
// and instantiates the [ContentSource].
///
// This is used internally by [ContentSourceRegistry] and [SettingsScreen]
// to ensure that sources like `crotpedia` correctly use their custom adapters
// instead of falling back to the default `GenericSourceFactory`.
class SourceFactoryResolver {
  final List<SourceFactory> _factories;
  final SourceFactory _defaultFactory;

  SourceFactoryResolver({
    required this._factories,
    required this._defaultFactory,
  });

  // Returns the appropriate [SourceFactory] for the given raw config.
  SourceFactory resolve(Map<String, dynamic> rawConfig) {
    final String sourceId = rawConfig['source'] as String? ?? '';

    for (final factory in _factories) {
      if (factory.sourceId == sourceId) {
        log('SourceFactoryResolver: Matched $sourceId to ${factory.runtimeType}');
        return factory;
      }
    }

    log('SourceFactoryResolver: No explicit factory for $sourceId, using ${_defaultFactory.runtimeType}');
    return _defaultFactory;
  }

  // Instantiates a [ContentSource] directly using the resolved factory.
  ContentSource createSource(Map<String, dynamic> rawConfig) {
    final factory = resolve(rawConfig);
    return factory.create(rawConfig);
  }
}
