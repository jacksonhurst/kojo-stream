sub init()
    m.playlistList = m.top.findNode("PlaylistList")
    m.emptyLabel = m.top.findNode("EmptyLabel")
    m.playlists = []
    m.focusIndex = 0
    m.allowXmltvClear = false
    m.xmltvClearUrl = ""
    loadPlaylists()
    refreshList()
end sub

sub onVisibleChange()
    if m.top.visible then
        loadPlaylists()
        refreshList()
        if m.playlists.count() > 0
            m.playlistList.setFocus(true)
        else
            m.top.setFocus(true)
        end if
    end if
end sub

sub loadPlaylists()
    registry = createObject("roRegistrySection", "KojoStream")
    if registry.exists("kojostream_playlists") then
        jsonStr = registry.read("kojostream_playlists")
        if jsonStr <> invalid and jsonStr <> "" then
            parsed = parseJSON(jsonStr)
            if parsed <> invalid and type(parsed) = "roArray" then
                m.playlists = parsed
                print "Loaded playlists from registry: "; m.playlists.count()
                return
            end if
        end if
    end if
    m.playlists = []
end sub

sub savePlaylists()
    preserveExistingXmltvUrls()
    registry = createObject("roRegistrySection", "KojoStream")
    jsonStr = formatJSON(m.playlists)
    registry.write("kojostream_playlists", jsonStr)
    registry.flush()
    m.allowXmltvClear = false
    m.xmltvClearUrl = ""
end sub

sub preserveExistingXmltvUrls()
    registry = createObject("roRegistrySection", "KojoStream")
    if not registry.exists("kojostream_playlists") then return

    existingJson = registry.read("kojostream_playlists")
    if existingJson = invalid or existingJson = "" then return

    existingPlaylists = parseJSON(existingJson)
    if existingPlaylists = invalid or type(existingPlaylists) <> "roArray" then return

    lastUsedUrl = ""
    lastXmltvUrl = ""
    if registry.exists("last_used_url") then lastUsedUrl = safeText(registry.read("last_used_url"))
    if registry.exists("last_xmltv_url") then lastXmltvUrl = safeText(registry.read("last_xmltv_url"))

    for i = 0 to m.playlists.count() - 1
        pl = normalizePlaylistEntry(m.playlists[i], i)
        shouldPreserveXmltv = true
        if m.allowXmltvClear and pl.url = m.xmltvClearUrl then shouldPreserveXmltv = false
        if pl.xmltvUrl = "" and shouldPreserveXmltv then
            recovered = lookupXmltvForPlaylist(existingPlaylists, pl.url)
            if recovered = "" and pl.url <> "" and pl.url = lastUsedUrl then recovered = lastXmltvUrl
            if recovered <> "" then pl.xmltvUrl = recovered
        end if
        m.playlists[i] = pl
    end for
end sub

function lookupXmltvForPlaylist(playlists as object, playlistUrl as string) as string
    targetUrl = safeText(playlistUrl)
    if targetUrl = "" or playlists = invalid then return ""

    for each entry in playlists
        pl = normalizePlaylistEntry(entry, 0)
        if pl.url = targetUrl and pl.xmltvUrl <> "" then return pl.xmltvUrl
    end for

    return ""
end function

sub refreshList()
    content = createObject("roSGNode", "ContentNode")
    for i = 0 to m.playlists.count() - 1
        pl = normalizePlaylistEntry(m.playlists[i], i)
        m.playlists[i] = pl
        item = createObject("roSGNode", "ContentNode")
        item.addField("displayName", "string", true)
        item.displayName = pl.name
        item.addField("playlistUrl", "string", true)
        item.playlistUrl = pl.url
        item.addField("xmltvUrl", "string", true)
        item.xmltvUrl = pl.xmltvUrl
        item.title = pl.name
        item.description = pl.url
        content.appendChild(item)
    end for
    m.playlistList.content = content

    if m.playlists.count() = 0 then
        m.playlistList.visible = false
        m.emptyLabel.visible = true
    else
        m.playlistList.visible = true
        m.emptyLabel.visible = false
        normalizeFocusIndex()
        m.playlistList.jumpToItem = m.focusIndex
    end if
end sub

sub showAddPlaylistDialog()
    kb = createObject("roSGNode", "KeyboardDialog")
    if kb = invalid then return
    kb.title = "Enter playlist name"
    kb.text = ""
    kb.buttons = ["Next", "Cancel"]
    m.addMode = "name"
    m.pendingName = ""
    kb.observeField("buttonSelected", "onAddDialogButton")
    m.top.getScene().dialog = kb
end sub

