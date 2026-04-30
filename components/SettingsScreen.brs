sub init()
    m.viewModeLabel = m.top.findNode("ViewModeValue")
    m.viewModeHighlight = m.top.findNode("ViewModeHighlight")
    m.transcodeServerLabel = m.top.findNode("TranscodeServerValue")
    m.transcodeServerHighlight = m.top.findNode("TranscodeServerHighlight")
    m.focusIndex = 0
    loadSettings()
    updateDisplay()
end sub

sub onVisibleChange()
    if m.top.visible then
        loadSettings()
        updateDisplay()
        m.top.setFocus(true)
    end if
end sub

sub loadSettings()
    registry = createObject("roRegistrySection", "KojoStream")
    if registry.exists("view_mode") then
        m.top.viewMode = registry.read("view_mode")
    else
        m.top.viewMode = "grouped"
    end if

    if registry.exists("transcode_server_url") then
        m.top.transcodeServerUrl = safeText(registry.read("transcode_server_url"))
    else
        m.top.transcodeServerUrl = ""
    end if
end sub

sub saveSettings()
    registry = createObject("roRegistrySection", "KojoStream")
    registry.write("view_mode", m.top.viewMode)
    registry.write("transcode_server_url", m.top.transcodeServerUrl)
    registry.flush()
end sub

sub updateDisplay()
    if m.top.viewMode = "grouped" then
        m.viewModeLabel.text = "Group by Category"
    else
        m.viewModeLabel.text = "Flat List"
    end if

    if m.top.transcodeServerUrl = "" then
        m.transcodeServerLabel.text = "Off"
    else
        m.transcodeServerLabel.text = m.top.transcodeServerUrl
    end if

    updateFocus()
end sub

sub updateFocus()
    m.viewModeHighlight.visible = (m.focusIndex = 0)
    m.transcodeServerHighlight.visible = (m.focusIndex = 1)
end sub

sub toggleViewMode()
    if m.top.viewMode = "grouped" then
        m.top.viewMode = "flat"
    else
        m.top.viewMode = "grouped"
    end if
    saveSettings()
    updateDisplay()
end sub

sub showTranscodeServerDialog()
    kb = createObject("roSGNode", "KeyboardDialog")
    if kb = invalid then return
    kb.title = "Transcode server URL"
    if m.top.transcodeServerUrl <> "" then
        kb.text = m.top.transcodeServerUrl
    else
        kb.text = "http://"
    end if
    kb.buttons = ["Save", "Off", "Cancel"]
    kb.observeField("buttonSelected", "onTranscodeDialogButton")
    m.top.getScene().dialog = kb
end sub

sub onTranscodeDialogButton()
    dialog = m.top.getScene().dialog
    if dialog = invalid then return

    if dialog.buttonSelected = 0 then
        url = safeText(dialog.text)
        if url = "http://" or url = "https://" then url = ""
        m.top.transcodeServerUrl = url
        saveSettings()
        updateDisplay()
    else if dialog.buttonSelected = 1 then
        m.top.transcodeServerUrl = ""
        saveSettings()
        updateDisplay()
    end if

    m.top.getScene().dialog = invalid
    m.top.setFocus(true)
end sub

function onKeyEvent(key, press) as boolean
    if not press then return false

    if key = "up" then
        m.focusIndex = m.focusIndex - 1
        if m.focusIndex < 0 then m.focusIndex = 1
        updateFocus()
        return true
    end if

    if key = "down" then
        m.focusIndex = m.focusIndex + 1
        if m.focusIndex > 1 then m.focusIndex = 0
        updateFocus()
        return true
    end if

    if key = "OK" then
        if m.focusIndex = 0 then
            toggleViewMode()
        else
            showTranscodeServerDialog()
        end if
        return true
    end if

    return false
end function

function safeText(value as dynamic) as string
    if value = invalid then return ""
    return value.toStr().Trim()
end function
