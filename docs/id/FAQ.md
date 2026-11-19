# Pertanyaan yang Sering Diajukan (FAQ)

---

**Q: Apa itu Kuron?**

Kuron adalah klien pihak ketiga tidak resmi untuk menjelajahi konten. Aplikasi ini menyediakan antarmuka yang ramah seluler dengan fitur tambahan seperti pembacaan offline dan favorit.

---

**Q: Apakah Kuron gratis?**

Ya, Kuron sepenuhnya gratis dan open-source. Anda dapat melihat kode sumbernya di GitHub.

---

**Q: Apakah Kuron aman digunakan?**

Ya. Aplikasi tidak mengumpulkan data pribadi apapun dan semua informasi disimpan secara lokal di perangkat Anda.

---

**Q: Bagaimana cara menonaktifkan efek blur?**

Pergi ke **Pengaturan → Tampilan → Blur Thumbnail** dan matikan.

> Catatan: Blur diaktifkan secara default untuk perlindungan privasi.

---

**Q: Di mana file unduhan disimpan?**

Unduhan disimpan di folder: `Downloads/nhasix/` di perangkat Anda.

---

**Q: Bisakah saya menggunakan aplikasi secara offline?**

Ya! Konten yang telah Anda unduh dapat diakses tanpa koneksi internet. Pergi ke tab **Offline** untuk melihat konten yang telah diunduh.

---

**Q: Bagaimana cara menambahkan konten ke favorit?**

Buka galeri manapun dan ketuk **ikon hati** untuk menambahkannya ke favorit Anda.

---

**Q: Bagaimana cara menghapus riwayat baca?**

Pergi ke **Pengaturan → Pembaca → Hapus Semua Riwayat** atau aktifkan **Pembersihan Otomatis** untuk manajemen riwayat otomatis.

---

**Q: Aplikasi tidak bisa terhubung / menampilkan error**

Coba solusi berikut:
1. Periksa koneksi internet Anda
2. Website mungkin sedang down sementara
3. Gunakan VPN jika akses diblokir di wilayah Anda
4. Tarik ke bawah untuk refresh konten
5. **Khusus Crotpedia**: Beberapa chapter mewajibkan login. Buka **Drawer → Login** untuk mengakses konten penuh.
6. **Nhentai**: Beberapa fitur (favorit online, sinkronisasi blacklist) memerlukan login. Buka **Drawer → Login (nhentai)** untuk masuk.

---

**Q: Bisakah saya login dengan akun nhentai?**

Ya! Kuron mendukung login nhentai mulai versi v0.9.15:
- Buka **Drawer → Login (nhentai)** dan masukkan kredensial Anda.
- Anda mungkin perlu menyelesaikan CAPTCHA saat login — ketuk **Solve CAPTCHA** dan selesaikan tantangannya.
- Setelah login, Anda dapat menyinkronkan **favorit online** dan **blacklist tag** nhentai (tag yang ingin Anda sembunyikan di feed).

---

**Q: Apa itu Favorit Online?**

Favorit Online disinkronkan langsung dengan akun nhentai Anda. Saat menambahkan galeri ke favorit dari layar Detail, Anda bisa memilih:
- **Offline** — disimpan hanya di perangkat lokal
- **Online** — disinkronkan ke akun nhentai Anda (memerlukan login)
- **Keduanya** — disimpan lokal DAN disinkronkan ke nhentai

Lihat favorit online di tab **Favorit → Online**.

---

**Q: Bisakah saya mengirim komentar di nhentai?**

Bisa. Jika Anda sudah login, halaman detail galeri nhentai yang didukung sekarang memungkinkan Anda menulis dan mengirim komentar langsung dari layar detail.
- Panjang komentar harus mengikuti batas validasi di aplikasi.
- Anda mungkin diminta menyelesaikan CAPTCHA lagi sebelum komentar diterima.
- Komentar yang berhasil dikirim akan langsung dimasukkan kembali ke diskusi yang sedang terbuka.

---

**Q: Mengapa preview aplikasi terlihat blur di recent apps?**

