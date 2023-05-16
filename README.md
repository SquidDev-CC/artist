# A Rather Tremendous Item SysTem
Artist is an inventory management system for CC: Tweaked (requires MC 1.16.x or later). One could think of it as a
budget AE network. It offers an easy way to store and extract items, but powered entirely through ComputerCraft.

https://user-images.githubusercontent.com/4346137/159051788-2664b57e-b184-4e1d-b759-99e5c010d539.mp4

## Features
 - Index an arbitrary number of inventories (chests, barrels, etc...), allowing for insertion and extraction from them.
 - Simple interface to view and request items.
 - Inventory operations run in parallel, allowing for near-instant scanning and transfer of items.
 - Furnace management support, able to automatically refuel furnaces and insert smelted items into the main system.
 - Automatically dispose of items when you've got too many.

## Install
 - Place down a turtle and some chests, and connect them all together with wired modems and networking cable.
 - Run `wget run https://raw.githubusercontent.com/SquidDev-CC/artist/HEAD/installer.lua` on your computer to install artist.
 - Run `/artist.lua` to start it. You may want to call this from your `startup.lua` file!

## Basic usage
 - Type to filter items. All text inputs use standard [readline] keybindings, so <kbd>Ctrl+u</kbd> can be used to clear
   the filter. Items are searchable using display name, item id and enchantments.
 - You can scroll through the list with <kbd>↑</kbd>/<kbd>↓</kbd>/<kbd>PgUp</kbd>/<kbd>PgDown</kbd>.
 - Hold <kbd>Tab</kbd> to see additional information about an item, such as its durability or enchantments.
 - You can close Artist (or any dialog within Artist) by typing <kbd>Ctrl+d</kbd>.
 - To extract an item, press <kbd>Enter</kbd>. This brings up the "Extract" dialog. Hit <kbd>Enter</kbd> again to
   extract 64 items, or specify a different amount. The input box supports arbitrary expressions (like `64 * 2 + 16`),
   which can be useful when working with larger numbers.
 - To smelt an item, press <kbd>Ctrl+Shift+f</kbd>. Here you can specify the number of items to smelt (defaulting to 64
   again) and the number of furnaces to use (defaults to all of them). This requires furnaces to be attached on the
   wired network.

## Configuration
Artist writes a (documented) config option to `.artist.d/config.lua`, which can be used to change some of Artist's
behaviour.

Some options you may want to adjust:

 - `turtle` → `auto_drop`: Auto-drop items from the turtle's inventory when requested from the interface.
 - `furnace` → `fuels`: A list of valid fuels for the furnace.
 - `dropoff` → `chests`: A list of "dropoff" chests. Items inserted into them are automatically transferred into the
   main system.
 - `trashcan` → `items`: Discard items when you've got too many of them. This requires another turtle on the network
   running the [extra/trashcan.lua](extra/trashcan.lua) script. This is a mapping of items to the max number to stock.

   **Example:**
    ```lua
    items = {
      ["minecraft:cobblestone"] = 20000,
      ["minecraft:cobbled_deepslate"] = 20000,
    }
    ```

## Extending
Artist is intended to be somewhat extensible, and you can register your own custom modules (be aware that the API is not
stable though!) See the `examples/display.lua` file for an example.

## History
Artist is a pretty old program at this point. It was [first written in 2016][forum post] and, to my knowledge, was the
first "inventory management" program for CC. While the code has changed a lot, the core ideas and interface haven't.

It should be noted that this is not the only item system out there, nor is it necessarily the best. There's a couple of
other item systems I'm aware of out there:

 - **[Turtlegistics]:** This was the first inventory system to become popular on [SwitchCraft]. I _believe_ it's the
   first to use the turtle's inventory as a drop-off and pickup point (Artist used separate chests beforehand).
 - **[Milo] (see also [this forum post][milo forum]):** Milo is probably the most powerful inventory system out there,
   with support for crafting and remote item transfer (using Plethora's introspection module).

[forum post]: http://www.computercraft.info/forums2/index.php?/topic/27321-mc-189-1122-plethora/page__view__findpost__p__262475 "Artist on the ComputerCraft forums"
[turtlegistics]: https://github.com/apemanzilla/turtlegistics "Tutlegistics on GitHub"
[milo]: https://github.com/kepler155c/opus-apps/tree/develop-1.8/milo
[milo forum]: http://www.computercraft.info/forums2/index.php?/topic/29761-milo-crafting-and-inventory-system/
[switchcraft]: https://switchcraft.pw "The SwitchCraft Minecraft server"
[readline]: https://en.wikipedia.org/wiki/GNU_Readline "GNU Readline - Wikipedia"
