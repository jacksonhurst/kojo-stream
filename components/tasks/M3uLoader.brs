Sub Init()
    m.top.functionName = "load"
End Sub

Sub load()
    url = m.top.m3uUrl
    if url = "" then
        m.top.error = "No playlist URL provided"
        return
    end if
    print "Loading M3U: " + url

    req = CreateObject("roUrlTransfer")
    if req = invalid then
        m.top.error = "Network error: could not create connection"
        return
    end if
    req.SetUrl(url)
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.EnableFreshConnection(true)

    ' Try downloading to file first
    tmpFile = "tmp:/downloaded.m3u"
    port = CreateObject("roMessagePort")
    req.SetPort(port)
    response = ""

    if req.AsyncGetToFile(tmpFile)
        msg = wait(30000, port)
        if msg <> invalid and type(msg) = "roUrlEvent"
            code = msg.GetResponseCode()
            if code = 200
                fs = CreateObject("roFileSystem")
                if fs.Exists(tmpFile)
                    response = ReadAsciiFile(tmpFile)
                    fs.Delete(tmpFile)
                    if response = invalid or response = "" then
                        response = tryAsyncGetToString(req, url)
                    end if
                else
                    response = tryAsyncGetToString(req, url)
                end if
            else
                response = tryAsyncGetToString(req, url)
            end if
        else
            response = tryAsyncGetToString(req, url)
        end if
    else
        response = tryAsyncGetToString(req, url)
    end if

    if response = "" then
        m.top.error = "Failed to download playlist. Check URL and network connection."
        return
    end if

    print "Parsing M3U, length: "; response.len()
    list = parse(response)

    if list.count() = 0 then
        m.top.error = "No channels found in playlist. Verify the M3U URL is valid."
        return
    end if
    m.top.content = toContentNode(list)
    print "Loaded: "; list.count(); " categories"
End Sub

Function tryAsyncGetToString(req as object, url as string) as string
    req.SetUrl(url)
    port = CreateObject("roMessagePort")
    req.SetPort(port)
    if not req.AsyncGetToString() then return ""
    msg = wait(30000, port)
    if msg <> invalid and type(msg) = "roUrlEvent"
        code = msg.GetResponseCode()
        if code = 200
            response = msg.GetString()
            if response <> "" then return response
        end if
    end if
    return ""
End Function

Function parse(m3u as string) as object
    lines = m3u.Split(Chr(10))
    if lines.count() < 2 then return []
    cats = {}
    i = 0
    headerAwareCount = 0
    while i < lines.count()
        line = lines[i].Trim()
        if line.Left(7) = "#EXTINF" then
            parsedLine = parseExtinfEntry(lines, i)
            i = parsedLine.nextIndex

            url = parsedLine.url
            if url <> "" then
                cat = "Uncategorized"
                title = line.Mid(line.Instr(",") + 1).Trim()
                logo = ""
                tvgId = ""
                tvgName = ""
                gm = CreateObject("roRegex", "group-title=""([^""]+)""", "i").Match(line)
                if gm.count() > 1 then cat = gm[1]
                lm = CreateObject("roRegex", "tvg-logo=""([^""]+)""", "i").Match(line)
                if lm.count() > 1 then logo = lm[1]
                tm = CreateObject("roRegex", "tvg-id=""([^""]+)""", "i").Match(line)
                if tm.count() > 1 then tvgId = tm[1]
                nm = CreateObject("roRegex", "tvg-name=""([^""]+)""", "i").Match(line)
                if nm.count() > 1 then tvgName = nm[1]

                if parsedLine.userAgent <> "" or parsedLine.referrer <> "" or parsedLine.origin <> "" or parsedLine.cookie <> "" then
                    headerAwareCount++
                end if

                fmt = guessStreamFormat(url)
                live = (fmt = "hls" or fmt = "ts" or fmt = "dash" or fmt = "ism")
                if not cats.DoesExist(cat) then cats[cat] = []
                cats[cat].Push({
                    title: title
                    HDPosterUrl: logo
                    url: url
                    streamformat: fmt
                    live: live
                    tvgId: tvgId
                    tvgName: tvgName
                    userAgent: parsedLine.userAgent
                    referrer: parsedLine.referrer
                    origin: parsedLine.origin
                    cookie: parsedLine.cookie
                })
            end if
        else
            i += 1
        end if
        if i mod 1000 = 0 then print "Processed "; i; " lines"
    end while

    list = []
    for each c in cats
        list.Push({Title: c, ContentList: cats[c]})
    end for
    print "Header-aware channels: "; headerAwareCount
    return list
End Function

