sub init()
    m.nodes = {
        Video: m.top.findNode("Video"),
        PreviewPoster: m.top.findNode("PreviewPoster"),
        FadeInPreview: m.top.findNode("FadeInPreview"),
        FadeOutPreview: m.top.findNode("FadeOutPreview"),
        RowList: m.top.findNode("RowList"),
        Labels: {
            Category: m.top.findNode("CategoryLabel"),
            Category2: m.top.findNode("CategoryLabel2"),
            ChannelCount: m.top.findNode("ChannelCountLabel"),
            Info: m.top.findNode("InfoLabel")
        },
        GuidePanel: {
            Container: m.top.findNode("GuidePanel"),
            TimeHeaders: [
                m.top.findNode("GuideTimeHeader0"),
                m.top.findNode("GuideTimeHeader1"),
                m.top.findNode("GuideTimeHeader2"),
                m.top.findNode("GuideTimeHeader3")
            ]
        },
        InfoBar: m.top.findNode("InfoBar"),
        PlaybackStatus: {
            Overlay: m.top.findNode("PlaybackStatusOverlay"),
            Backdrop: m.top.findNode("PlaybackStatusBackdrop"),
            Card: m.top.findNode("PlaybackStatusCard"),
            Icon: m.top.findNode("PlaybackStatusIcon"),
            Title: m.top.findNode("PlaybackStatusTitle"),
            Subtitle: m.top.findNode("PlaybackStatusSubtitle"),
            Pulse: m.top.findNode("PlaybackStatusPulse")
        },
        Timer: m.top.findNode("ChannelLoadedTimer"),
        GuideTickTimer: m.top.findNode("GuideTickTimer"),
        XmltvRefreshTimer: m.top.findNode("XmltvRefreshTimer"),
        Scrolls: {
            Up: m.top.findNode("ScrollCategoryLabelUp"),
            Down: m.top.findNode("ScrollCategoryLabelDown"),
            Up2: m.top.findNode("ScrollCategoryLabel2Up"),
            Down2: m.top.findNode("ScrollCategoryLabel2Down")
        },
        Menu: m.top.findNode("SideMenu"),
        MenuItems: m.top.findNode("MenuItems"),
        ExpandMenu: m.top.findNode("ExpandMenu"),
        CollapseMenu: m.top.findNode("CollapseMenu"),
        LoadingAnim1: m.top.findNode("LoadingAnimation1"),
        LoadingAnim2: m.top.findNode("LoadingAnimation2"),
        PlaylistManager: m.top.findNode("PlaylistManager"),
        SettingsScreen: m.top.findNode("SettingsScreen")
    }

    m.guideProgramSlots = 6
    m.guideGridWidth = 1300
    m.guideWindowSeconds = 7200
    m.guideTimeOffsetSeconds = 0
    m.guideStepSeconds = 1800
    m.guideMaxOffsetSeconds = 86400
    m.guideSlideOffset = 0
    m.fastScrollKey = ""
    m.fastScrollTicks = 0

    m.nodes.Video.enableUI = false
    m.nodes.Video.loop = true
    m.nodes.Video.enableTrickPlay = true
    logDevicePlaybackCapabilities()

    ' Ensure scene key handling is active.
    m.top.setFocus(true)

    ' State management
    m.global.addFields({lastUrl: ""})
    m.state = {isFullScreen: false, lastRow: 0, menuItem: 0, menuFocused: false}
    m.currentScreen = "main" ' main, playlists, settings
    m.currentXmltvUrl = ""
    m.currentGuideTitle = ""
    m.searchActive = false
    m.searchTerm = ""
    m.epgByChannel = {}
    m.totalChannels = 0
    m.errorState = false
    m.minBufferReached = false
    m.isChannelLoading = false
    m.currentlyPlayingItem = invalid
    m.currentPlaybackSourceItem = invalid
    m.currentPlaybackFormats = []
    m.currentPlaybackFormatIndex = 0
    m.lastProbeUrl = ""
    m.hlsWrapperCounter = 0
    m.allChannelsList = [] ' flat list of all channels for channel up/down

    ' Load view mode preference
    m.viewMode = loadViewMode()
    m.transcodeServerUrl = loadTranscodeServerUrl()
    m.autoRefreshOnStart = loadAutoRefreshOnStart()

    ' Initialize content with loading placeholders
    m.content = createObject("roSGNode", "ContentNode")
    showLoadingPlaceholders()

    m.nodes.RowList.content = m.content
    m.nodes.Labels.Category.text = "Loading..."
    m.nodes.Labels.Category2.text = "Loading..."
    m.nodes.LoadingAnim1.control = "start"
    m.nodes.LoadingAnim2.control = "start"

    ' Loading progress timer
    m.loadingTimer = m.top.findNode("LoadingProgressTimer")
    m.loadingTimer.observeField("fire", "updateLoadingProgress")
    m.loadingProgress = 0
    m.isLoadingList = true
    m.loadingTimer.control = "start"

    ' Error reset timer
    m.errorResetTimer = createObject("roSGNode", "Timer")
    m.errorResetTimer.duration = 5
    m.errorResetTimer.repeat = false
    m.errorResetTimer.observeField("fire", "resetErrorState")
    m.top.appendChild(m.errorResetTimer)

    ' Force play timer for buffering
    m.forcePlayTimer = createObject("roSGNode", "Timer")
    m.forcePlayTimer.duration = 3
    m.forcePlayTimer.repeat = false
    m.forcePlayTimer.observeField("fire", "forcePlayVideo")
    m.top.appendChild(m.forcePlayTimer)

    ' Long-press channel scrolling starts one row at a time, then shortens the interval after a hold.
    m.fastScrollDelayTimer = createObject("roSGNode", "Timer")
    m.fastScrollDelayTimer.duration = 0.65
    m.fastScrollDelayTimer.repeat = false
    m.fastScrollDelayTimer.observeField("fire", "beginFastChannelScroll")
    m.top.appendChild(m.fastScrollDelayTimer)

    m.fastScrollTimer = createObject("roSGNode", "Timer")
    m.fastScrollTimer.duration = 0.18
    m.fastScrollTimer.repeat = true
    m.fastScrollTimer.observeField("fire", "continueFastChannelScroll")
    m.top.appendChild(m.fastScrollTimer)

    ' Set up PlaylistManager observer
    m.nodes.PlaylistManager.observeField("selectedUrl", "onPlaylistSelected")
    m.nodes.PlaylistManager.observeField("selectedXmltv", "onPlaylistXmltvSelected")

    ' Set up SettingsScreen observer
    m.nodes.SettingsScreen.observeField("viewMode", "onViewModeChanged")
    m.nodes.SettingsScreen.observeField("autoRefreshOnStart", "onAutoRefreshOnStartChanged")
    m.nodes.SettingsScreen.observeField("transcodeServerUrl", "onTranscodeServerUrlChanged")

    ' Set up observers
    m.nodes.RowList.observeField("itemSelected", "ChannelChange")
    m.nodes.RowList.observeField("itemFocused", "onRowItemFocused")
    m.nodes.Timer.observeField("fire", "restoreChannelCount")
    m.nodes.GuideTickTimer.observeField("fire", "onGuideTick")
    m.nodes.XmltvRefreshTimer.observeField("fire", "onXmltvRefreshTimer")
    m.nodes.Video.observeField("state", "onVideoStateChange")
    m.nodes.Video.observeField("bufferingStatus", "onBufferingStatusChange")

    ' Check if playlists exist, if so try loading last used
    checkInitialPlaylist()
end sub

sub logDevicePlaybackCapabilities()
    deviceInfo = CreateObject("roDeviceInfo")
    if deviceInfo = invalid then return

    print "Roku device model: "; deviceInfo.GetModel(); " videoMode: "; deviceInfo.GetVideoMode()
    print "CanDecode H264 main 4.1: "; formatDecodeResult(deviceInfo.CanDecodeVideo({Codec: "h264", Profile: "main", Level: "4.1"}))
    print "CanDecode H264 high 4.2: "; formatDecodeResult(deviceInfo.CanDecodeVideo({Codec: "h264", Profile: "high", Level: "4.2"}))
end sub

function formatDecodeResult(result as object) as string
    if result = invalid then return "unknown"
    if result.result <> invalid then return result.result.toStr()
    return "unknown"
end function

' --- Initialization helpers ---

sub checkInitialPlaylist()
    registry = createObject("roRegistrySection", "KojoStream")
    hasPlaylists = false
    if registry.exists("kojostream_playlists") then
        jsonStr = registry.read("kojostream_playlists")
        if jsonStr <> invalid and jsonStr <> "" then
            parsed = parseJSON(jsonStr)
            if parsed <> invalid and parsed.count() > 0 then
                hasPlaylists = true
                ' Load the last used URL or first playlist
                if registry.exists("last_used_url") then
                    m.global.lastUrl = registry.read("last_used_url")
                else
                    m.global.lastUrl = parsed[0].url
                end if
                m.currentXmltvUrl = resolveXmltvUrlForPlaylist(parsed, m.global.lastUrl)
            end if
        end if
    end if

    if hasPlaylists and m.global.lastUrl <> "" and m.autoRefreshOnStart then
        showScreen("main")
        startLoadingPlaylist(m.global.lastUrl)
    else if hasPlaylists then
        m.isLoadingList = false
        m.loadingTimer.control = "stop"
        m.nodes.LoadingAnim1.control = "stop"
        m.nodes.LoadingAnim2.control = "stop"
        m.nodes.Labels.Category.text = ""
        m.nodes.Labels.Category2.text = ""
        m.nodes.Labels.ChannelCount.text = "Select a playlist to load"
        m.content.removeChildrenIndex(m.content.getChildCount(), 0)
        m.nodes.RowList.content = m.content
        showScreen("playlists")
    else
        ' No playlists - show playlist manager
        m.isLoadingList = false
        m.loadingTimer.control = "stop"
        m.nodes.Labels.Category.text = ""
        m.nodes.Labels.Category2.text = ""
        m.nodes.LoadingAnim1.control = "stop"
        m.nodes.LoadingAnim2.control = "stop"
        m.nodes.Labels.ChannelCount.text = "No playlist loaded"
        showScreen("playlists")
    end if
end sub

function loadViewMode() as string
    registry = createObject("roRegistrySection", "KojoStream")
    if registry.exists("view_mode") then
        return registry.read("view_mode")
    end if
    return "grouped"
end function

function loadTranscodeServerUrl() as string
    registry = createObject("roRegistrySection", "KojoStream")
    if registry.exists("transcode_server_url") then
        return sanitizeUrl(registry.read("transcode_server_url"))
    end if
    return ""
