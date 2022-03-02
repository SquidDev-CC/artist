# A Rather Tremendous Item SysTem
Artist is an inventory management system for CC: Tweaked (requires MC 1.15.x
or later).

One could think of it as a poor-man's AE network. It offers an easy way to store
and extract items, but powered entirely through ComputerCraft.

## Features
 - Index an arbitrary number of inventories (chests, barrel, crates, etc...),
   allowing for insertion and extraction from them.
 - Simple interface to view and request items.
 - Furnace management support, able to automatically refuel furnaces and insert
   smelted items into the main system.
 - Caching of item information, allowing for speedier startup.

## Install
 - Place down a turtle and some chests, and connect them all together with a wired modem.
 - Run `wget run https://gist.githubusercontent.com/SquidDev/e0f82765bfdefd48b0b15a5c06c0603b/raw/clone.lua https://github.com/SquidDev-CC/artist.git` on your computer to install artist.
 - Run `artist/launch.lua` to start it. You may want to call this from your `startup.lua` file!
## See also
It should be noted that this is not the only item system out there, nor is it
necessarily the best. You should also check out [these][turtlegistics]
[fantastic][roger] [programs][milo]. One notable missing feature is the ability
to run multiple instances on the same set of chests.

[turtlegistics]: https://github.com/apemanzilla/turtlegistics "Tutlegistics on GitHub"
[roger]: http://www.computercraft.info/forums2/index.php?/topic/28438- "roger109z's item system on the CCF"
[milo]: https://github.com/kepler155c/opus-apps/tree/develop-1.8/milo
