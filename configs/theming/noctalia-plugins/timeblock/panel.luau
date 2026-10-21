-- panel.luau — main scheduling panel for Time Blocks plugin (Luau)
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")

local colorRoles = { "primary", "secondary", "tertiary", "error" }

local function parseHHMM(str: string): number?
    local h, m = string.match(str, "^%s*(%d%d?):(%d%d)%s*$")
    if h and m then
        local hour = tonumber(h)
        local min = tonumber(m)
        if hour and min and hour >= 0 and hour <= 24 and min >= 0 and min < 60 then
            local total = hour * 60 + min
            if total <= 1440 then
                return total
            end
        end
    end
    return nil
end

local function render()
    local state = store.load()
    local nowMin = store.now()
    local pushInc = state.pushIncrement or 15
    local overlaps = schedule.overlappingIds(state.today.blocks)

    -- Header row of action buttons
    local headerRow = ui.row({ gap = 6, align = "center" }, {
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
                    s.today.blocks = schedule.insertNow(s.today.blocks, curNow, s.defaultBlockMinutes, "New Block", s.defaultColor, store.newId)
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
        ui.button({
            text = "Template…",
            controlSize = "sm",
            onClick = function()
                noctalia.togglePanel("bhaswata/timeblock:template")
            end,
        }),
    })

    -- Block rows
    local blockRows = {}
    for _, b in ipairs(state.today.blocks) do
        local isPast = b["end"] <= nowMin
        local isActive = not b.skipped and (nowMin >= b.start and nowMin < b["end"])
        local isOverlap = overlaps[b.id] == true

        local colorIdx = table.find(colorRoles, b.color) or 1
        local selectedIdx = colorIdx - 1

        local rowChildren = {}

        if isOverlap then
            table.insert(rowChildren, ui.label({ text = "⚠", color = "error", fontWeight = "bold" }))
        end

        table.insert(rowChildren, ui.input({
            key = "label_" .. b.id,
            value = b.label,
            placeholder = "Label",
            flexGrow = 1,
            controlSize = "sm",
            onChange = function(newVal: string)
                store.mutate(function(s)
                    for _, item in ipairs(s.today.blocks) do
                        if item.id == b.id then
                            item.label = newVal
                            break
                        end
                    end
                    return s
                end)
            end,
        }))

        table.insert(rowChildren, ui.input({
            key = "start_" .. b.id .. "_" .. tostring(b.start),
            value = schedule.fmt(b.start),
            width = 65,
            controlSize = "sm",
            onChange = function(newVal: string)
                local parsed = parseHHMM(newVal)
                if parsed ~= nil then
                    store.mutate(function(s)
                        for _, item in ipairs(s.today.blocks) do
                            if item.id == b.id then
                                item.start = parsed
                                break
                            end
                        end
                        s.today.blocks = schedule.sorted(s.today.blocks)
                        return s
                    end)
                end
            end,
            onSubmit = function(newVal: string)
                local parsed = parseHHMM(newVal)
                if parsed ~= nil then
                    store.mutate(function(s)
                        for _, item in ipairs(s.today.blocks) do
                            if item.id == b.id then
                                item.start = parsed
                                break
                            end
                        end
                        s.today.blocks = schedule.sorted(s.today.blocks)
                        return s
                    end)
                else
                    render()
                end
            end,
        }))

        table.insert(rowChildren, ui.label({ text = "–" }))

        table.insert(rowChildren, ui.input({
            key = "end_" .. b.id .. "_" .. tostring(b["end"]),
            value = schedule.fmt(b["end"]),
            width = 65,
            controlSize = "sm",
            onChange = function(newVal: string)
                local parsed = parseHHMM(newVal)
                if parsed ~= nil then
                    store.mutate(function(s)
                        for _, item in ipairs(s.today.blocks) do
                            if item.id == b.id then
                                item["end"] = parsed
                                break
                            end
                        end
                        s.today.blocks = schedule.sorted(s.today.blocks)
                        return s
                    end)
                end
            end,
            onSubmit = function(newVal: string)
                local parsed = parseHHMM(newVal)
                if parsed ~= nil then
                    store.mutate(function(s)
                        for _, item in ipairs(s.today.blocks) do
                            if item.id == b.id then
                                item["end"] = parsed
                                break
                            end
                        end
                        s.today.blocks = schedule.sorted(s.today.blocks)
                        return s
                    end)
                else
                    render()
                end
            end,
        }))

        table.insert(rowChildren, ui.select({
            options = colorRoles,
            selectedIndex = selectedIdx,
            width = 110,
            controlSize = "sm",
            onChange = function(idxStr: string, optText: string?)
                local chosenColor = (optText ~= nil and optText ~= "") and optText or nil
                if chosenColor == nil then
                    local idx = tonumber(idxStr)
                    if idx and colorRoles[idx + 1] then
                        chosenColor = colorRoles[idx + 1]
                    end
                end
                if chosenColor then
                    store.mutate(function(s)
                        for _, item in ipairs(s.today.blocks) do
                            if item.id == b.id then
                                item.color = chosenColor
                                break
                            end
                        end
                        return s
                    end)
                end
            end,
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

        table.insert(rowChildren, ui.button({
            glyph = "trash",
            variant = "destructive",
            controlSize = "sm",
            onClick = function()
                store.mutate(function(s)
                    local nextBlocks = {}
                    for _, item in ipairs(s.today.blocks) do
                        if item.id ~= b.id then
                            table.insert(nextBlocks, item)
                        end
                    end
                    s.today.blocks = nextBlocks
                    return s
                end)
            end,
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
                        label = "New Block",
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

    panel.render(ui.column({ gap = 12, padding = 16, fill = "surface", radius = 12 }, {
        ui.row({ align = "center", justify = "space_between" }, {
            ui.label({ text = "Time Blocks — Today", fontSize = 16, fontWeight = "bold", color = "primary" }),
            ui.button({
                glyph = "x",
                variant = "ghost",
                controlSize = "sm",
                onClick = function()
                    panel.close()
                end,
            }),
        }),
        headerRow,
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