sub onAddDialogButton()
    dialog = m.top.getScene().dialog
    if dialog = invalid then return

    if dialog.buttonSelected = 1 and m.addMode <> "xmltv" then
        ' Cancel
        m.top.getScene().dialog = invalid
        focusList()
        return
    end if

    if m.addMode = "name" then
        m.pendingName = safeText(dialog.text)
        if m.pendingName = "" then m.pendingName = "Playlist " + (m.playlists.count() + 1).toStr()
        print "Add playlist name captured: "; m.pendingName
        m.top.getScene().dialog = invalid

        ' Now ask for URL
        kb = createObject("roSGNode", "KeyboardDialog")
        if kb = invalid then return
        kb.title = "Enter M3U playlist URL"
        kb.text = "http://"
        kb.buttons = ["Next", "Cancel"]
        m.addMode = "url"
        kb.observeField("buttonSelected", "onAddDialogButton")
        m.top.getScene().dialog = kb
    else if m.addMode = "url" then
        pendingUrl = safeText(dialog.text)
        m.top.getScene().dialog = invalid
        if pendingUrl <> "" and pendingUrl <> "http://" then
            m.pendingUrl = pendingUrl

            kb = createObject("roSGNode", "KeyboardDialog")
            if kb = invalid then return
            kb.title = "Optional XMLTV URL (EPG)"
            kb.text = ""
            kb.buttons = ["Save", "Skip"]
            m.addMode = "xmltv"
            kb.observeField("buttonSelected", "onAddDialogButton")
            m.top.getScene().dialog = kb
        else
            focusList()
        end if
    else if m.addMode = "xmltv" then
        pendingXmltv = ""
        if dialog.buttonSelected = 0 then
            pendingXmltv = safeText(dialog.text)
        end if
        m.top.getScene().dialog = invalid

        playlist = {name: m.pendingName, url: m.pendingUrl, xmltvUrl: pendingXmltv}
        m.playlists.push(playlist)
        print "Saved playlist: "; m.pendingName; " -> "; m.pendingUrl; " (xmltv: "; pendingXmltv; ")"
        savePlaylists()
        refreshList()
        focusList()
    end if
end sub

sub showEditPlaylistDialog()
    idx = getFocusedPlaylistIndex()
    if idx < 0 or idx >= m.playlists.count() then return

    pl = m.playlists[idx]
    kb = createObject("roSGNode", "KeyboardDialog")
    if kb = invalid then return
    kb.title = "Edit playlist name"
    kb.text = pl.name
    kb.buttons = ["Next", "Cancel"]
    m.editMode = "name"
    m.editIndex = idx
    m.editName = pl.name
    m.editXmltv = pl.xmltvUrl
    kb.observeField("buttonSelected", "onEditDialogButton")
    m.top.getScene().dialog = kb
end sub

sub onEditDialogButton()
    dialog = m.top.getScene().dialog
    if dialog = invalid then return

    if dialog.buttonSelected = 1 and m.editMode <> "xmltv" then
        m.top.getScene().dialog = invalid
        focusList()
        return
    end if

    if m.editMode = "name" then
        m.editName = safeText(dialog.text)
        if m.editName = "" then m.editName = m.playlists[m.editIndex].name
        m.top.getScene().dialog = invalid

        kb = createObject("roSGNode", "KeyboardDialog")
        if kb = invalid then return
        kb.title = "Edit playlist URL"
        kb.text = m.playlists[m.editIndex].url
        kb.buttons = ["Next", "Cancel"]
        m.editMode = "url"
        kb.observeField("buttonSelected", "onEditDialogButton")
        m.top.getScene().dialog = kb
    else if m.editMode = "url" then
        editUrl = safeText(dialog.text)
        m.top.getScene().dialog = invalid
        if editUrl <> "" then
            m.editUrl = editUrl

            kb = createObject("roSGNode", "KeyboardDialog")
            if kb = invalid then return
            kb.title = "Edit XMLTV URL (optional)"
            kb.text = m.editXmltv
            kb.buttons = ["Save", "Clear"]
            m.editMode = "xmltv"
            kb.observeField("buttonSelected", "onEditDialogButton")
            m.top.getScene().dialog = kb
        else
            focusList()
        end if
    else if m.editMode = "xmltv" then
        editXmltv = ""
        if dialog.buttonSelected = 0 then editXmltv = safeText(dialog.text)
        if editXmltv = "" then
            m.allowXmltvClear = true
            m.xmltvClearUrl = m.editUrl
        end if
        m.top.getScene().dialog = invalid

        m.playlists[m.editIndex] = {name: m.editName, url: m.editUrl, xmltvUrl: editXmltv}
        print "Updated playlist: "; m.editName; " -> "; m.editUrl; " (xmltv: "; editXmltv; ")"
        savePlaylists()
        refreshList()
        focusList()
    end if
end sub

