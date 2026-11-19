# Frequently Asked Questions (FAQ)

---

**Q: What is Kuron?**

Kuron is an unofficial, third-party client for browsing content. It provides a mobile-friendly interface with additional features like offline reading and favorites.

---

**Q: Is Kuron free?**

Yes, Kuron is completely free and open-source. You can view the source code on GitHub.

---

**Q: Is Kuron safe to use?**

Yes. The app does not collect any personal data and all information is stored locally on your device.

---

**Q: How do I disable the blur effect?**

Go to **Settings → Display → Blur Thumbnails** and turn it OFF.

> Note: Blur is enabled by default for privacy protection.

---

**Q: Where are downloaded files saved?**

Downloads are saved in: `Downloads/nhasix/` folder on your device.

---

**Q: Can I use the app offline?**

Yes! Content that you have downloaded can be accessed without an internet connection. Go to the **Offline** tab to view your downloaded content.

---

**Q: How do I add content to favorites?**

Open any gallery and tap the **heart icon** to add it to your favorites.

---

**Q: How do I clear my reading history?**

Go to **Settings → Reader → Clear All History** or enable **Auto Cleanup** for automatic history management.

---

**Q: The app can't connect / shows errors**

Try these solutions:
1. Check your internet connection
2. The website may be temporarily down
3. Try using a VPN if access is blocked in your region
4. Pull down to refresh the content
5. **Crotpedia Only**: Some chapters require login. Navigate to **Drawer → Login** to access full content.
6. **Nhentai**: Some actions (online favorites, blacklist sync) require login. Go to **Drawer → Login (nhentai)** to sign in.

---

**Q: Can I log in with my nhentai account?**

Yes! Kuron supports nhentai login starting from v0.9.15:
- Go to **Drawer → Login (nhentai)** and enter your credentials.
- You may need to solve a CAPTCHA during login — tap **Solve CAPTCHA** and complete the challenge.
- Once logged in, you can sync your **online favorites** and your nhentai **blacklist** (tags you want to blur in feeds).

---

**Q: What are Online Favorites?**

Online Favorites are synced directly with your nhentai account. When adding a gallery to favorites from the Detail screen, you can choose:
- **Offline** — saved locally on device only
- **Online** — synced to your nhentai account (requires login)
- **Both** — saved locally AND synced to nhentai

View online favorites in **Favorites → Online** tab.

---

**Q: Can I post comments on nhentai?**

Yes. If you're logged in, supported nhentai gallery pages now let you write and submit comments directly from the detail screen.
- Comment length must stay within the in-app validation limits.
- You may be asked to solve a CAPTCHA again before the comment is accepted.
- Successful comments are inserted back into the current discussion immediately.

---

**Q: Why does the app preview look blurred in recent apps?**

Kuron obscures the recent-apps preview on purpose to protect your privacy when the app goes into the background.
- The blur/scrim overlay is applied as soon as the app transitions away from the foreground.
- On Android 13 and newer, an additional native fallback is used so the Recents preview is more reliable.
- This privacy behavior is separate from the reader itself and is designed not to interrupt normal background handoff behavior.

---

**Q: What is the Tag Blacklist?**

The Tag Blacklist lets you hide unwanted content by blurring thumbnails in all feeds.
- **Local rules**: Manage tags in **Settings → Blacklist**. Works offline, no login required.
- **Online sync (nhentai)**: When logged in, your nhentai server-side blacklist is automatically merged with local rules for combined blur matching.

---

**Q: What are "Other Sources"? Are they free?**

Kuron supports multiple content providers beyond nhentai:
- **MangaDex, E-Hentai, HentaiNexus, Hitomi, and others** are **advanced sources**.
- They are **not bundled** by default and require manual installation via:
  **Settings → Sources → Add via Link** or **Import ZIP**.
- These sources may require an account (MangaDex, E-Hentai) or have their own access requirements.
- nhentai is the default free source included out of the box.

---

**Q: Images aren't loading**

1. Check your internet connection
2. Try changing **Image Quality** in Settings
3. Clear the app cache
4. The server may be experiencing high traffic

---

**Q: Downloads are failing**

1. Ensure you have enough storage space
2. Check if storage permission is granted
3. Try downloading fewer items at once
4. Check your internet stability

---

**Q: The app is slow or laggy**

1. Clear completed downloads
2. Reduce grid columns in Settings
3. Enable **Auto Cleanup History**
4. Restart the app

---

**Q: Does the app collect my data?**

No. Kuron does not collect any personal information. All data (history, favorites, settings) is stored locally on your device only.

---

**Q: Is my browsing history shared?**

No. Your browsing history is never shared and remains only on your device.

---

**Q: How do I delete all my data?**

You can either:
- Reset individual features in Settings
- Uninstall the app (removes all data)

---

**Q: How do I update the app?**

Go to **About → Check for Updates**. You'll be notified when a new version is available on GitHub.

Current latest release: **v0.9.29+39**
https://github.com/shirokun20/nhasixapp/releases/tag/v0.9.29%2B39

---

**Q: Why isn't the app on Play Store?**

Due to content restrictions, the app is distributed via GitHub releases only.

---

**Q: How do I report a bug?**

Please open an issue on our GitHub repository with:
- Description of the problem
- Steps to reproduce
- Your device model and Android version

---

**Q: How can I contribute?**

The app is open-source! You can contribute by:
- Submitting bug reports
- Suggesting features
- Contributing code via pull requests

---

*Didn't find your answer? Visit our GitHub repository for more help.*
