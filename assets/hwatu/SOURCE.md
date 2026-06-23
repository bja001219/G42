# Hwatu Card Image Assets — Source & License

## Source

- **Repository**: https://github.com/ALee1303/Hwatu
- **Author**: ALee1303
- **License**: MIT License
- **Download Date**: 2026-06-23
- **Commit/Branch**: master

## License Text (MIT)

The MIT License grants permission to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software and associated assets, provided the copyright notice and license notice are included in all copies or substantial portions.

Full license: https://raw.githubusercontent.com/ALee1303/Hwatu/master/LICENSE

## Files Downloaded

48 PNG card images, organized by month subdirectory under `assets/hwatu/`:

| Subdirectory | Files |
|---|---|
| January/ | Kwang.png, Tti.png, Pi1.png, Pi2.png |
| February/ | Yul.png, Tti.png, Pi1.png, Pi2.png |
| March/ | Kwang.png, Tti.png, Pi1.png, Pi2.png |
| April/ | Yul.png, Tti.png, Pi1.png, Pi2.png |
| May/ | Yul.png, Tti.png, Pi1.png, Pi2.png |
| June/ | Yul.png, Tti.png, Pi1.png, Pi2.png |
| July/ | Yul.png, Tti.png, Pi1.png, Pi2.png |
| August/ | Kwang.png, Yul.png, Pi1.png, Pi2.png |
| September/ | Yul.png, Tti.png, Pi1.png, Pi2.png |
| October/ | Yul.png, Tti.png, Pi1.png, Pi2.png |
| November/ | Kwang.png, SsangPi.png, Pi1.png, Pi2.png |
| December/ | Kwang.png, Yul.png, Tti.png, SsangPi.png |

Image dimensions: ~49-50 × 81 px, 8-bit RGB PNG.

## Card ID to File Mapping Notes

Engine card IDs 0–47 map to months via `month = id / 4 + 1` (integer division).
Within each month, the 4 cards are ordered: [광/열끗, 띠, 피1, 피2] per the go-stop engine encoding.

### File type mapping per month

| Month | id%4=0 (광/열끗) | id%4=1 (띠) | id%4=2 (피) | id%4=3 (피/쌍피) |
|---|---|---|---|---|
| 1 (Jan) | Kwang.png | Tti.png | Pi1.png | Pi2.png |
| 2 (Feb) | Yul.png | Tti.png | Pi1.png | Pi2.png |
| 3 (Mar) | Kwang.png | Tti.png | Pi1.png | Pi2.png |
| 4 (Apr) | Yul.png | Tti.png | Pi1.png | Pi2.png |
| 5 (May) | Yul.png | Tti.png | Pi1.png | Pi2.png |
| 6 (Jun) | Yul.png | Tti.png | Pi1.png | Pi2.png |
| 7 (Jul) | Yul.png | Tti.png | Pi1.png | Pi2.png |
| 8 (Aug) | Kwang.png | Yul.png | Pi1.png | Pi2.png |
| 9 (Sep) | Yul.png | Tti.png | Pi1.png | Pi2.png |
| 10 (Oct) | Yul.png | Tti.png | Pi1.png | Pi2.png |
| 11 (Nov) | Kwang.png | SsangPi.png | Pi1.png | Pi2.png |
| 12 (Dec) | Kwang.png | Yul.png | Tti.png | SsangPi.png |

**Note on Month 8 (August)**: The engine assigns id 29 as 기러기열끗 (geese junk/Yul), not a ribbon (Tti). The source repo has no Tti.png for August, which is correct — August has no ribbon card in standard hwatu.

**Note on Month 11 (November)**: Engine id 41 = 쌍피 (double chaff). Source file is SsangPi.png.

**Note on Month 12 (December)**: Unusual month — no plain Pi1/Pi2 chaff. Cards are: 비광 (rain bright/Kwang.png), 제비열끗 (swallow/Yul.png), 비띠 (rain ribbon/Tti.png), 쌍피 (double chaff/SsangPi.png).

## Missing Assets

- **Card back**: No card back image found in the source repository. The Wikimedia Commons `Hanafuda_card_back_Alt.svg` (CC-BY-SA 4.0, author: Spenĉjo) was identified but excluded because CC-BY-SA's share-alike clause does not meet the project's license requirements (MIT/CC0/Public Domain/CC-BY only).
- **Bonus cards (ids 48, 49, 50)**: Joker/bonus cards are not present in this set. These are not standard hwatu cards and are absent from the source repository.

## Repos Investigated But Not Used

| Repo | Reason Not Used |
|---|---|
| https://github.com/solarsailer/hanafuda | Repository not found (404) |
| https://github.com/p1ho/go-stop-game | Repository not found (404) |
| https://github.com/axetroy/react-go-stop | Repository not found (404) |
| https://github.com/nojhan/hanafuda | SVG source, no license file found; archived March 2026 |
| https://github.com/C-W-Z/hanafuda | GPL-3.0 license; images sourced from Wikimedia CC-BY-SA |
| https://github.com/nightsky30/koikoi | GPL-2.0 license |
| Wikimedia Commons SVG Hwatu (48 files) | CC-BY-SA 4.0 — share-alike restriction excludes it |
