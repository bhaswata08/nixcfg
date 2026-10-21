-- actions.luau — quick-actions panel for Time Blocks plugin (Luau)
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")

local function render()
    local state = store.load()
    local pushInc = state.pushIncrement or 15

    panel.render(ui.column({ gap = 8, padding = 12, fill = "surface", radius = 12 }, {
        ui.button({
            text = "End now",
            variant = "default",
            controlSize = "md",
            onClick = function()
                local nowMin = store.now()
                store.mutate(function(s)
                    s.today.blocks = schedule.endNow(s.today.blocks, nowMin)
                    return s
                end)
                panel.close()
            end,
        }),
        ui.button({
            text = "Insert now",
            variant = "default",
            controlSize = "md",
            onClick = function()
                local nowMin = store.now()
                store.mutate(function(s)
                    s.today.blocks = schedule.insertNow(s.today.blocks, nowMin, s.defaultBlockMinutes, "Ad-hoc", s.defaultColor, store.newId)
                    return s
                end)
                panel.close()
            end,
        }),
        ui.button({
            text = string.format("+%dm", pushInc),
            variant = "default",
            controlSize = "md",
            onClick = function()
                local nowMin = store.now()
                store.mutate(function(s)
                    s.today.blocks = schedule.push(s.today.blocks, nowMin, pushInc)
                    return s
                end)
                panel.close()
            end,
        }),
        ui.button({
            text = "Reset today",
            variant = "destructive",
            controlSize = "md",
            onClick = function()
                local _, _, date, weekday = store.now()
                store.mutate(function(s)
                    s.today = schedule.generateToday(s.template, date, weekday, store.newId)
                    return s
                end)
                panel.close()
            end,
        }),
    }))
end

function onOpen(_context)
    render()
end

noctalia.state.watch("rev", function()
    render()
end)

render()
