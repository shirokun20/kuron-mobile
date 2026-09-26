# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### 🐛 Fixed

- **Import from NClient failed on every backup** (`Invalid argument(s): Illegal argument in isolate message: object is unsendable`, surfaced as a snackbar): `Isolate.run(() => _parser.parseBytes(data))` captured the whole use case via the `_parser` field, dragging `ReaderRepositoryImpl` → `Logger` (which holds an unsendable internal `Future`) across the isolate boundary. The closure now receives only a hoisted field-less parser plus the file bytes. The Kuron restore path was audited and is safe (its closure constructs the parser inside the isolate). Reported on issue #50, fix shipped in v0.9.27+37.
- **NClient import had zero logs on the tap path**: `pickAndParse` now logs pick started / picked byte size / parsed row counts per table / pick + parse failures with stack trace (and still rethrows, so UI behavior is unchanged); `import` logs started, per-category completion, and the final summary; pick and progress-flow failures are logged with the error. Reproduce on device and filter `adb logcat | grep -i nclient`.

### 🧪 Tests

- NClient import: +3 unit (picker-throw and parse-garbage rethrow with asserted log lines via an in-memory `LogOutput`; isolate-capture regression with a `Logger`-holding fake repository that is red-proven without the fix) + widget `Logger` registration for the now-logging failure path. 18/18 green, analyze clean.

## [0.9.27+37] - 2026-09-26

### ✨ Added

- **Kuron Backup & Restore** (openspec: `kuron-full-backup`, archived 2026-09-26): One-tap backup of the whole library + settings to a versioned `KuronBackup_<epoch>.zip` (`kuron-database.json`, `formatVersion: 1`) — favorites with gallery metadata, favorite collections + memberships, history entries, reader positions, and settings. No image bytes (metadata only), so a backup stays KB–MB. Export pages through `getHistory`/`getAllReaderPositions` (both paginated, default 50 — a single call would silently truncate). Restore is non-destructive with the same merge policy as the NClient importer: existing favorites skipped, collections merged by exact name (unioned memberships), history/positions filled only when absent, settings device-wins per key. A newer `formatVersion` aborts before any write; missing categories restore as empty; malformed rows are counted, never abort. UX reuses the NClient flow: preview counts → progress per category → succeeded/skipped/failed summary. New **BACKUP & RESTORE** section in Settings next to *Import from NClient*. Delivery = temp file + system share sheet (same pattern as `ExportService.shareExport()`) — no new native code, no new dependency. 11 new l10n keys (en/id/zh). 29 new tests + `integration_test/kuron_backup_roundtrip_test.dart` (device round-trip against real SQLite).
- **Import from NClient** (openspec: `nclient-v2v3-import`, archived 2026-09-26): Import a NClient V2/V3 `Backup_*.zip` (or raw `Database.json`) into Kuron with the same preview → progress → summary flow. Accepts `Database.json`/`database.json` case-insensitively, ignores `__MACOSX/`, and never materializes `Tags`/`GalleryTags` (a real backup holds 85k+ tag rows ≈ 7.7 MB for 5 galleries — typed models there risk OOM); `Downloads`/`Bookmark`/`Settings`/`ScrapedTags` are ignored entirely. **3 P0 bugs fixed against the upstream NClient sources**: (1) `Resume` reading positions were dropped whenever the `Gallery` row was absent — NClient prunes galleries outside `Downloads ∪ Favorite ∪ StatusManga` in `onOpen`, so real backups lose positions; they now import with `totalPages` 0 and title/cover fallbacks from `History` (page clamped `1..totalPages`, floored at 1, and `page` is 1-based — `ZoomActivity.java:303` stores `actualPage + 1`); (2) V2 `History.thumbType` is an `ImageExt` **ordinal int**, not a URL, so the `as String?` cast threw `TypeError` and silently lost *every* V2 history row; (3) V2 `Gallery.pages` is a compact run-length string (`"270pj35w245j"`, no `;`, V2 knows only `j`/`p`/`g`) which yielded page count 0 and a wrong cover extension. Validated against both real reporter backups from issue #50 (`Backup_92026_1046.zip`, `Backup_92226_548.zip`). **4 P1 follow-ups**: the progress dialog can no longer get stuck when `import()` throws (`barrierDismissible: false` + `late final summary` could leave the flow hanging or throw `LateInitializationError`) — idempotent settle + post-frame pop close both the fast and slow paths; parsing the 6.8 MB `Database.json` moved off the UI isolate (`Isolate.run`); preview counts are now honest (favorites = `Favorite ∪ StatusManga` galleries, positions only rows carrying id + page, `memberships` key dropped) with the invariant `keys(preview) ⊆ keys(summary)`; unreadable rows surface as a `malformed` row in the summary. 16 unit + 2 widget tests.
- **Per-key settings snapshot on `SettingsRepository`** (additive, used by the backup above): `exportSettingsKeys()` returns the raw per-key payload (same as `exportSettings()` minus `exportedAt`/`version`, only keys that actually hold a value), and `importSettingsKeys(values, {onlyIfAbsent: true})` returns `(applied, skipped)`. The legacy `importSettings()` overwrote the whole blob unconditionally, so per-key *device wins* was impossible; the old contract is untouched. Keys unknown to the app version are skipped, never failed. `content_filter_settings`, `proxy_settings` and `debug_settings` are intentionally excluded — the legacy exporter never produced them, so importing them would restore state the exporter could not have created. 6 round-trip tests.

### 🐛 Fixed

