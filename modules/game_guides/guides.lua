local guidesWindow = nil
local guidesData = nil
local selectedEntry = nil
local selectedListItem = nil
local guideMinimap = nil
local currentTab = 'all'
local chatFilter = nil

local config = {
  apiUrl = nil,
  cacheFile = 'guides_cache.json',
  fallbackFile = '/modules/game_guides/data/guides_fallback.json',
}

local TAB_LABELS = {
  all = 'All Guides',
  quests = 'Quests',
  hunts = 'Hunts',
  systems = 'Systems',
  city = 'City Respawns',
  level = 'Hunts by Level',
  rewards = 'Level Rewards',
}

local TAB_BUTTONS = {
  all = 'tabAll',
  quests = 'tabQuests',
  hunts = 'tabHunts',
  systems = 'tabSystems',
  city = 'tabCity',
  level = 'tabLevel',
  rewards = 'tabRewards',
}

function init()
  if Services and Services.guides and Services.guides:len() > 0 then
    config.apiUrl = Services.guides
  else
    config.apiUrl = 'http://72.62.11.29:8088/api/guides.json'
  end

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  guidesWindow = g_ui.displayUI('guides')
  guidesWindow:hide()

  guideMinimap = guidesWindow:recursiveGetChildById('guideMinimap')
  if guideMinimap then
    if guideMinimap.setup then
      guideMinimap:setup()
    end
    if not guideMinimap.flags then
      guideMinimap.flags = {}
    end
    guideMinimap:disableAutoWalk()
  end

  setupSearch()
  setupListSelection()
  g_keyboard.bindKeyDown('Ctrl+G', toggle)

  if modules.client_terminal and modules.client_terminal.addCommand then
    modules.client_terminal.addCommand({
      name = 'guide',
      aliases = { 'guides', 'ng' },
      description = 'Open New Player Guide',
      usage = 'guide',
      callback = function()
        toggle()
        return true
      end
    })
  end

  if modules.game_console and modules.game_console.addFilter then
    chatFilter = function(message)
      local cmd = message:trim():lower()
      if cmd == '!guide' or cmd == '!guides' then
        toggle()
        return true
      end
      return false
    end
    modules.game_console.addFilter(chatFilter)
  end

  loadGuidesData(false)

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  g_keyboard.unbindKeyDown('Ctrl+G', toggle)

  if chatFilter and modules.game_console and modules.game_console.removeFilter then
    modules.game_console.removeFilter(chatFilter)
    chatFilter = nil
  end

  if guidesWindow then
    guidesWindow:destroy()
    guidesWindow = nil
  end
end

function online()
  fetchFromApi(false)
end

function offline()
  hide()
end

function toggle()
  if not guidesWindow then return end
  if guidesWindow:isVisible() then
    hide()
  else
    show()
  end
end

function show()
  if not guidesWindow then return end
  if not guidesData then
    loadGuidesData(false)
  end
  updateIntro()
  selectTab(currentTab)
  guidesWindow:show()
  guidesWindow:raise()
  guidesWindow:focus()
end

function hide()
  if guidesWindow then
    guidesWindow:hide()
  end
end

function setupSearch()
  local searchEdit = guidesWindow:recursiveGetChildById('searchEdit')
  if not searchEdit then return end
  connect(searchEdit, { onTextChange = refreshList })
end

function setupListSelection()
  local list = guidesWindow:recursiveGetChildById('guideList')
  if not list then return end
  connect(list, {
    onChildFocusChange = function(self, focusedChild)
      if focusedChild and focusedChild.entryData then
        selectEntry(focusedChild.entryData, focusedChild)
      end
    end
  })
end

function getCachePath()
  if modules.client_profiles and modules.client_profiles.getSettingsFilePath then
    return modules.client_profiles.getSettingsFilePath(config.cacheFile)
  end
  return config.cacheFile
end

function setStatus(text, color)
  local label = guidesWindow and guidesWindow:recursiveGetChildById('statusLabel')
  if label then
    label:setText(text or '')
    if color then
      label:setColor(color)
    end
  end
end

