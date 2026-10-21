-- widget.luau — bar widget for Time Blocks plugin (Luau)
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")

local lastActiveId: string? = nil
local isFirstTick = true

noctalia.setUpdateInterval(30000)

function update()
    local state = store.load()
    local nowMin, nowSec = store.now()

    local text, cur = schedule.remaining(state.today.blocks, nowSec)
    barWidget.setText(text)

    if cur ~= nil then
        barWidget.setColor(cur.color)
    else
        barWidget.setColor("on_surface", "script")
    end

    local nxt = schedule.upcoming(state.today.blocks, nowMin)
    local currentText = cur and string.format("Current: %s (%s–%s)", cur.label, schedule.fmt(cur.start), schedule.fmt(cur["end"])) or "Current: Unscheduled"
    local nextText = nxt and string.format("Next: %s (%s–%s)", nxt.label, schedule.fmt(nxt.start), schedule.fmt(nxt["end"])) or "Next: None"
    barWidget.setTooltip(currentText .. "\n" .. nextText)

    local curId = cur and cur.id or nil
    if not isFirstTick then
        if curId ~= lastActiveId then
            if state.notifyTransitions then
                if cur ~= nil then
                    noctalia.notify("Time Blocks", string.format("Now: %s (%s–%s)", cur.label, schedule.fmt(cur.start), schedule.fmt(cur["end"])))
                else
                    noctalia.notify("Time Blocks", "Unscheduled")
                end
            end
        end
    else
        isFirstTick = false
    end
    lastActiveId = curId
end

function onClick()
    noctalia.togglePanel("bhaswata/timeblock:panel")
end

function onRightClick()
    noctalia.togglePanel("bhaswata/timeblock:actions")
end

function onIpc(event: string, payload: string?)
    local action = event
    local arg = payload

    if event == "bar" and payload ~= nil then
        local cmd, rest = string.match(payload, "^(%S+)%s*(.*)$")
        if cmd then
            action = cmd
            arg = (rest ~= "") and rest or nil
        end
    end

    local nowMin = store.now()

    if action == "endNow" or action == "next" then
        store.mutate(function(s)
            s.today.blocks = schedule.endNow(s.today.blocks, nowMin)
            return s
        end)
        update()
    elseif action == "insertNow" then
        store.mutate(function(s)
            s.today.blocks = schedule.insertNow(s.today.blocks, nowMin, s.defaultBlockMinutes, "New Block", s.defaultColor, store.newId)
            return s
        end)
        update()
    elseif action == "push" then
        local mins = tonumber(arg)
        store.mutate(function(s)
            local delta = mins or s.pushIncrement
            s.today.blocks = schedule.push(s.today.blocks, nowMin, delta)
            return s
        end)
        update()
    elseif action == "resetToday" then
        local _, _, date, weekday = store.now()
        store.mutate(function(s)
            s.today = schedule.generateToday(s.template, date, weekday, store.newId)
            return s
        end)
        update()
    end
end

noctalia.state.watch("rev", function()
    update()
end)

update()