end function

function loadAutoRefreshOnStart() as boolean
    registry = createObject("roRegistrySection", "KojoStream")
    if registry.exists("auto_refresh_on_start") then
        return registry.read("auto_refresh_on_start") <> "false"
    end if
    return true
end function

function resolveXmltvUrlForPlaylist(playlists as object, playlistUrl as string) as string
    registry = createObject("roRegistrySection", "KojoStream")
    targetUrl = sanitizeUrl(playlistUrl)
    savedXmltv = ""
    if registry.exists("last_xmltv_url") then savedXmltv = sanitizeUrl(registry.read("last_xmltv_url"))

    matchedXmltv = ""
    if playlists <> invalid then
        for each pl in playlists
            if pl <> invalid and type(pl) = "roAssociativeArray" then
                plUrl = ""
                if pl.doesExist("url") and pl.url <> invalid then plUrl = sanitizeUrl(pl.url)
                if plUrl = "" and pl.doesExist("playlistUrl") and pl.playlistUrl <> invalid then plUrl = sanitizeUrl(pl.playlistUrl)
                if plUrl = targetUrl then
                    if pl.doesExist("xmltvUrl") and pl.xmltvUrl <> invalid then matchedXmltv = sanitizeUrl(pl.xmltvUrl)
                    if matchedXmltv = "" and pl.doesExist("xmltv") and pl.xmltv <> invalid then matchedXmltv = sanitizeUrl(pl.xmltv)
                    exit for
                end if
            end if
        end for
    end if

    if matchedXmltv <> "" then return matchedXmltv
    if savedXmltv <> "" then return savedXmltv
    return ""
end function

sub saveXmltvUrlForPlaylist(playlistUrl as string, xmltvUrl as string)
    targetUrl = sanitizeUrl(playlistUrl)
    targetXmltv = sanitizeUrl(xmltvUrl)
    if targetUrl = "" or targetXmltv = "" then return

    registry = createObject("roRegistrySection", "KojoStream")
    if not registry.exists("kojostream_playlists") then return

    jsonStr = registry.read("kojostream_playlists")
    if jsonStr = invalid or jsonStr = "" then return

    playlists = parseJSON(jsonStr)
    if playlists = invalid or type(playlists) <> "roArray" then return

    changed = false
    for each pl in playlists
        if pl <> invalid and type(pl) = "roAssociativeArray" then
            plUrl = ""
            if pl.doesExist("url") and pl.url <> invalid then plUrl = sanitizeUrl(pl.url)
            if plUrl = "" and pl.doesExist("playlistUrl") and pl.playlistUrl <> invalid then plUrl = sanitizeUrl(pl.playlistUrl)

            if plUrl = targetUrl then
                currentXmltv = ""
                if pl.doesExist("xmltvUrl") and pl.xmltvUrl <> invalid then currentXmltv = sanitizeUrl(pl.xmltvUrl)
                if currentXmltv = "" and pl.doesExist("xmltv") and pl.xmltv <> invalid then currentXmltv = sanitizeUrl(pl.xmltv)

                if currentXmltv = "" then
                    pl.xmltvUrl = targetXmltv
                    changed = true
                end if
                exit for
            end if
        end if
    end for

    if changed then
        registry.write("kojostream_playlists", formatJSON(playlists))
        registry.flush()
        print "Recovered XMLTV URL for playlist: "; targetXmltv
    end if
end sub

sub showLoadingPlaceholders()
    m.content.removeChildrenIndex(m.content.getChildCount(), 0)
    for i = 0 to 19
        item = createObject("roSGNode", "ContentNode")
        item.addField("isLoading", "boolean", true)
        item.isLoading = true
        item.title = "Loading..."
        m.content.appendChild(item)
    end for
end sub

' --- Playlist loading ---

sub startLoadingPlaylist(url as string)
    m.global.lastUrl = url
    m.epgByChannel = {}
    m.currentGuideTitle = ""
    m.guideTimeOffsetSeconds = 0
    if m.currentXmltvUrl = "" then
        registryForXmltv = createObject("roRegistrySection", "KojoStream")
        if registryForXmltv.exists("kojostream_playlists") then
            playlistJson = registryForXmltv.read("kojostream_playlists")
            if playlistJson <> invalid and playlistJson <> "" then
                parsedPlaylists = parseJSON(playlistJson)
                if parsedPlaylists <> invalid then
                    m.currentXmltvUrl = resolveXmltvUrlForPlaylist(parsedPlaylists, url)
                end if
            end if
        end if
    end if
    stopXmltvTimers()
    hidePlaybackStatusOverlay()

    ' Save as last used
    registry = createObject("roRegistrySection", "KojoStream")
    registry.write("last_used_url", url)
    if m.currentXmltvUrl <> "" then registry.write("last_xmltv_url", m.currentXmltvUrl)
    registry.flush()
    if m.currentXmltvUrl <> "" then saveXmltvUrlForPlaylist(url, m.currentXmltvUrl)

    ' Reset UI to loading state
    m.nodes.Labels.ChannelCount.text = "Loading channels: 0%"
    m.nodes.Labels.Category.text = "Loading..."
    m.nodes.Labels.Category2.text = "Loading..."
    m.nodes.LoadingAnim1.control = "start"
    m.nodes.LoadingAnim2.control = "start"

    showLoadingPlaceholders()
    m.nodes.RowList.content = m.content

    m.isLoadingList = true
    m.loadingProgress = 0
    m.loadingTimer.control = "start"

    ' Create and run loader task
    m.LoadTask = createObject("roSGNode", "M3uLoader")
    if m.LoadTask = invalid then
        m.nodes.Labels.ChannelCount.text = "Error: could not create loader"
        return
    end if
    m.LoadTask.observeField("content", "rowListContentChanged")
    m.LoadTask.observeField("error", "onLoadError")
    m.LoadTask.m3uUrl = url
    m.LoadTask.control = "RUN"
    print "Loading playlist: "; url; " (xmltv: "; m.currentXmltvUrl; ")"

    if m.currentXmltvUrl <> "" then
        loadXmltvGuide(m.currentXmltvUrl)
    end if
end sub

sub onPlaylistSelected()
    url = m.nodes.PlaylistManager.selectedUrl
    m.currentXmltvUrl = m.nodes.PlaylistManager.selectedXmltv
    if m.currentXmltvUrl = invalid then m.currentXmltvUrl = ""
    if url <> "" then
        showScreen("main")
        startLoadingPlaylist(url)
    end if
end sub

sub onPlaylistXmltvSelected()
    m.currentXmltvUrl = m.nodes.PlaylistManager.selectedXmltv
    if m.currentXmltvUrl = invalid then m.currentXmltvUrl = ""
end sub

sub onViewModeChanged()
    m.viewMode = m.nodes.SettingsScreen.viewMode
    ' Re-render content with new view mode if we have content
    if m.LoadTask <> invalid and m.LoadTask.content <> invalid then
        renderContent(m.LoadTask.content)
    end if
end sub

sub onAutoRefreshOnStartChanged()
    m.autoRefreshOnStart = m.nodes.SettingsScreen.autoRefreshOnStart
    if m.autoRefreshOnStart then
        print "Auto-refresh on start enabled"
    else
        print "Auto-refresh on start disabled"
    end if
end sub

sub onTranscodeServerUrlChanged()
    m.transcodeServerUrl = sanitizeUrl(m.nodes.SettingsScreen.transcodeServerUrl)
    if m.transcodeServerUrl <> "" then
        print "Transcode server enabled: "; m.transcodeServerUrl
    else
        print "Transcode server disabled"
    end if
end sub

sub onLoadError()
    if m.LoadTask = invalid then return
    errMsg = m.LoadTask.error
    if errMsg <> "" then
        m.nodes.Labels.ChannelCount.text = errMsg
        m.nodes.Labels.Category.text = ""
        m.nodes.Labels.Category2.text = ""
        m.nodes.LoadingAnim1.control = "stop"
        m.nodes.LoadingAnim2.control = "stop"
        m.nodes.Labels.Category.opacity = 1.0
        m.nodes.Labels.Category2.opacity = 1.0
        m.isLoadingList = false
        m.loadingTimer.control = "stop"
        m.content.removeChildrenIndex(m.content.getChildCount(), 0)
        m.nodes.RowList.content = m.content
    end if
end sub

' --- Screen management ---

sub showScreen(screen as string)
    m.currentScreen = screen
    stopFastChannelScroll()
    m.top.setFocus(true)
    if screen <> "main" then hidePlaybackStatusOverlay()
    if screen = "main" then
        m.nodes.PlaylistManager.visible = false
        m.nodes.SettingsScreen.visible = false
        m.nodes.RowList.visible = true
        m.nodes.Labels.Category.visible = true
        m.nodes.Labels.Category2.visible = true
        m.nodes.Labels.ChannelCount.visible = true
        m.nodes.InfoBar.visible = false
        m.nodes.Menu.visible = true
        m.nodes.RowList.setFocus(true)
        updateGuidePanelForFocusedItem()
    else if screen = "playlists" then
        m.nodes.PlaylistManager.visible = true
        m.nodes.SettingsScreen.visible = false
        m.nodes.RowList.visible = false
        m.nodes.Labels.Category.visible = false
        m.nodes.Labels.Category2.visible = false
        m.nodes.InfoBar.visible = false
        hideGuidePanel()
        m.nodes.Menu.visible = false
        m.nodes.PlaylistManager.setFocus(true)
    else if screen = "settings" then
        m.nodes.SettingsScreen.visible = true
        m.nodes.PlaylistManager.visible = false
        m.nodes.RowList.visible = false
        m.nodes.Labels.Category.visible = false
        m.nodes.Labels.Category2.visible = false
        m.nodes.InfoBar.visible = false
        hideGuidePanel()
        m.nodes.Menu.visible = false
        m.nodes.SettingsScreen.setFocus(true)
    end if
end sub

' --- Loading progress ---

sub updateLoadingProgress()
    if not m.isLoadingList then return
    m.loadingProgress += 5
    if m.loadingProgress > 99 then m.loadingProgress = 99
    m.nodes.Labels.ChannelCount.text = "Loading channels: " + m.loadingProgress.toStr() + "%"
end sub

