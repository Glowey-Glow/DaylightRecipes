# Daylight Recipes

## 2.2.0
- Everyone, including players who had Daylight Recipes before, sees the welcome and the tours once with this version.
- Keep My Window on the welcome leaves a window you already picked (the game's or the docked pane) as it is.
- New: a welcome on first launch that lists what Daylight Recipes takes over (your profession window, the panels at vendors, the auction house and trainers, recipe tooltips). Start Tour uses Recipes' window and starts the tour; Keep My Window keeps the one you had.
- New: tours, each shown once the first time you get there: the window (professions, tabs, recipe list, crafting, the swap button), the Leveling Guide, Missing and Queue tabs, the buy lists and trainer panel, and enchanting runs. Back, Next and Skip tour; Escape skips; a fight ends it.
- New: after an update, a short note with what changed.
- New Help card in the options: Retake Tour, What's new, and Revert to DaylightUI's Window (or DaylightMogul's, or the game's: whichever you had).
- Mastercraft's gathering node tooltips now read "Turns gray in 30 more skill", the color in its own color, instead of "Turns grey at +30 skill" (and "Gatherable in 5 more skill").
- New: tells you when a newer version is out. Your copy and those of players in your guild and group trade version numbers in the background, and one chat line says when there is a newer one to get through CurseForge or WowUp (once a session). Turn it off with "Tell me when a newer version is out" on the plugin's first options page; then nothing is sent either.
- Fix: you can link your profession to chat again. With the chat box open, Shift-click the profession's icon at the top of the window, or the profession in the list on the left (one that isn't open opens first, then goes into chat). Both tooltips say so.
- Fix: Shift-clicking a recipe, item or reagent into chat no longer relies on the game's old chat function, which is only there while its backward-compatibility addon is loaded.
- Recipes marked at vendors: a small square in your accent on any recipe a vendor sells that you or an alt on this realm and faction can learn and doesn't know yet. Bright when this character can learn it now, faint when it's for later (more skill needed) or for an alt. On DaylightUI's vendor page and the game's own vendor window (DaylightMogul's vendor window has no way in, so none there; the tooltip still says who it's for). Switch: "Mark recipes at vendors".
- Recipe item tooltips: "Known by" in class colors, and a new "Can learn" line with your characters who have the profession but not the recipe, and the skill it needs when theirs is short. Shown when any of your characters on this realm and faction has the profession, not only this one.
- Mastercraft: its own list of your characters on recipe items is switched off while ours shows, so it isn't said twice (asked once; "Hide Mastercraft's recipe lines" in the options gives it back).
- Translations: the new text in German, French, Spanish, Russian, Korean and Simplified Chinese.

## 2.1.0
- Leveling Guide: a light runs round the step you're on, and round its recipe in the recipe list wherever you scroll, so it's easy to find. It uses the glow style you picked for DaylightUI's main buttons (none when that's set to None or DaylightUI's motion is off). Turn it off with "Light up the guide's step" (Help around the game). Needs DaylightUI 1.8.4 or later.
- Swap button: on a window where DaylightUI 1.8.4 puts its own swap icon or "Daylight UI window" link, its tooltip says which window it opens and what DaylightUI's control beside it does.
- Translations: the new text in German, French, Spanish, Russian, Korean and Simplified Chinese.

## 2.0.7
- DaylightUI 1.8.4: the swap button no longer sits on top of DaylightUI's new swap icon in its profession window's header, or its "Daylight UI window" link on the game's profession window. It goes just left of them.

## 2.0.6
- Translations tidied: lines for text the plugin no longer shows are taken out of all six languages.

## 2.0.5
- Translations: this week's new text (camping, gathering pages, unlearn, the swap button and the first-load question, reputation lines) in German, French, Spanish, Russian, Korean and Simplified Chinese.
- Every recipe's sources are checked against QuestieDB (the Questie team's database, used under the GPLv3 terms they offer), and the Missing tab is corrected where ours were wrong or short.
- The Missing tab knows where far more recipes come from: of the 276 still listed as "Source not known yet", 201 now show their drops, vendors or quests. Forever's own patterns, plans and formulas are among them (the Sterling Silver and Shining Mithril plans, the Scorpid and Earthen patterns, the class armor sets), as are the classic ones whose only known source was QuestieDB (the Imperial Plate plans, a quest reward each).
- More places for the recipes that already had some: 2,089 more drops across 266 recipes, the lockboxes and junkboxes 142 recipes are found in, 75 more vendors (the Magram Clan Quartermaster's Forever formulas and plans, more vendors for the Sagefish recipes and reagent bags; never the bots engineers summon) and 8 more quest rewards.
- 230 NPCs a recipe names now have a spot on the map and a waypoint (Riverpaw Mongrel in Westfall, for one), and 333 that the data didn't know at all are added with theirs.
- Fix: drops from the other faction's NPCs (the Horde Runners an Alliance player fights, Stromgarde's men for the Horde) are listed for the faction that can fight them, not for their own.
- Fix: eight trainers and vendors listed for both factions are your faction's only (Angus Hammerhand and William Pickman for the Horde, Iaadaria Bitterwind and Granny Finespindle for the Alliance, among them), so the skill a recipe can be learned at no longer counts the other faction's trainer.
- Fix: wrong places taken away or moved: Teremus the Devourer is in the Blasted Lands only (not Stormwind), Stitches in Duskwood only, the Alliance Outrunners in the southern Barrens, and ten more NPCs.
- Fix: Formula: Enchant Chest - Minor Mana no longer lists Vance Undergloom in Brill, who teaches Enchanting but doesn't sell it.

