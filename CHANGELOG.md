# Daylight Recipes

## 2.0.0
- New: Daylight Recipes' own profession window, in place of the game's and DaylightUI's. Your professions sit on the left (click one to open it) with your alts' below; the open profession's skill bar and five tabs across the top: Recipes, Leveling Guide, Materials, Queue and Missing.
- Recipes tab: the recipe list with a search, "Can make" and "Skill-ups" filters, categories that fold, and how many you can make of each; the picked recipe beside it with what it makes and needs, the materials you hold (bags, bank, mail, alts), its skill-up chance, costs and value, and Create, Create All or the item an enchant goes on. Stop ends a run of crafts.
- An alt's profession shows what that character knows, as of the last time they opened it.
- New: a buy list under the vendor window: every material your Leveling Guides and crafting queue still need that this character doesn't have (an alt holding some is mentioned, [Mira has 12], but not counted), a double-click to buy exactly that many (or "Buy all here"), each after an "Are you sure?" with its total cost; what this vendor doesn't sell is grayed out, [Not Available]. It folds away like the trainer's list.
- New: the same list at the Auction House, with its price and the vendor's side by side and which is cheaper; a click puts the item in the game's search box.
- New: "Recommended" beside a profession trainer: only the recipes your leveling route learns, with the skill range it uses each for, or "All Leveling Recipes Known". A click learns one, "Learn all" the lot. It folds away to a small tab like the old pane, and is not shown once the profession is at 300.
- New: the Leveling Guide (the old Plan tab): your goal (150, 225, 300 at a click) and progress, the step you're on as a card (what to make and how many, its progress, the materials with what you hold and what to buy, and Make, Queue and Show recipe buttons), then every next step numbered, with each rank to train on the way.
- New: a crafting queue. Queue a recipe from the Recipes tab or a step of the Leveling Guide; the Queue tab lists them with what they need, and "Craft next" makes the first one of the open profession. Every cast of a queued recipe takes one off it.
- What to buy is what the current character doesn't have: alts' holdings are mentioned ([Mira has 12]) but no longer subtracted.
- Enchanting for skill: an item row above the buttons holds the item your enchants go on (drag it in, or click to pick one). It is kept, so one cheap item takes enchant after enchant: the count, Enchant All, the queue and the Leveling Guide's Make set up a run of that many on it, one enchant a click (the game takes the answer to its "replace the enchant?" question only inside a click): after each, Next casts the next one. With Auto-replace on, that question is answered yes for you on each click.
- Leveling Guide, smarter route: Enchanting's rods and Engineering's tools are made when the next recipes need them (a step of their own, their materials on the buy list); recipes you'd buy from a vendor or the Auction House count, priced in; materials you can make yourself (bolts, bars) are priced at the cheaper of buying and making them, and a recipe making something the route needs counts what it saves; cooldown and holiday recipes are left out; a step keeps its recipe unless another is clearly cheaper; each step shows the two next-best recipes; a stretch no recipe covers is named and the route goes on past it.
- Leveling Guide, cheapest route by: Cheapest (materials), Vendor, Disenchant or Auction House: the last three take what you make off the cost (selling skips recipes under a 10% chance and ignores absurd prices).
- Auction House prices: how many are up is kept, and a vendor wins over an Auction House price only a little lower with fewer than 10 up. A scan over 12 hours old says so. With Auctionator loaded, the Auction House buy list becomes an Auctionator shopping list at a click.
- /recipes (or /dr) opens the window on your last profession, away from a crafting station too.
- It takes the place of DaylightMogul's profession window too (Mogul's prices are still used). Prefer DaylightUI's or Mogul's window? Options, Recipes, Profession window: "Docked pane" brings it back with the pane beside it.
- "Craft next" (the Leveling Guide's "Also good right now") lists your recipes that still give points, cheapest expected cost per point first (with the chance and how many you can make now); a click picks it in the profession window.
- New: a route to your target skill (your cap or the next rank's, or 300; click to change). For every point it takes the recipe with the cheapest expected cost per point, among the ones you know and the ones a trainer will teach by then, counting the misses on yellow and green recipes, and stops at each rank cap to tell you which rank to train. Each step shows the skill range, the recipe, about how many crafts and what they cost.
- New: the materials the route takes, less what the route makes on the way, with what's in your bags, bank (Forever's bank tabs and the account's shared ones too) and mail, what your alts on the realm hold, and what's left to buy and for how much, with who on your account can make it or which vendor sells it.
- New: Daylight Recipes no longer needs another addon. It keeps its own Auction House prices from what you browse and from a scan you start in the Leveling Guide (DaylightMogul's prices are used instead when it's loaded, and then nothing is read twice), learns vendor prices from the merchants you visit, and remembers every character's professions, recipes, bags, bank and mail.
- New: item tooltips (DaylightUI 1.7): which professions use a material and in how many recipes, what your plans (and your alts') need of it, and who on your account knows a recipe item.
- New: trainer reminders in chat when a skill-up opens new recipes at a trainer or a profession reaches its cap, and a small mark on the best recipe to skill up with in DaylightUI's recipe list. Each can be turned off on the options page.
- Fix: switching profession in DaylightMogul's window no longer keeps showing the last profession's recipe.
- Fix: the Missing tab shows the skill a trainer really asks for a recipe (it showed the orange threshold, which is off for a few hundred recipes), and no longer says "Skill 0" when the data doesn't know.
- Fix: recipes the data has no source for (many of Forever's own) are listed as "Source not known yet" instead of being left out, so the Missing tab no longer says you know every recipe when you don't.
- The skill-up chance follows the game's own color for recipes you know: orange is a sure point and gray none, with the thresholds only giving the odds on yellow and green. Recipes that give more than one point say so, and the cost per skill point counts it.
- Trainers, vendors and drops in a recipe's sources are listed nearest first (your zone, then your continent), so the six shown are the ones you can reach, and a waypoint goes to the nearest spawn.
- Lighter: the Missing tab no longer reads every recipe again on each bag change or rebuilds its list on each skill point (only learning a recipe, or opening the window, does), a recipe's sources are worked out once, and the list shows 60 recipes at a time with "Show more".
- Fix: after DaylightUI's profession window closes, a weapon skill-up no longer makes the pane forget your known recipes.

## 1.1.2
- All text in American English (gray, color and the like), in the game and in the docs.

## 1.1.1
- Lighter while a profession is open: a bag change or a craft no longer rebuilds the missing list (only learning a recipe does) or redraws the pane unless the skill changed; item data arriving redraws only a page waiting on that item; the missing list's search runs a moment after the last key instead of on every key.

## 1.1.0
- The pane folds away, like DaylightUI's damage meter: a small tab on its outer edge slides it out of sight, leaving only the tab against the profession window, and a click on the tab brings it back. It stays folded or open between sessions, on DaylightUI's profession window and DaylightMogul's.

## 1.0.0
- First release: a pane beside DaylightUI's profession window, or DaylightMogul's.
- Recipe page: skill-up chance (Overtime counted), every material priced from the Auction House (DaylightMogul) or the cheapest vendor (reputation and Bartering counted), total and cost per skill point, value on the Auction House, at a vendor and disenchanted with the profit each way, and the disenchant materials.
- Missing page: every recipe you don't know for the open profession, with its trainers, vendors, drops and quests, their places, and a waypoint on click.
- Recipe, source and disenchant data from ForeverRecipes (GPL-3.0).
