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

    ' Set up PlaylistManager observer
    m.nodes.PlaylistManager.observeField("selectedUrl", "onPlaylistSelected")
    m.nodes.PlaylistManager.observeField("selectedXmltv", "onPlaylistXmltvSelected")

    ' Set up SettingsScreen observer
    m.nodes.SettingsScreen.observeField("viewMode", "onViewModeChanged")
    m.nodes.SettingsScreen.observeField("transcodeServerUrl", "onTranscodeServerUrlChanged")

    ' Set up observers
    m.nodes.RowList.observeField("itemSelected", "ChannelChange")
    m.nodes.RowList.observeField("itemFocused", "onRowItemFocused")
    m.nodes.Timer.observeField("fire", "restoreChannelCount")
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
                if registry.exists("last_xmltv_url") then
                    m.currentXmltvUrl = registry.read("last_xmltv_url")
                else
                    if parsed[0] <> invalid and parsed[0].doesExist("xmltvUrl") then
                        m.currentXmltvUrl = parsed[0].xmltvUrl
                    else
                        m.currentXmltvUrl = ""
                    end if
                end if
            end if
        end if
    end if

    if hasPlaylists and m.global.lastUrl <> "" then
        showScreen("main")
        startLoadingPlaylist(m.global.lastUrl)
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
    hidePlaybackStatusOverlay()

    ' Save as last used
    registry = createObject("roRegistrySection", "KojoStream")
    registry.write("last_used_url", url)
    registry.write("last_xmltv_url", m.currentXmltvUrl)
    registry.flush()

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
    m.top.setFocus(true)
    if screen <> "main" then hidePlaybackStatusOverlay()
    if screen = "main" then
        m.nodes.PlaylistManager.visible = false
        m.nodes.SettingsScreen.visible = false
        m.nodes.RowList.visible = true
        m.nodes.Labels.Category.visible = true
        m.nodes.Labels.Category2.visible = true
        m.nodes.Labels.ChannelCount.visible = true
        m.nodes.Menu.visible = true
        m.nodes.RowList.setFocus(true)
    else if screen = "playlists" then
        m.nodes.PlaylistManager.visible = true
        m.nodes.SettingsScreen.visible = false
        m.nodes.RowList.visible = false
        m.nodes.Labels.Category.visible = false
        m.nodes.Labels.Category2.visible = false
        m.nodes.InfoBar.visible = false
        m.nodes.Menu.visible = false
        m.nodes.PlaylistManager.setFocus(true)
    else if screen = "settings" then
        m.nodes.SettingsScreen.visible = true
        m.nodes.PlaylistManager.visible = false
        m.nodes.RowList.visible = false
        m.nodes.Labels.Category.visible = false
        m.nodes.Labels.Category2.visible = false
        m.nodes.InfoBar.visible = false
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

' --- Row item focus ---

sub onRowItemFocused()
    row = m.nodes.RowList.itemFocused
    if row = invalid or row < 0 or row >= m.content.getChildCount() then return
    item = m.content.getChild(row)
    if item = invalid or item.isLoading then
        m.nodes.InfoBar.visible = false
        m.nodes.PreviewPoster.visible = false
        return
    end if

    m.nodes.Labels.Info.text = item.title
    m.nodes.InfoBar.visible = true
    if item.HDPosterUrl <> "" then
        m.nodes.PreviewPoster.uri = item.HDPosterUrl
    else
        m.nodes.PreviewPoster.uri = "pkg:/images/no-image.png"
    end if

    if not m.state.isFullScreen then
        m.nodes.PreviewPoster.visible = true
        m.nodes.FadeInPreview.control = "start"
    else
        m.nodes.FadeOutPreview.control = "start"
    end if
    updateCategoryLabel(row)
end sub

sub updateCategoryLabel(row)
    totalRows = m.content.getChildCount()
    if totalRows = 0 then return
    focusedItem = m.content.getChild(row)
    m.nodes.Labels.Category.text = getItemTitle(focusedItem)

    guideLine = ""
    if focusedItem <> invalid then
        if focusedItem.category <> invalid and focusedItem.category <> "" then
            guideLine = focusedItem.category
        end if
        if focusedItem.epgNow <> invalid and focusedItem.epgNow <> "" then
            if guideLine <> "" then guideLine = guideLine + "  |  "
            guideLine = guideLine + "Now: " + focusedItem.epgNow
        end if
        if focusedItem.epgNext <> invalid and focusedItem.epgNext <> "" then
            if guideLine <> "" then guideLine = guideLine + "  |  "
            guideLine = guideLine + "Next: " + focusedItem.epgNext
        end if
    end if
    m.nodes.Labels.Category2.text = guideLine
    m.state.lastRow = row
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
            video.translation = [1200,0]
            video.width = 720
            video.height = 405
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

sub setFullScreen(state)
    m.state.isFullScreen = state
    nodes = m.nodes
    nodes.RowList.visible = not state
    nodes.Labels.Category.visible = not state
    nodes.Labels.Category2.visible = not state
    nodes.Labels.ChannelCount.visible = not state
    nodes.InfoBar.visible = not state
    nodes.Menu.visible = not state

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
        nodes.Video.translation = [1200,0]
        nodes.Video.width = 720
        nodes.Video.height = 405
        nodes.Video.enableUI = false
    end if

    if nodes.PlaybackStatus.Overlay.visible then
        positionPlaybackStatusOverlay()
    end if
end sub