function updateIntro()
  local intro = guidesWindow and guidesWindow:recursiveGetChildById('introLabel')
  if intro and guidesData and guidesData.intro then
    intro:setText(guidesData.intro)
  end
end

function updateListTitle()
  local title = guidesWindow and guidesWindow:recursiveGetChildById('listTitle')
  if title then
    title:setText(TAB_LABELS[currentTab] or 'Guides')
  end
end

function loadFromFile(path)
  if not g_resources.fileExists(path) then
    return nil
  end
  local ok, data = pcall(function()
    return json.decode(g_resources.readFileContents(path))
  end)
  if ok and type(data) == 'table' then
    return data
  end
  return nil
end

function saveCache(data)
  local path = getCachePath()
  local ok, encoded = pcall(function() return json.encode(data, 2) end)
  if not ok then return end
  g_resources.writeFileContents(path, encoded)
end

function loadGuidesData(fromNetwork)
  local cache = loadFromFile(getCachePath())
  if cache then
    guidesData = cache
    setStatus('Loaded from cache', '#AAAAAA')
    updateIntro()
    refreshList()
    return true
  end

  local fallback = loadFromFile(config.fallbackFile)
  if fallback then
    guidesData = fallback
    setStatus('Loaded bundled guide data', '#AAAAAA')
    updateIntro()
    refreshList()
    return true
  end

  setStatus('No guide data available', '#FF6666')
  return false
end

function fetchFromApi(manual)
  if not config.apiUrl or config.apiUrl:len() == 0 then
    loadGuidesData(false)
    return
  end

  setStatus(manual and 'Refreshing...' or 'Updating guides...', '#AAAAAA')

  HTTP.getJSON(config.apiUrl, function(data, err)
    if err or type(data) ~= 'table' then
      if not guidesData then
        loadGuidesData(false)
      end
      setStatus('API unavailable — using cached data', '#FFAA00')
      if manual then
        modules.game_textmessage.displayFailureMessage('Could not refresh guides: ' .. (err or 'invalid response'))
      end
      return
    end

    guidesData = data
    saveCache(data)
    setStatus('Updated from server', '#66FF66')
    updateIntro()
    refreshList()
    if manual then
      modules.game_textmessage.displayGameMessage('Guides updated successfully.')
    end
  end)
end

function getBaseUrl()
  if guidesData and guidesData.baseUrl and guidesData.baseUrl:len() > 0 then
    return guidesData.baseUrl:gsub('/+$', '')
  end
  if Services and Services.website and Services.website:len() > 0 then
    return Services.website:gsub('/+$', '')
  end
  return 'http://72.62.11.29:8088'
end

function resolveUrl(url)
  if not url or url:len() == 0 then
    return nil
  end
  if url:find('^https?://') then
    return url
  end
  local base = getBaseUrl()
  if url:sub(1, 1) == '/' then
    return base .. url
  end
  return base .. '/' .. url
end

function selectTab(tab)
  currentTab = tab or 'all'
  highlightTabs()
  updateListTitle()
  clearSelection()
  refreshList()
end

function highlightTabs()
  for key, id in pairs(TAB_BUTTONS) do
    local btn = guidesWindow:recursiveGetChildById(id)
    if btn then
      if key == currentTab then
        btn:setColor('#FFAA00')
      else
        btn:setColor('#FFFFFF')
      end
    end
  end
end

function getSearchText()
  local searchEdit = guidesWindow:recursiveGetChildById('searchEdit')
  if not searchEdit then return '' end
  return (searchEdit:getText() or ''):lower()
end

function matchesSearch(text, query)
  if not query or query:len() == 0 then return true end
  return text and text:lower():find(query, 1, true) ~= nil
end

function guideMatchesTab(guideType)
  if currentTab == 'all' then return true end
  if currentTab == 'quests' then return guideType == 'Quest' end
  if currentTab == 'hunts' then return guideType == 'Hunt' end
  if currentTab == 'systems' then return guideType == 'System' end
  return false
end

