local upgradeLevelIcon = false

function init()
	connect(g_game, {
		onGameStart = enableThingLua,
		onGameEnd = disableThingLua
	})

	if g_game.isOnline() then
		enableThingLua()
	end

	connect(Tile, {
		onAddThing = onAddThing,
	})

  connect(Item, {
		onAddThing = onAddThing,
	})

end

function terminate()
	disconnect(g_game, {
		onGameStart = enableThingLua,
		onGameEnd = disableThingLua
	})
	disconnect(Tile, {
		onAddThing = onAddThing,
	})


end

function enableThingLua()
	g_game.enableTileThingLuaCallback(true)
	addEvent(function ()
		g_game.enableTileThingLuaCallback(true)
	end)
end

function disableThingLua()
	g_game.enableTileThingLuaCallback(false)
end

function onAddThing(tile, thing)
	if thing:isItem() and thing:isPickupable() and not thing:isGround() and not thing:isFullGround() then
		getImageRarity(thing)
	end
end

local imgTableFrame = {
[1] = "/images/ui/rarity/frame_rare", 
[2] = "/images/ui/rarity/frame_epic",
[3] = "/images/ui/rarity/frame_legendary",
}

function getImageRarity(item)
  if not item then
    return ""
  end
  local s = type(item) == "table" and item.rarity or (item.getRarity and item:getRarity() or 0)
  if s == 0 then
	return ""
  end
   return imgTableFrame[s]
end


-- where is the code where you edit rarity in serverSide data