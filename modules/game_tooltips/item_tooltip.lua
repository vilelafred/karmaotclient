local CODE_TOOLTIPS = 105

local tooltipWindow = nil
local itemSprite = nil
local itemWeightLabel = nil
local labels = nil
local hoveredItem = nil
local player = nil
local protocolGame = nil
local showingVirtual = nil
local hoveredLinked = nil

local BASE_WIDTH = 170
local BASE_HEIGHT = 0

local tooltipWidth = 0
local tooltipWidthBase = BASE_WIDTH
local tooltipHeight = BASE_HEIGHT
local longestString = 0

cachedItems = {}

local Colors = {
  Default = "#ffffff",
  ItemLevel = "#abface",
  Description = "#8080ff",
  Implicit = "#ffbb22",
  Attribute = "#2266ff",
  Mirrored = "#22ffbb"
}

local rarityColor = {
  {name = "", color = "#ffffff"},
  {name = "Common", color = "#7b7b7b"},
  {name = "Rare", color = "#1258a2"},
  {name = "Epic", color = "#bd3ffa"},
  {name = "Legendary", color = "#ff7605"}
}

local implicits = {
  ["ca"] = "Critical Damage",
  ["cc"] = "Critical Chance",
  ["la"] = "Life Leech",
  ["lc"] = "Life Leech Chance",
  ["ma"] = "Mana Leech",
  ["mc"] = "Mana Leech Chance",
  ["speed"] = "Movement Speed",
  ["fist"] = "Fist Fighting",
  ["sword"] = "Sword Fighting",
  ["club"] = "Club Fighting",
  ["axe"] = "Axe Fighting",
  ["dist"] = "Distance Fighting",
  ["shield"] = "Shielding",
  ["fish"] = "Fishing",
  ["mag"] = "Magic Level",
  ["a_phys"] = "Physical Protection",
  ["a_ene"] = "Energy Protection",
  ["a_earth"] = "Earth Protection",
  ["a_fire"] = "Fire Protection",
  ["a_ldrain"] = "Lifedrain Protection",
  ["a_mdrain"] = "Manadrain Protection",
  ["a_heal"] = "Healing Protection",
  ["a_drown"] = "Drown Protection",
  ["a_ice"] = "Ice Protection",
  ["a_holy"] = "Holy Protection",
  ["a_death"] = "Death Protection",
  ["a_all"] = "Protection All"
}

local impPercent = {
  ["ca"] = true,
  ["cc"] = true,
  ["la"] = true,
  ["lc"] = true,
  ["ma"] = true,
  ["mc"] = true,
  ["a_phys"] = true,
  ["a_ene"] = true,
  ["a_earth"] = true,
  ["a_fire"] = true,
  ["a_ldrain"] = true,
  ["a_mdrain"] = true,
  ["a_heal"] = true,
  ["a_drown"] = true,
  ["a_ice"] = true,
  ["a_holy"] = true,
  ["a_death"] = true,
  ["a_all"] = true
}

function init()
  connect(UIItem, {onHoverChange = onHoverChange})
  connect(g_game, {onGameEnd = resetData})
  -- [Custom] connect(UILinkedItem, {onHoverChange = onHoverChange})

  ProtocolGame.registerExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

  tooltipWindow = g_ui.displayUI("item_tooltip")
  tooltipWindow:hide()

  labels = tooltipWindow:getChildById("labels")
  itemWeightLabel = tooltipWindow:getChildById("itemWeightLabel")
  itemSprite = tooltipWindow:getChildById("itemSprite")
end

function terminate()
  disconnect(UIItem, {onHoverChange = onHoverChange})
  disconnect(g_game, {onGameEnd = resetData})
  --disconnect(UILinkedItem, {onHoverChange = onHoverChange})

  ProtocolGame.unregisterExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

  if tooltipWindow then
    cachedItems = {}
    hoveredItem = nil
    player = nil
    protocolGame = nil
    showingVirtual = nil
    hoveredLinked = nil

    itemWeightLabel = nil
    itemSprite = nil
    labels = nil

    tooltipWindow:destroy()
    tooltipWindow = nil
  end
end

function onExtendedOpcode(protocol, code, buffer)
  local json_status, json_data =
    pcall(
    function()
      return json.decode(buffer)
    end
  )

  if not json_status then
    g_logger.error("Tooltips JSON error: " .. json_data)
    return
  end

  local action = json_data.action
  local data = json_data.data
  if not action or not data then
    return
  end
  if action == "new" then
    newTooltip(data)
  end
end

