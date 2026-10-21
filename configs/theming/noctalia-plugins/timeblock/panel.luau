-- panel.luau — main scheduling panel for Time Blocks plugin (Luau)
local editor = require("./lib/editor.luau")
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")


local function render()
    local state = store.load()
    local nowMin = store.now()
    local pushInc = state.pushIncrement or 15
    local overlaps = schedule.overlappingIds(state.today.blocks)

    -- Action buttons on two rows: all six on one row ran past the panel's
    -- 540px width. "Template…" lives in the title row instead.
    local actionRow = ui.row({ gap = 6, align = "center" }, {
        ui.button({
            text = "End now",
            controlSize = "sm",
            onClick = function()
                local curNow = store.now()
                store.mutate(function(s)
                    s.today.blocks = schedule.endNow(s.today.blocks, curNow)
                    return s
                end)
            end,
        }),
        ui.button({
            text = "Insert now",
            controlSize = "sm",
            onClick = function()
                local curNow = store.now()
                store.mutate(function(s)
                    s.today.blocks = schedule.insertNow(s.today.blocks, curNow, s.defaultBlockMinutes, "Ad-hoc", s.defaultColor, store.newId)
                    return s
                end)
            end,
        }),
        ui.button({
            text = string.format("+%dm", pushInc),
            controlSize = "sm",
            onClick = function()
                local curNow = store.now()
                store.mutate(function(s)
                    s.today.blocks = schedule.push(s.today.blocks, curNow, pushInc)
                    return s
                end)
            end,
        }),
    })

    local manageRow = ui.row({ gap = 6, align = "center" }, {
        ui.button({
            text = "Reset today",
            variant = "destructive",
            controlSize = "sm",
            onClick = function()
                local _, _, date, weekday = store.now()
                store.mutate(function(s)
                    s.today = schedule.generateToday(s.template, date, weekday, store.newId)
                    return s
                end)
            end,
        }),
        ui.button({
            text = "Save as template",
            controlSize = "sm",
            onClick = function()
                store.mutate(function(s)
                    local newTpl, newToday = schedule.saveAsTemplate(s.today.blocks, store.newId)
                    s.template = newTpl
                    s.today.blocks = newToday
                    return s
                end)
            end,
        }),
    })

    -- Block rows
    local blockRows = {}
    for _, b in ipairs(state.today.blocks) do
        local isPast = b["end"] <= nowMin
        local isActive = not b.skipped and (nowMin >= b.start and nowMin < b["end"])
        local isOverlap = overlaps[b.id] == true

        local rowChildren = {}

        if isOverlap then
            table.insert(rowChildren, ui.label({ text = "⚠", color = "error", fontWeight = "bold" }))
        end

        table.insert(rowChildren, editor.labelInput({
            prefix = "label",
            target = "today",
            blockId = b.id,
            value = b.label,
        }))

        table.insert(rowChildren, editor.timeInput({
            prefix = "start",
            target = "today",
            blockId = b.id,
            field = "start",
            valueMin = b.start,
            onInvalid = render,
        }))

        table.insert(rowChildren, ui.label({ text = "–" }))

        table.insert(rowChildren, editor.timeInput({
            prefix = "end",
            target = "today",
            blockId = b.id,
            field = "end",
            valueMin = b["end"],
            onInvalid = render,
        }))

        table.insert(rowChildren, editor.colorSelect({
            target = "today",
            blockId = b.id,
            color = b.color,
        }))

        table.insert(rowChildren, ui.toggle({
            checked = b.skipped == true,
            onChange = function(val: string)
                store.mutate(function(s)
                    for _, item in ipairs(s.today.blocks) do
                        if item.id == b.id then
                            item.skipped = (val == "true")
                            break
                        end
                    end
                    return s
                end)
            end,
        }))

        table.insert(rowChildren, editor.deleteButton({
            target = "today",
            blockId = b.id,
        }))

        local blockColChildren = {}
        if isActive then
            local dur = math.max(1, b["end"] - b.start)
            local pct = math.clamp((nowMin - b.start) / dur, 0, 1)
            table.insert(blockColChildren, ui.progress({
                progress = pct,
                fill = b.color,
                height = 4,
                radius = 2,
            }))
        end
        table.insert(blockColChildren, ui.row({ gap = 8, align = "center" }, rowChildren))

        table.insert(blockRows, ui.column({
            key = "blk_col_" .. b.id,
            gap = 4,
            padding = 6,
            radius = 8,
            fill = isActive and "surface_variant/0.5" or nil,
            opacity = isPast and 0.55 or 1.0,
        }, blockColChildren))
    end

    local addBlockRow = ui.row({ justify = "start" }, {
        ui.button({
            text = "+ Add block",
            variant = "outline",
            controlSize = "sm",
            onClick = function()
                local curNow = store.now()
                store.mutate(function(s)
                    local startMin: number
                    local n = #s.today.blocks
                    if n > 0 then
                        startMin = s.today.blocks[n]["end"]
                    else
                        startMin = math.floor(curNow)
                    end
                    local endMin = math.clamp(startMin + s.defaultBlockMinutes, 0, 1440)
                    local newB = {
                        id = store.newId(),
                        label = "Ad-hoc",
                        start = startMin,
                        ["end"] = endMin,
                        color = s.defaultColor,
                        notes = "",
                        skipped = false,
                        templateId = "",
                    }
                    table.insert(s.today.blocks, newB)
                    s.today.blocks = schedule.sorted(s.today.blocks)
                    return s
                end)
            end,
        }),
    })

    -- flexGrow bounds the root to the panel height. Without it the root sizes to
    -- its content, so the list never scrolls and spills past the panel.
    panel.render(ui.column({ gap = 12, flexGrow = 1 }, {
        ui.row({ gap = 6, align = "center" }, {
            ui.label({ text = "Time Blocks — Today", fontSize = 16, fontWeight = "bold", color = "primary", flexGrow = 1 }),
            ui.button({
                text = "Template…",
                variant = "ghost",
                controlSize = "sm",
                onClick = function()
                    noctalia.togglePanel("bhaswata/timeblock:template")
                end,
            }),
            ui.button({
                glyph = "x",
                variant = "ghost",
                controlSize = "sm",
                onClick = function()
                    panel.close()
                end,
            }),
        }),
        actionRow,
        manageRow,
        ui.separator({ thickness = 1, color = "outline_variant/0.5" }),
        ui.scroll({ flexGrow = 1, gap = 6 }, blockRows),
        addBlockRow,
    }))
end

noctalia.setUpdateInterval(60000)

function update()
    render()
end

function onOpen(_context)
    render()
end

noctalia.state.watch("rev", function()
    render()
end)

render()
