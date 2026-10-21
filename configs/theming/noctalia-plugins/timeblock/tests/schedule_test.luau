local schedule = require("../lib/schedule")

-- Simple JSON decoder for tests
local function parseJson(str: string): any
    local pos = 1
    local len = #str

    local function skipWhitespace()
        while pos <= len do
            local c = string.sub(str, pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos += 1
            else
                break
            end
        end
    end

    local parseValue: () -> any

    local function parseString(): string
        if string.sub(str, pos, pos) ~= '"' then
            error("Expected '\"' at position " .. pos)
        end
        pos += 1
        local res = {}
        while pos <= len do
            local c = string.sub(str, pos, pos)
            if c == '"' then
                pos += 1
                return table.concat(res)
            elseif c == "\\" then
                pos += 1
                local esc = string.sub(str, pos, pos)
                if esc == '"' then table.insert(res, '"')
                elseif esc == "\\" then table.insert(res, "\\")
                elseif esc == "/" then table.insert(res, "/")
                elseif esc == "n" then table.insert(res, "\n")
                elseif esc == "t" then table.insert(res, "\t")
                elseif esc == "r" then table.insert(res, "\r")
                elseif esc == "b" then table.insert(res, "\b")
                elseif esc == "f" then table.insert(res, "\f")
                else table.insert(res, esc)
                end
                pos += 1
            else
                table.insert(res, c)
                pos += 1
            end
        end
        error("Unterminated string")
    end

    local function parseNumber(): number
        local startPos = pos
        if string.sub(str, pos, pos) == "-" then
            pos += 1
        end
        while pos <= len do
            local c = string.sub(str, pos, pos)
            if (c >= "0" and c <= "9") or c == "." or c == "e" or c == "E" or c == "+" or c == "-" then
                pos += 1
            else
                break
            end
        end
        local numStr = string.sub(str, startPos, pos - 1)
        local n = tonumber(numStr)
        if n == nil then
            error("Invalid number at position " .. startPos)
        end
        return n
    end

    local function parseArray(): {any}
        if string.sub(str, pos, pos) ~= "[" then
            error("Expected '[' at position " .. pos)
        end
        pos += 1
        local arr = {}
        skipWhitespace()
        if string.sub(str, pos, pos) == "]" then
            pos += 1
            return arr
        end
        while true do
            local val = parseValue()
            table.insert(arr, val)
            skipWhitespace()
            local c = string.sub(str, pos, pos)
            if c == "]" then
                pos += 1
                break
            elseif c == "," then
                pos += 1
                skipWhitespace()
            else
                error("Expected ',' or ']' at position " .. pos)
            end
        end
        return arr
    end

    local function parseObject(): {[string]: any}
        if string.sub(str, pos, pos) ~= "{" then
            error("Expected '{' at position " .. pos)
        end
        pos += 1
        local obj = {}
        skipWhitespace()
        if string.sub(str, pos, pos) == "}" then
            pos += 1
            return obj
        end
        while true do
            skipWhitespace()
            local key = parseString()
            skipWhitespace()
            if string.sub(str, pos, pos) ~= ":" then
                error("Expected ':' at position " .. pos)
            end
            pos += 1
            local val = parseValue()
            obj[key] = val
            skipWhitespace()
            local c = string.sub(str, pos, pos)
            if c == "}" then
                pos += 1
                break
            elseif c == "," then
                pos += 1
                skipWhitespace()
            else
                error("Expected ',' or '}' at position " .. pos)
            end
        end
        return obj
    end

    function parseValue(): any
        skipWhitespace()
        if pos > len then
            error("Unexpected EOF")
        end
        local c = string.sub(str, pos, pos)
        if c == "{" then
            return parseObject()
        elseif c == "[" then
            return parseArray()
        elseif c == '"' then
            return parseString()
        elseif (c >= "0" and c <= "9") or c == "-" then
            return parseNumber()
        elseif string.sub(str, pos, pos + 3) == "true" then
            pos += 4
            return true
        elseif string.sub(str, pos, pos + 4) == "false" then
            pos += 5
            return false
        elseif string.sub(str, pos, pos + 3) == "null" then
            pos += 4
            return nil
        else
            error("Unexpected character '" .. c .. "' at position " .. pos)
        end
    end

    skipWhitespace()
    local result = parseValue()
    skipWhitespace()
    if pos <= len then
        error("Trailing characters at position " .. pos)
    end
    return result
end

-- Test framework
local passCount = 0
local failCount = 0

local function check(name: string, cond: boolean, msg: string?)
    if cond then
        passCount += 1
    else
        failCount += 1
        print("FAIL: " .. name .. (msg and (" (" .. msg .. ")") or ""))
    end
end

local function makeNewId(prefix: string?): () -> string
    local p = prefix or "t"
    local count = 0
    return function()
        count += 1
        return p .. tostring(count)
    end
end

-- 1. importV4
do
    local s1 = schedule.importV4(nil, parseJson)
    check("importV4 nil template len", #s1.template == 0)
    check("importV4 nil pushIncrement", s1.pushIncrement == 15)

    local s2 = schedule.importV4("not json", parseJson)
    check("importV4 invalid json template len", #s2.template == 0)
    check("importV4 invalid json pushIncrement", s2.pushIncrement == 15)

    -- also test without decode callback passed
    local s3 = schedule.importV4(nil)
    check("importV4 nil without decode template len", #s3.template == 0)
    check("importV4 nil without decode pushIncrement", s3.pushIncrement == 15)

    local v4Raw = '{"template":[{"label":"Scrum","start":540,"end":600}]}'
    local s4 = schedule.importV4(v4Raw, parseJson)
    check("importV4 valid template len", #s4.template == 1)
    local t0 = s4.template[1]
    check("importV4 valid label", t0.label == "Scrum")
    check("importV4 valid start", t0.start == 540)
    check("importV4 valid end", t0["end"] == 600)
    check("importV4 valid days len", t0.days ~= nil and #t0.days == 7)
    check("importV4 valid days values", t0.days ~= nil and t0.days[1] == 0 and t0.days[7] == 6)
    check("importV4 valid color", t0.color == "primary")
    check("importV4 valid notes", t0.notes == "")
    check("importV4 valid non-empty id", t0.id ~= nil and #t0.id > 0)
    check("importV4 valid today.date", s4.today.date == "")
    check("importV4 valid today.blocks len", #s4.today.blocks == 0)
end

-- 2. generateToday
do
    local tplA = {
        id = "tplA",
        label = "A",
        start = 540,
        ["end"] = 600,
        color = "primary",
        notes = "",
        days = {1, 2, 3, 4, 5},
    }
    local tplB = {
        id = "tplB",
        label = "B",
        start = 720,
        ["end"] = 780,
        color = "secondary",
        notes = "",
    }
    local template = { tplA, tplB }

    local gen0 = schedule.generateToday(template, "2026-10-25", 0, makeNewId("w0_"))
    check("generateToday weekday 0 count", #gen0.blocks == 1)
    check("generateToday weekday 0 block is B", gen0.blocks[1].templateId == "tplB")
    check("generateToday weekday 0 date", gen0.date == "2026-10-25")

    local gen1 = schedule.generateToday(template, "2026-10-26", 1, makeNewId("w1_"))
    check("generateToday weekday 1 count", #gen1.blocks == 2)
    check("generateToday weekday 1 block 1 is A", gen1.blocks[1].templateId == "tplA")
    check("generateToday weekday 1 block 2 is B", gen1.blocks[2].templateId == "tplB")
    check("generateToday weekday 1 templateId set", gen1.blocks[1].templateId == "tplA" and gen1.blocks[2].templateId == "tplB")
    check("generateToday weekday 1 skipped false", gen1.blocks[1].skipped == false and gen1.blocks[2].skipped == false)
    check("generateToday weekday 1 date", gen1.date == "2026-10-26")
end

-- 3. ensureToday
do
    local tplA = {
        id = "tplA",
        label = "A",
        start = 540,
        ["end"] = 600,
        color = "primary",
        notes = "",
        days = {1, 2, 3, 4, 5},
    }
    local tplB = {
        id = "tplB",
        label = "B",
        start = 720,
        ["end"] = 780,
        color = "primary",
        notes = "",
    }
    local initState = schedule.defaultState()
    initState.template = { tplA, tplB }
    initState.today = {
        date = "2026-10-21",
        blocks = {
            {
                id = "custom1",
                label = "Custom",
                start = 500,
                ["end"] = 550,
                color = "primary",
                notes = "",
                skipped = false,
                templateId = "tplA",
            }
        }
    }

    local stSame, changedSame = schedule.ensureToday(initState, "2026-10-21", 3, makeNewId("ens_"))
    check("ensureToday same date changed is false", changedSame == false)
    check("ensureToday same date blocks count unchanged", #stSame.today.blocks == 1)
    check("ensureToday same date block untouched", stSame.today.blocks[1].id == "custom1")

    local stNext, changedNext = schedule.ensureToday(initState, "2026-10-22", 4, makeNewId("ens_"))
    check("ensureToday new date changed is true", changedNext == true)
    check("ensureToday new date updated date", stNext.today.date == "2026-10-22")
    check("ensureToday new date blocks regenerated", #stNext.today.blocks == 2)
    check("ensureToday new date block 1 templateId", stNext.today.blocks[1].templateId == "tplA")
    check("ensureToday new date block 2 templateId", stNext.today.blocks[2].templateId == "tplB")
end

-- 4. active
do
    local b1 = { id = "b1", label = "540-600", start = 540, ["end"] = 600, color = "primary", notes = "", skipped = false }
    local b2 = { id = "b2", label = "570-630", start = 570, ["end"] = 630, color = "primary", notes = "", skipped = false }
    local b3Skipped = { id = "b3", label = "570-630-skip", start = 570, ["end"] = 630, color = "primary", notes = "", skipped = true }

    local act1 = schedule.active({ b1, b2 }, 580)
    check("active at 580 returns 570 block (latest start)", act1 ~= nil and act1.id == "b2")

    local act2 = schedule.active({ b1, b2 }, 600)
    check("active at 600 returns 570 block", act2 ~= nil and act2.id == "b2")

    local act3 = schedule.active({ b1, b3Skipped }, 580)
    check("active never returns skipped block", act3 ~= nil and act3.id == "b1")

    local act4 = schedule.active({ b1, b2 }, 700)
    check("active at 700 returns nil", act4 == nil)
end

-- 5. endNow
do
    local b1 = { id = "b1", label = "540-600", start = 540, ["end"] = 600, color = "primary", notes = "", skipped = false }
    local res1 = schedule.endNow({ b1 }, 540.4)
    check("endNow at 540.4 sets end to 541 (start+1)", #res1 == 1 and res1[1]["end"] == 541)

    local res2 = schedule.endNow({ b1 }, 575)
    check("endNow at 575 sets end to 575", #res2 == 1 and res2[1]["end"] == 575)
end

-- 6. push
do
    local pEarly = { id = "pEarly", label = "Early", start = 540, ["end"] = 600, color = "primary", notes = "", skipped = false }
    local p1 = { id = "p1", label = "P1", start = 600, ["end"] = 660, color = "primary", notes = "", skipped = false }
    local pSkip = { id = "pSkip", label = "Skip", start = 620, ["end"] = 680, color = "primary", notes = "", skipped = true }
    local p2 = { id = "p2", label = "P2", start = 1420, ["end"] = 1440, color = "primary", notes = "", skipped = false }

    local pushed = schedule.push({ pEarly, p1, pSkip, p2 }, 590, 30)
    local byId = {}
    for _, b in ipairs(pushed) do
        byId[b.id] = b
    end

    check("push p1 shifted to 630-690", byId["p1"] ~= nil and byId["p1"].start == 630 and byId["p1"]["end"] == 690)
    check("push p2 clamped to 1440-1440", byId["p2"] ~= nil and byId["p2"].start == 1440 and byId["p2"]["end"] == 1440)
    check("push pEarly started before now unchanged", byId["pEarly"] ~= nil and byId["pEarly"].start == 540 and byId["pEarly"]["end"] == 600)
    check("push pSkip skipped future block unchanged", byId["pSkip"] ~= nil and byId["pSkip"].start == 620 and byId["pSkip"]["end"] == 680)

    -- Near end of day push clamp check
    local late = { id = "late", label = "Late", start = 1430, ["end"] = 1440, color = "primary", notes = "", skipped = false }
    local pushedLate = schedule.push({ late }, 1400, 30)
    check("push fully past midnight clamps to 1440-1440", pushedLate[1].start == 1440 and pushedLate[1]["end"] == 1440)
end

-- 7. insertNow
do
    local existing = {
        { id = "e1", label = "E1", start = 540, ["end"] = 600, color = "primary", notes = "", skipped = false },
        { id = "e2", label = "E2", start = 700, ["end"] = 760, color = "primary", notes = "", skipped = false },
    }
    local inserted = schedule.insertNow(existing, 600.7, 30, "Ad-hoc", "primary", makeNewId("ins_"))
    check("insertNow count increased", #inserted == 3)
    -- Should be inserted in sorted order at index 2
    local newB = inserted[2]
    check("insertNow label is Ad-hoc", newB.label == "Ad-hoc")
    check("insertNow start is 600", newB.start == 600)
    check("insertNow end is 630", newB["end"] == 630)
    check("insertNow color is primary", newB.color == "primary")
    check("insertNow sorted order", inserted[1].start == 540 and inserted[2].start == 600 and inserted[3].start == 700)

    local insertedLate = schedule.insertNow({}, 1430, 30, "Ad-hoc", "primary", makeNewId("ins_"))
    check("insertNow at 1430 with 30m clamps end to 1440", #insertedLate == 1 and insertedLate[1]["end"] == 1440)
end

-- 8. saveAsTemplate
do
    local t1 = { id = "b1", label = "Scrum", start = 540, ["end"] = 600, color = "primary", notes = "notes1", skipped = false, templateId = "oldTpl" }
    local t2 = { id = "b2", label = "Walk", start = 660, ["end"] = 700, color = "secondary", notes = "notes2", skipped = true, templateId = "oldTpl2" }

    local newTpl, newToday = schedule.saveAsTemplate({ t1, t2 }, makeNewId("tpl_"))
    check("saveAsTemplate excludes skipped block from template", #newTpl == 1)
    check("saveAsTemplate new template block label", newTpl[1].label == "Scrum")
    check("saveAsTemplate new template block days", newTpl[1].days ~= nil and #newTpl[1].days == 7 and newTpl[1].days[1] == 0 and newTpl[1].days[7] == 6)
    check("saveAsTemplate new template id assigned", newTpl[1].id == "tpl_1")

    local byId = {}
    for _, b in ipairs(newToday) do
        byId[b.id] = b
    end
    check("saveAsTemplate today kept both blocks", #newToday == 2)
    check("saveAsTemplate today non-skipped relinked to new templateId", byId["b1"] ~= nil and byId["b1"].templateId == newTpl[1].id)
    check("saveAsTemplate today skipped has empty templateId", byId["b2"] ~= nil and byId["b2"].templateId == "")
end

-- 9. overlappingIds
do
    local b1 = { id = "id1", label = "B1", start = 540, ["end"] = 600, color = "primary", notes = "", skipped = false }
    local b2 = { id = "id2", label = "B2", start = 570, ["end"] = 630, color = "primary", notes = "", skipped = false }
    local b3 = { id = "id3", label = "B3", start = 600, ["end"] = 660, color = "primary", notes = "", skipped = false }

    local ov1 = schedule.overlappingIds({ b1, b2 })
    check("overlappingIds on 540-600 and 570-630 includes id1", ov1["id1"] == true)
    check("overlappingIds on 540-600 and 570-630 includes id2", ov1["id2"] == true)

    local ov2 = schedule.overlappingIds({ b1, b3 })
    check("overlappingIds on 540-600 and 600-660 is empty", next(ov2) == nil)
end

-- 10. fmt
do
    check("fmt(545) == '09:05'", schedule.fmt(545) == "09:05")
    check("fmt(0) == '00:00'", schedule.fmt(0) == "00:00")
    check("fmt(1439) == '23:59'", schedule.fmt(1439) == "23:59")
    check("fmt(1440) == '24:00'", schedule.fmt(1440) == "24:00")
end

-- 11. remaining
do
    local scrum = { id = "s1", label = "Scrum", start = 540, ["end"] = 600, color = "primary", notes = "", skipped = false }
    local textActive, activeBlk = schedule.remaining({ scrum }, 575 * 60)
    check("remaining active text", textActive == "Scrum · 25m left", textActive)
    check("remaining active block returned", activeBlk ~= nil and activeBlk.label == "Scrum")

    local lunch = { id = "l1", label = "Lunch", start = 720, ["end"] = 780, color = "primary", notes = "", skipped = false }
    local textGap, gapBlk = schedule.remaining({ lunch }, 600 * 60)
    check("remaining gap text", textGap == "Unscheduled · next in 2h 0m", textGap)
    check("remaining gap block is nil", gapBlk == nil)

    local textEmpty, emptyBlk = schedule.remaining({}, 600 * 60)
    check("remaining empty text", textEmpty == "Unscheduled", textEmpty)
    check("remaining empty block is nil", emptyBlk == nil)
end

-- Summary
if failCount > 0 then
    error(string.format("%d test(s) failed", failCount))
else
    print(string.format("all passed (%d checks)", passCount))
end
