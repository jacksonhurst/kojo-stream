sub init()
    m.top.functionName = "probe"
end sub

sub probe()
    url = m.top.probeUrl
    if url = invalid or url = "" then
        m.top.error = "Probe URL missing"
        return
    end if

    manifestRes = fetchUrl(url)
    if manifestRes.code <> 200 then
        m.top.error = "Manifest request failed. code=" + manifestRes.code.toStr()
        return
    end if

    text = manifestRes.body
    if text = invalid or text = "" then
        m.top.error = "Manifest body empty"
        return
    end if

    lines = text.Split(Chr(10))
    firstMediaLine = findFirstMediaLine(lines)
    firstMediaUrl = resolveUrl(url, firstMediaLine)
    manifestInfo = summarizeHlsManifest(lines)

    segCode = -1
    segLen = 0
    segSync = -1
    segContentType = ""
    tsReport = "ts_probe=not_run"
    if firstMediaUrl <> "" then
        segRes = fetchBytes(firstMediaUrl)
        segCode = segRes.code
        segLen = segRes.length
        segSync = segRes.syncByte
        segContentType = segRes.contentType
        if segRes.bytes <> invalid and segRes.length > 0 then
            tsReport = analyzeTsSegment(segRes.bytes)
        end if
    end if

    snippet = text
    if snippet.Len() > 220 then snippet = snippet.Left(220)
    snippet = snippet.Replace(Chr(13), "").Replace(Chr(10), " | ")

    report = ""
    report = report + "manifest_code=" + manifestRes.code.toStr() + "; "
    report = report + "manifest_ctype=" + manifestRes.contentType + "; "
    report = report + manifestInfo + "; "
    report = report + "first_media_url=" + firstMediaUrl + "; "
    report = report + "segment_code=" + segCode.toStr() + "; "
    report = report + "segment_ctype=" + segContentType + "; "
    report = report + "segment_len=" + segLen.toStr() + "; "
    report = report + "segment_sync=" + segSync.toStr() + "; "
    report = report + tsReport + "; "
    report = report + "manifest_snippet=" + snippet

    m.top.report = report
end sub

function fetchUrl(url as string) as object
    req = createObject("roUrlTransfer")
    if req = invalid then return {code: -1, body: "", contentType: ""}
    req.SetUrl(url)
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.EnableFreshConnection(true)
    applyHeaders(req)
    port = createObject("roMessagePort")
    req.SetPort(port)
    if not req.AsyncGetToString() then return {code: -1, body: "", contentType: ""}
    msg = wait(20000, port)
    if msg = invalid or type(msg) <> "roUrlEvent" then return {code: -1, body: "", contentType: ""}
    ctype = ""
    resHeaders = msg.GetResponseHeaders()
    if resHeaders <> invalid then
        if resHeaders["Content-Type"] <> invalid then ctype = resHeaders["Content-Type"]
    end if
    return {
        code: msg.GetResponseCode()
        body: msg.GetString()
        contentType: ctype
    }
end function

function fetchBytes(url as string) as object
    req = createObject("roUrlTransfer")
    if req = invalid then return {code: -1, length: 0, syncByte: -1, contentType: "", bytes: invalid}
    req.SetUrl(url)
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.EnableFreshConnection(true)
    applyHeaders(req)
    port = createObject("roMessagePort")
    req.SetPort(port)

    tmp = "tmp:/stream_probe.bin"
    if not req.AsyncGetToFile(tmp) then return {code: -1, length: 0, syncByte: -1, contentType: "", bytes: invalid}
    msg = wait(20000, port)
    if msg = invalid or type(msg) <> "roUrlEvent" then return {code: -1, length: 0, syncByte: -1, contentType: "", bytes: invalid}
    code = msg.GetResponseCode()
    ctype = ""
    resHeaders = msg.GetResponseHeaders()
    if resHeaders <> invalid then
        if resHeaders["Content-Type"] <> invalid then ctype = resHeaders["Content-Type"]
    end if
    if code <> 200 then return {code: code, length: 0, syncByte: -1, contentType: ctype, bytes: invalid}

    fs = createObject("roFileSystem")
    if fs = invalid or not fs.Exists(tmp) then return {code: code, length: 0, syncByte: -1, contentType: ctype, bytes: invalid}
    ba = CreateObject("roByteArray")
    if ba = invalid then
        fs.Delete(tmp)
        return {code: code, length: 0, syncByte: -1, contentType: ctype, bytes: invalid}
    end if
    if not ba.ReadFile(tmp) then
        fs.Delete(tmp)
        return {code: code, length: 0, syncByte: -1, contentType: ctype, bytes: invalid}
    end if
    fs.Delete(tmp)

    sync = -1
    if ba.Count() > 0 then sync = ba[0]
    return {code: code, length: ba.Count(), syncByte: sync, contentType: ctype, bytes: ba}