function buildLoadedChannelsText() as string
    countText = "Channels loaded: " + m.totalChannels.toStr()
    if m.guideTimeOffsetSeconds <> invalid and m.guideTimeOffsetSeconds > 0 then
        countText = countText + "  |  Guide +" + formatGuideOffset(m.guideTimeOffsetSeconds)
    end if
    if m.currentGuideTitle <> invalid and m.currentGuideTitle <> "" then
        return m.currentGuideTitle + "  |  " + countText
    end if
    return countText
end function

function formatGuideOffset(offsetSeconds as integer) as string
    if offsetSeconds <= 0 then return "0m"
    totalMinutes = int(offsetSeconds / 60)
    hours = int(totalMinutes / 60)
    minutes = totalMinutes - (hours * 60)

    if hours > 0 and minutes > 0 then return hours.toStr() + "h" + minutes.toStr() + "m"
    if hours > 0 then return hours.toStr() + "h"
    return minutes.toStr() + "m"
end function

sub showLoadedChannelsText()
    m.nodes.Labels.ChannelCount.text = buildLoadedChannelsText()
end sub

' --- Row item focus ---

sub onRowItemFocused()
    row = m.nodes.RowList.itemFocused
    if row = invalid or row < 0 or row >= m.content.getChildCount() then return
    item = m.content.getChild(row)
    if item = invalid or item.isLoading then
        m.nodes.InfoBar.visible = false
        hideGuidePanel()
        if not m.isChannelLoading then m.nodes.PreviewPoster.visible = false
        return
    end if

    ' The focused channel title is already shown in the top guide label.
    m.nodes.InfoBar.visible = false
    if item.HDPosterUrl <> "" then
        m.nodes.PreviewPoster.uri = item.HDPosterUrl
    else
        m.nodes.PreviewPoster.uri = "pkg:/images/no-image.png"
    end if

    if not m.state.isFullScreen then
        m.nodes.PreviewPoster.visible = true
        if m.nodes.PreviewPoster.opacity < 1.0 then
            m.nodes.PreviewPoster.opacity = 1.0
        end if
    else
        m.nodes.FadeOutPreview.control = "start"
    end if
    updateCategoryLabel(row)
end sub

sub updateCategoryLabel(row)
    totalRows = m.content.getChildCount()
    if totalRows = 0 then return
    if row < 0 or row >= totalRows then return
    focusedItem = m.content.getChild(row)
    if focusedItem = invalid then
        m.nodes.Labels.Category.text = ""
        m.nodes.Labels.Category2.text = ""
        hideGuidePanel()
        return
    end if
    m.nodes.Labels.Category.text = getItemTitle(focusedItem)
    m.nodes.Labels.Category2.text = ""
    m.state.lastRow = row
    ensureGuideRowsNear(row)
    updateGuidePanelForFocusedItem()
end sub

sub beginFastChannelScroll()
    if m.fastScrollKey = "" then return
    m.fastScrollTicks = 0
    m.fastScrollTimer.duration = fastChannelScrollInterval()
    m.fastScrollTimer.control = "start"
end sub

sub continueFastChannelScroll()
    if m.fastScrollKey = "" then
        stopFastChannelScroll()
        return
    end if

    m.fastScrollTicks++
    m.fastScrollTimer.duration = fastChannelScrollInterval()
    scrollFocusedChannel(m.fastScrollKey)
end sub

function startChannelListScroll(key as string) as boolean
    if key <> "up" and key <> "down" then return false
    if m.content = invalid then return true
    if m.content.getChildCount() = 0 then return true

    if m.fastScrollKey <> key then
        stopFastChannelScroll()
        m.fastScrollKey = key
        m.fastScrollTicks = 0
        scrollFocusedChannel(key)
        m.fastScrollDelayTimer.control = "start"
    end if

    return true
end function

function stopFastChannelScrollForKey(key as string) as boolean
    if m.fastScrollKey = key then
        stopFastChannelScroll()
        return true
    end if
    return false
end function

sub stopFastChannelScroll()
    if m.fastScrollDelayTimer <> invalid then m.fastScrollDelayTimer.control = "stop"
    if m.fastScrollTimer <> invalid then m.fastScrollTimer.control = "stop"
    m.fastScrollKey = ""
    m.fastScrollTicks = 0
end sub

function fastChannelScrollInterval()
    if m.fastScrollTicks < 14 then return 0.18
    if m.fastScrollTicks < 28 then return 0.105
    return 0.065
end function

sub scrollFocusedChannel(key as string)
    if m.content = invalid then return
    totalRows = m.content.getChildCount()
    if totalRows <= 0 then return

    currentRow = m.state.lastRow
    if currentRow = invalid or currentRow < 0 then currentRow = m.nodes.RowList.itemFocused
    if currentRow = invalid or currentRow < 0 then currentRow = 0
    if currentRow >= totalRows then currentRow = totalRows - 1

    nextRow = currentRow
    if key = "up" then
        nextRow = currentRow - 1
    else if key = "down" then
        nextRow = currentRow + 1
    end if

    if nextRow < 0 then nextRow = 0
    if nextRow >= totalRows then nextRow = totalRows - 1

    if nextRow = currentRow then
        stopFastChannelScroll()
        return
    end if

    m.nodes.RowList.jumpToItem = nextRow
    updateCategoryLabel(nextRow)
end sub

' --- Channel playback ---

sub ChannelChange()
    selected = m.nodes.RowList.itemSelected
    if selected = invalid or selected < 0 then selected = m.nodes.RowList.itemFocused
    if selected = invalid or selected < 0 or selected >= m.content.getChildCount() then return
    item = m.content.getChild(selected)
    if item = invalid or item.isLoading then return
    itemUrl = getItemUrl(item)
    if itemUrl = "" then
        print "ChannelChange skipped: missing URL for focused item"
        return
    end if

    video = m.nodes.Video
    if m.currentlyPlayingItem <> invalid and playbackItemsMatch(m.currentlyPlayingItem, item) and not m.state.isFullScreen then
        video.translation = [0,0]
        video.width = 1920
        video.height = 1080
        video.enableUI = true
        setFullScreen(true)
    else
        if not m.state.isFullScreen then
            applyPipVideoLayout()
            video.enableUI = false
        end if
        startChannelPlayback(item)
    end if
end sub

function playbackItemsMatch(currentItem as object, selectedItem as object) as boolean
    currentSourceUrl = getPlaybackSourceUrl(currentItem)
    if currentSourceUrl = "" then currentSourceUrl = getItemUrl(currentItem)

    selectedSourceUrl = getPlaybackSourceUrl(selectedItem)
    if selectedSourceUrl = "" then selectedSourceUrl = getItemUrl(selectedItem)

    return currentSourceUrl <> "" and currentSourceUrl = selectedSourceUrl
end function

sub applyPipVideoLayout()
    m.nodes.Video.translation = [1240,0]
    m.nodes.Video.width = 640
    m.nodes.Video.height = 360
end sub

sub setFullScreen(state)
    stopFastChannelScroll()
    m.state.isFullScreen = state
    nodes = m.nodes
    nodes.RowList.visible = not state
    nodes.Labels.Category.visible = not state
    nodes.Labels.Category2.visible = not state
    nodes.Labels.ChannelCount.visible = not state
    nodes.InfoBar.visible = not state
    nodes.Menu.visible = not state
    if state then
        hideGuidePanel()
    else
        updateGuidePanelForFocusedItem()
    end if

    if not state and nodes.Video.state <> "playing" then
        nodes.PreviewPoster.visible = true
        nodes.FadeInPreview.control = "start"
    else
        nodes.FadeOutPreview.control = "start"
    end if

    if state then
        nodes.Video.setFocus(true)
    else
        nodes.RowList.setFocus(true)
        applyPipVideoLayout()
        nodes.Video.enableUI = false
    end if

    if nodes.PlaybackStatus.Overlay.visible then
        positionPlaybackStatusOverlay()
    end if
end sub

sub showPlaybackLoading(title as string, subtitle as string)
    m.isChannelLoading = true
    positionPlaybackStatusOverlay()
    if not m.state.isFullScreen then
        m.nodes.FadeOutPreview.control = "stop"
        m.nodes.FadeInPreview.control = "stop"
        m.nodes.PreviewPoster.visible = true
        m.nodes.PreviewPoster.opacity = 1.0
    end if

    nodes = m.nodes.PlaybackStatus
    displayTitle = title
    if displayTitle = "" then displayTitle = "channel"
    nodes.Icon.text = "..."
    nodes.Icon.color = "0xFFFFFFFF"
    nodes.Icon.opacity = 1.0
    nodes.Title.text = "Loading " + displayTitle
    nodes.Title.color = "0xFFFFFFFF"
    nodes.Subtitle.text = subtitle
    nodes.Subtitle.color = "0xC9D4E5FF"
    nodes.Overlay.visible = true
    nodes.Pulse.control = "start"
end sub

sub showPlaybackFailure(title as string)
    m.isChannelLoading = false
    positionPlaybackStatusOverlay()

    nodes = m.nodes.PlaybackStatus
    nodes.Pulse.control = "stop"
    nodes.Icon.opacity = 1.0
    nodes.Icon.text = "!"
    nodes.Icon.color = "0xFF6B6BFF"
    nodes.Title.text = "Failed to load channel"
    nodes.Title.color = "0xFFFFFFFF"
    if title <> "" then
        nodes.Subtitle.text = title
    else
        nodes.Subtitle.text = "Try another channel"
    end if
    nodes.Subtitle.color = "0xC9D4E5FF"
    nodes.Overlay.visible = true
end sub

sub hidePlaybackStatusOverlay()
    m.isChannelLoading = false
    m.nodes.PlaybackStatus.Pulse.control = "stop"
    m.nodes.PlaybackStatus.Overlay.visible = false
end sub

sub positionPlaybackStatusOverlay()
    nodes = m.nodes.PlaybackStatus
    if m.state.isFullScreen then
        nodes.Overlay.translation = [0,0]
        nodes.Backdrop.width = 1920
        nodes.Backdrop.height = 1080
        nodes.Card.translation = [610,405]
        nodes.Card.width = 700
        nodes.Card.height = 270
        nodes.Icon.translation = [820,430]
        nodes.Icon.width = 280
        nodes.Icon.height = 80
        nodes.Title.translation = [510,545]
        nodes.Title.width = 900
        nodes.Title.height = 54
        nodes.Subtitle.translation = [510,610]
        nodes.Subtitle.width = 900
        nodes.Subtitle.height = 44
    else
        nodes.Overlay.translation = [1240,0]
        nodes.Backdrop.width = 640
        nodes.Backdrop.height = 360
        nodes.Card.translation = [58,78]
        nodes.Card.width = 524
        nodes.Card.height = 216
        nodes.Icon.translation = [205,94]
        nodes.Icon.width = 230
        nodes.Icon.height = 67
        nodes.Title.translation = [52,181]
        nodes.Title.width = 536
        nodes.Title.height = 46
        nodes.Subtitle.translation = [52,241]
        nodes.Subtitle.width = 536
        nodes.Subtitle.height = 42
    end if
