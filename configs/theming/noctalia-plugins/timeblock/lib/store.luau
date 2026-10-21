-- store.luau — persistence and state management for Time Blocks plugin (Luau)
local schedule = require("./schedule.luau")

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

local store = {}

local idCounter = 0

function store.newId(): string
    idCounter += 1
    return string.format("blk_%d_%d", os.time(), idCounter)
end

function store.now(): (number, number, string, number)
    local timeStr = noctalia.formatTime("%Y-%m-%d %H %M %S %w")
    local d, h, m, s, w = string.match(timeStr, "^(%S+) (%d+) (%d+) (%d+) (%d+)$")
    local hour = tonumber(h) or 0
    local min = tonumber(m) or 0
    local sec = tonumber(s) or 0
    local weekday = tonumber(w) or 0
    local date = d or ""
    local nowSec = hour * 3600 + min * 60 + sec
    local nowMin = hour * 60 + min + sec / 60
    return nowMin, nowSec, date, weekday
end

local function getStatePath(): string
    local dir = noctalia.pluginDataDir()
    return dir .. "/state.json"
end

local function applyConfigSettings(state: State)
    local notify = noctalia.getConfig("notifyTransitions")
    if notify ~= nil then
        state.notifyTransitions = notify == true
    end

    local pushInc = noctalia.getConfig("pushIncrement")
    if pushInc ~= nil and type(pushInc) == "number" then
        state.pushIncrement = pushInc
    end

    local defMinutes = noctalia.getConfig("defaultBlockMinutes")
    if defMinutes ~= nil and type(defMinutes) == "number" then
        state.defaultBlockMinutes = defMinutes
    end

    local defColor = noctalia.getConfig("defaultColor")
    if defColor ~= nil and type(defColor) == "string" and defColor ~= "" then
        state.defaultColor = defColor
    end
end

function store.save(state: State)
    local path = getStatePath()
    local encoded = noctalia.json.encode(state, true)
    if encoded then
        noctalia.writeFile(path, encoded)
    end

    local rev = (tonumber(noctalia.state.get("rev")) or 0) + 1
    noctalia.state.set("rev", rev)
end

function store.load(): State
    local path = getStatePath()
    local raw = noctalia.readFile(path)
    local state: State

    if raw == nil or raw == "" then
        -- Initial launch: import legacy v4 config
        local v4Path = noctalia.expandPath("~/.config/noctalia/plugins/timeblock/settings.json")
        local v4Raw = noctalia.readFile(v4Path)
        local ok, imported = pcall(schedule.importV4, v4Raw, noctalia.json.decode)
        if ok and imported and type(imported) == "table" and type(imported.template) == "table" then
            state = imported
        else
            state = schedule.defaultState()
        end
        store.save(state)
    else
        local ok, parsed = pcall(noctalia.json.decode, raw)
        if ok and type(parsed) == "table" then
            local tpl = type(parsed.template) == "table" and parsed.template or {}
            local today = type(parsed.today) == "table" and parsed.today or {}
            local todayDate = type(today.date) == "string" and today.date or ""
            local todayBlocks = type(today.blocks) == "table" and today.blocks or {}

            state = {
                template = schedule.sorted(schedule.normalize(tpl, true, store.newId)),
                today = {
                    date = todayDate,
                    blocks = schedule.sorted(schedule.normalize(todayBlocks, false, store.newId)),
                },
                notifyTransitions = parsed.notifyTransitions == true,
                pushIncrement = type(parsed.pushIncrement) == "number" and parsed.pushIncrement or 15,
                defaultBlockMinutes = type(parsed.defaultBlockMinutes) == "number" and parsed.defaultBlockMinutes or 30,
                defaultColor = type(parsed.defaultColor) == "string" and parsed.defaultColor ~= "" and parsed.defaultColor or "primary",
            }
        else
            state = schedule.defaultState()
        end
    end

    -- Run ensureToday with current local date and weekday
    local _, _, curDate, curWeekday = store.now()
    local ensuredState, changed = schedule.ensureToday(state, curDate, curWeekday, store.newId)
    if changed then
        state = ensuredState
        store.save(state)
    else
        state = ensuredState
    end

    -- Plugin settings come from noctalia.getConfig
    applyConfigSettings(state)

    return state
end

function store.mutate(fn: (State) -> State): State
    local s = store.load()
    local nextState = fn(s)
    store.save(nextState)
    return nextState
end

return store
