-- @description Smart region marker: create a named and coloured Region from the time selection
-- @version 1.0
-- @author futurewy
-- @about
--   Requires REAPER with the ReaImGui extension (available through ReaPack).
--
--   Usage:
--     1. Select a time range in the arrange view. Without a time selection the
--        range of the selected media item is used.
--     2. Click a preset button. The button shows "English (Chinese)" while
--        only the English part is written into the Region.
--     3. Right click a preset button to edit or delete it, and use the add
--        button to create a new preset.
--
--   Notes:
--     * Clicking a preset again at the same position renames and recolours the
--       existing Region instead of stacking a duplicate.
--     * Repeating sections are numbered automatically as Verse 1, Verse 2 and
--       so on. Each preset decides on its own whether it takes part in the
--       numbering, so Intro and Outro stay unnumbered by default.
local SECTION = "WXY_SMART_REGION_MAKER_V2"
local EMPTY_MARK = "__EMPTY__"

-- ============================================================
-- 默认预设：通俗歌曲常见结构（界面中英对照，写入时只取英文）
-- num = 重复出现时是否自动编号
-- ============================================================
local default_presets = {
    {cat = "🎼 歌曲结构", name = "Intro (前奏)",          r = 107, g = 123, b = 140, num = false},
    {cat = "🎼 歌曲结构", name = "Verse (主歌)",          r = 74,  g = 144, b = 217, num = true },
    {cat = "🎼 歌曲结构", name = "Pre-Chorus (预副歌)",   r = 80,  g = 192, b = 200, num = true },
    {cat = "🎼 歌曲结构", name = "Chorus (副歌)",         r = 232, g = 80,  b = 58,  num = true },
    {cat = "🎼 歌曲结构", name = "Post-Chorus (后副歌)",  r = 240, g = 138, b = 75,  num = true },
    {cat = "🎼 歌曲结构", name = "Interlude (间奏)",      r = 168, g = 216, b = 168, num = true },
    {cat = "🎼 歌曲结构", name = "Solo (独奏)",           r = 126, g = 211, b = 33,  num = true },
    {cat = "🎼 歌曲结构", name = "Bridge (桥段)",         r = 155, g = 89,  b = 182, num = false},
    {cat = "🎼 歌曲结构", name = "Breakdown (拆解段)",    r = 100, g = 100, b = 110, num = true },
    {cat = "🎼 歌曲结构", name = "Key Change (转调段)",   r = 255, g = 217, b = 61,  num = false},
    {cat = "🎼 歌曲结构", name = "Coda (尾声)",           r = 110, g = 90,  b = 140, num = false},
    {cat = "🎼 歌曲结构", name = "Outro (尾奏)",          r = 74,  g = 85,  b = 104, num = false},
}

local DEFAULT_CAT = "🎼 歌曲结构"