function buildEntries()
  if not guidesData then return {} end

  local entries = {}
  local query = getSearchText()

  if currentTab == 'all' or currentTab == 'quests' or currentTab == 'hunts' or currentTab == 'systems' then
    for _, guide in ipairs(guidesData.guides or {}) do
      local guideType = guide.type or ''
      if guideMatchesTab(guideType) and matchesSearch(guide.name or '', query) then
        table.insert(entries, {
          kind = 'guide',
          name = guide.name or '',
          type = guideType,
          level = guide.level,
          summary = guide.summary,
          pageUrl = guide.pageUrl,
          videoUrl = guide.videoUrl,
          location = guide.location,
        })
      end
    end
  elseif currentTab == 'city' then
    for _, city in ipairs(guidesData.cityHunts or {}) do
      local label = city.city or ''
      if matchesSearch(label, query) then
        table.insert(entries, {
          kind = 'city',
          name = label,
          type = 'City',
          level = nil,
          summary = city.summary,
          pageUrl = city.pageUrl,
          videoUrl = nil,
          location = city.location,
        })
      end
    end
  elseif currentTab == 'level' then
    for _, hunt in ipairs(guidesData.levelHunts or {}) do
      local label = hunt.name or ''
      if matchesSearch(label, query) or matchesSearch(hunt.level or '', query) then
        table.insert(entries, {
          kind = 'level',
          name = label,
          type = 'Hunt',
          level = hunt.level,
          summary = hunt.summary,
          pageUrl = hunt.pageUrl,
          videoUrl = nil,
          location = hunt.location,
        })
      end
    end
  elseif currentTab == 'rewards' then
    local rewards = guidesData.levelRewards or {}
    table.insert(entries, {
      kind = 'rewards',
      name = rewards.title or 'Level Rewards',
      type = 'System',
      level = nil,
      summary = rewards.description or guidesData.intro,
      pageUrl = rewards.pageUrl,
      videoUrl = nil,
    })
  end

  return entries
end

function clearSelection()
  selectedEntry = nil
  if selectedListItem then
    selectedListItem:setOn(false)
    selectedListItem = nil
  end
  updateDetailPanel()
end

function parseGuidePosition(loc)
  if not loc then return nil end
  local x = math.floor(tonumber(loc.x) or -1)
  local y = math.floor(tonumber(loc.y) or -1)
  local z = math.floor(tonumber(loc.z) or -1)
  if x < 0 or y < 0 or z < 0 then return nil end
  return { x = x, y = y, z = z }
end

function renderGuideMinimap(pos, label, attempt)
  if not guideMinimap or not pos then return end
  attempt = attempt or 1

  local ok, err = pcall(function()
    if guideMinimap:getZoom() ~= 0 then
      guideMinimap:setZoom(0)
    end
    guideMinimap:setCameraPosition(pos)
    guideMinimap:addFlag(pos, 3, label, true)
  end)

  if not ok and attempt < 8 then
    scheduleEvent(function()
      renderGuideMinimap(pos, label, attempt + 1)
    end, 50)
  elseif not ok then
    g_logger.warning('[game_guides] minimap render failed: ' .. tostring(err))
  end
end

function clearGuideMap()
  if not guideMinimap or not guideMinimap.flags then return end
  for i = #guideMinimap.flags, 1, -1 do
    local flag = guideMinimap.flags[i]
    if flag and flag.temporary then
      flag:destroy()
    end
  end
end

function showGuideLocation(entry)
  if not guidesWindow then return end

  local mapPanel = guidesWindow:recursiveGetChildById('mapPanel')
  local noCoordsPanel = guidesWindow:recursiveGetChildById('noCoordsPanel')
  local coordsLabel = guidesWindow:recursiveGetChildById('coordsLabel')

  clearGuideMap()

  if not entry or not entry.location or not entry.location.x then
    if mapPanel then mapPanel:hide() end
    if coordsLabel then
      coordsLabel:setText('')
      coordsLabel:hide()
    end
    if noCoordsPanel then noCoordsPanel:show() end
    return
  end

  if noCoordsPanel then noCoordsPanel:hide() end
  if mapPanel then mapPanel:show() end
  if coordsLabel then coordsLabel:show() end

  local loc = entry.location
  local pos = parseGuidePosition(loc)
  local label = loc.label or entry.name or 'Location'

  if coordsLabel and pos then
    coordsLabel:setText(string.format('%s — %d, %d, %d', label, pos.x, pos.y, pos.z))
  end

  if guideMinimap and pos then
    guideMinimap:setVisible(true)
    scheduleEvent(function()
      renderGuideMinimap(pos, label)
    end, 50)
  end
