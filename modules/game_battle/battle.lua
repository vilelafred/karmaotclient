battleWindow = nil
battlePanel = nil
filterPanel = nil
toggleFilterButton = nil

mouseWidget = nil
updateEvent = nil

hoveredCreature = nil
newHoveredCreature = nil
prevCreature = nil
draggedBattleWindow = false
battleButtons = {}

-- At the top of the file with other globals
local ageNumber = 1
local ages = {}

function init()  
  g_ui.importStyle('battlebutton')

  battleWindow = g_ui.loadUI('battle', modules.game_interface.getRightPanel())
  g_keyboard.bindKeyDown('Ctrl+B', toggle)

  -- Disable scrollbar auto-hiding
  local scrollbar = battleWindow:getChildById('miniwindowScrollBar')
  scrollbar:mergeStyle({ ['$!on'] = { }})

  battlePanel = battleWindow:recursiveGetChildById('battlePanel')
  filterPanel = battleWindow:recursiveGetChildById('filterPanel')
  toggleFilterButton = battleWindow:recursiveGetChildById('toggleFilterButton')

  --local extendButton = battleWindow:recursiveGetChildById('extendButton')
  --extendButton:setVisible(true)

  local sortTypeBox = filterPanel.sortPanel.sortTypeBox
  local sortOrderBox = filterPanel.sortPanel.sortOrderBox

  mouseWidget = g_ui.createWidget('UIButton')
  mouseWidget:setVisible(false)
  mouseWidget:setFocusable(false)
  mouseWidget.cancelNextRelease = false

  battleWindow:setup()
  battleWindow:setContentMinimumHeight(105)
  --modules.game_sidebuttons.toggleButton('battle', not battleWindow:getSettings('closed'))

  battleWindow.onMouseMove = onBattleWindowMove
  battleWindow.onMousePress = onBattleWindowMousePress
  
  -- Add the filter options to the combobox
  sortTypeBox:addOption('Name', 'name')
  sortTypeBox:addOption('Distance', 'distance')
  sortTypeBox:addOption('Total age', 'age')
  sortTypeBox:addOption('Screen age', 'screenage')
  sortTypeBox:addOption('Health', 'health')
  sortTypeBox:setCurrentOptionByData(getSortType())
  sortTypeBox.onOptionChange = onChangeSortType

  sortOrderBox:addOption('Asc.', 'asc')
  sortOrderBox:addOption('Desc.', 'desc')
  sortOrderBox:setCurrentOptionByData(getSortOrder())
  sortOrderBox.onOptionChange = onChangeSortOrder

  for i = 1, 45 do
    local battleButton = g_ui.createWidget('BattleButton', battlePanel)
    battleButton:setup()
    battleButton:hide()
    battleButton.onHoverChange = onBattleButtonHoverChange
    battleButton.onMouseRelease = onBattleButtonMouseRelease
    battleButton.onWidgetHide = onBattleCreatureDisappear
    table.insert(battleButtons, battleButton)
  end
  
  updateBattleList()
  
  connect(LocalPlayer, {
    onPositionChange = onPlayerPositionChange
  })
  connect(Creature, {
    onAppear = updateSquare,
    onDisappear = updateSquare
  })  
  connect(g_game, { 
    onAttackingCreatureChange = updateSquare,
    onFollowingCreatureChange = updateSquare 
  })
end

function terminate()
  if battleButton == nil then
    return
  end
  
  battleButtons = {}
  
  g_keyboard.unbindKeyDown('Ctrl+B')
  battleWindow:destroy()
  mouseWidget:destroy()
	
  disconnect(LocalPlayer, {
    onPositionChange = onPlayerPositionChange
  })
  disconnect(Creature, {
    onAppear = onCreatureAppear,
    onDisappear = onCreatureDisappear
  })  
  disconnect(g_game, { 
    onAttackingCreatureChange = updateSquare,
    onFollowingCreatureChange = updateSquare 
  })

  removeEvent(updateEvent)
