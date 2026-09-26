# Kuron Config Generator

Developer tooling for generating Kuron source configs — interactive wizard **and** URL-assisted discovery (HTML → CMS scraper, JSON → REST API).

## Status

**Phase 1 Complete** — Interactive wizard + HTTP discovery shipped ✅
- 27 tests passing, analyzer clean
- Sections 4-6 (browser, GitHub, validation) deferred per YAGNI

## Quick Start

| Goal | Command |
|------|---------|
| Interactive wizard | `fvm dart run ... generate --interactive` |
| HTML site probe | `fvm dart run ... generate --url https://site.com` |
| JSON API probe | `fvm dart run ... generate --url https://api.site.com/endpoint` |
| Validate output | `fvm dart run kuron_generic:kuron_config_validate build/generated/*.json` |
| Deploy | `cp build/generated/*.json <kuron-extensions>/config/new/` |

## Usage

Run from **project root**:

### Interactive Wizard (Manual)

```bash
fvm dart run packages/kuron_config_generator/bin/kuron_config_generator.dart \
    generate --interactive
```

Prompts: source identity, mode (REST / scraper), features, endpoints, headers.  
**Output:** `build/generated/{sourceId}-config.json`

### Theme Detection (recommended)

The generator ships a **theme bank** in code: `cms_detector.dart` holds
signatures (hints + selectors + URL patterns) per CMS theme, and
`config_generator.dart` emits full configs per theme. Signatures are lifted
from live-proven configs — not guesses. Proven config files themselves stay
**private** (`informations/configs/` is gitignored); only the distilled
patterns live in code.

```bash
fvm dart run packages/kuron_config_generator/bin/kuron_config_generator.dart \
    generate --url https://areakomik.com --validate --live
```

- CMS auto-detected from HTML hints (e.g. `areakomik`, `madara`, `zmanga`,
  `mangathemesia`, `hentairhymes`) → full selector set emitted.
- `--validate --live` — readiness validation + 5-screen live smoke through the
  real adapter; on success emits golden fixtures + a dual-mode skeleton test.

### Template Clone (local-only)

On machines that have the private proven configs, `--template` clones one as
the theme verbatim:

```bash
fvm dart run packages/kuron_config_generator/bin/kuron_config_generator.dart \
    generate --template hentaiera --url https://hentaiera.com --validate --live
```