end sub

function getPlaybackLoadingSubtitle(fmtSpec as string) as string
    if fmtSpec = "hls-direct" then return "Trying native Roku playback"
    if fmtSpec = "hls-wrapper" then return "Trying HLS compatibility wrapper"
    if fmtSpec = "hls-transcode" then return "Preparing transcoded stream"
    return "Preparing stream"
end function

' --- Channel up/down during fullscreen playback ---

sub playNextChannel()
    if m.allChannelsList.count() = 0 then buildFlatChannelList()
    if m.allChannelsList.count() = 0 then return

    idx = findCurrentChannelIndex()
    if idx >= 0 then
        nextIdx = idx + 1
        if nextIdx >= m.allChannelsList.count() then nextIdx = 0
    else
        nextIdx = 0
    end if

    playChannelByIndex(nextIdx)
end sub

sub playPrevChannel()
    if m.allChannelsList.count() = 0 then buildFlatChannelList()
    if m.allChannelsList.count() = 0 then return

    idx = findCurrentChannelIndex()
    if idx >= 0 then
        prevIdx = idx - 1
        if prevIdx < 0 then prevIdx = m.allChannelsList.count() - 1
    else
        prevIdx = 0
    end if

    playChannelByIndex(prevIdx)
end sub

sub buildFlatChannelList()
    m.allChannelsList = []
    if m.LoadTask = invalid or m.LoadTask.content = invalid then return
    for each cat in m.LoadTask.content.getChildren(-1, 0)
        for each ch in cat.getChildren(-1, 0)
            m.allChannelsList.push(ch)
        end for
    end for
end sub

function findCurrentChannelIndex() as integer
    if m.currentlyPlayingItem = invalid then return -1
    for i = 0 to m.allChannelsList.count() - 1
        if playbackItemsMatch(m.currentlyPlayingItem, m.allChannelsList[i]) then return i
    end for
    return -1
end function

sub playChannelByIndex(idx as integer)
    if idx < 0 or idx >= m.allChannelsList.count() then return
    item = m.allChannelsList[idx]
    startChannelPlayback(item)

    ' Show channel name briefly
    m.nodes.Labels.Info.text = getItemTitle(item)
    m.nodes.InfoBar.visible = true
    m.nodes.Timer.control = "start"
end sub

sub startChannelPlayback(item as object)
    url = getItemUrl(item)
    if url = "" then
        m.nodes.Labels.ChannelCount.text = "Channel URL missing"
        print "Playback aborted: channel has no URL"
        return
    end if

    m.currentPlaybackSourceItem = item.clone(true)
    m.currentPlaybackFormats = getPlaybackFormats(item)
    m.currentPlaybackFormatIndex = 0
    attemptPlaybackWithCurrentFormat(m.currentPlaybackSourceItem)
end sub

sub attemptPlaybackWithCurrentFormat(item as object)
    if m.currentPlaybackFormats.count() = 0 then
        m.currentPlaybackFormats = ["hls"]
        m.currentPlaybackFormatIndex = 0
    end if
    if m.currentPlaybackFormatIndex < 0 or m.currentPlaybackFormatIndex >= m.currentPlaybackFormats.count() then return

    fmtSpec = m.currentPlaybackFormats[m.currentPlaybackFormatIndex]
    fmt = fmtSpec
    useHlsWrapper = false
    useTranscodeProxy = false
    if fmtSpec = "hls-direct" then
        fmt = "hls"
    else if fmtSpec = "hls-wrapper" then
        fmt = "hls"
        useHlsWrapper = true
    else if fmtSpec = "hls-transcode" then
        fmt = "hls"
        useTranscodeProxy = true
    end if

    sourceUrl = getPlaybackSourceUrl(item)
    if sourceUrl = "" then sourceUrl = getItemUrl(item)
    title = getItemTitle(item)
    loadingSubtitle = getPlaybackLoadingSubtitle(fmtSpec)
    showPlaybackLoading(title, loadingSubtitle)

    content = item.clone(true)
    playUrl = sourceUrl
    if fmt = "hls" and useTranscodeProxy then
        m.nodes.Video.control = "stop"
        sleep(1000)
        transcodeUrl = buildTranscodePlaybackUrl(sourceUrl, item)
        if transcodeUrl <> "" then playUrl = transcodeUrl
    else if fmt = "hls" and useHlsWrapper then
        wrappedUrl = createHlsMasterWrapper(sourceUrl)
        if wrappedUrl <> "" then playUrl = wrappedUrl
    end if
    content.url = playUrl
    if not content.hasField("sourceUrl") then content.addField("sourceUrl", "string", true)
    content.sourceUrl = sourceUrl
    content.streamformat = fmt
    content.live = (fmt = "hls" or fmt = "ts" or fmt = "dash" or fmt = "ism")
    if not useTranscodeProxy then
        applyHttpHeadersToContent(content, item)
    end if

    m.nodes.Labels.ChannelCount.text = "Loading channel..."
    m.nodes.Video.content = content
    m.nodes.Video.control = "play"
    m.currentlyPlayingItem = content
    m.nodes.FadeOutPreview.control = "start"
    m.errorState = false
    m.minBufferReached = false
    m.forcePlayTimer.control = "start"

    print "Playback attempt format "; (m.currentPlaybackFormatIndex + 1).toStr(); "/"; m.currentPlaybackFormats.count().toStr(); ": "; fmtSpec; " | "; title; " | "; playUrl
end sub

function buildTranscodePlaybackUrl(sourceUrl as string, item as object) as string
    baseUrl = getTranscodeServerUrl()
    if baseUrl = "" then return ""
    if sourceUrl = "" then return ""

    if baseUrl.Right(1) = "/" then baseUrl = baseUrl.Left(baseUrl.Len() - 1)
    proxyUrl = baseUrl + "/hls?url=" + encodeQueryValue(sourceUrl)

    userAgent = getItemField(item, "userAgent")
    referrer = getItemField(item, "referrer")
    origin = getItemField(item, "origin")
    cookie = getItemField(item, "cookie")

    if userAgent <> "" then proxyUrl = proxyUrl + "&ua=" + encodeQueryValue(userAgent)
    if referrer <> "" then proxyUrl = proxyUrl + "&ref=" + encodeQueryValue(referrer)
    if origin <> "" then proxyUrl = proxyUrl + "&origin=" + encodeQueryValue(origin)
    if cookie <> "" then proxyUrl = proxyUrl + "&cookie=" + encodeQueryValue(cookie)

    print "Using transcode proxy for stream"
    return proxyUrl
end function

function getTranscodeServerUrl() as string
    if m.transcodeServerUrl <> invalid and m.transcodeServerUrl <> "" then return sanitizeUrl(m.transcodeServerUrl)
    return ""
end function

function encodeQueryValue(value as dynamic) as string
    if value = invalid then return ""
    encoded = value.toStr().Trim()
    encoded = encoded.Replace("%", "%25")
    encoded = encoded.Replace(" ", "%20")
    encoded = encoded.Replace(Chr(34), "%22")
    encoded = encoded.Replace("#", "%23")
    encoded = encoded.Replace("&", "%26")
    encoded = encoded.Replace("+", "%2B")
    encoded = encoded.Replace(",", "%2C")
    encoded = encoded.Replace("/", "%2F")
    encoded = encoded.Replace(":", "%3A")
    encoded = encoded.Replace(";", "%3B")
    encoded = encoded.Replace("=", "%3D")
    encoded = encoded.Replace("?", "%3F")
    encoded = encoded.Replace("@", "%40")
    encoded = encoded.Replace("[", "%5B")
    encoded = encoded.Replace("]", "%5D")
    return encoded
end function

sub applyHttpHeadersToContent(content as object, originalItem as object)
    headers = buildRequestHeaders(originalItem)

    if headers <> invalid and headers.count() > 0 then
        headerLines = []
        for each key in headers
            value = headers[key]
            if value <> invalid and value <> "" then
                headerLines.push(key + ":" + value)
            end if
        end for

        if headerLines.count() > 0 then
            content.HttpHeaders = headerLines
            print "Applying HTTP headers: "; headerLines.count()
        end if
    end if

    agent = CreateObject("roHttpAgent")
    if agent <> invalid and headers <> invalid and headers.count() > 0 then
        agent.SetHeaders(headers)
        m.nodes.Video.setHttpAgent(agent)
    end if
end sub

function createHlsMasterWrapper(mediaPlaylistUrl as string) as string
    if mediaPlaylistUrl = invalid or mediaPlaylistUrl = "" then return ""
    m.hlsWrapperCounter++
    wrapperPath = "tmp:/hls_master_" + m.hlsWrapperCounter.toStr() + ".m3u8"

    master = "#EXTM3U" + Chr(10)
    master = master + "#EXT-X-VERSION:3" + Chr(10)
    master = master + "#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720" + Chr(10)
    master = master + mediaPlaylistUrl + Chr(10)

    ok = WriteAsciiFile(wrapperPath, master)
    if ok then
        print "Created HLS wrapper: "; wrapperPath
        return wrapperPath
    end if
    return mediaPlaylistUrl
end function

function buildRequestHeaders(item as object) as object
    headers = {}
    userAgent = getItemField(item, "userAgent")
    referrer = getItemField(item, "referrer")
    origin = getItemField(item, "origin")
    cookie = getItemField(item, "cookie")

    if userAgent <> "" then headers["User-Agent"] = userAgent
    if referrer <> "" then headers["Referer"] = referrer
    if origin <> "" then headers["Origin"] = origin
    if cookie <> "" then headers["Cookie"] = cookie

    return headers
end function

function getItemField(item as object, key as string) as string
    if item = invalid then return ""
    lowerKey = lcase(key)
    if lowerKey = "useragent" then
        if item.userAgent <> invalid and item.userAgent <> "" then return item.userAgent
        if item.UserAgent <> invalid and item.UserAgent <> "" then return item.UserAgent
    else if lowerKey = "referrer" then
        if item.referrer <> invalid and item.referrer <> "" then return item.referrer
        if item.referer <> invalid and item.referer <> "" then return item.referer
        if item.Referrer <> invalid and item.Referrer <> "" then return item.Referrer
        if item.Referer <> invalid and item.Referer <> "" then return item.Referer
    else if lowerKey = "origin" then
        if item.origin <> invalid and item.origin <> "" then return item.origin
        if item.Origin <> invalid and item.Origin <> "" then return item.Origin
    else if lowerKey = "cookie" then
        if item.cookie <> invalid and item.cookie <> "" then return item.cookie
        if item.Cookie <> invalid and item.Cookie <> "" then return item.Cookie
    end if
    return ""
