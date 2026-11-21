# Glowey's Recipes (DaylightUI Plugin)

**A profession window that levels you up:** your recipes, a step-by-step Leveling Guide, a crafting queue, and buy lists at the vendor, the Auction House and the trainer, all in the Daylight UI look.

A plugin for Daylight UI, by Glowey (not part of Daylight UI itself: report its bugs here, not to Daylight UI). Requires **Daylight UI**. Works on its own: it keeps its own Auction House prices, and uses **DaylightMogul**'s when Mogul is loaded. With it installed you can turn ForeverRecipes off.

---

## New in 2.8.0
- **Leveling Guide you can trust:** every step uses a recipe that is orange or yellow at that skill, for all four goals (Cheapest, Vendor, Disenchant, Auction House). No more "make 100" of something that barely gives points. For recipes you know, the game's own color decides.
- **424 recipes added:** everything whose gray skill lies past 300 was missing, Runecloth Bandage among them. The guide now reaches 300 on recipes that give points in every crafting profession.
- **Your prices are back:** the game stopped giving realm names on Nov 20, which hid saved prices and your other characters' holdings. They are found again and kept by the server's rules from now on. Nothing was lost.
- **Daylight UI 2.1.2:** its profession window now shows cost and profit, so the Docked Pane can leave those to it (asked once, switch it back in the options). Buy List searches find items in every category.

---

## The window
Open any profession and Glowey's Recipes' window takes the place of the game's (and Daylight UI's or Mogul's).
- **Your professions on the left** (click one to open it), with your alts' below: see what each alt knows. Herbalism, Skinning and Fishing open their own page (skill, rank, where to train next) and a **Camping** entry lists every profession's camping items. Right-click a main profession to **unlearn** it.
- **Swap button** beside the X: switch to the game's profession window and back any time. It sits beside Daylight UI 1.8.4's own swap icon and link, never on top of them.
- **Recipes:** search, "Can Make" and "Skill-ups" filters, folding categories and how many you can make. The picked recipe shows its skill-up chance, what its materials cost and what you hold of them (bags, bank, mail, alts), what it's worth, and Create / Create All / Queue.
- **Leveling Guide:** pick your goal (150, 225, 300) and what the route aims for (cheapest materials, or after vendoring, disenchanting or selling what you make). The step you're on comes as a card: what to make and how many, its materials, and Make / Queue / Show Recipe. Then every next step, numbered, with when to train each rank, and the rods and tools you'll need made along the way. **New in 2.1.0:** the step you're on glows, and so does its recipe in the list, in Daylight UI's glow style.
- **Materials:** everything the route needs, what you hold, and what's left to buy.
- **Queue:** queue recipes from anywhere, then "Craft Next".
- **Missing:** every recipe you don't know yet, where to get it (checked against QuestieDB), nearest first, with waypoints, including reputation recipes ("Nightclaw Druids: Friendly (Current Rep: Neutral)", in the game's reputation colors).
- `/recipes` opens it on your last profession, even away from a crafting station.

## Where you shop and train
- **Vendor:** your buy list under the vendor's window. Double-click to buy exactly what you need; what the vendor doesn't sell is grayed out.
- **Auction House:** the same list with the Auction House and vendor prices side by side, and which is cheaper. One click makes an Auctionator shopping list when Auctionator is installed.
- **Trainer:** "Recommended" beside the trainer: only the recipes your Leveling Guide needs, and your next rank.
- Each one folds away to a small tab.

## Enchanting
Drag a cheap item into the slot and level on it: enchant after enchant, with the game's "replace the enchant?" answered for you (Auto-replace, a switch).

## Around the game
Item tooltips (what uses a material, what your guides need of it, and for a recipe who on your account knows it and who could learn it, in class colors, with the skill still needed; only this character's guides), and trainer reminders in chat when a skill-up opens new recipes or you reach your rank's cap.

---

## In your language
Glowey's Recipes speaks German, French, Spanish, Russian, Korean and Simplified Chinese (machine drafts, corrections welcome; words the game already translates use the game's own wording), and shows recipe, item, profession, zone and quest names in your game's language.

---

## Settings
Daylight UI options > **Plugins > Recipes**. Prefer Daylight UI's or Mogul's own profession window? Pick **Docked Pane** there for the old pane beside it. Window opacity follows Daylight UI's, or set your own there.

---

*Glowey's Recipes is free software under the GNU General Public License v3. Recipe and source data from ForeverRecipes (GPL-3.0); more recipe sources, reputation and camping data from Polestar (GPL-3.0); source corrections and additions from QuestieDB (under the Questie team's GPLv3 terms).*