end function

function summarizeHlsManifest(lines as object) as string
    mediaCount = 0
    targetDuration = ""
    hasEndList = false
    hasIndependentSegments = false
    hasDiscontinuity = false
    hasKey = false

    for each line in lines
        trimmed = line.Trim()
        if trimmed = "" then
            ' skip
        else if trimmed.Left(22) = "#EXT-X-TARGETDURATION:" then
            targetDuration = trimmed.Mid(22)
        else if trimmed = "#EXT-X-ENDLIST" then
            hasEndList = true
        else if trimmed = "#EXT-X-INDEPENDENT-SEGMENTS" then
            hasIndependentSegments = true
        else if trimmed = "#EXT-X-DISCONTINUITY" then
            hasDiscontinuity = true
        else if trimmed.Left(10) = "#EXT-X-KEY" then
            hasKey = true
        else if trimmed.Left(1) <> "#" then
            mediaCount += 1
        end if
    end for

    return "manifest_segments=" + mediaCount.toStr() + "; manifest_target_duration=" + targetDuration + "; manifest_endlist=" + boolText(hasEndList) + "; manifest_independent_segments=" + boolText(hasIndependentSegments) + "; manifest_discontinuity=" + boolText(hasDiscontinuity) + "; manifest_key=" + boolText(hasKey)
end function

function analyzeTsSegment(ba as object) as string
    packetSize = detectTsPacketSize(ba)
    if packetSize = 0 then return "ts_probe=no_sync"

    pmtPid = findPmtPid(ba, packetSize)
    if pmtPid < 0 then return "ts_probe=pat_not_found; ts_packet_size=" + packetSize.toStr()

    pmtInfo = findPmtInfo(ba, packetSize, pmtPid)
    if pmtInfo.streams.count() = 0 then
        return "ts_probe=pmt_not_found; ts_packet_size=" + packetSize.toStr() + "; pmt_pid=" + pmtPid.toStr()
    end if

    details = []
    if pmtInfo.h264Pid >= 0 then details.push(analyzeH264Pid(ba, packetSize, pmtInfo.h264Pid))
    if pmtInfo.aacPid >= 0 then details.push(analyzeAacPid(ba, packetSize, pmtInfo.aacPid))

    report = "ts_probe=ok; ts_packet_size=" + packetSize.toStr() + "; pmt_pid=" + pmtPid.toStr() + "; pmt_streams=" + joinStrings(pmtInfo.streams, ", ")
    if details.count() > 0 then report = report + "; " + joinStrings(details, "; ")
    return report
end function

function detectTsPacketSize(ba as object) as integer
    if ba = invalid or ba.Count() < 188 then return 0
    if ba[0] <> 71 then return 0
    if ba.Count() > 188 and ba[188] = 71 then return 188
    if ba.Count() > 192 and ba[192] = 71 then return 192
    return 188
end function

function findPmtPid(ba as object, packetSize as integer) as integer
    count = ba.Count()
    for packetStart = 0 to count - packetSize step packetSize
        if ba[packetStart] = 71 then
            pid = getTsPid(ba, packetStart)
            payloadStart = getPayloadStart(ba, packetStart, packetSize)
            payloadUnitStart = (ba[packetStart + 1] and 64) <> 0
            if pid = 0 and payloadStart >= 0 and payloadUnitStart then
                pointerField = ba[payloadStart]
                sectionStart = payloadStart + 1 + pointerField
                if sectionStart + 12 < packetStart + packetSize and ba[sectionStart] = 0 then
                    sectionLength = ((ba[sectionStart + 1] and 15) * 256) + ba[sectionStart + 2]
                    entryEnd = sectionStart + 3 + sectionLength - 4
                    entryStart = sectionStart + 8
                    while entryStart + 3 < entryEnd and entryStart + 3 < count
                        programNumber = (ba[entryStart] * 256) + ba[entryStart + 1]
                        if programNumber <> 0 then
                            return ((ba[entryStart + 2] and 31) * 256) + ba[entryStart + 3]
                        end if
                        entryStart += 4
                    end while
                end if
            end if
        end if
    end for

    return -1
