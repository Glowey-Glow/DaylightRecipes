# Glowey's Recipes (DaylightUI Plugin)

**A profession window that levels you up:** your recipes, a step-by-step Leveling Guide, a crafting queue, and what to buy or learn at the vendor, the Auction House and the trainer, all in the Daylight UI look.

A plugin for Daylight UI, by Glowey (not part of Daylight UI itself: report its bugs here, not to Daylight UI). Requires **Daylight UI**. Works on its own: it keeps its own Auction House prices, and uses **DaylightMogul**'s when Mogul is loaded. With it installed you can turn ForeverRecipes off.

---

## New in 3.0.7
- **Upgrade arrows on recipes:** with Glowey's Gear 1.0.6 or later installed, every recipe whose crafted item would be a gear upgrade for your character gets the green upgrade arrow in the recipe list.
---

## The window
Open any profession and Glowey's Recipes' window takes the place of the game's (and Daylight UI's or Mogul's): one compact column at the left of the screen, out of the way of your character. It opens the way you left it.
- **Compact, with details on demand:** the picked recipe's chance, cost and sale value are one line above the craft bar. The **Details** button (or a press on that line) slides its full page out beside the list. Drag the bottom edge to make the window taller.
- **Roll Up** folds the window to its header and one bar while you craft. The bar says what it acts on: what is being made (with Stop), else the next craft in your queue (with **Craft Next**), else the picked recipe.
- **Your professions across the title bar:** a chip for each, by its abbreviation, the open one lit with its skill; press another to open it. Herbalism, Skinning and Fishing open their own page (skill, rank, where to train next), and a **Camping** chip lists every profession's camping items. A right-click on a chip has **Link to Chat** and **Unlearn** (Unlearn asks first); the three dots at the end have your alts' professions (see what each alt knows), your craft cooldowns and your tracking spells.
- **Swap button** beside the X: switch to the game's profession window and back any time.
- **Recipes:** search, "Can Make" and "Skill-ups" filters, folding categories and how many you can make. The picked recipe shows its skill-up chance, what its materials cost and what you hold of them (bags, bank, mail, alts), what it's worth, and Create, Max and Queue (Max fills in all you can make).
- **Leveling Guide:** pick your goal (150, 225, 300) and what the route aims for (cheapest materials, or after vendoring, disenchanting or selling what you make). Every step uses a recipe that is orange or yellow at that skill, whatever the goal; for recipes you know, the game's own color decides. The step you're on comes as a card: what to make and how many, its materials, and Make / Queue / Show Recipe, with other recipes that give points under Or Instead. Then every next step, numbered, with when to train each rank, and the rods and tools you'll need made along the way. The step you're on glows, and so does its recipe in the list.
- **Materials:** everything the route needs, what you hold, and what's left to buy.
- **Queue:** queue recipes from anywhere, then "Craft Next".
- **Missing:** every recipe you don't know yet, where to get it (checked against QuestieDB), nearest first, with waypoints, including reputation recipes ("Nightclaw Druids: Friendly (Current Rep: Neutral)", in the game's reputation colors).
- `/recipes` opens it on your last profession, even away from a crafting station.

## Where you shop and train
A thin strip docks flush to the window you are at, and only where there is something for you: at a vendor that sells nothing you need, nothing shows.
- **Vendor:** how many of the items you need this vendor sells and what they cost. **List** opens the list: press a line to buy that item at once, exactly the number you need. **Buy All Needed** asks first, with the total, and buys what your gold, the vendor's stock and your bags allow.
- **Auction House:** a compact strip at the window's bottom right corner with what is still to buy there. **Check Prices** reads how many are for sale at each price, so a line shows what the number you need really costs. Press a line to search for it. One click makes an Auctionator shopping list when Auctionator is installed.
- **Trainer:** only the recipes your Leveling Guide recommends that you can learn here now, their cost, and **Learn All Recommended**.
- **Each place lists what is cheapest there:** the vendor's strip leaves out what the Auction House sells for less, and the other way round, with a line saying how many and why. **Queue List** and **Guide List** keep the crafting queue's needs and the Leveling Guide's apart, profession tags narrow a list to one profession, and Shift-click removes a line.
- The lists count what this character has in bags, bank and mail, and what you just bought at the Auction House; an alt's stock is a note.

## Enchanting
Drag a cheap item into the slot and level on it: enchant after enchant, with the game's "replace the enchant?" answered for you (Auto-replace, a switch).

## Around the game
- **Item tooltips:** what uses a material, what your guides need of it, and for a recipe who on your account knows it and who could learn it, in class colors, with the skill still needed.
- **Recipes marked at vendors:** a small square on any recipe a vendor sells that you or an alt on this server can learn, bright when you can learn it now.
- **Trainer reminders** in chat when a skill-up opens new recipes or you reach your rank's cap, and an update alert when a newer version is out.
- **Controller support:** the whole window, the strips and the tours work with a controller.
- **Docked Pane:** prefer Daylight UI's or Mogul's own profession window? The same recipe, guide and Missing pages sit in a pane beside it, with the enchanting slot too. Beside Daylight UI 2.1.2's window, which shows cost and profit itself, the pane leaves those to it.

## Professionally Lost
With Professionally Lost installed, a window asks once which of the two addons does each job: Leveling Guide, Buy Lists, Trainer Panel, the guide line in item tooltips, scanned prices, and lighting its step in your recipe list. Nothing changes until you press Apply, nothing of Professionally Lost's is ever changed, and **Put Everything Back** in the settings undoes it at once. Glowey's Recipes works fully without it.

---

## In your language
Glowey's Recipes speaks German, French, Spanish, Russian, Korean and Simplified Chinese (machine drafts, corrections welcome; words the game already translates use the game's own wording), and shows recipe, item, profession, zone and quest names in your game's language.

---

## Settings
Daylight UI options > **Plugins > Recipes**. Help there has the tours, What's New, and **Revert to** the profession window you had. Window opacity follows Daylight UI's, or set your own there.

---

*Glowey's Recipes is free software under the GNU General Public License v3. Recipe and source data from ForeverRecipes (GPL-3.0); more recipe sources, reputation and camping data from Polestar (GPL-3.0); source corrections and additions from QuestieDB (under the Questie team's GPLv3 terms).*