Kuron memang mengaburkan preview di recent apps untuk menjaga privasi ketika aplikasi masuk ke background.
- Overlay blur/scrim diterapkan segera saat aplikasi berpindah dari foreground.
- Di Android 13 ke atas, ada fallback native tambahan agar preview Recents lebih konsisten terlindungi.
- Perilaku privasi ini terpisah dari reader dan dirancang agar tidak mengganggu handoff background normal.

---

**Q: Apa itu Tag Blacklist?**

Tag Blacklist memungkinkan Anda menyembunyikan konten yang tidak diinginkan dengan memblur thumbnail di semua feed.
- **Aturan lokal**: Kelola tag di **Pengaturan → Blacklist**. Bekerja offline, tidak perlu login.
- **Sinkronisasi online (nhentai)**: Saat login, blacklist server-side nhentai Anda otomatis digabungkan dengan aturan lokal untuk pencocokan blur gabungan.

---

**Q: Apa itu "Source Lain"? Apakah gratis?**

Kuron mendukung beberapa penyedia konten selain nhentai:
- **MangaDex, E-Hentai, HentaiNexus, Hitomi, dan lainnya** adalah **source tingkat lanjut**.
- Source ini **tidak disertakan** secara default dan memerlukan instalasi manual melalui:
  **Pengaturan → Sources → Add via Link** atau **Import ZIP**.
- Source-source ini mungkin memerlukan akun (MangaDex, E-Hentai) atau memiliki persyaratan akses sendiri.
- nhentai adalah source gratis default yang sudah tersedia langsung.

---

**Q: Gambar tidak dimuat**

1. Periksa koneksi internet Anda
2. Coba ubah **Kualitas Gambar** di Pengaturan
3. Bersihkan cache aplikasi
4. Server mungkin mengalami traffic tinggi

---

**Q: Unduhan gagal**

1. Pastikan Anda memiliki ruang penyimpanan yang cukup
2. Periksa apakah izin penyimpanan diberikan
3. Coba unduh lebih sedikit item sekaligus
4. Periksa stabilitas internet Anda

---

**Q: Aplikasi lambat atau lag**

1. Hapus unduhan yang sudah selesai
2. Kurangi kolom grid di Pengaturan
3. Aktifkan **Pembersihan Otomatis Riwayat**
4. Restart aplikasi

---

**Q: Apakah aplikasi mengumpulkan data saya?**

Tidak. Kuron tidak mengumpulkan informasi pribadi apapun. Semua data (riwayat, favorit, pengaturan) disimpan secara lokal di perangkat Anda saja.

---

**Q: Apakah riwayat browsing saya dibagikan?**

Tidak. Riwayat browsing Anda tidak pernah dibagikan dan tetap hanya ada di perangkat Anda.

---

**Q: Bagaimana cara menghapus semua data saya?**

Anda bisa:
- Reset fitur individual di Pengaturan
- Uninstall aplikasi (menghapus semua data)

---

**Q: Bagaimana cara memperbarui aplikasi?**

Pergi ke **Tentang → Periksa Pembaruan**. Anda akan diberi tahu ketika versi baru tersedia di GitHub.

Rilis terbaru saat ini: **v0.9.29+39**
https://github.com/shirokun20/nhasixapp/releases/tag/v0.9.29%2B39

---

**Q: Mengapa aplikasi tidak ada di Play Store?**

Karena pembatasan konten, aplikasi didistribusikan hanya melalui GitHub releases.

---

**Q: Bagaimana cara melaporkan bug?**

Silakan buka issue di repositori GitHub kami dengan:
- Deskripsi masalah
- Langkah-langkah untuk mereproduksi
- Model perangkat dan versi Android Anda

---

**Q: Bagaimana saya bisa berkontribusi?**

Aplikasi ini open-source! Anda dapat berkontribusi dengan:
- Mengirimkan laporan bug
- Menyarankan fitur
- Berkontribusi kode melalui pull request

---

*Tidak menemukan jawaban Anda? Kunjungi repositori GitHub kami untuk bantuan lebih lanjut.*