end function

function findPmtInfo(ba as object, packetSize as integer, pmtPid as integer) as object
    streams = []
    h264Pid = -1
    aacPid = -1
    count = ba.Count()
    for packetStart = 0 to count - packetSize step packetSize
        if ba[packetStart] = 71 then
            pid = getTsPid(ba, packetStart)
            payloadStart = getPayloadStart(ba, packetStart, packetSize)
            payloadUnitStart = (ba[packetStart + 1] and 64) <> 0
            if pid = pmtPid and payloadStart >= 0 and payloadUnitStart then
                pointerField = ba[payloadStart]
                sectionStart = payloadStart + 1 + pointerField
                if sectionStart + 16 < packetStart + packetSize and ba[sectionStart] = 2 then
                    sectionLength = ((ba[sectionStart + 1] and 15) * 256) + ba[sectionStart + 2]
                    sectionEnd = sectionStart + 3 + sectionLength - 4
                    programInfoLength = ((ba[sectionStart + 10] and 15) * 256) + ba[sectionStart + 11]
                    streamStart = sectionStart + 12 + programInfoLength

                    while streamStart + 4 < sectionEnd and streamStart + 4 < count
                        streamType = ba[streamStart]
                        elemPid = ((ba[streamStart + 1] and 31) * 256) + ba[streamStart + 2]
                        esInfoLength = ((ba[streamStart + 3] and 15) * 256) + ba[streamStart + 4]
                        descriptorText = describeDescriptors(ba, streamStart + 5, esInfoLength)
                        streams.push(streamTypeName(streamType, descriptorText) + " pid=" + elemPid.toStr())
                        if streamType = 27 and h264Pid < 0 then h264Pid = elemPid
                        if (streamType = 15 or streamType = 17) and aacPid < 0 then aacPid = elemPid
                        streamStart = streamStart + 5 + esInfoLength
                    end while

                    return {streams: streams, h264Pid: h264Pid, aacPid: aacPid}
                end if
            end if
        end if
    end for

    return {streams: streams, h264Pid: h264Pid, aacPid: aacPid}
end function

function analyzeH264Pid(ba as object, packetSize as integer, videoPid as integer) as string
    payloadBytes = collectPidPayloadPrefix(ba, packetSize, videoPid, 180000)
    if payloadBytes.count() = 0 then return "h264_probe=no_payload"

    nalTypes = listH264NalTypes(payloadBytes, 12)
    spsNal = findH264Nal(payloadBytes, 7)
    spsInfo = "h264_sps=not_found"
    if spsNal.count() > 0 then spsInfo = parseH264Sps(spsNal)

    hasIdr = arrayContainsInteger(nalTypes, 5)
    hasSps = arrayContainsInteger(nalTypes, 7)
    hasPps = arrayContainsInteger(nalTypes, 8)

    return spsInfo + "; h264_has_idr=" + boolText(hasIdr) + "; h264_has_sps=" + boolText(hasSps) + "; h264_has_pps=" + boolText(hasPps) + "; h264_first_nals=" + joinIntegers(nalTypes, ",")
end function

function analyzeAacPid(ba as object, packetSize as integer, audioPid as integer) as string
    payloadBytes = collectPidPayloadPrefix(ba, packetSize, audioPid, 24000)
    if payloadBytes.count() = 0 then return "aac_probe=no_payload"

    for idx = 0 to payloadBytes.count() - 7
        if payloadBytes[idx] = 255 and (payloadBytes[idx + 1] and 240) = 240 then
            profileBits = Int((payloadBytes[idx + 2] and 192) / 64)
            sampleRateIndex = Int((payloadBytes[idx + 2] and 60) / 4)
            channelConfig = ((payloadBytes[idx + 2] and 1) * 4) + Int((payloadBytes[idx + 3] and 192) / 64)
            return "aac_probe=ok; aac_profile=" + aacProfileName(profileBits) + "; aac_sample_rate=" + aacSampleRateName(sampleRateIndex) + "; aac_channels=" + channelConfig.toStr()
        end if
    end for

    return "aac_probe=adts_not_found"