end function

function getPlaybackFormats(item as object) as object
    url = lcase(getItemUrl(item))
    declared = lcase(getItemStreamFormat(item))
    formats = []

    if url.instr(".m3u8") >= 0 then
        formats.push("hls-direct")
        formats.push("hls-wrapper")
        if getTranscodeServerUrl() <> "" then formats.push("hls-transcode")
        return formats
    end if

    if declared = "hls" then
        formats.push("hls-direct")
        formats.push("hls-wrapper")
        if getTranscodeServerUrl() <> "" then formats.push("hls-transcode")
    else if declared <> "" then
        formats.push(declared)
    end if
    if url.instr(".m3u8") >= 0 then formats.push("hls")
    if url.instr(".mpd") >= 0 then formats.push("dash")
    if url.instr(".ism") >= 0 or url.instr("/manifest") >= 0 then formats.push("ism")
    if url.instr(".ts") >= 0 or url.instr("/live/") >= 0 then formats.push("ts")
    if url.instr(".mp4") >= 0 then formats.push("mp4")

    formats.push("hls-direct")
    formats.push("hls-wrapper")
    if getTranscodeServerUrl() <> "" then formats.push("hls-transcode")
    formats.push("ts")
    formats.push("mp4")

    unique = []
    for each f in formats
        if f <> "" and not arrayContains(unique, f) then
            unique.push(f)
        end if
    end for

    return unique
end function

function arrayContains(values as object, expected as string) as boolean
    for each value in values
        if value = expected then return true
    end for
    return false
end function

function getItemUrl(item as object) as string
    if item = invalid then return ""
    if item.url <> invalid and item.url <> "" then return sanitizeUrl(item.url)
    if item.Url <> invalid and item.Url <> "" then return sanitizeUrl(item.Url)
    return ""
end function

function getPlaybackSourceUrl(item as object) as string
    if item = invalid then return ""
    if item.sourceUrl <> invalid and item.sourceUrl <> "" then return sanitizeUrl(item.sourceUrl)
    if item.SourceUrl <> invalid and item.SourceUrl <> "" then return sanitizeUrl(item.SourceUrl)
    return ""
end function

function sanitizeUrl(urlValue as dynamic) as string
    if urlValue = invalid then return ""
    url = urlValue
    url = url.Trim()
    url = url.Replace(Chr(13), "")
    url = url.Replace(Chr(10), "")
    return url
end function

function getItemTitle(item as object) as string
    if item = invalid then return ""
    if item.title <> invalid and item.title <> "" then return item.title
    if item.Title <> invalid and item.Title <> "" then return item.Title
    return "(untitled channel)"
end function

function getItemStreamFormat(item as object) as string
    if item = invalid then return ""
    if item.streamformat <> invalid and item.streamformat <> "" then return item.streamformat
    if item.streamFormat <> invalid and item.streamFormat <> "" then return item.streamFormat
    if item.StreamFormat <> invalid and item.StreamFormat <> "" then return item.StreamFormat
    return ""
end function

' --- Video state handlers ---

sub onVideoStateChange()
    state = m.nodes.Video.state
    if state = "error" then
        print "Video errorCode: "; m.nodes.Video.errorCode; " errorMsg: "; m.nodes.Video.errorMsg
    end if
    if state = "buffering" then
        if not m.isChannelLoading then
            title = getItemTitle(m.nodes.Video.content)
            showPlaybackLoading(title, "Preparing stream")
        end if
        m.nodes.Labels.ChannelCount.text = "Loading channel..."
    else if state = "playing" then
        m.nodes.Labels.ChannelCount.text = "Channel loaded"
        hidePlaybackStatusOverlay()
        if m.state.isFullScreen then
            m.nodes.FadeOutPreview.control = "start"
        else
            m.nodes.FadeOutPreview.control = "stop"
            m.nodes.PreviewPoster.visible = true
            m.nodes.PreviewPoster.opacity = 1.0
        end if
        m.nodes.Timer.control = "start"
        m.errorState = false
        m.minBufferReached = true
        m.forcePlayTimer.control = "stop"
        print "Playback started with format: "; getItemStreamFormat(m.nodes.Video.content)
    else if state = "error" then
        if m.currentPlaybackSourceItem <> invalid and m.currentPlaybackFormatIndex + 1 < m.currentPlaybackFormats.count() then
            m.currentPlaybackFormatIndex++
            nextFmt = m.currentPlaybackFormats[m.currentPlaybackFormatIndex]
            m.nodes.Labels.ChannelCount.text = "Retrying format: " + nextFmt
            print "Retrying playback with format: "; nextFmt
            attemptPlaybackWithCurrentFormat(m.currentPlaybackSourceItem)
            return
        end if
        runStreamProbe(m.currentPlaybackSourceItem)
        failedTitle = getItemTitle(m.currentPlaybackSourceItem)
        showPlaybackFailure(failedTitle)
        m.nodes.Labels.ChannelCount.text = "Failed to load channel"
        if not m.state.isFullScreen then
            m.nodes.PreviewPoster.visible = true
            m.nodes.PreviewPoster.opacity = 1.0
        end if
        m.errorState = true
        m.errorResetTimer.control = "start"
        m.forcePlayTimer.control = "stop"
    else if state = "stopped" or state = "finished" then
        if m.errorState then
            m.nodes.Labels.ChannelCount.text = "Failed to load channel"
        else if m.isChannelLoading then
            m.nodes.Labels.ChannelCount.text = "Loading channel..."
        else
            showLoadedChannelsText()
            hidePlaybackStatusOverlay()
            if not m.state.isFullScreen then
                m.nodes.PreviewPoster.visible = true
                m.nodes.PreviewPoster.opacity = 1.0
            end if
        end if
        m.forcePlayTimer.control = "stop"
    end if
    if not m.state.isFullScreen then
        applyPipVideoLayout()
        m.nodes.Video.enableUI = false
        if m.nodes.PlaybackStatus.Overlay.visible then positionPlaybackStatusOverlay()
    end if
end sub

sub onBufferingStatusChange()
    status = m.nodes.Video.bufferingStatus
    if status <> invalid and status.percentage <> invalid and m.nodes.Video.state = "buffering" then
        m.nodes.Labels.ChannelCount.text = "Loading channel..."
        if status.percentage >= 5 and not m.minBufferReached then
            m.nodes.Video.control = "play"
            m.minBufferReached = true
            m.forcePlayTimer.control = "stop"
        end if
    end if
end sub

sub forcePlayVideo()
    if m.nodes.Video.state = "buffering" and not m.minBufferReached then
        m.nodes.Video.control = "play"
        m.minBufferReached = true
    end if
end sub

sub resetErrorState()
    m.errorState = false
    if m.nodes.PlaybackStatus.Overlay.visible and m.nodes.PlaybackStatus.Title.text = "Failed to load channel" then
        m.nodes.Labels.ChannelCount.text = "Failed to load channel"
        return
    end if
    if m.nodes.Video.state = "stopped" or m.nodes.Video.state = "finished" then
        showLoadedChannelsText()
    end if
end sub

sub restoreChannelCount()
    if m.state.isFullScreen then
        m.nodes.InfoBar.visible = false
    end if
    if not m.errorState then
        showLoadedChannelsText()
    end if
end sub

' --- Content loading and rendering ---

sub rowListContentChanged()
    if m.LoadTask = invalid or m.LoadTask.content = invalid then return
    renderContent(m.LoadTask.content)
    buildFlatChannelList()
end sub

sub runStreamProbe(item as object)
    if item = invalid then return
    url = getItemUrl(item)
    if url = "" then return
    if m.lastProbeUrl = url then return
    m.lastProbeUrl = url

    m.StreamProbeTask = createObject("roSGNode", "StreamProbeTask")
    if m.StreamProbeTask = invalid then
        print "StreamProbeTask creation failed"
        return
    end if
    m.StreamProbeTask.observeField("report", "onStreamProbeReport")
    m.StreamProbeTask.observeField("error", "onStreamProbeError")
    m.StreamProbeTask.probeUrl = url
    m.StreamProbeTask.userAgent = getItemField(item, "userAgent")
    m.StreamProbeTask.referrer = getItemField(item, "referrer")
    m.StreamProbeTask.origin = getItemField(item, "origin")
    m.StreamProbeTask.cookie = getItemField(item, "cookie")
    m.StreamProbeTask.control = "RUN"
    print "Stream probe started for: "; url
end sub

sub onStreamProbeReport()
    if m.StreamProbeTask = invalid then return
    if m.StreamProbeTask.report <> "" then
        print "Stream probe report:"
        print m.StreamProbeTask.report
    end if
end sub

sub onStreamProbeError()
    if m.StreamProbeTask = invalid then return
    if m.StreamProbeTask.error <> "" then
        print "Stream probe error: "; m.StreamProbeTask.error
    end if
end sub

sub loadXmltvGuide(xmltvUrl as string)
    if xmltvUrl = "" then return
    m.XmltvTask = createObject("roSGNode", "XmltvLoader")
    if m.XmltvTask = invalid then
        print "XMLTV loader task creation failed"
        return
    end if
    m.XmltvTask.observeField("guideJson", "onXmltvGuideLoaded")
    m.XmltvTask.observeField("error", "onXmltvGuideError")
    m.XmltvTask.xmltvUrl = xmltvUrl
    m.XmltvTask.control = "RUN"
    m.nodes.Labels.Category2.text = "Loading guide data..."
    m.nodes.GuideTickTimer.control = "stop"
    m.nodes.XmltvRefreshTimer.control = "stop"
    print "Loading XMLTV guide: "; xmltvUrl
end sub

sub onXmltvGuideLoaded()
    if m.XmltvTask = invalid then return
    guideJson = m.XmltvTask.guideJson
    if guideJson = invalid or guideJson = "" then return

    parsed = parseJSON(guideJson)
    if parsed = invalid or type(parsed) <> "roAssociativeArray" then
        print "XMLTV parse failed: guide JSON invalid"
        return
    end if

    m.epgByChannel = parsed
    applyGuideDataToVisibleRows(true)
    m.nodes.GuideTickTimer.control = "start"
    m.nodes.XmltvRefreshTimer.control = "start"
    print "XMLTV guide loaded keys: "; m.epgByChannel.count()
