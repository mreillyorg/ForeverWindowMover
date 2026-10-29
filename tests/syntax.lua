-- Compile every shipped Lua file without running it. Cheapest guard against
-- shipping a parse error. Run from the repository root: lua5.1 tests/syntax.lua
--
-- The module list is read from the TOC rather than duplicated here, so a file
-- added to the TOC is compile-checked automatically and one added to the folder
-- but forgotten in the TOC is reported.
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]syntax%.lua$")) or "./"
local TOC = "ForeverWindowMover.toc"

local manifest = assert(io.open(base .. TOC, "r"), "cannot open " .. TOC)
local text = manifest:read("*a")
manifest:close()

local modules = {}
local sawVersion, sawInterface = false, false
for raw in text:gmatch("[^\r\n]+") do
    -- Strip a UTF-8 BOM on the first line and surrounding whitespace.
    local line = raw:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line:match("^##%s*Version%s*:") then sawVersion = true end
    if line:match("^##%s*Interface%s*:") then sawInterface = true end
    if line ~= "" and line:sub(1, 1) ~= "#" then
        assert(line:match("^[%w_%-]+%.lua$") or line:match("^[%w_%-]+%.xml$"),
            "unexpected TOC entry in " .. TOC .. ": " .. line)
        if line:match("%.lua$") then modules[#modules + 1] = line end
    end
end
assert(sawVersion, TOC .. " has no ## Version line")
assert(sawInterface, TOC .. " has no ## Interface line")
assert(#modules > 0, TOC .. " lists no Lua modules")

for _, filename in ipairs(modules) do
    local chunk, err = loadfile(base .. filename)
    assert(chunk, "Lua syntax error in " .. filename .. ": " .. tostring(err))
end

-- The .luacheckrc assigns `files` as a whole table rather than indexing it, so
-- it loads under a plain interpreter too. Compiling it here means a typo in the
-- lint configuration is caught by the harness rather than by a confusing
-- luacheck failure later.
local rc, rcErr = loadfile(base .. ".luacheckrc")
assert(rc, "Lua syntax error in .luacheckrc: " .. tostring(rcErr))

-- A Lua file in the repository root that the TOC does not load would never run
-- in game. The packager ships it regardless, so catch it here.
local listed = {}
for _, name in ipairs(modules) do listed[name] = true end
local pipe = io.popen and io.popen("ls " .. base .. "*.lua 2>/dev/null || dir /b " ..
    base .. "*.lua 2>nul")
if pipe then
    for path in pipe:lines() do
        local leaf = path:gsub("^.*[/\\]", ""):gsub("%s+$", "")
        if leaf ~= "" and not listed[leaf] then
            pipe:close()
            error(leaf .. " is in the repository root but not listed in " .. TOC)
        end
    end
    pipe:close()
end

print("PASSED: " .. #modules .. " TOC-listed Lua files and .luacheckrc compile")