- **Splash hung on "Initializing tag database…"**: `assets/configs/tags-config.json` holds an empty `sources` map (480 B), so the tag loop was doing zero work — the label was a red herring. The real wait was the **Cloudflare check** (`checkCloudflareStatus()` → `RemoteDataSource.initialize()` with `cloudflareBypass.attemptBypass` + retry/rate-limit) and it only ever applied to nhentai, the legacy source. New `needsLegacyCloudflare(registry)` gates it on the active source config (config-driven sources carry `network.requiresBypass` and are bypassed lazily by `ReaderCubit`), the check result is cached in prefs with a 30-min TTL (written on all three success paths), and the label is only emitted when the manifest actually has sources. Next cold start skips the round trip. 5 new tests.
- **doujin.desu.xxx genres picker and by-tag search were effectively dead**: tag queries were sent as literal tag names to `/api/manga` (`/api/manga?search=Sole%20Male` returned 1 of 1,481 hits) because there was no `navigation.tagQueryMapping`, and the adapter treated `tagName` as free text. `navigation.tagQueryMapping` now maps raw tags → taxonomy slugs per facet (genre → `taxonomy_genre`, artist → `taxonomy_artist`, character → `taxonomy_character`, parody → `taxonomy_parody`, group → `taxonomy_group`, country/language/misc → `name`) with `valueSource: tagName` + `transform: lowercase` — the `tagIdOrName` trap returns `=0`. The adapter routes through `/api/taxonomy/<genres|artists|groups>/<slug>?page&sort&limit=30`, reads `pagination{total,totalPages}` plus a `x-total-count` header, parses `term_list` (artist/author/character/parody/circle) and `genres`, and the picker data source is configurable per source (`itemsPath`, `valuePath`, `decrypt`, `sort`). Verified live: genre *1* → **30** items, page 227 empty ✓, 149 genres / 30 authors / 2 groups / 1 character.
- **Cronet + AGP 9 manifest merge failure** (`Namespace 'org.chromium.net' is used in multiple modules and/or libraries`): `--dart-define=cronetHttpNoPlay=true` selects `org.chromium.net:cronet-embedded`, whose AARs (`cronet-api`, `cronet-shared`, `cronet-common`) all declare the same namespace, and AGP 9 flipped `android.uniquePackageNames` to `true`. `android/gradle.properties` now sets `android.uniquePackageNames=false` (Google's official mitigation, restoring the AGP 8 warning behavior). Verified with a full `devRelease` APK build.

### 🔧 Changed

- **`AGENTS.md` is now the single source of truth for AI tooling**: the surviving rules from `CLAUDE.md` were merged in (layer map with the `lib/domain/` pure-Dart constraint, import ordering, full branch list, the "always warmup before benchmarking" rule, dormant-code notes for the unused Rust image pipeline), and two false claims were corrected — DI is **manual** `get_it` registration (there is no `injectable` codegen) and the project is **Android-only** (no `ios/`, so `flutter build ipa` is irrelevant). `CLAUDE.md` and `.github/copilot-instructions.md` were deleted so no second rule set can drift.

### 🧪 Tests

- Kuron backup: serializer/parser 11, restore use case 8 (stateful fakes, also proving the membership path does not double-add), settings parity 6, widget restore flow 4, plus a device-only `integration_test/kuron_backup_roundtrip_test.dart` (seed → export → wipe → restore → assert counts, 1 favorite, 1 collection membership, 1 history, 1 reading position, identical settings snapshot, then a second restore proving device-wins).
- NClient import: 16 unit (dual `pages` encodings, V2 int `thumbType`, ZIP multi-entry decoys, resume without `Gallery`, page clamp/floor, 85k-tag skip) + 2 widget.
- `fvm dart analyze lib test` and `integration_test/` clean.

## [0.9.26+36] - 2026-09-06

### ✨ Added

- **Dynamic AI model catalog and provider expansion** (openspec: `ai-model-lov`): AI provider settings now load live model lists from each provider's verified `/models` endpoint instead of hardcoded model IDs or fallback lists. Added Meta Model API/Muse Spark, ClinePass, and Cohere provider types; Cohere uses native `v2/chat` with `image_url` support and `v1/models` vision metadata. Non-custom providers expose live LOV selection, nullable API-derived vision flags, searchable large lists, manual-entry fallback, stale-model handling, and per-type/key-hash in-memory caching. Added a dedicated clean `aiDio` without browser headers, Cohere-safe neutral image-translation prompts, 90-second AI request timeouts, and `isClosed` guards preventing post-dispose Cubit emits. Verified with `fvm dart analyze lib test` and focused model-catalog/Cubit tests.
- **Manual bubble shape tools in AI translate draw mode** (openspec: `improve-reader-translation-draw-and-architecture`): Three drawing tools — Rectangle (legacy behavior), Ellipse (inscribed ~24-point polygon, live `addOval` preview) and Freeform (path trace with terminal backtracking trim + greedy simplification, cap 160 points). Tool row in the draw-mode controls with icons and l10n labels (en/id/zh `aiDrawRect`/`aiDrawEllipse`/`aiDrawFreeform`). Manual bubbles now carry their polygon shape end-to-end: gesture → `BubbleBox.shape` → cubit → reattach post-AI via `_nearestManualShape` (interArea/smaller ≥ 0.6) → shape-aware rendering (smooth midpoint-quadratic bezier for oval/jagged, sharp rect for frame/narration boxes via `isRectLikePolygon` ≥ 0.95). Provider prompt stays rect-only — no model changes. Files: `reader_translation_draw_mode.dart`, `reader_translation_cubit.dart`, `reader_translation_widgets.dart`, `lib/l10n/*.arb`.
- **`DownloadService.fetchRemoteImageBytes`** (openspec: `improve-reader-translation-draw-and-architecture`): Presentation no longer builds raw `Dio` GETs for capture-time page bytes — `reader_mode_widgets.dart` calls `DownloadService.fetchRemoteImageBytes(sourceId, url)` which reuses the source's header pipeline (`_getHeadersForSource`; send/receive timeouts 30/60s). Removes the direct `getIt<Dio>` dependency from the reader screen.
- **`SaveGlossaryEntryUsecase`** (openspec: `improve-reader-translation-draw-and-architecture`): New domain use case wrapping `GlossaryRepository.save`, registered in DI; the translated-bubble sheet no longer touches the repository directly.
- **Show last update on cards** (openspec: `show-last-update-on-cards`, archived 2026-09-02): Home & by-tag cards show relative update time. **UI**: `MainGridCard`/`MainFeaturedCard` + `RelativeTimeUtils` (epoch/future guard, l10n en/id/zh `releasedLabel`/`updatedLabel` + `justNow`/`daysAgo` etc.). **Mapper**: Indonesian `menit/jam/hari/minggu/bulan/tahun lalu` + `baru saja`/`kemarin` parsing in `GenericContentMapper`. **Config**: `mangadex` `api.list.fields` `uploadDate: $.attributes.updatedAt`, `komikcast` `$.updatedAt`, `rawdevart` `manga_chapters[0].chapter_date_published`, `komiku` `.judul2` (optional). **E-Hentai**: `EHentaiScraperAdapter` extracts `posted_*/postedpop_*` (`2026-09-02 12:29`) per row → `postedDate` → `Content.uploadDate` enrichment. **DoujinDesu.xxx/Hitomi**: already have dates via adapter (`created_at`/`gallery['date']`), no config patch needed. Verified device.
- **MangaDex external chapter support** (openspec: `mangadex-external-chapter-support`, archived 2026-09-01): Dual-mode chapter handling — internal (`externalUrl=null`, `pages>0`, at-home valid) vs external (`externalUrl=comikey.com`, `pages=0`, at-home `hash:"" data:[]`). **Domain**: `Chapter` entity `externalUrl/pages/isUnavailable` + `isExternal`/`isReadableInApp` (`packages/kuron_core`). **Config**: `informations/configs/mangadex-config.json` `api.detail.chapters.fields` `externalUrl/pages/isUnavailable/title` via JSONPath. **Mapper**: `GenericContentMapper.toChapter` nullable backward-compat. **Adapter**: `GenericRestAdapter` guard skip at-home for external + no-retry on empty hash, `fetchChapters` extract new fields. **Persistence**: `ContentModel` `fromMap`/`toMap` + `reader_route_extra` serialize `externalUrl/pages/isUnavailable`. **Presentation**: `ChapterListBottomSheet` & `DetailInfoSections` badge `External • <host>` + `open_in_new` icon, tap external → `launchUrl(externalApplication)` with `Uri.tryParse`+`canLaunchUrl` guard, internal → `DetailCubit.openChapter`; full-external hint + download guard snackbar. **L10n**: 4 keys `externalChapterBadge/Hint/OpenFailed/DownloadBlocked` (en/id/zh). **Pipeline**: `PageResolutionPipeline` `externalChapter` diagnostic (info). Files: `chapter.dart`, `generic_content_mapper.dart`, `generic_rest_adapter.dart`, `content_model.dart`, `reader_route_extra.dart`, `detail_cubit.dart`, `chapter_list_bottom_sheet.dart`, `detail_info_sections.dart`, `download_button_widget.dart`, `page_resolution_pipeline.dart`, `lib/l10n/*.arb`, `CONFIG-GUIDE.md`.
- **Offline group-level pagination & source buckets** (openspec: `offline-ai-polish-pack`): `OfflineSearchCubit` browse + search paths now fetch filtered rows, group into series via `ContentGroup`/`_groupContent`, and slice 20 groups per page — `totalResults`/`hasMore`/`currentPage`/`totalPages` are group-based (1 series × 20 chapters = 1 group, not 20 rows). `loadMore` appends the next 20 groups; sort/filter reset to page 1. New `availableSourceIds` state (distinct store sources, refreshed on unfiltered loads) drives the All + per-source `FilterChip` row in `OfflineContentBody` (falls back to remote-config list pre-load); selection persists in `offline_selected_source_filter`.
- **Mosaic quality tiers** (openspec: `offline-ai-polish-pack`): `MosaicQuality { low, high }` + `AiPreferencesRepository.get/setMosaicQuality` (SharedPreferences, default `high`). `MosaicBuilder.buildMosaic(..., quality:)` — low = JPEG 75 cap 1 MB (Dart encoder, skips the fixed-quality Rust path), high = legacy JPEG 85 cap 2 MB; both keep 2× bubble scale with downscale loop until cap or width ≤ 64. Wired through `ReaderTranslationCubit` (incl. single-bubble retry) with an AI Settings dropdown (l10n en/id/zh `aiMosaicQuality*`).
- **Glossary-aware translation prompts** (openspec: `offline-ai-polish-pack`): before each mosaic request, `ReaderTranslationCubit` loads `GlossaryRepository` and injects up to 5 relevant entries as `Glossary: "src" -> "dst"` lines — substring match (case-insensitive, timestamp-desc) against known bubble texts (same-content previous result, retry bubble), most-recent-5 fallback on fresh pages. Threaded via `translatePage(glossaryContext:)` into OpenAI/Gemini/Cohere mosaic prompts inside the same single AI request.
- **Reader model switcher**: new ⋮-menu item "Ganti model" (`showReaderModelSwitcherSheet`) listing already-configured vision-capable providers (name + model, current default checked) → `setDefault(id)` + snackbar. No add/manage here (stays in Settings); takes effect on next translate. L10n en/id/zh `aiSwitchModel`/`aiModelSwitched`.
- **Structured translate-pipeline logging**: every provider `translatePage` logs start (model/mosaic/bubbles/bytes/glossary), truncated raw-response preview + latency (debug), mapped N/M counts (info), and on `AiTranslationException` an error with the raw preview before rethrow. `ModelJsonParser` logs which candidate decoded (+repaired flag); placeholder echoes log a warning; cubit logs provider+tier+glossary per translate plus per-attempt/fallback lines. Privacy: truncated previews, glossary on/off only, prompts/images never logged, debug-level stripped in release (DevelopmentFilter).

### 🐛 Fixed

- **MangaDex chapters not showing for non-external manga** (openspec: `mangadex-external-chapter-support`): `informations/configs/mangadex-config.json` `api.queryRules.chapters.ensureParams.includeExternalUrl=1` filtered to *only* external chapters — manga with 0 external (e.g. `143ed116...` Tonari no Seki) returned `total=0` vs `53` without param; `69dcebee...` (all external) `=0` → 0 vs `=1` → 4; mixed `f9c33607...` 458 vs 33. **Fix**: removed `ensureParams` — without param API returns both types with `externalUrl` still present (`has_key=True` verified), `fvm dart analyze` clean, JSON OK. Docs updated to warn against `includeExternalUrl`.
- **MangaForFree online reader blank pages** (openspec: `fix-mangaforfree-reader-online-blank`, archived 2026-08-27): Three root causes fixed: (1) `reader_cubit` emitted `loaded` with empty `imageUrls` on online-fetch failure → now emits explicit error state with retry action; (2) `_buildSinglePageReader` and `_buildVerticalPageReader` did not pass `sourceId` to `_ReaderImageViewer`, so bypass headers (Cookie/UA) never reached the image loader → all 3 reader modes now pass `sourceId`; (3) `_resolveAttribute` treated `_result.jpg` (WP-manga lazy-load placeholder) as a valid image src and never fell back to `data-src` where real URLs live → added `_result.jpg` to `_kPlaceholderSrcPattern`. Cloudflare bypass recovery (`cf_mangaforfree`) already triggers on challenge detection and retries once after clearance. 2 tasks deferred (H2 chapter-id mismatch not confirmed, H3 prefetch rate-limit not confirmed).
- **Draw-mode controls pill sluggish / sometimes unopenable in continuous scroll**: Two overlapping tap-zone bugs at the bottom-center: (1) the floating page indicator (`bottom: 24`, `AnimatedOpacity` 0 while idle but still hit-testable) sat on top of the draw pill (`bottom: 20`) and swallowed its taps; (2) the raw-tap `Listener` in continuous scroll fired `toggleUI()` on every pill tap — flashing the chrome, rewriting `showUI` to SharedPreferences, and flipping system UI for a 280ms slide animation, which read as "lag". Fixes in `reader_mode_widgets.dart`: the tap-middle handler now returns early whenever draw mode is active (draw mode owns all taps — drawing / bubble removal), and the floating page indicator is only mounted in continuous scroll when draw mode is off (it is useless while drawing). Draw-mode entry still reads no images (pure flag flip) — image work only happens on Detect/Translate, with ONNX inference on a background executor thread.
- **Manual bubbles silently dropped when tapping translate** (full-manual draw flow): `capturePage` wiped `_manualBubbles` whenever the capture signature changed, and translate re-captures the page before running — so every manual bubble drawn was deleted the moment the user tapped Translate, and the page fell back to full-image upload. `capturePage` now keeps manual bubbles (user corrections are authoritative for the active page; `resetPage` on page navigation still clears them). New regression tests: manual bubble survives re-capture, manual bubble still reaches the mosaic after re-capture.
- **Translate re-ran ONNX detection even with user boxes present**: `translatePage` detected again whenever `_detectedBoxes` was empty, ignoring manual bubbles — a full-manual page ran the 2.6s ONNX wait and (with the previous wipe) threw away the user's work. The detect guard is now `_manualBubbles.isEmpty && _detectedBoxes.isEmpty` — user-drawn boxes OR a draw-mode 🛰 detection short-circuit detection entirely. `capturePage` also keeps detected boxes across re-capture of the same logical page (re-detecting after the user pressed Detect first defeats the purpose; `resetPage` clears on real page navigation). New tests: manual-only translate → 0 ONNX calls; 🛰 boxes survive re-capture → 1 ONNX call total.
- **Translate returned the stale cached result after the user drew manual bubbles**: the translation cache key (`contentId:pageIndex:imageUrl#cropYTop`) does not include manual bubbles — if the page was translated before (or prefetched), tapping translate again replayed the old result and the user's freshly drawn bubbles never reached the AI. `translatePage` now bypasses the cache whenever `_manualBubbles` is non-empty (the cached result was generated without them) and runs the full mosaic pipeline. Regression test: translate → draw manual → translate again must re-run the pipeline and translate the manual bubble.
- **Equatable cubit state not re-emitting on manual-bubble mutations**: `ReaderTranslationCubit` manual/detected mutators (`addManualBubble`, `undoLastManual`, `removeManualBubble`, `clearManualBubbles`, `removeDetectedBubble`) now bump the internal `uiVersion` so the bloc emits a new state — previously undo/clear could leave the UI stale (e.g. red manual boxes not disappearing) because the state object compared equal.
- **All-tab hang on large offline libraries (3000+ rows)**: group-then-slice ran `getOfflineFirstImagePath` (~30 `File.exists()` per content) + `getReaderPosition` per row for ALL rows before first paint, so the All tab sat on shimmer indefinitely. Now two-phase: lightweight conversion + full grouping with no I/O (`_groupContent(..., includeReaderPositions: false)`), then `_enrichGroupWindow` resolves covers + positions for the visible 20 groups only (top-up when missing-cover drops leave the page short); `_consumedGroupCount` cursor lets `loadMore` continue without re-resolving. `TitleParserUtils` regexes hoisted to `static final`.
- **"Failed to parse model JSON" on weak-model template echo**: small models echo the prompt's example literally (literal `...` + translated placeholders like `<bacaan latin>`/`<terjemahan>`), and the naive single-attempt `_parseJson` failed the whole page while the raw `FormatException` leaked into the snackbar. New shared `ModelJsonParser` (all 3 providers, mosaic + full-image): fence strip, string-aware balanced extraction from every opener, mosaic-root validation (numeric keys, blocks nested shadowing), `...`/trailing-comma repair as fallback, user-actionable throw. `_mapMosaicResult` skips whole-value placeholders (`^<[^<>]*>$`, `...`) — partial echoes still yield real bubbles; all-placeholder throws a friendly retry/switch-model error while legit all-SKIP still returns empty. Mosaic prompts no longer contain `...` and carry an explicit never-output-placeholders rule.

### 🔧 Changed

- **`addManualBubble` signature** (openspec: `improve-reader-translation-draw-and-architecture`): `addManualBubble(Rect)` → `addManualBubble(BubbleBox)` — the bubble now carries its polygon `shape` (null = rect). Call sites updated; test fixtures use `BubbleBox(x,y,w,h,confidence:1.0)`.
- **`removeDetectedBubble`** marked `@Deprecated` — kept for the single draw-mode tap-to-delete handler.

### 🧪 Tests

- `reader_translation_cubit_test.dart`: 35/35 pass — new group 'manual bubble shape tools (D1-D3)': shape kept through `addManualBubble` + state bump, undo/remove/clear emit bumps, `removeDetectedBubble`, containment dedup provenance (`_manualCovers` semantics verified unchanged: inner rect dropped, 30% overlap kept), manual shape reattach post-translate. New group 'T2-D manual bubbles survive re-capture': bubble kept through signature-change re-capture, still translated; manual-only translate skips ONNX (0 detect calls); 🛰 boxes survive re-capture (1 call total); manual bubbles present → cache bypassed (stale cached result not replayed, pipeline re-runs, manual bubble translated).
- `reader_translation_draw_mode_test.dart`: 7/7 pass — ellipse drag → inscribed polygon bubble, freeform `timedDragFrom` → traced polygon, tool buttons + localized tooltips, existing rect/detect flows.
- Full suite: 16 pre-existing failures at clean HEAD (import_zip, download_content, download_bloc, ehviewer, reader_screen_policy, offline_content_body, end_of_chapter_overlay) — verified unrelated to this change via `git stash`.
- `fvm flutter analyze` clean.
- `offline_search_cubit_test.dart`: new 'Group Pagination' group — 25 distinct series paginate 20+5 with group counts, 20-chapter series yields 1 group, search groups-then-slices 30 hits, bucket listing/filter persistence, sort resets to page 1; existing stubs updated to fetch-all contract.
- `reader_glossary_test.dart` (new): glossary selector match/limit/no-match/empty, block rendering, prompt-embedding for OpenAI/Gemini/Cohere (payload capture), cubit propagation (low tier reaches builder, glossary reaches provider, exactly 1 AI call).
- `model_json_parser_test.dart` (new): fences, echoed `...`, trailing commas, brace chatter, legit-ellipsis preservation, garbage → actionable throw, placeholder detection incl. `<3`/inequality negatives, end-to-end echo/partial/all-SKIP via OpenAI provider.
- `mosaic_builder_test.dart` + `ai_preferences_mosaic_test.dart` (new): low < 1 MB / high < 2 MB / default-high, quality default `high` + persistence round-trip.

## [0.9.25+35] - 2026-08-16

### ✨ Added

- **AI translation prefetch detection (T2, openspec: `reader-ai-translate-improvements`)**: When a page settles (600ms no scroll/page change), bubble detection now runs ahead of time in the background and caches the result keyed by a page signature (`w:h:len:head24:tail24` of the captured bytes). Tapping translate reuses the prefetched boxes and skips the ~2.6s ONNX wait (`reuse prefetch — N boxes (no re-detect)`). Stale signature → prefetch dropped, re-detect. A race guard in `translatePage` waits (bounded 5s) for an in-flight prefetch instead of competing for the same non-thread-safe ONNX session. Empty prefetch results are never cached — translate re-detects rather than falling back to full-image upload. Loading overlay now appears on the very first frame of a translate tap (`emit Detecting` before provider resolution).
- **Fonts per translation style (T6)**: Bundled Bangers (action/SFX) + ComicNeue (formal) OFL-licensed fonts; `_styleFontMap` maps `natural/genz/romantis/kasar` → Komika, `action` → Bangers, `formal` → ComicNeue, `literal` → KosugiMaru, fallback default. (Anime Ace 2BB and CC Wild Words rejected: non-app licenses.)

### 🐛 Fixed

- **NNAPI session failure left bubble detection dead on MediaTek (openspec: `reader-ai-translate-improvements`)**: `env.createSession` with mixed NNAPI+CPU options threw `ORT_NOT_IMPLEMENTED` (MediaTek neuron shim has no kernel for the YOLO26s-seg `Flatten(13)` node) from the BubbleDetector constructor, so every detect call created a new detector that immediately failed → `[]` detections → translate silently fell back to full-image upload. `BubbleDetector.kt` now wraps session creation: on NNAPI build failure it rebuilds with a pure-CPU session (`nnapi=false, cpu-only`), keeps a CPU backup session for runtime failures, and switches permanently to CPU after one runtime failure. Detection now works on devices where NNAPI cannot execute the model.
- **Busy overlay stuck on screen after translate error**: `ReaderTranslationOverlay` `buildWhen` did not include `ReaderTranslationError`/`ReaderTranslationRateLimited`, so the busy overlay never closed when the AI request failed (e.g. provider 429). The `buildWhen` filter was removed entirely — the builder already returns `SizedBox.shrink` for non-visible states, and the filter had silently dropped Detecting too (loading never appeared on first tap).
- **ParentDataWidget crash from nested `Positioned`**: `AiBusyOverlay` used `Positioned.fill` at its root; when placed inside the already-`Positioned` translate overlay it wrote competing `StackParentData` into the same RenderObject ("Competing ParentDataWidgets"). Root switched to `SizedBox.expand` (fills any parent without writing parent data) — draw-mode and translate-path call sites both safe.

- **Areakomik source config** (`informations/configs/areakomik-config.json`, schemaVersion 2.0): New config-driven HTML source. Home list scoped to the UPDATE TERBARU section only (`#lin-update-terbaru + .status-filter + .komik-grid .komik-card`, 22 cards/page) with `/page/{page}/` pagination; search (`/?s={query}`) and genre pages (`/genre/{tag}/`); detail via `/series/{id}/` with cover from `meta[property='og:image']` (absolute); chapter list from `.chapter-grid .chapter-row` with ad rows filtered out via `:not(.lin-bonus-chapter-link)` (site's "Bonus Chapter" links are `reffpa.com` ads); reader images from `<img src>` (CDN `pic.gudangkomik.top` / `warungkomikcdn.icu`, no Referer needed). Validator `compatible`; verified live end-to-end via `GenericScraperAdapter` (home 22/22, search 17, genre 22, reader 48 images, JPEG 200). Not yet registered in the app — source registration still pending.
- **DoujinDesu.xxx detail tags + genre search** (openspec: `add-doujin-desu-xxx-source`, archived): `DoujinDesuXxxAdapter` now maps `manga_genres` → typed `Tag`s (id + slug, type `genre`) and parses `term_list` (`Name:type:slug|...`) into artists/characters/groups/parodies (N/A filtered), so detail pages show genre chips. Tag tap / genre search resolves numeric ids via a cached `/api/genres` list (148 items) and filters with `?genre=<slug>` (the API accepts slug, not id).
- **DoujinDesu.xxx pagination with totals**: Adapter now pages with `?limit=30&offset={page-1}*30` (the API ignores `page`/`per_page`/`skip`), reads the `x-total-count` header (10,261 titles → 343 pages; e.g. "neko" 237 → 8 pages, genre shota 1,239 → 42) and reports `totalItems`/`totalPages`/precise `hasNextPage`, falling back to the page-size heuristic if the header is missing. Config `doujindesuxxx-config.json` v1.1.0: endpoints synced with `offset={offset}` + new `genres` endpoint; `api` block documented as metadata (custom adapter reads the API directly).
- **Manga font rendering for AI translation overlay** (openspec: `reader-ai-render-polish`): Bundled `Komika Axis.ttf` (Latin) + `KosugiMaru.ttf` (CJK) as Flutter assets, picked per-bubble by script. Font-fit algorithm replaces rigid `rect.height * 0.18` — iterates font size large→small with `TextPainter` word-wrap, picks largest size that fits within the bubble (scale-down floor for tiny bubbles, bounded ~40 layout iterations). Tiny bubbles (below 44px touch target) are inflated outward from center so text fits and stays tappable. **Flat-bubble detection** (cypy heuristic: ratio ≥ 2.4, w ≥ 45% imgW, h ≤ 22% imgH) → `BubbleTranslation.needsWhitePatch`; only flat bubbles render the white patch (normal bubbles stay transparent — original balloon art visible). **White outline stroke** (3-layer `Shadow`, blur `size*0.18*i`) on text for contrast over bright artwork. Files: `pubspec.yaml`, `assets/fonts/`, `ai_translation.dart`, `reader_translation_cubit.dart`, `reader_translation_widgets.dart`, `reader_translation_cubit_test.dart` (+1), `reader_translation_overlay_test.dart`.

### 🐛 Fixed

- **DoujinDesu.xxx tag-tap search sent `?search=raw%3Asearch%3Dneko`**: Tap on a detail tag produced a `raw:search=neko` query that the custom adapter URL-encoded verbatim. `search()` now parses `raw:` params (`search`/`q`/`s` → search query; `genre`/`tag`/`tag_id`/`genre_id` → genre filter), supports `genre:`/`tag:` prefixes, and falls back to `includeTags` for genre navigation.
- **AI translate in continue-scroll now WYSIWYG (viewport-based)**: Replaced scroll-offset math (which drifted) with an actual on-screen viewport capture. Continue-scroll translate/detect now snapshots the visible `RenderRepaintBoundary` (the reader content) and runs the pipeline on that exact bitmap — bubbles align with what the user sees, not the full page image. Lazy capture on the draw-mode 🛰 Detect button (no capture on draw-mode entry, so toggling draw no longer janks). Re-encode to JPG runs on a background isolate. Added capture loading/success/failure snackbars (l10n en/id/zh). Bubbles are now interactive in continue-scroll (tap to edit, long-press save glossary). Files: `reader_mode_widgets.dart`, `reader_translation_cubit.dart`, `reader_image_widgets.dart`, `reader_translation_draw_mode.dart`, `reader_translation_widgets.dart`, `reader_overlay_widgets.dart`, `lib/l10n/*.arb`.

## [0.9.24+34] - 2026-08-07

### ✨ Added

- **Reader AI Learning Mode (image translation)**: BYOK multi-provider page translation with ONNX bubble detection. Pipeline: on-device `detectBubbles` (ONNX 1280 letterbox) → NMS IoU 0.45 + false-positive filter → mosaic (crop 2× + red labels, JPEG85/2MB) → AI provider → `Positioned` overlay scaled to fitWidth render. **Providers**: OpenAICompatible (OpenCode Go/OpenAI/OpenRouter/Zen/Custom) + Gemini — separate Go vs free endpoints, text-only `deepseek-v4-flash-free` excluded from vision path. **Features**: 7 translation styles (incl. Kasar 18+ confirm), target language, SFX skip toggle, per-bubble partial loading, tap-to-edit bubble (`isUserEdited`), long-press save glossary with romaji reading, manual draw mode (Detect blue / manual red, tap-delete, page-lock), continue-scroll guard, 429 multi-key round robin, SQLite `translation_cache` (SHA256 16-hex key, 30-day purge at launch), one-time full-screen tutorial. **kuron_native**: ONNX Runtime Android 1.23.0, `BubbleDetector.kt`, `BubbleBox` Dart class, `detectBubbles()` method channel. Full l10n (en/id/zh). 19 tests pass, analyze clean.
- **Nicomanga reader via `parseChapterApi`**: Reader page migrated to Next.js SPA — chapter images no longer in static HTML. New `GenericScraperAdapter.fetchChapterImages` mode `parseChapterApi`: `POST /api/parse-chapter` with `{"chapterUrl": ...}` → `{images: [...]}` (endpoint from legacy reader fixture). DOM fallback retained. Config `nicomanga-config.json` v1.2.0. +2 adapter tests (76/76 pass).
- **Rust Hitomi nozomi B-tree search**: Full binary-tree search via `hitomiDecodeNode` FFI using compact 21-byte binary struct (no JSON overhead). `_bSearchWithRust` replaces Dart `_decodeNode` + `_bSearch` loop — single-pass binary parse + SHA256-based key lookup. `cargo test` 33/33.
- **Rust EHentai regex batch**: `ehentaiExtractUrls` + `ehentaiExtractTags` FFI — compiled regex + dedup pipeline. Tag extraction with rawType parsing matching Dart `$rawType:$tagText` format. `clean_html_text` strips all HTML tags (regex `<[^>]+>`).
- **Rust file header inspection**: `headerInspect` + `headerInspectBatch` FFI — WebP/AVIF magic byte detection + dimensions. `inspect_webp` only returns format for animated VP8X (animation flag bit 1 set), matching Dart `looksLikeAnimatedWebPHeader` behavior.
- **Hitomi parallel nozomi fetch**: `_loadIds` now uses `Future.wait` to fetch positive/negative term nozomi files in parallel (was sequential — 7 terms = 7× latency).
- **Dart-Rust parity test**: `test/rust_parity_test.dart` — 18 tests validating Dart fallback output against expected values. On device (Rust available), also asserts Rust output == Dart output per function.
- **Image download cancellation on reader dispose**: Cancel all in-flight image network requests when reader screen is disposed — CancellationToken for ExtendedImage.network, Dio CancelToken for prefetch downloads, native HttpURLConnection.disconnect() in AnimatedWebPView.kt. Prevents orphaned requests causing UI lag on home screen.
- **Native-first heavy image routing**: Heavy images (E-Hentai 10MB+ AVIF/WebP) prefer native AnimatedWebPView where supported (static/animated), with Flutter ExtendedImage as fallback. Configurable via static URL sets in `extended_image_reader_widget.dart`.
- **Android CPU thermal management**: Prefetch throttle (back=1, forward=3) for heavy sources in continuous scroll. GPU memory budget eviction (heavy count tracking, evict farthest 25% only when exceeded). Repeated prefetch to same URL skipped.
- **CancellationToken post-completion lifecycle**: After heavy image detection fires in post-completion, CancellationToken is cancelled and recreated (with mounted guard) — prevents stale token from blocking future retries.
- **App Lock (PIN + Biometric)**: Full app-level lock with PIN setup/verify/change/remove and optional biometric (fingerprint/face) via `local_auth`. Session-based — 10 min session after unlock persisted in flutter_secure_storage (survives Activity recreation). Timer checks every 30s, re-locks when expired. Gate renders after splash on home route (not blocking root), so all sources load before lock appears.
- **Content Source loading fix**: `ContentBloc` removed from `MultiBlocProviderConfig` — `ContentSourceRegistry` no longer created eagerly at startup with only nhentai. Now created from `MainScreen.getIt<ContentBloc>()` after splash completes + RemoteConfigService loads all sources.
- **Session time-limit lock**: `AppLockCubit` starts 10-min session on unlock. Periodic 30s check — if expired, auto-lock. Short lifecycle pauses from biometric dialog (< 30s onPaused/resumed) ignored.
- **MIUI biometric compatibility**: `MainActivity.kt` changed from `FlutterActivity` to `FlutterFragmentActivity`. Auth uses `sensitiveTransaction: false`, `useErrorDialogs: false`, `stickyAuth: false`. `canCheckBiometrics` removed — MIUI false negative bug.
- **PIN/Biometric l10n**: Added 30+ ARB keys (en/id/zh) for PIN entry, setup, change, error strings, and settings toggles.

### 🔧 Changed

- **Remove dead Dart PDF chain**: Deleted `pdf_service.dart`, `pdf_isolate_worker.dart`, `image_splitter.dart` — active PDF path is Kotlin native (`PdfConversionService` → `NativePdfService` → `KuronNative.convertImagesToPdf`). `DownloadContentUseCase.convertToPdfIfRequested()` had zero callers. Removed `PdfService` DI registration + use case param + `pdf` dependency (unused after deletion; `image` kept — used by `image_cache_service`).
- **Rust `hitomiDecodeNode` binary format**: FFI now returns 21-byte fixed struct `[tag:u8][data:u64 LE][data:u32 LE]` instead of JSON string. Eliminates JSON serialization/deserialization per B-tree step. `hitomiBsetSearch` same format.
- **Rust-first, no Dart fallback policy**: All integration points (`_decodeGalleryIdsFromData`, `_decodeNozomiIds`, `_extractReaderLinks`, `_extractTags`, `batchInspectHeaders`, `inspectFileHeader`, `inspectAvifHeaderForRouting`) now skip Dart fallback when `RustBridge.instance != null`. Dart fallback only runs when Rust unavailable (compute isolates, dev platforms).
- **`header_inspector.dart` Dart fallback restored**: `inspectFileHeader` + `inspectAvifHeaderForRouting` Dart fallback uncommented — needed for `compute()` isolates where `RustBridge.instance` is null.
- **`clean_html_text` in Rust `ehentai.rs`**: Now strips all HTML tags via regex `<[^>]+>` (was only `<br>`/`<br/>`), matching Dart `_cleanHtmlText`.
- **ExtendedImageReaderWidget**: Added `_cancelToken` field (init → dispose), passed to `ExtendedImage.network` as `cancelToken`. Dead retry code removed (`_imageLoadRetries`, `_maxImageLoadRetries`, `_autoRetryTimer`, `_shouldAutoRetryImage`/`_scheduleAutoRetry`, `isRetrying`). Post-completion heavy detect now cancels + recreates token only when still mounted.
- **ReaderScreen dispose**: `_prefetchCancelTokens` map (`Map<int, CancelToken>`) tracks prefetch download tokens. On dispose: cancel all pending, clear map, clear `_decodeQueue`, reset `_isDecodeTickScheduled`, call `ExtendedImageReaderWidget.clearNativeAnimatedCache()`.
- **LocalImagePreloader**: Refactored `downloadAndCacheImage()` from raw dart:io HttpClient → Dio with optional `CancelToken` param. Removed ~28 lines of HttpClient boilerplate.
- **AnimatedWebPView.kt**: Added `@Volatile var activeConnection: HttpURLConnection?` — set in `fetchBytes()`, cleared in finally. Disconnected in `dispose()`. Added disposed guard in `fetchBytes()` (early throw on connection if already disposed).
- **pubspec.yaml**: Added `http_client_helper: ^3.0.0` dependency for CancellationToken.
- **App architecture**: `AppLockGate` now `StatefulWidget` with `didChangeDependencies` (one-time init, gated by `_inited`). `MultiBlocProviderConfig` no longer provides `ContentBloc` eagerly.
- **MainActivity.kt**: Extends `FlutterFragmentActivity` instead of `FlutterActivity` for `local_auth` FragmentActivity requirement.
- **ContentBloc access pattern**: Two `context.read<ContentBloc>()` calls in `main_screen_scrollable.dart` changed to `getIt<ContentBloc>()` (DI singleton, no BlocProvider needed).
- **GenericScraperAdapter tagTransform: base64**: `_resolvePattern()` now supports `tagTransform: "base64"` in pattern config — base64-encodes tag value before URL substitution. Used by nicomanga genreSearch.
- **CS Reader "Go to First Page" button**: Added `onGoToFirstPage` callback to `EndOfChapterOverlay` — when reaching chapter end in continuous scroll mode, tapping "Go to First Page" jumps back to page 0. Files: `end_of_chapter_overlay.dart`, `reader_screen.dart`.
- **HDoujin Source Integration**: New HDoujin source (`hdoujin.org`) reusing Schale Network's clearance engine and CDN architecture. Fully config-driven via `informations/configs/hdoujin-config.json`. Turnstile bypass scoped per-source with isolated storage keys. Refactored `SchaleClearanceService` to accept dynamic `domainUrl` + `sourceId`. Refactored `SchaleSourceFactory` for conditional domain routing. Registered hdoujin factory in service locator.
- **Lifecycle-aware Cubits**: `ReaderCubit` now pauses reading timer and disables `WakelockPlus` on lock screen (via `didChangeAppLifecycleState` in `ReaderScreen`). `DownloadBloc` has `pauseBackgroundWork()` / `resumeBackgroundWork()` — cancels DB flush timer (5s) and FrameTimingCallback on background, restores on foreground. Prevents CPU/GPU overheating saat app di lock screen.
- **ReaderCubit screen-level scoping**: Moved `ReaderCubit` from app-level `MultiBlocProviderConfig` to `BlocProvider` wrapping in route builder. Cubit `close()` sekarang kepanggil otomatis saat navigasi keluar dari reader — timer mati, wakelock di-disable, posisi baca tersimpan.
- **Native HTTP cancel untuk WebP thumbnail**: `getThumbnailForWebP` sekarang support `cancelWebPThumbnail(requestId)` via MethodChannel. `AnimatedWebPViewState` generate unique `_requestId`, kirim cancel signal di `dispose()`. Native Kotlin `downloadBytesForThumbnail()` check cancellation flag tiap read chunk untuk stop HTTP request lebih awal.

### 🐛 Fixed

- **Rust `extract_tags` double-joined tagSpec**: Was outputting `"language:korean:korean"` instead of `"language:korean"`. Now extracts rawType from tagSpec before joining.
- **Rust `inspect_webp` false positive for static WebP**: Was returning `format: "webp"` for ALL WebP files, causing reader to treat static WebP as animated heavy → continuous scroll break. Now returns `None` when no VP8X animation flag.
- **`_extractReaderLinks` Dart fallback missing**: Dart regex fallback was commented out → `return const []` when Rust unavailable. Restored full Dart regex + dedup pipeline.
- **Dead code removed**: `bsearch_json` in `hitomi.rs` (FFI now calls `decode_node_binary` directly).
- **CancellationToken leak after dispose**: Post-completion code ran `_cancelToken?.cancel(); _cancelToken = CancellationToken()` before `if (!mounted) return;`. If dispose fired between these, new token leaked. Fix: moved mounted guard before token creation.
- **TOCTOU race in AnimatedWebPView.kt**: `fetchBytes()` sets `activeConnection = conn`, but `dispose()` could read it as null before assignment — missed abort, 90s HTTP drain. Fix: disposed guard after setting activeConnection.
- **Orphaned prefetch downloads on reader close**: Prefetch using raw HttpClient had no cancellation mechanism. Fix: refactored to Dio + CancelToken tracked in `_prefetchCancelTokens`, all cancelled on dispose.
- **App Lock (PIN + Biometric)**: Full app-level lock with PIN setup/verify/change/remove and optional biometric (fingerprint/face) via `local_auth`. Session-based — 10 min session after unlock persisted in flutter_secure_storage (survives Activity recreation). Timer checks every 30s, re-locks when expired. Gate renders after splash on home route (not blocking root), so all sources load before lock appears.
- **Content Source loading fix**: `ContentBloc` removed from `MultiBlocProviderConfig` — `ContentSourceRegistry` no longer created eagerly at startup with only nhentai. Now created from `MainScreen.getIt<ContentBloc>()` after splash completes + RemoteConfigService loads all sources.
- **Session time-limit lock**: `AppLockCubit` starts 10-min session on unlock. Periodic 30s check — if expired, auto-lock. Short lifecycle pauses from biometric dialog (< 30s onPaused/resumed) ignored.
- **MIUI biometric compatibility**: `MainActivity.kt` changed from `FlutterActivity` to `FlutterFragmentActivity`. Auth uses `sensitiveTransaction: false`, `useErrorDialogs: false`, `stickyAuth: false`. `canCheckBiometrics` removed — MIUI false negative bug.
- **PIN/Biometric l10n**: Added 30+ ARB keys (en/id/zh) for PIN entry, setup, change, error strings, and settings toggles.
- **Fingerprint unlock → missing sources**: Root cause: `ContentSourceRegistry` initialized at `runApp()` with only nhentai (from DI) because `SplashBloc.smartInitialize()` hadn't run yet. Pin unlock "worked" only because PIN typing took enough time for splash to finish, but biometric instant unlock raced. Fix: removed `ContentBloc` from `MultiBlocProviderConfig` so `ContentSourceRegistry` is only created when home screen renders — after splash completes.
- **AppLockGate blocking splash**: Moved `AppLockGate` from `MaterialApp.builder` to home/main route wrappers. Splash runs freely, gate only appears after navigation to home.
- **AppLockGate re-init on rebuild**: `StatefulWidget` + `_inited` flag in `didChangeDependencies` prevents re-calling `cubit.init()` on rebuild.
- **Settings PIN setup sheet not closing**: `showPinSetupSheet` now passes `onSetupComplete: () => Navigator.pop()` so sheet auto-closes on success.
- **Gate showing PIN setup even when disabled**: Gate now checks `!lockState.hasPin && lockState.isPinEnabled` — only shows setup when PIN is explicitly enabled.
- **Gate triggering when already unlocked**: `AppLockCubit.init()` checks `isSessionActive()` — skips lock if session still valid.
- **HDoujin CDN headers**: `getImageDownloadHeaders()` in `generic_http_source.dart` now correctly restores Origin/Referer from config for hdoujin CDN requests (was using API URL instead of domain). Together with `schale-network`.
- **HDoujin cache refresh**: `content_repository_impl.dart` now forces detail cache refresh for hdoujin source (same policy as schale-network).
- **FlutterImageDecoder spam di log**: `FlutterError.onError` dan `PlatformDispatcher.instance.onError` skip `Failed to decode image` / `Invalid image data` dari Flutter engine native (`FlutterImageDecoderImplDefault`). Ini harmless — AVIF/WebP variant yang gak didukung engine dilewati dan ExtendedImage otomatis fallback. Tidak ada CPU hang atau crash.
- **Reader chapter selector crash**: `Navigator.of(context).pop()` di `_showChapterSelector` menggunakan `context` dari BlocBuilder yang sudah di-pop (settings sheet). Fatal: `Null check operator used on a null value` tiap tap chapter. Fix: ganti ke `ctx` dari builder bottom sheet selector. File: `reader_settings_widgets.dart:748`.
- **Continuous scroll tidak reset ke atas saat ganti chapter**: `_syncControllersWithState` selalu `return` untuk mode continuous scroll → scroll offset gak pernah di-reset pas navigasi chapter. Fix: track `_lastSyncedContentId`, skip sync cuma kalau content sama. Defer `_scrollController.animateTo(0)` ke post-frame callback biar ListView sudah mount. Files: `reader_screen.dart`.
- **Prev/next chapter navigasi 404 via EndOfChapterOverlay**: `_resolveNextChapterId` prioritaskan `state.chapterData?.nextChapterId` yang berisi raw URL dari source (misal `chapter-c35.3i294523.html`) — gak match format ID di `_allChapters` → `loadChapter` kirim URL korup → 404. Fix: balik prioritas — cek adjacent di `_allChapters` dulu, `chapterData` jadi fallback. File: `reader_cubit.dart:750-792`.
- **ManhwaRead side-story chapter double prefix `/manhwa/`**: Chapter URL `/manhwa/cliterary-book-club/side-story-2-minsuk-3/`. Regex `chapter-` gagal match → raw href dipakai → template `/manhwa/{id}` bikin `//manhwa//manhwa/...`. Fix 3 lapis: (1) config regex `contentIdPattern` jadi `[^/]+(?:/[^/]+)?` — tangkap 2 segmen path; (2) config chapter id regex hapus prefix `chapter-`; (3) adapter tambah `_normalizeChapterIdForTemplate()` — strip template prefix dari chapterID sebelum substitusi. Files: `manhwaread-config.json`, `generic_scraper_adapter.dart`.

### 🧪 Tests
- `cargo test` 33/33 (hitomi 8, ehentai 8, header 9, decrypt 2, unpack 3, imageproc 3)
- `flutter test test/rust_parity_test.dart` 18/18
- `flutter analyze`: No issues found

## [0.9.23+33] - 2026-07-14

### ✨ Added

- **Note Mode**: Added `note` (monochrome UI with light background) and `note_dark` (monochrome UI with dark background) themes. In both modes, all images (native WebP and Flutter-rendered) are dynamically desaturated to grayscale using `ColorMatrix` and `ColorFiltered` for a distraction-free reading experience.
- **Native theme sync**: Kotlin activities (`PdfReaderActivity`, `WebViewActivity`, `CaptchaWebViewActivity`) now parse the `textColor` intent extra to dynamically tint their `navigationIcon` (back button) and `overflowIcon` (menu button) to match the Flutter app's active theme.
- **Offline PDF routing**: `OfflineSeriesDetailScreen` now checks the offline chapter directory for `.pdf` files. If a PDF exists, clicking "Read Now (PDF)" correctly routes to the native PDF reader (`AppRouter.goToReaderPdf`) instead of the standard image reader.
- **Dual-rate scroll processing**: Page indicator (via vsync-aligned `Ticker`) updates at 120 FPS, while heavy ops (prefetch/evict/history) remain throttled at 300ms. Zero extra cost when idle.
- **GPU memory budget eviction**: Tracks heavy image count via `_heavyImageCount` — evicts farthest 25% pages only when budget exceeded (30 images within 5s window). No evict on low-memory chapters.
- **Rapid tap detection**: Non-CS page transitions skip `animateToPage` (200ms) when user taps faster than animation duration — jump directly for instant response.
- **WebP VP8X chunk parsing for native image dimensions**: `_inferNativeAnimatedCapableExtensionFromFileSync` now parses WebP VP8X chunk (width/height) and prefers WebP dimensions over AVIF `ispe` header for native AnimatedWebPView sizing. Fallback to AVIF dimensions when VP8X unavailable. Reduces scroll placeholder fallback from 90%→50% viewport height. AVIF pre-check now fires `onImageLoaded` via `addPostFrameCallback` for faster height cache population.
- **Responsive image sizing with cached height resolution in ReaderScreen**: `_resolveContinuousItemHeight()` uses neighbor-page cached heights (page±1, ±2 then last) before falling back to screen percentage. `ExtendedImageReaderWidget` wrapped in `SizedBox` with resolved height to prevent scroll jump during rebuild. Loading indicator redesigned for continuous scroll: card width 280px, linear progress bar, compact headline/detail layout.
- **DynamicFormSearchUI Advanced Filters panel**: Added expandable "Advanced Filters" toggle with animated expand/collapse (AnimatedSize + AnimatedSwitcher), active-filter badge count, and smooth chevron rotation — matching the polished UX of `QueryStringSearchUI`. Primary fields (text search, sort) remain always visible; all other fields hide behind the toggle panel.
- **Config `options` upgrade to label-value objects**: `SearchFormFieldConfig.options` now supports both plain strings (`["update"]`) and labeled objects (`[{"name": "Update", "value": "update"}]`). Added `SearchFormOptionConfig` model class with `value`, `name`, and `label` fields. Raw JSON path in `_optionsForField` and `_optionsForStaticField` now reads `"name"` key first, falling back to `"label"`. Typed path updated in `search_form_contract_adapter.dart`.
- **CMS template analysis**: Analyzed 20 source configs, live-verified 11 sites via Playwright. Identified 3 reusable templates (Madara, ZManga, Blogger) — see `output/cms-template-analysis.md`.
- **Config generator MangaThemesia support**: Added `cms_detector.dart` hints for mangareader theme, `listupd`/`bsx` class patterns. Full `mangathemesia` branch in `config_generator.dart` with correct containers, pagination, detail/chapter/reader selectors, genre URLs.
- **Config generator smart probes**: `generate --url` now extracts `defaultLanguage` from `<html lang>`, `iconPath` from `<link rel="icon">`, `brandColor` from `<meta name="theme-color">`.
- **Source health monitor proposal**: New OpenSpec change `source-health-monitor` — per-source HTTP health check (HEAD/GET to baseUrl, 10s timeout, staggered concurrency), green/red/grey dot indicators in settings, aggregate "N/N reachable" summary, manual "Check All" button. Advisory only, no auto-disable.
- **SpyFakku remote tag autocomplete**: Added `tagSource` block to `spyfakku-config.json` with 4,423 tags extracted from hentalk.pw boot data. Tags loaded via `TagDataManager.loadAndCacheTagsFromUrl()` on first autocomplete query. No dedicated API endpoint needed.
- **Multi-select filter support for query-string search UI**: `QueryStringSearchUI` now encodes multi-select filter selections (tag/artist/parody) into the query string (e.g. `-tag:"Lolicon" parody:"Azur Lane"`) so the generic REST adapter sends them via the `q=` parameter.
- **TagDataManager new method**: `loadAndCacheTagsFromUrl(url, source)` loads tags from a remote URL and caches them per-source for subsequent `hasTags()` / `searchTags()` lookups.
- **Ehentai heavy image continuous scroll support**: E-Hentai 10MB+ WebP images no longer auto-kick to singlePage mode. Added `ehentai` to `shouldSkipHeavyImageAutoSwitchForSource`, `_isHeavyPrefetchSource`, `_isHeavyReaderSource`. `AnimatedWebPView` now receives `visiblePageNotifier` in continuous scroll for heavy sources so off-screen thumbnails auto-pause. Added `_evictDistantPages()` call on scroll for heavy sources (±4 window). Works online + offline.
- **MangaFire chapter pagination**: Added page-based pagination fallback in `_nextOffsetPageUrl()` for `meta.page`/`meta.lastPage` response. Config endpoint from `?page=1` to `?language={language}&sort=number&order=asc&limit=20`.
- **MangaDex chapter language filtering**: `fetchChapters()` standalone injects `translatedLanguage[]` when `language` param passed. Detail initial load filters by first `availableTranslatedLanguages` language. Language chips from `available_language` tags.
- **Volume/chapter separation in adapter**: `scanGroup` respected in `fetchChapters()` — skips volumes when `scanGroup='Chapter'` and vice versa.
- **Reader lazy pool expansion**: `ReaderCubit._fetchAndMergePage()` fetches extra pages when prev/next hits boundary. `_ensureChapterInPool()` expands pool when chapter missing. Prev/next stays in same `scanGroup`.
- **General language selection handler**: `onLanguageSelected` works for all sources (not just MangaFire) via `DetailCubit.loadChapterLane()`.
- **ARB `loadMoreChapters` key**: Added to `app_en.arb`, `app_id.arb`, `app_zh.arb` with `{label}` placeholder.
- **Smart query syntax placeholder**: Added `(tag:yuri -tag:futanari language:english)` hint to search input placeholders in nhentai, ehentai, and hitomi configs.
- **MangaFire multi-select filters**: Upgraded MangaFire's search form to use dynamic `dataSources` hitting `/api/filter-options`. The hardcoded select dropdowns for `type` and `status` have been replaced with full multi-select tag pickers (similar to MangaDex). Added pickers for `Genres`, `Themes`, `Demographics`, `Formats`, and `Content Ratings`, allowing complex multi-field filtering directly in the search UI.
- **Domain entity for ReaderSettings**: Created `lib/domain/entities/reader_settings_entity.dart` with pure `ReaderSettings`, `ReadingMode`, `TapDirection`. Data model `ReaderSettingsModel` now extends the entity with JSON serialization only — eliminating the Presentation→Data import for reader settings across 3 files.
- **AppInitializer domain abstraction**: New `lib/domain/services/app_initializer.dart` interface for `initialize()`, `checkCloudflareStatus()`, `bypassCloudflare()`. `RemoteDataSource implements AppInitializer` — SplashBloc no longer imports data layer directly.
- **UserDataRepository search filter methods**: Implemented `saveSearchFilter`, `getLastSearchFilter`, `clearSearchFilter`, `addSearchHistory`, `getSearchHistory`, `clearSearchHistory`, `deleteSearchHistory` in `UserDataRepositoryImpl` — enabling 6 presentation files to drop direct `LocalDataSource` imports.

### 🐛 Fixed

- **Schale Network Image Loading**: Fixed `Bad state: Failed to load` CDN error on reader pages.
  - The `generic_rest_adapter.dart` inadvertently appended a `?w=$quality` query parameter to the CDN image URL.
  - Schale Network's Edge CDN (`erocdn.net`) rejects requests with query parameters (`404 Not Found`).
  - Removed the `?w=` parameter, as Schale already embeds the resolution within the path (e.g. `/1280/`).
  - Added Turnstile Challenge bypass using `showLoginWebView` and injected JavaScript to extract the `cf_clearance` cookie from `localStorage`.
  - Added `_SchaleHttpSource` to intercept image requests and inject the `cf_clearance` cookie and User-Agent headers, preventing 403 Forbidden errors.
- **ViHentai packed JS image URL extraction**: Fixed `_imageUrlRegex` in `ViHentaiPackedJs` — JS-escaped forward slashes (`\/`) in decoded `KuroReader` output caused regex mismatch, falling back to `<img>` tag extraction which grabbed `/imgs/fav2.png` instead of real chapter images. Normalized `\/` → `/` before regex matching. Also aligned `_packedArgsRegex` group 1 to `(.+)` per Tachiyomi reference implementation. 18/18 tests pass.
- **Dynamic Form multiple parameters**: Fixed a bug where multiple dropdowns or fields sharing the same `queryParam` (e.g. `rawParam` in MangaFire for `type` and `sort`) would overwrite each other when restoring the form state. `_setRestoredFieldValue` now properly checks if the restored value actually belongs to the field's available options before assigning it, allowing multiple `rawParam` fields to be selected and handled simultaneously.
- **GenericJSONParser prefix logic**: Fixed an issue where `extractRaw` would not apply a `prefix` or `suffix` if the extracted value was not initially a `String` (e.g., an integer ID). This caused MangaFire volume IDs to miss their `https://mangafire.to/api/volumes/` prefix, leading the app to mistakenly use the chapters endpoint when fetching volume reader images. Non-string values are now converted to strings when a prefix or suffix is provided.
- **MangaFire detail volume tabs**: Fixed an issue where the "Volumes" and "Chapters" tab selector would not appear on MangaFire detail pages. The generic JSON parser skips `fallback` fields if no JSON `selector` is provided, causing `scanGroup` to be null. Switched to using `value` to explicitly hardcode the `scanGroup` for both chapters and volumes, restoring the tab UI. Also restored chapter `date` extraction and removed hardcoded `en` language queries to fetch all available translations.
- **OfflineSearchCubit test**: Fixed `loadMoreContent` test that passed hardcoded `offset: 1` while the cubit tracks its own internal `_dbOffset`. Mock now uses `any(named: 'offset')` with `orderBy`/`descending` params to match the cubit's real call signature.
- **Dynamic form sort retention**: Fixed an issue where selecting a sort option from a Dynamic Form (like in MangaFire or Generic Scraper sources) would be lost and fall back to the default sort when returning to the main screen. The `MainScreenScrollable` no longer strips the `sort` parameter from the raw query string, ensuring the adapter correctly receives and processes the user's explicit sort selection.
- **Duplicate tags and string lists cleanup**: Fixed an issue where generic scraper string fields (like `Artists`) were cached with trailing counts and newlines (e.g. `Shiro Marimo\n1`), causing duplicate UI chips and deduplication failure. Added a regex rule to `hentairead-config.json` to cleanly extract the artist name, and patched `ContentModel._decodeStringList` to strip trailing counts directly from the local SQLite cache so old data is fixed without requiring a pull-to-refresh.
- **Tag resolution slug fallback**: Fixed a bug where clicking older corrupted tags failed to navigate because the missing `tagId` triggered a `navigation cancelled to avoid invalid query` error. `DetailTagQueryResolver` now falls back to generating a slug from the raw `tagName` when `resolvedTagId` is empty.
- **Offline metadata resync for hashed folders**: Full offline resync now rebuilds completed download rows from native `metadata.json` using the real `content_id`/source fields instead of the elegant/hash folder name. This fixes missing offline status detection on cards and detail actions for chapter-based sources like Crotpedia and KomikTap after DB recreation or local filesystem resync.
- **HentaiNexus detail cover + reader stability**: Detail cover scraping now uses `meta[property="og:image"]` instead of guessing from page URLs, so header covers no longer depend on unstable reader-image extensions like `.jpg.thumb.jpg` or `.png.thumb.webp`. The HentaiNexus decrypt/runtime path also now deduplicates page URLs by page key with stable format priority, avoids stale detail cache reuse, and stops static WebP/AVIF pages from being misclassified as heavy animated content that forced the reader out of continuous scroll.
- **ToonCubus reader and label routing**: ToonCubus now treats the detail `Baca Online` block as a real chapter lane, follows the explicit `tooncubus-read.my.id` reader URL before scraping images, uses Blogger cursor pagination from the live pager (`updated-max=...&start=...`) instead of repeating page 1, and routes detail-tag clicks to `/search/label/...` label pages instead of falling back to keyword search.
- **Numeric gallery ID search redirect**: When user types a numeric gallery ID (e.g. `544433`) in DynamicFormSearchUI, the form now redirects directly to `/content/{id}` instead of saving a search filter. Search APIs (nhentai, hentaifox, hentainexus, e-hentai, etc.) do full-text search and return empty results for numeric IDs. Detail endpoint fetches the gallery correctly.
- **ARB key naming violation**: Renamed `ReaderSettingsEntityResetSuccess`/`ReaderSettingsEntityReset`/`ReaderSettingsEntity` to valid camelCase keys (`readerSettingsLabel`, `readerSettingsResetSuccessMsg`, `readerSettingsResetMsg`), fixing build failure.
- **Crotpedia test config**: Added `home` pattern to `_crotpediaRawConfig` test fixture so empty query fallback resolves correctly instead of returning empty results.
- **print() violation in downloads_screen.dart**: Removed debug `print()` inside assert block — semgrep now reports 0 print violations.
- **`SearchFormFieldOption.fromMap` reads `name` key**: Canonical config bridge now reads `"name"` as label fallback (`displayLabel` → `label` → `name`). Fixes chip label display for configs using `{"name": "...", "value": "..."}` format.
- **Field restore cross-contamination fix**: When restoring saved filter raw query, values are only restored to fields whose `valuePrefix` matches (e.g. `includeTag` values with prefix `tag:` don't leak to `excludeTag`/`artist`/`parody`). Added `joinMode: space` to spyfakku q-fields for correct `_restoreJoinedParamGroup` routing.
- **Chip value double-prefix fix**: `_setRestoredFieldValue` now strips prefix/suffix from restored values using `_extractFieldCoreFromToken`, preventing `_formatFieldValue` from re-adding the prefix and producing `tag:"tag:Blowjob"`.
- **`_selectLanguage` setState fix**: Chips update immediately instead of waiting for async fetch.
- **DynamicFormSearchUI picker restore fix**: Fixed a bug where picker fields using `valuePrefix` (e.g. MangaFire's `genres_in[]=`) would fail to restore their selected state from a saved filter, causing them to either lose selection or duplicate dummy chips across fields that share the same `queryParam` (e.g. `rawParam`).
- **gitleaks config**: Created `.gitleaks.toml` to exclude documentation fixtures and build artifacts — 45 false-positive leaks reduced to 0.

### 🔧 Changed & Refactored

- **State management cleanup**: Replaced `ReaderInitial`/`ReaderLoading`/`ReaderLoaded`/`ReaderError` subclass pattern with `ReaderStatus` enum + single `ReaderState`. Removed `_undefined` sentinel `copyWith` — replaced with 7 focused copy methods (`copyWithPage`, `copyWithUI`, `copyWithContent`, `copyWithMessage`, `copyWithMode`, `copyWithTimer`, `copyWithOffline`). Reduced `Equatable.props` — `content?.id` instead of full object, removed `readingTimer`/`message`/`isOfflineMode` from equality comparison.
- **BlocListener prefetch scoped to CS only**: Removed redundant `_prefetchImages` call for singlePage/verticalPage modes — ExtendedImage handles its own caching via PageView item builder.
- **Rapid non-CS page sync**: Detects consecutive taps faster than 200ms and skips `animateToPage` — uses `jumpToPage` directly.
- **Removed stale eviction fields**: `_lastEvictedPage`/`_evictionWindowPages` replaced by budget-based eviction.
- **Removed `_resolveContinuousFallbackItemHeight`**: Replaced by `_resolveAverageItemHeight` + cached-heights scan.
- **Cursor pagination DRY**: Extracted duplicate 12-line cursor priming block (copy-pasted between `search()` and `_searchRaw()`) into single `_tryPrimeCursorPagination()` helper. Removed redundant `_hasCursorPagination()` method. Added `_maxPrimePages = 10` guard to prevent runaway serial HTTP requests. Net −63 lines, +1 import.
- **Clean Architecture violations (Path A)**: Moved `ReaderSettings`, `ReadingMode`, `TapDirection` from `data/models/` to `domain/entities/`. Updated `ReaderSettingsRepository` interface + impl. Updated 3 presentation files + 2 test files to import from domain.
- **Clean Architecture violations (Path B)**: Updated `search_bloc.dart`, `content_bloc.dart`, `main_screen_scrollable.dart`, `query_string_search_ui.dart`, `form_based_search_ui.dart`, `dynamic_form_search_ui.dart` to use `UserDataRepository`/`TagRepository` instead of direct `LocalDataSource`/`TagDataSource` imports. Updated `service_locator.dart` DI registration.
- **CLAUDE.md + AGENTS.md**: Added FVM prefix to all commands, new `/security-review` and `/review` commands, added gitleaks + typos-cli to search tools section, added hyphen to section headers, removed ast-grep references.

### 🏗️ ManhwaRead Source Config

- **Full config rewrite**: `informations/configs/manhwaread-config.json` rewritten from v2 compact to full format with `urlPatterns`, `selectors`, pagination, and `chapterDataScript` reader mode.
- **XHR Proxy reader**: New `chapterDataScript` reader mode extracts base64-encoded `chapterData` script variable → builds direct CDN URLs (`manread.xyz/{mangaId}/{chapterId}/mr_{page}.jpg`). Base64 only for metadata transport (1-2KB), images streamed direct from CDN.
- **`"self"` pseudo-selector**: `_extractElementFields` handler reads attributes/text from the container element directly (bypasses `querySelectorAll` limitation in `html` Dart package). Supports `regex` + `transform` chains.
- **Prefix-based tag routing**: `tag:`, `author:`, `artist:`, `publisher:`, `genre:` prefixes map to `tagSearch`/`authorSearch`/`artistSearch`/`publisherSearch`/`genreSearch` URL patterns — supports `{type}/{value}` routing for detail-page tag clicks.
- **Typed tag injection for author/artist/publisher**: `GenericContentMapper.toDetail()` now injects author, artist, and publisher as typed `Tag` objects (`type:"author"`, `type:"artist"`, `type:"publisher"`) so they appear as tappable chips on detail screens.
- **Tag count strip**: Author/artist/publisher selectors use regex `^(.*?)\s+\d+$` to strip trailing count (`Hwalhwasan\n7` → `Hwalhwasan`). Tags use `^(.*?)\s+[\d.]+K?$` for same purpose.
- **Generic html reader padding fix**: `_extractChapterDataScriptImageUrls` now pads base64 input to multiple of 4 (`padRight`) before decoding, fixing `Invalid length` errors on unpadded base64 from `chapterData` script variable.

### 🗑️ Removed

- **kuron_ads package**: Empty shell (no `lib/`, 0 Dart files, unreferenced) — deleted.
- **ast-grep config artifacts**: Removed `sgconfig.yml` + `ast-grep-rules/` directory from project root.
- **flutter_01.png**: Stray screenshot deleted.
- **Native DNS roll-out**: Promoted native Android DoH as canonical managed DNS path. Removed Dart-side DnsResolver from DI. Added device Private DNS diagnostics (ConnectivityManager API 29+), system DNS settings launch with layered fallback intent routing, and settings UI showing device-level Private DNS status with guidance text.
- **Chapter load more (MangaDex + MangaFire)**: Bottom sheet `_loadMoreChapters()` uses `page` (MangaFire) / `offset` (MangaDex) via `ContentRepository`. All hardcoded Dio/Dart calls removed.
- **Language emoji flags**: Replaced SVG files with Unicode emoji flags across all card widgets. 60 language entries in `assets/configs/languages.json`. Removed `flagFile`/`flagAssetPath`/`flutter_svg` dependency.
- **Deprecated legacy search UI removed**: Deleted `query_string_search_ui.dart` and `form_based_search_ui.dart`. `SearchScreen` hardwired to `DynamicFormSearchUI` unconditionally. Net -65KB, -3 imports, -3 routing methods (195->128 lines).

### 🧪 Tests

- **DoujinDesu tests disabled**: Wrapped in `_doujindesuTests()` function while source is down — re-enable by calling it.
- **Crotpedia test fixed**: Added mock for `home` URL fallback route.
- **ReaderSettings test alignment**: Updated 2 test files (`reader_cubit_hentairead_test`, `extended_image_reader_widget_test`) to use domain entity import.
- **Full test suite**: 73/73 passer (generic_scraper), 13/13 (ToonCubus + HentaiRead), 3/3 (ToonCubus config).

---

## [0.9.22+32] - 2026-06-27

### ✨ Highlights

- **Offline ZIP Import Polish**: Import notifications no longer appear prematurely if the file picker is cancelled, and bulk ZIP extractions now display progression indices (e.g., `[1/3]`) in the notification.
- **Core Upgrades & Cleanup**: Upgraded `flutter_local_notifications` to v22.0.1 (fixing breaking API changes) and purged deprecated UI packages (`shimmer`, `flutter_spinkit`, `pull_to_refresh`) in favor of native/local equivalents like `KuronShimmer`.
- **Tag & Offline Card Revamp**: `content_by_tag` now reuses the stronger home-card visual treatment, and offline library cards were refreshed to match with clearer offline/read badges plus safer bottom spacing near the last row.

---

## [0.9.21+31] - 2026-06-25

### ✨ Highlights

- **Home Card Status Borders**: Main cards now show read, offline, or combined read+offline borders with matching cover badges.
- **Theme-Aware UI Cleanup**: Fixed lingering hardcoded text/color mismatches across home, about, search, and bottom-sheet surfaces.
- **Cover Badge Polish**: Content covers now surface read/offline state directly on the image for quicker scanability.

#### 🏗️ Kuron Config Generator (Developer Tooling)
- **Interactive CLI Wizard**: New `packages/kuron_config_generator` with guided question flow for source identity, mode (REST/scraper), features, endpoints, and headers. Generates valid Source Config v2 JSON without manual writing.
- **URL-Assisted HTML Discovery**: `generate --url` probes any manga site, detects CMS (Madara/WordPress/custom), infers selectors for list/detail/chapters/reader, and produces a draft scraper config. Recognizes Cloudflare blocks and adds bypass annotations.
- **URL-Assisted API Discovery**: `generate --url` against JSON endpoints auto-detects response structure (arrays, `data[]`, `results[]`, or single detail objects), pagination hints, and outputs a REST API config with inferred endpoints.
- **Source Config Validator Integration**: Generated configs can be immediately validated with `kuron_config_validate` for compatibility status.
- **27 Unit Tests**: Coverage for wizard flow, CMS detection (Madara/WordPress/custom), API inference (array/map/detail patterns), probe response classification, and end-to-end smoke tests.

#### 🔥 MangaFire Integration & Deferred Chapter Lanes
- **MangaFire Source Support**: Added MangaFire with config-driven browse/detail parsing, VRF-backed search and reader capture, AJAX chapter lane support, and native image descrambling for scrambled pages.
- **Lazy Chapter Lane Loading**: MangaFire detail now prioritizes the default chapter lane on first load, keeps other language and volume lanes visible as selectable chips, and fetches those lanes only when the user activates them.
- **Related/Tag Detail Polish**: MangaFire detail now hides empty related sections, falls back to a simple list when related covers are missing, and keeps internal lane metadata out of the public tag UI.

#### 🧭 Chapter Language Tabs & MangaDex Paging
- **Tabbed Chapter Lanes**: Detail pages now group multi-language chapters into explicit lanes/chips, keep the selected lane stable across reader launches, and preserve reader same-language navigation with shared language normalization.
- **Scoped Chapter Browsing**: `View all chapters` now opens on the active lane, MangaDex detail fetches stop at the first chapter page by default, and the bottom sheet loads more chapters per selected language instead of pulling the entire feed at once.
- **Chapter Preview Polish**: The detail chapter preview section now uses a lighter container, compact language chips, slimmer rows, and clearer read/download actions for better scanability.

#### 🔎 Search Runtime Autowiring
- **Canonical Search Bridge**: Search runtime wiring now routes canonical form-backed configs into the dynamic search UI while keeping legacy configs available for compatibility.
- **Safer Search UX**: Picker-backed filters, query construction, and config-driven search behavior are preserved through the runtime bridge so search screens can render the right controls without duplicate field logic.

#### 🎨 Offline Library UI Polish
- **Ganteng UI Updates**: Improved Offline Content sorting/filter UI with a Glowing Gradient floating action button, modern AnimatedContainer filter chips, and pill-shaped TabBar ripples.
- **Smart FAB Auto-Hide**: Fixed FAB auto-hide behavior during scroll by implementing a `NotificationListener<ScrollUpdateNotification>`.
- **Filter State Stability**: Fixed filter state anomaly by reading `offline_selected_source_filter` from `SharedPreferences` during loading states to prevent UI flickering back to the "All" tab.
- **Advanced File Path Utility**: Added file path display in the offline long-press bottom sheet with "Copy Path" and "Open in Explorer" utilities.
- **Chapter Card Redesign**: Redesigned chapter list cards in the detail screen to be more premium with outline borders, icons, and badges.
- **Grouped Offline Metadata**: Offline grouped items now aggregate per-chapter DB file sizes, show available chapter counts instead of misleading single-item size, and keep multi-path information available for inspection.
- **Info-Only Offline Group Sheet**: Offline library long-press sheet now focuses on information only; read, delete, and PDF conversion actions live in `OfflineSeriesDetailScreen`.
- **Offline Detail Actions Fix**: Fixed offline detail delete/PDF/read flow by using the shared offline search cubit, refreshing local detail items after deletion, and keeping progress state in sync after returning from reader.
- **Offline Duplicate Chapter Fix**: Offline series detail now collapses duplicate chapter rows that point to the same source/title/local path, so stale duplicate DB IDs no longer inflate the visible chapter count.
- **Offline Content Body Dedupe**: `OfflineContentBody` now renders the deduped chapter set directly, so the grid card, chapter badge, and long-press info sheet all agree on the same count.

#### 📖 Reader Interaction & Progress
- **Offline Progress Flush**: Reader now force-saves offline reading progress into `reader_positions` before dispose, so offline library and detail progress update without requiring an app restart.
- **Animated Image Tap Zones**: Reader tap zones now work over native/animated image surfaces, restoring left/right next/previous navigation and center UI toggling behavior.
- **Draggable Chrome Toggle**: Added a draggable mini floating control to show/hide reader header/footer, clamped to the visible screen area.

#### 📥 Download Storage & Permissions
- **Custom Directory Permission Flow**: `DownloadsScreen` now treats `StorageSettings.custom_storage_root` as the download source of truth and no longer requires full storage permission when a custom directory is configured.
- **Storage Setup Prompt**: When no custom download directory is set, downloads now prompt the user to open Settings instead of requesting broad storage access.
- **PDF Conversion Permission Scope**: PDF conversion from downloads now skips storage permission when the custom download root is available and only requests notification permission when needed.

#### 🎨 Theme Polish
- **Animated Dice Theme Color**: `AnimatedDiceWidget` icon/painter color now follows `IconTheme` and the active app theme.
- **Search & Filter Chip Contrast**: Improved selected chip readability in light/dark mode for dynamic search select/checkbox fields, MangaDex include/exclude tag pickers, `FilterDataScreen`, and selected filter summaries. Include states now use a readable green palette and exclude states use a readable red palette.
- **Canonical Checkbox URL Loading**: Dynamic search checkbox fields now preserve `loadFromTags`/`tagType`/`tagSourceUrl` through the canonical contract bridge and can load tag options from remote URLs with loading and error feedback.
- **MangaDex search language filters**: Added `originalLanguage[]` and `availableTranslatedLanguage[]` multi-picker fields to `mangadex-config.json` searchForm with 62 language options via static `dataSources.languages` block. Proposed but not implemented: `mangadex-search-language-to-detail` — pass selected languages from search to detail page for auto-filtering chapters.
- **Crotpedia Search Dedupe**: Removed the redundant overlapping search input for Crotpedia by deduplicating form-backed query fields, so the UI now shows a single source-of-truth search field while preserving the `title` query param.
- **Crotpedia Genre Direct Source**: Genre chips now load from the explicit remote tag URL declared in `crotpedia-config.json`, removing the dependency on the legacy tag sync manifest for this screen.
- **Search Config Reload Action**: Added a Search screen reload button that force-refreshes the source config from `configUrl` and remounts the search widget so updated fields can appear without reinstalling the app.

#### 🚦 Source Rate-Limit Hardening
- **Config-Driven Runtime Limits**: Generic source pipeline now reads `network.rateLimit` config and applies request throttling (`requestsPerSecond`/`requestsPerMinute`, `maxConcurrentRequests`, and delay controls) across REST and scraper adapters.
- **Adaptive Cooldown on 429**: `RequestRateManager` now honors source config for cooldown duration and active state, and `RemoteDataSource` uses the manager cooldown path instead of fixed hardcoded timing.
- **Cooldown Behavior Safety**: Nhentai client wait flow now enforces cooldown checks in a loop and surfaces explicit rate-limit failures when API calls are attempted during active cooldown.
- **Test Compatibility Fix**: Updated secure storage test overrides to use `AppleOptions` so auth client tests remain compatible with current `flutter_secure_storage` API changes.

#### 🧩 Source Config Baseline
- Added baseline `network.rateLimit` blocks (`enabled`, `requestsPerSecond`, `maxConcurrentRequests`) for multiple source configs under `informations/configs` for safer default request pacing.

### 🐛 Bug Fixes & UX
- **MangaFire Tag Routing**: Fixed an issue where tapping Author or Magazine tags on MangaFire detail pages triggered a generic keyword search instead of navigating to the specific author/magazine routes.

---

## [0.9.20+30] - 2026-06-01

### ✨ Highlights

#### 🧩 Config Runtime & Source Adapter Hardening
- **Endpoint Schema Compatibility**: Updated `ApiConfig`, `GenericHttpSource`, and `GenericRestAdapter` to support the newer `api.endpoints` map structure and extension mapping flow.
- **Template URL Generation**: Added config-driven URL generation for search and browse paths from remote templates.
- **REST Adapter Reliability**: Improved pagination logic, tag query resolution, language defaults, sorting/detail URL generation, and rating sort mapping.
- **Komikcast REST Stability**: Completed Komikcast REST schema hardening and related integration coverage.
- **Scraper Pagination Improvements**: Enhanced `GenericScraperAdapter` pagination/template handling and improved parser error handling for invalid `--dir` usage.

#### 📖 Reader & UX
- **Tap Direction Control**: Added reader tap direction setting with localized labels and descriptions.
- **Zoom Toggle**: Added reader zoom toggle setting for better per-device readability preferences.
- **Page Estimation Refactor**: Refined reader page estimation logic for improved accuracy and smoother behavior.
- **Heavy Source Performance**: Optimized `ListView` caching for heavy image sources to reduce offscreen rebuild cost.
- **Settings Layout Polish**: Improved settings layout constraints for better usability on varied screen sizes.

#### 🎨 Visual & Localization
- **Tag Color Palette Revamp**: Implemented theme-aware tag color resolution and tuned dark-mode colors to more muted tones for readability.
- **Localization Updates**: Clarified blacklist descriptions across locales.

#### 🔌 Source Capability Expansion
- **DoujinDesuV2 Runtime Support**: Added category routing and AJAX reader support for DoujinDesuV2 integration.

#### 🛠 Build, Dependencies & Docs
- **Android Build Compatibility**: Updated Gradle/Kotlin-related configuration and fixed Android build compilation issues.
- **Dependency Refresh**: Updated `flutter_secure_storage` and related dependency lockfiles.
- **Documentation & Assets**: Added Indonesian/Chinese configuration guides, refreshed screenshots, cleaned README links, and corrected architecture-specific binary size notes.

## [0.9.19+29] - 2026-05-24

### ✨ Highlights

#### 🖼 AVIF Reader Conversion Pipeline
- **Auto AVIF -> WebP Conversion**: Added native conversion path for problematic tall animated AVIF (`avis`, height > 4096) so reader can route converted output into native animated rendering.
- **Offline In-Place Conversion**: Local/offline chapter pages now support in-place AVIF replacement to `.webp`, including metadata rewrite and offline cache invalidation.
- **Reader Loading UX**: Improved loading copy during native conversion with dedicated localized message for conversion state (`id/en/zh`).

#### 🛡 Release Stability Hardening
- **FFmpeg Runtime Guard**: Hardened native converter path to catch JNI/runtime failures from FFmpegKit in release and degrade gracefully (soft-fail) instead of crashing process.
- **R8/ProGuard Consumer Rules**: Added plugin-level consumer ProGuard rules in `kuron_native` for FFmpeg JNI classes and native method preservation.
- **Build Script Cleanup**: Removed hardcoded universal APK size text in `build_optimized.sh`; output now reports dynamic reference size or `N/A` when universal APK is not generated.

#### 📝 Documentation
- **Kuron Native README**: Added Android release integration guide for R8/ProGuard + FFmpegKit setup and verification steps.

## [0.9.18+28] - 2026-05-16

### ✨ Highlights

#### 🧭 Hentai Cosplay Scraper Reliability
- **Raw Search URL Fix**: Fixed duplicate raw query appending (`?query=...`) when query/tag already resolved in path templates.
- **Primary Section Filtering**: Added config-driven section filtering so only `Search Results`/`New Images` blocks are parsed.
- **Pagination Accuracy**: Added config-based `pagination.last` support and improved total-page fallback extraction.
- **ID Fallback Config**: Added `idFallbackSelectors` in source config to avoid hardcoded list-item fallback selectors.
- **List Parsing Robustness**: Improved list mapping resilience and diagnostics for empty-list cases.

---

## [0.9.18+27] - 2026-05-10

### ✨ Highlights

#### 📦 DoujinDesuV2 Integration
- **New Source**: Added DoujinDesuV2 API integration with full search, detail, and reader support.
- **Tag Search Fix**: Fixed tag search endpoint and image extraction bug.

#### 🚀 Source Expansion
- **6 New Config-Driven Sources**: Integrated Tachiyomi-style external sources via configuration.
- **Komiku Fix**: Fixed issues with Komiku source implementation.

#### 🛠 Dependency Updates
- **Deprecated Packages Removal**: Cleaned up deprecated packages for better performance.

#### 🎨 UI/UX Improvements
- **Icon Updates**: Replaced Frame.png with logo_app.png across the application for consistent branding.
- **Tag Visibility Fix**: Adjusted tag border opacity from `0.5` to `0.8` on detail screen for better contrast.
- **Tag Color Handling**: Fixed "other" tag case to use `colorScheme.outline` for dark mode.
- **Theme Refactor**: Refactored color constants to use AppColors in ThemeCubit and ThemeState.

#### 🌐 Localization
- **Empty State Suggestions**: Enhanced empty state suggestions with localized keys for better i18n support.

#### 📥 Download & Offline
- **Range Download**: Implemented range download with original page numbering and metadata preservation.
- **Offline Content Enhancement**: Improved metadata handling by removing repaired pages from failed_pages.
- **Failed Page Placeholders**: Enhanced offline reader with failed-page placeholders and cache invalidation.

#### 📖 Reader Improvements
- **Image Repair Handling**: Enhanced image repair handling with source page fallback options.
- **Reader Routing**: Improved reader routing and download management with new route extra handling.

#### 🏷️ Tag & Metadata
- **Uploader Tag**: Added uploader tag extraction and enhanced tag parsing for E-Hentai.
- **Namespace-Typed Tags**: Added namespace-typed tags and uploader tag injection for generic scraper.

#### 🧩 Architecture
- **Code Refactor**: Refactored code structure for improved readability and maintainability.
- **HTTP Client Fix**: Improved error handling for malformed Set-Cookie headers.
- **WebView Session**: Prevented duplicate CookieManager interceptors in Dio.
- **Parameter Merging**: Enhanced generic scraper parameter merging logic for clarity.

---

## [0.9.17+26] - 2026-04-19

### ✨ Highlights

#### 💬 Nhentai Comments & Auth Polish
- **Submit Comments**: Logged-in nhentai users can now post comments directly from gallery detail pages with inline validation, CAPTCHA fallback, and immediate prepend on success.
- **Auth User-Agent**: Standardized authenticated nhentai requests to `Kuron/<version> (+https://github.com/shirokun20/nhasixapp)` across the config-driven auth and comment flow.

#### 🖼 Reader & Download Reliability
- **Animated WebP Visibility Control**: Fixed the offline/native animated reader so off-screen pages pause correctly instead of continuing to play after the page is no longer current.
- **Original File Extension Preservation**: E-Hentai downloads now save pages using the detected real image format (`.webp`, `.png`, `.gif`, etc.) instead of forcing `.jpg`, improving offline animated-WebP support.
- **Legacy Detection Hardening**: The reader now sniffs local file bytes so older misnamed animated WebP downloads can still route to the native animated renderer.

#### 🛡 Privacy
- **Recent Apps Privacy Overlay**: Added a root-level blur + scrim overlay when the app transitions to background-facing lifecycle states.
- **Android 13+ Native Fallback**: Added a Recents-specific native fallback plus privacy-safe window background to make the recent-apps preview more reliable on modern Android.

### 🩹 Stability & UX
- **Continuous Scroll Cache Regression**: Restored selective image retention so normal non-animated pages recycle properly again in continuous scroll.
- **Native Loader Feedback**: Improved animated WebP native thumbnail preparation so cached files can still show meaningful loading progress.
- **Documentation Sync**: Updated README and FAQ documentation to reflect comment posting and recent-apps privacy behavior.

---


## [0.9.16+25] - 2026-04-12

### ✨ Highlights

#### 📦 MangaDex Integration
- **MangaDex Support**: Added initial support for MangaDex with partial API integration and supporting assets.
- **OpenAPI Config**: Configured `mangadex-config.json` with fallback mechanisms and local cache support.

#### ⭐ Local Collections & Favorites
- **Categorized Collections**: Introduced local collection categories for better organization of favorite series.
- **Management Tools**: Enhanced favorites management including search and deduplication improvements.

#### 📖 Reader Optimizations
- **Smart History Tracking**: Fixed a critical bug where reading progress could reset when navigating back. Introduced precise page tracking (`_lastTrackedPage`) independent of the UI state.
- **Asynchronous Navigation**: Refactored `goToReader` to return a `Future`, enabling better synchronization with reading history updates.

#### 🛠 E-Hentai Sync & Auth
- **Auth UI Cleanup**: Temporarily disabled the incompatible token-based login UI for E-Hentai to avoid user confusion.
- **Config Sync**: Harmonized config keys with the internal `GenericHttpSource` implementation.

### 🩹 Bug Fixes & UX
- **Blacklist Fixes**: Resolved regressions in the blacklist picker's "clear all" functionality.
- **Tag Metadata**: Improved search filters by including detailed tag metadata.

---

## [0.9.15+24] - 2026-04-03

### 🎉 QoL Enhancements — Issue #32

#### 🔐 Nhentai Login & Session Auth
- **Config-Driven Auth**: Added `SourceAuthService`, `SourceAuthCubit`, and `SourceLoginPage` — fully config-driven, no source hardcoding in UI.
- **CAPTCHA Solver (Native)**: Migrated CAPTCHA flow from embedded WebView page to `kuron_native` Android WebView activity (`CaptchaWebViewActivity`) with JS bridge token/error callbacks and status-bar-safe insets.
- **PoW Login Support**: nhentai-config now declares `powAction=login` + full auth endpoint mapping for PoW → CAPTCHA → session persist flow.
- **Route**: Generic `/source-login?source={id}` route and drawer entry appear automatically for any auth-capable config source.

#### ⭐ Online Favorites
- **2-Tab Favorites Screen**: New Offline / Online tab layout; online tab is driven by config capabilities (no source hardcode).
- **Online Favorite Actions**: Add, remove, and check favorite status via config-declared `auth.endpoints.galleryFavorite` template — with paginated online list support (`page` + `q` query).
- **Detail Screen**: Tap favorite heart to choose target — **Offline / Online / Both** — when source supports online write and user has an active session.
- **Resilience**: Auto-retry with bounded attempts + localized friendly error messages for transient network failures.

#### 🗂 Tag Blacklist (Offline + Online)
- **Settings Blacklist Manager**: Modern bottom-sheet editor with chip previews, multi-entry parsing, and nhentai login shortcut.
- **Persistent Local Rules**: `blacklistedTags` now persisted via `PreferencesService` + `SettingsCubit`; rules survive app restarts and work fully offline.
- **Online Sync (nhentai)**: Config-driven `TagBlacklistService` fetches nhentai `/api/v2/blacklist/ids` and merges with local rules for blur matching in feeds.
- **Blur Overlays Applied**: `MainGridCard`, `MainFeaturedCard`, `ContentCard`, `FeaturedContentCard`, offline library cards, and tag-browse result screen.
- **Detail Screen Banner**: Indicator banner when current gallery matches merged blacklist rules.
- **Picker Fix**: `Clear All` + `Apply` now correctly persists empty selection; results replace prior entries instead of appending stale metadata.

#### 🎲 Random Gallery
- **Random Button**: Tapping Random opens a loading dialog, fetches a random gallery from the configured source, and navigates directly to the Detail screen on success.
- **Unavailability Handling**: Clear localized message when the active source does not support random gallery.

#### 🧭 Gesture Navigation
- **Drawer Edge Drag**: Configurable edge drag width to open the navigation drawer with a swipe.
- **Haptic Feedback**: Tactile response on drawer open/close gestures.

#### ⚙️ Centralized Settings
- **Settings Hub**: All download and storage settings consolidated into the main Settings screen.
- **Download Settings Removed from Downloads Screen**: Storage path, download limits, and related options now live exclusively in Settings.
- **ZIP Import Improvements**: Native ZIP extraction with real-time progress dialog and improved large-file handling.

#### 🔍 Native Explorer (Advanced Search)
- **Dynamic Tag Browsing**: API-driven tag explorer with categorized browsing, search, and inline tag detail cards.
- **Tag Detail Screen**: Full tag info with gallery count, related gallery list, and tag-scoped navigation.
- **Tag API v2 Infrastructure**: Clean Architecture tag data source and use case layer for tag queries.

#### ♻️ Refactor
- **Source Config Auth Block**: `assets/configs/nhentai-config.json` now declares auth + blacklist feature flags and all endpoint templates.
- **CAPTCHA Solver Page**: Removed direct `webview_flutter` dependency; all CAPTCHA solving goes through `KuronNative.instance.showCaptchaWebView`.

> ⚠️ **Note**: Sources other than nhentai (E-Hentai, HentaiNexus, Hitomi, etc.) are **premium / advanced sources** requiring manual installation via Settings → Sources → Add via Link or Import ZIP.

---

## [0.9.14+23] - 2026-03-31

### 🔧 Build Update (Build #23)

#### ✨ Enhancement
- **Reader Experience**: Image height caching for instant page render without relayout; floating page indicator for quick navigation awareness.

#### 🐛 Bug Fixes
- **Offline Page**: Prevent duplicate items for externally imported content.
- **ZIP Import**: Calculate and persist `fileSize` when importing ZIP archives.
- **Offline Metadata**: Auto-generate `metadata.json` for manually imported offline content; fixes rendering errors on doujin import.
- **Lint**: Resolve lint errors introduced after ZIP import migration.

#### ♻️ Refactor
- **ZIP Import Handler**: Migrated from `MainActivity` to `kuron_native` plugin for cleaner native boundary separation.
- **ImportZipUseCase**: Improved code readability and formatting.

#### 📝 Docs
- Added comprehensive ZIP Import feature guide (`ZIP_IMPORT_GUIDE.md`).

---

## [0.9.14] - 2026-03-28

### 🎉 Phase 6 Complete: Multi-Provider Special Adapters
- **E-Hentai Source Added**:
  - Full E-Hentai gallery support with per-page reader image extraction
  - E-Hentai session adapter with igneous cookie verification and content warning bypass
  - Dynamic search form with token-based pagination
  - All smoke tests passing (Search→Detail→Reader validated)
- **HentaiNexus Source Added**:
  - HentaiNexus decryption adapter with Base64 → XOR stream decryption
  - Full image URL decryption pipeline for reader support
  - Gate A validation passed on live samples
  - All smoke tests passing (Search→Detail→Reader validated)
- **Hitomi Fallback Support Added**:
  - Hitomi source with fallback-safe registration (full protocol deferred due to gg.js volatility)
  - All smoke tests passing (Search→Detail→Reader via fallback mode validated)
- **Architecture Improvements**:
  - Added adapter override hook in GenericHttpSource for provider-specific adapters
  - Enhanced factory pattern across source resolvers for extensibility
  - All configs staged in manifest-driven `app/config/` layer

### ✅ Verification
- All Phase 6 tasks complete (10/10)
- Test coverage: 8 EHentai + 2 HentaiNexus tests passing
- flutter analyze: No issues found
- Smoke tests: All 3 providers (E-Hentai, HentaiNexus, Hitomi) validated

### 📊 Project Milestone
- **Multi-Provider Integration**: 100% complete (Phase 0-6)
- **Total projects completed**: 12/12 from onprogress → success-plan
- **Ready for**: Production rollout

---

## [0.9.13] - 2026-03-16

### 🚀 New Features
- **MangaDex Expansion**:
  - Added full MangaDex source support with language-aware gallery/chapter retrieval
  - Added original language and available translation metadata in API responses
  - Added chapter pagination support and integration tests for chapter fetch flow
- **Search UX Upgrade**:
  - Added included/excluded tag filtering with multi-select and combined picker support
  - Improved dynamic tag loading, endpoint sorting, and query mapping for search forms
  - Added raw query parameter support for advanced search scenarios
- **Metadata & Detail Enrichment**:
  - Added configurable tag-relations mapping to enrich tags and artists in detail pages
  - Improved detail field label routing and multi-candidate tag resolution
- **HentaiFox Support Improvements**:
  - Added API-first comments handling with CSRF/session fallback support
  - Added favorites/comments integration and robust full-resolution image fallback handling
  - Added upload date extraction and relative date parsing improvements

### 🛠 Fixes
- **Reader Navigation Stability**:
  - Fixed chapter navigation language and reading direction handling in reader settings
  - Fixed chapter list presentation to show chapter index consistently in detail view
  - Added fallback chapter title (`Oneshot`) for empty chapter title fields
- **Search Robustness**:
  - Prevented modal invocation when widget is unmounted to avoid runtime errors
  - Improved picker error handling, loading-state flow, and cache invalidation requirement handling

### 🛠 Improvements
- **Architecture & Source Management**:
  - Removed KomikTap dependency and refactored URL generation to use `SourceUrlResolver`
  - Refactored content URL building to prioritize config-driven URLs while keeping backward compatibility
  - Enhanced generic adapter query-rule support for multi-value parameters
- **Data & Performance**:
  - Added batch loading for completed downloads from local database
  - Improved chapter retrieval fallback logic and chapter ordering detection

### 🔧 Technical
- Updated `pubspec.yaml` to version `0.9.13+21`
- Updated MangaDex config versions through `1.1.4` with related manifest metadata updates

---

## [0.9.12] - 2026-02-15

### 🚀 New Features
- **Enhanced Chapter Reading Experience**:
  - End-of-chapter overlay with "Next Chapter" / "Back to Detail" options
  - Chapter navigation support (Next/Previous chapter buttons)
  - Integrated history tracking for each chapter
  - Chapter selector dropdown in reader settings
  - Support for chapter-based content (Crotpedia, Komiktap)
- **Improved Image Loading**:
  - Replaced `CachedNetworkImage` with `ProgressiveImageWidget` for better static GIF support
  - Source-specific HTTP headers passed to image loading widgets
  - Enhanced compatibility with various content sources
- **Auto-Hide UI**:
  - Reader UI (top/bottom bars) auto-hides and auto-shows on scroll
  - Improved reading experience for immersive content consumption

### 🛠 Fixes
- **Navigation Page Accessibility**:
  - Fixed PageView onPageChanged to report actual page number (35) instead of clamped (34)
  - Fixed nextPage() and updateCurrentPageFromSwipe() to allow pageCount+1 when navigation is enabled
  - UI now displays "Chapter Complete" (bold, primary color) instead of "Page 35 of 34"
  - UI now displays "100%" instead of "103%" overflow
  - Progress bar shows 100% instead of overflow
  - Navigation page accessible via both swipe AND tap "Next" button
  - Only enabled in online mode with content.imageUrls.isNotEmpty
- **Continuous Scroll Enhancement**:
  - Enhanced page detection accuracy using viewport center calculation
  - Adaptive item height calculation based on actual maxScrollExtent
  - Fixed false page saves during programmatic scroll operations
  - Better handling of webtoon (tall images) vs manga (normal images)

### 🛠 Improvements
- **Database**:
  - Database v11: Added chapter support to history table (chapter_id, chapter_index, chapter_title)
  - Database v12: Added parent_id to history for series/parent content tracking
- **History Tracking**:
  - Chapter-level read status tracking
  - Creative read indicators in chapter list:
    - Color-coded chapter badges (tertiary=completed, primary=in-progress)
    - Circular progress ring on chapter number
    - "Done" trophy badge for completed chapters
    - Percentage badge with mini progress for in-progress chapters
  - Auto-scroll to last read chapter when opening from history
- **Search**:
  - Search highlighting for Doujin List, Favorites, and Offline Downloads
  - Title-based search enabled in Favorites

### 🔧 Technical
- Updated `pubspec.yaml` to version `0.9.12+20`
- Added OpenCode configuration and skill definitions
- Modernized Crotpedia UI with Genre List, Doujin List (A-Z index), and Project Request screens

---

## [0.9.11] - 2026-02-11

### 🚀 New Features
- **View Comments**:
  - Added ability to view comments on gallery detail pages.
  - Integration with **NHentai JSON API** for reliable comment data.
  - Robust handling of avatar URLs and comment formatting (Markdown).
  - Modern, card-based UI optimized for readability in both Light and Dark modes.
- **Search Highlighting**:
  - Implemented search term highlighting for **Favorites**, **Offline Downloads**, and **Doujin List**.
  - Improved search experience with visual feedback on matching text.
- **Favorites Enhancement**:
  - Added ability to search favorites by **Title** (previously only ID).

### 🛠 Fixes
- **Favorites Bug Fix**: 
  - Fixed issue where items from certain sources (KomikTap, Crotpedia) displayed overflowing IDs and missing titles.
  - Implemented database migration (v10) to persist titles locally, ensuring data reliability.
  - Fixed UI layout overflow in Favorites cards for long IDs.

### 🛠 Improvements
- **Network Stability**:
  - Implemented `NativeAdapter` for Dio HTTP client to bypass Cloudflare TLS fingerprinting issues (`Connection reset by peer`).
  - Improved resilience of API requests and scraping fallbacks.
- **Architecture**:
  - Refactored `Comment` entity to `kuron_core` for better modularity across packages.
  - Cleaned up legacy scraping code in favor of API-first approach for comments.

### 🔧 Technical
- Updated `pubspec.yaml` to version `0.9.11+19`.
- Added unit tests for API model parsing and comment mapping.
- Enhanced error logging for network requests.

---

## [0.9.10] - 2026-02-08

### 🚀 New Features
- **Crotpedia Enhancements**: 
  - Added **Genre List** screen with browsable genre categories and item counts
  - Added **Doujin List** screen with alphabetical index (A-Z) for easy navigation
  - Added **Project Request** screen displaying community-requested content with pagination
- **Login Required Detection**: Implemented automatic detection and handling for content requiring authentication in Crotpedia

### 🎨 Reader UX Improvements
- **Auto-Hide UI on Scroll**: Reader interface now automatically hides on scroll for immersive reading experience
- **Disabled Zoom in Continuous Scroll**: Prevents accidental zoom gestures in continuous scroll mode for smoother reading
- **Conditional Page Count Display**: Page count now displayed contextually based on reading mode

### 🛠 Improvements
- Enhanced request list parsing with support for genres, ratings, and synopsis
- Updated Crotpedia config to version 1.2.0 with new menu configurations
- Propagated `LoginRequiredException` through content detail retrieval for better error handling

### 🔧 Technical
- New localization strings for login-required scenarios
- Removed debug print statements from Crotpedia scraper tests
- Added `flutter_02.png` screenshot to repository

---

## [0.9.9] - 2026-01-28

### 🚀 Pre-Release Polish
- **Git Migration**: Migrated local packages (`kuron_core`, etc.) to proper git structure.
- **Cleanup**: Removed legacy documentation and unused assets.
- **Stability**: Repository restructuring in preparation for v1.0.0.

## [0.9.0] - 2026-01-26

### 🚀 New Features
- **KomikTap Support**: Added full support for **KomikTap** source, including:
  - Latest updates feed
  - Search functionality
  - Detail view with chapter list
  - Reading capability
- **Dynamic Offline Filters**: 
  - Offline content filter chips are now dynamically generated from configuration.
  - Added support for source-specific coloring (Purple for Crotpedia, Orange for KomikTap, Red for nHentai).
- **Source Labels**: Added colored source labels to download items for easy identification.

### 🛠 Improvements
- **Configuration**: moved hardcoded UI elements to `assets/configs/` for flexibility.
- **Search Logic**: Improved search result prioritization logic.
- **Error Handling**: Enhanced error messages with localization support (EN, ID, ZH).

---

## [0.8.0] - 2026-01-15

### 🚀 Features & UX
- **Tag Pagination**: 
  - Implemented pagination for tag-based searches on **Nhentai** (`/tag/{slug}/?page={N}`).
  - Implemented pagination for genre browsing on **Crotpedia** (`/baca/genre/{slug}/page/{N}/`).
- **Nhentai Smart Search**:
  - Direct navigation to gallery detail page when inputting numeric ID (Gallery ID) in Nhentai search.
  - Skips search results step for faster access to known IDs.
  - Automatic normalization of numeric IDs (removes leading zeros).
- **Crotpedia Account Integration**:
  - Added login functionality for Crotpedia to access all chapters.
  - Source-aware account status in App Drawer.

### 🎨 Rebranding
- **APK Naming**: Updated APK output filename to `kuron_[version]_[date]_[abi].apk` to match the brand identity.

---

## [0.7.2] - 2025-12-28

### 🔒 Privacy & Safety
- **Blur Thumbnails by Default**: Thumbnail blur enabled by default for child safety protection.
- **Blur Toggle Setting**: New setting in Display section to enable/disable blur effect.

### 📋 Legal & Info
- **Terms and Conditions**: New menu in About screen with user agreement.
- **Privacy Policy**: New menu explaining data handling practices.
- **FAQ**: Frequently asked questions with helpful information.
- **Hybrid Loading**: Legal docs fetched from GitHub with local fallback for offline access.
- **2-Language Support**: All legal content available in English and Indonesian.

### Added
- `markdown_widget` package for rendering markdown content in bottom sheets.
- `LegalContentService` with GitHub fetch, caching, and local fallback.
- `LegalContentSheet` bottom sheet widget with loading/error states.

---

## [0.7.1] - 2025-12-21

### 🛠 Fixes & Improvements
- **Detail Screen Image**:
  - Replaced unreliable cover image source with **Page 1 Full Image** (guaranteed high definition & availability).
  - Fixed logic so Detail cover works **Offline** by checking downloaded pages.
- **Sync Notification Context**:
  - Notification `System Sync` now only appears during explicit storage scans (Import/Auto Scan).
  - Silenced notifications for internal DB refreshes and App Startup.
- **Image Fallback**:
  - Implemented robust fallback to Page 1 Thumbnail (`1t`) for list items if main cover fails.

## [0.7.0] - 2025-12-21

### 🌟 Rebranding & UI Overhaul
- **Rebranded to "Kuron"**: New name, identity, and premium feel.
- **Premium UI Redesign**:
  - **Glassmorphism App Drawer**: Animated logo, gradients, and modern navigation.
  - **Paper-Like Light Theme**: Completely revamped light mode with warm, comfortable tones.
  - **Refined Settings**: Card-based layouts, better controls, and cleaner typography.
- **New About Screen**: Interactive branding, changelog summary, and direct links.

### Added
- **In-App Update Checker**: Automatically checks GitHub releases for updates.
- **Animated Logos**: Pulsing animations in Drawer and About screen.
- **Sort By UI**: Improved sorting chips and dropdowns styling.

### Fixed
- **Localization Bug**: Fixed app name reverting to old name in some locales.
- **Text Visibility**: Fixed invisible text in light theme hardcoded colors.
- **Navigation Transitions**: Unified smooth fade transitions across all screens.

## [0.6.2] - 2025-12-21

### Fixed
- Fixed API sorting issue where "Popular" filters were ignored and defaulted to "Newest"
- Fixed content reader attempting to load items with 0 images (now forces fresh fetch)
- Improved cache validation to prevent using incomplete content data from search results

## [0.6.1] - 2025-12-14

### Fixed
- Fixed offline content bugs where deleted files persisted in list
- Fixed notification permission issues causing missing notifications
- Fixed build error related to desugaring libs

## [0.6.0] - 2025-12-12

### Added
- **Export Library**: Export database and content files to shareable folder with progress dialog
- **Import from Backup**: Manual import button to sync backup folder content to database
- **Database-First Loading**: Offline screen now loads from database first (faster startup)
- **Sync to Database**: Automatic sync of backup folder content with duplicate handling

### Changed
- Offline screen no longer auto-scans file system on startup (uses database)
- Delete now works for backup-scanned items (passes content path directly)
- AppBar redesigned with Import/Export buttons instead of permission debug button

### Fixed
- Delete offline content not working for items from backup folder
- Path lookup failing for content not in database

### Technical
- New `ExportService` for library export and sharing
- `OfflineSearchCubit` now uses `UserDataRepository.getAllDownloads()`
- `OfflineContentManager.syncBackupToDatabase()` with smart duplicate handling
- `OfflineContentManager.deleteOfflineContent()` now accepts optional `contentPath`

---

## [0.5.0] - 2025-11-26

### Added
- Initial release with core features
- Home screen with content discovery
- Immersive reader mode
- Smart search with filters
- App Disguise mode
- Offline downloads with bulk management
- History and favorites
- Dark/Light theme with Material 3

---

## Version History

| Version | Date | Type | Description |
|:--------|:-----|:-----|:------------|
| 0.6.0 | 2025-12-12 | Feature | Offline export & database-first |
| 0.5.0 | 2025-11-26 | Release | Initial public release |