end sub

sub onXmltvGuideError()
    if m.XmltvTask = invalid then return
    err = m.XmltvTask.error
    if err <> "" then
        print "XMLTV error: "; err
        m.nodes.Labels.Category2.text = "Guide unavailable"
    end if
end sub

sub onGuideTick()
    if m.epgByChannel = invalid or type(m.epgByChannel) <> "roAssociativeArray" then return
    focusRow = currentChannelFocusRow()
    if focusRow < 0 then focusRow = 0
    applyGuideDataToRowsNear(focusRow, true)
    updateGuidePanelForFocusedItem()
end sub

sub onXmltvRefreshTimer()
    if m.currentXmltvUrl <> invalid and m.currentXmltvUrl <> "" then
        print "Refreshing XMLTV guide: "; m.currentXmltvUrl
        loadXmltvGuide(m.currentXmltvUrl)
    end if
end sub

sub stopXmltvTimers()
    m.nodes.GuideTickTimer.control = "stop"
    m.nodes.XmltvRefreshTimer.control = "stop"
end sub

sub applyGuideDataToVisibleRows(preserveFocus as boolean)
    if m.content = invalid then return
    rowCount = m.content.getChildCount()
    if rowCount = 0 then return
    focusRow = -1
    if preserveFocus then focusRow = currentChannelFocusRow()

    applyGuideDataToRowRange(0, rowCount - 1, true)
    if preserveFocus and focusRow >= 0 then
        updateCategoryLabelText(focusRow)
        updateGuidePanelForFocusedItem()
    end if
end sub

sub ensureGuideRowsNear(row as integer)
    if m.guideSlideOffset <> 0 then return
    if m.epgByChannel = invalid or type(m.epgByChannel) <> "roAssociativeArray" then return
    if m.epgByChannel.count() = 0 then return

    applyGuideDataToRowsNear(row, false)
end sub

sub applyGuideDataToRowsNear(row as integer, forceUpdate as boolean)
    if m.content = invalid then return
    rowCount = m.content.getChildCount()
    if rowCount = 0 then return

    startRow = row - 4
    endRow = row + 8
    if startRow < 0 then startRow = 0
    if endRow >= rowCount then endRow = rowCount - 1
    applyGuideDataToRowRange(startRow, endRow, forceUpdate)
end sub

sub applyGuideDataToRowRange(startRow as integer, endRow as integer, forceUpdate as boolean)
    if m.content = invalid then return
    rowCount = m.content.getChildCount()
    if rowCount = 0 then return
    if startRow < 0 then startRow = 0
    if endRow >= rowCount then endRow = rowCount - 1
    if startRow > endRow then return

    windowStart = currentGuideWindowStart()

    for i = startRow to endRow
        applyGuideDataToRow(i, windowStart, forceUpdate)
    end for
end sub

sub applyGuideDataToRow(row as integer, windowStart as integer, forceUpdate as boolean)
    if m.content = invalid then return
    if row < 0 or row >= m.content.getChildCount() then return

    ch = m.content.getChild(row)
    if ch = invalid or ch.isLoading then return

    ensureGuideFields(ch)
    if not forceUpdate and m.guideSlideOffset = 0 and ch.guideWindowStart <> invalid and int(ch.guideWindowStart) = windowStart then return

    clearGuideFields(ch)
    epg = lookupEpgForChannel(ch)
    if epg <> invalid then
        if m.guideSlideOffset = 0 or ch.epgNow = invalid then
            guideInfo = currentGuideInfo(epg)
            ch.epgNow = guideInfo.nowTitle
            ch.epgNext = guideInfo.nextTitle
        end if
        populateGuideFieldsForWindow(ch, epg, windowStart)
    else
        ch.epgNow = ""
        ch.epgNext = ""
    end if

    ch.guideWindowStart = windowStart
    ch.guideSlideOffset = m.guideSlideOffset
    version = 0
    if ch.guideVersion <> invalid then version = int(ch.guideVersion)
    ch.guideVersion = version + 1
end sub

sub updateCategoryLabelText(row as integer)
    if m.content = invalid then return
    totalRows = m.content.getChildCount()
    if totalRows = 0 then return
    if row < 0 or row >= totalRows then return
    focusedItem = m.content.getChild(row)
    if focusedItem = invalid then
        m.nodes.Labels.Category.text = ""
        m.nodes.Labels.Category2.text = ""
        return
    end if

    m.nodes.Labels.Category.text = getItemTitle(focusedItem)
    m.nodes.Labels.Category2.text = ""
    m.state.lastRow = row
end sub

sub ensureGuideFields(ch as object)
    if ch = invalid then return
    if ch.guideVisible = invalid then ch.addField("guideVisible", "boolean", true)
    if ch.guideVersion = invalid then ch.addField("guideVersion", "integer", true)
    if ch.guideSlideOffset = invalid then ch.addField("guideSlideOffset", "integer", true)
    if ch.guideWindowStart = invalid then ch.addField("guideWindowStart", "integer", true)

    if ch.guide0Title = invalid then ch.addField("guide0Title", "string", true)
    if ch.guide0Time = invalid then ch.addField("guide0Time", "string", true)
    if ch.guide0X = invalid then ch.addField("guide0X", "integer", true)
    if ch.guide0Width = invalid then ch.addField("guide0Width", "integer", true)

    if ch.guide1Title = invalid then ch.addField("guide1Title", "string", true)
    if ch.guide1Time = invalid then ch.addField("guide1Time", "string", true)
    if ch.guide1X = invalid then ch.addField("guide1X", "integer", true)
    if ch.guide1Width = invalid then ch.addField("guide1Width", "integer", true)

    if ch.guide2Title = invalid then ch.addField("guide2Title", "string", true)
    if ch.guide2Time = invalid then ch.addField("guide2Time", "string", true)
    if ch.guide2X = invalid then ch.addField("guide2X", "integer", true)
    if ch.guide2Width = invalid then ch.addField("guide2Width", "integer", true)

    if ch.guide3Title = invalid then ch.addField("guide3Title", "string", true)
    if ch.guide3Time = invalid then ch.addField("guide3Time", "string", true)
    if ch.guide3X = invalid then ch.addField("guide3X", "integer", true)
    if ch.guide3Width = invalid then ch.addField("guide3Width", "integer", true)

    if ch.guide4Title = invalid then ch.addField("guide4Title", "string", true)
    if ch.guide4Time = invalid then ch.addField("guide4Time", "string", true)
    if ch.guide4X = invalid then ch.addField("guide4X", "integer", true)
    if ch.guide4Width = invalid then ch.addField("guide4Width", "integer", true)

    if ch.guide5Title = invalid then ch.addField("guide5Title", "string", true)
    if ch.guide5Time = invalid then ch.addField("guide5Time", "string", true)
    if ch.guide5X = invalid then ch.addField("guide5X", "integer", true)
    if ch.guide5Width = invalid then ch.addField("guide5Width", "integer", true)
end sub

sub clearGuideFields(ch as object)
    if ch = invalid then return
    ch.guideVisible = false
    setGuideField(ch, 0, "", "", 0, 0)
    setGuideField(ch, 1, "", "", 0, 0)
    setGuideField(ch, 2, "", "", 0, 0)
    setGuideField(ch, 3, "", "", 0, 0)
    setGuideField(ch, 4, "", "", 0, 0)
    setGuideField(ch, 5, "", "", 0, 0)
end sub

sub populateGuideFieldsForWindow(ch as object, epg as object, windowStart as integer)
    if ch = invalid or epg = invalid then return
    programs = guideProgramsForWindow(epg, windowStart, windowStart + m.guideWindowSeconds, m.guideProgramSlots)
    if programs.count() = 0 then return

    ch.guideVisible = true
    for i = 0 to programs.count() - 1
        program = programs[i]
        x = guideProgramX(program.startSeconds, windowStart)
        width = guideProgramWidth(program.startSeconds, program.stopSeconds, windowStart)
        if width < 80 then width = 80
        if x + width > m.guideGridWidth then width = m.guideGridWidth - x
        if width < 40 then
            if x > m.guideGridWidth - 40 then x = m.guideGridWidth - 40
            width = 40
        end if

        setGuideField(ch, i, cleanGuideText(program.title), formatGuideTimeRange(program.startSeconds, program.stopSeconds), x, width)
    end for
end sub

sub refreshGuideWindow(preserveFocus as boolean)
    if m.epgByChannel = invalid or type(m.epgByChannel) <> "roAssociativeArray" then return
    if m.epgByChannel.count() = 0 then return
    focusRow = currentChannelFocusRow()
    if focusRow < 0 then focusRow = 0
    applyGuideDataToRowsNear(focusRow, true)
    if preserveFocus and focusRow >= 0 then updateCategoryLabelText(focusRow)
    updateGuidePanelForFocusedItem()
end sub

function moveGuideWindow(deltaSeconds as integer) as boolean
    if m.epgByChannel = invalid or type(m.epgByChannel) <> "roAssociativeArray" then return false
    if m.epgByChannel.count() = 0 then return false

    nextOffset = m.guideTimeOffsetSeconds + deltaSeconds
    if nextOffset < 0 then nextOffset = 0
    if nextOffset > m.guideMaxOffsetSeconds then nextOffset = m.guideMaxOffsetSeconds
    if nextOffset = m.guideTimeOffsetSeconds then return true

    m.guideTimeOffsetSeconds = nextOffset
    m.guideSlideOffset = guideSlideOffsetForDelta(deltaSeconds)
    refreshGuideWindow(true)
    m.guideSlideOffset = 0
    showLoadedChannelsText()
    return true
end function

function guideSlideOffsetForDelta(deltaSeconds as integer) as integer
    if deltaSeconds = 0 then return 0
    offset = int((deltaSeconds * m.guideGridWidth) / m.guideWindowSeconds)
    if offset > m.guideGridWidth then offset = m.guideGridWidth
    if offset < -m.guideGridWidth then offset = -m.guideGridWidth
    return offset
end function

