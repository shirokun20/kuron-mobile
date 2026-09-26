# Panduan Config Source (Config-Driven)

> **Kuron App** — Cara membuat, mendaftarkan, dan memvalidasi config sumber konten baru.

---

## Gambaran Umum

Kuron menggunakan **arsitektur berbasis config**. Setiap sumber konten (situs manga/doujin) sepenuhnya dideskripsikan oleh satu file JSON. Tidak perlu mengubah kode Dart untuk menambahkan sumber baru — file config adalah satu-satunya artefak yang dibutuhkan.

Sebuah config lengkap mendeskripsikan **enam hal**:

| # | Apa | Key |
|---|-----|-----|
| 1 | Identitas sumber & base URL | `source`, `baseUrl`, `version` |
| 2 | Info tampilan UI (nama, ikon, warna) | `ui` |
| 3 | Aturan jaringan (bypass, headers, rate limit) | `network` |
| 4 | Cara mengambil list / detail / chapter | `scraper` atau `api` |
| 5 | Cara mengambil dan menampilkan gambar di reader | `scraper.selectors.reader` |
| 6 | Fitur apa saja yang didukung sumber ini | `features` |

---

## Anatomi Config

File config adalah satu objek JSON. Minimal harus memiliki:

```
source          (wajib)  ID sumber unik — harus cocok dengan prefix nama file
version         (wajib)  String versi semanti, misal "1.0.0"
enabled         (wajib)  true/false — matikan tanpa menghapus file
baseUrl         (wajib)  URL root situs
defaultLanguage (wajib)  misal "english", "japanese", "indonesian", "unknown"
scraper atau api (wajib) Minimal satu data driver harus ada
features        (wajib)  Flag kemampuan fitur
ui              (wajib)  Metadata tampilan untuk UI aplikasi
```

---

## Field Level Teratas

```jsonc
{
  // ── Identitas ─────────────────────────────────────────────────────
  "source": "mysite",               // WAJIB. ID snake_case unik
  "version": "1.0.0",              // WAJIB. Naikan setiap ada perubahan config
  "enabled": true,                  // WAJIB. false = sumber disembunyikan di app
  "baseUrl": "https://mysite.com", // WAJIB. Dipakai untuk resolve URL relatif

  // ── Bahasa ────────────────────────────────────────────────────────
  "defaultLanguage": "english",
  // Nilai: "english" | "japanese" | "chinese" | "korean"
  //        "indonesian" | "thai" | "vietnamese" | "unknown"
  // Dipakai saat item individual tidak punya tag bahasa

  // ── Remote sync (opsional) ────────────────────────────────────────
  "configUrl": "https://raw.githubusercontent.com/.../mysite-config.json",
  // Jika ada, app bisa hot-reload config ini dari URL remote

  // ── Pola ID konten (opsional) ─────────────────────────────────────
  "contentIdPattern": "/manga/([^/]+)",
  // Regex untuk mengekstrak content ID dari URL lengkap

  // ── Tampilan UI ───────────────────────────────────────────────────
  "ui": {
    "displayName": "My Site",
    "iconPath": "https://raw.githubusercontent.com/shirokun20/nhasixapp/refs/heads/master/app/images/mysite.png",
    "brandColor": "#FF6740",
    "openInBrowserUrl": "https://mysite.com"
  },

  // ── Aturan jaringan ───────────────────────────────────────────────
  "network": {
    "requiresBypass": false,      // true = perlu bypass Cloudflare/WebView
    "headers": {
      "Referer": "https://mysite.com/",
      "User-Agent": "Mozilla/5.0"
    },
    "rateLimit": {                // Opsional: throttle request
      "requestsPerSecond": 1,
      "maxConcurrentRequests": 2
    }
  }
}
```

---

## Data Driver: `scraper` (HTML)

Gunakan ini saat situs hanya menyajikan halaman HTML.