end

function toggle()
  if modules.game_sidebuttons.battleButton:isOn() then
    battleWindow:close()
    modules.game_sidebuttons.battleButton:setOn(false)
  else
    battleWindow:open()
    modules.game_sidebuttons.battleButton:setOn(true)
  end
end

function getSortType()
  local settings = g_settings.getNode('BattleList')
  if not settings then
    if g_app.isMobile() then
      return 'distance'
    else
      return 'name'
    end
  end
  return settings['sortType']
end

function setSortType(state)
  settings = {}
  settings['sortType'] = state
  g_settings.mergeNode('BattleList', settings)

  checkCreatures()
end

function getSortOrder()
  local settings = g_settings.getNode('BattleList')
  if not settings then
    return 'asc'
  end
  return settings['sortOrder']
end

function setSortOrder(state)
  settings = {}
  settings['sortOrder'] = state
  g_settings.mergeNode('BattleList', settings)

  checkCreatures()
end

function isSortAsc()
    return getSortOrder() == 'asc'
end

function isSortDesc()
    return getSortOrder() == 'desc'
end

function onMiniWindowClose()
  modules.game_sidebuttons.battleButton:setOn(false)
end

-- functions
function updateBattleList() 
  removeEvent(updateEvent)
  updateEvent = scheduleEvent(updateBattleList, 100)
  checkCreatures()
end

function checkCreatures()
  if not battlePanel or not g_game.isOnline() then
    return
  end

  local player = g_game.getLocalPlayer()
  if not player then
    return
  end
  
  local dimension = modules.game_interface.getMapPanel():getVisibleDimension()
  if not player:getPosition() then
	return
  end
  local spectators = g_map.getSpectatorsInRangeEx(player:getPosition(), false, math.floor(dimension.width / 2), math.floor(dimension.width / 2), math.floor(dimension.height / 2), math.floor(dimension.height / 2))
  local maxCreatures = battlePanel:getChildCount()
  
  local creatures = {}
  local now = g_clock.millis()
  local resetAgePoint = now - 250
  for _, creature in ipairs(spectators) do
    if doCreatureFitFilters(creature) and #creatures < maxCreatures then
      if not creature.lastSeen or creature.lastSeen < resetAgePoint then
        creature.screenAge = now
        now = now + 1	
      end      
      creature.lastSeen = now
      now = now + 2
      
      -- Track total age
      if not ages[creature:getId()] then
        if ageNumber > 1000 then
          ageNumber = 1
          ages = {}
        end
        ages[creature:getId()] = ageNumber
        ageNumber = ageNumber + 1
      end
      
      table.insert(creatures, creature)	
    end
  end
  
  updateSquare()
  sortCreatures(creatures)
  battlePanel:getLayout():disableUpdates()
  
  for i = 1, #creatures do  
    local creature = creatures[i]
    local battleButton = battleButtons[i]      
    battleButton:creatureSetup(creature)
    battleButton:show()
    battleButton:setOn(true)
  end
  
  for i = #creatures + 1, maxCreatures do
    if battleButtons[i]:isHidden() then break end
    battleButtons[i]:hide()
  end

  battlePanel:getLayout():enableUpdates()
  battlePanel:getLayout():update()
end

function doCreatureFitFilters(creature)
  if creature:isLocalPlayer() then
    return false
  end
  if creature:getHealthPercent() <= 0 then
    return false
  end

  local pos = creature:getPosition()
  if not pos then return false end

  local localPlayer = g_game.getLocalPlayer()
  if pos.z ~= localPlayer:getPosition().z or not creature:canBeSeen() then return false end

  local hidePlayers = filterPanel.buttons.hidePlayers:isChecked()
  local hideNPCs = filterPanel.buttons.hideNPCs:isChecked()
  local hideMonsters = filterPanel.buttons.hideMonsters:isChecked()
  local hideSkulls = filterPanel.buttons.hideSkulls:isChecked()
  local hideParty = filterPanel.buttons.hideParty:isChecked()

  if hidePlayers and creature:isPlayer() then
    return false
  elseif hideNPCs and creature:isNpc() then
    return false
  elseif hideMonsters and creature:isMonster() then
    return false
  elseif hideSkulls and creature:isPlayer() and creature:getSkull() == SkullNone then
    return false
  elseif hideParty and creature:getShield() > ShieldWhiteBlue then
    return false
  end

  return true
