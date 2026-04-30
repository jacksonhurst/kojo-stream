sub Main()
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    initializeGlobalVariables(screen)
    setDeviceModel()
    initializeScene(screen)
    runEventLoop()
end sub

sub initializeGlobalVariables(screen as Object)
    m.global = screen.getGlobalNode()
    m.global.addField("Model", "integer", true)
    m.global.Model = 0
    m.global.addField("Options", "integer", true)
    m.global.Options = 2
end sub

sub setDeviceModel()
    dev = CreateObject("roDeviceInfo")
    if dev <> invalid then
        modelString = dev.GetModel()
        if modelString <> invalid and Len(modelString) > 0 then
            modelNum = Left(modelString, 1).toInt()
            if modelNum < 4 then
                m.global.Model = 1
            end if
        end if
    end if
end sub

sub initializeScene(screen as Object)
    scene = screen.CreateScene("HomeScene")
    screen.show()

    m.RowList = scene.findNode("RowList")
    if m.RowList <> invalid then
        m.RowList.observeField("itemSelected", m.port)
    end if

    m.Video = scene.findNode("Video")
end sub

sub runEventLoop()
    while true
        msg = wait(0, m.port)
        if msg <> invalid then
            msgType = type(msg)
            if msgType = "roSGScreenEvent" then
                if msg.isScreenClosed() then
                    exit while
                end if
            else if msgType = "roSGNodeEvent" then
                handleNodeEvent(msg)
            end if
        end if
    end while
end sub

sub handleNodeEvent(msg as Object)
    node = msg.GetNode()
    field = msg.GetField()

    if node = "RowList" and field = "itemSelected" then
        index = msg.GetData()
    end if
end sub
