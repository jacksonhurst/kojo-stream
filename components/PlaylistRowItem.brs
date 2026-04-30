sub init()
    m.nameLabel = m.top.findNode("NameLabel")
    m.urlLabel = m.top.findNode("UrlLabel")
end sub

sub updateContent()
    content = m.top.itemContent
    if content = invalid then return

    name = ""
    if content.displayName <> invalid then name = content.displayName
    if name = "" and content.title <> invalid then name = content.title
    if name = "" then name = "(unnamed playlist)"

    url = ""
    if content.playlistUrl <> invalid then
        url = content.playlistUrl
    else if content.description <> invalid then
        url = content.description
    end if

    xmltv = ""
    if content.xmltvUrl <> invalid then xmltv = content.xmltvUrl
    if xmltv <> "" then
        url = url + "  |  EPG: linked"
    end if

    m.nameLabel.text = name
    m.urlLabel.text = url
end sub
