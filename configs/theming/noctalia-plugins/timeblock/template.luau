-- template.luau — standing template editor for Time Blocks plugin (Luau)
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")

local colorRoles = { "primary", "secondary", "tertiary", "error" }

local weekdays = {
    { day = 0, label = "S" },
    { day = 1, label = "M" },
    { day = 2, label = "T" },
    { day = 3, label = "W" },
    { day = 4, label = "T" },
    { day = 5, label = "F" },
    { day = 6, label = "S" },
}

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

    local templateRows = {}
    for _, b in ipairs(state.template) do
        local colorIdx = table.find(colorRoles, b.color) or 1
        local selectedIdx = colorIdx - 1

        local rowChildren = {}

        table.insert(rowChildren, ui.input({
            key = "tpl_label_" .. b.id,
            value = b.label,
            placeholder = "Label",
            flexGrow = 1,
            controlSize = "sm",
            onChange = function(newVal: string)
                store.mutate(function(s)
                    for _, item in ipairs(s.template) do
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
            key = "tpl_start_" .. b.id .. "_" .. tostring(b.start),
            value = schedule.fmt(b.start),
            width = 65,
            controlSize = "sm",
            onChange = function(newVal: string)
                local parsed = parseHHMM(newVal)
                if parsed ~= nil then
                    store.mutate(function(s)
                        for _, item in ipairs(s.template) do
                            if item.id == b.id then
                                item.start = parsed
                                break
                            end
                        end
                        s.template = schedule.sorted(s.template)
                        return s
                    end)
                end
            end,
            onSubmit = function(newVal: string)
                local parsed = parseHHMM(newVal)
                if parsed ~= nil then
                    store.mutate(function(s)
                        for _, item in ipairs(s.template) do
                            if item.id == b.id then
                                item.start = parsed
                                break
                            end
                        end
                        s.template = schedule.sorted(s.template)
                        return s
                    end)
                else
                    render()
                end
            end,
        }))

        table.insert(rowChildren, ui.label({ text = "–" }))

        table.insert(rowChildren, ui.input({
            key = "tpl_end_" .. b.id .. "_" .. tostring(b["end"]),
            value = schedule.fmt(b["end"]),
            width = 65,
            controlSize = "sm",
            onChange = function(newVal: string)
                local parsed = parseHHMM(newVal)
                if parsed ~= nil then
                    store.mutate(function(s)
                        for _, item in ipairs(s.template) do
                            if item.id == b.id then
                                item["end"] = parsed
                                break
                            end
                        end
                        s.template = schedule.sorted(s.template)
                        return s
                    end)
                end
            end,
            onSubmit = function(newVal: string)
                local parsed = parseHHMM(newVal)
                if parsed ~= nil then
                    store.mutate(function(s)
                        for _, item in ipairs(s.template) do
                            if item.id == b.id then
                                item["end"] = parsed
                                break
                            end
                        end
                        s.template = schedule.sorted(s.template)
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
                        for _, item in ipairs(s.template) do
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

        -- Seven weekday toggles (S M T W T F S)
        local weekdayNodes = {}
        for _, d in ipairs(weekdays) do
            local hasDay = b.days ~= nil and table.find(b.days, d.day) ~= nil
            table.insert(weekdayNodes, ui.column({ gap = 2, align = "center" }, {
                ui.label({ text = d.label, fontSize = 10, color = hasDay and "primary" or "on_surface_variant" }),
                ui.toggle({
                    checked = hasDay,
                    onChange = function(val: string)
                        store.mutate(function(s)
                            for _, item in ipairs(s.template) do
                                if item.id == b.id then
                                    local days = item.days or {}
                                    local existingIdx = table.find(days, d.day)
                                    if val == "true" and not existingIdx then
                                        table.insert(days, d.day)
                                        table.sort(days)
                                    elseif val == "false" and existingIdx then
                                        table.remove(days, existingIdx)
                                    end
                                    item.days = days
                                    break
                                end
                            end
                            return s
                        end)
                    end,
                }),
            }))
        end
        table.insert(rowChildren, ui.row({ gap = 4, align = "center" }, weekdayNodes))

        table.insert(rowChildren, ui.button({
            glyph = "trash",
            variant = "destructive",
            controlSize = "sm",
            onClick = function()
                store.mutate(function(s)
                    local nextTpl = {}
                    for _, item in ipairs(s.template) do
                        if item.id ~= b.id then
                            table.insert(nextTpl, item)
                        end
                    end
                    s.template = nextTpl
                    return s
                end)
            end,
        }))

        table.insert(templateRows, ui.column({
            key = "tpl_col_" .. b.id,
            gap = 4,
            padding = 6,
            radius = 8,
            fill = "surface_variant/0.2",
        }, {
            ui.row({ gap = 8, align = "center" }, rowChildren),
        }))
    end

    local addBlockRow = ui.row({ justify = "start" }, {
        ui.button({
            text = "+ Add template block",
            variant = "outline",
            controlSize = "sm",
            onClick = function()
                store.mutate(function(s)
                    local startMin = 540
                    local n = #s.template
                    if n > 0 then
                        startMin = s.template[n]["end"]
                    end
                    local endMin = math.clamp(startMin + s.defaultBlockMinutes, 0, 1440)
                    local newB = {
                        id = store.newId(),
                        label = "Template Block",
                        start = startMin,
                        ["end"] = endMin,
                        color = s.defaultColor,
                        notes = "",
                        days = { 0, 1, 2, 3, 4, 5, 6 },
                    }
                    table.insert(s.template, newB)
                    s.template = schedule.sorted(s.template)
                    return s
                end)
            end,
        }),
    })

    panel.render(ui.column({ gap = 12, padding = 16, fill = "surface", radius = 12 }, {
        ui.row({ align = "center", justify = "space_between" }, {
            ui.label({ text = "Time Blocks — Standing Template", fontSize = 16, fontWeight = "bold", color = "primary" }),
            ui.button({
                glyph = "x",
                variant = "ghost",
                controlSize = "sm",
                onClick = function()
                    panel.close()
                end,
            }),
        }),
        ui.separator({ thickness = 1, color = "outline_variant/0.5" }),
        ui.scroll({ flexGrow = 1, gap = 6 }, templateRows),
        addBlockRow,
    }))
end

function onOpen(_context)
    render()
end

noctalia.state.watch("rev", function()
    render()
end)

render()
