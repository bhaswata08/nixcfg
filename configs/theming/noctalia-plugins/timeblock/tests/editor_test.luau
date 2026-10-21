local editor = require("../lib/editor")

local totalChecks = 0
local failedChecks = 0

local function check(desc: string, cond: boolean)
    totalChecks += 1
    if not cond then
        failedChecks += 1
        print("FAIL: " .. desc)
    end
end

-- 1. parseHHMM valid cases
check("parseHHMM 00:00 is 0", editor.parseHHMM("00:00") == 0)
check("parseHHMM 0:00 is 0", editor.parseHHMM("0:00") == 0)
check("parseHHMM 09:00 is 540", editor.parseHHMM("09:00") == 540)
check("parseHHMM 9:00 is 540", editor.parseHHMM("9:00") == 540)
check("parseHHMM 9:05 is 545", editor.parseHHMM("9:05") == 545)
check("parseHHMM 12:30 is 750", editor.parseHHMM("12:30") == 750)
check("parseHHMM 23:59 is 1439", editor.parseHHMM("23:59") == 1439)
check("parseHHMM 24:00 is 1440", editor.parseHHMM("24:00") == 1440)
check("parseHHMM whitespace '  08:15  ' is 495", editor.parseHHMM("  08:15  ") == 495)

-- 2. parseHHMM invalid cases (explicitly: '25:00', '9:5x', '24:01')
check("parseHHMM '25:00' is nil", editor.parseHHMM("25:00") == nil)
check("parseHHMM '9:5x' is nil", editor.parseHHMM("9:5x") == nil)
check("parseHHMM '12:60' is nil", editor.parseHHMM("12:60") == nil)
check("parseHHMM '12:99' is nil", editor.parseHHMM("12:99") == nil)
check("parseHHMM '-1:00' is nil", editor.parseHHMM("-1:00") == nil)
check("parseHHMM '24:01' is nil", editor.parseHHMM("24:01") == nil)
check("parseHHMM '24:30' is nil", editor.parseHHMM("24:30") == nil)
check("parseHHMM '' is nil", editor.parseHHMM("") == nil)
check("parseHHMM '   ' is nil", editor.parseHHMM("   ") == nil)
check("parseHHMM 'invalid' is nil", editor.parseHHMM("invalid") == nil)
check("parseHHMM '12' is nil", editor.parseHHMM("12") == nil)
check("parseHHMM '12:' is nil", editor.parseHHMM("12:") == nil)
check("parseHHMM ':30' is nil", editor.parseHHMM(":30") == nil)
check("parseHHMM '1:2:3' is nil", editor.parseHHMM("1:2:3") == nil)
check("parseHHMM '99:99' is nil", editor.parseHHMM("99:99") == nil)

-- 3. Nonces and revert tracking
check("initial nonce for blk1 start is 0", editor.getNonce("blk1", "start") == 0)
check("initial nonce for blk1 end is 0", editor.getNonce("blk1", "end") == 0)
local bumpedStart = editor.bumpNonce("blk1", "start")
check("bumped blk1 start nonce is 1", bumpedStart == 1 and editor.getNonce("blk1", "start") == 1)
check("blk1 end nonce remains 0 after blk1 start bump", editor.getNonce("blk1", "end") == 0)
local bumpedStart2 = editor.bumpNonce("blk1", "start")
check("bumped blk1 start nonce again is 2", bumpedStart2 == 2 and editor.getNonce("blk1", "start") == 2)
local bumpedEnd = editor.bumpNonce("blk1", "end")
check("bumped blk1 end nonce is 1", bumpedEnd == 1 and editor.getNonce("blk1", "end") == 1)

-- 4. timeInputKey generation
local key0 = editor.timeInputKey("start", "blk_test", "start", 540)
check("timeInputKey with 0 nonce", key0 == "start_blk_test_540_0")
editor.bumpNonce("blk_test", "start")
local key1 = editor.timeInputKey("start", "blk_test", "start", 540)
check("timeInputKey after bump has updated nonce", key1 == "start_blk_test_540_1")
check("keys before and after bump are different", key0 ~= key1)

-- 5. resolveColor helper
check("resolveColor with optText", editor.resolveColor("0", "tertiary") == "tertiary")
check("resolveColor idx '0' is primary", editor.resolveColor("0", nil) == "primary")
check("resolveColor idx '1' is secondary", editor.resolveColor("1", nil) == "secondary")
check("resolveColor idx '2' is tertiary", editor.resolveColor("2", nil) == "tertiary")
check("resolveColor idx '3' is error", editor.resolveColor("3", nil) == "error")
check("resolveColor idx '4' is nil", editor.resolveColor("4", nil) == nil)
check("resolveColor invalid idx is nil", editor.resolveColor("invalid", nil) == nil)

-- 6. colorRoles list
check("colorRoles has 4 elements", #editor.colorRoles == 4)
check("colorRoles has primary", editor.colorRoles[1] == "primary")
check("colorRoles has secondary", editor.colorRoles[2] == "secondary")
check("colorRoles has tertiary", editor.colorRoles[3] == "tertiary")
check("colorRoles has error", editor.colorRoles[4] == "error")

if failedChecks == 0 then
    print(string.format("all passed (%d checks)", totalChecks))
else
    error(string.format("%d of %d checks failed", failedChecks, totalChecks))
end
