# Glowey's Recipes

A plugin for Daylight UI on WoW: Forever. It gives you a compact profession window of its own: your recipes with what each costs to make, what it's worth and how likely it is to give a skill point, a step-by-step Leveling Guide, a crafting queue, and every recipe you don't know yet with where to get it. At vendors, trainers and the Auction House a thin strip shows what to buy or learn.

## Requirements

- Daylight UI.
- Optional: DaylightMogul, for its Auction House prices. Without it, Glowey's Recipes keeps its own from what you browse or scan, and uses vendor prices where it has none.
- Optional: Professionally Lost. With it installed, a window asks once which of the two addons does each job (see below).

With this plugin installed you can turn ForeverRecipes off.

## Installing

Install it from CurseForge (or WowUp), or unzip it into `World of Warcraft\_forever_\Interface\AddOns`. Make sure it's ticked in the AddOns list on the character screen, then log in or `/reload`.

## How to use it

Open a profession, or type `/recipes`. Glowey's Recipes' window opens in place of the game's: one column at the left of the screen, the way you left it.

- **Pick a recipe** to see its skill-up chance, the cost of its materials and what it sells for in one line above the craft bar. Press that line or the Details button for its full page beside the list: what you hold of each material, what it's worth on the Auction House, at a vendor or disenchanted, and what it disenchants into.
- **Craft:** set how many (Max fills in all you can make), then Create, or add it to the queue. Roll Up folds the window to its header and one bar while you craft; the bar says what it will make: the next craft in your queue, with Craft Next, or the picked recipe.
- **Your professions:** press the profession's name for a menu with your professions, Camping, your alts, your craft cooldowns and tracking. Each profession's More button has Link to Chat and Unlearn.
- **Leveling Guide, Materials, Queue:** the cheapest way to your next goal step by step (every step on a recipe that still gives skill points), everything it needs, and what you plan to craft.
- **Missing recipes:** open this tab for every recipe of the profession you don't know yet, sorted by the skill it needs. Search by name at the top. Click a recipe for where to get it (trainers, vendors, drops, quests), and click a place for a waypoint (TomTom when it's installed).
- **Vendors, trainers and the Auction House:** a thin strip under their window, only where there is something for you. List shows the items; a press on one buys or learns it. Buy All Needed asks first, with the total. At the Auction House the strip sits at the window's bottom right corner, a press on a line searches for the item, and Check Prices reads what the number you need really costs.
- **The lists:** Queue List and Guide List keep the crafting queue's needs and the Leveling Guide's apart; profession tags narrow a list to one profession; each place lists only what is cheapest there and says what it left out; Shift-click removes a line, and the list's last line puts removed items back.
- **Tours:** nothing starts by itself. Plugins → Recipes → Help has Retake Tour, Shop Strip Tour and Enchanting Runs Tour.
- **With Professionally Lost installed:** a window asks once which addon does each job (Leveling Guide, Buy Lists, Trainer Panel, the guide line in item tooltips, scanned prices, lighting its step). Nothing changes until you press Apply, nothing of Professionally Lost's is changed, and Put Everything Back in the settings undoes it.
- **Prefer Daylight UI's or DaylightMogul's own profession window?** Pick Docked Pane in the settings: the same recipe and Missing pages in a pane on its right, with a tab at the pane's top corner to fold it away.

## Settings

Open the Daylight UI options and go to **Plugins → Recipes**.

## Updates

What's new in each version is in [CHANGELOG.md](CHANGELOG.md).

## License

Copyright (c) 2026 Glowey. Free software under the GNU General Public License, version 3 or later; see [LICENSE](LICENSE.md). The recipe, source and disenchant data come from [ForeverRecipes](https://www.curseforge.com/wow/addons/foreverrecipes) by Ismail (GPL-3.0), built from [ForeverDB.app](https://foreverdb.app/) and CMaNGOS Classic DB, and are included unchanged. Where those have no source for a recipe (many of Forever's own, the reputation ones), and for every profession's camping items, the facts come from [Polestar](https://github.com/fitzforge/polestar) by the Polestar authors (GPL-3.0), generated into `Data/Polestar.lua` by `Tools/polestar.py`. Both are checked against [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team, used under the GPLv3 terms the Questie team offers (with their caveat that not every historic contributor may agree; see [LICENSE](LICENSE.md)): `Tools/questie.py` writes what it corrects and adds into `Data/Corrections.lua`. Disenchant yields are the Classic ones, not yet confirmed for WoW: Forever.