end function

function collectPidPayloadPrefix(ba as object, packetSize as integer, targetPid as integer, maxBytes as integer) as object
    bytes = []
    count = ba.Count()
    for packetStart = 0 to count - packetSize step packetSize
        if bytes.count() >= maxBytes then exit for
        if ba[packetStart] = 71 and getTsPid(ba, packetStart) = targetPid then
            payloadStart = getPayloadStart(ba, packetStart, packetSize)
            if payloadStart >= 0 then
                payloadUnitStart = (ba[packetStart + 1] and 64) <> 0
                if payloadUnitStart then
                    pesStart = getPesPayloadStart(ba, payloadStart, packetStart + packetSize)
                    if pesStart >= 0 then payloadStart = pesStart
                end if

                for idx = payloadStart to packetStart + packetSize - 1
                    if idx >= ba.Count() or bytes.count() >= maxBytes then exit for
                    bytes.push(ba[idx])
                end for
            end if
        end if
    end for
    return bytes
end function

function getPesPayloadStart(ba as object, payloadStart as integer, packetEnd as integer) as integer
    if payloadStart + 8 >= packetEnd then return -1
    if ba[payloadStart] <> 0 or ba[payloadStart + 1] <> 0 or ba[payloadStart + 2] <> 1 then return payloadStart

    pesHeaderBytes = ba[payloadStart + 8]
    pesPayloadStart = payloadStart + 9 + pesHeaderBytes
    if pesPayloadStart >= packetEnd then return -1
    return pesPayloadStart
end function

function listH264NalTypes(bytes as object, maxCount as integer) as object
    nalTypes = []
    idx = 0
    while idx < bytes.count() - 4 and nalTypes.count() < maxCount
        startInfo = findStartCode(bytes, idx)
        if startInfo.offset < 0 then exit while
        nalHeaderOffset = startInfo.offset + startInfo.size
        if nalHeaderOffset < bytes.count() then
            nalTypes.push(bytes[nalHeaderOffset] and 31)
        end if
        idx = nalHeaderOffset + 1
    end while
    return nalTypes
end function

function findH264Nal(bytes as object, expectedNalType as integer) as object
    idx = 0
    while idx < bytes.count() - 4
        startInfo = findStartCode(bytes, idx)
        if startInfo.offset < 0 then exit while

        nalHeaderOffset = startInfo.offset + startInfo.size
        if nalHeaderOffset >= bytes.count() then exit while
        nalType = bytes[nalHeaderOffset] and 31

        nextInfo = findStartCode(bytes, nalHeaderOffset + 1)
        nalEnd = bytes.count()
        if nextInfo.offset >= 0 then nalEnd = nextInfo.offset

        if nalType = expectedNalType then
            nalBytes = []
            for nalIdx = nalHeaderOffset + 1 to nalEnd - 1
                nalBytes.push(bytes[nalIdx])
            end for
            return nalBytes
        end if

        if nextInfo.offset < 0 then exit while
        idx = nextInfo.offset
    end while
    return []
end function

function findStartCode(bytes as object, startOffset as integer) as object
    idx = startOffset
    while idx < bytes.count() - 3
        if bytes[idx] = 0 and bytes[idx + 1] = 0 then
            if bytes[idx + 2] = 1 then return {offset: idx, size: 3}
            if idx < bytes.count() - 4 and bytes[idx + 2] = 0 and bytes[idx + 3] = 1 then return {offset: idx, size: 4}
        end if
        idx += 1
    end while
    return {offset: -1, size: 0}
end function

