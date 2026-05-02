sub init()
    m.Poster = m.top.findNode("poster")
    m.Background = m.top.findNode("background")
    m.LoadingAnimation = m.top.findNode("LoadingAnimation")
    m.TitleLabel = m.top.findNode("titleLabel")
    m.MetaLabel = m.top.findNode("metaLabel")
    m.GuideGroup = m.top.findNode("guideGroup")
    m.GuideContent = m.top.findNode("guideContent")
    m.GuideSlide = m.top.findNode("GuideSlideAnimation")
    m.GuideSlideInterpolator = m.top.findNode("GuideSlideInterpolator")
    m.GuideSlideResetTimer = m.top.findNode("GuideSlideResetTimer")
    m.guideBaseX = 0
    m.guideGridWidth = 1300
    m.guideRowHeight = 95
    m.guideProgramSlots = 6
    m.observedGuideContent = invalid
    m.lastAnimatedGuideVersion = -1
    createGuideCells()
    m.Poster.uri = "pkg:/images/loading.png"
    m.currentUri = "pkg:/images/loading.png"
    m.top.observeField("itemContent", "updateContent")
    m.top.observeField("height", "updateSize")
    m.top.observeField("width", "updateSize")
    m.Poster.observeField("loadStatus", "onPosterLoadStatus")
    if m.GuideSlideResetTimer <> invalid then m.GuideSlideResetTimer.observeField("fire", "resetGuideSlide")
end sub

sub updateContent()
    content = m.top.itemContent
    observeGuideContent(content)
    if content <> invalid
        if content.isLoading = true
            m.Poster.uri = "pkg:/images/loading.png"
            m.currentUri = "pkg:/images/loading.png"
            m.LoadingAnimation.control = "start"
            m.TitleLabel.text = "Loading channels..."
            m.MetaLabel.text = ""
            hideGuideCells()
        else
            m.LoadingAnimation.control = "stop"
            m.Poster.opacity = 1.0
            title = ""
            if content.title <> invalid then title = content.title
            if title = "" and content.Title <> invalid then title = content.Title

            meta = ""
            if (content.epgNow = invalid or content.epgNow = "") and content.category <> invalid and content.category <> "" then
                meta = content.category
            end if

            m.TitleLabel.text = title
            m.MetaLabel.text = meta
            renderGuideCells(content, false)
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

sub observeGuideContent(content as object)
    if m.observedGuideContent <> invalid then
        m.observedGuideContent.unobserveField("guideVersion")
        m.observedGuideContent = invalid
    end if

    if content <> invalid and content.guideVersion <> invalid then
        content.observeField("guideVersion", "onGuideFieldsChanged")
        m.observedGuideContent = content
    end if
end sub

sub onGuideFieldsChanged()
    renderGuideCells(m.top.itemContent, true)
end sub

sub createGuideCells()
    if m.GuideContent = invalid then return
    m.GuideContent.removeChildrenIndex(m.GuideContent.getChildCount(), 0)
    m.guideCells = []

    for i = 0 to m.guideProgramSlots - 1
        cellGroup = createObject("roSGNode", "Group")
        cellGroup.visible = false

        cellBackground = createObject("roSGNode", "Rectangle")
        cellBackground.width = 180
        cellBackground.height = m.guideRowHeight
        cellBackground.color = "0x172A3FFF"
        cellBackground.opacity = 1.0
        cellGroup.appendChild(cellBackground)

        titleLabel = createObject("roSGNode", "Label")
        titleLabel.translation = [0, 10]
        titleLabel.width = 156
        titleLabel.height = 46
        titleLabel.color = "0xFFFFFFFF"
        titleLabel.vertAlign = "center"
        cellGroup.appendChild(titleLabel)

        timeLabel = createObject("roSGNode", "Label")
        timeLabel.translation = [0, 58]
        timeLabel.width = 156
        timeLabel.height = 26
        timeLabel.color = "0x9FBDE8FF"
        timeLabel.vertAlign = "center"
        cellGroup.appendChild(timeLabel)

        m.GuideContent.appendChild(cellGroup)
        m.guideCells.push({container: cellGroup, background: cellBackground, title: titleLabel, time: timeLabel})
    end for
end sub

sub renderGuideCells(content as object, animate as boolean)
    if m.GuideGroup = invalid or m.GuideContent = invalid then return
    if content = invalid then
        hideGuideCells()
        return
    end if
    if content.guideVisible = invalid then
        hideGuideCells()
        return
    end if
    if content.guideVisible = false then
        hideGuideCells()
        return
    end if

    selectedIndex = getGuideSelectedIndex(content)
    for i = 0 to m.guideCells.count() - 1
        cell = m.guideCells[i]
        title = getGuideTitle(content, i)

        if title <> "" then
            x = getGuideX(content, i)
            width = getGuideWidth(content, i)
            if width < 40 then width = 40
            if x < 0 then x = 0
            if x + width > m.guideGridWidth then width = m.guideGridWidth - x
            if width < 40 then width = 40

            cell.container.translation = [x, 0]
            cell.container.clippingRect = [0, 0, width - 4, m.guideRowHeight]
            cell.container.visible = true
            cell.background.width = width - 4
            cell.title.width = width - 8
            cell.time.width = width - 8
            cell.title.text = title
            cell.time.text = getGuideTime(content, i)
            isSelected = (i = selectedIndex)
            applyGuideCellStyle(cell, isSelected)
        else
            cell.container.visible = false
            cell.container.clippingRect = [0, 0, 1, 1]
            cell.title.text = ""
            cell.time.text = ""
        end if
    end for

    animateGuideSlide(content, animate)
