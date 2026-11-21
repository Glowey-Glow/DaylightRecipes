# Glowey's Recipes (DaylightUI Plugin)

## 3.0.3

- Leveling Guide: a step whose recipe you haven't learned now says so first, in its own row ("Learn ... First", with the price), before it asks you to make anything; the crafting row under it reads "Then Make ...". Before, the card opened with "Make 12 x ..." and the learning was a small line further down.
- Leveling Guide: that step names the nearest trainer who teaches the recipe (or the nearest vendor who sells it), with the zone and coordinates. A click sets a waypoint. In the list of later steps, a click on a recipe you still have to learn sets the same waypoint.
- Leveling Guide: the step for your next rank (Journeyman, Expert, Artisan) says how it is learned and where, for every profession, looked up for this game version as it was for Fishing:
  - Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Mining and Tailoring: the nearest trainer who teaches that rank, with the price. Not every trainer does: in Orgrimmar, Magar trains Journeyman Tailoring, and Expert is Josef Gregorian's in Undercity.
  - Cooking and First Aid: Journeyman from any trainer; Expert from a book (the Expert Cookbook, Expert First Aid - Under Wraps), with your faction's vendor; Artisan from a quest (Clamlette Surprise in Gadgetzan, with the eggs, clam meat and cheese it asks for and how many you hold; Triage at your faction's doctor).
- Leveling Guide: a rank can be learned before your cap (Journeyman from skill 50, Expert from 125, Artisan from 200). Once you are there, and of the level it asks, the guide says "You can already learn Expert" with where to go, instead of waiting until the cap stops you.
- Cooking, First Aid and Mining ranks ask for no character level; the guide no longer says they do.
- Where the trainer lists come from: ForeverDB's own lists where it has them, and the Forever trainer guides for the rest (every Artisan trainer, most Alliance ones). A few new trainers whose records could not be found (Dalaran, Shen'dralas) are left out.
- "Nearest" is your zone first (by distance), then your continent, then elsewhere.
- Buy List: the Guide List now holds the recipes the Leveling Guide has you buy, from a vendor or the Auction House, one of each beside the materials. At that vendor a press buys it; at the Auction House a press searches for it. A recipe already in your bags is not listed.

## 3.0.2

- Your professions are across the window's title bar: a small chip for each, by its abbreviation (Cook, FA, LW, Fish, Skin), and one for Camping. One press opens another profession; there is no menu to open first. The open one is lit in your accent color and shows its skill ("Cook 153 / 225"); point at any chip for its full name and skill. Rolled up, the window has the same chips.
- A right-click on a chip (Y on a controller) has Link to Chat and Unlearn, and nowhere else offers them. Unlearn asks first, in a box that names the profession and the skill you would lose. The three dots at the end of the row open Your Alts and the Cooldowns and Tracking tiles; with none of those there are no three dots. A green dot on them says a cooldown is ready.
- With more professions than fit, the last ones go behind a "+2" chip that opens them as a list. No chip is ever cut off, and the open profession always stays in the row.
- A profession the game adds that has no abbreviation yet shows as its icon.
- On an alt's recipes and on someone's linked recipes the title bar still spells the name out ("Mira's Alchemy"), and a press on it lists your professions.
- The abbreviations are in every language the plugin speaks, each with its own.
- Controller: every chip is a stop; A opens it, Y has Link to Chat and Unlearn. LB and RB step the tabs, as before.
- Fixed: the professions menu is a solid box. The window's tabs and page no longer show through it, whatever Window Opacity is set to.
- The list a shopping strip drops (at a vendor, a trainer and the Auction House) is solid too, so the game's window, the chat or the world behind it no longer shows through its rows. So is the Professionally Lost question. The window itself, the docked pane and a strip's bar still follow Window Opacity.

## 3.0.1

