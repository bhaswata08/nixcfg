-- widget.luau — bar widget for Time Blocks plugin (Luau)
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")

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
end

function onClick()
    noctalia.togglePanel("bhaswata/timeblock:panel")
end

function onRightClick()
    noctalia.togglePanel("bhaswata/timeblock:actions")
end

noctalia.state.watch("rev", function()
    update()
end)

update()