end sub

sub hideGuideCells()
    if m.guideCells = invalid then return
    if m.GuideSlide <> invalid then m.GuideSlide.control = "stop"
    if m.GuideContent <> invalid then m.GuideContent.translation = [m.guideBaseX, 0]
    for each cell in m.guideCells
        cell.container.visible = false
        cell.container.clippingRect = [0, 0, 1, 1]
        cell.title.text = ""
        cell.time.text = ""
    end for
end sub

sub animateGuideSlide(content as object, animate as boolean)
    if m.GuideContent = invalid then return

    if not animate then
        m.GuideContent.translation = [m.guideBaseX, 0]
        if content <> invalid and content.guideVersion <> invalid then m.lastAnimatedGuideVersion = int(content.guideVersion)
        return
    end if

    version = -1
    if content <> invalid and content.guideVersion <> invalid then version = int(content.guideVersion)
    if version = m.lastAnimatedGuideVersion then return
    m.lastAnimatedGuideVersion = version

    offset = 0
    if content <> invalid and content.guideSlideOffset <> invalid then offset = int(content.guideSlideOffset)
    if offset = 0 or m.GuideSlide = invalid or m.GuideSlideInterpolator = invalid then
        m.GuideContent.translation = [m.guideBaseX, 0]
        return
    end if

    m.GuideSlide.control = "stop"
    m.GuideContent.translation = [m.guideBaseX + offset, 0]
    m.GuideSlideInterpolator.keyValue = [[m.guideBaseX + offset, 0], [m.guideBaseX, 0]]
    m.GuideSlide.control = "start"
    if m.GuideSlideResetTimer <> invalid then m.GuideSlideResetTimer.control = "start"
end sub

sub resetGuideSlide()
    if m.GuideContent <> invalid then m.GuideContent.translation = [m.guideBaseX, 0]
end sub

sub applyGuideCellStyle(cell as object, selected as boolean)
    if selected then
        cell.background.color = "0x2F7DD8FF"
        cell.title.color = "0xFFFFFFFF"
        cell.time.color = "0xFFFFFFFF"
    else
        cell.background.color = "0x172A3FFF"
        cell.title.color = "0xFFFFFFFF"
        cell.time.color = "0x9FBDE8FF"
    end if
end sub

function getGuideTitle(content as object, index as integer) as string
    if index = 0 and content.guide0Title <> invalid then return content.guide0Title
    if index = 1 and content.guide1Title <> invalid then return content.guide1Title
    if index = 2 and content.guide2Title <> invalid then return content.guide2Title
    if index = 3 and content.guide3Title <> invalid then return content.guide3Title
    if index = 4 and content.guide4Title <> invalid then return content.guide4Title
    if index = 5 and content.guide5Title <> invalid then return content.guide5Title
    return ""
end function

function getGuideTime(content as object, index as integer) as string
    if index = 0 and content.guide0Time <> invalid then return content.guide0Time
    if index = 1 and content.guide1Time <> invalid then return content.guide1Time
    if index = 2 and content.guide2Time <> invalid then return content.guide2Time
    if index = 3 and content.guide3Time <> invalid then return content.guide3Time
    if index = 4 and content.guide4Time <> invalid then return content.guide4Time
    if index = 5 and content.guide5Time <> invalid then return content.guide5Time
    return ""
end function

function getGuideX(content as object, index as integer) as integer
    if index = 0 and content.guide0X <> invalid then return int(content.guide0X)
    if index = 1 and content.guide1X <> invalid then return int(content.guide1X)
    if index = 2 and content.guide2X <> invalid then return int(content.guide2X)
    if index = 3 and content.guide3X <> invalid then return int(content.guide3X)
    if index = 4 and content.guide4X <> invalid then return int(content.guide4X)
    if index = 5 and content.guide5X <> invalid then return int(content.guide5X)
    return 0
end function

function getGuideWidth(content as object, index as integer) as integer
    if index = 0 and content.guide0Width <> invalid then return int(content.guide0Width)
    if index = 1 and content.guide1Width <> invalid then return int(content.guide1Width)
    if index = 2 and content.guide2Width <> invalid then return int(content.guide2Width)
    if index = 3 and content.guide3Width <> invalid then return int(content.guide3Width)
    if index = 4 and content.guide4Width <> invalid then return int(content.guide4Width)
    if index = 5 and content.guide5Width <> invalid then return int(content.guide5Width)
    return 0
end function

function getGuideSelectedIndex(content as object) as integer
    if content <> invalid and content.guideSelectedIndex <> invalid then return int(content.guideSelectedIndex)
    return -1
end function

sub updateSize()
    w = m.top.width
    h = m.top.height
    if w > 0 and h > 0
        m.Background.width = 520
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