sub setGuideField(ch as object, index as integer, title as string, timeText as string, x as integer, width as integer)
    if index = 0 then
        ch.guide0Title = title
        ch.guide0Time = timeText
        ch.guide0X = x
        ch.guide0Width = width
    else if index = 1 then
        ch.guide1Title = title
        ch.guide1Time = timeText
        ch.guide1X = x
        ch.guide1Width = width
    else if index = 2 then
        ch.guide2Title = title
        ch.guide2Time = timeText
        ch.guide2X = x
        ch.guide2Width = width
    else if index = 3 then
        ch.guide3Title = title
        ch.guide3Time = timeText
        ch.guide3X = x
        ch.guide3Width = width
    else if index = 4 then
        ch.guide4Title = title
        ch.guide4Time = timeText
        ch.guide4X = x
        ch.guide4Width = width
    else if index = 5 then
        ch.guide5Title = title
        ch.guide5Time = timeText
        ch.guide5X = x
        ch.guide5Width = width
    end if
end sub

function currentChannelFocusRow() as integer
    if m.content = invalid then return -1
    rowCount = m.content.getChildCount()
    if rowCount = 0 then return -1

    row = m.state.lastRow
    if row = invalid or row < 0 then row = m.nodes.RowList.itemFocused
    if row = invalid or row < 0 then row = 0
    if row >= rowCount then row = rowCount - 1

    return row
end function

sub restoreChannelFocusRow(row as integer)
    if row < 0 then return
    if m.content = invalid then return

    rowCount = m.content.getChildCount()
    if rowCount = 0 then return
    if row >= rowCount then row = rowCount - 1

    m.nodes.RowList.jumpToItem = row
    updateCategoryLabel(row)
end sub

function lookupEpgForChannel(ch as object) as object
    if m.epgByChannel = invalid or type(m.epgByChannel) <> "roAssociativeArray" then return invalid
    tvgId = normalizeGuideKey(getItemTvgId(ch))
    tvgName = normalizeGuideKey(getItemTvgName(ch))
    titleKey = normalizeGuideKey(getItemTitle(ch))

    if tvgId <> "" and m.epgByChannel.doesExist(tvgId) then return m.epgByChannel[tvgId]
    if tvgName <> "" and m.epgByChannel.doesExist(tvgName) then return m.epgByChannel[tvgName]
    if titleKey <> "" and m.epgByChannel.doesExist(titleKey) then return m.epgByChannel[titleKey]
    return invalid
end function

sub updateGuidePanelForFocusedItem()
    if m.content = invalid then
        hideGuidePanel()
        return
    end if
    if m.content.getChildCount() = 0 then
        hideGuidePanel()
        return
    end if

    if m.currentScreen <> "main" or m.state.isFullScreen then
        hideGuidePanel()
        return
    end if

    if m.epgByChannel = invalid or type(m.epgByChannel) <> "roAssociativeArray" or m.epgByChannel.count() = 0 then
        hideGuidePanel()
        return
    end if

    timeStart = currentGuideWindowStart()
    updateGuideTimeHeaders(timeStart)
    m.nodes.GuidePanel.Container.visible = true
end sub

sub hideGuidePanel()
    if m.nodes = invalid then return
    if m.nodes.GuidePanel = invalid then return
    m.nodes.GuidePanel.Container.visible = false
end sub

function cleanGuideText(value as dynamic) as string
    if value = invalid then return ""
    text = value.toStr()
    text = text.Replace(chr(9), " ")
    text = text.Replace(chr(10), " ")
    text = text.Replace(chr(13), " ")
    text = text.Trim()

    while text.instr("  ") >= 0
        text = text.Replace("  ", " ")
    end while

    return text
end function

function guideProgramsForWindow(epg as object, windowStart as integer, windowEnd as integer, maxCount as integer) as object
    result = []
    if epg = invalid or maxCount <= 0 then return result
    if type(epg) <> "roAssociativeArray" then return result
    if not epg.doesExist("programs") or epg.programs = invalid then return result

    for each pr in epg.programs
        if pr <> invalid then
            startSeconds = getGuideProgramSeconds(pr, "start")
            stopSeconds = getGuideProgramSeconds(pr, "stop")
            title = getGuideProgramTitle(pr)
            if stopSeconds <= startSeconds then stopSeconds = startSeconds + 1800

            if title <> "" and startSeconds < windowEnd and stopSeconds > windowStart then
                sortValue = startSeconds
                if sortValue < windowStart then sortValue = windowStart
                candidate = {
                    title: title
                    startSeconds: startSeconds
                    stopSeconds: stopSeconds
                    sortSeconds: sortValue
                }
                addGuideProgramCandidate(result, candidate, maxCount)
            end if
        end if
    end for

    sortGuideProgramsByStart(result)
    return result
end function

sub addGuideProgramCandidate(result as object, candidate as object, maxCount as integer)
    if result.count() < maxCount then
        result.push(candidate)
        return
    end if

    worstIndex = -1
    worstSort = -1
    for i = 0 to result.count() - 1
        item = result[i]
        if item <> invalid and item.sortSeconds <> invalid then
            if worstIndex < 0 or item.sortSeconds > worstSort then
                worstIndex = i
                worstSort = item.sortSeconds
            end if
        end if
    end for

    if worstIndex >= 0 and candidate.sortSeconds < worstSort then result[worstIndex] = candidate
end sub

sub sortGuideProgramsByStart(programs as object)
    if programs = invalid then return
    count = programs.count()
    if count < 2 then return

    for i = 0 to count - 2
        minIndex = i
        minSort = programs[i].sortSeconds
        for j = i + 1 to count - 1
            if programs[j].sortSeconds < minSort then
                minIndex = j
                minSort = programs[j].sortSeconds
            end if
        end for

        if minIndex <> i then
            temp = programs[i]
            programs[i] = programs[minIndex]
            programs[minIndex] = temp
        end if
    end for
end sub

function currentGuideWindowStart() as integer
    nowSeconds = currentEpochSeconds()
    if nowSeconds <= 0 then return 0
    halfHour = 1800
    return (int(nowSeconds / halfHour) * halfHour) + m.guideTimeOffsetSeconds
end function

sub updateGuideTimeHeaders(windowStart as integer)
    if m.nodes = invalid then return
    if m.nodes.GuidePanel = invalid then return
    for i = 0 to m.nodes.GuidePanel.TimeHeaders.count() - 1
        m.nodes.GuidePanel.TimeHeaders[i].text = formatGuideClock(windowStart + (i * 1800))
    end for
end sub

function guideProgramX(startSeconds as integer, windowStart as integer) as integer
    effectiveStart = startSeconds
    if effectiveStart > windowStart and effectiveStart - windowStart <= 300 then effectiveStart = windowStart
    if effectiveStart < windowStart then effectiveStart = windowStart
    offset = effectiveStart - windowStart
    if offset < 0 then offset = 0
    if offset > m.guideWindowSeconds then offset = m.guideWindowSeconds
    return int((offset * m.guideGridWidth) / m.guideWindowSeconds)
end function

function guideProgramWidth(startSeconds as integer, stopSeconds as integer, windowStart as integer) as integer
    effectiveStart = startSeconds
    if effectiveStart > windowStart and effectiveStart - windowStart <= 300 then effectiveStart = windowStart
    if effectiveStart < windowStart then effectiveStart = windowStart

    effectiveStop = stopSeconds
    if effectiveStop <= startSeconds then effectiveStop = startSeconds + 1800
    windowEnd = windowStart + m.guideWindowSeconds
    if effectiveStop > windowEnd then effectiveStop = windowEnd

    duration = effectiveStop - effectiveStart
    if duration <= 0 then duration = 300
    return int((duration * m.guideGridWidth) / m.guideWindowSeconds)
end function

function formatGuideTimeRange(startSeconds as integer, stopSeconds as integer) as string
    startText = formatGuideClock(startSeconds)
    if startText = "" then return ""

    if stopSeconds > startSeconds then
        stopText = formatGuideClock(stopSeconds)
        if stopText <> "" then return startText + " - " + stopText
    end if

    return startText
end function

function formatGuideClock(seconds as integer) as string
    if seconds <= 0 then return ""
    dt = createObject("roDateTime")
    if dt = invalid then return ""

    dt.FromSeconds(seconds)
    dt.ToLocalTime()

    hour = dt.GetHours()
    minute = dt.GetMinutes()
    suffix = "AM"
    if hour >= 12 then suffix = "PM"

    displayHour = hour
    if displayHour = 0 then displayHour = 12
    if displayHour > 12 then displayHour = displayHour - 12

    return displayHour.toStr() + ":" + padTwoDigits(minute) + " " + suffix
end function

function padTwoDigits(value as integer) as string
    if value < 10 then return "0" + value.toStr()
    return value.toStr()
end function

function currentGuideInfo(epg as object) as object
    result = {nowTitle: "", nextTitle: ""}
    if epg = invalid then return result

    if type(epg) = "roAssociativeArray" and epg.doesExist("programs") and epg.programs <> invalid then
        nowSeconds = currentEpochSeconds()
        bestNowStart = 0
        bestNextStart = 0

        for each pr in epg.programs
            if pr <> invalid then
                startSeconds = getGuideProgramSeconds(pr, "start")
                stopSeconds = getGuideProgramSeconds(pr, "stop")
                title = getGuideProgramTitle(pr)

                if title <> "" and startSeconds > 0 then
                    if startSeconds <= nowSeconds and (stopSeconds = 0 or stopSeconds > nowSeconds) then
                        if bestNowStart = 0 or startSeconds > bestNowStart then
                            bestNowStart = startSeconds
                            result.nowTitle = title
                        end if
                    else if startSeconds > nowSeconds then
                        if bestNextStart = 0 or startSeconds < bestNextStart then
                            bestNextStart = startSeconds
                            result.nextTitle = title
                        end if
                    end if
                end if
            end if
        end for

        return result
    end if

    if type(epg) = "roAssociativeArray" then
        if epg.doesExist("nowTitle") and epg.nowTitle <> invalid then result.nowTitle = epg.nowTitle
        if epg.doesExist("nextTitle") and epg.nextTitle <> invalid then result.nextTitle = epg.nextTitle
    end if
    return result
end function

function currentEpochSeconds() as integer
    dt = createObject("roDateTime")
    if dt = invalid then return 0
    return dt.AsSeconds()
end function

function getGuideProgramSeconds(program as object, fieldName as string) as integer
    if program = invalid or type(program) <> "roAssociativeArray" then return 0
    if not program.doesExist(fieldName) or program[fieldName] = invalid then return 0
    return int(program[fieldName])
end function

function getGuideProgramTitle(program as object) as string
    if program = invalid or type(program) <> "roAssociativeArray" then return ""
    if program.doesExist("title") and program.title <> invalid then return program.title.toStr()
    return ""
end function

function getItemTvgId(item as object) as string
    if item = invalid then return ""
    if item.tvgId <> invalid and item.tvgId <> "" then return item.tvgId
    if item.tvgID <> invalid and item.tvgID <> "" then return item.tvgID
    if item.tvg_id <> invalid and item.tvg_id <> "" then return item.tvg_id
    return ""
