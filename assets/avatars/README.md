# Reader tier avatars

No bundled PNGs — tiers render from the dedicated **Kuro tier painter**
(`lib/presentation/widgets/kuro_tier_avatar.dart`): same black-cat base,
one accessory each. Deliberately separate from `KuroMascot` moods —
avatars are 40-52px identity marks, drawn bold, static (no tickers).

- `santai` → plain, calm
- `kutubuku` → round glasses
- `otaku` → headphone band + pads
- `resi` → dusty hood ring
- `shaker` → sweat drop + worried mouth

Pastel disc behind the cat (`ReaderAvatar.backgroundFor`):
`santai` ffdfbf, `kutubuku` c0aede, `otaku` b6e3f4,
`resi` ffd5dc, `shaker` d1d4f9.

Old DiceBear Open Peeps PNGs (CC0) were deleted 2026-10-04 —
git history has them if ever needed.
