# The report: PC-HEALTH-REPORT.md

**Tone:** plain English, short sentences, an everyday analogy where it helps, no jargon without a one-line explanation. Match the user's spelling (British or American). Lead with the answer. For a healthy PC keep it to about two pages; the detail lives in `diagnostic.json`.

**Honesty:** report what was checked and what was not. If a finding turned out to be wrong when you looked closer, say so. Never claim a fix worked until it has been verified.

```
# <Name>'s PC health check, <date>

**Verdict:** <one or two lines: in good shape or needs work, and the single most important thing.>

**Top three wins for you:**
1. <the biggest, tied to what they told you they play and what bugs them>
2. ...
3. ...

**The machine:** <CPU>, <graphics card>, <motherboard> on BIOS <version> (<date>), <RAM: size, speed now vs rated>, <drives with free space>, <monitor(s) with resolution and refresh>, <Windows version>.
**You told me:** <games, what matters most, what's bugging them, how hands-on>.

## 1. Already right
<Short bullets, so they know what is fine and needs no attention.>

## 2. Safe fixes I can make now (reversible, with your yes)
| # | Fix | Why it helps you | How to undo |
|---|---|---|---|
| 1 | ... | ... | ... |

## 3. Needs you (BIOS, cables, hardware), in this order
1. <Job>: <one line on why>. Card: <file name in this folder>.
2. ...

## 4. Your call (trade-offs and your own files)
- <security trade-offs with the honest cost and my recommendation>
- <uninstall candidates>
- <space: recordings, old games, duplicates, with sizes and dates>

## 5. Checked and fine / could not check
<Brief: what the scan covered without issues, and anything it could not read and why.>

## 6. Sources
<Links: BIOS page, driver pages, RAM specification, anything else relied on.>

## Changes log
| When | What changed | Undo | Checked afterwards |
|---|---|---|---|
```
