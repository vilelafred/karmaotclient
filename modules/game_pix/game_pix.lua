local acceptWindow = {}
statusUpdateEvent = nil
url = "http://72.62.11.29:8088/polopagapi.php"

local valores = { 30, 50, 100, 200, 300, 500, 800, 1000 }

local prices = {
  [30] = 250,
  [50] = 600,
  [100] = 1200,
  [200] = 2500,
  [300] = 5500,
  [500] = 14000,
  [800] = 26000,
  [1000] = 38000
}

function checkPayment(url, paymentId)
  if not g_game.isOnline() then
    removeEvent(statusUpdateEvent)
    return true
  end
  local function callback(data, err)
    if err then
      print("fale com a administra��o, Erro na solicita��o:", err)
    else
      -- print(data)
      if data == "true" then
        cancelDonate()
        removeEvent(statusUpdateEvent)
        sendCancelBox("Aviso",
          " Seu pagamento foi confirmado!\n muito obrigado pela sua doa��o, n�s sem voc�s\n n�o somos nada!")
      else
        qrCodeWindowPix.Loading:show()
        statusUpdateEvent = scheduleEvent(function() checkPayment(url, paymentId) end, 5000)
      end
    end
  end

  local postData = {
    ["payment_id"] = paymentId
  }

  HTTP.post(url, json.encode(postData), callback)
end

function returnQr(data, valor)
  --print(data)
  local data = json.decode(data)
  local base64 = data["qr_code_base64"]
  local copiaecola = data["qr_code"]
  local paymentId = data["payment_id"]
  local valor = data["valor"]
  local produto = data["pontos"]

  if not base64 or not paymentId or not data then
    sendCancelBox("Aviso", "Falha na transa��o, tente novamente mais tarde.\nErro: " .. data["error"])
    return true
  end

  qrCodeWindowPix.text:setText(tr('Ola %s.\nVoc� esta realizando uma doacao via Pix!\nValor: R$ %s\nLogin: %s',
    g_game.getCharacterName(), valor, G.account))
  qrCodeWindowPix.qrCode:setImageSourceBase64(base64)
  g_window.setClipboardText(copiaecola)
  qrCodeWindowPix.qrCodeEdit:setText(copiaecola)
  qrCodeWindowPix.qrCodeEdit:setEditable(false)

  checkPayment(url, paymentId)
  qrCodeWindowPix:show()
  qrCodeWindowPix:focus()
  qrCodeWindowPix:raise()
end

function sendPost(firstName, lastName, cpf, valor, playerAccount, playerCharacter)
  local playerAccount = G.account


  local postData = {
    ["nameAccount"] = playerAccount,
    ["valor"]       = valor,
    ["name"]        = firstName,
    ["lastname"]    = lastName,
    ["namePlayer"]  = g_game.getCharacterName()
  }

  local function callback(data, err)
    if err then
      print("fale com a administra��o, Erro na solicita��o:", err)
    else
      -- print(data)
      if data == "false" or not data then
        sendCancelBox("Aviso", "Falha na transa��o, tente novamente mais tarde.")
        return true
      end
      returnQr(data)
    end
  end
  --print(json.encode(postData))
  HTTP.post(url, json.encode(postData), callback)
end

function applyBonus(valor)
  return prices[valor] or 30
end

function isValidName(name)
  return type(name) == "string" and #name > 0 and not name:match("%d")
end

function isValidValue(value)
  return type(value) == "number" and value == value
end

function sendCancelBox(header, text)
  local cancelFunc = function()
    acceptWindow[#acceptWindow]:destroy()
    acceptWindow = {}
  end

  if #acceptWindow > 0 then
    acceptWindow[#acceptWindow]:destroy()
  end

  acceptWindow[#acceptWindow + 1] =
      displayGeneralBox(tr(header), tr(text),
        {
          { text = tr("OK"), callback = cancelFunc },
          anchor = AnchorHorizontalCenter
        }, cancelFunc)
end

function sendDonate()
  local firstName = mainWindow.firstNameText:getText()
  local lastName = mainWindow.lastNameText:getText()
  local valor = math.floor(tonumber(mainWindow.valueComboBox:getText())) or 0
  local playerAccount = G.account
  local playerCharacter = g_game.getCharacterName()

  if not isValidName(firstName) or not isValidName(lastName) then
    local header, text = "Aviso", "Voc� precisa digitar um nome v�lido."
    sendCancelBox(header, text)
    return true
  end

  if not isValidValue(valor) then
    local header, text = "Aviso", "Voc� precisa doar um valor minimo de 10 reais."
    sendCancelBox(header, text)
    return true
  end

  local acceptFunc = function()
    acceptWindow[#acceptWindow]:destroy()
    if statusUpdateEvent then
      removeEvent(statusUpdateEvent)
    end
    sendPost(firstName, lastName, cpf, valor, playerAccount, playerCharacter)
  end

  local cancelFunc = function()
    acceptWindow[#acceptWindow]:destroy()
    -- cancelDonate()
    acceptWindow = {}
  end

  if #acceptWindow > 0 then
    acceptWindow[#acceptWindow]:destroy()
  end

  acceptWindow[#acceptWindow + 1] = displayGeneralBox(tr("Tem certeza?"),
    tr(" Voc� deseja prosseguir com a doa��o?\n Valor doado: " ..
    valor .. "\n Pontos a serem recebidos: " .. applyBonus(valor)),
    {
      { text = tr("Sim"), callback = acceptFunc },
      { text = tr("N�o"), callback = cancelFunc },
      anchor = AnchorHorizontalCenter
    }, acceptFunc, cancelFunc)
end

function cancelDonate()
  qrCodeWindowPix:hide()
  mainWindow:hide()
end

function toggle()
  if mainWindow:isVisible() then
    mainWindow:hide()
    if statusUpdateEvent then
      cancelDonate()
      removeEvent(statusUpdateEvent)
    end
  else
    mainWindow:focus()
    mainWindow:raise()
    mainWindow:show()
  end
end

function init()
  mainWindow = g_ui.loadUI('game_pix', modules.game_interface.getRootPanel())
  qrCodeWindowPix = g_ui.displayUI('qrcodePix')
  qrCodeWindowPix:hide()
  mainWindow:hide()
  connect(g_game, {
    onGameStart = cancelDonate,
    onGameEnd = cancelDonate,
  })
  mainWindow.valueComboBox:clear()
  for i, value in pairs(valores) do
    mainWindow.valueComboBox:addOption(value)
  end
end

function terminate()
  mainWindow:destroy()
  qrCodeWindowPix:destroy()
  if #acceptWindow > 0 then
    acceptWindow[#acceptWindow]:destroy()
  end

  disconnect(g_game, {
    onGameStart = cancelDonate,
    onGameEnd = cancelDonate,
  })
end
