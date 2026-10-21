-- service.luau — headless service for Time Blocks plugin (Luau)
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")

local lastActiveId: string? = nil
local isFirstTick = true

noctalia.setUpdateInterval(10000)

function update()
    local state = store.load()
    local nowMin, nowSec, curDate, curWeekday = store.now()

    -- Midnight rollover check & save
    local ensuredState, changed = schedule.ensureToday(state, curDate, curWeekday, store.newId)
    if changed then
        store.save(ensuredState)
        state = ensuredState
    end

    -- Transition notifications
    local cur = schedule.active(state.today.blocks, nowMin)
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
    elseif action == "insertNow" then
        store.mutate(function(s)
            s.today.blocks = schedule.insertNow(s.today.blocks, nowMin, s.defaultBlockMinutes, "Ad-hoc", s.defaultColor, store.newId)
            return s
        end)
    elseif action == "push" then
        local mins = tonumber(arg)
        store.mutate(function(s)
            local delta = mins or s.pushIncrement
            s.today.blocks = schedule.push(s.today.blocks, nowMin, delta)
            return s
        end)
    elseif action == "resetToday" then
        local _, _, date, weekday = store.now()
        store.mutate(function(s)
            s.today = schedule.generateToday(s.template, date, weekday, store.newId)
            return s
        end)
    end
end

noctalia.state.watch("rev", function()
    update()
end)

update()
