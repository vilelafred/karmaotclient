Decrypt_Name = "KarmaOT-DEV"
Encrypt_Name = "KarmaOT"
APP_VERSION = 1344       -- client version for updater and login to identify outdated client
DEFAULT_LAYOUT = "default" -- on android it's forced to "mobile", check code bellow
REGISTRATION_KEY = "AbcDeFgH"

-- servers shown in enter game list
SERVER_LIST = {
  {
    host = '72.62.11.29', -- login.karma-global.com quando DNS propagar
    name = "Karma",
    port = 7171,
    protocol = 772,
  },
}

-- If you don't use updater or other service, set it to updater = ""
Services = {
  website = "http://72.62.11.29:8088", -- https://karma-global.com quando DNS propagar
  guides = "http://72.62.11.29:8088/api/guides.json",
  updater = "http://72.62.11.29:8088/api/updater_advanced.php",
  stats = "",
  crash = "",
  feedback = "",
  status = "" -- Desabilitado para evitar erros 403
}

-- Servers accept http login url, websocket login url or ip:port:version
Servers = {
--[[  OTClientV8 = "http://otclient.ovh/api/login.php",
  OTClientV8proxy = "http://otclient.ovh/api/login.php?proxy=1",
  OTClientV8c = "otclient.ovh:7171:1099:25:30:80:90",
  OTClientV8Test = "http://otclient.ovh/api/login2.php",
  Evoulinia = "evolunia.net:7171:1098",
  GarneraTest = "garnera-global.net:7171:1100",
  LocalTestServ = "127.0.0.1:7171:1098:110:30:93"  ]]
}

--Server = "ws://otclient.ovh:3000/"
--Server = "ws://127.0.0.1:88/"
--USE_NEW_ENERGAME = true -- uses entergamev2 based on websockets instead of entergame
ALLOW_CUSTOM_SERVERS = false -- if true it shows option ANOTHER on server list

g_app.setName("KarmaOT")

-- CONFIG END

-- print first terminal message
g_logger.info(os.date("== application started at %b %d %Y %X"))
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' .. g_app.getBuildCommit() .. ') made by ' .. g_app.getAuthor() .. ' built on ' .. g_app.getBuildDate() .. ' for arch ' .. g_app.getBuildArch())

if g_resources.isOTCEncrypted() then
  local files = g_resources.listDirectoryFiles('/')
  for _,file in pairs(files) do
    if g_resources.isFileType(file, 'ini') then
      g_logger.fatal("O Client não pode ser iniciado!.")
  	return 0
    end
    if g_resources.isFileType(file, 'key') then
      g_logger.fatal("O Client não pode ser iniciado!.")
  	return 0
    end
    if g_resources.isFileType(file, 'spr') then
      g_logger.fatal("O Client não pode ser iniciado!.")
  	return 0
    end
    if g_resources.isFileType(file, 'dat') then
      g_logger.fatal("O Client não pode ser iniciado!.")
  	return 0
    end
    if g_resources.isFileType(file, 'dll') then
      if file ~= 'd3dcompiler_47.dll'
	  and file ~= 'libEGL.dll'
	  and file ~= 'libGLESv2.dll'
	  and file ~= 'Google.Apis.Auth.dll'
	  and file ~= 'Google.Apis.Core.dll'
	  and file ~= 'Google.Apis.dll'
	  and file ~= 'Google.Apis.Drive.v3.dll'
	  and file ~= 'LauncherUpdater.dll'
	  and file ~= 'Newtonsoft.Json.dll'
	  and file ~= 'System.Management.dll' then
        g_logger.fatal("O Client não pode ser iniciado!.")
  	  return 0
      end
    end
    if g_resources.isFileType(file, 'lua') then
      if file ~= 'init.lua' and file ~= 'otclientrc.lua' then
        g_logger.fatal("O Client não pode ser iniciado!.")
  	  return 0
      end
    end
  end
end

if not g_resources.directoryExists("/data") then
  g_logger.fatal("Data dir doesn't exist.")
end

if not g_resources.directoryExists("/modules") then
  g_logger.fatal("Modules dir doesn't exist.")
end

-- settings
g_configs.loadSettings("/config.otml")

-- set layout
local settings = g_configs.getSettings()
local layout = DEFAULT_LAYOUT
if g_app.isMobile() then
  layout = "mobile"
elseif settings:exists('layout') then
  layout = settings:getValue('layout')
end
g_resources.setLayout(layout)

-- load mods
g_modules.discoverModules()
g_modules.ensureModuleLoaded("corelib")
  
local function loadModules()
  -- libraries modules 0-99
  g_modules.autoLoadModules(99)
  g_modules.ensureModuleLoaded("gamelib")

  -- client modules 100-499
  g_modules.autoLoadModules(499)
  g_modules.ensureModuleLoaded("client")

  -- game modules 500-999
  g_modules.autoLoadModules(999)
  g_modules.ensureModuleLoaded("game_interface")

  -- mods 1000-9999
  g_modules.autoLoadModules(9999)
end

-- report crash
if type(Services.crash) == 'string' and Services.crash:len() > 4 and g_modules.getModule("crash_reporter") then
  g_modules.ensureModuleLoaded("crash_reporter")
end

-- run updater (requer data.zip montado; nao usar com pastas data/modules soltas)
if type(Services.updater) == 'string' and Services.updater:len() > 4
  and g_resources.isLoadedFromArchive() and g_modules.getModule("updater") then
  g_modules.ensureModuleLoaded("updater")
  return Updater.init(loadModules)
end
loadModules()