function parseH264Sps(nalBytes as object) as string
    rbsp = removeEmulationPreventionBytes(nalBytes)
    if rbsp.count() < 4 then return "h264_sps=too_short"

    reader = {bytes: rbsp, bitOffset: 0}
    profileIdc = readBits(reader, 8)
    constraintFlags = readBits(reader, 8)
    levelIdc = readBits(reader, 8)
    readUnsignedExpGolomb(reader)

    chromaFormatIdc = 1
    separateColorPlaneFlag = 0
    if isExtendedH264Profile(profileIdc) then
        chromaFormatIdc = readUnsignedExpGolomb(reader)
        if chromaFormatIdc = 3 then separateColorPlaneFlag = readBit(reader)
        readUnsignedExpGolomb(reader)
        readUnsignedExpGolomb(reader)
        readBit(reader)
        seqScalingMatrixPresent = readBit(reader)
        if seqScalingMatrixPresent = 1 then skipScalingLists(reader, chromaFormatIdc)
    end if

    readUnsignedExpGolomb(reader)
    picOrderCntType = readUnsignedExpGolomb(reader)
    if picOrderCntType = 0 then
        readUnsignedExpGolomb(reader)
    else if picOrderCntType = 1 then
        readBit(reader)
        readSignedExpGolomb(reader)
        readSignedExpGolomb(reader)
        cycleCount = readUnsignedExpGolomb(reader)
        for cycleIdx = 0 to cycleCount - 1
            readSignedExpGolomb(reader)
        end for
    end if

    readUnsignedExpGolomb(reader)
    readBit(reader)
    picWidthInMbsMinus1 = readUnsignedExpGolomb(reader)
    picHeightInMapUnitsMinus1 = readUnsignedExpGolomb(reader)
    frameMbsOnlyFlag = readBit(reader)
    if frameMbsOnlyFlag = 0 then readBit(reader)
    readBit(reader)

    cropLeft = 0
    cropRight = 0
    cropTop = 0
    cropBottom = 0
    frameCroppingFlag = readBit(reader)
    if frameCroppingFlag = 1 then
        cropLeft = readUnsignedExpGolomb(reader)
        cropRight = readUnsignedExpGolomb(reader)
        cropTop = readUnsignedExpGolomb(reader)
        cropBottom = readUnsignedExpGolomb(reader)
    end if

    cropUnits = h264CropUnits(chromaFormatIdc, separateColorPlaneFlag, frameMbsOnlyFlag)
    width = ((picWidthInMbsMinus1 + 1) * 16) - ((cropLeft + cropRight) * cropUnits.x)
    height = ((2 - frameMbsOnlyFlag) * (picHeightInMapUnitsMinus1 + 1) * 16) - ((cropTop + cropBottom) * cropUnits.y)

    return "h264_sps=ok; h264_profile=" + h264ProfileName(profileIdc) + "; h264_profile_idc=" + profileIdc.toStr() + "; h264_level=" + h264LevelName(levelIdc) + "; h264_resolution=" + width.toStr() + "x" + height.toStr() + "; h264_progressive=" + boolText(frameMbsOnlyFlag = 1) + "; h264_constraints=" + constraintFlags.toStr()
end function

function removeEmulationPreventionBytes(bytes as object) as object
    rbsp = []
    zeroCount = 0
    for each value in bytes
        if zeroCount = 2 and value = 3 then
            zeroCount = 0
        else
            rbsp.push(value)
            if value = 0 then
                zeroCount += 1
            else
                zeroCount = 0
            end if
        end if
    end for
    return rbsp
end function

function skipScalingLists(reader as object, chromaFormatIdc as integer)
    listCount = 8
    if chromaFormatIdc = 3 then listCount = 12
    for listIdx = 0 to listCount - 1
        present = readBit(reader)
        if present = 1 then
            listSize = 16
            if listIdx >= 6 then listSize = 64
            lastScale = 8
            nextScale = 8
            for scaleIdx = 0 to listSize - 1
                if nextScale <> 0 then
                    deltaScale = readSignedExpGolomb(reader)
                    nextScale = (lastScale + deltaScale + 256) mod 256
                end if
                if nextScale <> 0 then lastScale = nextScale
            end for
        end if
    end for
    return true
end function

function readBit(reader as object) as integer
    return readBits(reader, 1)
end function