```jsonc
"scraper": {
  "enabled": true,

  // ── Template URL ──────────────────────────────────────────────────
  "urlPatterns": {
    // Halaman home / terbaru
    "home": {
      "url": "/",
      "list": {
        "container": ".gallery-item",        // Selector CSS untuk setiap kartu
        "fields": {
          "id": {
            "selector": "a",
            "attribute": "href",
            "transform": "slug"              // PENTING: selalu pakai untuk ID
          },
          "title": { "selector": ".title" },
          "coverUrl": { "selector": "img", "attribute": "src" }
        },
        "pagination": {
          "next": "a.next-page",
          "links": ".pagination a"
        }
      }
    },

    // Halaman N dari home (gunakan placeholder {page})
    "homePage": { "url": "/page/{page}/", "inherits": "home" },

    // Pencarian
    "search": { "url": "/?s={query}", "inherits": "home" },
    "searchPage": { "url": "/page/{page}/?s={query}", "inherits": "search" },

    // Browse genre/tag
    "genreSearch": { "url": "/genre/{tag}/", "inherits": "home" },
    "genreSearchPage": { "url": "/genre/{tag}/page/{page}/", "inherits": "home" },

    // Halaman detail (ringkasan series)
    "detail": "/manga/{id}/",

    // Halaman chapter/reader
    "chapter": "/{id}/"
  },

  // ── Selector CSS ──────────────────────────────────────────────────
  "selectors": {
    "detail": {
      "fields": {
        "title":       { "selector": "h1.title" },
        "coverUrl":    { "selector": ".cover img", "attribute": "src" },
        "author":      { "selector": ".author a" },
        "tags":        { "selector": ".tags a", "multi": true },
        "status":      { "selector": ".status" },
        "description": { "selector": ".synopsis" }
      },

      // Daftar chapter (hanya untuk sumber multi-chapter)
      "chapters": {
        "container": ".chapter-list li",
        "fields": {
          "id": {
            "selector": "a",
            "attribute": "href",
            "transform": "slug"   // HARUS cocok dengan output nav reader
          },
          "title": { "selector": ".chapter-name" },
          "date":  { "selector": ".chapter-date" }
        }
      }
    },

    // ── Reader (wajib untuk bisa membaca) ────────────────────────────
    "reader": {
      "container": "#reader-wrap",       // Elemen pembungkus gambar
      "images": {
        "selector": "#reader-wrap img",  // Selector gambar
        "attribute": "src"               // Atribut URL gambar (src/data-src/dll)
      },
      // Link navigasi chapter dari DOM halaman reader
      "nav": {
        "next": "a.btn-next",
        "prev": "a.btn-prev"
      }
    }
  }
}
```

### Opsi Field Selector

| Key | Tipe | Keterangan |
|-----|------|------------|
| `selector` | string | CSS selector |
| `attribute` | string | Atribut HTML yang dibaca (hilangkan untuk baca teks) |
| `transform` | `"slug"` | Ambil segmen path terakhir yang bermakna dari URL |
| `regex` | string | Regex dengan satu capture group untuk filter/ekstrak nilai |
| `multi` | boolean | Kembalikan array alih-alih nilai tunggal |
| `fallback` | string | Nilai fallback statis jika ekstraksi kosong |

> ⚠️ **Aturan kritis**: Field `id` pada chapter list **harus** menggunakan `"transform": "slug"` saat diekstrak dari `href`. Tanpa ini, navigasi next/prev di reader tidak bisa mencocokkan chapter di `_allChapters` dan akan menampilkan `unknownChapter`.

---

## Data Driver: `api` (REST JSON)

Gunakan ini saat situs menyediakan JSON API.

```jsonc
"api": {
  "enabled": true,
  "url": "https://api.mysite.com",  // Opsional: override baseUrl untuk API

  "endpoints": {
    "allGalleries": "/manga?page={page}",
    "search": "/manga?q={query}&page={page}",
    "detail": "/manga/{id}"
  },

  // Parsing response list
  "list": {
    "items": "$.data[*]",            // JSONPath ke array item
    "pagination": {
      "offsetMode": false,           // true = pakai offset, false = pakai page
      "currentPage": { "path": "$.page" },
      "total":       { "path": "$.total" },
      "limit":       { "path": "$.limit" }
    },
    "fields": {
      "id":       { "selector": "$.id" },
      "title":    { "selector": "$.attributes.title" },
      "coverUrl": { "selector": "$.cover.url" },
      "tags":     { "selector": "$.tags[*].name", "multi": true },
      "language": { "selector": "$.language" }
    }
  },

  // Parsing response detail
  "detail": {
    "fields": {
      "id":    { "selector": "$.data.id" },
      "title": { "selector": "$.data.attributes.title" }
    },
    // Daftar chapter dari endpoint terpisah
    "chapters": {
      "endpoint": "/manga/{id}/chapters?limit=100",
      "items": "$.data[*]",
      "fields": {
        "id":            { "selector": "$.id" },
        "chapterNum":    { "selector": "$.attributes.chapter" },
        "title":         { "selector": "$.attributes.title" },
        "language":      { "selector": "$.attributes.translatedLanguage" },
        "externalUrl":   { "selector": "$.attributes.externalUrl" },
        "pages":         { "selector": "$.attributes.pages" },
        "isUnavailable": { "selector": "$.attributes.isUnavailable" },
        "date":          { "selector": "$.attributes.publishAt" }
      }
    }
  },

  // Cara mengambil gambar chapter
  "images": {
    "mode": "atHome",
    "atHomeEndpoint": "/at-home/server/{chapterId}"
    // Mode lain: "directUrl", "hentaifoxCdn"
  }
}
```

