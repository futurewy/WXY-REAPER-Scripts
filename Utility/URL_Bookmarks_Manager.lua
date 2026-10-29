-- @description URL Bookmarks Menu (safe URL launching and corrected menu mapping)
-- @version 2.1
-- @author futurewy
-- @about
--   Manage persistent URL bookmarks from a mouse-position popup menu.
--   Supports opening, adding, renaming, editing URLs, deleting, and reordering.
--   Opening requires SWS CF_ShellExecute; only HTTP(S) and file URLs are allowed.
--   File URLs use the system handler and must only point to trusted files.
-- @changelog
--   Remove shell-based URL fallback; require SWS CF_ShellExecute and validate schemes.
--   Fix submenu endings and command mapping; sanitize display labels.
--   Validate line-based storage and split records at the first delimiter.

local section = "URL_Bookmarks_Menu"

local function load_bookmarks()
    local data = reaper.GetExtState(section, "Data")
    local list = {}
    if data and data ~= "" then
        for line in string.gmatch(data, "[^\r\n]+") do
            local name, url = string.match(line, "^(.-)|||(.*)$")
            if name and url then
                table.insert(list, { name = name, url = url })
            end
        end
    end
    return list
end

local function show_error(message)
    reaper.MB(message, "URL Bookmarks", 0)
end