sub showPlaybackLoading(title as string, subtitle as string)
    m.isChannelLoading = true
    positionPlaybackStatusOverlay()

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
        nodes.Overlay.translation = [1200,0]
        nodes.Backdrop.width = 720
        nodes.Backdrop.height = 405
        nodes.Card.translation = [80,95]
        nodes.Card.width = 560
        nodes.Card.height = 215
        nodes.Icon.translation = [260,112]
        nodes.Icon.width = 200
        nodes.Icon.height = 64
        nodes.Title.translation = [60,190]
        nodes.Title.width = 600
        nodes.Title.height = 44
        nodes.Subtitle.translation = [60,242]
        nodes.Subtitle.width = 600
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
        m.nodes.FadeOutPreview.control = "start"
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
            m.nodes.FadeInPreview.control = "start"
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
            m.nodes.Labels.ChannelCount.text = "Channels loaded: " + m.totalChannels.toStr()
            hidePlaybackStatusOverlay()
            if not m.state.isFullScreen then
                m.nodes.PreviewPoster.visible = true
                m.nodes.FadeInPreview.control = "start"
            end if
        end if
        m.forcePlayTimer.control = "stop"
    end if
    if not m.state.isFullScreen then
        m.nodes.Video.translation = [1200,0]
        m.nodes.Video.width = 720
        m.nodes.Video.height = 405
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
        m.nodes.Labels.ChannelCount.text = "Channels loaded: " + m.totalChannels.toStr()
    end if
end sub

sub restoreChannelCount()
    if m.state.isFullScreen then
        m.nodes.InfoBar.visible = false
    end if
    if not m.errorState then
        m.nodes.Labels.ChannelCount.text = "Channels loaded: " + m.totalChannels.toStr()
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
    applyGuideDataToVisibleRows()
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

sub applyGuideDataToVisibleRows()
    if m.content = invalid then return
    rowCount = m.content.getChildCount()
    if rowCount = 0 then return

    for i = 0 to rowCount - 1
        ch = m.content.getChild(i)
        if ch = invalid then
            ' skip
        else
            if ch = invalid or ch.isLoading then
                ' skip
            else
                epg = lookupEpgForChannel(ch)
                if epg <> invalid then
                    ch.epgNow = epg.nowTitle
                    ch.epgNext = epg.nextTitle
                else
                    ch.epgNow = ""
                    ch.epgNext = ""
                end if
            end if
        end if
    end for

    m.nodes.RowList.content = m.content
end sub

function lookupEpgForChannel(ch as object) as object
    if m.epgByChannel = invalid or type(m.epgByChannel) <> "roAssociativeArray" then return invalid
    tvgId = normalizeGuideKey(getItemTvgId(ch))
    titleKey = normalizeGuideKey(getItemTitle(ch))

    if tvgId <> "" and m.epgByChannel.doesExist(tvgId) then return m.epgByChannel[tvgId]
    if titleKey <> "" and m.epgByChannel.doesExist(titleKey) then return m.epgByChannel[titleKey]
    return invalid
end function

function getItemTvgId(item as object) as string
    if item = invalid then return ""
    if item.tvgId <> invalid and item.tvgId <> "" then return item.tvgId
    if item.tvgID <> invalid and item.tvgID <> "" then return item.tvgID
    if item.tvg_id <> invalid and item.tvg_id <> "" then return item.tvg_id
    return ""
end function

function normalizeGuideKey(value as dynamic) as string
    if value = invalid then return ""
    key = lcase(value.Trim())
    key = key.Replace("&amp;", "&")
    return key
end function

sub renderContent(sourceContent as object)
    m.content.removeChildrenIndex(m.content.getChildCount(), 0)
    channels = 0

    ' Vertical mode: one channel per row for up/down navigation.
    for each cat in sourceContent.getChildren(-1, 0)
        categoryTitle = cat.title
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

    m.nodes.RowList.content = m.content
    m.totalChannels = channels
    m.nodes.Labels.ChannelCount.text = "Channels loaded: " + channels.toStr()
    m.nodes.LoadingAnim1.control = "stop"
    m.nodes.LoadingAnim2.control = "stop"
    m.nodes.Labels.Category.opacity = 1.0
    m.nodes.Labels.Category2.opacity = 1.0
    m.isLoadingList = false
    m.loadingTimer.control = "stop"

    m.nodes.Labels.Category.text = "Channels"
    if m.currentXmltvUrl <> "" then
        m.nodes.Labels.Category2.text = "Guide source: XMLTV connected"
    else
        m.nodes.Labels.Category2.text = "Guide source: none"
    end if

    applyGuideDataToVisibleRows()
    print "Content loaded: "; channels; " channels in vertical list"
end sub

' --- Search ---

sub filterContent(term)
    if m.LoadTask = invalid or m.LoadTask.content = invalid then return
    m.content.removeChildrenIndex(m.content.getChildCount(), 0)
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
    applyGuideDataToVisibleRows()
    m.nodes.RowList.content = m.content
    if count > 0 then
        m.nodes.Labels.ChannelCount.text = "Results: " + count.toStr()
        m.nodes.RowList.jumpToItem = 0
        m.nodes.Labels.Category.text = "Search: " + term
        m.nodes.Labels.Category2.text = "Up/Down to browse results"
    else
        m.nodes.Labels.ChannelCount.text = "No results found"
        m.nodes.Labels.Category.text = "Search: " + term
        m.nodes.Labels.Category2.text = "No matching channels"
    end if
end sub

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
    if not press then return false

    ' Handle overlay screens
    if m.currentScreen = "playlists" then
        if key = "back" then
            showScreen("main")
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
            video.translation = [1200,0]
            video.width = 720
            video.height = 405
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
        if key = "left" then
            m.state.menuFocused = true
            m.nodes.Menu.setFocus(true)
            m.nodes.ExpandMenu.control = "start"
            updateMenuFocus()
            return true
        end if
        if key = "back" then
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
