# Daylight Recipes

A plugin for Daylight UI on WoW: Forever. It adds a pane beside your profession window showing what a recipe costs to make, what it's worth, how likely it is to give a skill point, and every recipe you don't know yet with where to get it.

## Requirements

- Daylight UI.
- Optional: DaylightMogul, for Auction House prices. Without it, costs use vendor prices.

With this plugin installed you can turn ForeverRecipes off.

## Installing

Install it from CurseForge (or WowUp), or unzip it into `World of Warcraft\_forever_\Interface\AddOns`. Make sure it's ticked in the AddOns list on the character screen, then log in or `/reload`.

## How to use it

Open a profession. The pane appears on the right of Daylight UI's profession window (or DaylightMogul's, while Mogul runs your professions).

- **Pick a recipe** to see its skill-up chance, the cost of its materials, what it's worth on the Auction House, at a vendor or disenchanted, and what it disenchants into.
- **Missing recipes:** open this tab for every recipe of the profession you don't know yet, sorted by the skill it needs. Search by name at the top. Click a recipe for where to get it (trainers, vendors, drops, quests), and click a place for a waypoint (TomTom when it's installed).
- **Fold it away:** click the tab on the pane's outer edge to slide the pane away, and again to bring it back. The pane remembers how you left it.

## Settings

Open the Daylight UI options and go to **Plugins → Recipes**.

## Updates

What's new in each version is in [CHANGELOG.md](CHANGELOG.md).

## License

Copyright (c) 2026 Glowey. Free software under the GNU General Public License, version 3 or later; see [LICENSE](LICENSE.md). The recipe, source and disenchant data come from [ForeverRecipes](https://www.curseforge.com/wow/addons/foreverrecipes) by Ismail (GPL-3.0), built from [ForeverDB.app](https://foreverdb.app/) and CMaNGOS Classic DB, and are included unchanged. Where those have no source for a recipe (many of Forever's own, the reputation ones), and for every profession's camping items, the facts come from [Polestar](https://github.com/fitzforge/polestar) by the Polestar authors (GPL-3.0), generated into `Data/Polestar.lua` by `Tools/polestar.py`. Both are checked against [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team, used under the GPLv3 terms the Questie team offers (with their caveat that not every historic contributor may agree; see [LICENSE](LICENSE.md)): `Tools/questie.py` writes what it corrects and adds into `Data/Corrections.lua`. Disenchant yields are the Classic ones, not yet confirmed for WoW: Forever.
