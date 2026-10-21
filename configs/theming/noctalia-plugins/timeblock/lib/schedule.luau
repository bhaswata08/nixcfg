-- schedule.luau — pure schedule logic for Time Blocks plugin (Luau)
-- All functions are pure and return new tables or copies. Time is always passed in.

export type Block = {
    id: string,
    label: string,
    start: number,
    ["end"]: number,
    color: string,
    notes: string,
    days: {number}?,
    skipped: boolean?,
    templateId: string?,
}

export type State = {
    template: {Block},
    today: {
        date: string,
        blocks: {Block},
    },
    notifyTransitions: boolean,
    pushIncrement: number,
    defaultBlockMinutes: number,
    defaultColor: string,
}

local schedule = {}

local function copyBlock(b: Block): Block
    local res: Block = {
        id = b.id,
        label = b.label,
        start = b.start,
        ["end"] = b["end"],
        color = b.color,
        notes = b.notes,
        skipped = b.skipped,
        templateId = b.templateId,
    }
    if b.days ~= nil then
        local daysCopy = {}
        for _, d in ipairs(b.days) do
            table.insert(daysCopy, d)
        end
        res.days = daysCopy
    end
    return res
end

local function fmtDuration(mins: number): string
    if mins < 60 then
        return string.format("%dm", mins)
    else
        return string.format("%dh %dm", math.floor(mins / 60), mins % 60)
    end
end

function schedule.defaultState(): State
    return {
        template = {},
        today = {
            date = "",
            blocks = {},
        },
        notifyTransitions = false,
        pushIncrement = 15,
        defaultBlockMinutes = 30,
        defaultColor = "primary",
    }
end

function schedule.sorted(blocks: {Block}): {Block}
    local copy = {}
    for _, b in ipairs(blocks) do
        table.insert(copy, copyBlock(b))
    end
    table.sort(copy, function(a: Block, b: Block)
        if a.start ~= b.start then
            return a.start < b.start
        end
        return a["end"] < b["end"]
    end)
    return copy
end

function schedule.normalize(blocks: {Block}, isTemplate: boolean, newId: () -> string): {Block}
    local out = {}
    for _, b in ipairs(blocks) do
        local id = (b.id ~= nil and tostring(b.id) ~= "") and tostring(b.id) or newId()
        local label = b.label ~= nil and tostring(b.label) or ""
        local startMin = math.clamp(math.floor(b.start or 0), 0, 1440)
        local endRaw = b["end"]
        local endMin: number
        if endRaw == nil then
            endMin = math.clamp(startMin + 30, 0, 1440)
        else
            endMin = math.clamp(math.floor(endRaw), 0, 1440)
        end
        local color = (b.color ~= nil and tostring(b.color) ~= "") and tostring(b.color) or "primary"
        local notes = b.notes ~= nil and tostring(b.notes) or ""

        local item: Block = {
            id = id,
            label = label,
            start = startMin,
            ["end"] = endMin,
            color = color,
            notes = notes,
        }

        if isTemplate then
            if b.days ~= nil and type(b.days) == "table" then
                local daysCopy = {}
                for _, d in ipairs(b.days) do
                    table.insert(daysCopy, d)
                end
                item.days = daysCopy
            else
                item.days = { 0, 1, 2, 3, 4, 5, 6 }
            end
        else
            item.skipped = b.skipped == true
            item.templateId = b.templateId ~= nil and tostring(b.templateId) or ""
        end

        table.insert(out, item)
    end
    return out
end

function schedule.importV4(raw: string?, decode: ((string) -> any?)?): State
    if raw == nil or raw == "" or decode == nil then
        return schedule.defaultState()
    end

    local ok, parsed = pcall(decode, raw)
    if not ok or type(parsed) ~= "table" then
        return schedule.defaultState()
    end

    local idCounter = 0
    local function autoId(): string
        idCounter += 1
        return "v4_blk_" .. tostring(idCounter)
    end

    local rawTemplate = type(parsed.template) == "table" and parsed.template or {}
    local normalizedTemplate = schedule.normalize(rawTemplate, true, autoId)

    local todayDate = ""
    local todayBlocks = {}
    if type(parsed.today) == "table" then
        if type(parsed.today.date) == "string" then
            todayDate = parsed.today.date
        end
        if type(parsed.today.blocks) == "table" then
            todayBlocks = schedule.sorted(schedule.normalize(parsed.today.blocks, false, autoId))
        end
    end

    local notifyTransitions = false
    if parsed.notifyTransitions == true then
        notifyTransitions = true
    end

    local pushIncrement = 15
    if type(parsed.pushIncrement) == "number" then
        pushIncrement = parsed.pushIncrement
    end

    local defaultBlockMinutes = 30
    if type(parsed.defaultBlockMinutes) == "number" then
        defaultBlockMinutes = parsed.defaultBlockMinutes
    end

    local defaultColor = "primary"
    if type(parsed.defaultColor) == "string" and parsed.defaultColor ~= "" then
        defaultColor = parsed.defaultColor
    end

    return {
        template = schedule.sorted(normalizedTemplate),
        today = {
            date = todayDate,
            blocks = todayBlocks,
        },
        notifyTransitions = notifyTransitions,
        pushIncrement = pushIncrement,
        defaultBlockMinutes = defaultBlockMinutes,
        defaultColor = defaultColor,
    }
end

function schedule.generateToday(template: {Block}, date: string, weekday: number, newId: () -> string): { date: string, blocks: {Block} }
    local out = {}
    for _, t in ipairs(template) do
        local include = true
        if t.days ~= nil then
            include = table.find(t.days, weekday) ~= nil
        end
        if include then
            table.insert(out, {
                id = newId(),
                label = t.label,
                start = t.start,
                ["end"] = t["end"],
                color = t.color,
                notes = t.notes,
                skipped = false,
                templateId = t.id,
            })
        end
    end
    return {
        date = date,
        blocks = schedule.sorted(out),
    }
