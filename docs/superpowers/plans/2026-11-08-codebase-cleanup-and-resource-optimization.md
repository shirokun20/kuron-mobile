# Codebase Cleanup and Resource Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove unused dead code, zombie dependencies, unused native artifacts, and orphaned assets to optimize app resources, APK size, and maintainability.

**Architecture:** Maintain strict Clean Architecture boundaries while pruning confirmed dead code in Presentation, Core, and Data layers, removing zombie dependencies in root `pubspec.yaml` and `kuron_native`, excluding desktop `.so` libraries from Android APK packaging, and cleaning up unread assets and duplicate Gradle files.

**Tech Stack:** Flutter / Dart, Gradle, FVM.

**Spec:** Grounded Karpathy audit findings (session 2026-11-08).

## Global Constraints

- Never commit (`git add` / `git commit` forbidden; source control is strictly user-managed per `AGENTS.md`).
- All Dart/Flutter operations must use `fvm`.
- Zero broken imports or regression: all existing tests must pass, and `fvm dart analyze` must be 100% clean.
- Only remove strictly verified dead code with 0 callers/references.

## Review Focus

1. Verify no existing caller is broken when deleting the 13 orphaned Dart files.
2. Verify `pub get` runs cleanly after removing zombie dependencies (`webview_flutter`, `http_client_helper`, redundant `pointycastle`, `ffi`).
3. Verify Android packaging configuration syntax in `android/app/build.gradle` is valid.
4. Verify Flutter asset bundle builds without warning after removing unneeded asset directory references.

---

### Task 1: Clean Zombie Dependencies from `pubspec.yaml` and `kuron_native/pubspec.yaml`

**Files:**
- Modify: `pubspec.yaml`
- Modify: `packages/kuron_native/pubspec.yaml`

- [ ] 1.1 Remove `http_client_helper: ^3.0.0` from `pubspec.yaml`
- [ ] 1.2 Remove `webview_flutter: ^4.14.1` from `pubspec.yaml`
- [ ] 1.3 Remove redundant root declaration `pointycastle: ^4.0.0` from `pubspec.yaml` (maintained in `kuron_generic`)
- [ ] 1.4 Remove `ffi: ^2.2.0` and `ffiPlugin: true` from `packages/kuron_native/pubspec.yaml`
- [ ] 1.5 Run `fvm flutter pub get` across workspace to verify clean resolution

---

### Task 2: Exclude Desktop Native Libraries from Android APK Packaging

**Files:**
- Modify: `android/app/build.gradle`

- [ ] 2.1 Add `excludes += "lib/**/libcnativeapi.so"` into `packaging.jniLibs` in `android/app/build.gradle`
- [ ] 2.2 Verify gradle syntax

---

### Task 3: Remove Dead Assets, Backup Files, and Duplicate Gradle DSL Files

**Files:**
- Delete: `assets/widget/` (and all 6 png files)
- Delete: `assets/configs/nhentai-config.original.json`
- Delete: `assets/configs/version.json`
- Delete: `assets/icons/nhentai.png`
- Delete: `lib/presentation/cubits/settings/settings_cubit.dart.backup`
- Delete: `packages/kuron_native/android/build.gradle.kts`
- Delete: `packages/kuron_native/android/settings.gradle.kts`
- Modify: `pubspec.yaml` (remove `- assets/widget/`)

- [ ] 3.1 Remove `- assets/widget/` from `pubspec.yaml`
- [ ] 3.2 Delete dead asset files and directories
- [ ] 3.3 Delete `.backup` file
- [ ] 3.4 Delete duplicate `.gradle.kts` files in `packages/kuron_native/android/`
- [ ] 3.5 Run `fvm flutter pub get`

---

### Task 4: Remove 13 Verified Dead Dart Files (1,949 Lines)

**Files to delete:**
- `lib/presentation/widgets/featured_content_card.dart`
- `lib/presentation/widgets/modern_pagination_widget.dart`
- `lib/core/utils/search_query_builder.dart`
- `lib/core/utils/url_nhentai_util.dart`
- `lib/data/models/pagination_model.dart`
- `lib/presentation/pages/crotpedia/crotpedia_login_page.dart`
- `lib/core/utils/theme_debug_utility.dart`
- `lib/presentation/widgets/download_storage_error_widget.dart`
- `lib/presentation/widgets/content_grid.dart`
- `lib/presentation/widgets/crotpedia_login_prompt.dart`
- `lib/data/datasources/remote/remote_data_source_factory.dart`
- `lib/core/services/chapter_cache.dart`
- `lib/core/services/workers/workers.dart`

- [ ] 4.1 Delete the 13 orphaned files
- [ ] 4.2 Clean any remaining dangling comments or unused imports if any

---

### Task 5: Verification & Full Regression Testing

- [ ] 5.1 Run `fvm dart analyze` across the entire workspace (expect 0 issues)
- [ ] 5.2 Run targeted widget & unit tests (`combined_home_test.dart`, `kuron_cli_test.dart`, etc.)
- [ ] 5.3 Update `MEMORY.md` with recorded optimizations
