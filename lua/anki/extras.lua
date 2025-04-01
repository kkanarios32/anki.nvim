local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local api = require("anki.api")
local anki = require("anki")

local M = {}

-- Use vim.loop (libuv) and built-in Neovim API functions
local uv = vim.loop

-- Function to hash a course name into a short directory name.
-- This version takes the first letter of each word and makes them lowercase.
local function fileHash(courseName)
    local hash = ""
    for word in courseName:gmatch("%S+") do
        hash = hash .. word:sub(1, 1):lower()
    end
    return hash
end

local function dirHash(courseName)
    return courseName:lower():gsub("%s+", "_")
end

-- Function to ensure the directory exists, creating it if necessary.
local function ensureDirectory(dir)
    if not uv.fs_stat(dir) then
        -- vim.fn.mkdir with "p" creates intermediate directories if needed
        vim.fn.mkdir(dir, "p")
    end
end

-- Function to get the next file name in the directory.
-- It searches for files matching the pattern: hash-XXXX (with 4-digit numbers)
local function getNextFileName(dir, hash)
    local maxNum = 0
    local scanner = uv.fs_scandir(dir)
    if scanner then
        while true do
            local name = uv.fs_scandir_next(scanner)
            if not name then
                break
            end
            local numStr = name:match("^" .. hash .. "%-(%d%d%d%d)$")
            if numStr then
                local num = tonumber(numStr)
                if num and num > maxNum then
                    maxNum = num
                end
            end
        end
    end
    local nextNum = maxNum + 1
    return string.format("%s-%04d.anki", hash, nextNum)
end

-- Main routine to create the course file.
local function createCourseFile(base_dir, course)
    -- Compute the directory name by hashing the course name.
    local dirName = dirHash(course)
    dirName = base_dir .. dirName
    ensureDirectory(dirName)

    -- Get the next file name
    local fileName = getNextFileName(dirName, fileHash(course))
    local filePath = dirName .. "/" .. fileName

    -- Open the file for writing (mode "w" creates a new file)
    local fd, err = uv.fs_open(filePath, "w", 438) -- 438 is octal 0666
    if not fd then
        error("Error opening file " .. filePath .. ": " .. err)
    end

    return filePath
end

local function createFileAndAnki(base_dir, deckName)
    local filePath = createCourseFile(base_dir, deckName)
    vim.cmd("edit " .. filePath)
    anki.ankiWithDeck(deckName, "Basic")
end

M.AnkiWithPickedDeck = function(config)
    local deckNames = api.deckNames()
    pickers
        .new({}, {
            prompt_title = "Select an item",
            finder = finders.new_table({
                results = deckNames,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, _)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    createFileAndAnki(config.flashcard_dir, selection.value)
                end)
                return true
            end,
        })
        :find()
end

M.setup = function(config)
    vim.api.nvim_create_user_command("AnkiDebug", function()
        local content =
            vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, 0)
        content = table.concat(content, "\n")
        local buffer = require("anki.buffer")
        parsed = buffer.parse(content)
    end, {})
end

return M
