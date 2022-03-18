local Context = require "artist.core.context"
local Items = require "artist.core.items"
local log = require "artist.lib.log"

local helpers = require "test_helpers"

local function basic_setup()
  local world = helpers.World()
  local context = Context()
  local items = context:require(Items)

  local inv1 = world:add_inventory("inventory_1")
  inv1.contents[1] = { name = "minecraft:dirt", count = 64 }
  inv1.contents[2] = { name = "minecraft:cobblestone", count = 32 }
  inv1.contents[4] = { name = "minecraft:dirt", count = 12 }

  return world, context, items, inv1
end

local function count(items, name)
  local item = items.item_cache[name]
  return item and item.count or 0
end

local function yield()
  os.queueEvent("artist_yield")
  os.pullEvent("artist_yield")
end

describe("artist.core.items", function()
  describe("loading and unloading of inventories", function()
    it("loads an inventory", function()
      local world, context, items, inv1 = basic_setup()

      helpers.simulate(world, context, function()
        items:load_peripheral(inv1.name)
      end)

      expect(count(items, "minecraft:dirt")):eq(64 + 12)
      expect(count(items, "minecraft:cobblestone")):eq(32)
    end)

    for i = 0, 4 do
      it("loads an inventory again after " .. i .. " ticks", function()
        local world, context, items, inv1 = basic_setup()

        helpers.simulate(world, context, function()
          items:load_peripheral(inv1.name)

          for _ = 1, i do yield() end
          helpers.check_invariant(world, items)

          items:load_peripheral(inv1.name)
        end)

        expect(count(items, "minecraft:dirt")):eq(64 + 12)
        expect(count(items, "minecraft:cobblestone")):eq(32)
      end)
    end

    for i = 0, 4 do
      it("loads and unloads an inventory after " .. i .. " ticks", function()
        local world, context, items, inv1 = basic_setup()

        helpers.simulate(world, context, function()
          items:load_peripheral(inv1.name)

          for _ = 1, i do yield() end
          helpers.check_invariant(world, items)

          items:unload_peripheral(inv1.name)
        end)

        expect(count(items, "minecraft:dirt")):eq(0)
        expect(count(items, "minecraft:cobblestone")):eq(0)
      end)
    end
  end)

  describe("extracting items", function()
    it("transfers to an inventory", function()
      local world, context, items, inv1 = basic_setup()
      local inv2 = world:add_inventory("inventory_2")

      helpers.simulate(world, context, function()
        items:load_peripheral(inv1.name)
      end)

      helpers.simulate(world, context, function()
        items:extract(inv2.name, "minecraft:dirt", 100)
      end)

      expect(count(items, "minecraft:dirt")):eq(0)
      expect(inv2.contents[1]):same { name = "minecraft:dirt", count = 64 }
      expect(inv2.contents[2]):same { name = "minecraft:dirt", count = 12 }
    end)

    it("transfers to a specific slot", function()
      local world, context, items, inv1 = basic_setup()
      local inv2 = world:add_inventory("inventory_2")

      helpers.simulate(world, context, function()
        items:load_peripheral(inv1.name)
      end)

      helpers.simulate(world, context, function()
        items:extract(inv2.name, "minecraft:dirt", 100, 1)
      end)

      expect(count(items, "minecraft:dirt")):eq(12)
      expect(inv1.contents[1]):same { name = "minecraft:dirt", count = 12 }
      expect(inv1.contents[3]):eq(nil)
      expect(inv2.contents[1]):same { name = "minecraft:dirt", count = 64 }
      expect(inv2.contents[2]):eq(nil)
    end)

    it("transfers to an inventory despite inventory changes", function()
      local world, context, items, inv1 = basic_setup()
      local inv2 = world:add_inventory("inventory_2")

      helpers.simulate(world, context, function()
        items:load_peripheral(inv1.name)
      end)

      helpers.simulate(world, context, function()
        inv1.contents[1].count = 50 -- A lie!
        items:extract(inv2.name, "minecraft:dirt", 64, 1)
        for _ = 1, 3 do yield() end
        items:load_peripheral(inv1.name)
      end)

      expect(count(items, "minecraft:dirt")):eq(0)
      expect(inv2.contents[1]):same { name = "minecraft:dirt", count = 62 }
    end)
  end)

  describe("inserting items", function()
    it("rescans the inventory list() calls.", function()
      local world, context, items, inv1 = basic_setup()
      local inv2 = world:add_inventory("inventory_2")
      inv2.contents[1] = { name = "minecraft:dirt", count = 64 }
      inv2.contents[2] = { name = "minecraft:cobblestone", count = 64 }

      helpers.simulate(world, context, function()
        items:load_peripheral(inv1.name)
      end)

      local old_list, list_called = inv1.methods.list, 0
      inv1.methods.list = function(...)
        list_called = list_called + 1
        return old_list(...)
      end

      helpers.simulate(world, context, function() items:insert(inv2.name, 1, 64) end)

      expect(list_called):describe(".list() is only called once."):eq(1)
      expect(count(items, "minecraft:dirt")):eq(140)
      expect(inv2.contents[1]):eq(nil)
      expect(inv1.contents[3]):same { name = "minecraft:dirt", count = 64 }
      expect(inv1.contents[4]):same { name = "minecraft:dirt", count = 12 }

      helpers.simulate(world, context, function() items:insert(inv2.name, 2, 64) end)

      expect(list_called):describe(".list() is called once more."):eq(2)
      expect(count(items, "minecraft:cobblestone")):eq(96)
      expect(inv2.contents[2]):eq(nil)
      expect(inv1.contents[2]):same { name = "minecraft:cobblestone", count = 64 }
      expect(inv1.contents[5]):same { name = "minecraft:cobblestone", count = 32 }
    end)

    it("de-duplicates list() calls.", function()
      local world, context, items, inv1 = basic_setup()
      local inv2 = world:add_inventory("inventory_2")
      inv2.contents[1] = { name = "minecraft:dirt", count = 64 }
      inv2.contents[2] = { name = "minecraft:dirt", count = 64 }

      helpers.simulate(world, context, function()
        items:load_peripheral(inv1.name)
      end)

      local old_list, list_called = inv1.methods.list, 0
      inv1.methods.list = function(...)
        list_called = list_called + 1
        return old_list(...)
      end

      helpers.simulate(world, context, function()
        items:insert(inv2.name, 1, 64)
        items:insert(inv2.name, 2, 64)
      end)

      expect(list_called):describe(".list() is only called once."):eq(1)
    end)
  end)

  -- We generate a random sequence of actions against the item store and run them,
  -- checking invariants hold at every point. Tests can then be re-run by running
  -- mcfly with --seed=deadbeef.
  -- This has actually caught a surprising number of subtle bugs. It's not clear
  -- if they'd ever occur in practice (lots of weird race condition stuff with
  -- peripherals detaching), but probably useful to test.
  describe("randomised tests", function()
    local function create_test(seed)
      it(("test with seed %08x"):format(seed), function()
        local log = log.get_logger(("Test-%08x"):format(seed))

        math.randomseed(seed)
        local world = helpers.World()
        local context = Context()
        local items = context:require(Items)

        -- Setup a random collection of inventories
        local item_types = { "item_1", "item_2", "item_3" }
        local invs = {}
        local inv_n, attachable_inv_n = 5, 3
        for i = 1, inv_n do
          local name = "inventory_" .. i
          local inv = world:add_inventory(name)
          invs[i], invs[name] = inv, inv

          for j = 1, 27 do
            if math.random() >= 0.5 then
              invs[i].contents[j] = { name = item_types[math.random(#item_types)], count = math.random(64) }
            end
          end
        end

        helpers.simulate(world, context, function()
          items:load_peripheral(invs[1].name)

          for _ = 1, 100 do
            local action = math.random()

            if action <= 0.05 then
              local inv = invs[math.random(inv_n)]
              inv.attached = not inv.attached
              log("invs[%q].attached = %s", inv.name, inv.attached)
            elseif action <= 0.10 then
              local inv = invs[math.random(attachable_inv_n)].name
              log("items:load_peripheral(%q)", inv)
              items:load_peripheral(inv)
            elseif action <= 0.15 then
              local inv = invs[math.random(attachable_inv_n)].name
              log("items:unload_peripheral(%q)", inv)
              items:unload_peripheral(inv)
            elseif action <= 0.40 then
              log("yield()")
              yield()
            elseif action <= 0.70 then
              local count = math.random(1, 100)
              local item = item_types[math.random(#item_types)]
              local dest = invs[math.random(attachable_inv_n + 1, inv_n)].name

              log(("items:extract(%q, %q, %d)"):format(dest, item, count))
              items:extract(dest, item, count)
            else
              local count = math.random(1, 100)
              local slot = math.random(27)
              local source = invs[math.random(attachable_inv_n + 1, inv_n)].name

              log(("items:insert(%q, %q, %d)"):format(source, slot, count))
              items:insert(source, slot, count)
            end

            helpers.check_invariant(world, items, false)
          end
        end)

      end)
    end

    if mcfly_seed then
      create_test(mcfly_seed)
    else
      for _ = 1, 500 do
        create_test(math.random(0, 0x1FFFFFFF))
      end
    end
  end)
end)
