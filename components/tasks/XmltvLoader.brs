sub init()
    m.top.functionName = "load"
end sub

sub load()
    url = m.top.xmltvUrl
    if url = invalid or url = "" then
        m.top.error = "No XMLTV URL provided"
        return
    end if

    xmlText = downloadText(url)
    if xmlText = "" then
        m.top.error = "Failed to download XMLTV feed"
        return
    end if

    root = createObject("roXMLElement")
    if root = invalid or not root.parse(xmlText) then
        m.top.error = "Failed to parse XMLTV feed"
        return
    end if

    guide = buildGuideMap(root)
    if guide = invalid then
        m.top.error = "Failed to build XMLTV guide map"
        return
    end if

    m.top.guideJson = formatJSON(guide)
end sub

function downloadText(url as string) as string
    req = createObject("roUrlTransfer")
    if req = invalid then return ""
    req.setUrl(url)
    req.setCertificatesFile("common:/certs/ca-bundle.crt")
    req.enableFreshConnection(true)
    port = createObject("roMessagePort")
    req.setPort(port)

    if not req.AsyncGetToString() then return ""
    msg = wait(45000, port)
    if msg = invalid or type(msg) <> "roUrlEvent" then return ""
    if msg.GetResponseCode() <> 200 then return ""
    return msg.GetString()
end function

function buildGuideMap(root as object) as object
    guide = {}
    channelNameById = {}

    channels = root.getNamedElements("channel")
    if channels <> invalid then
        for each ch in channels
            chId = normalizeKey(ch@id)
            names = ch.getNamedElements("display-name")
            if chId <> "" and names <> invalid and names.count() > 0 then
                channelNameById[chId] = normalizeKey(names[0].getText())
            end if
        end for
    end if

    programmes = root.getNamedElements("programme")
    if programmes = invalid then return guide

    for each pr in programmes
        chId = normalizeKey(pr@channel)
        if chId = "" then
            ' skip
        else
            title = ""
            titles = pr.getNamedElements("title")
            if titles <> invalid and titles.count() > 0 then title = titles[0].getText()
            if title = invalid or title = "" then
                ' skip
            else
                if not guide.doesExist(chId) then
                    guide[chId] = {nowTitle: "", nextTitle: ""}
                end if
                if guide[chId].nowTitle = "" then
                    guide[chId].nowTitle = title
                else if guide[chId].nextTitle = "" and guide[chId].nowTitle <> title then
                    guide[chId].nextTitle = title
                end if
            end if
        end if
    end for

    for each id in channelNameById
        nameKey = channelNameById[id]
        if nameKey <> "" and guide.doesExist(id) and not guide.doesExist(nameKey) then
            guide[nameKey] = guide[id]
        end if
    end for

    return guide
end function

function normalizeKey(value as dynamic) as string
    if value = invalid then return ""
    key = lcase(value.toStr().Trim())
    key = key.Replace("&amp;", "&")
    return key
end function