- `--template <sourceId>` — reads `informations/configs/<id>-config.json`
  (gitignored; fresh clones won't have it — use Theme Detection above)
- `--url` — new source's base URL (host becomes the new source id)
- `--validate --live` — readiness validation + 5-screen live smoke through the
  real adapter; on success emits golden fixtures + a dual-mode skeleton test

**Live smoke output:**
```
[I]  🌐 Live smoke validation via real adapter...
[I]    ✓ home: OK (25 items)
[I]    ✓ search: OK (20 items)
[I]    ✓ detail: OK (0 items)
[I]    ✓ chapters: OK (182 items)
[I]    ✓ reader: OK (106 items)
[I]  ✓ Live smoke passed. Fixtures + skeleton test emitted
```

Gallery-only sources (hentaifox family, `reader.mode == "hentaifoxCdn"`) skip
the chapters screen — reader images are probed directly from the detail page.

**Emitted verification test** (`<source>_generated_live_test.dart`) is dual-mode:

```bash
# Offline replay (CI-safe): replays golden fixtures
fvm dart test build/generated/<source>_generated_live_test.dart

# Live mode: hits the real site
LIVE=1 fvm dart test build/generated/<source>_generated_live_test.dart
```

Fixtures land in `build/generated/fixtures/<source>/{home,search,detail,chapters,reader}.html`
plus a `manifest.json`.

### URL-Assisted HTML → Scraper

> ⚠️ Prefer **Theme Detection** above — the theme bank emits proven selectors.
> Use **Template Clone** when a private proven config exists for the exact
> site family. Generic detection is the last resort and often needs fixes.

```bash
fvm dart run packages/kuron_config_generator/bin/kuron_config_generator.dart \
    generate --url https://manhwaread.com/
```

1. HTTP probe with browser User-Agent (blocked/CF sites stop here with a verdict — use `--interactive` for those)
2. **API-first**: hunt hidden JSON endpoints (page-script `/api/...`, Next.js `/_next/data`, WordPress `/wp-json/`, generic `/api/`) — a hit becomes a `rest_json` config as the patokan, no scraper needed
3. Fallback: detect CMS (Madara / WordPress / custom) from HTML signatures
4. Inject candidate selectors into config (list, detail, chapters, reader)
5. Output scraper-mode Source Config v2 (clean sites only — no CF machinery)

**Example probe output:**
```
✓ HTTP 200, 45231 bytes received (html)
📋 CMS detected: madara (100% confidence)
✓ Config generated: build/generated/manhwaread-config.json
💡 Review suggested selectors — adjust paths as needed.
```

### URL-Assisted JSON → REST API

```bash
fvm dart run packages/kuron_config_generator/bin/kuron_config_generator.dart \
    generate --url https://api.example.com/v1/manga
```

1. Detect `content-type: application/json` (or sniff `{` / `[`)  
2. Infer structure — direct array, `data[]`, `results[]`, or single detail object  
3. Detect pagination hints (`page`, `offset`, total count)  
4. Output rest_json-mode Source Config v2 with inferred endpoints

**Example probe output:**
```
✓ HTTP 200, 12304 bytes received (json)
📡 API mode detected — inferred structure:
  isList=true isDetail=false confidence=70%
✓ Config generated: build/generated/api.example.com-config.json
💡 This is a draft — review endpoints and pagination.
```

### Validate & Deploy

```bash
# Validate with runtime validator
fvm dart run kuron_generic:kuron_config_validate \
    build/generated/manhwaread-config.json

# Deploy to extension repo staging, then publish via manifest flow
# (see kuron-source-config skill: bucket foldering + refresh_manifest.py)
cp build/generated/manhwaread-config.json <kuron-extensions>/config/new/
```

> 💡 `build/` is gitignored. Generated output stays local until deployed.

## Architecture

```
kuron_config_generator/
├── bin/
│   └── kuron_config_generator.dart  # CLI entry point
├── lib/src/
│   ├── commands/                   # 3 CLI commands
│   │   ├── generate_command.dart   # Wizard + URL-assisted
│   │   ├── discover_command.dart   # URL discovery (stub)
│   │   └── validate_command.dart   # Validation workflow (stub)
│   ├── models/
│   │   └── wizard_question.dart    # Question models
│   ├── wizard/
│   │   ├── wizard_builder.dart     # Question flow
│   │   └── wizard_runner.dart      # Interactive runner
│   ├── discovery/
│   │   ├── http_probe.dart         # HTTP GET + content-type detect
│   │   ├── cms_detector.dart       # HTML → CMS detection
│   │   └── api_detector.dart       # JSON → API structure
│   └── generator/
│       └── config_generator.dart   # Answers → JSON
└── test/
    ├── commands_test.dart          # CLI tests (4)
    ├── wizard_test.dart            # Wizard flow (3)
    ├── cms_detector_test.dart      # CMS detection (6)
    ├── probe_discovery_test.dart   # Probe + API detection (10)
    └── integration_smoke_test.dart # End-to-end (3)
```

## Generated Config Structure

Produces Source Config Contract v2 compliant JSON:

```json
{
  "source": "example_source",
  "displayName": "Example Source",
  "schemaVersion": "2.0",
  "version": "1.0.0",
  "homeUrl": "https://example.com",
  "features": {
    "home": {"supported": true},
    "search": {"supported": true},
    "detail": {"supported": true},
    "reader": {"supported": true},
    "download": {"supported": true}
  },
  "requiredPrimitives": [
    "imageMode.directUrl",
    "pagination.page",
    "auth.none"
  ],
  "api": {
    "type": "rest_json",
    "url": "https://api.example.com",
    "listEndpoint": "/list",
    "detailEndpoint": "/detail/{id}"
  }
}
```

## Testing

```bash
cd packages/kuron_config_generator

# Run all 27 tests
fvm dart test

# Run specific suite
fvm dart test test/probe_discovery_test.dart
fvm dart test test/cms_detector_test.dart
fvm dart test test/wizard_test.dart
fvm dart test test/commands_test.dart
fvm dart test test/integration_smoke_test.dart
```

## Development

```bash
# Install dependencies
fvm dart pub get

# Run analyzer
fvm dart analyze

# Format code
fvm dart format .
```

## Next Steps

1. **Try interactive**: `generate --interactive` — manual wizard
2. **Try URL-assisted**: `generate --url https://site.com` — auto-detect
3. **Validate**: `kuron_config_validate build/generated/*.json`
4. **Deploy**: `cp build/generated/*.json <kuron-extensions>/config/new/` (staging, then bucket + manifest via kuron-source-config skill)
5. **Test in app**: Import via Settings → Sources → Add Link

## Deferred Features

- Browser discovery — add if JS-rendered sites become common
- GitHub mining — add if bulk config creation from extensions needed
- Validation engine integration — add if `kuron_config_validate` CLI is too manual

Priority based on actual pain, not anticipated pain.

## See Also

- [Source Config Contract v2](../../docs/en/SOURCE_CONFIG_CONTRACT_V2.md)
- [Runtime Validator CLI](../kuron_generic/README.md#kuron_config_validate)
- [revamp-kuron-config-runtime](../../openspec/changes/revamp-kuron-config-runtime/)