end

local function getDistanceBetween(p1, p2)
    return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

function sortCreatures(creatures)
  local playerPos = g_game.getLocalPlayer():getPosition()
  local sortOrder = getSortOrder()
  local sortType = getSortType()

  table.sort(creatures, function(a, b)
    -- Fixed name comparison function for secondary sorting
    local function compareNames(a, b)
      local aName = a:getName():lower()
      local bName = b:getName():lower()
      if sortOrder == 'desc' then
        return aName > bName  -- For Z->A
      else
        return aName < bName  -- For A->Z
      end
    end

    if sortType == 'name' then
      return compareNames(a, b)
    elseif sortType == 'distance' then
      local aDist = getDistanceBetween(playerPos, a:getPosition())
      local bDist = getDistanceBetween(playerPos, b:getPosition())
      if aDist == bDist then
        return compareNames(a, b)
      end
      if sortOrder == 'desc' then
        return aDist > bDist  -- Furthest first
      else
        return aDist < bDist  -- Closest first
      end
    elseif sortType == 'health' then
      local aHealth = a:getHealthPercent()
      local bHealth = b:getHealthPercent()
      
      if aHealth == bHealth then
        return compareNames(a, b)
      end
      
      if sortOrder == 'desc' then
        return aHealth > bHealth  -- Highest health first
      else
        return aHealth < bHealth  -- Lowest health first
      end
    elseif sortType == 'screenage' then
      local aAge = a.screenAge or 0
      local bAge = b.screenAge or 0
      if aAge == bAge then
        return compareNames(a, b)
      end
      if sortOrder == 'desc' then
        return aAge < bAge  -- Oldest on screen first (lower numbers)
      else
        return aAge > bAge  -- Newest on screen first (higher numbers)
      end
    elseif sortType == 'age' then
      local aAge = ages[a:getId()] or 0
      local bAge = ages[b:getId()] or 0
      if aAge == bAge then
        return compareNames(a, b)
      end
      if sortOrder == 'desc' then
        return aAge < bAge  -- Oldest first (lower numbers)
      else
        return aAge > bAge  -- Newest first (higher numbers)
      end
    end
    
    return compareNames(a, b)
  end)
end

function onBattleWindowMove(self, mousePosition, mouseButton)
  if not (g_mouse.isPressed(MouseLeftButton)) then
    return 
  end
  draggedBattleWindow = false
  if self:isDragging() then
    draggedBattleWindow = true
  end
  return true
end

function onBattleWindowMousePress(self, mousePosition, mouseButton)
  if draggedBattleWindow then
    draggedBattleWindow = false
  end
  return true
end