function readBits(reader as object, bitCount as integer) as integer
    value = 0
    for bitIdx = 0 to bitCount - 1
        if reader.bitOffset >= reader.bytes.count() * 8 then return value
        byteIndex = Int(reader.bitOffset / 8)
        bitIndex = 7 - (reader.bitOffset mod 8)
        mask = bitMask(bitIndex)
        bitValue = 0
        if (reader.bytes[byteIndex] and mask) <> 0 then bitValue = 1
        value = (value * 2) + bitValue
        reader.bitOffset += 1
    end for
    return value
end function

function readUnsignedExpGolomb(reader as object) as integer
    zeroCount = 0
    while reader.bitOffset < reader.bytes.count() * 8
        if readBit(reader) = 1 then exit while
        zeroCount += 1
        if zeroCount > 31 then return 0
    end while

    suffix = 0
    if zeroCount > 0 then suffix = readBits(reader, zeroCount)
    return pow2Int(zeroCount) - 1 + suffix
end function

function readSignedExpGolomb(reader as object) as integer
    codeNum = readUnsignedExpGolomb(reader)
    signedValue = Int((codeNum + 1) / 2)
    if (codeNum mod 2) = 0 then signedValue = -signedValue
    return signedValue
end function

function bitMask(bitIndex as integer) as integer
    if bitIndex = 0 then return 1
    if bitIndex = 1 then return 2
    if bitIndex = 2 then return 4
    if bitIndex = 3 then return 8
    if bitIndex = 4 then return 16
    if bitIndex = 5 then return 32
    if bitIndex = 6 then return 64
    return 128
end function

function pow2Int(power as integer) as integer
    value = 1
    if power <= 0 then return value
    for idx = 1 to power
        value = value * 2
    end for
    return value
end function

function isExtendedH264Profile(profileIdc as integer) as boolean
    return profileIdc = 100 or profileIdc = 110 or profileIdc = 122 or profileIdc = 244 or profileIdc = 44 or profileIdc = 83 or profileIdc = 86 or profileIdc = 118 or profileIdc = 128 or profileIdc = 138 or profileIdc = 139 or profileIdc = 134
end function

function h264CropUnits(chromaFormatIdc as integer, separateColorPlaneFlag as integer, frameMbsOnlyFlag as integer) as object
    if chromaFormatIdc = 0 or separateColorPlaneFlag = 1 then return {x: 1, y: 2 - frameMbsOnlyFlag}
    if chromaFormatIdc = 1 then return {x: 2, y: 2 * (2 - frameMbsOnlyFlag)}
    if chromaFormatIdc = 2 then return {x: 2, y: 2 - frameMbsOnlyFlag}
    return {x: 1, y: 2 - frameMbsOnlyFlag}
end function

function h264ProfileName(profileIdc as integer) as string
    if profileIdc = 66 then return "baseline"
    if profileIdc = 77 then return "main"
    if profileIdc = 88 then return "extended"
    if profileIdc = 100 then return "high"
    if profileIdc = 110 then return "high10"
    if profileIdc = 122 then return "high422"
    if profileIdc = 244 then return "high444"
    return "profile_" + profileIdc.toStr()
end function

function h264LevelName(levelIdc as integer) as string
    if levelIdc = 9 then return "1b"
    major = Int(levelIdc / 10)
    minor = levelIdc mod 10
    return major.toStr() + "." + minor.toStr()
end function

function aacProfileName(profileBits as integer) as string
    if profileBits = 0 then return "Main"
    if profileBits = 1 then return "LC"
    if profileBits = 2 then return "SSR"
    return "reserved"
end function

function aacSampleRateName(sampleRateIndex as integer) as string
    rates = ["96000", "88200", "64000", "48000", "44100", "32000", "24000", "22050", "16000", "12000", "11025", "8000", "7350"]
    if sampleRateIndex >= 0 and sampleRateIndex < rates.count() then return rates[sampleRateIndex]
    return "unknown"
end function

function arrayContainsInteger(values as object, expected as integer) as boolean
    for each value in values
        if value = expected then return true
    end for
    return false
end function

function boolText(value as boolean) as string
    if value then return "true"
    return "false"
end function