> **Chapter eksternal MangaDex**: Jika `externalUrl` tidak kosong, chapter di-host di situs pihak ketiga (mis. `comikey.com`) dan `pages` bernilai `0`. Aplikasi membuka `externalUrl` di browser eksternal, bukan memanggil `/at-home/server/{chapterId}`. Jangan set `includeExternalUrl` — tanpa param ini API mengembalikan kedua tipe chapter (dengan `externalUrl` tetap ada); `includeExternalUrl=1` justru filter ke *hanya* eksternal dan bikin manga tanpa chapter eksternal jadi 0.

---

## Flag Fitur

Mengontrol fitur UI mana yang muncul untuk sumber ini.

```jsonc
"features": {
  "search":         true,   // Search bar terlihat
  "chapters":       true,   // Navigasi chapter aktif (series multi-chapter)
  "download":       true,   // Izinkan download offline
  "favorite":       true,   // Izinkan tambah ke favorit
  "comments":       false,  // Tampilkan seksi komentar
  "related":        false,  // Tampilkan konten terkait
  "generatePdf":    true,   // Izinkan ekspor PDF
  "offlineMode":    true,   // Izinkan membaca offline
  "advancedSearch": false,  // Tampilkan form pencarian lanjutan
  "supportsAuth":   false   // Tampilkan tombol login
}
```

---

## Search Form

Mendeklarasikan parameter query mana yang ditampilkan di UI pencarian.

```jsonc
"searchForm": {
  "urlPattern": "search",
  "params": {
    "query": {
      "queryParam": "s",
      "type": "text",
      "placeholder": "Cari manga..."
    },
    "page": {
      "queryParam": "page",
      "type": "page"
    }
  }
}
```

---

## Autentikasi (Opsional)

Hanya dibutuhkan untuk sumber dengan konten yang butuh login.

```jsonc
"auth": {
  "enabled": true,
  "loginUrl": "https://mysite.com/login/",
  "registerUrl": "https://mysite.com/register/",
  "bookmarkUrl": "https://mysite.com/bookmarks/",
  "nonceRegex": "name=\"_nonce\" value=\"([^\"]+)\"",
  "loginSuccessFilter": "/dashboard"
}
```

---

## Tag Navigation Mapping (Opsional)

Memetakan tipe tag ke format query pencarian saat user mengetuk tag.

```jsonc
"navigation": {
  "tagQueryMapping": {
    "artist": {
      "mode": "rawParam",
      "param": "q",
      "valueSource": "tagName",
      "valuePrefix": "artist:\"",
      "valueSuffix": "\""
    },
    "default": {
      "mode": "rawParam",
      "param": "q",
      "valueSource": "tagName",
      "valuePrefix": "tag:\""
    }
  }
}
```

---

## Dekripsi (Sumber Khusus)

Untuk sumber yang mengenkripsi data reader (mis. HentaiNexus XOR/RC4).

```jsonc
"decryption": {
  "method": "initReader_xor_rc4_variant",
  "hostname": "mysite.com",
  "readerPath": "/read/{id}",
  "encryptedDataPattern": "initReader\\(\\s*\"([^\"]+)\""
}
```

---

## Langkah demi Langkah: Menambahkan Sumber Baru

### 1. Buat file config

Nama file: `<source-id>-config.json`, taruh di staging `<kuron-extensions>/config/new/`, lalu pindah ke bucket bahasa (`config/<lang>/`) sesuai skill kuron-source-config.  
Prefix nama file **harus** cocok dengan nilai field `"source"`.

### 2. Struktur minimum yang dibutuhkan

