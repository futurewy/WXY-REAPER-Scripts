-- @description Smart track renamer and preset manager with a Chinese reference for every preset
-- @version 1.0
-- @author futurewy
-- @about
--   Requires REAPER with the ReaImGui extension (available through ReaPack).
--
--   Renames the selected tracks from a preset list and stores the presets in
--   the project state. Presets show an English name with a Chinese reference,
--   while the written track name keeps the plain underscore form.
--
--   Features:
--     * The two columns can be resized by dragging the divider.
--     * Button widths follow the length of their text.
--     * Preset search, collapsible categories, and multi select, select all,
--       invert and batch delete with a confirmation.
--     * Automatic numbering for repeated names, and the next track is
--       selected after applying a preset.
--     * A world instrument library window that can add its entries to the
--       preset list in one click.
--     * Presets can be taken from the selected track, and colours are picked
--       with a colour picker.
local SECTION = "WXY_TRACK_RENAMER_PRO"
local EMPTY_MARK = "__EMPTY__"

-- 默认预设数据 (界面带中文对照，写入时自动清洗)
local default_presets = {
    -- Guitars & Bass (吉他与贝斯)
    {cat = "🎸 吉他与贝斯", name = "Acoustic_Guitar (原声吉他)", r = 100, g = 200, b = 100},
    {cat = "🎸 吉他与贝斯", name = "Electric_Guitar (电吉他)", r = 90, g = 170, b = 110},
    {cat = "🎸 吉他与贝斯", name = "Classical_Guitar (古典吉他)", r = 120, g = 210, b = 120},
    {cat = "🎸 吉他与贝斯", name = "Bass (贝斯)", r = 60, g = 120, b = 70},
    {cat = "🎸 吉他与贝斯", name = "Electric_Bass (电贝斯)", r = 50, g = 100, b = 60},
    {cat = "🎸 吉他与贝斯", name = "Slap_Bass (击勾贝斯)", r = 70, g = 140, b = 80},

    -- Vocals (人声)
    {cat = "🎤 人声", name = "Lead_Vocal (主唱)", r = 255, g = 100, b = 100},
    {cat = "🎤 人声", name = "Backing_Vocal (和声/伴唱)", r = 240, g = 130, b = 140},
    {cat = "🎤 人声", name = "Vocal_Harmony (和声组)", r = 220, g = 110, b = 120},
    {cat = "🎤 人声", name = "Chorus (合唱)", r = 255, g = 140, b = 150},

    -- Drums & Percussion (鼓与打击乐)
    {cat = "🥁 鼓与打击乐", name = "Drum_Bus (鼓总线)", r = 200, g = 100, b = 250},
    {cat = "🥁 鼓与打击乐", name = "Kick (底鼓)", r = 180, g = 80, b = 220},
    {cat = "🥁 鼓与打击乐", name = "Snare (军鼓)", r = 210, g = 110, b = 240},
    {cat = "🥁 鼓与打击乐", name = "Hi_Hat (踩镲)", r = 220, g = 140, b = 250},
    {cat = "🥁 鼓与打击乐", name = "Tom (通鼓)", r = 160, g = 70, b = 200},
    {cat = "🥁 鼓与打击乐", name = "Percussion (打击乐)", r = 190, g = 120, b = 220},

    -- Keyboards & Piano (键盘与钢琴)
    {cat = "🎹 键盘与钢琴", name = "Piano (钢琴)", r = 255, g = 210, b = 80},
    {cat = "🎹 键盘与钢琴", name = "Grand_Piano (三角钢琴)", r = 255, g = 230, b = 100},
    {cat = "🎹 键盘与钢琴", name = "Electric_Piano_Rhodes (电钢琴)", r = 230, g = 180, b = 70},
    {cat = "🎹 键盘与钢琴", name = "Organ (管风琴)", r = 210, g = 160, b = 60},

    -- Synths & Electronic (合成器与电子)
    {cat = "⚡ 合成器与电子", name = "Lead_Synth (主旋律合成器)", r = 70, g = 210, b = 220},
    {cat = "⚡ 合成器与电子", name = "Pad_Synth (铺底合成器)", r = 60, g = 180, b = 240},
    {cat = "⚡ 合成器与电子", name = "Bass_Synth (低音合成器)", r = 80, g = 230, b = 200},

    -- Strings (弦乐组)
    {cat = "🎻 弦乐组", name = "Strings_Ensemble (弦乐合奏)", r = 150, g = 100, b = 255},
    {cat = "🎻 弦乐组", name = "Violin (小提琴)", r = 170, g = 120, b = 255},
    {cat = "🎻 弦乐组", name = "Cello (大提琴)", r = 130, g = 80, b = 230},
    {cat = "🎻 弦乐组", name = "Double_Bass (低音提琴)", r = 110, g = 60, b = 200},

    -- Woodwinds (木管组)
    {cat = "🍃 木管组", name = "Flute (长笛)", r = 120, g = 220, b = 180},
    {cat = "🍃 木管组", name = "Clarinet (单簧管)", r = 100, g = 200, b = 160},
    {cat = "🍃 木管组", name = "Oboe (双簧管)", r = 90, g = 190, b = 150},

    -- Brass (铜管组)
    {cat = "🎺 铜管组", name = "Brass_Section (铜管乐段)", r = 255, g = 150, b = 50},
    {cat = "🎺 铜管组", name = "Trumpet (小号)", r = 255, g = 170, b = 70},
    {cat = "🎺 铜管组", name = "Trombone (长号)", r = 230, g = 130, b = 40},

    -- World & Traditional Folk (世界民乐)
    {cat = "🌏 世界民乐", name = "Pipa (琵琶)", r = 190, g = 130, b = 80},
    {cat = "🌏 世界民乐", name = "Guzheng (古筝)", r = 170, g = 110, b = 70},
    {cat = "🌏 世界民乐", name = "Erhu (二胡)", r = 160, g = 100, b = 60},
    {cat = "🌏 世界民乐", name = "Bamboo_Flute (竹笛)", r = 140, g = 160, b = 80},
    {cat = "🌏 世界民乐", name = "Xiao (箫)", r = 120, g = 140, b = 70},
}