end

function refreshList()
  if not guidesWindow then return end

  local list = guidesWindow:recursiveGetChildById('guideList')
  if not list then return end

  list:destroyChildren()
  selectedListItem = nil

  local entries = buildEntries()
  for index, entry in ipairs(entries) do
    local item = g_ui.createWidget('GuideTableRow', list)
    item.entryIndex = index
    item.entryData = entry

    local nameLabel = item:getChildById('nameLabel')
    local typeLabel = item:getChildById('typeLabel')
    local levelLabel = item:getChildById('levelLabel')

    if nameLabel then nameLabel:setText(entry.name) end
    if typeLabel then typeLabel:setText(entry.type or '') end
    if levelLabel then levelLabel:setText(entry.level or '-') end

    item.onMouseRelease = function(widget, mousePos, mouseButton)
      if mouseButton == MouseLeftButton then
        selectEntry(widget.entryData, widget)
        return true
      end
      return false
    end
  end

  if #entries == 0 then
    setStatus('No entries match your search', '#FFAA00')
  else
    setStatus(string.format('%d entries in %s', #entries, TAB_LABELS[currentTab] or 'Guides'), '#AAAAAA')
  end
end

function selectEntry(entry, widget)
  selectedEntry = entry
  if selectedListItem and selectedListItem ~= widget then
    selectedListItem:setOn(false)
  end
  selectedListItem = widget
  if selectedListItem then
    selectedListItem:setOn(true)
    selectedListItem:focus()
  end
  updateDetailPanel()
end

function updateDetailPanel()
  local title = guidesWindow:recursiveGetChildById('detailTitle')
  local meta = guidesWindow:recursiveGetChildById('detailMeta')
  local summary = guidesWindow:recursiveGetChildById('detailSummary')
  local pageBtn = guidesWindow:recursiveGetChildById('openPageButton')
  local videoBtn = guidesWindow:recursiveGetChildById('openVideoButton')

  if not selectedEntry then
    if title then title:setText('Select an entry') end
    if meta then meta:setText('') end
    if summary then summary:setText('Browse the list and click an entry to see details here.') end
    if pageBtn then pageBtn:setEnabled(false) end
    if videoBtn then videoBtn:setEnabled(false) end
    showGuideLocation(nil)
    return
  end

  if title then title:setText(selectedEntry.name or '') end

  local metaParts = {}
  if selectedEntry.type and selectedEntry.type:len() > 0 then
    table.insert(metaParts, selectedEntry.type)
  end
  if selectedEntry.level and tostring(selectedEntry.level):len() > 0 then
    table.insert(metaParts, 'Level ' .. tostring(selectedEntry.level))
  end
  if meta then meta:setText(table.concat(metaParts, ' • ')) end
  if summary then summary:setText(selectedEntry.summary or 'No summary available.') end

  if pageBtn then
    pageBtn:setEnabled(selectedEntry.pageUrl ~= nil and selectedEntry.pageUrl:len() > 0)
  end
  if videoBtn then
    videoBtn:setEnabled(selectedEntry.videoUrl ~= nil and selectedEntry.videoUrl:len() > 0)
  end

  showGuideLocation(selectedEntry)
end

function openSelectedPage()
  if not selectedEntry or not selectedEntry.pageUrl then return end
  local url = resolveUrl(selectedEntry.pageUrl)
  if url then
    g_platform.openUrl(url)
  end
end

function openSelectedVideo()
  if not selectedEntry or not selectedEntry.videoUrl then return end
  local url = resolveUrl(selectedEntry.videoUrl)
  if url then
    g_platform.openUrl(url)
  end
end
