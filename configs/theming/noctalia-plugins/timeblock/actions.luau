-- actions.luau — quick-actions panel for Time Blocks plugin (Luau)
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")

local function render()
    local state = store.load()
    local pushInc = state.pushIncrement or 15

    panel.render(ui.column({ gap = 8 }, {
        ui.button({
            text = "End now",
            tooltip = "End the current block at this minute",
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
            tooltip = string.format("Start a %dm Ad-hoc block now", state.defaultBlockMinutes or 30),
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
            tooltip = string.format("Push every block that has not started yet %d minutes later", pushInc),
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
            tooltip = "Rebuild today from the weekly template, dropping today's edits",
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