-- 世界主流专业乐器与民乐标准库（全方位提供中英文对照）
local instrument_database = {
    {
        cat = "🎸 吉他与贝斯",
        items = {
            {name = "Acoustic_Guitar (原声吉他)", r = 100, g = 200, b = 100},
            {name = "Electric_Guitar (电吉他)", r = 90, g = 170, b = 110},
            {name = "Classical_Guitar (古典吉他)", r = 120, g = 210, b = 120},
            {name = "12_String_Guitar (12弦吉他)", r = 110, g = 190, b = 110},
            {name = "Bass (贝斯)", r = 60, g = 120, b = 70},
            {name = "Electric_Bass (电贝斯)", r = 50, g = 100, b = 60},
            {name = "Fretless_Bass (无品贝斯)", r = 55, g = 110, b = 65},
            {name = "Slap_Bass (击勾贝斯)", r = 70, g = 140, b = 80},
            {name = "Upright_Bass (立式低音提琴)", r = 40, g = 90, b = 50},
        }
    },
    {
        cat = "🎤 人声",
        items = {
            {name = "Lead_Vocal (主唱)", r = 255, g = 100, b = 100},
            {name = "Backing_Vocal (和声/伴唱)", r = 240, g = 130, b = 140},
            {name = "Vocal_Harmony (和声组)", r = 220, g = 110, b = 120},
            {name = "Chorus (合唱)", r = 255, g = 140, b = 150},
            {name = "Ad_lib (即兴人声/Adlib)", r = 255, g = 160, b = 170},
            {name = "Vocal_Double (人声双轨)", r = 230, g = 120, b = 130},
            {name = "Spoken_Word (旁白/说白)", r = 200, g = 90, b = 100},
        }
    },
    {
        cat = "🥁 鼓与打击乐",
        items = {
            {name = "Drum_Bus (鼓总线)", r = 200, g = 100, b = 250},
            {name = "Kick (底鼓)", r = 180, g = 80, b = 220},
            {name = "Snare (军鼓)", r = 210, g = 110, b = 240},
            {name = "Hi_Hat (踩镲)", r = 220, g = 140, b = 250},
            {name = "Tom (通鼓)", r = 160, g = 70, b = 200},
            {name = "Cymbal_Overhead (镲片/顶置)", r = 230, g = 160, b = 255},
            {name = "Percussion (打击乐)", r = 190, g = 120, b = 220},
            {name = "Shaker (沙锤)", r = 200, g = 130, b = 230},
            {name = "Tambourine (铃鼓)", r = 210, g = 150, b = 240},
            {name = "Conga_Bongo (康加/邦戈鼓)", r = 170, g = 90, b = 190},
        }
    },
    {
        cat = "🎹 键盘与钢琴",
        items = {
            {name = "Piano (钢琴)", r = 255, g = 210, b = 80},
            {name = "Grand_Piano (三角钢琴)", r = 255, g = 230, b = 100},
            {name = "Electric_Piano_Rhodes (电钢琴罗兹)", r = 230, g = 180, b = 70},
            {name = "Wurlitzer (夹底电钢琴)", r = 220, g = 170, b = 60},
            {name = "Organ (管风琴)", r = 210, g = 160, b = 60},
            {name = "Clavinet (克拉维琴)", r = 200, g = 150, b = 50},
            {name = "Harpsichord (羽管键琴)", r = 240, g = 200, b = 90},
            {name = "Accordion (手风琴)", r = 230, g = 190, b = 80},
        }
    },
    {
        cat = "⚡ 合成器与电子",
        items = {
            {name = "Lead_Synth (主旋律合成器)", r = 70, g = 210, b = 220},
            {name = "Pad_Synth (铺底合成器)", r = 60, g = 180, b = 240},
            {name = "Bass_Synth (低音合成器)", r = 80, g = 230, b = 200},
            {name = "Arp_Synth (琶音合成器)", r = 90, g = 200, b = 250},
            {name = "Pluck_Synth (拨弦合成器)", r = 75, g = 190, b = 230},
            {name = "Sub_Bass_Synth (超低音合成器)", r = 50, g = 160, b = 210},
            {name = "FX_Synth (特效合成器)", r = 100, g = 220, b = 255},
        }
    },
    {
        cat = "🎻 弦乐组",
        items = {
            {name = "Strings_Ensemble (弦乐合奏)", r = 150, g = 100, b = 255},
            {name = "Violin (小提琴)", r = 170, g = 120, b = 255},
            {name = "Viola (中提琴)", r = 160, g = 110, b = 245},
            {name = "Cello (大提琴)", r = 130, g = 80, b = 230},
            {name = "Double_Bass (低音提琴)", r = 110, g = 60, b = 200},
            {name = "Pizzicato_Strings (拨弦弦乐)", r = 180, g = 130, b = 255},
        }
    },
    {
        cat = "🍃 木管组",
        items = {
            {name = "Flute (长笛)", r = 120, g = 220, b = 180},
            {name = "Piccolo (短笛)", r = 140, g = 240, b = 200},
            {name = "Clarinet (单簧管)", r = 100, g = 200, b = 160},
            {name = "Oboe (双簧管)", r = 90, g = 190, b = 150},
            {name = "Bassoon (大管/巴松)", r = 80, g = 170, b = 130},
            {name = "English_Horn (英国管)", r = 110, g = 210, b = 170},
        }
    },
    {
        cat = "🎺 铜管组",
        items = {
            {name = "Brass_Section (铜管乐段)", r = 255, g = 150, b = 50},
            {name = "Trumpet (小号)", r = 255, g = 170, b = 70},
            {name = "Trombone (长号)", r = 230, g = 130, b = 40},
            {name = "French_Horn (圆号/法国号)", r = 210, g = 110, b = 30},
            {name = "Tuba (大号/低音号)", r = 190, g = 90, b = 20},
            {name = "Flugelhorn (富鲁格号)", r = 240, g = 160, b = 60},
        }
    },
    {
        cat = "🌏 世界民乐",
        items = {
            {name = "Pipa (琵琶)", r = 190, g = 130, b = 80},
            {name = "Guzheng (古筝)", r = 170, g = 110, b = 70},
            {name = "Erhu (二胡)", r = 160, g = 100, b = 60},
            {name = "Bamboo_Flute (竹笛)", r = 140, g = 160, b = 80},
            {name = "Xiao (箫)", r = 120, g = 140, b = 70},
            {name = "Shamisen (三味线)", r = 180, g = 120, b = 75},
            {name = "Koto (日本筝)", r = 165, g = 105, b = 65},
            {name = "Sitar (西塔尔)", r = 200, g = 140, b = 90},
            {name = "Oud (乌德琴)", r = 150, g = 95, b = 55},
            {name = "Bouzouki (布祖基琴)", r = 175, g = 115, b = 70},
            {name = "Celtic_Harp (凯尔特竖琴)", r = 160, g = 130, b = 90},
            {name = "Bagpipes (风笛)", r = 145, g = 90, b = 60},
            {name = "Pan_Flute (排箫)", r = 135, g = 150, b = 75},
        }
    }
}