- Fixed: Cooking and First Aid open from the professions menu. A press on one of your professions there now opens it the way the game's own profession tabs do, by its spell, so every profession with recipes opens from the menu. A Shift-click still links it to chat, and a right-click or its More button still opens Link to Chat and Unlearn. With a controller, A on a profession does the same. In combat the menu asks the game the way it did before.
- The menu closes by itself when a profession opens.
- Camping, Cooldowns and Tracking are in the same menu (press the profession's name in the header): Camping under your professions, the Cooldowns and Tracking tiles at its foot. A Cooldowns tile shows for each recipe you know that has a cooldown (transmutes, Mooncloth, Cured Rugged Hide and any other the game reports one for), ready or not; with none, there is no Cooldowns row.

## 3.0.0

### Window
- The Recipes window is one compact column now, 420 x 560 by default at the left of the screen (it was 1000 x 640 across the middle). Drag its bottom edge to make it 400 to 720 tall, or set Window Height in the options. Drag it by its header; right-click the header to put it back. In a language with longer words the column is a little wider (520 at most), so no tab is cut and the craft bar stays on one row.
- Three states, and it opens the way you left it (on the tab and in the place you left it too). Compact: the list, with the picked recipe's chance, cost and sale value in one line above the craft bar. With details: the Details button, a press on that line, or Y on a controller slides the recipe's full page out beside the list; open or closed is remembered for each tab. Rolled up: Roll Up folds the window to its header and one bar while you craft.
- Rolled up, the bar says what it acts on. While something is being made: what, how far, and Stop. With something queued for the open profession: "Queue: Silk Headband x 3 · and 1 more" and one button, Craft Next, which makes it exactly as the Queue tab's Craft Next does; short of materials for it, the bar says so and a press on the line opens the Queue tab. Otherwise: the picked recipe's name above Queue, the count, Max and Create.
- Your professions, Camping, your alts, Cooldowns and Tracking are in a menu on the profession's name. Link to Chat and Unlearn are on each profession's More button there (a right-click, or Y on a controller). With more alts than fit, the menu scrolls.
- Create All is now Max beside the count: Max fills in all you can make, Create makes them. While something is being made, the craft bar with Stop shows on every tab.
- Someone's linked profession always says whose recipes they are, after the profession's name.
- Docked Pane (for those who keep Daylight UI's or DaylightMogul's own profession window): its fold tab sits at the pane's top corner, and on DaylightMogul's window the pane sits flush against the window's edge.
- If you had the old window, it starts once at the new compact size.

### Shopping strips
- The Buy List and Recommended panels are gone. In their place a thin strip docks flush to the window you are at (Daylight UI's, DaylightMogul's or the game's), and only where there is something for you: at a vendor that sells nothing you need, nothing of Glowey's Recipes shows.
- Vendor: under the vendor window, as wide as it: how many of the items you need this vendor sells, what they cost, List, and Buy All Needed. Buy All Needed asks once, with the total (the option Ask Before Buying All switches the question off), and buys what your gold, the vendor's stock and your bag space allow; short of gold it reads Buy What I Can Afford. Anything left out is named in chat with the reason.
- Trainer: under the trainer window: how many of your Leveling Guide's recipes you can learn here now, their cost, and Learn All Recommended.
- Auction House: a compact strip at the window's bottom right corner: how many items are still to buy, what they cost there, List, and Check Prices (with Auctionator on the game's own window, Auctionator List too). Buying on the Auction House stays your own action.
- List opens the list at the strip's right end: under it, beside the window's right edge when there is no room under, or over the window's lower right corner when there is none there either. It is as tall as all its items where there is room (sixteen at most, then it scrolls) and always ends on a whole line. A press on a line buys or learns that one at once, exactly the number you need, with no question; at the Auction House a press searches for the item, and the line reads "Left Click to Search" under the mouse.
- The strips carry everything the Buy List gained in 2.6 to 2.8, in less room: Queue List and Guide List as two small buttons at the top of the list, profession tags under them, the lines that say what is cheaper elsewhere (with Show), Remove with a Shift-click and the line that puts removed items back, Check Prices with "about" and "only 40 for sale", and purchases that come off the lists at once, the Auction House's too.
- Goods sold in lots are bought by the whole lot, and a line shows the number it will buy. A purchase of 150 gold or more is asked about, as the game's own vendor window does.
- Buying can't run away from you: every purchase is worked out anew just before it is made, so fast or repeated presses buy once; a run buys only at the vendor it was started at and stops for good when that vendor closes; and what you just bought counts as held until your bags show it.
- Controller: LT / RT reach a strip from the window it hangs on; X is its main button, Y opens the list, A presses a line, the Menu button on the right switches between Queue List and Guide List, the Menu button on the left removes the line the cursor is on, B goes back.

### Leveling Guide
- Goal and Cheapest Route are two pickers on one line.
- Everything 2.8.0 brought is here unchanged: a step only uses a recipe while it is orange or yellow, the 424 recipes that were missing, and costs that follow checked Auction House prices.

### Professionally Lost
- New: with Professionally Lost installed, a window asks once which of the two addons does each job: Leveling Guide, Buy Lists, Trainer Panel, Guide Line in Item Tooltips, Scanned Prices, Light Up Its Step. On means Professionally Lost does it. Nothing changes until you press Apply, and Ask Me Later asks again at the next login. It never opens over the welcome, What's New or another question, and with a controller in use the first three start off, because Professionally Lost has no controller support yet.
- Handing a job over only quiets Glowey's Recipes' own part: nothing in Professionally Lost is changed or switched. It applies per profession, so smelting and Poisons, which Professionally Lost has no guide for, keep Glowey's Recipes' Leveling Guide.
- With its guide in use for a profession, the Leveling Guide and Materials tabs give way to an Open Professionally Lost button, and the recipe its guide is on is marked in the recipe list (Light Up Its Step).
- With Scanned Prices on (and DaylightMogul not installed), Glowey's Recipes also uses the auction prices Professionally Lost scanned, whichever of the two was seen later, so one scan serves both.
- Where its Buy for Guide or Scan Prices button hangs under the corner of the game's own vendor or Auction House window, the strip stands flush against the window's right edge instead.

### Options
- New: Window Height, Open Details by Default, Ask Before Buying All, and Show Your Alts' Professions (switch it off to leave your other characters out of the professions menu).
- New: a Professionally Lost group with the same six switches as its window, Open Professionally Lost, Professionally Lost Settings and Put Everything Back, which gives everything back to Glowey's Recipes at once, with no reload. It shows only while Professionally Lost is installed.

### Tours and What's New
- Tours no longer start by themselves and nothing dims the screen unasked. The first time a window or strip with a tour shows, one line says where the tours are: Plugins > Recipes > Help, with Retake Tour, Shop Strip Tour and Enchanting Runs Tour.
- Both tours are written for the new window and strips: the three window states and the rolled-up bar, the professions menu, each tab, the strip's count and buttons, the two lists and the tags, what each place leaves out, Remove, and Check Prices.
- What's New tells you why the window is smaller and what replaced the panels.

### Fixes
- Stop is always where you see it. If the window is moved, resized, rolled up or closed during a fight, Stop stays put with its own look until the fight ends, instead of leaving an unseen button behind.
- A long item name in the enchant row is no longer cut off (it wraps). A long recipe name in the list steps down a size and then takes the count's room before it is ever cut.
- A Buy List line's tooltip no longer repeats what your bank holds when Daylight UI 2.1.1 or later already lists it.

## 2.8.0
- Checked against Daylight UI 2.1.2. Searching a material from the Buy List finds it in every category, whatever category is picked on Daylight UI's Buy page.
- Fixed: the Leveling Guide no longer sends you to make things that give no skill points, or hardly any. With Vendor, Disenchant or Auction House picked, a recipe whose craft sells for more than its materials looked better the lower its chance of a point was, so a step could run a recipe down to a 10% chance and ask for a hundred crafts or more (First Aid 83 to 122: "Make 100 x Lesser Healing Potion"). With Cheapest, a cheap recipe could be kept down to a chance of a few percent. All four now work the same way: a step only uses a recipe while the game shows it orange or yellow (a point at least every other craft), so no step asks for more than about two crafts a point.
- A profit still counts with Vendor, Disenchant and Auction House, but never as a reason to craft something that rarely gives a point: of two recipes that both give points, the one that costs less (or earns more) for each point wins.
- Where no recipe you know or can learn is orange or yellow (stretches of Mining, or anywhere the recipes that would do better are ones you can't learn or price yet), the guide takes the green recipe with the best chance there is and says so on the step: "This recipe is green at this skill (a point only now and then): nothing you know or can learn does better here", with how many crafts a point to expect. Such a step is marked "green: a point only now and then" in the list of steps too.
- Where even the best recipe gives a point less than one craft in five, the guide plans no step at all and says so ("From 62 to 65 the recipes in the data give a point less than one craft in five"), rather than ask for dozens of crafts, and their materials, for a single point.
- For recipes you know, the game's own color at your skill now decides. A recipe the game shows gray is never the step you're on, and one it shows green is only used when nothing better exists, even where the guide's data says otherwise; the route is worked out again by itself when a skill-up brings that about.
- Fixed: "Or Instead" under the current step listed the recipes that were good when the step began, which could be green or gray by the time you were partway through it. It now lists the ones that are orange or yellow at your skill.
- Craft Next, "Also Good Right Now" and the mark on the best recipe no longer pick a cheap green recipe while one of yours is orange or yellow. When none is, Craft Next says so.
- Fixed: First Aid Kit, Camp Tent, Sharpening Wheel, Lodestone, Mana Well, Enchanted Lute, Reagent Bot, Faction Banner, Anvil, Tanning Rack, Spinning Wheel, Rock Garden, Toxin Study, Fermenter, Repair Bot and Arcane Salvager were planned as giving five skill points each (20 to 25, 140 to 145). The game gives none for them, so the guide no longer does. Cookie's Feast gives points up to 145, not 150, and Coarse Grinding Stone up to 90, not 75, as in the game.
- Fixed: with Vendor, Disenchant or Auction House picked, a recipe whose sale price looked far too good to be true was left out of the route altogether, which could leave a hole ("no recipe in the data gives points") where recipes did exist. It is now counted for its materials alone.
- Fixed: after a skill-up inside a stretch where no recipe gives points, the guide's line saying so disappeared.
- Fixed: a recipe's first yellow point showed a 75% chance on the Recipe page; it is still a sure point there.
- New: 424 recipes the data was missing: every recipe whose gray skill lies past 300 had been left out, though they are learned at 300 or below and many are made well before it. The Leveling Guide, the Missing tab, Craft Next and the tooltips now know them: Blacksmithing 91, Enchanting 88, Leatherworking 85, Tailoring 46, Engineering 42, Alchemy 38, Cooking 26, First Aid 7 and Mining 1. Among them Runecloth Bandage and Heavy Runecloth Bandage, Major Healing Potion, Lobster Stew and the other late fish recipes, Cloak of Warding, Delicate Arcanite Converter and the level 300 plans, patterns and formulas.
- With them the guide reaches 300 on orange and yellow recipes in First Aid (Runecloth Bandage from 260, Heavy Runecloth Bandage from 290), Cooking, Engineering, Blacksmithing, Leatherworking, Alchemy, Tailoring and Enchanting: the green last steps and the "no recipe gives points" stretches before 300 are gone there. Mining is unchanged: smelting alone does not carry it, as in the game.
- Runecloth Bandage and Heavy Runecloth Bandage are taught by a trainer nobody has reported yet: the guide plans them and says "First learn it from a First Aid trainer: the data doesn't say which one teaches it yet."
- Eight of the new recipes have no known way to learn them (Enchant Chest - Stats, Mooncloth Boots, the two transporters and others): they are used for a character who already knows them and are not listed as missing.
- A recipe's yellow and gray skill now come from the game's own table wherever the data disagreed with it (the 21 recipes set right above).
- Recipe sources from Polestar are read from its current version (0.4.1.1), which also brings sources for 302 of the new recipes' plans, patterns and formulas; the other 110 say "Source not known yet". A source that both Polestar and the correction list name is shown once.
- Fixed for good: prices, vendors and alts are kept by the server's rules ("US-PvP", "US-PvE"...) instead of by realm name, which the game stopped giving on 2026-11-20. Every numbered realm of a set of rules is one server with one Auction House for both factions, so a price read on one of them counts on all of them, and a character made from now on lands on the right server's book instead of sharing one with every other new character. Alts are the account's other characters under the same rules and faction, whichever numbered realm they are on.
- Your saved prices and vendors are carried over on the first login: each old book goes to the rules it belongs to (a newer price wins, a cheaper vendor stays). A book that can't be placed for sure stays where it is and is still read by the characters that wrote it. Nothing old is deleted, and going back to an older version of the plugin keeps working.
- With Daylight UI 2.1.2 or later: its own profession window now shows a recipe's materials cost, what it sells for and the profit. Beside it, the Docked Pane's Recipe tab no longer says the same again with slightly different numbers: it leaves the materials total and the Auction House's "sells for" and profit to Daylight UI, and keeps what Daylight UI doesn't show (each material's price and where it's from, the cost per skill point, the vendor's and disenchanting's value). You're asked once (Use Daylight UI's, or Keep Both), and "Leave Cost and Profit to Daylight UI" in the options changes it later. Glowey's Recipes' own window, and the pane beside DaylightMogul's window, are as they were.

## 2.7.0
- New: the Buy List costs an Auction House purchase by what is really for sale. When an item's prices are known step by step ("4 at 11s 75c, 51 at 12s..."), the row's cost walks those steps, cheapest first, for the number you need, instead of the number times the lowest price. With fewer for sale than you need the row says so ("only 40 for sale") and costs what is there. The row's tooltip lists the steps your purchase would take, the average for one, and when the prices were read.
- New: Check Prices, a button on the Auction House Buy List. It asks the Auction House for the price steps of every item on the list shown, one after another ("Checking prices: 3 of 12"); press it again (Stop) to end it, and it ends by itself when the window closes or you change the list. Any search you make yourself, a click on a row included, reads that item's steps too. Steps are trusted for 15 minutes; a cost worked out without them reads "about".
- New: where a vendor also sells an item, the Auction House Buy List asks only for the ones that are cheaper than the vendor, and the vendor's Buy List for the rest, so the two together ask for exactly what you need.
- The Leveling Guide's Materials ("To buy" and each material's cost), each step's cost and the route's total use the same step-by-step prices when they are known. Which recipes the route picks is still decided on one price an item.
- Controller support: Check Prices / Stop is a stop for the D-pad.

