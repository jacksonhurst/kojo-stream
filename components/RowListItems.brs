sub init()
    m.Poster = m.top.findNode("poster")
    m.Background = m.top.findNode("background")
    m.LoadingAnimation = m.top.findNode("LoadingAnimation")
    m.TitleLabel = m.top.findNode("titleLabel")
    m.MetaLabel = m.top.findNode("metaLabel")
    m.Poster.uri = "pkg:/images/loading.png"
    m.currentUri = "pkg:/images/loading.png"
    m.top.observeField("itemContent", "updateContent")
    m.top.observeField("height", "updateSize")
    m.top.observeField("width", "updateSize")
    m.Poster.observeField("loadStatus", "onPosterLoadStatus")
end sub

sub updateContent()
    content = m.top.itemContent
    if content <> invalid
        if content.isLoading = true
            m.Poster.uri = "pkg:/images/loading.png"
            m.currentUri = "pkg:/images/loading.png"
            m.LoadingAnimation.control = "start"
            m.TitleLabel.text = "Loading channels..."
            m.MetaLabel.text = ""
        else
            m.LoadingAnimation.control = "stop"
            m.Poster.opacity = 1.0
            title = ""
            if content.title <> invalid then title = content.title
            if title = "" and content.Title <> invalid then title = content.Title

            meta = ""
            if content.category <> invalid and content.category <> "" then meta = content.category
            if content.epgNow <> invalid and content.epgNow <> "" then
                if meta <> "" then meta = meta + "  |  "
                meta = meta + "Now: " + content.epgNow
            end if
            if content.epgNext <> invalid and content.epgNext <> "" then
                if meta <> "" then meta = meta + "  |  "
                meta = meta + "Next: " + content.epgNext
            end if

            m.TitleLabel.text = title
            m.MetaLabel.text = meta
            if content.HDPosterUrl <> invalid and content.HDPosterUrl <> "" and content.HDPosterUrl <> m.currentUri
                m.Poster.loadWidth = 133
                m.Poster.loadHeight = 75
                m.Poster.uri = content.HDPosterUrl
                m.currentUri = content.HDPosterUrl
            else if content.HDPosterUrl = invalid or content.HDPosterUrl = "" then
                m.Poster.uri = "pkg:/images/no-image.png"
                m.currentUri = "pkg:/images/no-image.png"
            end if
        end if
    end if
end sub

sub updateSize()
    w = m.top.width
    h = m.top.height
    if w > 0 and h > 0
        m.Background.width = w
        m.Background.height = h
        posterW = 133
        posterH = h - 20
        if posterH < 40 then posterH = 40
        m.Poster.translation = [10, (h - posterH) / 2]
        m.Poster.width = posterW
        m.Poster.height = posterH
        m.TitleLabel.translation = [160, 10]
        m.TitleLabel.width = w - 180
        m.MetaLabel.translation = [160, 46]
        m.MetaLabel.width = w - 180
    end if
end sub

sub onPosterLoadStatus()
    if m.Poster.loadStatus = "failed" and m.currentUri <> "pkg:/images/no-image.png"
        m.Poster.uri = "pkg:/images/no-image.png"
        m.currentUri = "pkg:/images/no-image.png"
    end if
end sub

sub onLoadingChange()
    if m.top.isLoading
        m.Poster.uri = "pkg:/images/loading.png"
        m.currentUri = "pkg:/images/loading.png"
        m.LoadingAnimation.control = "start"
    else
        m.LoadingAnimation.control = "stop"
        m.Poster.opacity = 1.0
    end if
end sub