function onBattleButtonMouseRelease(self, mousePosition, mouseButton)
  self = self:getParent():getChildByPos(mousePosition)
  if not self then
    return false
  end
  if draggedBattleWindow then
    draggedBattleWindow = false
    return false
  end
  if mouseWidget.cancelNextRelease then
    mouseWidget.cancelNextRelease = false
    return false
  end
  if not self.creature then
    return false
  end
  if ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton)
    or (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
    mouseWidget.cancelNextRelease = true
    g_game.look(self.creature, true)
    return true
  elseif mouseButton == MouseLeftButton and g_keyboard.isShiftPressed() then
    g_game.look(self.creature, true)
    return true
  elseif mouseButton == MouseRightButton and not g_mouse.isPressed(MouseLeftButton) then
    modules.game_interface.createThingMenu(mousePosition, nil, nil, self.creature)
    return true
  elseif mouseButton == MouseLeftButton and not g_mouse.isPressed(MouseRightButton) then
    if self.isTarget then
      g_game.cancelAttack()
    else
      g_game.attack(self.creature)
    end
    return true
  end
  return false
end

function onBattleButtonHoverChange(battleButton, hovered)
  if not hovered then
    newHoveredCreature = nil    
  else
    newHoveredCreature = battleButton.creature
  end
  if battleButton.isHovered ~= hovered then
    battleButton.isHovered = hovered
    battleButton:update()
  end
  updateSquare()
end

function onPlayerPositionChange(creature, newPos, oldPos)
  addEvent(checkCreatures)
end

local CreatureButtonColors = {
  onIdle = {notHovered = '#afafaf', hovered = '#f7f7f7' },
  onTargeted = {notHovered = '#df3f3f', hovered = '#f7a3a3' },
  onFollowed = {notHovered = '#3fdf3f', hovered = '#b3f7b3' }
}

function updateSquare()
  local following = g_game.getFollowingCreature()
  local attacking = g_game.getAttackingCreature()
    
  if newHoveredCreature == nil then
    if hoveredCreature ~= nil then
      hoveredCreature:hideStaticSquare()
      hoveredCreature = nil
    end
  else
    if hoveredCreature ~= nil then
      hoveredCreature:hideStaticSquare()
    end
    hoveredCreature = newHoveredCreature
    hoveredCreature:showStaticSquare(CreatureButtonColors.onIdle.hovered)
  end
  
  local color = CreatureButtonColors.onIdle
  local creature = nil
  if attacking then
    color = CreatureButtonColors.onTargeted
    creature = attacking
  elseif following then
    color = CreatureButtonColors.onFollowed
    creature = following
  end

  if prevCreature ~= creature then
    if prevCreature ~= nil then
      prevCreature:hideStaticSquare()
    end
    prevCreature = creature
  end
  
  if not creature then
    return
  end
  
  color = creature == hoveredCreature and color.hovered or color.notHovered
  creature:showStaticSquare(color)
end

function onBattleCreatureDisappear(battleButton)
  local mousePos = g_window.getMousePosition()
  local hoveredWidget = battleButton:getParent():getChildByPos(mousePos)
  if hoveredWidget and hoveredWidget.creature ~= newHoveredCreature then
    newHoveredCreature = hoveredWidget.creature
  elseif not hoveredWidget then
    newHoveredCreature = nil
  end
  updateSquare()
end

function toggleFilterPanel()
  if filterPanel:isVisible() then
    hideFilterPanel()
  else
    showFilterPanel()
  end
end

function hideFilterPanel()
  filterPanel.originalHeight = filterPanel:getHeight()
  filterPanel:setHeight(0)
  filterPanel:setMarginTop(10)
  toggleFilterButton:getParent():setMarginTop(0)
  toggleFilterButton:setImageClip(torect("0 0 21 12"))
  setHidingFilters(true)
  filterPanel:setVisible(false)
end

function showFilterPanel()
  toggleFilterButton:getParent():setMarginTop(5)
  filterPanel:setHeight(filterPanel.originalHeight)
  filterPanel:setMarginTop(26)
  toggleFilterButton:setImageClip(torect("21 0 21 12"))
  setHidingFilters(false)
  filterPanel:setVisible(true)
end

function isHidingFilters()
  local settings = g_settings.getNode('BattleList')
  if not settings then
    return false
  end
  return settings['hidingFilters']
end

function setHidingFilters(state)
  settings = {}
  settings['hidingFilters'] = state
  g_settings.mergeNode('BattleList', settings)
end

function onChangeSortType(comboBox, option, value)
  setSortType(value:lower())
end

function onChangeSortOrder(comboBox, option, value)
  setSortOrder(value:lower():gsub('[.]', ''))
end