## 2.6.0
- Fixed: in the Leveling Guide, an "Or Instead" recipe with a material that has no price showed a cost of 100,000 gold or more a point ("200000 gold a point"). That figure was only the guide's own weight for ranking unpriced recipes last, never a price. Such a recipe now says "no price".
- New: with Daylight UI 2.0 or later and its Auction House on, Glowey's Recipes reads the prices Daylight UI has already collected (its searches and its Full scan), so materials no longer stand at "No price" when Daylight UI knows them. The newer of its price and yours is used; nothing of Daylight UI's is changed. The guide says "Auction House prices from Daylight UI" and when they were read, and its own Scan Auction House Prices button is left out while Daylight UI's window is the one in use (scan from that window instead). Without Daylight UI's Auction House, or with DaylightMogul, prices work as before.
- New: the Buy List at vendors and the Auction House is now two lists, picked with two tabs under its title: Queue List (what your crafting queue needs) and Guide List (what your Leveling Guides need). Each tab shows how many items it still has to buy. Your pick is remembered for the whole account and is the same at vendors and the Auction House; it starts on Guide List. If the list you picked has nothing to buy and the other one has, the other one shows for that visit.
- New: each Buy List shows only what is cheapest where you are. At the Auction House, items a vendor sells for less (or that only a vendor sells) are left out; at a vendor, items that are cheaper on the Auction House are left out. Items a vendor is cheapest for that this vendor doesn't sell still show grayed out, with where to get them. Nothing is hidden silently: a line under the list says how many were left out and why ("3 more are cheaper at a vendor: show them"); click it to show them for that visit, and again to hide them.
- "N to buy", the footer's total and Buy All Here count only what the list shows; at a vendor, "N to buy" is what this vendor can sell you right now.
- A list with nothing left to buy says so instead of showing an empty box.
- Controller support: the two tabs and the line under the list are stops for the D-pad like the rows, and LB / RB switch between the tabs.
- New: profession tags on the Buy List. When the list has items for two or more professions, a row of tags shows under the tabs: All, then one for each profession. Click a tag to see only that profession's items (an item several professions use shows that profession's share); click it again, or All, to see everything. "N to buy", the total, Buy All Here and the Auctionator List follow the tag. Your tag is remembered for the whole account, at vendors and the Auction House alike.
- New: remove an item from the Buy List. Hold Shift over a row and its right side reads "Remove"; Shift-click takes the item off that list (Queue List and Guide List each keep their own) for this character. Your queue and Leveling Guide aren't changed. A line at the end of the list says how many you removed and puts them back with a click. A removed item comes back by itself once the list no longer needs it, or needs more of it than when you removed it.
- Fixed: what you buy on the Auction House now comes off the Buy List right away. Auction purchases arrive by mail, and the list used to keep asking for them until you opened a mailbox. The row's tooltip says how many are bought and waiting in the mail.
- Fixed: buying from a vendor through the Buy List could put the items back on the list for a moment when they arrived in the bags in two steps, or when something else was read in between. A purchase the vendor refused (bags full) now returns to the list after five seconds by itself.
- Fixed: after buying something by hand in the vendor's window, the Buy List follows at once, and a press on a row or Buy All Here in that same moment no longer buys what you just bought again: it buys only what is still short.
- At the Auction House, a Buy List row under the mouse reads "Left Click to Search" on its right, so it's clear what a click does ("Remove" while Shift is held).
- Controller support: Y on a Buy List row removes it (shown as "Remove" in the button hints); the profession tags and the put-back line are stops for the D-pad.

