-- editor.luau — shared row editor logic and UI components for Time Blocks (Luau)
local editor = {}

editor.colorRoles = { "primary", "secondary", "tertiary", "error" }

export type TargetList = "today" | "template"

local schedule
local function getSchedule()
    if not schedule then
        local ok, res = pcall(require, "./schedule.luau")
        if ok then
            schedule = res
        else
            schedule = require("./schedule")
        end
    end
    return schedule
end

local store
local function getStore()
    if not store then
        local ok, res = pcall(require, "./store.luau")
        if ok then
            store = res
        else
            store = require("./store")
        end
    end
    return store
end

local nonces: { [string]: number } = {}

function editor.getNonce(blockId: string, field: string): number
    local key = blockId .. "_" .. field
    return nonces[key] or 0
end

function editor.bumpNonce(blockId: string, field: string): number
    local key = blockId .. "_" .. field
    local nextVal = (nonces[key] or 0) + 1
    nonces[key] = nextVal
    return nextVal
end

function editor.timeInputKey(prefix: string, blockId: string, field: string, timeVal: number): string
    return string.format("%s_%s_%d_%d", prefix, blockId, timeVal, editor.getNonce(blockId, field))
end

function editor.parseHHMM(str: string): number?
    local h, m = string.match(str, "^%s*(%d%d?):(%d%d)%s*$")
    if h and m then
        local hour = tonumber(h)
        local min = tonumber(m)
        if hour == 24 and min == 0 then
            return 1440
        end
        if hour and min and hour >= 0 and hour <= 23 and min >= 0 and min < 60 then
            return hour * 60 + min
        end
    end
    return nil
end

function editor.resolveColor(idxStr: string, optText: string?): string?
    if optText ~= nil and optText ~= "" then
        return optText
    end
    local idx = tonumber(idxStr)
    if idx and editor.colorRoles[idx + 1] then
        return editor.colorRoles[idx + 1]
    end
    return nil
end

local function getList(s: any, target: TargetList): {any}
    if target == "today" then
        return s.today.blocks
    else
        return s.template
    end
end

local function setList(s: any, target: TargetList, list: {any})
    if target == "today" then
        s.today.blocks = list
    else
        s.template = list
    end
end

function editor.submitTime(
    target: TargetList,
    blockId: string,
    field: "start" | "end",
    newVal: string,
    currentVal: number,
    onInvalid: () -> ()
)
    local parsed = editor.parseHHMM(newVal)
    if parsed ~= nil then
        if currentVal == parsed then
            editor.bumpNonce(blockId, field)
        end
        local sched = getSchedule()
        local st = getStore()
        st.mutate(function(s)
            local list = getList(s, target)
            for _, item in ipairs(list) do
                if item.id == blockId then
                    item[field] = parsed
                    break
                end
            end
            setList(s, target, sched.sorted(list))
            return s
        end)
    else
        editor.bumpNonce(blockId, field)
        onInvalid()
    end
end

function editor.mutateColor(target: TargetList, blockId: string, idxStr: string, optText: string?)
    local chosenColor = editor.resolveColor(idxStr, optText)
    if chosenColor then
        local st = getStore()
        st.mutate(function(s)
            local list = getList(s, target)
            for _, item in ipairs(list) do
                if item.id == blockId then
                    item.color = chosenColor
                    break
                end
            end
            return s
        end)
    end
end

function editor.mutateLabel(target: TargetList, blockId: string, newVal: string)
    local st = getStore()
    st.mutate(function(s)
        local list = getList(s, target)
        for _, item in ipairs(list) do
            if item.id == blockId then
                item.label = newVal
                break
            end
        end
        return s
    end)
end

function editor.deleteBlock(target: TargetList, blockId: string)
    local st = getStore()
    st.mutate(function(s)
        local list = getList(s, target)
        local nextList = {}
        for _, item in ipairs(list) do
            if item.id ~= blockId then
                table.insert(nextList, item)
            end
        end
        setList(s, target, nextList)
        return s
    end)
end

function editor.labelInput(opts: {
    prefix: string,
    target: TargetList,
    blockId: string,
    value: string,
})
    return ui.input({
        key = opts.prefix .. "_" .. opts.blockId,
        value = opts.value,
        placeholder = "Label",
        flexGrow = 1,
        controlSize = "sm",
        onSubmit = function(newVal: string)
            editor.mutateLabel(opts.target, opts.blockId, newVal)
        end,
    })
end

function editor.timeInput(opts: {
    prefix: string,
    target: TargetList,
    blockId: string,
    field: "start" | "end",
    valueMin: number,
    onInvalid: () -> (),
})
    local sched = getSchedule()
    return ui.input({
        key = editor.timeInputKey(opts.prefix, opts.blockId, opts.field, opts.valueMin),
        value = sched.fmt(opts.valueMin),
        width = 65,
        controlSize = "sm",
        onSubmit = function(newVal: string)
            editor.submitTime(opts.target, opts.blockId, opts.field, newVal, opts.valueMin, opts.onInvalid)
        end,
    })
end

function editor.colorSelect(opts: {
    target: TargetList,
    blockId: string,
    color: string,
})
    local colorIdx = table.find(editor.colorRoles, opts.color) or 1
    local selectedIdx = colorIdx - 1
    return ui.select({
        options = editor.colorRoles,
        selectedIndex = selectedIdx,
        width = 110,
        controlSize = "sm",
        onChange = function(idxStr: string, optText: string?)
            editor.mutateColor(opts.target, opts.blockId, idxStr, optText)
        end,
    })
end

function editor.deleteButton(opts: {
    target: TargetList,
    blockId: string,
})
    return ui.button({
        glyph = "trash",
        variant = "destructive",
        controlSize = "sm",
        onClick = function()
            editor.deleteBlock(opts.target, opts.blockId)
        end,
    })
end

return editor