Function toContentNode(list as object) as object
    rows = CreateObject("roSGNode", "ContentNode")
    for each r in list
        row = CreateObject("roSGNode", "ContentNode")
        row.Title = r.Title
        for each i in r.ContentList
            item = CreateObject("roSGNode", "ContentNode")
            item.SetFields(i)
            row.appendChild(item)
        end for
        rows.appendChild(row)
    end for
    return rows
End Function

Function guessStreamFormat(url as string) as string
    lowered = lcase(url)
    if lowered.instr(".m3u8") >= 0 then return "hls"
    if lowered.instr(".mpd") >= 0 then return "dash"
    if lowered.instr("/manifest") >= 0 then return "ism"
    if lowered.instr(".ism") >= 0 then return "ism"
    if lowered.instr(".ts") >= 0 then return "ts"
    if lowered.instr(".mp4") >= 0 then return "mp4"
    if lowered.instr(".mkv") >= 0 then return "mkv"
    if lowered.instr(".mov") >= 0 then return "mov"
    if lowered.instr("/live/") >= 0 then return "ts"
    return "hls"
End Function

function parseExtinfEntry(lines as object, extinfIndex as integer) as object
    result = {
        url: ""
        nextIndex: extinfIndex + 1
        userAgent: ""
        referrer: ""
        origin: ""
        cookie: ""
    }

    j = extinfIndex + 1
    while j < lines.count()
        candidate = lines[j].Trim()
        if candidate = "" then
            j += 1
        else if candidate.Left(11) = "#EXTVLCOPT:" then
            parseVlcOption(candidate, result)
            j += 1
        else if candidate.Left(10) = "#KODIPROP:" then
            parseKodiOption(candidate, result)
            j += 1
        else if candidate.Left(7) = "#EXTINF" then
            result.nextIndex = j
            return result
        else if candidate.Left(1) = "#" then
            j += 1
        else
            result.url = candidate
            applyInlineUrlHeaders(result)
            result.nextIndex = j + 1
            return result
        end if
    end while

    result.nextIndex = j
    return result
end function

sub parseVlcOption(line as string, entry as object)
    prefix = "#EXTVLCOPT:"
    body = line.Mid(prefix.Len())
    eqPos = body.Instr("=")
    if eqPos < 0 then return
    key = lcase(body.Left(eqPos).Trim())
    value = body.Mid(eqPos + 1).Trim()
    if value.Left(1) = """" and value.Right(1) = """" and value.Len() >= 2 then
        value = value.Mid(1, value.Len() - 2)
    end if

    if key = "http-user-agent" then
        entry.userAgent = value
    else if key = "http-referrer" or key = "http-referer" then
        entry.referrer = value
    else if key = "http-origin" then
        entry.origin = value
    else if key = "http-cookie" then
        entry.cookie = value
    end if
end sub

sub parseKodiOption(line as string, entry as object)
    prefix = "#KODIPROP:"
    body = line.Mid(prefix.Len())
    eqPos = body.Instr("=")
    if eqPos < 0 then return
    key = lcase(body.Left(eqPos).Trim())
    value = body.Mid(eqPos + 1).Trim()
    if key = "inputstream.adaptive.stream_headers" or key = "http-user-agent" or key = "http-referrer" then
        parseHeaderPairsIntoEntry(value, entry)
    end if
end sub

sub applyInlineUrlHeaders(entry as object)
    rawUrl = entry.url
    pipePos = rawUrl.Instr("|")
    if pipePos < 0 then return

    entry.url = rawUrl.Left(pipePos)
    headerPart = rawUrl.Mid(pipePos + 1)
    parseHeaderPairsIntoEntry(headerPart, entry)
end sub

sub parseHeaderPairsIntoEntry(headerPart as string, entry as object)
    pairs = headerPart.Split("&")
    for each pair in pairs
        eqPos = pair.Instr("=")
        if eqPos < 0 then
            colonPos = pair.Instr(":")
            if colonPos >= 0 then eqPos = colonPos
        end if
        if eqPos < 0 then
            ' skip invalid pair
        else
            rawKey = lcase(pair.Left(eqPos).Trim())
            rawVal = pair.Mid(eqPos + 1).Trim()
            key = rawKey.Replace("%2d", "-").Replace("%2D", "-")
            value = rawVal.Replace("%20", " ").Replace("+", " ")

            if key = "user-agent" or key = "http-user-agent" then
                entry.userAgent = value
            else if key = "referer" or key = "referrer" or key = "http-referrer" or key = "http-referer" then
                entry.referrer = value
            else if key = "origin" or key = "http-origin" then
                entry.origin = value
            else if key = "cookie" or key = "http-cookie" then
                entry.cookie = value
            end if
        end if
    end for
end sub