## 2.5.4
- Checked against Daylight UI 2.1.1.
- Fixed with Daylight UI 2.1.1: its bags now add what your own bank (and the account bank) holds to an item's tooltip, so a Buy List row's tooltip said it twice ("You have 12 in bags, 5 in the bank" under Daylight UI's own lines). The row now leaves it to Daylight UI and says only what's in the mail, as it already did when an alt holds the item. With Daylight UI's "Item counts on tooltips" switched off, the row says it all itself again.

## 2.5.3
- Checked against Daylight UI 2.0.
- Fixed: the Auction House Buy List didn't show with Daylight UI 2.0's new Auction House window. It now docks to that window: under it when there's room, else beside it. On a screen with no room on any side it stays folded to its tab on the window's corner, so it never covers the window by itself; click the tab to open the list over the window, and again to put it away. It follows the window when you drag or scale it, and moves to the game's own window when you swap to that one. With Daylight UI's Auction House turned off, on Daylight UI 1.9, or with DaylightMogul, it docks where it always did.
- Fixed: a click on a Buy List row did nothing at Daylight UI's Auction House window. It now opens the Buy tab and searches for that item. At the game's own window a click still puts the name in the search box.
- Fixed: with Mastercraft, a gathering node's "Turns gray in 30 more skill" line kept Mastercraft's own wording in Daylight UI 2.0's Rich tooltip style. It now reads the same in both tooltip styles.

## 2.5.2
- Checked against Daylight UI 1.9.6.
- Fixed: with the Recipes window in use, opening a game window in a fight could raise an "action blocked" error. Recipes told the game how wide its window is so the next game window opened beside it, and the game then ran that part of its window code as an addon's. Recipes no longer does (Daylight UI 1.9.6 made the same fix for its own windows), so a game window that opens beside the Recipes window sits where the game's own profession window would have put it.

## 2.5.1
- Daylight Recipes is now Glowey's Recipes (DaylightUI Plugin), so it's clear it's a plugin and not part of Daylight UI. Inside Daylight UI the section is Glowey's Recipes. Your settings are kept. New Auctionator shopping lists are named "Glowey's Recipes"; an old "Daylight Recipes" list stays until you delete it.

## 2.5.0
- Enchanting in the Docked Pane: pick an enchant in Daylight UI's or DaylightMogul's profession window and the pane gets the same tools as the Recipes window, docked along its bottom: the item slot (drag an item on it or pick one from your bags; right-click empties it), the item every enchant goes on, Auto-replace, a count and an Enchant button, and enchant runs with Next and Done. A run's buttons stay up on any tab until it's done. Works with a controller too.
- The Professions key (K) opens the Recipes window while Daylight UI's own profession window is off.

## 2.4.1
- Fixed: the Daylight Recipes window didn't open in 2.4.0. The file that builds it had grown past a limit of the game's Lua and failed to load (an error naming Window.lua and "more than 60 upvalues").

## 2.4.0
- New: Cooldowns, above Tracking at the foot of the professions list. Your recipes that can only be made once in a while (transmutes, Mooncloth, Cured Rugged Hide, and any other the game reports a cooldown on) each get a tile: ready with an accent ring, or gray with the time left. Click one to open that recipe. Ready times are kept per character across logouts.
- Controller support: the whole Daylight Recipes window works with a controller (D-pad over everything, LB / RB through the tabs, the right stick scrolls, Y for the right-click actions, B closes), and so do the shopping panels, the tours, the welcome and What's New.
- Tracking also finds Find Minerals and Find Herbs by name, in case a spell's number differs.
- Labels and buttons in Title Case, and "Daylight UI" written with a space.

## 2.3.0
- New: Tracking at the foot of the professions list in the Daylight Recipes window. The profession tracking spells you know (Find Minerals, Find Herbs) each have an icon; click one to turn it on or off, as the minimap's tracking menu does. The one on is in full color with an accent ring and Daylight UI's glow (in the style you picked for its main buttons); the rest are grayed. It follows changes made from the minimap, and hides when you know none.

## 2.2.1
- The window tour that starts by itself opens the Daylight Recipes window again. It asked the game to open a profession, which the game blocks unless you click, so no window showed.

## 2.2.0
- Everyone, including players who had Daylight Recipes before, sees the welcome and the tours once with this version.
- Keep My Window on the welcome leaves a window you already picked (the game's or the docked pane) as it is.
- New: a welcome on first launch that lists what Daylight Recipes takes over (your profession window, the panels at vendors, the auction house and trainers, recipe tooltips). Start Tour uses Recipes' window and starts the tour; Keep My Window keeps the one you had.
- New: tours, each shown once the first time you get there: the window (professions, tabs, recipe list, crafting, the swap button), the Leveling Guide, Missing and Queue tabs, the buy lists and trainer panel, and enchanting runs. Back, Next and Skip tour; Escape skips; a fight ends it.
- New: after an update, a short note with what changed.
- New Help card in the options: Retake Tour, What's new, and Revert to Daylight UI's Window (or DaylightMogul's, or the game's: whichever you had).
- Mastercraft's gathering node tooltips now read "Turns gray in 30 more skill", the color in its own color, instead of "Turns grey at +30 skill" (and "Gatherable in 5 more skill").
- New: tells you when a newer version is out. Your copy and those of players in your guild and group trade version numbers in the background, and one chat line says when there is a newer one to get through CurseForge or WowUp (once a session). Turn it off with "Tell me when a newer version is out" on the plugin's first options page; then nothing is sent either.
- Fix: you can link your profession to chat again. With the chat box open, Shift-click the profession's icon at the top of the window, or the profession in the list on the left (one that isn't open opens first, then goes into chat). Both tooltips say so.
- Fix: Shift-clicking a recipe, item or reagent into chat no longer relies on the game's old chat function, which is only there while its backward-compatibility addon is loaded.
- Recipes marked at vendors: a small square in your accent on any recipe a vendor sells that you or an alt on this realm and faction can learn and doesn't know yet. Bright when this character can learn it now, faint when it's for later (more skill needed) or for an alt. On Daylight UI's vendor page and the game's own vendor window (DaylightMogul's vendor window has no way in, so none there; the tooltip still says who it's for). Switch: "Mark recipes at vendors".
- Recipe item tooltips: "Known by" in class colors, and a new "Can learn" line with your characters who have the profession but not the recipe, and the skill it needs when theirs is short. Shown when any of your characters on this realm and faction has the profession, not only this one.
- Mastercraft: its own list of your characters on recipe items is switched off while ours shows, so it isn't said twice (asked once; "Hide Mastercraft's recipe lines" in the options gives it back).
- Translations: the new text in German, French, Spanish, Russian, Korean and Simplified Chinese.

## 2.1.0
- Leveling Guide: a light runs round the step you're on, and round its recipe in the recipe list wherever you scroll, so it's easy to find. It uses the glow style you picked for Daylight UI's main buttons (none when that's set to None or Daylight UI's motion is off). Turn it off with "Light up the guide's step" (Help around the game). Needs Daylight UI 1.8.4 or later.
- Swap button: on a window where Daylight UI 1.8.4 puts its own swap icon or "Daylight UI window" link, its tooltip says which window it opens and what Daylight UI's control beside it does.
- Translations: the new text in German, French, Spanish, Russian, Korean and Simplified Chinese.

## 2.0.7
- Daylight UI 1.8.4: the swap button no longer sits on top of Daylight UI's new swap icon in its profession window's header, or its "Daylight UI window" link on the game's profession window. It goes just left of them.

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
- Its own icon: in the game's AddOns list and other menus (instead of the blank "?"), and on its page in Daylight UI's options.

## 2.0.3
- A swap button (two arrows) beside the X: on Daylight Recipes' window it switches to the game's own profession window, and on the game's window it switches back. The open profession moves across at once, and the window you pick stays picked. Not in a fight.
- New "Use Daylight Recipes' profession window?" question, asked once. Yes makes Daylight Recipes' window the one and switches Daylight UI's own profession window off (one reload, offered), so the swap button goes to the game's window. Picking Docked pane in the options brings Daylight UI's window back as it was. The Profession window choice now also has The game's window.
- Reputation recipes read "Nightclaw Druids: Friendly (Current Rep: Neutral)", each standing in the game's reputation colors (red for Hated and Hostile, orange for Unfriendly, yellow for Neutral, green from Friendly up).
- Herbalism, Skinning and Fishing are no longer grayed out on the left of the window: a click shows their own page, with your skill, your rank and when to train the next one (they have no recipes, so no recipe list or Leveling Guide).
- Mining is found under its own name too, so its smelting recipes and Leveling Guide open from the left; if the game won't open a profession from there, its page says which spell to cast instead.
- Text wraps instead of being cut off: long recipe, item and place names, prices and notes in the window, the pane and the buy and trainer lists take a second line, and a page drawn at one width is drawn again when its panel gets wider or narrower.
- Buttons fit their words in every language (Create All, Queue, Buy all here, Learn all...): when the crafting bar runs out of room, the count and Queue move to a row of their own above Create.
- The enchant item row, the pane's skill beside its tabs, and the buy list's total beside its button no longer run into each other.
- At a large Window size on a small screen, the window shrinks to fit instead of running off the screen.
- With Daylight UI 1.8.3: Create, Buy all here, Learn all and the Yes of the confirm box have Daylight UI's main-button look; a buy list's item tooltip no longer repeats your bags and bank when Daylight UI already lists every character's (the mail count stays).
- New: camping items. Herbalism, Skinning and Fishing's pages list theirs (Fishing's Fish Bowl, Fishing Rack and Fishing Hut, for one): what each does, what it takes and what you hold of it, the skill it needs, whether you know it, and how to learn it (a trainer or the quest "Camping 101", or a blueprint with where it drops and a waypoint). A new "Camping" entry on the left lists every profession's camping items, yours first.
- Fishing's page says where its next rank comes from: Expert is a book sold in Booty Bay, Artisan a quest from Nat Pagle in Dustwallow Marsh (with a waypoint to each), not a trainer.
- The Missing tab knows where far more recipes come from: of the 469 listed as "Source not known yet", 193 now show their vendors, drops, quests or reputation, from Polestar's data (GPL-3.0), Forever's own ones among them (the Gustwoven and Windraveled patterns: the Nightclaw Druids' vendor).
- Recipes that ask for a reputation say which and how much, with your standing beside it (green once you have it): "Nightclaw Druids: Friendly (you: Neutral)". For a recipe no data knows, the recipe item's own tooltip is read for it.
- Right-click one of your two primary professions on the left to unlearn it (as in the game's professions book), after an "Are you sure?" that names it and warns that its skill and recipes are lost. Its saved skill, recipes, Leveling Guide and queued recipes are forgotten with it.
- Fix: a skill-up while you gather (Herbalism 70 to 75) shows on the window's list of professions and the gathering page at once, with no profession window open.
- Fix: the window fits the screen again when the UI scale or the game's window size changes.
- Lighter: a page drawn again after its panel changed width redraws only that window (not the pane, the window and the buy lists together), and never the folded pane.
- The buy list's item tooltip keeps "You have..." unless Daylight UI (1.8.3 or later, its bags and its bank and alts viewer on) lists your characters' bags and bank there itself; the mail stays said.

## 2.0.2
- On German, French, Spanish, Russian, Korean and Chinese clients, words the game already translates (like Apprentice, Journeyman, Search, Yes and No) use the game's own translation instead of our draft.
- Item tooltips no longer show your alts' guide lines: only this character's own guides, for the professions it has learned.

## 2.0.1
- Item tooltips only speak of the professions this character has learned: "Used in", "Known by" and your own guides' lines (your alts' guide lines stay).
- Daylight Recipes speaks German, French, Spanish, Russian, Korean and Simplified Chinese (machine drafts, corrections welcome).
- Fixes for non-English game clients: the Leveling Guide makes Enchanting's rods and Engineering's tools again when the next recipes need them (the game names them in your language, and the guide only knew the English names); the trainer's "Recommended" list finds the recipes a trainer teaches by their name in your language too.
- Recipe, item, profession, zone and quest names are shown in your game's language wherever the game has them (the Missing tab, an alt's recipes, trainer reminders, item tooltips, the buy lists), with the English name only while the game hasn't loaded one yet.
- Searches find accented and Cyrillic letters whatever their case ("ä" finds "Ä", "б" finds "Б"), and lists sorted by name follow your language's alphabet.
- Window opacity: follows Daylight UI's by default, or set your own on the options page.