end

function schedule.ensureToday(state: State, date: string, weekday: number, newId: () -> string): (State, boolean)
    if state.today.date == date then
        return state, false
    end

    local newToday = schedule.generateToday(state.template, date, weekday, newId)
    local newState: State = {
        template = state.template,
        today = newToday,
        notifyTransitions = state.notifyTransitions,
        pushIncrement = state.pushIncrement,
        defaultBlockMinutes = state.defaultBlockMinutes,
        defaultColor = state.defaultColor,
    }
    return newState, true
end

function schedule.active(blocks: {Block}, nowMin: number): Block?
    local cur: Block? = nil
    for _, b in ipairs(blocks) do
        if not b.skipped then
            if nowMin >= b.start and nowMin < b["end"] then
                if cur == nil or b.start > cur.start then
                    cur = b
                end
            end
        end
    end
    return cur
end

function schedule.upcoming(blocks: {Block}, nowMin: number): Block?
    local nxt: Block? = nil
    for _, b in ipairs(blocks) do
        if not b.skipped then
            if b.start > nowMin then
                if nxt == nil or b.start < nxt.start or (b.start == nxt.start and b["end"] < nxt["end"]) then
                    nxt = b
                end
            end
        end
    end
    return nxt
end

function schedule.endNow(blocks: {Block}, nowMin: number): {Block}
    local cur = schedule.active(blocks, nowMin)
    if cur == nil then
        return schedule.sorted(blocks)
    end
    local newEnd = math.clamp(math.max(cur.start + 1, math.floor(nowMin)), 0, 1440)
    local out = {}
    for _, b in ipairs(blocks) do
        local cp = copyBlock(b)
        if b.id == cur.id then
            cp["end"] = newEnd
        end
        table.insert(out, cp)
    end
    return schedule.sorted(out)
end

function schedule.insertNow(blocks: {Block}, nowMin: number, minutes: number, label: string, color: string, newId: () -> string): {Block}
    local startMin = math.clamp(math.floor(nowMin), 0, 1440)
    local endMin = math.clamp(startMin + minutes, 0, 1440)
    local newBlock: Block = {
        id = newId(),
        label = label,
        start = startMin,
        ["end"] = endMin,
        color = color,
        notes = "",
        skipped = false,
        templateId = "",
    }
    local out = {}
    for _, b in ipairs(blocks) do
        table.insert(out, copyBlock(b))
    end
    table.insert(out, newBlock)
    return schedule.sorted(out)
end

function schedule.push(blocks: {Block}, nowMin: number, minutes: number): {Block}
    local cutoff = math.floor(nowMin)
    local out = {}
    for _, b in ipairs(blocks) do
        local cp = copyBlock(b)
        if not cp.skipped and cp.start >= cutoff then
            cp.start = math.clamp(cp.start + minutes, 0, 1440)
            cp["end"] = math.clamp(cp["end"] + minutes, 0, 1440)
        end
        table.insert(out, cp)
    end
    return schedule.sorted(out)
end

function schedule.saveAsTemplate(today: {Block}, newId: () -> string): ({Block}, {Block})
    local newTemplate = {}
    local newToday = {}
    for _, b in ipairs(today) do
        local todayCopy = copyBlock(b)
        if todayCopy.skipped then
            todayCopy.templateId = ""
            table.insert(newToday, todayCopy)
        else
            local tid = newId()
            todayCopy.templateId = tid
            table.insert(newToday, todayCopy)
            table.insert(newTemplate, {
                id = tid,
                label = b.label,
                start = b.start,
                ["end"] = b["end"],
                color = b.color,
                notes = b.notes,
                days = { 0, 1, 2, 3, 4, 5, 6 },
            })
        end
    end
    return schedule.sorted(newTemplate), schedule.sorted(newToday)
end

function schedule.overlappingIds(blocks: {Block}): {[string]: boolean}
    local res: {[string]: boolean} = {}
    local sortedBlocks = schedule.sorted(blocks)
    local n = #sortedBlocks
    for i = 1, n do
        local a = sortedBlocks[i]
        if not a.skipped then
            for j = i + 1, n do
                local b = sortedBlocks[j]
                if not b.skipped then
                    if b.start < a["end"] and a.start < b["end"] then
                        res[a.id] = true
                        res[b.id] = true
                    end
                end
            end
        end
    end
    return res
end

function schedule.fmt(min: number): string
    if min == 1440 then
        return "24:00"
    end
    local m = (math.floor(min) % 1440 + 1440) % 1440
    local h = math.floor(m / 60)
    local mins = m % 60
    return string.format("%02d:%02d", h, mins)
end

function schedule.remaining(blocks: {Block}, nowSec: number): (string, Block?)
    local nowMin = nowSec / 60
    local cur = schedule.active(blocks, nowMin)
    if cur ~= nil then
        local targetSec = cur["end"] * 60
        local remMin = math.max(0, math.round((targetSec - nowSec) / 60))
        return string.format("%s · %s left", cur.label, fmtDuration(remMin)), cur
    end

    local nxt = schedule.upcoming(blocks, nowMin)
    if nxt ~= nil then
        local targetSec = nxt.start * 60
        local remMin = math.max(0, math.round((targetSec - nowSec) / 60))
        return string.format("Unscheduled · next in %s", fmtDuration(remMin)), nil
    end

    return "Unscheduled", nil
end

return schedule
