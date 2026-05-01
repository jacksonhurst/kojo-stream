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
    nowSeconds = currentEpochSeconds()

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
                startSeconds = parseXmltvTime(pr@start)
                stopSeconds = parseXmltvTime(pr@stop)
                if not guide.doesExist(chId) then
                    guide[chId] = createGuideEntry()
                end if
                if startSeconds > 0 then
                    guide[chId].programs.push({
                        title: title
                        start: startSeconds
                        stop: stopSeconds
                    })

                    if startSeconds <= nowSeconds and (stopSeconds = 0 or stopSeconds > nowSeconds) then
                        guide[chId].nowTitle = title
                    else if startSeconds > nowSeconds then
                        if guide[chId].nextTitle = "" or startSeconds < guide[chId].nextStart then
                            guide[chId].nextTitle = title
                            guide[chId].nextStart = startSeconds
                        end if
                    end if
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

function createGuideEntry() as object
    return {
        nowTitle: ""
        nextTitle: ""
        nextStart: 0
        programs: []
    }
end function

function currentEpochSeconds() as integer
    dt = createObject("roDateTime")
    if dt = invalid then return 0
    return dt.AsSeconds()
end function

function parseXmltvTime(value as dynamic) as integer
    if value = invalid then return 0
    raw = value.toStr().Trim()
    if raw.Len() < 14 then return 0

    stamp = raw.Left(14)
    year = stamp.Left(4).toInt()
    month = stamp.Mid(4, 2).toInt()
    day = stamp.Mid(6, 2).toInt()
    hour = stamp.Mid(8, 2).toInt()
    minute = stamp.Mid(10, 2).toInt()
    second = stamp.Mid(12, 2).toInt()

    offsetSeconds = 0
    rest = raw.Mid(14).Trim()
    if rest.Len() >= 5 then
        signChar = rest.Left(1)
        if signChar = "+" or signChar = "-" then
            offsetHours = rest.Mid(1, 2).toInt()
            offsetMinutes = rest.Mid(3, 2).toInt()
            offsetSeconds = (offsetHours * 3600) + (offsetMinutes * 60)
            if signChar = "-" then offsetSeconds = -offsetSeconds
        end if
    end if

    return epochSecondsUtc(year, month, day, hour, minute, second) - offsetSeconds
end function

function epochSecondsUtc(year as integer, month as integer, day as integer, hour as integer, minute as integer, second as integer) as integer
    adjYear = year
    if month <= 2 then adjYear = adjYear - 1

    era = int(adjYear / 400)
    yearOfEra = adjYear - (era * 400)

    monthPrime = month
    if monthPrime > 2 then
        monthPrime = monthPrime - 3
    else
        monthPrime = monthPrime + 9
    end if

    dayOfYear = int(((153 * monthPrime) + 2) / 5) + day - 1
    dayOfEra = (yearOfEra * 365) + int(yearOfEra / 4) - int(yearOfEra / 100) + dayOfYear
    daysSinceEpoch = (era * 146097) + dayOfEra - 719468

    return (daysSinceEpoch * 86400) + (hour * 3600) + (minute * 60) + second
end function

function normalizeKey(value as dynamic) as string
    if value = invalid then return ""
    key = lcase(value.toStr().Trim())
    key = key.Replace("&amp;", "&")
    return key
end function