function joinIntegers(values as object, separator as string) as string
    joined = ""
    for each value in values
        if joined <> "" then joined = joined + separator
        joined = joined + value.toStr()
    end for
    return joined
end function

function getTsPid(ba as object, packetStart as integer) as integer
    return ((ba[packetStart + 1] and 31) * 256) + ba[packetStart + 2]
end function

function getPayloadStart(ba as object, packetStart as integer, packetSize as integer) as integer
    adaptationControl = Int((ba[packetStart + 3] and 48) / 16)
    if adaptationControl = 0 or adaptationControl = 2 then return -1

    payloadStart = packetStart + 4
    if adaptationControl = 3 then
        if payloadStart >= ba.Count() then return -1
        payloadStart = payloadStart + 1 + ba[payloadStart]
    end if

    if payloadStart >= packetStart + packetSize or payloadStart >= ba.Count() then return -1
    return payloadStart
end function

function describeDescriptors(ba as object, descriptorStart as integer, descriptorBytes as integer) as string
    if descriptorBytes <= 0 then return ""
    descriptorEnd = descriptorStart + descriptorBytes
    descriptorNames = []
    descriptorOffset = descriptorStart
    while descriptorOffset + 1 < descriptorEnd and descriptorOffset + 1 < ba.Count()
        descriptorTag = ba[descriptorOffset]
        descriptorSize = ba[descriptorOffset + 1]
        if descriptorTag = 106 then descriptorNames.push("AC-3 descriptor")
        if descriptorTag = 122 then descriptorNames.push("E-AC-3 descriptor")
        if descriptorTag = 123 then descriptorNames.push("DTS descriptor")
        descriptorOffset = descriptorOffset + 2 + descriptorSize
    end while
    return joinStrings(descriptorNames, "+")
end function

function streamTypeName(streamType as integer, descriptorText as string) as string
    if streamType = 1 then return "type=1 MPEG-1 video"
    if streamType = 2 then return "type=2 MPEG-2 video"
    if streamType = 3 then return "type=3 MPEG-1 audio"
    if streamType = 4 then return "type=4 MPEG-2 audio"
    if streamType = 15 then return "type=15 AAC audio"
    if streamType = 17 then return "type=17 LATM AAC audio"
    if streamType = 27 then return "type=27 H.264 video"
    if streamType = 36 then return "type=36 H.265/HEVC video"
    if streamType = 129 then return "type=129 AC-3 audio"
    if streamType = 135 then return "type=135 E-AC-3 audio"
    if streamType = 6 and descriptorText <> "" then return "type=6 private data (" + descriptorText + ")"
    if streamType = 6 then return "type=6 private data"
    return "type=" + streamType.toStr() + " unknown"
end function

function joinStrings(values as object, separator as string) as string
    joined = ""
    for each value in values
        if joined <> "" then joined = joined + separator
        joined = joined + value
    end for
    return joined
end function

sub applyHeaders(req as object)
    if m.top.userAgent <> invalid and m.top.userAgent <> "" then req.AddHeader("User-Agent", m.top.userAgent)
    if m.top.referrer <> invalid and m.top.referrer <> "" then req.AddHeader("Referer", m.top.referrer)
    if m.top.origin <> invalid and m.top.origin <> "" then req.AddHeader("Origin", m.top.origin)
    if m.top.cookie <> invalid and m.top.cookie <> "" then req.AddHeader("Cookie", m.top.cookie)
end sub

function findFirstMediaLine(lines as object) as string
    for each line in lines
        trimmed = line.Trim()
        if trimmed = "" then
            ' skip
        else if trimmed.Left(1) = "#" then
            ' skip
        else
            return trimmed
        end if
    end for
    return ""
end function

function resolveUrl(baseUrl as string, maybeRelative as string) as string
    if maybeRelative = "" then return ""
    lower = lcase(maybeRelative)
    if lower.Left(7) = "http://" or lower.Left(8) = "https://" then return maybeRelative

    slash = -1
    for i = baseUrl.Len() - 1 to 0 step -1
        if baseUrl.Mid(i, 1) = "/" then
            slash = i
            exit for
        end if
    end for
    if slash < 0 then return maybeRelative
    return baseUrl.Left(slash + 1) + maybeRelative
end function
