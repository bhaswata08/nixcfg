-- template.luau — standing template editor for Time Blocks plugin (Luau)
local editor = require("./lib/editor.luau")
local schedule = require("./lib/schedule.luau")
local store = require("./lib/store.luau")

local weekdays = {
    { day = 0, label = "S" },
    { day = 1, label = "M" },
    { day = 2, label = "T" },
    { day = 3, label = "W" },
    { day = 4, label = "T" },
    { day = 5, label = "F" },
    { day = 6, label = "S" },
}

local function render()
    local state = store.load()

    local templateRows = {}
    for _, b in ipairs(state.template) do
        local rowChildren = {}

        table.insert(rowChildren, editor.labelInput({
            prefix = "tpl_label",
            target = "template",
            blockId = b.id,
            value = b.label,
        }))

        table.insert(rowChildren, editor.timeInput({
            prefix = "tpl_start",
            target = "template",
            blockId = b.id,
            field = "start",
            valueMin = b.start,
            onInvalid = render,
        }))

        table.insert(rowChildren, ui.label({ text = "–" }))

        table.insert(rowChildren, editor.timeInput({
            prefix = "tpl_end",
            target = "template",
            blockId = b.id,
            field = "end",
            valueMin = b["end"],
            onInvalid = render,
        }))

        table.insert(rowChildren, editor.colorSelect({
            target = "template",
            blockId = b.id,
            color = b.color,
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
        table.insert(rowChildren, editor.deleteButton({
            target = "template",
            blockId = b.id,
        }))

        table.insert(templateRows, ui.column({
            key = "tpl_col_" .. b.id,
            gap = 4,
            padding = 6,
            radius = 8,
            fill = "surface_variant/0.2",
        }, {
            ui.row({ gap = 8, align = "center" }, rowChildren),
            -- The weekday toggles get their own line: on the fields row they pushed
            -- each block about 110px past the panel's 640px width.
            ui.row({ gap = 4, align = "center" }, weekdayNodes),
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

    -- flexGrow bounds the root to the panel height. Without it the root sizes to
    -- its content, so the list never scrolls and spills past the panel.
    panel.render(ui.column({ gap = 12, flexGrow = 1 }, {
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