local function save_bookmarks(list)
    local records = {}
    for _, item in ipairs(list) do
        -- Keep the existing ExtState format without silently corrupting records.
        if item.name:find("[%c]") or item.name:find("|||", 1, true)
            or item.url:find("[%c]") then
            show_error("名称和 URL 不能包含控制字符，名称不能包含 |||。未保存更改。")
            return false
        end
        records[#records + 1] = item.name .. "|||" .. item.url .. "\n"
    end
    reaper.SetExtState(section, "Data", table.concat(records), true)
    return true
end

local function normalize_url(url)
    -- Do not pass control characters, raw quotes or embedded whitespace to handlers.
    if url:find("[%c]") then return nil end
    url = url:match("^%s*(.-)%s*$")
    if url == "" or url:find('[%s"]') then return nil end
    local scheme = url:match("^([%a][%w+.-]*):")
    if scheme and not url:match("^[%w.-]+:%d+") then
        scheme = scheme:lower()
        if scheme ~= "http" and scheme ~= "https" and scheme ~= "file" then
            return nil
        end
        -- Normalize only the scheme; preserve case-sensitive paths and query data.
        url = scheme .. url:sub(#scheme + 1)
    else
        url = "https://" .. url
    end
    if url:match("^https?://[^/%?#]+") or url:match("^file://.+") then
        return url
    end
end

local function open_url(url)
    local normalized = normalize_url(url)
    if not normalized then
        show_error("URL 无效：仅支持 http://、https://、file:// 或无协议网址。请将空格和双引号进行 URL 编码。")
        return
    end
    -- Never interpolate bookmark data into cmd.exe, a shell, or a command line.
    -- SWS uses the native URL handler. Missing SWS fails closed on every OS.
    if type(reaper.CF_ShellExecute) ~= "function" then
        show_error("打开网址需要 SWS 扩展 (CF_ShellExecute)。为安全起见，不使用 shell 命令回退。")
        return
    end
    local ok, result = pcall(reaper.CF_ShellExecute, normalized)
    if not ok or result == false or (type(result) == "number" and result == 0) then
        show_error("无法打开 URL。请检查系统默认应用和 SWS 扩展。")
    end
end

-- ==========================================
-- 核心修复：菜单构建与动作闭包映射引擎
-- ==========================================
local menu_entries = {}
local actions = {}
local folder_start = nil

local function display_name(name)
    -- gfx.showmenu interprets these as syntax, not literal bookmark text.
    local clean = name:gsub("[|<>#!%c]", "")
    return clean ~= "" and clean or "未命名"
end

local function add_item(name, func)
    menu_entries[#menu_entries + 1] = display_name(name)
    actions[#actions + 1] = func
end

local function add_disabled(name)
    menu_entries[#menu_entries + 1] = "#" .. display_name(name)
    -- Disabled items count as command IDs; separators and submenu headings do not.
    actions[#actions + 1] = function() end
end

local function add_sep()
    menu_entries[#menu_entries + 1] = ""
end

local function start_folder(name)
    assert(not folder_start, "Nested folders are not supported")
    menu_entries[#menu_entries + 1] = ">" .. display_name(name)
    folder_start = #menu_entries
end

local function end_folder()
    -- '<' belongs on the LAST child, not on the next folder or next item.
    assert(folder_start and #menu_entries > folder_start, "Empty submenu")
    menu_entries[#menu_entries] = "<" .. menu_entries[#menu_entries]
    folder_start = nil
end

-- ==========================================
-- 主逻辑
-- ==========================================
local function main()
    menu_entries, actions, folder_start = {}, {}, nil
    local bookmarks = load_bookmarks()

    -- 1. 动态生成网址列表
    if #bookmarks == 0 then
        add_disabled("列表为空 - 请点击下方添加")
    else
        for i, item in ipairs(bookmarks) do
            add_item(tostring(i) .. ". " .. item.name, function() open_url(item.url) end)
        end
    end

    add_sep()

    -- 2. 添加网址 (修正了字符串分割导致的解析失败)
    add_item("➕ 添加新网址...", function()
        local retval, csv = reaper.GetUserInputs("添加网址", 2, "名称:,URL (包含http):,extrawidth=250", "新网址,https://")
        if retval then
            -- 采用非贪婪正则匹配，完美兼容 URL 中包含逗号的情况
            local n, u = string.match(csv, "^(.-),(.*)$")
            if n and u and u ~= "" then
                if n == "" then n = "未命名" end
                table.insert(bookmarks, {name=n, url=u})
                save_bookmarks(bookmarks)
            end
        end
    end)

    -- 3. 管理选项子目录
    if #bookmarks > 0 then
        start_folder("✏️ 修改名称")
        for i, item in ipairs(bookmarks) do
            add_item(item.name, function()
                local r, new_n = reaper.GetUserInputs("修改名称", 1, "新名称:,extrawidth=200", item.name)
                if r and new_n ~= "" then
                    bookmarks[i].name = new_n
                    save_bookmarks(bookmarks)
                end
            end)
        end
        end_folder()

        start_folder("🔗 修改 URL")
        for i, item in ipairs(bookmarks) do
            add_item(item.name, function()
                local r, new_u = reaper.GetUserInputs("修改 URL", 1, "新 URL:,extrawidth=300", item.url)
                if r and new_u ~= "" then
                    bookmarks[i].url = new_u
                    save_bookmarks(bookmarks)
                end
            end)
        end
        end_folder()

        start_folder("❌ 删除网址")
        for i, item in ipairs(bookmarks) do
            add_item(item.name, function()
                local mb = reaper.MB("确定删除 '"..item.name.."'?", "删除确认", 4)
                if mb == 6 then
                    table.remove(bookmarks, i)
                    save_bookmarks(bookmarks)
                end
            end)
        end
        end_folder()

        start_folder("⬆️ 上移")
        for i, item in ipairs(bookmarks) do
            if i == 1 then
                add_disabled(item.name)
            else
                add_item(item.name, function()
                    bookmarks[i], bookmarks[i-1] = bookmarks[i-1], bookmarks[i]
                    save_bookmarks(bookmarks)
                end)
            end
        end
        end_folder()

        start_folder("⬇️ 下移")
        for i, item in ipairs(bookmarks) do
            if i == #bookmarks then
                add_disabled(item.name)
            else
                add_item(item.name, function()
                    bookmarks[i], bookmarks[i+1] = bookmarks[i+1], bookmarks[i]
                    save_bookmarks(bookmarks)
                end)
            end
        end
        end_folder()
    end

    -- ==========================================
    -- 弹窗与触发
    -- ==========================================
    gfx.init("URL_Menu", 0, 0, 0, 0, 0)
    local x, y = reaper.GetMousePosition()
    gfx.x, gfx.y = gfx.screentoclient(x, y)

    local selection = gfx.showmenu(table.concat(menu_entries, "|"))
    gfx.quit()

    -- 直接从闭包数组中提取动作执行，不再进行任何数学计算
    if selection > 0 and actions[selection] then
        actions[selection]()
    end
end

reaper.defer(main)