function newTooltip(data)
  local _itemUId = data.uid
  local _itemName = data.itemName
  local _itemDesc = data.desc
  local _itemId = data.clientId
  local _itemLevel = data.itemLevel or 0
  local _imp = data.imp
  local _unidentified = data.unidentified
  local _mirrored = data.mirrored
  local _upgradeLvel = data.uLevel or 0
  local _uniqueName = data.uniqueName
  local _itemRarity = data.rarityId or 0
  local _itemMaxAttributes = data.maxAttr or 0
  local _itemAttributes = data.attr
  if _itemRarity ~= 0 then
    for i = _itemMaxAttributes, 1, -1 do
      _itemAttributes[i] = _itemAttributes[i]:gsub("%%%%", "%%")
    end
  end
  local _isStackable = data.stackable
  local _itemType = data.itemType
  local _firstStat = data.armor or data.attack or 0
  local _secondStat = data.hitChance or data.defense or 0
  local _thirdStat = data.shootRange or data.extraDefense or 0
  local _weight = data.weight
  cachedItems[_itemUId] = {
    last = os.time(),
    name = _itemName,
    desc = _itemDesc,
    iLvl = _itemLevel,
    imp = _imp,
    unidentified = _unidentified,
    mirrored = _mirrored,
    uLvl = _upgradeLvel,
    uniqueName = _uniqueName,
    rarity = _itemRarity,
    maxAttributes = _itemMaxAttributes,
    attributes = _itemAttributes,
    stackable = _isStackable,
    type = _itemType,
    first = _firstStat,
    second = _secondStat,
    third = _thirdStat,
    weight = _weight
  }
  
  if hoveredLinked and _itemUId == hoveredLinked.uid then
    hoveredLinked.cached = true
    for key, value in pairs(cachedItems[_itemUId]) do
      hoveredLinked[key] = value
    end
    buildItemTooltip(hoveredLinked:getLinkedTooltip())
    return
  end

  if hoveredItem and _itemId == hoveredItem:getId() then
    hoveredItem.uid = _itemUId
    hoveredItem.name = _name
    hoveredItem.rarity = _itemRarity
    showTooltip(_itemUId)
  end
end

function resetData()
  cachedItems = {}
  hoveredItem = nil
  player = nil
  protocolGame = nil
  showingVirtual = nil
  hoveredLinked = nil
  tooltipWindow:hide()
end

function onHoverChange(widget, hovered)
  if not protocolGame then
    protocolGame = g_game.getProtocolGame()
  end
  
  if widget.getLinkedTooltip then
    hoveredLinked = widget
    if not widget.cached then
      if protocolGame then
        protocolGame:sendExtendedOpcode(CODE_TOOLTIPS, json.encode({widget.uid}))
      end
    else
      if hovered then
        showingVirtual = widget:getLinkedTooltip()
        buildItemTooltip(widget:getLinkedTooltip())
      else
        tooltipWindow:hide()
        showingVirtual = nil
      end
    end
    return
  end
  
  local item = widget:getItem()
  if item and widget.getItemTooltip then
    if hovered then
      buildItemTooltip(widget:getItemTooltip())
    else
      tooltipWindow:hide()
    end
    return
  end
  if not item or widget:getId() == "containerItemWidget" or widget:isVirtual() then
    return
  end

  if not player then
    player = g_game.getLocalPlayer()
  end

  if hovered then
    hoveredItem = item
    if protocolGame then
      local pos = item:getPosition()
      protocolGame:sendExtendedOpcode(CODE_TOOLTIPS, json.encode({pos.x, pos.y, pos.z, item:getStackPos()}))
    end
  else
    hoveredItem = nil
    tooltipWindow:hide()
  end
end

function showTooltip(uid)
  local cachedItem = cachedItems[uid]

  cachedItem.id = hoveredItem:getId()
  cachedItem.count = hoveredItem:getCount()

  buildItemTooltip(cachedItem)
end