## 2.0.0
- New: Daylight Recipes' own profession window, in place of the game's and Daylight UI's. Your professions sit on the left (click one to open it) with your alts' below; the open profession's skill bar and five tabs across the top: Recipes, Leveling Guide, Materials, Queue and Missing.
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
- It takes the place of DaylightMogul's profession window too (Mogul's prices are still used). Prefer Daylight UI's or Mogul's window? Options, Recipes, Profession window: "Docked pane" brings it back with the pane beside it.
- "Craft next" (the Leveling Guide's "Also good right now") lists your recipes that still give points, cheapest expected cost per point first (with the chance and how many you can make now); a click picks it in the profession window.
- New: a route to your target skill (your cap or the next rank's, or 300; click to change). For every point it takes the recipe with the cheapest expected cost per point, among the ones you know and the ones a trainer will teach by then, counting the misses on yellow and green recipes, and stops at each rank cap to tell you which rank to train. Each step shows the skill range, the recipe, about how many crafts and what they cost.
- New: the materials the route takes, less what the route makes on the way, with what's in your bags, bank (Forever's bank tabs and the account's shared ones too) and mail, what your alts on the realm hold, and what's left to buy and for how much, with who on your account can make it or which vendor sells it.
- New: Daylight Recipes no longer needs another addon. It keeps its own Auction House prices from what you browse and from a scan you start in the Leveling Guide (DaylightMogul's prices are used instead when it's loaded, and then nothing is read twice), learns vendor prices from the merchants you visit, and remembers every character's professions, recipes, bags, bank and mail.
- New: item tooltips (Daylight UI 1.7): which professions use a material and in how many recipes, what your plans (and your alts') need of it, and who on your account knows a recipe item.
- New: trainer reminders in chat when a skill-up opens new recipes at a trainer or a profession reaches its cap, and a small mark on the best recipe to skill up with in Daylight UI's recipe list. Each can be turned off on the options page.
- Fix: switching profession in DaylightMogul's window no longer keeps showing the last profession's recipe.
- Fix: the Missing tab shows the skill a trainer really asks for a recipe (it showed the orange threshold, which is off for a few hundred recipes), and no longer says "Skill 0" when the data doesn't know.
- Fix: recipes the data has no source for (many of Forever's own) are listed as "Source not known yet" instead of being left out, so the Missing tab no longer says you know every recipe when you don't.
- The skill-up chance follows the game's own color for recipes you know: orange is a sure point and gray none, with the thresholds only giving the odds on yellow and green. Recipes that give more than one point say so, and the cost per skill point counts it.
- Trainers, vendors and drops in a recipe's sources are listed nearest first (your zone, then your continent), so the six shown are the ones you can reach, and a waypoint goes to the nearest spawn.
- Lighter: the Missing tab no longer reads every recipe again on each bag change or rebuilds its list on each skill point (only learning a recipe, or opening the window, does), a recipe's sources are worked out once, and the list shows 60 recipes at a time with "Show more".
- Fix: after Daylight UI's profession window closes, a weapon skill-up no longer makes the pane forget your known recipes.

## 1.1.2
- All text in American English (gray, color and the like), in the game and in the docs.

## 1.1.1
- Lighter while a profession is open: a bag change or a craft no longer rebuilds the missing list (only learning a recipe does) or redraws the pane unless the skill changed; item data arriving redraws only a page waiting on that item; the missing list's search runs a moment after the last key instead of on every key.

## 1.1.0
- The pane folds away, like Daylight UI's damage meter: a small tab on its outer edge slides it out of sight, leaving only the tab against the profession window, and a click on the tab brings it back. It stays folded or open between sessions, on Daylight UI's profession window and DaylightMogul's.

## 1.0.0
- First release: a pane beside Daylight UI's profession window, or DaylightMogul's.
- Recipe page: skill-up chance (Overtime counted), every material priced from the Auction House (DaylightMogul) or the cheapest vendor (reputation and Bartering counted), total and cost per skill point, value on the Auction House, at a vendor and disenchanted with the profit each way, and the disenchant materials.
- Missing page: every recipe you don't know for the open profession, with its trainers, vendors, drops and quests, their places, and a waypoint on click.
- Recipe, source and disenchant data from ForeverRecipes (GPL-3.0).