```json
{
  "source": "mysite",
  "version": "1.0.0",
  "enabled": true,
  "baseUrl": "https://mysite.com",
  "defaultLanguage": "english",
  "ui": {
    "displayName": "My Site",
    "iconPath": "https://...",
    "brandColor": "#000000"
  },
  "network": {
    "requiresBypass": false,
    "headers": {}
  },
  "scraper": {
    "enabled": true,
    "urlPatterns": {
      "home": {
        "url": "/",
        "list": {
          "container": ".item",
          "fields": {
            "id": { "selector": "a", "attribute": "href", "transform": "slug" },
            "title": { "selector": ".title" },
            "coverUrl": { "selector": "img", "attribute": "src" }
          }
        }
      },
      "detail": "/manga/{id}/",
      "chapter": "/{id}/"
    },
    "selectors": {
      "detail": {
        "fields": {
          "title": { "selector": "h1" }
        },
        "chapters": {
          "container": ".chapter-list li",
          "fields": {
            "id": { "selector": "a", "attribute": "href", "transform": "slug" },
            "title": { "selector": "a" }
          }
        }
      },
      "reader": {
        "images": {
          "selector": ".reader-container img",
          "attribute": "src"
        },
        "nav": {
          "next": "a.next-chapter",
          "prev": "a.prev-chapter"
        }
      }
    }
  },
  "features": {
    "chapters": true,
    "download": true,
    "favorite": true
  }
}
```

### 3. Validasi JSON

```bash
python3 -c "import json; json.load(open('<kuron-extensions>/config/new/mysite-config.json'))"
```

### 4. Uji selector di browser

Buka halaman target di DevTools browser dan uji selector CSS di console:

```js
document.querySelectorAll(".chapter-list li")  // Harus mengembalikan item chapter
document.querySelector(".chapter-list li a").getAttribute("href")  // URL chapter
document.querySelectorAll(".reader-container img")  // Harus mengembalikan gambar
```

### 5. Alur data hingga reader berfungsi

```
Config                    App
──────                    ───
urlPatterns.detail   →    Fetch halaman detail series
selectors.detail         → Parse judul, cover, tags
selectors.detail.chapters → Bangun daftar chapter (_allChapters)

urlPatterns.chapter  →    Fetch halaman reader chapter
selectors.reader.images  → Ekstrak URL gambar → tampilkan di reader

selectors.reader.nav     → Ekstrak link next/prev dari DOM halaman reader
                           Harus berupa slug → cocokkan dengan _allChapters.id
```

### 6. Masalah umum dan solusinya

| Gejala | Penyebab | Solusi |
|--------|----------|--------|
| `unknownChapter` di reader | Format `id` chapter tidak cocok antara list dan nav | Tambahkan `"transform": "slug"` pada field `id` di chapter list |
| Tidak ada gambar di reader | Selector atau attribute `images` salah | Inspect DOM nyata untuk selector yang benar |
| Daftar chapter kosong | `chapters.container` salah | Inspect DOM halaman detail |
| Pagination berhenti di halaman 2 | Pola URL untuk halaman N tidak ada | Tambahkan `homePage` / `searchPage` dengan placeholder `{page}` |
| Tag tampil sebagai slug | Terbaca dari `attribute` bukan teks | Hapus `attribute` agar selector membaca teks konten |
| Gambar tidak muncul (data-src) | Gambar lazy-load pakai atribut lain | Ganti `"attribute": "src"` menjadi `"attribute": "data-src"` |

---

## Matriks Referensi Field

| Field | Sumber scraper | Sumber API | Wajib? |
|-------|---------------|-----------|--------|
| `source` | ✅ | ✅ | **Wajib** |
| `version` | ✅ | ✅ | **Wajib** |
| `enabled` | ✅ | ✅ | **Wajib** |
| `baseUrl` | ✅ | ✅ | **Wajib** |
| `defaultLanguage` | ✅ | ✅ | **Wajib** |
| `ui` | ✅ | ✅ | **Wajib** |
| `network` | ✅ | ✅ | **Wajib** |
| `scraper` | ✅ | ❌ | Salah satu scraper/api |
| `api` | ❌ | ✅ | Salah satu scraper/api |
| `features` | ✅ | ✅ | **Wajib** |
| `scraper.selectors.reader` | ✅ | — | **Wajib** agar reader berfungsi |
| `scraper.selectors.reader.nav` | opsional | — | Wajib untuk navigasi next/prev |
| `contentIdPattern` | opsional | opsional | Opsional |
| `configUrl` | opsional | opsional | Opsional |
| `auth` | opsional | opsional | Opsional |
| `searchForm` | opsional | opsional | Opsional |
| `navigation.tagQueryMapping` | opsional | opsional | Opsional |
| `decryption` | opsional | opsional | Opsional |
| `network.rateLimit` | opsional | opsional | Opsional |