-- ============================================================
-- 持久化
-- ============================================================
local function CopyDefaults()
    local t = {}
    for _, p in ipairs(default_presets) do
        t[#t + 1] = {cat = p.cat, name = p.name, r = p.r, g = p.g, b = p.b, num = p.num}
    end
    return t
end

-- 分隔符 ":" 和 "|" 会破坏存储格式，写入前统一替换
local function CleanField(s) return (s:gsub("[:|]", "_")) end

local function LoadPresets()
    local data = reaper.GetExtState(SECTION, "presets")
    if data == "" then return CopyDefaults() end
    if data == EMPTY_MARK then return {} end
    local list = {}
    for item in data:gmatch("[^|]+") do
        local cat, name, r, g, b, n = item:match("([^:]+):([^:]+):(%d+):(%d+):(%d+):?(%d*)")
        if cat and name then
            table.insert(list, {
                cat = cat, name = name,
                r = tonumber(r), g = tonumber(g), b = tonumber(b),
                num = (n ~= "0"),
            })
        end
    end
    if #list == 0 then return CopyDefaults() end
    return list
end

local function SavePresets(tbl)
    if #tbl == 0 then
        reaper.SetExtState(SECTION, "presets", EMPTY_MARK, true)
        return
    end
    local parts = {}
    for _, p in ipairs(tbl) do
        table.insert(parts, string.format("%s:%s:%d:%d:%d:%d", p.cat, p.name, p.r, p.g, p.b, p.num and 1 or 0))
    end
    reaper.SetExtState(SECTION, "presets", table.concat(parts, "|"), true)
end

local presets = LoadPresets()

-- 自动编号开关（编号分隔符固定为空格）
local auto_number = reaper.GetExtState(SECTION, "auto_number") ~= "0"

local function SaveOptions()
    reaper.SetExtState(SECTION, "auto_number", auto_number and "1" or "0", true)
end

-- ============================================================
-- 名称处理
-- ============================================================

-- 取括号前的英文部分，保留字母 / 数字 / 空格 / 连字符 / 下划线；没有英文则返回 nil
local function SanitizeName(name)
    local cut = #name + 1
    local a = name:find("(", 1, true)
    local b = name:find("（", 1, true)
    if a and a < cut then cut = a end
    if b and b < cut then cut = b end
    local clean = name:sub(1, cut - 1)
    clean = clean:gsub("[^A-Za-z0-9%s%-_]", "")
    clean = clean:gsub("%s+", " ")
    clean = clean:match("^%s*(.-)%s*$")
    if clean == "" then return nil end
    return clean
end

local function EscapeLuaPattern(s)
    return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

-- ============================================================
-- Region 缓存：只在工程发生变化时重新扫描，避免每帧遍历
-- ============================================================
local rg_cache, rg_stamp = {}, -1

local function GetRegions()
    local stamp = reaper.GetProjectStateChangeCount(0)
    if stamp ~= rg_stamp then
        rg_stamp = stamp
        rg_cache = {}
        local _, nm, nr = reaper.CountProjectMarkers(0)
        local total = (nm or 0) + (nr or 0)
        for i = 0, total - 1 do
            local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers3(0, i)
            if retval and retval > 0 and isrgn then
                rg_cache[#rg_cache + 1] = {pos = pos, e = rgnend, name = name or "", idx = idx}
            end
        end
    end
    return rg_cache
end

-- 计算最终写入名称。skip_idx：计数时忽略的 region（正在被改名的那个）
local function ComputeName(base, numbered, skip_idx)
    if not (auto_number and numbered) then return base end
    local sep = " "
    local pattern = "^" .. EscapeLuaPattern(base) .. EscapeLuaPattern(sep) .. "(%d+)$"
    local max_n = 0
    for _, r in ipairs(GetRegions()) do
        if r.idx ~= skip_idx then
            local n = r.name:match(pattern)
            if n then
                local nn = tonumber(n)
                if nn and nn > max_n then max_n = nn end
            end
        end
    end
    return base .. sep .. (max_n + 1)
end

local function FindRegionAt(s, e)
    for _, r in ipairs(GetRegions()) do
        if math.abs(r.pos - s) < 0.0005 and math.abs(r.e - e) < 0.0005 then
            return r
        end
    end
    return nil
end

-- ============================================================
-- 范围：优先时间选区，其次选中的媒体 item
-- ============================================================
local function GetRange()
    local s, e = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if s and e and e > s then return s, e, "time" end

    local n = reaper.CountSelectedMediaItems(0)
    if n > 0 then
        local mn, mx = math.huge, -math.huge
        for i = 0, n - 1 do
            local it = reaper.GetSelectedMediaItem(0, i)
            local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
            if pos < mn then mn = pos end
            if pos + len > mx then mx = pos + len end
        end
        if mx > mn then return mn, mx, "item" end
    end
    return 0, 0, nil
end

-- ============================================================
-- 创建 Region
-- ============================================================
local function CreateRegion(display_name, r, g, b, numbered, s, e)
    if not s or e <= s then
        return false, "⚠ 请先在时间轴框选一个时间选区"
    end
    local base = SanitizeName(display_name)
    if not base then
        return false, "⚠ 名称需要包含英文"
    end

    local color = reaper.ColorToNative(r, g, b) | 0x1000000
    local existing = FindRegionAt(s, e)
    local final = ComputeName(base, numbered, existing and existing.idx or nil)

    reaper.Undo_BeginBlock()
    local ok
    if existing then
        ok = reaper.SetProjectMarker3(0, existing.idx, true, s, e, final, color)
    else
        local idx = reaper.AddProjectMarker2(0, true, s, e, final, -1, color)
        ok = idx and idx >= 0
    end
    reaper.Undo_EndBlock("WXY: 创建区域 " .. final, -1)
    reaper.UpdateArrange()

    if not ok then return false, "⚠ 创建区域失败" end
    if existing then
        return true, string.format("✔ 该位置已有区域，已改为 [%s]", final)
    end
    return true, string.format("✔ 已创建区域 [%s]  %.2fs ~ %.2fs", final, s, e)
end

-- ============================================================
-- 界面状态
-- ============================================================
local ctx = reaper.ImGui_CreateContext('WXY Smart Region Maker')

local status_text, status_until = "", 0
local last_custom = nil  -- 刚用「自定义名称」创建的区域，状态栏提供「存为预设」
local function SetStatus(msg)
    status_text = msg
    status_until = reaper.time_precise() + 4
end

local custom_name = ""
local custom_r, custom_g, custom_b = 100, 160, 240
local search_text = ""

-- 编辑小窗状态
local e_target = nil       -- 正在编辑的预设（nil = 新建）
local e_cat, e_name = DEFAULT_CAT, ""
local e_r, e_g, e_b = 100, 160, 240
local e_num = true
local open_edit_request = false

local function BeginEdit(p)
    e_target = p
    if p then
        e_cat, e_name = p.cat, p.name
        e_r, e_g, e_b = p.r, p.g, p.b
        e_num = p.num
    else
        local last = presets[#presets]
        e_cat = last and last.cat or DEFAULT_CAT
        e_name = ""
        e_r, e_g, e_b = 100, 160, 240
        e_num = true
    end
    open_edit_request = true
end

local function MatchesFilter(p, q)
    if q == "" then return true end
    return p.name:lower():find(q, 1, true) ~= nil or p.cat:lower():find(q, 1, true) ~= nil
end

-- 带“禁用”外观的按钮：禁用时变淡且点击无效
local function DisabledButton(label, w, h, disabled)
    if disabled then reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.4) end
    local clicked = reaper.ImGui_Button(ctx, label, w, h)
    if disabled then reaper.ImGui_PopStyleVar(ctx) end
    return clicked and not disabled
end

local function DrawStatus()
    if reaper.time_precise() < status_until then
        reaper.ImGui_TextColored(ctx, 0x7FDB8AFF, status_text)
        if last_custom then
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_SmallButton(ctx, "存为预设##save_custom") then
                local last = presets[#presets]
                table.insert(presets, {
                    cat = last and last.cat or DEFAULT_CAT,
                    name = CleanField(last_custom.name),
                    r = last_custom.r, g = last_custom.g, b = last_custom.b,
                    num = true,
                })
                SavePresets(presets)
                last_custom = nil
                SetStatus("✔ 已保存为预设")
            end
        end
    else
        last_custom = nil
        reaper.ImGui_Text(ctx, " ")
    end
end

local function PackColor(r, g, b) return (r << 16) | (g << 8) | b end
local function UnpackColor(c) return (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF end

-- ============================================================
-- 主循环
-- ============================================================
local function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 540, 440, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, 'WXY 智能区域标记器 · 歌曲结构版', true)

    if visible then
        local rs, re, source = GetRange()
        local has_range = source ~= nil

        -- ── 顶部：当前范围 ──
        if source == "time" then
            reaper.ImGui_TextColored(ctx, 0x7FDB8AFF,
                string.format("⏱ 时间选区：%.2fs ~ %.2fs（时长 %.2fs）", rs, re, re - rs))
        elseif source == "item" then
            reaper.ImGui_TextColored(ctx, 0xF0C060FF,
                string.format("⏱ 使用选中 item 范围：%.2fs ~ %.2fs（时长 %.2fs）", rs, re, re - rs))
        else
            reaper.ImGui_TextColored(ctx, 0xFF6B6BFF, "⚠ 请先在时间轴框选一个时间选区")
        end

        DrawStatus()

        -- ── 自动编号开关 + 设置 ──
        local rv_n, v_n = reaper.ImGui_Checkbox(ctx, "自动编号 (Verse 1, Verse 2…)##auto_num", auto_number)
        if rv_n then auto_number = v_n; SaveOptions() end


        -- ── 搜索框：预设较多时才出现 ──
        local q = ""
        if #presets >= 20 then
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            local _, ns = reaper.ImGui_InputTextWithHint(ctx, "##search", "🔍 搜索预设...", search_text)
            search_text = ns
            q = search_text:lower()
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ── 预设按钮网格 ──
        local cats, cat_order = {}, {}
        local max_tw = 0
        for idx, p in ipairs(presets) do
            if MatchesFilter(p, q) then
                if not cats[p.cat] then
                    cats[p.cat] = {}
                    table.insert(cat_order, p.cat)
                end
                table.insert(cats[p.cat], {item = p, index = idx})
                local tw = reaper.ImGui_CalcTextSize(ctx, p.name)
                if tw > max_tw then max_tw = tw end
            end
        end

        local sp = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local btn_w = math.max(120, math.ceil(max_tw) + 24)
        local cols = math.max(1, math.floor((avail_w + sp) / (btn_w + sp)))
        local show_cat_title = #cat_order > 1

        if #cat_order == 0 then
            if #presets == 0 then
                reaper.ImGui_TextDisabled(ctx, "暂无预设，可点下方「＋ 添加预设」新建，或：")
                if reaper.ImGui_Button(ctx, "恢复默认预设##restore", btn_w, 26) then
                    presets = CopyDefaults()
                    SavePresets(presets)
                    SetStatus("✔ 已恢复默认预设")
                end
            else
                reaper.ImGui_TextDisabled(ctx, "没有匹配的预设。")
            end
        end

        for _, cat in ipairs(cat_order) do
            local items = cats[cat]
            if show_cat_title then
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_TextDisabled(ctx, cat)
            end

            for i, data in ipairs(items) do
                local p = data.item
                reaper.ImGui_PushID(ctx, data.index)

                local alpha = has_range and 0.85 or 0.35
                local alpha_h = has_range and 1.0 or 0.5
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),
                    reaper.ImGui_ColorConvertDouble4ToU32(p.r/255, p.g/255, p.b/255, alpha))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),
                    reaper.ImGui_ColorConvertDouble4ToU32(p.r/255, p.g/255, p.b/255, alpha_h))
                local clicked = reaper.ImGui_Button(ctx, p.name .. "##apply", btn_w, 32)
                reaper.ImGui_PopStyleColor(ctx, 2)

                if clicked then
                    if has_range then
                        local _, msg = CreateRegion(p.name, p.r, p.g, p.b, p.num, rs, re)
                        last_custom = nil
                        SetStatus(msg)
                    else
                        SetStatus("⚠ 请先在时间轴框选一个时间选区")
                    end
                end

                -- 右键：编辑 / 删除
                if reaper.ImGui_IsItemClicked(ctx, 1) then
                    BeginEdit(p)
                end

                -- 悬停提示：实际写入名称
                if reaper.ImGui_IsItemHovered(ctx) then
                    local base = SanitizeName(p.name)
                    local will_be = base and ComputeName(base, p.num, nil) or "（缺少英文名称）"
                    reaper.ImGui_SetTooltip(ctx, "将写入：" .. will_be .. "\n右键：编辑 / 删除")
                end

                reaper.ImGui_PopID(ctx)

                if i % cols ~= 0 and i < #items then
                    reaper.ImGui_SameLine(ctx)
                end
            end
        end

        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, "＋ 添加预设##add_preset", btn_w, 26) then
            BeginEdit(nil)
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ── 自定义名称：输入后回车（或点「创建」）直接创建 ──
        reaper.ImGui_Text(ctx, "自定义名称：")
        reaper.ImGui_SetNextItemWidth(ctx, -150)
        local _, cn = reaper.ImGui_InputTextWithHint(ctx, "##custom_name", "如 Refrain (叠句)，回车创建", custom_name)
        custom_name = cn
        local enter_pressed = false
        if reaper.ImGui_IsItemActive(ctx) then
            local ok1, v1 = pcall(function()
                return reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
            end)
            local ok2, v2 = pcall(function()
                return reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
            end)
            enter_pressed = (ok1 and v1) or (ok2 and v2) or false
        end

        reaper.ImGui_SameLine(ctx)
        local col_flags = reaper.ImGui_ColorEditFlags_NoInputs() | reaper.ImGui_ColorEditFlags_NoLabel()
        local rv_ce, np = reaper.ImGui_ColorEdit3(ctx, "##custom_color", PackColor(custom_r, custom_g, custom_b), col_flags)
        if rv_ce then custom_r, custom_g, custom_b = UnpackColor(np) end

        reaper.ImGui_SameLine(ctx)
        local custom_base = SanitizeName(custom_name)
        local can_create = has_range and custom_base ~= nil
        local create_clicked = DisabledButton("创建##custom_create", 60, 0, not can_create)

        if custom_name ~= "" then
            if custom_base then
                reaper.ImGui_TextDisabled(ctx, "将写入：" .. ComputeName(custom_base, true, nil))
            else
                reaper.ImGui_TextColored(ctx, 0xFF6B6BFF, "需要包含英文名称")
            end
        end

        if (create_clicked or (enter_pressed and can_create)) then
            local ok, msg = CreateRegion(custom_name, custom_r, custom_g, custom_b, true, rs, re)
            SetStatus(msg)
            if ok then
                last_custom = {name = custom_name, r = custom_r, g = custom_g, b = custom_b}
                custom_name = ""
            end
        end

        -- ── 编辑 / 新建 预设小窗 ──
        if open_edit_request then
            reaper.ImGui_OpenPopup(ctx, "EditPresetPopup")
            open_edit_request = false
        end
        if reaper.ImGui_BeginPopupModal(ctx, "EditPresetPopup", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_Text(ctx, e_target and "编辑预设" or "新建预设")
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            reaper.ImGui_Text(ctx, "名称（英文 (中文)，只会写入英文部分）：")
            reaper.ImGui_SetNextItemWidth(ctx, 300)
            local _, nv = reaper.ImGui_InputTextWithHint(ctx, "##e_name", "例：Refrain (叠句)", e_name)
            e_name = nv

            local e_base = SanitizeName(e_name)
            if e_base then
                reaper.ImGui_TextDisabled(ctx, "将写入：" .. e_base)
            elseif e_name ~= "" then
                reaper.ImGui_TextColored(ctx, 0xFF6B6BFF, "需要包含英文名称")
            else
                reaper.ImGui_Text(ctx, " ")
            end

            reaper.ImGui_Text(ctx, "分类：")
            reaper.ImGui_SetNextItemWidth(ctx, 300)
            local _, cv = reaper.ImGui_InputText(ctx, "##e_cat", e_cat)
            e_cat = cv

            reaper.ImGui_Spacing(ctx)
            local col_flags2 = reaper.ImGui_ColorEditFlags_NoInputs() | reaper.ImGui_ColorEditFlags_NoLabel()
            local rv_e, pe = reaper.ImGui_ColorEdit3(ctx, "##e_color", PackColor(e_r, e_g, e_b), col_flags2)
            if rv_e then e_r, e_g, e_b = UnpackColor(pe) end
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_Text(ctx, "点击色块选择颜色")

            local rv_num, v_num = reaper.ImGui_Checkbox(ctx, "重复出现时自动编号##e_num", e_num)
            if rv_num then e_num = v_num end

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            if DisabledButton("保存##e_save", 100, 28, e_base == nil) then
                local cat = CleanField(e_cat)
                if cat == "" then cat = DEFAULT_CAT end
                if e_target then
                    e_target.cat = cat
                    e_target.name = CleanField(e_name)
                    e_target.r, e_target.g, e_target.b = e_r, e_g, e_b
                    e_target.num = e_num
                    SetStatus("✔ 预设已保存")
                else
                    table.insert(presets, {
                        cat = cat, name = CleanField(e_name),
                        r = e_r, g = e_g, b = e_b, num = e_num,
                    })
                    SetStatus("✔ 已添加新预设")
                end
                SavePresets(presets)
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "取消##e_cancel", 100, 28) then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            if e_target then
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x8A2A2AFF)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xB03A3AFF)
                if reaper.ImGui_Button(ctx, "删除##e_delete", 100, 28) then
                    for i = #presets, 1, -1 do
                        if presets[i] == e_target then
                            table.remove(presets, i)
                            break
                        end
                    end
                    SavePresets(presets)
                    SetStatus("🗑 已删除预设")
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_PopStyleColor(ctx, 2)
            end

            reaper.ImGui_EndPopup(ctx)
        end

        reaper.ImGui_End(ctx)
    end

    if open then
        reaper.defer(loop)
    else
        if reaper.ImGui_DestroyContext then
            reaper.ImGui_DestroyContext(ctx)
        end
    end
end

reaper.defer(loop)