end function

function getItemTvgName(item as object) as string
    if item = invalid then return ""
    if item.tvgName <> invalid and item.tvgName <> "" then return item.tvgName
    if item.tvg_name <> invalid and item.tvg_name <> "" then return item.tvg_name
    return ""
end function

function normalizeGuideKey(value as dynamic) as string
    if value = invalid then return ""
    key = lcase(value.Trim())
    key = key.Replace("&amp;", "&")
    return key
end function

sub renderContent(sourceContent as object)
    m.searchActive = false
    m.searchTerm = ""
    m.content = createObject("roSGNode", "ContentNode")
    channels = 0
    m.currentGuideTitle = ""

    ' Vertical mode: one channel per row for up/down navigation.
    for each cat in sourceContent.getChildren(-1, 0)
        categoryTitle = cat.title
        if m.currentGuideTitle = "" then
            if categoryTitle <> invalid then
                if categoryTitle <> "" then m.currentGuideTitle = categoryTitle
            end if
        end if
        for each ch in cat.getChildren(-1, 0)
            chClone = ch.clone(true)
            chClone.addField("isLoading", "boolean", true)
            chClone.isLoading = false
            chClone.addField("category", "string", true)
            chClone.category = categoryTitle
            chClone.addField("epgNow", "string", true)
            chClone.epgNow = ""
            chClone.addField("epgNext", "string", true)
            chClone.epgNext = ""

            m.content.appendChild(chClone)
            channels++
        end for
    end for

    m.totalChannels = channels
    m.guideSlideOffset = 0
    applyGuideDataToVisibleRows(false)
    m.nodes.RowList.content = m.content
    showLoadedChannelsText()
    m.nodes.LoadingAnim1.control = "stop"
    m.nodes.LoadingAnim2.control = "stop"
    m.nodes.Labels.Category.opacity = 1.0
    m.nodes.Labels.Category2.opacity = 1.0
    m.isLoadingList = false
    m.loadingTimer.control = "stop"

    m.nodes.Labels.Category.text = "Channels"
    m.nodes.Labels.Category2.text = ""

    print "Content loaded: "; channels; " channels in vertical list"
end sub

' --- Search ---

sub filterContent(term)
    if m.LoadTask = invalid or m.LoadTask.content = invalid then return
    m.searchActive = true
    m.searchTerm = term
    m.content = createObject("roSGNode", "ContentNode")
    termLower = lcase(term)
    count = 0
    for each cat in m.LoadTask.content.getChildren(-1, 0)
        for each ch in cat.getChildren(-1, 0)
            if lcase(ch.title).instr(termLower) >= 0 then
                chClone = ch.clone(true)
                chClone.addField("isLoading", "boolean", true)
                chClone.isLoading = false
                chClone.addField("category", "string", true)
                chClone.category = cat.title
                chClone.addField("epgNow", "string", true)
                chClone.epgNow = ""
                chClone.addField("epgNext", "string", true)
                chClone.epgNext = ""
                m.content.appendChild(chClone)
                count++
            end if
        end for
    end for
    applyGuideDataToVisibleRows(false)
    m.nodes.RowList.content = m.content
    if count > 0 then
        m.nodes.Labels.ChannelCount.text = "Results: " + count.toStr()
        m.state.lastRow = 0
        m.nodes.RowList.jumpToItem = 0
        m.nodes.Labels.Category.text = "Search: " + term
        m.nodes.Labels.Category2.text = "Up/Down to browse results"
    else
        m.state.lastRow = 0
        hideGuidePanel()
        m.nodes.Labels.ChannelCount.text = "No results found"
        m.nodes.Labels.Category.text = "Search: " + term
        m.nodes.Labels.Category2.text = "No matching channels"
    end if
end sub

sub clearSearch()
    if not m.searchActive then return
    stopFastChannelScroll()

    focusedItem = invalid
    focusRow = currentChannelFocusRow()
    if m.content <> invalid and focusRow >= 0 and focusRow < m.content.getChildCount() then focusedItem = m.content.getChild(focusRow)

    if m.LoadTask = invalid or m.LoadTask.content = invalid then
        m.searchActive = false
        m.searchTerm = ""
        return
    end if

    renderContent(m.LoadTask.content)

    targetRow = findMatchingVisibleChannelRow(focusedItem)
    if targetRow < 0 then targetRow = 0
    restoreChannelFocusRow(targetRow)
    showLoadedChannelsText()
    m.nodes.RowList.setFocus(true)
end sub

function findMatchingVisibleChannelRow(targetItem as object) as integer
    if targetItem = invalid or m.content = invalid then return -1

    targetUrl = getItemUrl(targetItem)
    targetTvgId = normalizeGuideKey(getItemTvgId(targetItem))
    targetTitle = normalizeGuideKey(getItemTitle(targetItem))

    for i = 0 to m.content.getChildCount() - 1
        ch = m.content.getChild(i)
        if ch <> invalid then
            if targetUrl <> "" and getItemUrl(ch) = targetUrl then return i
            if targetTvgId <> "" and normalizeGuideKey(getItemTvgId(ch)) = targetTvgId then return i
            if targetTitle <> "" and normalizeGuideKey(getItemTitle(ch)) = targetTitle then return i
        end if
    end for

    return -1
end function

' --- Menu ---

sub updateMenuFocus()
    for i = 0 to m.nodes.MenuItems.getChildCount() - 1
        item = m.nodes.MenuItems.getChild(i)
        label = item.findNode("MenuLabel" + i.toStr())
        icon = item.findNode("IconHighlight" + i.toStr())
        label.visible = true
        if i = m.state.menuItem then
            label.color = "0xE63946FF"
            icon.visible = true
        else
            label.color = "0xFFFFFFFF"
            icon.visible = false
        end if
    end for
end sub

sub hideMenuLabels()
    for i = 0 to m.nodes.MenuItems.getChildCount() - 1
        item = m.nodes.MenuItems.getChild(i)
        item.findNode("MenuLabel" + i.toStr()).visible = false
        item.findNode("IconHighlight" + i.toStr()).visible = false
    end for
end sub

sub selectMenuItem()
    m.state.menuFocused = false
    m.nodes.CollapseMenu.control = "start"
    hideMenuLabels()

    if m.state.menuItem = 0 then
        ' Home - just focus the row list
        m.nodes.RowList.setFocus(true)
    else if m.state.menuItem = 1 then
        ' Search
        kb = createObject("roSGNode", "KeyboardDialog")
        if kb = invalid then return
        kb.title = "Search channels"
        kb.text = ""
        kb.buttons = ["Search", "Cancel"]
        kb.observeField("buttonSelected", "onSearchButtonPressed")
        m.top.dialog = kb
    else if m.state.menuItem = 2 then
        ' Playlists
        showScreen("playlists")
    else if m.state.menuItem = 3 then
        ' Refresh
        m.nodes.RowList.setFocus(true)
        if m.global.lastUrl <> "" then
            startLoadingPlaylist(m.global.lastUrl)
        end if
    else if m.state.menuItem = 4 then
        ' Settings
        showScreen("settings")
    end if
end sub

sub onSearchButtonPressed()
    kb = m.top.dialog
    if kb = invalid then return
    if kb.buttonSelected = 0 and kb.text <> "" then
        filterContent(kb.text)
    end if
    m.top.dialog = invalid
    m.nodes.RowList.setFocus(true)
end sub

' --- Key event handler ---

function onKeyEvent(key, press) as boolean
    if not press then
        if key = "up" or key = "down" then return stopFastChannelScrollForKey(key)
        return false
    end if

    ' Handle overlay screens
    if m.currentScreen = "playlists" then
        if key = "back" then
            showScreen("main")
            return true
        end if
        if key = "rewind" or key = "replay" then
            m.nodes.PlaylistManager.deleteRequest = not m.nodes.PlaylistManager.deleteRequest
            return true
        end if
        return false ' let PlaylistManager handle other keys
    end if

    if m.currentScreen = "settings" then
        if key = "back" then
            showScreen("main")
            return true
        end if
        return false ' let SettingsScreen handle other keys
    end if

    ' Fullscreen video mode
    if m.state.isFullScreen then
        video = m.nodes.Video
        if key = "back" then
            applyPipVideoLayout()
            video.enableUI = false
            setFullScreen(false)
            return true
        end if
        if key = "play" or key = "pause" then video.control = "pause": return true
        if key = "fastforward" then video.seek = video.position + 10: return true
        if key = "rewind" then video.seek = video.position - 10: return true
        ' Channel up/down during fullscreen playback
        if key = "up" then
            playPrevChannel()
            return true
        end if
        if key = "down" then
            playNextChannel()
            return true
        end if
        return true
    end if

    ' Menu navigation
    if m.state.menuFocused then
        itemsCount = m.nodes.MenuItems.getChildCount() - 1
        if key = "right" or key = "back" then
            m.state.menuFocused = false
            m.nodes.RowList.setFocus(true)
            m.nodes.CollapseMenu.control = "start"
            hideMenuLabels()
            return true
        end if
        if key = "up" and m.state.menuItem > 0 then
            m.state.menuItem--
            updateMenuFocus()
            return true
        end if
        if key = "down" and m.state.menuItem < itemsCount then
            m.state.menuItem++
            updateMenuFocus()
            return true
        end if
        if key = "OK" then
            selectMenuItem()
            return true
        end if
    else
        if key = "up" or key = "down" then
            return startChannelListScroll(key)
        end if
        if key = "right" then
            return moveGuideWindow(m.guideStepSeconds)
        end if
        if key = "left" then
            if m.guideTimeOffsetSeconds <> invalid and m.guideTimeOffsetSeconds > 0 then
                return moveGuideWindow(-m.guideStepSeconds)
            end if
            m.state.menuFocused = true
            m.nodes.Menu.setFocus(true)
            m.nodes.ExpandMenu.control = "start"
            updateMenuFocus()
            return true
        end if
        if key = "back" then
            if m.searchActive then
                clearSearch()
                return true
            end if
            ' If video is playing in PIP, go fullscreen
            if m.nodes.Video.state = "playing" and not m.state.isFullScreen and not m.state.menuFocused then
                m.nodes.Video.translation = [0,0]
                m.nodes.Video.width = 1920
                m.nodes.Video.height = 1080
                m.nodes.Video.enableUI = true
                setFullScreen(true)
                return true
            end if
            return true
        end if
    end if
    return false
end function