function buildItemTooltip(item)
  tooltipWidth = 0
  longestString = 0
  tooltipWidthBase = BASE_WIDTH
  tooltipHeight = BASE_HEIGHT
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)

  labels:destroyChildren()

  local id = item.id
  local name = item.name
  local desc = item.desc
  local iLvl = item.iLvl
  local unidentified = item.unidentified
  local mirrored = item.mirrored
  local rarity = item.rarity + 1
  local maxAttributes = item.maxAttributes
  local attributes = item.attributes
  local count = item.count
  local type = item.type
  local first = item.first
  local second = item.second
  local third = item.third
  local weight = item.weight

  itemWeightLabel:setText(formatWeight(weight))

  itemSprite:setItemId(id)
  itemSprite:setItemCount(count)

  local itemNameColor
  if unidentified then
    itemNameColor = rarityColor[2].color
  elseif item.uniqueName then
    itemNameColor = "#dca01e"
  elseif rarity > 1 then
    itemNameColor = rarityColor[rarity].color
  else
    itemNameColor = "#ffffff"
  end

  name =
    name:gsub(
    "(%a)(%a+)",
    function(a, b)
      return string.upper(a) .. string.lower(b)
    end
  )
  if item.uLvl > 0 then
    name = name .. " +" .. item.uLvl
  end
  addString(name, itemNameColor)

  if unidentified then
    addString("Unidentified", rarityColor[2].color)
  else
    if item.uniqueName then
      addString(item.uniqueName, "#dca01e")
    elseif item.rarity ~= 0 then
      addString(rarityColor[rarity].name, rarityColor[rarity].color)
    end
  end

  if iLvl > 0 then
    addString("Item Level " .. iLvl, Colors.ItemLevel)
  end

  local firstText, secondText, thirdText
  if (type == "Armor" or type == "Helmet" or type == "Legs" or type == "Ring" or type == "Necklace" or type == "Boots") and first ~= 0 then
    firstText = "Armor: " .. first
  elseif
    type == "Two-Handed Sword" or type == "Two-Handed Club" or type == "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or type == "Fist" or
      type == "Distance" or
      type == "Ammunition"
   then
    firstText = "Attack: " .. first
  elseif type == "Shield" then
    firstText = "Defense: " .. second
  end

  if type == "Two-Handed Sword" or type == "Two-Handed Club" or type == "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or type == "Fist" then
    secondText = "Defense: " .. second
  elseif type == "Distance" then
    secondText = "Hit Chance: +" .. second .. "%"
  end

  if type == "Two-Handed Sword" or type == "Two-Handed Club" or type == "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or type == "Fist" then
    thirdText = "Extra-Defense: " .. third
  elseif type == "Distance" then
    thirdText = "Shoot Range: " .. third
  end

  if (firstText and (type == "Shield" or type == "Ring" or type == "Necklace")) or (first ~= 0 and second == 0 and third == 0) then
    addSeparator()
    addEmpty(5)
    addString(firstText, Colors.Default)
  elseif first ~= 0 and second ~= 0 and third == 0 then
    addSeparator()
    addEmpty(5)
    addString(firstText, Colors.Default)
    addString(secondText, Colors.Default)
  elseif first ~= 0 and second ~= 0 and third ~= 0 or type == "Distance" then
    addSeparator()
    addEmpty(5)
    addString(firstText, Colors.Default)
    addString(secondText, Colors.Default)
    addString(thirdText, Colors.Default)
  end

  if item.imp then
    if first ~= 0 or second ~= 0 or third ~= 0 or item.rarity ~= 0 then
      addSeparator()
      addEmpty(5)
    end

    for key, value in pairs(item.imp) do
      local impText
      if not implicits[key] then
        impText = value
      else
        impText = implicits[key] .. " " .. (value > 0 and "+" or "") .. value .. (impPercent[key] and "%" or "")
      end
      addString(impText, Colors.Implicit)
    end
  end

  if item.rarity ~= 0 then
    addSeparator()
    addEmpty(5)
    for i = 1, maxAttributes do
      addString(attributes[i], Colors.Attribute)
    end
  end

  if mirrored then
    addEmpty(5)
    addString("Mirrored", Colors.Mirrored)
  end

  if desc and desc:len() > 0 then
    addEmpty(5)
    addString(desc, Colors.Description, true)
  end

  shrinkSeparators()
  showItemTooltip()
end

function addString(text, color, resize)
  local label = g_ui.createWidget("TooltipLabel", labels)
  label:setColor(color)

  if resize then
    tooltipWindow:setWidth(tooltipWidth)
    label:setTextWrap(true)
    label:setTextAutoResize(true)
    label:setText(text)
    tooltipHeight = tooltipHeight + label:getTextSize().height + 4
  else
    label:setText(text)
    local textSize = label:getTextSize()
    if longestString == 0 then
      longestString = textSize.width + itemWeightLabel:getWidth()
      tooltipWidth = tooltipWidthBase + longestString
      label:addAnchor(AnchorTop, "parent", AnchorTop)
    elseif textSize.width > longestString then
      longestString = textSize.width
      tooltipWidth = tooltipWidthBase + longestString
    end
    tooltipHeight = tooltipHeight + textSize.height
  end
end

function shrinkSeparators()
  local children = labels:getChildren()
  local m = math.max(60, math.floor(tooltipWidth / 4))
  for _, child in ipairs(children) do
    if child:getStyleName() == "TooltipSeparator" then
      child:setMarginLeft(m)
      child:setMarginRight(m)
    end
  end
end

function addSeparator()
  local sep = g_ui.createWidget("TooltipSeparator", labels)
  tooltipHeight = tooltipHeight + sep:getHeight() + sep:getMarginTop() + sep:getMarginBottom()
end

function addEmpty(height)
  local empty = g_ui.createWidget("TooltipEmpty", labels)
  empty:setHeight(height)
  tooltipHeight = tooltipHeight + height
end

function showItemTooltip()
  local mousePos = g_window.getMousePosition()
  tooltipHeight = math.max(tooltipHeight, 40)
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)
  
  local windowSize = g_window.getSize()
  if mousePos.x > windowSize.width / 2 then
    tooltipWindow:move(mousePos.x - (tooltipWidth + 2), math.min(windowSize.height - tooltipHeight, mousePos.y + 5))
  else
    tooltipWindow:move(mousePos.x + 5, mousePos.y + 10)
  end
  tooltipWindow:raise()
  tooltipWindow:show()
  g_effects.fadeIn(tooltipWindow, 100)
end

function formatWeight(weight)
  local ss

  if weight < 10 then
    ss = "0.0" .. weight
  elseif weight < 100 then
    ss = "0." .. weight
  else
    local weightString = tostring(weight)
    local len = weightString:len()
    ss = weightString:sub(1, len - 2) .. "." .. weightString:sub(len - 1, len)
  end

  ss = ss .. " oz."
  return ss
end