## 2.0.4
- Its own icon: in the game's AddOns list and other menus (instead of the blank "?"), and on its page in DaylightUI's options.

## 2.0.3
- A swap button (two arrows) beside the X: on Daylight Recipes' window it switches to the game's own profession window, and on the game's window it switches back. The open profession moves across at once, and the window you pick stays picked. Not in a fight.
- New "Use Daylight Recipes' profession window?" question, asked once. Yes makes Daylight Recipes' window the one and switches DaylightUI's own profession window off (one reload, offered), so the swap button goes to the game's window. Picking Docked pane in the options brings DaylightUI's window back as it was. The Profession window choice now also has The game's window.
- Reputation recipes read "Nightclaw Druids: Friendly (Current Rep: Neutral)", each standing in the game's reputation colors (red for Hated and Hostile, orange for Unfriendly, yellow for Neutral, green from Friendly up).
- Herbalism, Skinning and Fishing are no longer grayed out on the left of the window: a click shows their own page, with your skill, your rank and when to train the next one (they have no recipes, so no recipe list or Leveling Guide).
- Mining is found under its own name too, so its smelting recipes and Leveling Guide open from the left; if the game won't open a profession from there, its page says which spell to cast instead.
- Text wraps instead of being cut off: long recipe, item and place names, prices and notes in the window, the pane and the buy and trainer lists take a second line, and a page drawn at one width is drawn again when its panel gets wider or narrower.
- Buttons fit their words in every language (Create All, Queue, Buy all here, Learn all...): when the crafting bar runs out of room, the count and Queue move to a row of their own above Create.
- The enchant item row, the pane's skill beside its tabs, and the buy list's total beside its button no longer run into each other.
- At a large Window size on a small screen, the window shrinks to fit instead of running off the screen.
- With DaylightUI 1.8.3: Create, Buy all here, Learn all and the Yes of the confirm box have DaylightUI's main-button look; a buy list's item tooltip no longer repeats your bags and bank when DaylightUI already lists every character's (the mail count stays).
- New: camping items. Herbalism, Skinning and Fishing's pages list theirs (Fishing's Fish Bowl, Fishing Rack and Fishing Hut, for one): what each does, what it takes and what you hold of it, the skill it needs, whether you know it, and how to learn it (a trainer or the quest "Camping 101", or a blueprint with where it drops and a waypoint). A new "Camping" entry on the left lists every profession's camping items, yours first.
- Fishing's page says where its next rank comes from: Expert is a book sold in Booty Bay, Artisan a quest from Nat Pagle in Dustwallow Marsh (with a waypoint to each), not a trainer.
- The Missing tab knows where far more recipes come from: of the 469 listed as "Source not known yet", 193 now show their vendors, drops, quests or reputation, from Polestar's data (GPL-3.0), Forever's own ones among them (the Gustwoven and Windraveled patterns: the Nightclaw Druids' vendor).
- Recipes that ask for a reputation say which and how much, with your standing beside it (green once you have it): "Nightclaw Druids: Friendly (you: Neutral)". For a recipe no data knows, the recipe item's own tooltip is read for it.
- Right-click one of your two primary professions on the left to unlearn it (as in the game's professions book), after an "Are you sure?" that names it and warns that its skill and recipes are lost. Its saved skill, recipes, Leveling Guide and queued recipes are forgotten with it.
- Fix: a skill-up while you gather (Herbalism 70 to 75) shows on the window's list of professions and the gathering page at once, with no profession window open.
- Fix: the window fits the screen again when the UI scale or the game's window size changes.
- Lighter: a page drawn again after its panel changed width redraws only that window (not the pane, the window and the buy lists together), and never the folded pane.
- The buy list's item tooltip keeps "You have..." unless DaylightUI (1.8.3 or later, its bags and its bank and alts viewer on) lists your characters' bags and bank there itself; the mail stays said.

## 2.0.2
- On German, French, Spanish, Russian, Korean and Chinese clients, words the game already translates (like Apprentice, Journeyman, Search, Yes and No) use the game's own translation instead of our draft.
- Item tooltips no longer show your alts' guide lines: only this character's own guides, for the professions it has learned.

## 2.0.1
- Item tooltips only speak of the professions this character has learned: "Used in", "Known by" and your own guides' lines (your alts' guide lines stay).
- Daylight Recipes speaks German, French, Spanish, Russian, Korean and Simplified Chinese (machine drafts, corrections welcome).
- Fixes for non-English game clients: the Leveling Guide makes Enchanting's rods and Engineering's tools again when the next recipes need them (the game names them in your language, and the guide only knew the English names); the trainer's "Recommended" list finds the recipes a trainer teaches by their name in your language too.
- Recipe, item, profession, zone and quest names are shown in your game's language wherever the game has them (the Missing tab, an alt's recipes, trainer reminders, item tooltips, the buy lists), with the English name only while the game hasn't loaded one yet.
- Searches find accented and Cyrillic letters whatever their case ("ä" finds "Ä", "б" finds "Б"), and lists sorted by name follow your language's alphabet.
- Window opacity: follows DaylightUI's by default, or set your own on the options page.

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
