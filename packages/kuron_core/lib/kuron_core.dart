// Core library for Kuron multi-source content app.
// This library provides shared interfaces, entities, and value objects
// that are used across different content source implementations.
library;

// Sources
export 'src/sources/content_source.dart';
export 'src/sources/search_capabilities.dart';
export 'src/sources/content_source_registry.dart';
export 'src/sources/source_factory.dart';
export 'src/sources/source_factory_resolver.dart';

// Entities
export 'src/entities/content.dart';
export 'src/entities/tag.dart';
export 'src/entities/search_filter.dart';
export 'src/entities/content_list_result.dart';
export 'src/entities/filter_item.dart';
export 'src/entities/content_metadata.dart';
export 'src/entities/chapter.dart';
export 'src/entities/chapter_data.dart';
export 'src/entities/comment.dart';
export 'src/entities/autocomplete_suggestion.dart';

// Filters (FilterList system — adapted from TachiyomiSY)
export 'src/filters/source_filter.dart';

// Value Objects
export 'src/value_objects/sort_option.dart';
export 'src/value_objects/popular_timeframe.dart';

// Enums
export 'src/enums/source_type.dart';
export 'src/enums/content_type.dart';

// Exceptions
export 'src/exceptions/login_required_exception.dart';

// Network utilities
export 'src/network/rate_limiter.dart';

// Platform ports (implemented by kuron_special, consumed by kuron_generic)
export 'src/ports/secure_value_store.dart';
export 'src/ports/clearance_driver.dart';
export 'src/network/registrable_domain.dart';

// Compatibility / validation contracts (revamp-kuron-config-runtime)
export 'src/compat/compatibility_status.dart';
export 'src/compat/diagnostic_severity.dart';
export 'src/compat/feature_kind.dart';
export 'src/compat/feature_status.dart';
export 'src/compat/validation_diagnostic.dart';
export 'src/compat/validation_report.dart';

// Source capability contracts
export 'src/capability/source_capability.dart';

// Canonical page resolution models (used by reader + native download)
export 'src/pages/page_request_kind.dart';
export 'src/pages/resolved_page_request.dart';
export 'src/pages/resolved_chapter_pages.dart';

// Secret redaction utilities for diagnostics + persisted reports
export 'src/redaction/secret_redactor.dart';