sub deletePlaylist()
    idx = getFocusedPlaylistIndex()
    if idx < 0 or idx >= m.playlists.count() then return

    dialog = createObject("roSGNode", "StandardMessageDialog")
    if dialog = invalid then return
    dialog.title = "Delete Playlist"
    dialog.message = ["Delete '" + m.playlists[idx].name + "'?"]
    dialog.buttons = ["Delete", "Cancel"]
    m.deleteIndex = idx
    dialog.observeField("buttonSelected", "onDeleteConfirm")
    m.top.getScene().dialog = dialog
end sub

sub onDeleteRequest()
    if not m.top.visible then return
    if m.top.getScene().dialog <> invalid then return
    if m.playlists.count() > 0 then deletePlaylist()
end sub

sub onDeleteConfirm()
    dialog = m.top.getScene().dialog
    if dialog = invalid then return
    m.top.getScene().dialog = invalid

    if dialog.buttonSelected = 0 then
        ' Delete confirmed
        newList = []
        for i = 0 to m.playlists.count() - 1
            if i <> m.deleteIndex then newList.push(m.playlists[i])
        end for
        m.playlists = newList
        savePlaylists()
        refreshList()
    end if
    focusList()
end sub

sub focusList()
    if m.playlists.count() > 0
        normalizeFocusIndex()
        m.playlistList.jumpToItem = m.focusIndex
        m.playlistList.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

sub normalizeFocusIndex()
    if m.playlists.count() = 0 then
        m.focusIndex = 0
        return
    end if
    if m.focusIndex < 0 then m.focusIndex = 0
    if m.focusIndex >= m.playlists.count() then m.focusIndex = m.playlists.count() - 1
end sub

function getFocusedPlaylistIndex() as integer
    if m.playlists.count() = 0 then return -1

    idx = m.playlistList.itemFocused
    if idx = invalid or idx < 0 or idx >= m.playlists.count() then
        normalizeFocusIndex()
        return m.focusIndex
    end if

    m.focusIndex = idx
    return idx
end function

sub movePlaylistFocus(delta as integer)
    if m.playlists.count() = 0 then return

    idx = getFocusedPlaylistIndex()
    if idx < 0 then idx = 0
    idx = idx + delta
    if idx < 0 then idx = m.playlists.count() - 1
    if idx >= m.playlists.count() then idx = 0

    m.focusIndex = idx
    m.playlistList.jumpToItem = idx
    m.playlistList.setFocus(true)
end sub

sub selectFocusedPlaylist()
    if m.playlists.count() = 0 then
        showAddPlaylistDialog()
        return
    end if

    idx = getFocusedPlaylistIndex()
    if idx >= 0 and idx < m.playlists.count() then
        print "Selected playlist index "; idx; ": "; m.playlists[idx].name; " -> "; m.playlists[idx].url
        ' Notify XMLTV first so HomeScene has the guide URL before selectedUrl starts loading.
        m.top.selectedXmltv = m.playlists[idx].xmltvUrl
        m.top.selectedUrl = m.playlists[idx].url
    end if
end sub

function onKeyEvent(key, press) as boolean
    if not press then return false

    if key = "up" then
        movePlaylistFocus(-1)
        return true
    end if

    if key = "down" then
        movePlaylistFocus(1)
        return true
    end if

    if key = "OK" then
        selectFocusedPlaylist()
        return true
    end if

    if key = "options" then
        ' * button = Add
        showAddPlaylistDialog()
        return true
    end if

    if key = "play" then
        ' Play button = Edit
        if m.playlists.count() > 0 then
            showEditPlaylistDialog()
        end if
        return true
    end if

    if key = "rewind" or key = "replay" then
        ' Rewind button = Delete
        if m.playlists.count() > 0 then
            deletePlaylist()
        end if
        return true
    end if

    return false
end function

function safeText(value as dynamic) as string
    if value = invalid then return ""
    text = value.toStr()
    return text.Trim()
end function

function normalizePlaylistEntry(pl as object, idx as integer) as object
    if pl = invalid or type(pl) <> "roAssociativeArray" then
        return {name: "Playlist " + (idx + 1).toStr(), url: "", xmltvUrl: ""}
    end if

    name = ""
    if pl.doesExist("name") and pl.name <> invalid then name = safeText(pl.name)
    if name = "" and pl.doesExist("title") and pl.title <> invalid then name = safeText(pl.title)
    if name = "" then name = "Playlist " + (idx + 1).toStr()

    url = ""
    if pl.doesExist("url") and pl.url <> invalid then url = safeText(pl.url)
    if url = "" and pl.doesExist("playlistUrl") and pl.playlistUrl <> invalid then url = safeText(pl.playlistUrl)

    xmltvUrl = ""
    if pl.doesExist("xmltvUrl") and pl.xmltvUrl <> invalid then xmltvUrl = safeText(pl.xmltvUrl)
    if xmltvUrl = "" and pl.doesExist("xmltv") and pl.xmltv <> invalid then xmltvUrl = safeText(pl.xmltv)

    return {name: name, url: url, xmltvUrl: xmltvUrl}
end function