-- ============================================================
-- 数据加载 / 保存
-- ============================================================

local function CopyDefaults()
    local t = {}
    for _, p in ipairs(default_presets) do
        t[#t + 1] = {cat = p.cat, name = p.name, r = p.r, g = p.g, b = p.b}
    end
    return t
end

-- 分隔符 ":" 和 "|" 会破坏存储格式，写入前统一替换
local function CleanField(s)
    return (s:gsub("[:|]", "_"))
end

local function LoadPresets()
    local data = reaper.GetExtState(SECTION, "presets")
    if data == "" then return CopyDefaults() end
    if data == EMPTY_MARK then return {} end -- 用户主动清空过全部预设
    local list = {}
    for item in data:gmatch("[^|]+") do
        local cat, name, r, g, b = item:match("([^:]+):([^:]+):(%d+):(%d+):(%d+)")
        if cat and name then
            table.insert(list, {cat = cat, name = name, r = tonumber(r), g = tonumber(g), b = tonumber(b)})
        end
    end
    if #list == 0 then return CopyDefaults() end
    return list
end

local function SavePresets(presets_tbl)
    if #presets_tbl == 0 then
        reaper.SetExtState(SECTION, "presets", EMPTY_MARK, true)
        return
    end
    local parts = {}
    for _, p in ipairs(presets_tbl) do
        table.insert(parts, string.format("%s:%s:%d:%d:%d", p.cat, p.name, p.r, p.g, p.b))
    end
    reaper.SetExtState(SECTION, "presets", table.concat(parts, "|"), true)
end

local presets = LoadPresets()

-- 记住用户的开关选项
local auto_number = reaper.GetExtState(SECTION, "auto_number") == "1"
local auto_next = reaper.GetExtState(SECTION, "auto_next") == "1"

local function SaveOptions()
    reaper.SetExtState(SECTION, "auto_number", auto_number and "1" or "0", true)
    reaper.SetExtState(SECTION, "auto_next", auto_next and "1" or "0", true)
end

-- ============================================================
-- 界面状态
-- ============================================================

local ctx = reaper.ImGui_CreateContext('WXY Track Renamer Pro')

local input_cat = "🎸 吉他与贝斯"
local input_name = "New_Track"
local edit_r, edit_g, edit_b = 100, 160, 240
local editing_index = nil
local color_input_str = string.format("%d, %d, %d", edit_r, edit_g, edit_b)

local search_text = ""
local selected = {}      -- 预设多选：selected[预设表] = true
local lib_selected = {}  -- 乐器库多选：lib_selected[乐器表] = true

local status_text, status_until = "", 0
local function SetStatus(msg)
    status_text = msg
    status_until = reaper.time_precise() + 3.5
end

-- ============================================================
-- 工具函数
-- ============================================================

-- 核心清洗函数：自动剥离括号及中文，将空格/特殊符号转为下划线，确保写入轨道时绝对符合纯英文下划线规范
local function SanitizeName(name)
    local clean = name:match("^(.-)%s*%(") or name
    clean = clean:gsub("%s+", "_")
    clean = clean:gsub("[^%w_]", "") -- 仅保留字母、数字和下划线
    if clean == "" then clean = "Track" end
    return clean
end

local function MatchesFilter(p, q)
    if q == "" then return true end
    return p.name:lower():find(q, 1, true) ~= nil or p.cat:lower():find(q, 1, true) ~= nil
end

local function SyncColorStr()
    color_input_str = string.format("%d, %d, %d", edit_r, edit_g, edit_b)
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
    else
        reaper.ImGui_Text(ctx, " ")
    end
end

-- 删除单个预设并修正编辑索引
local function DeletePresetAt(idx)
    local p = presets[idx]
    if p then selected[p] = nil end
    table.remove(presets, idx)
    SavePresets(presets)
    if editing_index == idx then
        editing_index = nil
    elseif editing_index and editing_index > idx then
        editing_index = editing_index - 1
    end
end

-- 应用预设到选中轨道
local function ApplyPreset(p)
    local n = reaper.CountSelectedTracks(0)
    if n == 0 then
        SetStatus("⚠ 请先在项目中选择至少一条轨道")
        return
    end

    -- 先把选中的轨道收集起来（后面可能会改变选中状态）
    local tracks = {}
    for i = 0, n - 1 do
        tracks[#tracks + 1] = reaper.GetSelectedTrack(0, i)
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local base_name = SanitizeName(p.name)
    local color_val = reaper.ColorToNative(p.r, p.g, p.b) | 0x1000000

    for i, tr in ipairs(tracks) do
        local nm = base_name
        if auto_number and #tracks > 1 then
            nm = base_name .. "_" .. i
        end
        reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", nm, true)
        reaper.SetTrackColor(tr, color_val)
    end

    local moved = false
    if auto_next then
        local last_tr = tracks[#tracks]
        local num = reaper.GetMediaTrackInfo_Value(last_tr, "IP_TRACKNUMBER") -- 从 1 开始
        local nxt = reaper.GetTrack(0, math.floor(num))
        if nxt then
            reaper.SetOnlyTrackSelected(nxt)
            moved = true
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("WXY: 智能重命名并着色轨道", -1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    if moved then
        reaper.Main_OnCommand(40913, 0) -- 将选中轨道滚动到可视区域
    end

    local shown = base_name
    if auto_number and #tracks > 1 then shown = base_name .. "_1 ~ _" .. #tracks end
    SetStatus("✔ 已应用到 " .. #tracks .. " 条轨道：" .. shown)
end

-- ============================================================
-- 主运行渲染循环
-- ============================================================

local function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 1000, 680, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, 'WXY 智能轨道重命名与预设管理 (全中文对照与自动清洗版)', true)

    if visible then
        local sel_tracks = reaper.CountSelectedTracks(0)

        -- 顶部状态栏
        DrawStatus()

        -- 两栏表格：可拖动中间分隔线调整左右宽度（Resizable）
        local table_flags = reaper.ImGui_TableFlags_Resizable() | reaper.ImGui_TableFlags_BordersInnerV()
        if reaper.ImGui_BeginTable(ctx, "MainLayoutTable", 2, table_flags, 0, 0) then
            reaper.ImGui_TableSetupColumn(ctx, "LeftCol", reaper.ImGui_TableColumnFlags_WidthStretch(), 3.0)
            reaper.ImGui_TableSetupColumn(ctx, "RightCol", reaper.ImGui_TableColumnFlags_WidthStretch(), 2.0)

            reaper.ImGui_TableNextRow(ctx)

            -- ==================== 左侧栏：预设列表 ====================
            reaper.ImGui_TableNextColumn(ctx)
            reaper.ImGui_Text(ctx, "📁 轨道预设列表 (点击名称应用 | ✏️ 编辑 | ❌ 删除)")
            reaper.ImGui_Separator(ctx)

            -- 应用选项
            reaper.ImGui_Text(ctx, "当前选中轨道: " .. sel_tracks .. " 条")
            local rv_n, v_n = reaper.ImGui_Checkbox(ctx, "多轨自动编号##opt_num", auto_number)
            if rv_n then auto_number = v_n; SaveOptions() end
            reaper.ImGui_SameLine(ctx)
            local rv_x, v_x = reaper.ImGui_Checkbox(ctx, "应用后自动选中下一条轨道##opt_next", auto_next)
            if rv_x then auto_next = v_x; SaveOptions() end

            -- 搜索框
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            local _, new_search = reaper.ImGui_InputTextWithHint(ctx, "##search", "🔍 搜索预设（中英文均可）...", search_text)
            search_text = new_search
            local q = search_text:lower()

            -- 统计当前可见的预设数量与已选数量
            local vis_count, vis_sel = 0, 0
            for _, p in ipairs(presets) do
                if MatchesFilter(p, q) then
                    vis_count = vis_count + 1
                    if selected[p] then vis_sel = vis_sel + 1 end
                end
            end

            -- 批量操作工具栏
            if reaper.ImGui_Button(ctx, "全选##sel_all") then
                for _, p in ipairs(presets) do
                    if MatchesFilter(p, q) then selected[p] = true end
                end
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "取消选择##sel_none") then
                for _, p in ipairs(presets) do
                    if MatchesFilter(p, q) then selected[p] = nil end
                end
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "反选##sel_inv") then
                for _, p in ipairs(presets) do
                    if MatchesFilter(p, q) then
                        if selected[p] then selected[p] = nil else selected[p] = true end
                    end
                end
            end
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x8A2A2AFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xB03A3AFF)
            if DisabledButton("删除选中 (" .. vis_sel .. ")##batch_del", 0, 0, vis_sel == 0) then
                reaper.ImGui_OpenPopup(ctx, "ConfirmBatchDelete")
            end
            reaper.ImGui_PopStyleColor(ctx, 2)
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_Text(ctx, "已选 " .. vis_sel .. " / 共 " .. vis_count)

            -- 批量删除确认弹窗
            if reaper.ImGui_BeginPopupModal(ctx, "ConfirmBatchDelete", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
                reaper.ImGui_Text(ctx, "确定要删除选中的 " .. vis_sel .. " 个预设吗？")
                reaper.ImGui_Text(ctx, "此操作无法撤销。")
                reaper.ImGui_Spacing(ctx)
                if reaper.ImGui_Button(ctx, "确认删除##confirm_del", 120, 28) then
                    local removed = 0
                    for i = #presets, 1, -1 do
                        local p = presets[i]
                        if selected[p] and MatchesFilter(p, q) then
                            table.remove(presets, i)
                            selected[p] = nil
                            removed = removed + 1
                        end
                    end
                    SavePresets(presets)
                    editing_index = nil
                    SetStatus("🗑 已删除 " .. removed .. " 个预设")
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "取消##cancel_del", 120, 28) then
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_EndPopup(ctx)
            end

            reaper.ImGui_Spacing(ctx)

            -- 预设列表滚动区
            if reaper.ImGui_BeginChild(ctx, "PresetScrollRegion", 0, 0, 1) then
                local sp = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
                local sx = reaper.ImGui_GetCursorScreenPos(ctx)
                local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
                local right_edge = sx + avail_w - 4
                local frame_h = reaper.ImGui_GetFrameHeight(ctx)

                local cats = {}
                local cat_order = {}
                for idx, p in ipairs(presets) do
                    if MatchesFilter(p, q) then
                        if not cats[p.cat] then
                            cats[p.cat] = {}
                            table.insert(cat_order, p.cat)
                        end
                        table.insert(cats[p.cat], {item = p, index = idx})
                    end
                end

                if #cat_order == 0 then
                    if #presets == 0 then
                        reaper.ImGui_TextDisabled(ctx, "暂无预设，可在右侧添加，或点击右下角“恢复默认预设”。")
                    else
                        reaper.ImGui_TextDisabled(ctx, "没有匹配的预设。")
                    end
                end

                for _, cat in ipairs(cat_order) do
                    local group_items = cats[cat]
                    reaper.ImGui_PushID(ctx, cat)

                    -- 搜索时强制展开；平时允许用户自行折叠
                    if q ~= "" then
                        reaper.ImGui_SetNextItemOpen(ctx, true, reaper.ImGui_Cond_Always())
                    else
                        reaper.ImGui_SetNextItemOpen(ctx, true, reaper.ImGui_Cond_Once())
                    end

                    if reaper.ImGui_TreeNode(ctx, cat .. " (" .. #group_items .. ")###tree_node") then
                        -- 本组快速选择
                        if reaper.ImGui_SmallButton(ctx, "选择本组##grp_sel") then
                            for _, d in ipairs(group_items) do selected[d.item] = true end
                        end
                        reaper.ImGui_SameLine(ctx)
                        if reaper.ImGui_SmallButton(ctx, "取消本组##grp_unsel") then
                            for _, d in ipairs(group_items) do selected[d.item] = nil end
                        end

                        -- 按本组中最长的名称计算按钮宽度，保证完整显示且整齐对齐
                        local max_tw = 0
                        for _, d in ipairs(group_items) do
                            local tw = reaper.ImGui_CalcTextSize(ctx, d.item.name)
                            if tw > max_tw then max_tw = tw end
                        end
                        local name_w = math.ceil(max_tw) + 20
                        local card_w = frame_h + 18 + name_w + 24 + 24 + sp * 4

                        for _, data in ipairs(group_items) do
                            reaper.ImGui_PushID(ctx, data.index)
                            local p = data.item

                            -- 0. 多选复选框
                            local rv_c, v_c = reaper.ImGui_Checkbox(ctx, "##chk", selected[p] or false)
                            if rv_c then selected[p] = v_c or nil end

                            reaper.ImGui_SameLine(ctx)

                            -- 1. 小色块
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(p.r/255, p.g/255, p.b/255, 1.0))
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(p.r/255, p.g/255, p.b/255, 1.0))
                            reaper.ImGui_Button(ctx, "##swatch", 18, 20)
                            reaper.ImGui_PopStyleColor(ctx, 2)

                            reaper.ImGui_SameLine(ctx)

                            -- 2. 应用预设按钮（宽度自适应；点击后 ApplyPreset 会自动剥离中文写入轨道）
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(p.r/255, p.g/255, p.b/255, 0.8))
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(p.r/255, p.g/255, p.b/255, 1.0))
                            if reaper.ImGui_Button(ctx, p.name .. "##apply", name_w, 20) then
                                ApplyPreset(p)
                            end
                            reaper.ImGui_PopStyleColor(ctx, 2)

                            reaper.ImGui_SameLine(ctx)
                            -- 3. 编辑按钮
                            if reaper.ImGui_Button(ctx, "✏️##edit", 24, 20) then
                                editing_index = data.index
                                input_cat = p.cat
                                input_name = p.name
                                edit_r, edit_g, edit_b = p.r, p.g, p.b
                                SyncColorStr()
                            end

                            reaper.ImGui_SameLine(ctx)
                            -- 4. 删除按钮
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x552222FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x883333FF)
                            if reaper.ImGui_Button(ctx, "❌##del", 24, 20) then
                                DeletePresetAt(data.index)
                            end
                            reaper.ImGui_PopStyleColor(ctx, 2)

                            reaper.ImGui_PopID(ctx)

                            -- 智能换行：右侧放得下下一张卡片就同行，否则换到下一行
                            local last_x2 = reaper.ImGui_GetItemRectMax(ctx)
                            if last_x2 + sp + card_w < right_edge then
                                reaper.ImGui_SameLine(ctx)
                            end
                        end

                        reaper.ImGui_Spacing(ctx)
                        reaper.ImGui_TreePop(ctx)
                    end
                    reaper.ImGui_PopID(ctx)
                end
                reaper.ImGui_EndChild(ctx)
            end

            -- ==================== 右侧栏：添加/修改预设控制面板 ====================
            reaper.ImGui_TableNextColumn(ctx)
            local panel_title = editing_index and ("✏️ 修改预设 [#" .. editing_index .. "]") or "➕ 添加新预设 / 管理"
            reaper.ImGui_Text(ctx, panel_title)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            -- 世界乐器库入口
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3A6EA5FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x4A8EC5FF)
            if reaper.ImGui_Button(ctx, "🎹 从世界乐器库网格选择...##btn_lib", -1, 30) then
                reaper.ImGui_OpenPopup(ctx, "InstrumentLibraryModal")
            end
            reaper.ImGui_PopStyleColor(ctx, 2)

            -- 从选中轨道提取名称和颜色
            if DisabledButton("🎯 从选中轨道提取名称和颜色##btn_extract", -1, 30, sel_tracks == 0) then
                local tr = reaper.GetSelectedTrack(0, 0)
                local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
                nm = CleanField(nm or "")
                if nm == "" then nm = "New_Track" end
                local col = reaper.GetTrackColor(tr)
                if col ~= 0 then
                    local r, g, b = reaper.ColorFromNative(col & 0xFFFFFF)
                    edit_r, edit_g, edit_b = r, g, b
                end
                input_name = nm
                editing_index = nil
                SyncColorStr()
                SetStatus("🎯 已提取：" .. nm .. "，请确认分类后点击“确认添加新预设”")
            end

            -- ---------- 世界乐器库弹窗（多选） ----------
            if reaper.ImGui_BeginPopupModal(ctx, "InstrumentLibraryModal", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
                reaper.ImGui_Text(ctx, "点击乐器可多选（白色边框 = 已选中，[已有] = 已在你的预设中）：")
                reaper.ImGui_Spacing(ctx)

                local have = {}
                for _, p in ipairs(presets) do have[p.name] = true end

                local lib_count = 0
                for _, group in ipairs(instrument_database) do
                    for _, inst in ipairs(group.items) do
                        if lib_selected[inst] then lib_count = lib_count + 1 end
                    end
                end

                if reaper.ImGui_BeginTabBar(ctx, "InstTabs", reaper.ImGui_TabBarFlags_None()) then
                    for _, group in ipairs(instrument_database) do
                        if reaper.ImGui_BeginTabItem(ctx, group.cat .. "##tab") then
                            reaper.ImGui_Spacing(ctx)

                            if reaper.ImGui_SmallButton(ctx, "全选本页##lib_page_all") then
                                for _, inst in ipairs(group.items) do lib_selected[inst] = true end
                            end
                            reaper.ImGui_SameLine(ctx)
                            if reaper.ImGui_SmallButton(ctx, "清空本页##lib_page_none") then
                                for _, inst in ipairs(group.items) do lib_selected[inst] = nil end
                            end
                            reaper.ImGui_Spacing(ctx)

                            -- 按本分类最长名称（含“[已有] ”前缀）计算统一按钮宽度
                            local sp = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
                            local max_tw = 0
                            for _, inst in ipairs(group.items) do
                                local tw = reaper.ImGui_CalcTextSize(ctx, "[已有] " .. inst.name)
                                if tw > max_tw then max_tw = tw end
                            end
                            local btn_w = math.ceil(max_tw) + 24
                            -- 弹窗为自动缩放，用固定最大宽度计算每行列数，避免循环依赖
                            local max_row_w = 760
                            local cols = math.max(1, math.floor((max_row_w + sp) / (btn_w + sp)))

                            for i, inst in ipairs(group.items) do
                                reaper.ImGui_PushID(ctx, inst.name)
                                local is_sel = lib_selected[inst] and true or false
                                local alpha = is_sel and 1.0 or 0.6
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(inst.r/255, inst.g/255, inst.b/255, alpha))
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(inst.r/255, inst.g/255, inst.b/255, 1.0))
                                if is_sel then
                                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 2)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xFFFFFFFF)
                                end

                                local label = (have[inst.name] and "[已有] " or "") .. inst.name
                                if reaper.ImGui_Button(ctx, label .. "##inst", btn_w, 30) then
                                    if is_sel then lib_selected[inst] = nil else lib_selected[inst] = true end
                                end

                                if is_sel then
                                    reaper.ImGui_PopStyleColor(ctx, 1)
                                    reaper.ImGui_PopStyleVar(ctx, 1)
                                end
                                reaper.ImGui_PopStyleColor(ctx, 2)
                                reaper.ImGui_PopID(ctx)

                                -- 每行 cols 个，行末不再 SameLine
                                if i % cols ~= 0 and i < #group.items then
                                    reaper.ImGui_SameLine(ctx)
                                end
                            end

                            reaper.ImGui_Spacing(ctx)
                            reaper.ImGui_EndTabItem(ctx)
                        end
                    end
                    reaper.ImGui_EndTabBar(ctx)
                end

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                DrawStatus()

                -- 一键加入我的预设（跳过已有的）
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2E7D4FFF)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3FA066FF)
                if DisabledButton("加入我的预设 (" .. lib_count .. ")##lib_add", 170, 28, lib_count == 0) then
                    local added, skipped = 0, 0
                    for _, group in ipairs(instrument_database) do
                        for _, inst in ipairs(group.items) do
                            if lib_selected[inst] then
                                if have[inst.name] then
                                    skipped = skipped + 1
                                else
                                    table.insert(presets, {cat = group.cat, name = inst.name, r = inst.r, g = inst.g, b = inst.b})
                                    have[inst.name] = true
                                    added = added + 1
                                end
                            end
                        end
                    end
                    lib_selected = {}
                    SavePresets(presets)
                    local msg = "✔ 已加入 " .. added .. " 个预设"
                    if skipped > 0 then msg = msg .. "（跳过 " .. skipped .. " 个已有项）" end
                    SetStatus(msg)
                end
                reaper.ImGui_PopStyleColor(ctx, 2)

                reaper.ImGui_SameLine(ctx)
                -- 把第一个选中的乐器填入右侧表单（用于加入前先改名/改色）
                if DisabledButton("填入右侧表单(取第一个)##lib_fill", 190, 28, lib_count == 0) then
                    local done = false
                    for _, group in ipairs(instrument_database) do
                        for _, inst in ipairs(group.items) do
                            if not done and lib_selected[inst] then
                                input_name = inst.name
                                input_cat = group.cat
                                edit_r, edit_g, edit_b = inst.r, inst.g, inst.b
                                editing_index = nil
                                SyncColorStr()
                                done = true
                            end
                        end
                    end
                    lib_selected = {}
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end

                reaper.ImGui_SameLine(ctx)
                if DisabledButton("清空选择##lib_clear", 100, 28, lib_count == 0) then
                    lib_selected = {}
                end

                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "关闭窗口##close_modal", 110, 28) then
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_EndPopup(ctx)
            end

            reaper.ImGui_Spacing(ctx)

            -- ---------- 表单：分类 / 名称 ----------
            reaper.ImGui_Text(ctx, "所属分类:")
            local unique_cats = {}
            local seen_cats = {}
            for _, p in ipairs(presets) do
                if not seen_cats[p.cat] then
                    seen_cats[p.cat] = true
                    table.insert(unique_cats, p.cat)
                end
            end
            for _, group in ipairs(instrument_database) do
                if not seen_cats[group.cat] then
                    seen_cats[group.cat] = true
                    table.insert(unique_cats, group.cat)
                end
            end

            if reaper.ImGui_BeginCombo(ctx, "##category_combo", input_cat) then
                for combo_i, c in ipairs(unique_cats) do
                    reaper.ImGui_PushID(ctx, combo_i)
                    local is_selected = (input_cat == c)
                    if reaper.ImGui_Selectable(ctx, c .. "##sel", is_selected) then
                        input_cat = c
                    end
                    if is_selected then
                        reaper.ImGui_SetItemDefaultFocus(ctx)
                    end
                    reaper.ImGui_PopID(ctx)
                end
                reaper.ImGui_EndCombo(ctx)
            end

            _, input_cat = reaper.ImGui_InputText(ctx, "分类名称 (自定义)##input_cat", input_cat)
            _, input_name = reaper.ImGui_InputText(ctx, "轨道名称##input_name", input_name)

            -- ---------- 颜色：取色器 + 可复制粘贴的 RGB 文本 ----------
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, "轨道颜色设置 (点击色块打开取色器):")

            local packed = (edit_r << 16) | (edit_g << 8) | edit_b
            local col_flags = reaper.ImGui_ColorEditFlags_NoInputs() | reaper.ImGui_ColorEditFlags_NoLabel()
            local rv_ce, new_packed = reaper.ImGui_ColorEdit3(ctx, "##color_edit", packed, col_flags)
            if rv_ce then
                edit_r = (new_packed >> 16) & 0xFF
                edit_g = (new_packed >> 8) & 0xFF
                edit_b = new_packed & 0xFF
            end

            reaper.ImGui_SameLine(ctx)

            reaper.ImGui_SetNextItemWidth(ctx, 140)
            local rv_col, new_col_str = reaper.ImGui_InputText(ctx, "RGB##color_text_input", color_input_str)
            if rv_col then
                color_input_str = new_col_str
                local r, g, b = new_col_str:match("(%d+)%D+(%d+)%D+(%d+)")
                if r and g and b then
                    edit_r = math.max(0, math.min(255, tonumber(r)))
                    edit_g = math.max(0, math.min(255, tonumber(g)))
                    edit_b = math.max(0, math.min(255, tonumber(b)))
                end
            end
            if not reaper.ImGui_IsItemActive(ctx) then
                SyncColorStr()
            end

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            -- ---------- 提交按钮 ----------
            if editing_index and presets[editing_index] then
                if reaper.ImGui_Button(ctx, "保存修改##btn_save", 110, 30) then
                    local p = presets[editing_index]
                    p.cat = CleanField(input_cat)
                    p.name = CleanField(input_name)
                    p.r, p.g, p.b = edit_r, edit_g, edit_b
                    SavePresets(presets)
                    SetStatus("✔ 预设修改成功：" .. p.name)
                    editing_index = nil
                end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "取消编辑##btn_cancel", 90, 30) then
                    editing_index = nil
                end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "删除##btn_del", 70, 30) then
                    DeletePresetAt(editing_index)
                    editing_index = nil
                    SetStatus("🗑 预设已删除")
                end
            else
                editing_index = nil
                if reaper.ImGui_Button(ctx, "确认添加新预设##btn_add", 140, 30) then
                    local nm = CleanField(input_name)
                    if nm == "" then
                        SetStatus("⚠ 轨道名称不能为空")
                    else
                        table.insert(presets, {cat = CleanField(input_cat), name = nm, r = edit_r, g = edit_g, b = edit_b})
                        SavePresets(presets)
                        SetStatus("✔ 新预设添加成功：" .. nm)
                    end
                end
            end

            -- ---------- 恢复默认预设 ----------
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)
            if reaper.ImGui_Button(ctx, "恢复默认预设##btn_restore", -1, 26) then
                reaper.ImGui_OpenPopup(ctx, "ConfirmRestoreDefaults")
            end

            if reaper.ImGui_BeginPopupModal(ctx, "ConfirmRestoreDefaults", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
                reaper.ImGui_Text(ctx, "将用默认预设替换当前全部预设（包括你自己添加的）。")
                reaper.ImGui_Text(ctx, "确定继续吗？")
                reaper.ImGui_Spacing(ctx)
                if reaper.ImGui_Button(ctx, "确认恢复##confirm_restore", 120, 28) then
                    presets = CopyDefaults()
                    selected = {}
                    editing_index = nil
                    SavePresets(presets)
                    SetStatus("✔ 已恢复默认预设")
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "取消##cancel_restore", 120, 28) then
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_EndPopup(ctx)
            end

            reaper.ImGui_EndTable(ctx)
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
