local bit = require("bit")
local call_errors = {}
local function checked_call(context, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        local now, message = globals.realtime(), tostring(a)
        local previous = call_errors[context]
        if not previous or previous.message ~= message or now < previous.time or now-previous.time >= 5 then
            client.error_log("[Ünoins_qucy] " .. context .. ": " .. message)
            call_errors[context] = {time=now, message=message}
        end
    end
    return ok, a, b, c, d
end
local json_ok, json = checked_call("optional dependency", require, "json")
local clipboard
do
    local ok_cp, cp = checked_call("optional dependency", require, "gamesense/clipboard")
    if ok_cp and cp and type(cp) == "table" and cp.get and cp.set then
        clipboard = cp
    else
        local ffi = require("ffi")
        checked_call("optional dependency", ffi.cdef, [[
            typedef void* HANDLE;
            typedef void* HGLOBAL;
            typedef void* HWND;
            typedef unsigned int UINT;
            HWND GetActiveWindow(void);
            bool OpenClipboard(HWND hWndNewOwner);
            bool CloseClipboard(void);
            bool EmptyClipboard(void);
            HANDLE SetClipboardData(UINT uFormat, HANDLE hMem);
            HANDLE GetClipboardData(UINT uFormat);
            HGLOBAL GlobalAlloc(UINT uFlags, size_t dwBytes);
            void* GlobalLock(HGLOBAL hMem);
            bool GlobalUnlock(HGLOBAL hMem);
            HGLOBAL GlobalFree(HGLOBAL hMem);
            size_t GlobalSize(HGLOBAL hMem);
        ]])
        local user32 = ffi.load("user32.dll")
        local kernel32 = ffi.load("kernel32.dll")
        clipboard = {
            get = function()
                assert(user32.OpenClipboard(nil), "clipboard: OpenClipboard failed")
                local memory, pointer
                local ok, text = pcall(function()
                    memory = user32.GetClipboardData(1)
                    if memory == nil then return "" end
                    local size = tonumber(kernel32.GlobalSize(memory))
                    assert(size and size > 0 and size <= 2097153, "clipboard: invalid or oversized text")
                    pointer = kernel32.GlobalLock(memory)
                    assert(pointer ~= nil, "clipboard: GlobalLock failed")
                    local bytes = ffi.string(pointer, size)
                    local finish = bytes:find("\0", 1, true)
                    assert(finish, "clipboard: text is not NUL-terminated")
                    return bytes:sub(1, finish-1)
                end)
                if pointer ~= nil then kernel32.GlobalUnlock(memory) end
                user32.CloseClipboard()
                if not ok then error(text, 0) end
                return text
            end,
            set = function(text)
                text = tostring(text)
                local memory = kernel32.GlobalAlloc(0x0042, #text+1)
                assert(memory ~= nil, "clipboard: GlobalAlloc failed")
                local pointer = kernel32.GlobalLock(memory)
                if pointer == nil then kernel32.GlobalFree(memory); error("clipboard: GlobalLock failed") end
                ffi.copy(pointer, text, #text)
                ffi.cast("char*", pointer)[#text] = 0
                kernel32.GlobalUnlock(memory)
                local owner = user32.GetActiveWindow()
                if owner == nil or not user32.OpenClipboard(owner) then
                    kernel32.GlobalFree(memory)
                    error("clipboard: active window unavailable or OpenClipboard failed")
                end
                if not user32.EmptyClipboard() or user32.SetClipboardData(1, memory) == nil then
                    user32.CloseClipboard()
                    kernel32.GlobalFree(memory)
                    error("clipboard: SetClipboardData failed")
                end
                user32.CloseClipboard()
                return true
            end
        }
    end
end

local TAB, CON = "AA", "Anti-aimbot angles"

local function safe_ref(tab, con, name)
    local ok, a, b, c = checked_call("safe_ref", ui.reference, tab, con, name)
    if ok then return a, b, c end
end
local N = {}
N.enabled = safe_ref(TAB, CON, "Enabled")
N.pitch, N.pitch_add = safe_ref(TAB, CON, "Pitch")
N.yaw_base = safe_ref(TAB, CON, "Yaw base")
N.yaw, N.yaw_add = safe_ref(TAB, CON, "Yaw")
N.yaw_jitter, N.yaw_jit_add = safe_ref(TAB, CON, "Yaw jitter")
N.body_yaw, N.body_yaw_add= safe_ref(TAB, CON, "Body yaw")
N.fs_body = safe_ref(TAB, CON, "Freestanding body yaw")
N.edge_yaw = safe_ref(TAB, CON, "Edge yaw")
N.freestand, N.fs_mode = safe_ref(TAB, CON, "Freestanding")
N.roll = safe_ref(TAB, CON, "Roll")
N.fake_enabled = safe_ref(TAB, "Fake lag", "Enabled")
N.fake_amt = safe_ref(TAB, "Fake lag", "Amount")
N.fake_var = safe_ref(TAB, "Fake lag", "Variance")
N.fake_limit = safe_ref(TAB, "Fake lag", "Limit")
local other_hide = {}
do
    local a, b = safe_ref(TAB, "Other", "On shot anti-aim"); other_hide[#other_hide+1] = a; other_hide[#other_hide+1] = b
    local a, b = safe_ref(TAB, "Other", "Slow motion"); other_hide[#other_hide+1] = a; other_hide[#other_hide+1] = b
    local a, b = safe_ref(TAB, "Other", "Fake peek"); other_hide[#other_hide+1] = a; other_hide[#other_hide+1] = b
    local a, b = safe_ref(TAB, "Other", "Leg movement"); other_hide[#other_hide+1] = a; other_hide[#other_hide+1] = b
end

local function native_visible(visible)
    for _, ref in pairs(N) do if ref then ui.set_visible(ref, visible) end end
    for _, ref in ipairs(other_hide) do if ref then ui.set_visible(ref, visible) end end
end

local native_hotkey_modes = {"Always on", "On hotkey", "Toggle", "Off hotkey"}
local native_snapshot

local function capture_native()
    if native_snapshot then return end
    local snapshot = {}
    for key, ref in pairs(N) do
        if ref then
            if key == "fs_mode" then
                local ok, _, mode, hotkey = checked_call("capture_native", ui.get, ref)
                if ok and native_hotkey_modes[(tonumber(mode) or -1) + 1] then
                    snapshot[key] = {native_hotkey_modes[mode + 1], tonumber(hotkey) or 0}
                end
            else
                local ok, value = checked_call("capture_native", ui.get, ref)
                if ok and value ~= nil then snapshot[key] = {value} end
            end
        end
    end
    native_snapshot = snapshot
end

local function reset_native()
    local snapshot = native_snapshot
    native_snapshot = nil
    if not snapshot then return end
    for key, values in pairs(snapshot) do
        local ref = N[key]
        if ref then checked_call("restore native " .. key, function() ui.set(ref, unpack(values)) end) end
    end
end
local aa_decision = {
    active = false,
    priority = 0,
    order = 0,
    requests = {},
    managed = {},
    refs = {}
}
local aa_managed_keys = {
    "enabled", "pitch", "pitch_add", "yaw_base", "yaw", "yaw_add",
    "yaw_jitter", "yaw_jit_add", "body_yaw", "body_yaw_add",
    "fs_body", "edge_yaw", "roll"
}
for i = 1, #aa_managed_keys do
    local ref = N[aa_managed_keys[i]]
    if ref then
        aa_decision.refs[#aa_decision.refs + 1] = ref
        aa_decision.managed[ref] = true
    end
end

local function aa_begin(priority)
    aa_decision.active = true
    aa_decision.priority = priority or 0
    aa_decision.jitter_offset = 0
    aa_decision.order = 0
    aa_decision.requests = {}
end

local function aa_owner(priority)
    aa_decision.priority = priority or 0
end

local function aa_cancel()
    aa_decision.active = false
    aa_decision.requests = {}
end

local function aa_commit()
    aa_decision.active = false
    for i = 1, #aa_decision.refs do
        local ref = aa_decision.refs[i]
        local request = ref and aa_decision.requests[ref]
        if request then ui.set(ref, request.value) end
    end
    aa_decision.requests = {}
end

local function nset(ref, val)
    if not ref then return false end
    if aa_decision.active and aa_decision.managed[ref] then
        aa_decision.order = aa_decision.order + 1
        local current = aa_decision.requests[ref]
        if not current
            or aa_decision.priority > current.priority
            or aa_decision.priority == current.priority and aa_decision.order > current.order then
            aa_decision.requests[ref] = {
                value = val,
                priority = aa_decision.priority,
                order = aa_decision.order
            }
        end
        return true
    end
    ui.set(ref, val)
    return true
end
local freestand_requested, freestand_applied = false, false
local freestand_mode_ready = false

local function invalidate_freestand_controller()
    freestand_requested = false
    freestand_applied = false
    freestand_mode_ready = false
end

local function apply_native_freestand(active)
    active = active == true
    if not freestand_mode_ready then
        freestand_mode_ready = nset(N.fs_mode, "Always on")
    end
    if not N.freestand then freestand_applied=false; return end
    if ui.get(N.freestand) ~= active then nset(N.freestand, active) end
    freestand_applied = active and ui.get(N.freestand) == true
end

local master = ui.new_checkbox(TAB, CON, "\aFFF59DFFÜnoins_qucy")
local page_sel = ui.new_combobox(TAB, CON, "Page", "Home", "\aFFF59DFFAnti-Aim\r", "Misc", "Visuals")

local function get_saved_config_names()
    local ok, list = checked_call("get_saved_config_names", database.read, "unoins_cfg_list")
    if ok and type(list) == "table" and #list > 0 then return list end
    return { "default" }
end

local function save_config_names_list(list)
    database.write("unoins_cfg_list", list)
end
local active_config_names = get_saved_config_names()
local cfg_listbox = ui.new_listbox(TAB, CON, "Configs", active_config_names)
local cfg_name_box = ui.new_textbox(TAB, CON, "Config name")
local cfg_load_btn = ui.new_button(TAB, CON, "Load", function() end)
local cfg_save_btn = ui.new_button(TAB, CON, "Save", function() end)
local cfg_delete_btn = ui.new_button(TAB, CON, "Delete", function() end)
local cfg_import_btn = ui.new_button(TAB, CON, "Import from clipboard", function() end)
local cfg_export_btn = ui.new_button(TAB, CON, "Export to clipboard", function() end)
local defensive_backend = ui.new_combobox(TAB, "Fake lag", "Defensive mode", "\a87B313FFGamesense\r", "\aFFF59DFFÜnoins_qucy\r", "\aFF9C9CFFÜnoins_qucy Pro\r")
local pro = {state={}, reset=function() end}
pro.duck = safe_ref("RAGE", "Other", "Duck peek assist")
local safe_head_weapons = ui.new_multiselect(TAB, "Fake lag", "Safe head", "Knife", "Taser", "Glock-18")
local manual_left = ui.new_hotkey(TAB, "Fake lag", "Left", false)
local manual_right = ui.new_hotkey(TAB, "Fake lag", "Right", false)
local manual_fwd = ui.new_hotkey(TAB, "Fake lag", "Forward", false)
local fs_hotkey = ui.new_hotkey(TAB, "Fake lag", "Freestanding", false)
local fs_states = ui.new_multiselect(TAB, "Fake lag", "Freestanding states", "Standing", "Moving", "Slowwalk", "Air", "Air+", "Duck", "Duck move")
local fs_options = ui.new_multiselect(TAB, "Fake lag", "Freestanding options", "Disable yaw jitter", "Disable body yaw")
local edge_hotkey = ui.new_hotkey(TAB, "Fake lag", "Edge yaw", false)
local anti_backstab = ui.new_checkbox(TAB, "Fake lag", "Anti backstab")
local fl_ground_mode = ui.new_combobox(TAB, "Fake lag", "Adaptive ground fake lag", "Low choke", "Maximum")
local _, slow_key = safe_ref(TAB, "Other", "Slow motion")
local condition_sel = ui.new_combobox(TAB, CON, "Condition",
    "Global", "Standing", "Moving", "Slowwalk", "Air", "Air+", "Duck", "Duck move", "Freestanding")
local conditions = { "Global", "Standing", "Moving", "Slowwalk", "Air", "Air+", "Duck", "Duck move", "Freestanding" }
local update_vis
local extras = {ui={}, controls={}, headers={}, cvars={}, native={}, pose={}, drop={}, velocity={}, sync=function() end, cleanup=function() end, pre_command=function() end, post_command=function() end, onshot=function() return false end}

function extras.add(key, kind, page, group, parent, ...)
    local ref = ui["new_"..kind](TAB, group, ...)
    extras.ui[key] = ref
    extras.controls[#extras.controls+1] = {key=key, ref=ref, kind=kind, page=page, parent=parent}
    return ref
end

function extras.header(page, group, name)
    name=name:sub(1,1):upper()..name:sub(2):lower()
    extras.headers[#extras.headers+1] = {page=page, ref=ui.new_label(TAB, group, "\aA8E6A3FF"..name:sub(1,1).."\r"..name:sub(2))}
end
extras.header("Visuals", CON, "SCOPE / AIMING")
extras.add("scope", "checkbox", "Visuals", CON, nil, "Scope Lines")
extras.add("scope_color", "color_picker", "Visuals", CON, "scope", "Scope accent", 255, 255, 255, 235)
extras.add("scope_style", "combobox", "Visuals", CON, "scope", "Scope style", "Soft", "Classic", "Diagonal")
extras.add("scope_exclude", "multiselect", "Visuals", CON, "scope", "Hidden arms", "Top", "Bottom", "Left", "Right")
extras.add("scope_length", "slider", "Visuals", CON, "scope", "Scope length", 20, 260, 105, true, "px")
extras.add("scope_gap", "slider", "Visuals", CON, "scope", "Scope gap", 0, 90, 10, true, "px")
extras.add("scope_width", "slider", "Visuals", CON, "scope", "Scope thickness", 1, 12, 1, true, "px")
local hide_vm_tp = ui.new_checkbox(TAB, CON, "Hide viewmodel in thirdperson")
extras.header("Visuals", "Fake lag", "HUD / STATUS")
extras.add("velocity", "checkbox", "Visuals", "Fake lag", nil, "Momentum HUD")
extras.add("velocity_color", "color_picker", "Visuals", "Fake lag", "velocity", "Momentum accent", 255, 156, 156, 255)
extras.add("velocity_x", "slider", "Visuals", "Fake lag", "velocity", "Momentum horizontal", 5, 95, 50, true, "%")
extras.add("velocity_y", "slider", "Visuals", "Fake lag", "velocity", "Momentum vertical", 5, 95, 32, true, "%")
extras.add("velocity_scale", "slider", "Visuals", "Fake lag", "velocity", "Momentum size", 75, 150, 100, true, "%")
local indicator_sel = ui.new_combobox(TAB, "Fake lag", "Indicator", "Off", "Ünoins_qucy", "Half-life", "Ideal yaw", "Ünoins_qucy new")
local qucy_color = ui.new_color_picker(TAB, "Fake lag", "\nIndicator accent color", 168, 230, 163, 255)
extras.ui.qucy_color = qucy_color
extras.controls[#extras.controls+1] = {key="qucy_color", ref=qucy_color, kind="color_picker", page="Visuals", indicator="Ünoins_qucy new"}
extras.add("qucy_offset", "slider", "Visuals", "Fake lag", nil, "New indicator offset", 20, 180, 28, true, "px")
extras.controls[#extras.controls].indicator = "Ünoins_qucy new"
local ind_groupname = ui.new_checkbox(TAB, "Fake lag", "Indicator group name")
local dmg_indicator = ui.new_checkbox(TAB, "Fake lag", "Damage ind")
extras.header("Misc", CON, "COMBAT / MOVEMENT")
extras.add("onshot", "checkbox", "Misc", CON, nil, "\aFFF59DFFon shot sync\r")
extras.add("move_hitchance", "checkbox", "Misc", CON, nil, "Double tap release hitchance")
extras.add("move_hitchance_weapons", "multiselect", "Misc", CON, "move_hitchance", "Release weapons", "SSG 08", "SCAR-20", "G3SG1", "AWP", "Desert Eagle", "R8 Revolver")
extras.add("move_hitchance_value", "slider", "Misc", CON, "move_hitchance", "Release hit chance", 0, 100, 60, true, "%")
extras.add("noscope_hitchance", "checkbox", "Misc", CON, nil, "No scope hit chance")
extras.add("noscope_weapon", "combobox", "Misc", CON, "noscope_hitchance", "No scope weapon", "SSG 08", "SCAR-20", "G3SG1", "AWP", "AUG", "SG 553")
extras.noscope_profiles, extras.noscope_legacy = {}, {}
for _, weapon in ipairs({{40,"SSG 08","ssg08"},{38,"SCAR-20","scar20"},{11,"G3SG1","g3sg1"},{9,"AWP","awp"},{8,"AUG","aug"},{39,"SG 553","sg553"}}) do
    local key="noscope_"..weapon[3]
    local unscoped=extras.add(key, "slider", "Misc", CON, "noscope_hitchance", "No scope Hitchange\n"..key, -1, 100, -1, true, "", 1, {[-1]="Off",[0]="0"})
    local scoped=extras.add(key.."_scoped", "slider", "Misc", CON, "noscope_hitchance", "Hitchange\n"..key.."_scoped", -1, 100, -1, true, "", 1, {[-1]="Off",[0]="0"})
    extras.controls[#extras.controls-1].weapon, extras.controls[#extras.controls].weapon = weapon[2], weapon[2]
    extras.noscope_profiles[weapon[1]]={unscoped=unscoped, scoped=scoped}
    extras.noscope_legacy["extra_"..key], extras.noscope_legacy["extra_"..key.."_scoped"] = "extra_noscope_value", "extra_scoped_value"
end
ui.set(extras.ui.move_hitchance_weapons, {"SSG 08", "SCAR-20", "G3SG1", "AWP", "Desert Eagle", "R8 Revolver"})
extras.add("autostop", "checkbox", "Misc", CON, nil, "Ünoins_qucy quick stop")
extras.add("stop_mode", "combobox", "Misc", CON, "autostop", "Brake activation", "Visible target", "On attack")
extras.add("stop_fov", "slider", "Misc", CON, "autostop", "Brake field of view", 5, 90, 25, true, "°")
extras.add("stop_speed", "slider", "Misc", CON, "autostop", "Brake target speed", 5, 60, 20, true, "u/s")
extras.add("duck_fd", "checkbox", "Misc", CON, nil, "\aFFF59DFFFake duck Freedom\r")
local fast_ladder = ui.new_checkbox(TAB, CON, "Fast ladder")
local rh_enabled = ui.new_checkbox(TAB, CON, "\aD4B2D8FFResolver\r")
extras.header("Misc", "Other", "ANIMATION / POSE")
extras.add("anim", "checkbox", "Misc", "Other", nil, "\aFFF59DFFAnim breaker\r")
extras.add("anim_ground", "combobox", "Misc", "Other", "anim", "Ground pose", "Static", "Jitter", "Moonwalk", "Off")
extras.add("anim_air", "combobox", "Misc", "Other", "anim", "Air pose", "Static", "Cycle", "Off")
extras.add("anim_amount", "slider", "Misc", "Other", "anim", "Pose amount", 0, 100, 100, true, "%")
extras.add("anim_delay", "slider", "Misc", "Other", "anim", "Pose interval", 1, 8, 2, true, "t")
extras.add("anim_land", "checkbox", "Misc", "Other", "anim", "Level pitch on landing")
extras.header("Misc", "Fake lag", "UTILITY / COMMUNICATION")
extras.add("drop", "checkbox", "Misc", "Fake lag", nil, "Nade Relay")
extras.add("drop_key", "hotkey", "Misc", "Fake lag", "drop", "Nade Relay key", true)
extras.add("drop_types", "multiselect", "Misc", "Fake lag", "drop", "Relay grenades", "HE", "Smoke", "Fire", "Flash", "Decoy")
local clan_tag_sel = ui.new_combobox(TAB, "Fake lag", "Clan tag", "Off", "Half-life.beta", "Ünoins_qucy", "gamesense", "Ideal Yaw")
local hitlog_enabled = ui.new_checkbox(TAB, "Fake lag", "Hit log")
local auto_mute_all = ui.new_checkbox(TAB, "Fake lag", "\aFF8E8EFFAuto mute all players\r")
extras.header("Misc", "Fake lag", "PERFORMANCE / CONSOLE")
extras.add("fps", "checkbox", "Misc", "Fake lag", nil, "FPS+")
extras.add("fps_groups", "multiselect", "Misc", "Fake lag", "fps", "Reduce effects", "Blood", "Bloom", "Decals", "Shadows", "Ropes", "Debris", "Weapon effects")
extras.add("console", "checkbox", "Misc", "Fake lag", nil, "Clear Console")
ui.set(extras.ui.drop_types, {"HE", "Smoke", "Fire"})
ui.set(extras.ui.fps_groups, {"Bloom", "Ropes", "Debris"})

function extras.visible(vis_on, misc_on)
    for _, h in ipairs(extras.headers) do ui.set_visible(h.ref, h.page == "Visuals" and vis_on or h.page == "Misc" and misc_on) end
    for _, c in ipairs(extras.controls) do
        local show = c.page == "Visuals" and vis_on or c.page == "Misc" and misc_on
        ui.set_visible(c.ref, show and (not c.parent or ui.get(extras.ui[c.parent]))
            and (not c.weapon or ui.get(extras.ui.noscope_weapon)==c.weapon)
            and (not c.indicator or ui.get(indicator_sel)==c.indicator))
    end
end

local vm_cb, vm_color = safe_ref("Visuals", "Colored models", "Weapon viewmodel")
local tp_vm_active, tp_vm_saved_cb, tp_vm_saved_color = false, nil, nil

local function restore_tp_viewmodel()
    if tp_vm_saved_cb ~= nil and vm_cb then ui.set(vm_cb, tp_vm_saved_cb) end
    if tp_vm_saved_color and vm_color then
        ui.set(vm_color, tp_vm_saved_color[1], tp_vm_saved_color[2], tp_vm_saved_color[3], tp_vm_saved_color[4])
    end
    tp_vm_active, tp_vm_saved_cb, tp_vm_saved_color = false, nil, nil
end

local function in_thirdperson()
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return false end
    local cx, cy, cz = client.camera_position()
    local ex, ey, ez = client.eye_position()
    if not cx or not cy or not cz or not ex or not ey or not ez then return false end
    local dx, dy, dz = cx - ex, cy - ey, cz - ez
    return math.sqrt(dx * dx + dy * dy + dz * dz) > 5
end

local function update_tp_viewmodel()
    local active = ui.get(master) and ui.get(hide_vm_tp) and in_thirdperson()
    if active and not tp_vm_active then
        if vm_cb then
            tp_vm_saved_cb = ui.get(vm_cb)
            ui.set(vm_cb, true)
        end
        if vm_color then
            local r, g, b, a = ui.get(vm_color)
            tp_vm_saved_color = {r, g, b, a}
            ui.set(vm_color, r, g, b, 0)
        end
        tp_vm_active = true
    elseif not active and tp_vm_active then
        restore_tp_viewmodel()
    end
end

client.set_event_callback("paint", update_tp_viewmodel)
local hitlog_shots = {}
local communication = {key="unoins.pro.communication.v1", cvars={}, players={}, loaded=false, recovering=true}
function communication.read(name)
    local ok,value=checked_call("communication.read", function() return cvar[name]:get_string() end)
    return ok and value~=nil and tostring(value) or nil
end
function communication.write(name,value)
    local ok=checked_call("communication.write", function() cvar[name]:set_string(value) end)
    return ok and communication.read(name)==value
end
function communication.warn(reason)
    if communication.warned == reason then return end
    communication.warned = reason
    client.error_log("[Ünoins_qucy] Communication: " .. reason)
end
function communication.save()
    local ok=checked_call("communication.save", database.write,communication.key,{version=1,cvars=communication.cvars,players=communication.players})
    if not ok then communication.warn("backup save failed; new mute writes blocked") end
    return ok
end
function communication.load()
    if communication.loaded then return true end
    local ok,saved=checked_call("communication.load", database.read,communication.key)
    if not ok then communication.warn("backup read failed; auto mute blocked"); return false end
    if type(saved)=="table" and saved.version==1 then
        for _,name in ipairs({"cl_chatfilters","voice_enable"}) do
            local value=type(saved.cvars)=="table" and saved.cvars[name]
            if type(value)=="string" and value:match("^%d+$") then communication.cvars[name]=value end
        end
        if type(saved.players)=="table" then
            for xuid,owned in pairs(saved.players) do
                if owned==true and type(xuid)=="string" and xuid:match("^%d+$") and xuid~="0" then
                    communication.players[xuid]=true
                end
            end
        end
    end
    communication.loaded=true
    return true
end
function communication.bridge()
    communication.ready=false
    local me=entity.get_local_player()
    if not me or me<1 then communication.panorama=nil; return end
    if not communication.panorama then
        local ok,bridge=checked_call("communication.bridge", function()
            return panorama.loadstring([[
                return {
                    ready: function(me) {
                        if (!me || me < 1 || me > 64) return false;
                        var xuid = GameStateAPI.GetPlayerXuidStringFromEntIndex(me);
                        return !!xuid && xuid !== "0";
                    },
                    collect: function(me) {
                        var result = [];
                        for (var i = 1; i <= 64; i++) {
                            if (i === me) continue;
                            var xuid = GameStateAPI.GetPlayerXuidStringFromEntIndex(i);
                            if (xuid && xuid !== "0" && !GameStateAPI.IsSelectedPlayerMuted(xuid)) result.push(xuid);
                        }
                        return result.join(",");
                    },
                    set_muted: function(xuid, muted) {
                        if (GameStateAPI.IsSelectedPlayerMuted(xuid) !== muted) GameStateAPI.ToggleMute(xuid);
                        return GameStateAPI.IsSelectedPlayerMuted(xuid) === muted;
                    }
                };
            ]],"CSGOHud")()
        end)
        if ok then communication.panorama=bridge end
    end
    if not communication.panorama then return end
    local ok,ready=checked_call("communication.ready", function() return communication.panorama.ready(me) end)
    communication.ready=ok and ready==true
    if not ok then communication.panorama=nil end
    return communication.ready and communication.panorama or nil
end
local function restore_communication()
    if not communication.load() then return end
    local changed, pending = false, {}
    for name,value in pairs(communication.cvars) do
        local current=communication.read(name)
        if current and (current~="0" or communication.write(name,value)) then
            communication.cvars[name]=nil
            changed=true
        else pending[#pending+1] = name .. " expected=" .. value .. " read=" .. tostring(current) end
    end
    if next(communication.players) then
        local bridge=communication.bridge()
        if bridge then
            for xuid in pairs(communication.players) do
                local ok,restored=checked_call("restore_communication", function() return bridge.set_muted(xuid,false) end)
                if ok and restored==true then communication.players[xuid]=nil; changed=true
                elseif not ok then communication.panorama=nil end
            end
        end
    end
    if changed then communication.unsaved=true end
    if communication.unsaved and communication.save() then communication.unsaved=nil end
    communication.recovering=next(communication.cvars)~=nil or next(communication.players)~=nil or communication.unsaved==true
    if communication.recovering then
        local players = 0
        for _ in pairs(communication.players) do players = players + 1 end
        if players > 0 and communication.ready then pending[#pending+1] = "player unmutes unconfirmed=" .. players end
        if communication.unsaved then pending[#pending+1] = "backup save pending" end
        table.sort(pending)
        if #pending>0 then communication.warn("restore pending: " .. table.concat(pending, "; ") .. "; recovery records retained")
        else communication.warned=nil end
    else communication.warned=nil end
end
local function block_communication()
    if not communication.load() then return end
    if communication.recovering then
        restore_communication()
        if communication.recovering then return end
    end
    local bridge=communication.bridge()
    if not bridge then return end
    local values={}
    for _,name in ipairs({"cl_chatfilters","voice_enable"}) do
        local value=communication.read(name)
        if not value or not value:match("^%d+$") then
            communication.warn("auto mute blocked: unreadable numeric " .. name .. " (" .. tostring(value) .. ")")
            return
        end
        values[name]=value
    end
    local dirty=false
    for name,value in pairs(values) do
        if communication.cvars[name]==nil or value~="0" and communication.cvars[name]~=value then
            communication.cvars[name]=value
            dirty=true
        end
    end
    if bridge then
        local ok,players=checked_call("block_communication", function() return bridge.collect(entity.get_local_player() or 0) end)
        if ok and type(players)=="string" then
            for xuid in players:gmatch("%d+") do
                if xuid~="0" and not communication.players[xuid] then communication.players[xuid]=true; dirty=true end
            end
        elseif not ok then communication.panorama=nil end
    end
    if dirty then communication.unsaved=true end
    if communication.unsaved then
        if not communication.save() then return end
        communication.unsaved=nil
    end
    for name,value in pairs(values) do
        if value~="0" and not communication.write(name,"0") then
            communication.warn("auto mute write unconfirmed: " .. name .. " expected=0 read=" .. tostring(communication.read(name)))
        end
    end
    if bridge then
        for xuid in pairs(communication.players) do
            local ok,muted=checked_call("block_communication", function() return bridge.set_muted(xuid,true) end)
            if not ok or muted~=true then communication.warn("auto mute player state unconfirmed; retry pending") end
            if not ok then communication.panorama=nil end
        end
    end
end
local function sync_communication_state()
    if extras.config_loading then return end
    if ui.get(master) and ui.get(auto_mute_all) then block_communication() else restore_communication() end
end
client.set_event_callback("shutdown",restore_communication)
client.set_event_callback("round_start",sync_communication_state)
client.set_event_callback("post_config_load",sync_communication_state)
client.set_event_callback("post_config_load",function() native_snapshot = nil end)
client.set_event_callback("paint_ui",function()
    local now=globals.realtime()
    if not communication.time or now<communication.time or now-communication.time>=0.5 then
        communication.time=now
        sync_communication_state()
    end
end)
restore_communication()

local function hl_R(t, c, n)
    local r1, r2, r3 = safe_ref(t, c, n)
    if r1 then return { r1, r2, r3 } end
end

local function hl_F(...)
    for i = 1, select("#", ...), 3 do local r = hl_R(select(i, ...), select(i+1, ...), select(i+2, ...)); if r then return r end end
end
local hl_ref = {}
hl_ref.dt = hl_F("RAGE", "Aimbot", "Double tap", "RAGE", "Other", "Double tap", "RAGE", "Aimbot", "Double Tap")
hl_ref.baim = hl_F("RAGE", "Aimbot", "Force body aim", "RAGE", "Other", "Force body aim")
hl_ref.md = hl_F("RAGE", "Aimbot", "Minimum damage override", "RAGE", "Other", "Minimum damage override")
hl_ref.os = hl_F("AA", "Other", "On shot anti-aim", "AA", "Anti-aimbot angles", "On shot anti-aim", "AA", "Other", "On Shot Anti-aim")
hl_ref.mindmg = hl_F("RAGE", "Aimbot", "Minimum damage", "RAGE", "Other", "Minimum damage")

local function hl_active(r)
    if not r or not r[1] then return false end
    local ok, enabled = checked_call("hl_active", ui.get, r[1])
    if not ok or enabled ~= true then return false end
    if not r[2] then return true end
    local key_ok, active = checked_call("hl_active", ui.get, r[2])
    return key_ok and active == true
end

local cfg = {}
for _, cond in ipairs(conditions) do
    cfg[cond] = {
        enabled = cond ~= "Global" and ui.new_checkbox(TAB, CON, "[" .. cond .. "] Enable") or nil,
        yaw_base = ui.new_combobox(TAB, CON, "[" .. cond .. "] Yaw base", "Local view", "At targets"),
        yaw_add = ui.new_slider(TAB, CON, "\n" .. cond .. " yaw", -180, 180, 0, true, "°"),
        yaw_left_right = ui.new_checkbox(TAB, CON, "[" .. cond .. "] Yaw L/R"),
        left = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw left", -180, 180, 0, true, "°"),
        left_randomization = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw left rand", 0, 100, 0, true, "°"),
        right = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw right", -180, 180, 0, true, "°"),
        right_randomization = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw right rand", 0, 100, 0, true, "°"),
        yaw_jitter = ui.new_combobox(TAB, CON, "[" .. cond .. "] Yaw jitter", "Off", "\aFFF59DFFCenter\r", "Slow", "\aFFF59DFFSlow Pro\r"),
        yaw_jit_add = ui.new_slider(TAB, CON, "\n" .. cond .. " jitter", -180, 180, 30, true, "°"),
        slow_pro_degree = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro degree", 0, 15, 3, true, "°"),
        slow_pro_random = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro randomly", 0, 10, 0, true, "°"),
        slow_pro_speed = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro delay", 0, 6, 0, true, "t", 1, {[0]="Fast"}),
        slow_pro_mode = ui.new_combobox(TAB, CON, "[" .. cond .. "] Slow Pro mode", "Default", "Randomize", "Cycle lift", "X-way"),
        slow_pro_min = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro lift min", 0, 5, 0, true, "t"),
        slow_pro_max = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro lift max", 1, 6, 1, true, "t"),
        slow_pro_interval = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro lift interval", 1, 30, 1, true, "t"),
        body_yaw = ui.new_combobox(TAB, CON, "[" .. cond .. "] Body yaw", "Off", "Opposite", "\aFFF59DFFJitter Pro\r", "\aFFF59DFFStatic Pro\r"),
        body_side = ui.new_combobox(TAB, CON, "[" .. cond .. "] Body side", "+", "-"),
        body_delay = ui.new_slider(TAB, CON, "[" .. cond .. "] Body delay", 1, 17, 1, true, "t", 1, {[1]="OFF"}),
        force_def = ui.new_checkbox(TAB, "Other", "\aFFF59DFF[" .. cond .. "] Force break lc\r"),
        force_break = ui.new_checkbox(TAB, "Other", "\n\aFFF59DFF" .. cond .. " force break lc\r"),
        height_based_pitch = ui.new_checkbox(TAB, "Other", "\aFFF59DFF[" .. cond .. "] Height-based pitch\r"),
        def_mode = ui.new_combobox(TAB, "Other", "[" .. cond .. "] Defensive mode", "Always", "On peek"),
        def_trigger = ui.new_checkbox(TAB, "Other", "\aFFF59DFF[" .. cond .. "] Defensive trigger\r"),
        def_duration = ui.new_slider(TAB, "Other", "\n" .. cond .. " defensive duration", 1, 14, 14, true, "t"),
        def_pitch = ui.new_combobox(TAB, "Other", "[" .. cond .. "] Defensive pitch", "Off", "Up", "Zero", "Down", "Custom", "Jitter", "Spin", "Auto Spin", "Random", "4Way", "5Way"),
        def_pitch_val = ui.new_slider(TAB, "Other", "\n" .. cond .. " def pitch val", -89, 89, 0, true, "°"),
        def_pitch_j1 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Pitch jitter 1", -89, 89, -89, true, "°"),
        def_pitch_j2 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Pitch jitter 2", -89, 89, 89, true, "°"),
        def_pitch_jdelay = ui.new_slider(TAB, "Other", "[" .. cond .. "] Pitch jitter delay", 1, 14, 1, true, "t"),
        def_pitch_s1 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Pitch spin 1", -89, 89, -89, true, "°"),
        def_pitch_s2 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Pitch spin 2", -89, 89, 89, true, "°"),
        def_pitch_speed = ui.new_slider(TAB, "Other", "[" .. cond .. "] Pitch spin speed", 1, 200, 20, true),
        def_pitch_r1 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Pitch rand min", -89, 89, -89, true, "°"),
        def_pitch_r2 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Pitch rand max", -89, 89, 89, true, "°"),
        def_yaw = ui.new_combobox(TAB, "Other", "[" .. cond .. "] Defensive yaw", "Off", "Custom", "Jitter", "Spin", "Auto Spin", "Random", "Opposite", "4Way", "Custom Way"),
        def_yaw_val = ui.new_slider(TAB, "Other", "\n" .. cond .. " def yaw val", -180, 180, 0, true, "°"),
        def_yaw_j1 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Yaw jitter 1", -180, 180, -90, true, "°"),
        def_yaw_j2 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Yaw jitter 2", -180, 180, 90, true, "°"),
        def_yaw_jdelay = ui.new_slider(TAB, "Other", "[" .. cond .. "] Yaw jitter delay", 1, 14, 1, true, "t"),
        def_yaw_s1 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Yaw spin 1", -180, 180, -180, true, "°"),
        def_yaw_s2 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Yaw spin 2", -180, 180, 180, true, "°"),
        def_yaw_speed = ui.new_slider(TAB, "Other", "[" .. cond .. "] Yaw spin speed", 1, 200, 20, true),
        def_yaw_r1 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Yaw rand min", -180, 180, -180, true, "°"),
        def_yaw_r2 = ui.new_slider(TAB, "Other", "[" .. cond .. "] Yaw rand max", -180, 180, 180, true, "°"),
        def_yaw_way_count = ui.new_slider(TAB, "Other", "[" .. cond .. "] Custom way count", 1, 10, 4, true),
        def_yaw_ways = {
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 1 angle", -180, 180, 0, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 2 angle", -180, 180, 90, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 3 angle", -180, 180, 180, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 4 angle", -180, 180, -90, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 5 angle", -180, 180, 0, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 6 angle", -180, 180, 45, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 7 angle", -180, 180, 90, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 8 angle", -180, 180, 135, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 9 angle", -180, 180, 180, true, "°"),
            ui.new_slider(TAB, "Other", "[" .. cond .. "] Way 10 angle", -180, 180, -135, true, "°"),
        },
        def_body_yaw = ui.new_combobox(TAB, "Other", "[" .. cond .. "] Defensive body yaw", "Inherit", "Off", "Opposite", "Jitter Pro", "Static Pro"),
        def_body_side = ui.new_combobox(TAB, "Other", "[" .. cond .. "] Defensive body side", "+", "-"),
        def_body_delay = ui.new_slider(TAB, "Other", "[" .. cond .. "] Defensive body delay", 1, 17, 1, true, "t"),
        fakelag = ui.new_combobox(TAB, CON, "[" .. cond .. "] Fake lag", "Off", "Always on", "\aFFF59DFFAdaptive\r"),
    }
end
local all_config_items = {}

local function reg_item(key, ref)
    if ref then all_config_items[#all_config_items + 1] = { key = key, ref = ref } end
end
reg_item("defensive_backend", defensive_backend)
reg_item("safe_head_weapons", safe_head_weapons)
reg_item("freestanding_states", fs_states)
reg_item("freestanding_options", fs_options)
reg_item("anti_backstab", anti_backstab)
reg_item("fl_ground_mode", fl_ground_mode)
reg_item("hide_vm_tp", hide_vm_tp)
reg_item("indicator_sel", indicator_sel)
reg_item("ind_groupname", ind_groupname)
reg_item("dmg_indicator", dmg_indicator)
reg_item("clan_tag_sel", clan_tag_sel)
reg_item("rh_enabled", rh_enabled)
reg_item("hitlog_enabled", hitlog_enabled)
reg_item("fast_ladder", fast_ladder)
reg_item("auto_mute_all", auto_mute_all)
for _, item in ipairs(extras.controls) do
    reg_item("extra_"..item.key, item.ref)
    all_config_items[#all_config_items].kind = item.kind
end
for _, cond in ipairs(conditions) do
    local c = cfg[cond]
    if c.enabled then reg_item(cond .. "_enabled", c.enabled) end
    reg_item(cond .. "_yaw_base", c.yaw_base)
    reg_item(cond .. "_yaw_add", c.yaw_add)
    reg_item(cond .. "_yaw_left_right", c.yaw_left_right)
    reg_item(cond .. "_left", c.left)
    reg_item(cond .. "_left_rand", c.left_randomization)
    reg_item(cond .. "_right", c.right)
    reg_item(cond .. "_right_rand", c.right_randomization)
    reg_item(cond .. "_yaw_jitter", c.yaw_jitter)
    reg_item(cond .. "_yaw_jit_add", c.yaw_jit_add)
    reg_item(cond .. "_slow_pro_degree", c.slow_pro_degree)
    reg_item(cond .. "_slow_pro_random", c.slow_pro_random)
    reg_item(cond .. "_slow_pro_speed", c.slow_pro_speed)
    reg_item(cond .. "_slow_pro_mode", c.slow_pro_mode)
    reg_item(cond .. "_slow_pro_min", c.slow_pro_min)
    reg_item(cond .. "_slow_pro_max", c.slow_pro_max)
    reg_item(cond .. "_slow_pro_interval", c.slow_pro_interval)
    reg_item(cond .. "_body_yaw", c.body_yaw)
    reg_item(cond .. "_body_side", c.body_side)
    reg_item(cond .. "_body_delay", c.body_delay)
    reg_item(cond .. "_force_def", c.force_def)
    reg_item(cond .. "_force_break", c.force_break)
    reg_item(cond .. "_height_based_pitch", c.height_based_pitch)
    reg_item(cond .. "_def_mode", c.def_mode)
    reg_item(cond .. "_def_trigger", c.def_trigger)
    reg_item(cond .. "_def_duration", c.def_duration)
    reg_item(cond .. "_def_pitch", c.def_pitch)
    reg_item(cond .. "_def_pitch_val", c.def_pitch_val)
    reg_item(cond .. "_def_pitch_j1", c.def_pitch_j1)
    reg_item(cond .. "_def_pitch_j2", c.def_pitch_j2)
    reg_item(cond .. "_def_pitch_jdelay", c.def_pitch_jdelay)
    reg_item(cond .. "_def_pitch_s1", c.def_pitch_s1)
    reg_item(cond .. "_def_pitch_s2", c.def_pitch_s2)
    reg_item(cond .. "_def_pitch_speed", c.def_pitch_speed)
    reg_item(cond .. "_def_pitch_r1", c.def_pitch_r1)
    reg_item(cond .. "_def_pitch_r2", c.def_pitch_r2)
    reg_item(cond .. "_def_yaw", c.def_yaw)
    reg_item(cond .. "_def_yaw_val", c.def_yaw_val)
    reg_item(cond .. "_def_yaw_j1", c.def_yaw_j1)
    reg_item(cond .. "_def_yaw_j2", c.def_yaw_j2)
    reg_item(cond .. "_def_yaw_jdelay", c.def_yaw_jdelay)
    reg_item(cond .. "_def_yaw_s1", c.def_yaw_s1)
    reg_item(cond .. "_def_yaw_s2", c.def_yaw_s2)
    reg_item(cond .. "_def_yaw_speed", c.def_yaw_speed)
    reg_item(cond .. "_def_yaw_r1", c.def_yaw_r1)
    reg_item(cond .. "_def_yaw_r2", c.def_yaw_r2)
    reg_item(cond .. "_def_yaw_way_count", c.def_yaw_way_count)
    for i = 1, 10 do
        reg_item(cond .. "_def_yaw_way_" .. i, c.def_yaw_ways[i])
    end
    reg_item(cond .. "_def_body_yaw", c.def_body_yaw)
    reg_item(cond .. "_def_body_side", c.def_body_side)
    reg_item(cond .. "_def_body_delay", c.def_body_delay)
    reg_item(cond .. "_fakelag", c.fakelag)
end
local b64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64_bytes, b64_values = {}, {}
for i = 1, #b64_chars do
    local byte = b64_chars:byte(i)
    b64_bytes[i-1], b64_values[byte] = byte, i-1
end

local function b64_encode(data)
    local result = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i+2)
        local word = bit.lshift(a, 16) + bit.lshift(b or 0, 8) + (c or 0)
        result[#result+1] = string.char(
            b64_bytes[bit.rshift(word, 18)], b64_bytes[bit.band(bit.rshift(word, 12), 63)],
            b and b64_bytes[bit.band(bit.rshift(word, 6), 63)] or 61,
            c and b64_bytes[bit.band(word, 63)] or 61)
    end
    return table.concat(result)
end

local function b64_decode(data)
    local result, buffer, bits = {}, 0, 0
    for i = 1, #data do
        local value = b64_values[data:byte(i)]
        if value then
            buffer, bits = bit.lshift(buffer, 6) + value, bits + 6
            if bits >= 8 then
                bits = bits - 8
                result[#result+1] = string.char(bit.band(bit.rshift(buffer, bits), 255))
                buffer = bit.band(buffer, bit.lshift(1, bits)-1)
            end
        end
    end
    return table.concat(result)
end

local function xor_bytes(data)
    local result = {}
    for i = 1, #data do result[i] = string.char(bit.bxor(data:byte(i), 0x5D)) end
    return table.concat(result)
end

local config_codec = {limit=1048576, prefix="Ünoins_qucy~"}

function config_codec.u32(value)
    return string.char(bit.band(value,255),bit.band(bit.rshift(value,8),255),
        bit.band(bit.rshift(value,16),255),bit.rshift(value,24))
end

function config_codec.read_u32(data, offset)
    local a,b,c,d=data:byte(offset,offset+3)
    return a+b*256+c*65536+d*16777216
end

function config_codec.checksum(data)
    local a,b=1,0
    for i=1,#data do a=(a+data:byte(i))%65521; b=(b+a)%65521 end
    return b*65536+a
end

function config_codec.compress(data)
    local output,heads,previous={}, {}, {}
    local size,pos,literal,work=#data,1,1,0
    local function insert(index)
        if index+2>size then return end
        local key=data:sub(index,index+2)
        previous[index],heads[key]=heads[key],index
    end
    local function flush(finish)
        while literal<=finish do
            local count=math.min(128,finish-literal+1)
            output[#output+1]=string.char(count-1)..data:sub(literal,literal+count-1)
            literal=literal+count
        end
    end
    while pos<=size do
        local candidate=pos+2<=size and heads[data:sub(pos,pos+2)]
        local length,distance,tries=0,0,0
        local maximum=math.min(130,size-pos+1)
        while candidate and pos-candidate<=65535 and tries<32 do
            local matched=3
            while matched<maximum and data:byte(candidate+matched)==data:byte(pos+matched) do
                matched,work=matched+1,work+1
                if work>size*32 then return nil end
            end
            if matched>length then length,distance=matched,pos-candidate end
            if length==maximum then break end
            candidate,tries=previous[candidate],tries+1
        end
        if length>=4 then
            flush(pos-1)
            output[#output+1]=string.char(128+length-3,bit.band(distance,255),bit.rshift(distance,8))
            for i=pos,pos+length-1 do insert(i) end
            pos=pos+length; literal=pos
        else
            insert(pos); pos=pos+1
            if pos-literal==128 then flush(pos-1) end
        end
    end
    flush(size)
    return table.concat(output)
end

function config_codec.decompress(data, size)
    local output,pos,count={},1,0
    while pos<=#data do
        local control=data:byte(pos); pos=pos+1
        if control<128 then
            local length=control+1
            if pos+length-1>#data or count+length>size then return nil end
            for i=pos,pos+length-1 do count=count+1; output[count]=data:sub(i,i) end
            pos=pos+length
        else
            if pos+1>#data then return nil end
            local length=control-128+3
            local distance=data:byte(pos)+data:byte(pos+1)*256
            if distance<1 or distance>count or count+length>size then return nil end
            for _=1,length do count=count+1; output[count]=output[count-distance] end
            pos=pos+2
        end
    end
    if count~=size then return nil end
    return table.concat(output)
end

local function obfuscate(str)
    assert(type(str)=="string" and #str<=config_codec.limit,"config: serialized data exceeds 1 MiB or is invalid")
    local packed=#str>=32 and config_codec.compress(str)
    local compressed=packed and #packed<#str
    local size=#str+(compressed and 0 or 2147483648)
    return config_codec.prefix..b64_encode(config_codec.u32(size)..config_codec.u32(config_codec.checksum(str))..(compressed and packed or str))
end

local function deobfuscate(str)
    if type(str)~="string" or #str>config_codec.limit*2 then return nil,"invalid or oversized config" end
    local branded=str:sub(1,#config_codec.prefix)==config_codec.prefix
    if branded or str:sub(1,8)=="UNOINS2~" then
        local encoded=str:sub((branded and #config_codec.prefix or 8)+1):gsub("%s","")
        if #encoded%4~=0 or encoded:find("[^A-Za-z0-9+/=]") then return nil,"invalid Base64" end
        local raw=b64_decode(encoded)
        if #raw<8 or b64_encode(raw)~=encoded then return nil,"invalid Base64 or header" end
        local size=config_codec.read_u32(raw,1)
        local plain=branded and size>=2147483648
        if plain then size=size-2147483648 end
        if size>config_codec.limit or size==0 and not plain then return nil,"invalid decompressed size" end
        local data
        if plain then data=raw:sub(9) else data=config_codec.decompress(raw:sub(9),size) end
        if not data or #data~=size then return nil,"invalid compressed data" end
        if config_codec.checksum(data)~=config_codec.read_u32(raw,5) then return nil,"config checksum mismatch" end
        if data=="" then return nil,"empty config" end
        return data
    end
    if str:match("^UNOINS%d+~") then return nil,"unsupported config version" end
    if str:sub(1,7)~="UNOINS~" then return nil end
    local raw=b64_decode(str:sub(8))
    return raw~="" and xor_bytes(raw) or nil
end

local function serialize_data(tbl)
    if json_ok and json and json.stringify then
        local ok, str = checked_call("serialize_data", json.stringify, tbl)
        if ok and str then return str end
    end
    local function escape(value)
        return (tostring(value):gsub("[^%w _%-]", function(c) return string.format("%%%02X", c:byte()) end))
    end
    local function scalar(value)
        if type(value) == "boolean" then return value and "b1" or "b0" end
        if type(value) == "number" then return "n"..tostring(value) end
        return "s"..escape(value)
    end
    local parts = {}
    for k, v in pairs(tbl) do
        local value
        if type(v) == "table" then
            local sub = {}
            for _, sv in ipairs(v) do sub[#sub+1] = scalar(sv) end
            value = "a"..table.concat(sub, ",")
        else value = scalar(v) end
        parts[#parts+1] = escape(k).."="..value
    end
    table.sort(parts)
    return "UCFG2\n"..table.concat(parts, ";")
end

local function deserialize_data(str)
    if not str or str == "" then return nil end
    if json_ok and json and json.parse and (str:sub(1,1) == "{" or str:sub(1,1) == "[") then
        local ok, tbl = checked_call("deserialize_data", json.parse, str)
        if ok and type(tbl) == "table" then return tbl end
    end
    if str:sub(1,6) == "UCFG2\n" then
        local function unescape(value)
            return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex,16)) end))
        end
        local function scalar(value)
            local kind, raw = value:sub(1,1), value:sub(2)
            if kind == "s" then return unescape(raw) end
            if kind == "n" then return tonumber(raw) end
            if value == "b1" then return true end
            if value == "b0" then return false end
        end
        local tbl = {}
        for entry in str:sub(7):gmatch("[^;]+") do
            local key, value = entry:match("^([^=]+)=(.*)$")
            if not key then return nil end
            local decoded
            if value:sub(1,1) == "a" then
                decoded = {}
                for item in value:sub(2):gmatch("[^,]+") do
                    local v = scalar(item)
                    if v == nil then return nil end
                    decoded[#decoded+1] = v
                end
            else decoded = scalar(value) end
            if decoded == nil then return nil end
            tbl[unescape(key)] = decoded
        end
        return tbl
    end
    local tbl = {}
    for entry in str:gmatch("([^;]+)") do
        local k, v = entry:match("^([^=]+)=(.*)$")
        if k and v then
            if v == "true" then tbl[k] = true
            elseif v == "false" then tbl[k] = false
            elseif tonumber(v) then tbl[k] = tonumber(v)
            else tbl[k] = v end
        else
            local kc, vc = entry:match("^([^:]+):(.*)$")
            if kc and vc then
                local sub = {}
                for item in vc:gmatch("([^,]+)") do
                    sub[#sub+1] = tonumber(item) or item
                end
                tbl[kc] = sub
            end
        end
    end
    return next(tbl) and tbl or nil
end

local function dump_config_table()
    local data = {}
    for _, item in ipairs(all_config_items) do
        if item.ref then
            if item.kind == "color_picker" then data[item.key] = {ui.get(item.ref)}
            elseif item.kind == "hotkey" then
                local _, mode, key = ui.get(item.ref)
                data[item.key] = {mode or 1, key or 0}
            else data[item.key] = ui.get(item.ref) end
        end
    end
    return data
end
local master_cleanup

local legacy_labels = {
    indicator_sel = {["Unoins"]="Ünoins_qucy", ["Ünoins"]="Ünoins_qucy", ["Unoins.qucy new"]="Ünoins_qucy new"},
    clan_tag_sel = {["Unoins.qucy"]="Ünoins_qucy", ["Ünoins.qucy"]="Ünoins_qucy"}
}

local function load_config_table(data)
    local result = {matched=0, applied=0, failed=0}
    if type(data) ~= "table" then return result end
    extras.config_loading = true
    for _, item in ipairs(all_config_items) do
        local val = data[item.key]
        if val == nil and extras.noscope_legacy[item.key] then val = data[extras.noscope_legacy[item.key]] end
        if val == nil then
            local legacy_key = item.key:gsub("^Freestanding_", "Freestand_")
            if legacy_key ~= item.key then val = data[legacy_key] end
        end
        if val ~= nil and item.ref then
            result.matched = result.matched + 1
            if legacy_labels[item.key] then val = legacy_labels[item.key][val] or val end
            if item.key == "defensive_backend" and type(val) == "string" then
                if val:find("noins.-Pro") then val = "\aFF9C9CFFÜnoins_qucy Pro\r"
                elseif val:find("noins") then val = "\aFFF59DFFÜnoins_qucy\r"
                elseif val:find("Gamesense", 1, true) then val = "\a87B313FFGamesense\r" end
            end
            if item.kind == "hotkey" and type(val) == "table" then
                local modes = {"Always on", "On hotkey", "Toggle", "Off hotkey"}
                local mode = modes[(tonumber(val[1]) or 1) + 1]
                val = mode and {mode, tonumber(val[2]) or 0} or nil
            end
            if val ~= nil then
                local spread = type(val) == "table" and (item.kind == "color_picker" or item.kind == "hotkey")
                local ok = checked_call("config field " .. item.key, function()
                    if spread then ui.set(item.ref, unpack(val)) else ui.set(item.ref, val) end
                end)
                if ok then result.applied=result.applied+1 else result.failed=result.failed+1 end
            else
                result.failed=result.failed+1
                client.error_log("[Ünoins_qucy] Invalid config field: " .. item.key)
            end
        end
    end
    extras.config_loading = nil
    if result.matched > 0 then
        invalidate_freestand_controller()
        sync_communication_state()
        extras.sync()
        if extras.scope_control then extras.scope_control() end
        if update_vis then update_vis() end
    end
    return result
end

local function report_config_load(data, action)
    local result = load_config_table(data)
    if result.matched == 0 then
        client.log("config " .. action .. " failed: no recognized settings")
    elseif result.failed > 0 then
        client.log(string.format("config %s partial: %d applied, %d failed; see errors above", action, result.applied, result.failed))
    else
        client.log(action == "import" and "config imported" or "config loaded")
    end
end

local function refresh_config_listbox()
    active_config_names = get_saved_config_names()
    ui.update(cfg_listbox, active_config_names)
end
refresh_config_listbox()
ui.set_callback(cfg_listbox, function()
    local sel = ui.get(cfg_listbox)
    if sel and active_config_names[sel + 1] and active_config_names[sel + 1] ~= "-" then
        ui.set(cfg_name_box, active_config_names[sel + 1])
    end
end)
ui.set_callback(cfg_save_btn, function()
    local name = ui.get(cfg_name_box)
    if not name or name == "" then
        local sel_idx = ui.get(cfg_listbox) or 0
        name = active_config_names[sel_idx + 1] or "default"
    end
    name = name:gsub("[%c%s]+$", ""):gsub("^[%c%s]+", "")
    if name == "" or name == "-" then name = "default" end
    local found = false
    for _, n in ipairs(active_config_names) do
        if n == name then found = true; break end
    end
    if not found then
        active_config_names[#active_config_names + 1] = name
        save_config_names_list(active_config_names)
    end
    local data = dump_config_table()
    local serialized = serialize_data(data)
    local obfuscated = obfuscate(serialized)
    database.write("unoins_cfg_" .. name, obfuscated)
    refresh_config_listbox()
    client.log("config saved")
end)
ui.set_callback(cfg_load_btn, function()
    local sel_idx = ui.get(cfg_listbox) or 0
    local name = active_config_names[sel_idx + 1]
    if not name or name == "-" then return end
    local raw = database.read("unoins_cfg_" .. name)
    if raw then
        local deob, err = deobfuscate(raw)
        if err then client.log("config load failed: " .. err); return end
        local data = deserialize_data(deob or raw)
        if data then
            report_config_load(data, "load")
        else
            client.log("config load failed: invalid data")
        end
    end
end)
ui.set_callback(cfg_delete_btn, function()
    local sel_idx = ui.get(cfg_listbox) or 0
    local name = active_config_names[sel_idx + 1]
    if not name or name == "-" then return end
    local new_list = {}
    for _, n in ipairs(active_config_names) do
        if n ~= name then new_list[#new_list + 1] = n end
    end
    if #new_list == 0 then new_list = { "default" } end
    active_config_names = new_list
    save_config_names_list(active_config_names)
    database.write("unoins_cfg_" .. name, nil)
    refresh_config_listbox()
    client.log("config deleted")
end)
ui.set_callback(cfg_export_btn, function()
    local data = dump_config_table()
    local serialized = serialize_data(data)
    local obfuscated = obfuscate(serialized)
    local ok, result = checked_call("config export", clipboard.set, obfuscated)
    if not ok or result == false then client.log("config export failed: clipboard unavailable"); return end
    client.log("config exported")
end)
ui.set_callback(cfg_import_btn, function()
    local ok, raw = checked_call("config import", clipboard.get)
    if not ok then client.log("config import failed: clipboard unavailable"); return end
    if raw and raw ~= "" then
        local deob, err = deobfuscate(raw)
        if err then client.log("config import failed: " .. err); return end
        local data = deserialize_data(deob or raw)
        if data then
            report_config_load(data, "import")
        else
            client.log("config import failed")
        end
    end
end)

local function has_trigger(trigger_ref, name)
    if not trigger_ref then return false end
    local vals = ui.get(trigger_ref)
    if type(vals) == "table" then
        for _, v in ipairs(vals) do
            if v == name then return true end
        end
        return false
    elseif type(vals) == "string" then
        return vals == name
    end
    return false
end
update_vis = function()
    local master_on = ui.get(master)
    local page = tostring(ui.get(page_sel) or "")
    if master_on then native_visible(false) else native_visible(true) end
    local function match_page(target)
        return page == target or string.find(page, target, 1, true) ~= nil
    end
    local home_on = master_on and match_page("Home")
    local aa_on = master_on and (match_page("Anti-Aim") or match_page("Anti") or match_page("AA"))
    local misc_on = master_on and match_page("Misc")
    local vis_on = master_on and match_page("Visuals")
    ui.set_visible(page_sel, master_on)
    ui.set_visible(cfg_listbox, home_on)
    ui.set_visible(cfg_name_box, home_on)
    ui.set_visible(cfg_load_btn, home_on)
    ui.set_visible(cfg_save_btn, home_on)
    ui.set_visible(cfg_delete_btn, home_on)
    ui.set_visible(cfg_import_btn, home_on)
    ui.set_visible(cfg_export_btn, home_on)
    ui.set_visible(defensive_backend, aa_on)
    local pro_visible = aa_on and tostring(ui.get(defensive_backend)):find("Ünoins_qucy Pro", 1, true) ~= nil
    ui.set_visible(safe_head_weapons, aa_on)
    ui.set_visible(manual_left, aa_on)
    ui.set_visible(manual_right, aa_on)
    ui.set_visible(manual_fwd, aa_on)
    ui.set_visible(fs_hotkey, aa_on)
    ui.set_visible(fs_states, aa_on)
    ui.set_visible(fs_options, aa_on)
    ui.set_visible(edge_hotkey, aa_on)
    ui.set_visible(anti_backstab, aa_on)
    ui.set_visible(fl_ground_mode, aa_on)
    ui.set_visible(condition_sel, aa_on)
    ui.set_visible(hide_vm_tp, vis_on)
    local show_unoins = vis_on and has_trigger(indicator_sel, "Ünoins_qucy")
    ui.set_visible(indicator_sel, vis_on)
    ui.set_visible(qucy_color, vis_on and ui.get(indicator_sel) == "Ünoins_qucy new")
    ui.set_visible(ind_groupname, show_unoins)
    ui.set_visible(dmg_indicator, vis_on)
    ui.set_visible(clan_tag_sel, misc_on)
    ui.set_visible(rh_enabled, misc_on)
    ui.set_visible(hitlog_enabled, misc_on)
    ui.set_visible(fast_ladder, misc_on)
    ui.set_visible(auto_mute_all, misc_on)
    extras.visible(vis_on, misc_on)
    local sel = ui.get(condition_sel)
    for _, cond in ipairs(conditions) do
        local c, vis = cfg[cond], aa_on and (cond == sel)
        if c.enabled then ui.set_visible(c.enabled, vis) end
        local lr_on = vis and ui.get(c.yaw_left_right)
        ui.set_visible(c.yaw_base, vis)
        ui.set_visible(c.yaw_add, vis)
        ui.set_visible(c.yaw_left_right, vis)
        ui.set_visible(c.left, lr_on); ui.set_visible(c.left_randomization, lr_on)
        ui.set_visible(c.right, lr_on); ui.set_visible(c.right_randomization, lr_on)
        local jit_val = tostring(ui.get(c.yaw_jitter) or "")
        local jit_on = vis and jit_val ~= "Off" and jit_val ~= ""
        ui.set_visible(c.yaw_jitter, vis)
        ui.set_visible(c.yaw_jit_add, jit_on)
        local pro_on = vis and jit_val == "\aFFF59DFFSlow Pro\r"
        local lift_on = pro_on and ui.get(c.slow_pro_mode) == "Cycle lift"
        ui.set_visible(c.slow_pro_degree, pro_on)
        ui.set_visible(c.slow_pro_random, pro_on)
        ui.set_visible(c.slow_pro_speed, pro_on and not lift_on)
        ui.set_visible(c.slow_pro_mode, pro_on)
        ui.set_visible(c.slow_pro_min, lift_on)
        ui.set_visible(c.slow_pro_max, lift_on)
        ui.set_visible(c.slow_pro_interval, lift_on)
        local body_val = tostring(ui.get(c.body_yaw) or "")
        local body_on = vis and body_val ~= "Off" and body_val ~= ""
        local bj_on = body_on and string.find(body_val, "Opposite", 1, true) == nil
        ui.set_visible(c.body_yaw, vis)
        ui.set_visible(c.body_side, bj_on)
        ui.set_visible(c.body_delay, bj_on)
        local def_on = vis and ui.get(c.force_def)
        ui.set_visible(c.force_def, vis)
        ui.set_visible(c.force_break, def_on)
        ui.set_visible(c.height_based_pitch, def_on)
        ui.set_visible(c.def_mode, def_on)
        ui.set_visible(c.def_trigger, def_on and not pro_visible)
        ui.set_visible(c.def_duration, def_on)
        ui.set_visible(c.def_pitch, def_on)
        local dp = def_on and ui.get(c.def_pitch) or "Off"
        ui.set_visible(c.def_pitch_val, def_on and dp == "Custom")
        ui.set_visible(c.def_pitch_j1, def_on and dp == "Jitter")
        ui.set_visible(c.def_pitch_j2, def_on and dp == "Jitter")
        ui.set_visible(c.def_pitch_jdelay, def_on and dp == "Jitter")
        local dp_spin = def_on and (dp == "Spin" or dp == "Auto Spin")
        ui.set_visible(c.def_pitch_s1, dp_spin)
        ui.set_visible(c.def_pitch_s2, dp_spin)
        ui.set_visible(c.def_pitch_speed, dp_spin)
        local dp_rand = def_on and dp == "Random"
        ui.set_visible(c.def_pitch_r1, dp_rand)
        ui.set_visible(c.def_pitch_r2, dp_rand)
        ui.set_visible(c.def_yaw, def_on)
        local dy = def_on and ui.get(c.def_yaw) or "Off"
        ui.set_visible(c.def_yaw_val, def_on and dy == "Custom")
        ui.set_visible(c.def_yaw_j1, def_on and dy == "Jitter")
        ui.set_visible(c.def_yaw_j2, def_on and dy == "Jitter")
        ui.set_visible(c.def_yaw_jdelay, def_on and dy == "Jitter")
        local dy_spin = def_on and (dy == "Spin" or dy == "Auto Spin")
        ui.set_visible(c.def_yaw_s1, dy_spin)
        ui.set_visible(c.def_yaw_s2, dy_spin)
        ui.set_visible(c.def_yaw_speed, dy_spin)
        local dy_rand = def_on and dy == "Random"
        ui.set_visible(c.def_yaw_r1, dy_rand)
        ui.set_visible(c.def_yaw_r2, dy_rand)
        local dy_cway = def_on and dy == "Custom Way"
        ui.set_visible(c.def_yaw_way_count, dy_cway)
        local way_count = dy_cway and ui.get(c.def_yaw_way_count) or 0
        for i = 1, 10 do
            ui.set_visible(c.def_yaw_ways[i], dy_cway and i <= way_count)
        end
        local def_body = def_on and tostring(ui.get(c.def_body_yaw) or "Inherit") or "Inherit"
        local def_body_jitter = def_body == "Jitter Pro"
        local def_body_sided = def_body_jitter or def_body == "Static Pro"
        ui.set_visible(c.def_body_yaw, def_on)
        ui.set_visible(c.def_body_side, def_on and def_body_sided)
        ui.set_visible(c.def_body_delay, def_on and def_body_sided)
        ui.set_visible(c.fakelag, vis)
    end
end
ui.set_callback(page_sel, update_vis)
ui.set_callback(master, function()
    sync_communication_state()
    if not ui.get(master) then
        hitlog_shots = {}
        extras.cleanup()
        reset_native()
        invalidate_freestand_controller()
        if master_cleanup then master_cleanup() end
    end
    update_vis()
end)
ui.set_callback(defensive_backend, function()
    pro.reset("backend_change")
    update_vis()
end)
ui.set_callback(condition_sel, update_vis)
ui.set_callback(indicator_sel, update_vis); ui.set_callback(anti_backstab, update_vis)
ui.set_callback(hide_vm_tp, function()
    if not ui.get(hide_vm_tp) then restore_tp_viewmodel() end
    update_vis()
end)
ui.set_callback(hitlog_enabled, function()
    if not ui.get(hitlog_enabled) then hitlog_shots = {} end
    update_vis()
end)
ui.set_callback(auto_mute_all, function()
    sync_communication_state()
    update_vis()
end)
for _, cond in ipairs(conditions) do
    local c = cfg[cond]
    for _, ref in ipairs({c.yaw_left_right, c.yaw_jitter, c.slow_pro_mode, c.body_yaw, c.force_def,
        c.def_pitch, c.def_yaw, c.def_yaw_way_count, c.def_body_yaw}) do
        ui.set_callback(ref, update_vis)
    end
end
update_vis()

client.set_event_callback("paint_ui", function()
    if ui.is_menu_open() then
        if ui.get(master) then native_visible(false) else native_visible(true) end
    end
end)

local function body_yaw()
    local lp = entity.get_local_player() if not lp then return "R" end
    local p = entity.get_prop(lp, "m_flPoseParameter", 11) if not p then return "R" end
    local d = p * 120 - 60
    if d > 25 then return "R" elseif d < -25 then return "L" else return "B" end
end
local manual_mode, prev_left, prev_right, prev_fwd = "back", false, false, false

local function update_manual()
    local l, r, f = ui.get(manual_left), ui.get(manual_right), ui.get(manual_fwd)
    if l and not prev_left then manual_mode = (manual_mode == "left") and "back" or "left" end
    if r and not prev_right then manual_mode = (manual_mode == "right") and "back" or "right" end
    if f and not prev_fwd then manual_mode = (manual_mode == "forward") and "back" or "forward" end
    prev_left, prev_right, prev_fwd = l, r, f
end
local current_cond, current_layer = "Standing", "normal"
local edge_active = false

local movement_state = {}

local function reset_movement_state()
    for key in pairs(movement_state) do movement_state[key] = nil end
end

local function get_movement_condition(me, cmd)
    local s, tick = movement_state, globals.tickcount()
    local command = cmd and cmd.command_number or tick
    local move = entity.get_prop(me, "m_MoveType") or 2
    if s.player ~= me or s.tick and (tick < s.tick or tick - s.tick > 16)
        or s.command and command < s.command or move == 8 or move == 9 then
        reset_movement_state()
    end
    if s.command == command and s.result then return s.result end
    local flags = entity.get_prop(me, "m_fFlags") or 0
    local on_gnd = bit.band(flags, 1) ~= 0
    local duck = (entity.get_prop(me, "m_flDuckAmount") or 0) == 1
    local vx, vy = entity.get_prop(me, "m_vecVelocity[0]") or 0, entity.get_prop(me, "m_vecVelocity[1]") or 0
    local moving = vx * vx + vy * vy > 25
    local result
    if not on_gnd then
        result = duck and "Air+" or "Air"
        s.air, s.landed = result, nil
    elseif s.air and move ~= 8 and move ~= 9 then
        s.landed = s.landed or tick
        if tick - s.landed < 2 then result = s.air else s.air, s.landed = nil, nil end
    end
    if not result then
        if duck then result = moving and "Duck move" or "Duck"
        elseif moving then result = (slow_key and ui.get(slow_key)) and "Slowwalk" or "Moving"
        else result = "Standing" end
    end
    s.player, s.command, s.tick, s.result = me, command, tick, result
    return result
end

local function get_condition(me, cmd)
    freestand_requested, edge_active = false, false
    local move_cond = get_movement_condition(me, cmd)
    if manual_mode ~= "back" then return "manual", move_cond end
    freestand_requested = ui.get(fs_hotkey) and has_trigger(fs_states, move_cond)
    edge_active = ui.get(edge_hotkey)
    local active_cond = move_cond
    if freestand_requested and cfg["Freestanding"] and cfg["Freestanding"].enabled and ui.get(cfg["Freestanding"].enabled) then
        active_cond = "Freestanding"
    end
    return active_cond, move_cond
end

local function resolve_config(cond, move_cond)
    if cond == "manual" then
        return cfg["Standing"] or cfg["Global"]
    end
    local c = cfg[cond]
    if c and (not c.enabled or ui.get(c.enabled)) then
        return c
    end
    if move_cond and move_cond ~= cond then
        local mc = cfg[move_cond]
        if mc and (not mc.enabled or ui.get(mc.enabled)) then
            return mc
        end
    end
    return cfg["Global"]
end

local function normalize_yaw(y)
    while y > 180 do y = y - 360 end
    while y < -180 do y = y + 360 end
    return y
end
local configured_proc = tonumber(client.get_cvar("sv_maxusrcmdprocessticks")) or 16
local max_proc = math.max(2, math.abs(configured_proc) - 1)

local function new_defensive_timing()
    return {
        window = false,
        request_until = -1,
        window_until = -1,
        exhausted = false,
        phase = 0,
        phase_tick = -1,
        cached_config = nil,
        cached_pitch_mode = nil,
        cached_pitch_value = 0,
        cached_yaw = nil
    }
end
local defensive_timing = {
    Gamesense = new_defensive_timing(),
    Unoins = new_defensive_timing(),
    UnoinsPro = pro.state
}
local active_defensive_backend = nil
local aa_sequence = {
    sent = 0,
    last_command = -1
}

local function reset_aa_sequence()
    aa_sequence.sent = 0
    aa_sequence.last_command = -1
end

local function update_aa_sequence(cmd)
    local command = cmd.command_number or globals.tickcount()
    if (cmd.chokedcommands or 0) == 0 and command ~= aa_sequence.last_command then
        aa_sequence.sent = aa_sequence.sent + 1
        aa_sequence.last_command = command
    end
end

local function reset_defensive_timing(state, full)
    state.window = false
    state.window_until = -1
    state.exhausted = false
    state.phase = 0
    state.phase_tick = -1
    state.cached_config = nil
    state.cached_pitch_mode = nil
    state.cached_pitch_value = 0
    state.cached_yaw = nil
    if full then
        state.request_until = -1
    end
end
local defensive_state = {
    run_command_number = 0,
    choked = 0,
    baseline = nil,
    lc_left = 0,
    ticks_processed = 0,
    active = false,
    last_predict_tick = -1,
    origin_x = nil,
    origin_y = nil,
    origin_z = nil,
    simulation_tick = nil,
    spatial_until = -1,
    request = false,
    peeking = false
}

local function reset_defensive_state()
    reset_movement_state()
    defensive_state.run_command_number = 0
    defensive_state.choked = 0
    defensive_state.baseline = nil
    defensive_state.lc_left = 0
    defensive_state.ticks_processed = 0
    defensive_state.active = false
    defensive_state.last_predict_tick = -1
    defensive_state.origin_x = nil
    defensive_state.origin_y = nil
    defensive_state.origin_z = nil
    defensive_state.simulation_tick = nil
    defensive_state.spatial_until = -1
    defensive_state.request = false
    defensive_state.peeking = false
    active_defensive_backend = nil
    reset_defensive_timing(defensive_timing.Gamesense, true)
    reset_defensive_timing(defensive_timing.Unoins, true)
    pro.reset("lifecycle")
end

client.set_event_callback("run_command", function(c)
    if not ui.get(master) then return end
    defensive_state.run_command_number = c.command_number or 0
    defensive_state.choked = c.chokedcommands or 0
end)

client.set_event_callback("predict_command", function(c)
    if not ui.get(master) then return end
    if (c.command_number or 0) ~= defensive_state.run_command_number then return end
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then reset_defensive_state(); return end
    local tickbase = entity.get_prop(me, "m_nTickBase")
    if not tickbase then return end
    local baseline = defensive_state.baseline
    if baseline == nil or math.abs(tickbase - baseline) > 64 then
        defensive_state.baseline = tickbase
    elseif tickbase > baseline then
        defensive_state.baseline = tickbase
    end
    baseline = defensive_state.baseline
    local cap = math.max(0, math.min(14, max_proc - defensive_state.choked))
    defensive_state.lc_left = math.min(cap, math.max(0, baseline - tickbase - 1))
    defensive_state.ticks_processed = math.min(cap, math.abs(baseline - tickbase))
    local active = (hl_active(hl_ref.dt) or hl_active(hl_ref.os)) and defensive_state.lc_left > 0
    defensive_state.active = active
    defensive_state.last_predict_tick = globals.tickcount()
    defensive_state.run_command_number = 0
end)

client.set_event_callback("net_update_start", function()
    if not ui.get(master) then return end
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    local x, y, z = entity.get_origin(me)
    local simulation_time = entity.get_prop(me, "m_flSimulationTime")
    local interval = globals.tickinterval()
    if not x or not y or not z or not simulation_time or not interval or interval <= 0 then return end
    local simulation_tick = math.floor(simulation_time / interval + 0.5)
    local previous_tick = defensive_state.simulation_tick
    if defensive_state.origin_x and previous_tick then
        local simulation_delta = simulation_tick - previous_tick
        if simulation_delta < 0 or (simulation_delta > 0 and simulation_delta <= 64) then
            local dx = x - defensive_state.origin_x
            local dy = y - defensive_state.origin_y
            local dz = z - defensive_state.origin_z
            local distance_sqr = dx * dx + dy * dy + dz * dz
            if distance_sqr > 4096 then
                defensive_state.spatial_until = globals.tickcount() + 2
            end
        end
    end
    defensive_state.origin_x = x
    defensive_state.origin_y = y
    defensive_state.origin_z = z
    defensive_state.simulation_tick = simulation_tick
end)

local function is_breaking_lc()
    local tick = globals.tickcount()
    if defensive_state.last_predict_tick >= 0
        and tick - defensive_state.last_predict_tick > 3 then
        defensive_state.active = false
        defensive_state.lc_left = 0
        defensive_state.ticks_processed = 0
    end
    local exploit = hl_active(hl_ref.dt) or hl_active(hl_ref.os)
    local age = tick - defensive_state.last_predict_tick
    local remaining = math.max(0, defensive_state.lc_left - math.max(0, age))
    local tickbase_break = exploit and defensive_state.active and age >= 0 and age <= 3 and remaining > 0
    local spatial_break = exploit and tick <= defensive_state.spatial_until
    return tickbase_break, remaining, spatial_break
end

local function is_early_peek(me)
    defensive_state.peeking = false
    if not me or not entity.is_alive(me) then return false end
    local vx = entity.get_prop(me, "m_vecVelocity[0]") or 0
    local vy = entity.get_prop(me, "m_vecVelocity[1]") or 0
    local vz = entity.get_prop(me, "m_vecVelocity[2]") or 0
    local speed = math.sqrt(vx * vx + vy * vy)
    if speed < 25 then return false end
    local eye_x, eye_y, eye_z = client.eye_position()
    if not eye_x then return false end
    local ticks = math.min(12, max_proc)
    local dt = globals.tickinterval() * ticks
    local pred_x, pred_y, pred_z = eye_x + vx * dt, eye_y + vy * dt, eye_z + vz * dt
    local move_x, move_y = pred_x - eye_x, pred_y - eye_y
    if move_x * move_x + move_y * move_y < 144 then return false end
    local function bullet_exposed(shooter, sx, sy, sz, tx, ty, tz)
        if type(client.trace_bullet) ~= "function" then return false end
        local ok, _, damage = checked_call("bullet_exposed", client.trace_bullet, shooter, sx, sy, sz, tx, ty, tz)
        return ok and (tonumber(damage) or 0) > 0
    end
    local function line_exposed(skip, sx, sy, sz, tx, ty, tz, target)
        if type(client.trace_line) ~= "function" then return false end
        local ok, fraction, hit = checked_call("line_exposed", client.trace_line, skip, sx, sy, sz, tx, ty, tz)
        return ok and (hit == target or (fraction and fraction > 0.97))
    end
    local enemies = entity.get_players(true)
    for _, enemy in ipairs(enemies) do
        if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
            local evx = entity.get_prop(enemy, "m_vecVelocity[0]") or 0
            local evy = entity.get_prop(enemy, "m_vecVelocity[1]") or 0
            local ev_dt = globals.tickinterval() * 4
            local current_exposed = false
            local predicted_exposed = false
            local hitboxes = {0, 2, 4}
            for _, hb in ipairs(hitboxes) do
                local hit_x, hit_y, hit_z = entity.hitbox_position(enemy, hb)
                if hit_x then
                    local target_x = hit_x + evx * ev_dt
                    local target_y = hit_y + evy * ev_dt
                    local target_z = hit_z
                    current_exposed = current_exposed
                        or bullet_exposed(me, eye_x, eye_y, eye_z, hit_x, hit_y, hit_z)
                        or bullet_exposed(enemy, hit_x, hit_y, hit_z, eye_x, eye_y, eye_z)
                        or line_exposed(me, eye_x, eye_y, eye_z, hit_x, hit_y, hit_z, enemy)
                    predicted_exposed = predicted_exposed
                        or bullet_exposed(me, pred_x, pred_y, pred_z, target_x, target_y, target_z)
                        or bullet_exposed(enemy, target_x, target_y, target_z, pred_x, pred_y, pred_z)
                        or line_exposed(me, pred_x, pred_y, pred_z, target_x, target_y, target_z, enemy)
                end
            end
            if predicted_exposed and not current_exposed then
                defensive_state.peeking = true
                return true
            end
        end
    end
    return false
end

local function find_backstab_threat(me)
    if not ui.get(anti_backstab) then return nil end
    local lx, ly, lz = entity.get_origin(me)
    local eye_x, eye_y, eye_z = client.eye_position()
    if not lx or not eye_x then return nil end
    local max_distance = 400
    local max_distance_sqr = max_distance * max_distance
    for _, enemy in ipairs(entity.get_players(true)) do
        if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
            local weapon = entity.get_player_weapon(enemy)
            local ex, ey, ez = entity.get_origin(enemy)
            if weapon and ex and entity.get_classname(weapon) == "CKnife" then
                local dx, dy, dz = ex - lx, ey - ly, ez - lz
                if dx * dx + dy * dy + dz * dz <= max_distance_sqr then
                    local hx, hy, hz = entity.hitbox_position(enemy, 4)
                    if hx then
                        local ok, fraction, hit = checked_call("find_backstab_threat", 
                            client.trace_line, enemy, hx, hy, hz, eye_x, eye_y, eye_z
                        )
                        if ok and (hit == me or (fraction and fraction > 0.97)) then
                            return enemy
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function reset_local_defensive(e)
    local me = entity.get_local_player()
    local idx = e and e.userid and client.userid_to_entindex(e.userid) or nil
    if not me or not idx or idx == me then reset_defensive_state() end
end

client.set_event_callback("level_init", function()
    reset_aa_sequence()
    reset_defensive_state()
end)

client.set_event_callback("round_prestart", reset_defensive_state)

client.set_event_callback("player_spawn", reset_local_defensive)

client.set_event_callback("player_death", reset_local_defensive)
local SLOW_RATE = 3
local hl_dt_st, hl_dt_lc, hl_dt_wh = "off", 0, false
local last_fl = { on = false, mode = "", limit = 0 }
ui.set_callback(fl_ground_mode, function() last_fl.on = nil end)
local fl_peek_until = -1

local function fl_user_value(key)
    local saved = native_snapshot and native_snapshot[key]
    return saved and saved[1]
end

local function fl_can_shoot_visible(me)
    local weapon = entity.get_player_weapon(me)
    if not weapon then return false end
    local tickbase, interval = entity.get_prop(me, "m_nTickBase"), globals.tickinterval()
    if not pro.finite(tickbase) or not pro.finite(interval) or interval <= 0 then return false end
    local now = tickbase * interval
    local ready = math.max(entity.get_prop(me, "m_flNextAttack") or 0, entity.get_prop(weapon, "m_flNextPrimaryAttack") or 0)
    if ready > now then return false end
    if (entity.get_prop(weapon, "m_iClip1") or 0) <= 0 then return false end
    local threat = client.current_threat()
    if not threat or not entity.is_alive(threat) or entity.is_dormant(threat) then return false end
    local x, y, z = entity.hitbox_position(threat, 0)
    return x ~= nil and client.visible(x, y, z)
end

local function fakelag_plan(me)
    if hl_active(hl_ref.dt) then return true end
    local interval = globals.tickinterval()
    local cap = math.max(2, math.min(14, max_proc - 1))
    local vx = entity.get_prop(me, "m_vecVelocity[0]") or 0
    local vy = entity.get_prop(me, "m_vecVelocity[1]") or 0
    local speed = math.sqrt(vx * vx + vy * vy)
    local on_ground = bit.band(entity.get_prop(me, "m_fFlags") or 0, 1) ~= 0
    local tick = globals.tickcount()
    if on_ground and speed <= 10 then return false end
    local need = (pro.finite(interval) and interval > 0 and speed > 1) and math.ceil(64 / (speed * interval)) or math.huge
    if on_ground and fl_can_shoot_visible(me) then
        fl_peek_until = -1
        return true, "Maximum", 2, 0
    end
    if on_ground and speed > 25 then
        local ok, ctx = checked_call("fakelag peek", pro.probe, me, true)
        if ok and ctx and ctx.peek then fl_peek_until = tick + 8 end
    end
    if tick <= fl_peek_until then return true, "Maximum", cap, 0 end
    if need <= cap then return true, "Dynamic", math.min(cap, need + 1), 0 end
    if not on_ground then return true, "Dynamic", cap, 0 end
    local variance = math.floor(math.max(0, math.min(100, speed / 300 * 100)))
    if ui.get(fl_ground_mode) == "Maximum" then return true, "Maximum", cap, variance end
    return true, "Maximum", 3, 0
end

local function get_threat_height_diff(me)
    if not me or not entity.is_alive(me) then return 0 end
    local threat = client.current_threat()
    if threat and entity.is_alive(threat) and not entity.is_dormant(threat) then
        local _, _, lz = entity.get_origin(me)
        local _, _, ez = entity.get_origin(threat)
        if lz and ez then return math.ceil(lz - ez) end
    end
    local lx, ly, lz = entity.get_origin(me)
    if not lx then return 0 end
    local nearest_dist_sqr = math.huge
    local nearest_z = nil
    for _, enemy in ipairs(entity.get_players(true)) do
        if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
            local ex, ey, ez = entity.get_origin(enemy)
            if ex then
                local dx, dy, dz = ex - lx, ey - ly, ez - lz
                local dist_sqr = dx * dx + dy * dy + dz * dz
                if dist_sqr < nearest_dist_sqr then
                    nearest_dist_sqr = dist_sqr
                    nearest_z = ez
                end
            end
        end
    end
    if nearest_z and nearest_dist_sqr < 4000000 then
        return math.ceil(lz - nearest_z)
    end
    return 0
end

local function calc_def_pitch(dp, c, phase)
    if dp == "Off" then return nil, nil end
    phase = math.max(0, phase or 0)
    local h_offset = 0
    if ui.get(c.height_based_pitch) then
        local me = entity.get_local_player()
        local h_diff = get_threat_height_diff(me)
        h_offset = math.max(-45, math.min(45, math.ceil(h_diff * 0.25)))
    end
    local function clamp_p(val)
        return math.max(-89, math.min(89, val - h_offset))
    end
    if dp == "Up" then
        if h_offset ~= 0 then return "Custom", clamp_p(-89) end
        return "Up", 0
    elseif dp == "Zero" then
        return "Custom", clamp_p(0)
    elseif dp == "Down" then
        if h_offset ~= 0 then return "Custom", clamp_p(89) end
        return "Down", 0
    elseif dp == "Custom" then
        return "Custom", clamp_p(ui.get(c.def_pitch_val))
    elseif dp == "Jitter" then
        local j1 = ui.get(c.def_pitch_j1)
        local j2 = ui.get(c.def_pitch_j2)
        local delay = math.max(1, ui.get(c.def_pitch_jdelay))
        local step = math.floor(phase / delay) % 2
        return "Custom", clamp_p(step == 0 and j1 or j2)
    elseif dp == "Spin" then
        local s1 = ui.get(c.def_pitch_s1)
        local s2 = ui.get(c.def_pitch_s2)
        local spd = ui.get(c.def_pitch_speed)
        local diff = s2 - s1
        local pitch_val
        if diff == 0 then
            pitch_val = s1
        else
            local progress = (globals.curtime() * spd * 0.1) % 1
            pitch_val = s1 + progress * diff
        end
        return "Custom", clamp_p(pitch_val)
    elseif dp == "Auto Spin" then
        local s1 = ui.get(c.def_pitch_s1)
        local s2 = ui.get(c.def_pitch_s2)
        local spd = ui.get(c.def_pitch_speed)
        local min_p = math.min(s1, s2)
        local max_p = math.max(s1, s2)
        local range = max_p - min_p
        local progress = (globals.curtime() * spd * 0.1) % 2
        if progress > 1 then progress = 2 - progress end
        local pitch_val = min_p + progress * range
        return "Custom", clamp_p(pitch_val)
    elseif dp == "Random" then
        local r1 = ui.get(c.def_pitch_r1)
        local r2 = ui.get(c.def_pitch_r2)
        local min_r = math.min(r1, r2)
        local max_r = math.max(r1, r2)
        local pitch_val = client.random_int(min_r, max_r)
        return "Custom", clamp_p(pitch_val)
    elseif dp == "4Way" then
        local step = math.floor(phase / 2) % 4
        if step == 0 then
            if h_offset ~= 0 then return "Custom", clamp_p(89) end
            return "Down", 0
        elseif step == 1 or step == 3 then
            return "Custom", clamp_p(0)
        elseif step == 2 then
            if h_offset ~= 0 then return "Custom", clamp_p(-89) end
            return "Up", 0
        end
    elseif dp == "5Way" then
        local step = math.floor(phase / 2) % 5
        if step == 0 then
            if h_offset ~= 0 then return "Custom", clamp_p(89) end
            return "Down", 0
        elseif step == 1 then
            return "Custom", clamp_p(45)
        elseif step == 2 then
            return "Custom", clamp_p(0)
        elseif step == 3 then
            return "Custom", clamp_p(-45)
        elseif step == 4 then
            if h_offset ~= 0 then return "Custom", clamp_p(-89) end
            return "Up", 0
        end
    end
    return nil, nil
end

local function calc_def_yaw(dy, base_yaw, c, phase)
    if dy == "Off" then return nil end
    phase = math.max(0, phase or 0)
    local yaw
    if dy == "Custom" then
        yaw = base_yaw + ui.get(c.def_yaw_val)
    elseif dy == "Jitter" then
        local j1 = ui.get(c.def_yaw_j1)
        local j2 = ui.get(c.def_yaw_j2)
        local delay = math.max(1, ui.get(c.def_yaw_jdelay))
        local step = math.floor(phase / delay) % 2
        yaw = base_yaw + (step == 0 and j1 or j2)
    elseif dy == "Spin" then
        local s1 = ui.get(c.def_yaw_s1)
        local s2 = ui.get(c.def_yaw_s2)
        local spd = ui.get(c.def_yaw_speed)
        local diff = s2 - s1
        local offset
        if diff == 0 then
            offset = s1
        else
            local progress = (globals.curtime() * spd * 0.05) % 1
            offset = s1 + progress * diff
        end
        yaw = base_yaw + normalize_yaw(offset)
    elseif dy == "Auto Spin" then
        local s1 = ui.get(c.def_yaw_s1)
        local s2 = ui.get(c.def_yaw_s2)
        local spd = ui.get(c.def_yaw_speed)
        local min_y = math.min(s1, s2)
        local max_y = math.max(s1, s2)
        local range = max_y - min_y
        local offset
        if range <= 0 then
            offset = min_y
        else
            local progress = (globals.curtime() * spd * 0.05) % 2
            if progress > 1 then progress = 2 - progress end
            offset = min_y + progress * range
        end
        yaw = base_yaw + normalize_yaw(offset)
    elseif dy == "Random" then
        local r1 = ui.get(c.def_yaw_r1)
        local r2 = ui.get(c.def_yaw_r2)
        local min_r = math.min(r1, r2)
        local max_r = math.max(r1, r2)
        local rand_val = client.random_int(min_r, max_r)
        yaw = base_yaw + normalize_yaw(rand_val)
    elseif dy == "Opposite" then
        yaw = base_yaw + 179
    elseif dy == "4Way" then
        local step = math.floor(phase / 2) % 4
        if step == 0 then
            yaw = base_yaw + 0
        elseif step == 1 then
            yaw = base_yaw + 90
        elseif step == 2 then
            yaw = base_yaw + 179
        elseif step == 3 then
            yaw = base_yaw - 90
        end
    elseif dy == "Custom Way" then
        local count = math.max(1, math.min(10, ui.get(c.def_yaw_way_count) or 1))
        local step = (math.floor(phase / 2) % count) + 1
        local way_slider = c.def_yaw_ways and c.def_yaw_ways[step]
        local way_angle = way_slider and ui.get(way_slider) or 0
        yaw = base_yaw + normalize_yaw(way_angle)
    end
    return yaw
end

local function defensive_config_key(c)
    local refs = {
        c.height_based_pitch,
        c.def_pitch, c.def_pitch_val, c.def_pitch_j1, c.def_pitch_j2, c.def_pitch_jdelay,
        c.def_pitch_s1, c.def_pitch_s2, c.def_pitch_speed, c.def_pitch_r1, c.def_pitch_r2,
        c.def_yaw, c.def_yaw_val, c.def_yaw_j1, c.def_yaw_j2, c.def_yaw_jdelay,
        c.def_yaw_s1, c.def_yaw_s2, c.def_yaw_speed, c.def_yaw_r1, c.def_yaw_r2,
        c.def_yaw_way_count, c.def_body_yaw, c.def_body_side, c.def_body_delay, c.def_duration
    }
    local values = {}
    for i = 1, #refs do values[#values + 1] = tostring(ui.get(refs[i])) end
    for i = 1, 10 do values[#values + 1] = tostring(ui.get(c.def_yaw_ways[i])) end
    return table.concat(values, ":")
end

local function inverter(body_sel, bdelay)
    local step = body_sel ~= "Off" and bdelay > 1 and bdelay or 1
    local phase = math.floor(math.max(0, aa_sequence.sent - 1) / step)
    return phase % 2 == 0 and 1 or -1
end
local slow_pro = {counter = 0, phase = 0, lift = 0}

function slow_pro.update(cmd, me)
    local tickbase = entity.get_prop(me, "m_nTickBase")
    if not pro.finite(tickbase) then return end
    local choke = cmd.chokedcommands or 0
    if (tickbase > 1 + choke or tickbase < 0) and choke == 0 then
        slow_pro.counter = slow_pro.counter + 1
    end
end

function slow_pro.offset(c, cmd, amount)
    local mode = ui.get(c.slow_pro_mode)
    local speed = ui.get(c.slow_pro_speed)
    if (cmd.command_number or globals.tickcount()) % (ui.get(c.slow_pro_interval) * 2) == 0 and mode == "Cycle lift" then
        slow_pro.lift = slow_pro.lift + 1
        if slow_pro.lift > ui.get(c.slow_pro_max) then
            slow_pro.lift = ui.get(c.slow_pro_min)
        end
    end
    if mode == "Cycle lift" then
        speed = slow_pro.lift
    elseif mode == "Randomize" then
        speed = client.random_int(0, speed + 1)
    end
    if (slow_pro.counter + 2) % (speed + 1) == 0 and (cmd.chokedcommands or 0) == 0 then
        slow_pro.phase = slow_pro.phase + 1
    end
    local random = client.random_int(0, ui.get(c.slow_pro_random))
    local degree = ui.get(c.slow_pro_degree)
    local expanded = amount > 0 and amount + degree + random or amount - degree - random
    local values = {amount, -amount, expanded, -expanded}
    return values[slow_pro.phase % 4 + 1]
end

local function apply_condition(cond, move_cond, cmd)
    local c = resolve_config(cond, move_cond)
    if not c then c = cfg["Global"] end
    nset(N.enabled, true)
    nset(N.pitch, "Minimal")
    nset(N.pitch_add, 0)
    nset(N.yaw_base, ui.get(c.yaw_base))
    local yaw_type, yaw_add = "180", ui.get(c.yaw_add)
    local pro_offset
    if ui.get(c.yaw_jitter) == "\aFFF59DFFSlow Pro\r" then
        pro_offset = slow_pro.offset(c, cmd, cond == "manual" and 0 or ui.get(c.yaw_jit_add))
    end
    local fs_requested = cond ~= "manual" and freestand_requested
    local fs_disable_jitter = fs_requested and has_trigger(fs_options, "Disable yaw jitter")
    local fs_disable_body = fs_requested
        and has_trigger(fs_options, "Disable body yaw")
    if cond == "manual" then
        if manual_mode == "left" then yaw_add = -90
        elseif manual_mode == "right" then yaw_add = 90
        elseif manual_mode == "forward" then yaw_add = 180 end
        yaw_type = "180"
        nset(N.yaw_base, "Local view")
        nset(N.body_yaw, "Off")
        nset(N.body_yaw_add, 0)
        nset(N.fs_body, false)
        nset(N.yaw_jitter, "Off")
        nset(N.yaw_jit_add, 0)
    else
        local body = tostring(ui.get(c.body_yaw) or "")
        local bdelay = ui.get(c.body_delay)
        local inverted = inverter(body, bdelay)
        if not fs_disable_jitter and ui.get(c.yaw_left_right) then
            local lr_side = pro_offset ~= nil and (pro_offset >= 0 and 1 or -1) or inverted
            local randv = lr_side == 1 and ui.get(c.left_randomization) or ui.get(c.right_randomization)
            local rand = randv > 0 and client.random_int(-randv, randv) or 0
            local lr_offset = (lr_side == 1 and ui.get(c.left) or ui.get(c.right)) + rand
            yaw_add = normalize_yaw(yaw_add + lr_offset)
        end
        local is_jitter = string.find(body, "Jitter", 1, true) ~= nil
        local is_opposite = string.find(body, "Opposite", 1, true) ~= nil
        local is_off = (body == "Off" or body == "")
        if fs_disable_body then
            nset(N.body_yaw, "Off")
            nset(N.body_yaw_add, 0)
        elseif not is_off and not is_opposite then
            local body_seed = ui.get(c.body_side) == "-" and -1 or 1
            local bside = (is_jitter or bdelay > 1) and inverted * body_seed or body_seed
            if pro_offset ~= nil and is_jitter then
                local relative_yaw = fs_disable_jitter and 0 or pro_offset
                bside = (relative_yaw >= 0 and 1 or -1) * body_seed
            end
            nset(N.body_yaw, "Static")
            nset(N.body_yaw_add, bside * 90)
        else
            nset(N.body_yaw, is_opposite and "Opposite" or "Off")
            nset(N.body_yaw_add, 0)
        end
        nset(N.fs_body, false)
        local jitter = tostring(ui.get(c.yaw_jitter) or "")
        local jit_range = ui.get(c.yaw_jit_add)
        if fs_disable_jitter then
            nset(N.yaw_jitter, "Off"); nset(N.yaw_jit_add, 0)
        elseif jitter == "\aFFF59DFFSlow Pro\r" then
            nset(N.yaw_jitter, "Off"); nset(N.yaw_jit_add, 0)
            aa_decision.jitter_offset = pro_offset
            yaw_add = yaw_add + pro_offset
        elseif jitter == "Slow" then
            nset(N.yaw_jitter, "Off"); nset(N.yaw_jit_add, 0)
            local slow_phase = math.floor(math.max(0, aa_sequence.sent - 1) / SLOW_RATE)
            aa_decision.jitter_offset = slow_phase % 2 == 0 and -jit_range or jit_range
            yaw_add = yaw_add + aa_decision.jitter_offset
        elseif jitter ~= "Off" and jitter ~= "" then
            nset(N.yaw_jitter, "Center"); nset(N.yaw_jit_add, jit_range)
        else
            nset(N.yaw_jitter, "Off"); nset(N.yaw_jit_add, 0)
        end
    end
    nset(N.yaw, yaw_type); nset(N.yaw_add, normalize_yaw(yaw_add))
    local edge_active_for_condition = cond ~= "manual" and edge_active
    nset(N.edge_yaw, edge_active_for_condition)
    if fs_requested then nset(N.edge_yaw, false) end
    local fl_mode = tostring(ui.get((cond == "manual" and cfg["Global"] or c).fakelag) or "")
    local fl_on, fl_amount, fl_limit, fl_var = false, nil, nil, nil
    local is_adaptive = string.find(fl_mode, "Adaptive", 1, true) ~= nil
    if fl_mode ~= "Off" and fl_mode ~= "" then
        fl_on = true
        local me2 = entity.get_local_player()
        if is_adaptive and me2 then fl_on, fl_amount, fl_limit, fl_var = fakelag_plan(me2) end
    end
    if extras.onshot() then fl_on = false end
    if not fl_amount then
        fl_amount, fl_limit, fl_var = fl_user_value("fake_amt"), fl_user_value("fake_limit"), fl_user_value("fake_var")
    end
    if last_fl.on ~= fl_on or last_fl.mode ~= fl_mode or last_fl.limit ~= fl_limit
        or last_fl.amount ~= fl_amount or last_fl.var ~= fl_var then
        last_fl.on, last_fl.mode, last_fl.limit, last_fl.amount, last_fl.var = fl_on, fl_mode, fl_limit, fl_amount, fl_var
        nset(N.fake_enabled, fl_on)
        if fl_amount ~= nil then nset(N.fake_amt, fl_amount) end
        if fl_limit ~= nil then nset(N.fake_limit, fl_limit) end
        if fl_var ~= nil then nset(N.fake_var, fl_var) end
    end
    nset(N.roll, 0)
    return c
end

local function clear_defensive_timings(full)
    reset_defensive_timing(defensive_timing.Gamesense, full)
    reset_defensive_timing(defensive_timing.Unoins, full)
    pro.reset("layer_change")
end

local function suppress_defensive_base(c, active)
    if not active or not ui.get(c.def_trigger) then return end
    nset(N.yaw_jitter, "Off")
    nset(N.yaw_jit_add, 0)
    if tostring(ui.get(c.def_body_yaw) or "Inherit") ~= "Inherit" then
        nset(N.body_yaw, "Off")
        nset(N.body_yaw_add, 0)
    end
end

local function apply_defensive_body(c, phase)
    local mode = tostring(ui.get(c.def_body_yaw) or "Inherit")
    if mode == "Inherit" then return end
    if mode == "Off" then
        nset(N.body_yaw, "Off")
        nset(N.body_yaw_add, 0)
        return
    end
    if mode == "Opposite" then
        nset(N.body_yaw, "Opposite")
        nset(N.body_yaw_add, 0)
        return
    end
    local side = ui.get(c.def_body_side) == "-" and -1 or 1
    local delay = math.max(1, ui.get(c.def_body_delay) or 1)
    if mode == "Jitter Pro" or delay > 1 then
        if math.floor(phase / delay) % 2 == 1 then side = -side end
    end
    nset(N.body_yaw, "Static")
    nset(N.body_yaw_add, side * 90)
end

local function update_defensive_window(state, tick, valid, duration)
    if not valid then
        state.window = false
        state.window_until = -1
        state.exhausted = false
        return false, false
    end
    if state.exhausted then return false, false end
    local entered = not state.window
    if entered then
        state.window = true
        state.window_until = tick + duration
    end
    if tick >= state.window_until then
        state.window = false
        state.exhausted = true
        return false, false
    end
    return true, entered
end

local function defensive_yaw(yaw, keep_jitter)
    if keep_jitter and aa_decision.active then yaw = yaw + (aa_decision.jitter_offset or 0) end
    return math.max(-179, math.min(179, normalize_yaw(yaw)))
end

local function apply_timed_defensive(backend, c, cmd, me)
    local state = defensive_timing[backend]
    defensive_state.request = false
    defensive_state.peeking = false
    if not c or not ui.get(c.force_def) or not (hl_active(hl_ref.dt) or hl_active(hl_ref.os)) then
        reset_defensive_timing(state, true)
        return false
    end
    local mode = ui.get(c.def_mode)
    local tick = globals.tickcount()
    if mode == "On peek" and is_early_peek(me) then state.request_until = tick + 7 end
    local should_request = mode == "Always"
        or (mode == "On peek" and tick <= state.request_until)
    defensive_state.request = should_request
    if should_request then cmd.force_defensive = true end
    suppress_defensive_base(c, should_request)
    local breaking = is_breaking_lc()
    local duration = math.max(1, math.min(14, ui.get(c.def_duration) or 14))
    local active, entered = update_defensive_window(state, tick, breaking, duration)
    if not active then return false end
    if entered then
        state.cached_config = nil
        state.cached_pitch_mode = nil
        state.cached_pitch_value = 0
        state.cached_yaw = nil
    end
    local phase_clock = aa_sequence.sent
    local phase_changed = state.phase_tick ~= phase_clock
    if phase_changed then
        if state.phase_tick >= 0 then state.phase = state.phase + 1 end
        state.phase_tick = phase_clock
    end
    local config_key = defensive_config_key(c)
    local config_changed = state.cached_config ~= config_key
    local force_send = ui.get(c.force_break) and entered
    if force_send then
        cmd.no_choke = true
        cmd.allow_send_packet = true
    end
    local phase = state.phase
    if phase_changed or config_changed then
        local dp = ui.get(c.def_pitch)
        local dy = ui.get(c.def_yaw)
        state.cached_pitch_mode = nil
        state.cached_pitch_value = 0
        if dp ~= "Off" then
            local p_type, p_val = calc_def_pitch(dp, c, phase)
            state.cached_pitch_mode = p_type
            state.cached_pitch_value = p_val or 0
        end
        state.cached_yaw = nil
        if dy ~= "Off" then
            local yaw_offset = calc_def_yaw(dy, 0, c, phase)
            if yaw_offset then state.cached_yaw = normalize_yaw(yaw_offset) end
        end
        state.cached_config = config_key
    end
    if state.cached_pitch_mode then
        nset(N.pitch, state.cached_pitch_mode)
        nset(N.pitch_add, state.cached_pitch_value)
    end
    if state.cached_yaw then
        local diff = state.cached_yaw
        if diff >= 180 then diff = 179 elseif diff <= -180 then diff = -179 end
        nset(N.yaw_base, ui.get(c.yaw_base))
        nset(N.yaw, "180")
        nset(N.yaw_add, defensive_yaw(diff, not ui.get(c.def_trigger)))
    end
    apply_defensive_body(c, phase)
    nset(N.fs_body, false)
    nset(N.edge_yaw, false)
    return true
end

local function safe_head_selected(me)
    local weapon = entity.get_player_weapon(me)
    if not weapon then return false end
    local class = entity.get_classname(weapon)
    if not class then return false end
    if string.find(class, "Knife", 1, true) then
        return has_trigger(safe_head_weapons, "Knife")
    elseif class == "CWeaponTaser" then
        return has_trigger(safe_head_weapons, "Taser")
    elseif class == "CWeaponGlock" then
        return has_trigger(safe_head_weapons, "Glock-18")
    end
    return false
end

local function apply_safe_head(cmd)
    cmd.force_defensive = false
    defensive_state.request = false
    defensive_state.peeking = false
    clear_defensive_timings(true)
    nset(N.pitch, "Down")
    nset(N.pitch_add, 0)
    nset(N.yaw_base, "At targets")
    nset(N.yaw, "180")
    nset(N.yaw_add, 0)
    nset(N.yaw_jitter, "Off")
    nset(N.yaw_jit_add, 0)
    nset(N.body_yaw, "Off")
    nset(N.body_yaw_add, 0)
    nset(N.fs_body, false)
end

function pro.finite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function pro.selected()
    return tostring(ui.get(defensive_backend) or ""):find("Ünoins_qucy Pro", 1, true) ~= nil
end

function pro.capacity(choke)
    local raw = tonumber(client.get_cvar("sv_maxusrcmdprocessticks"))
    if not pro.finite(raw) or raw < 2 then raw = 16 end
    return math.max(0, math.min(14, math.floor(raw) - 1 - math.max(0, choke or 0)))
end

function pro.reset(reason)
    local s = pro.state
    for key in pairs(s) do s[key] = nil end
    s.seen, s.last_command, s.last_send = -1, -1, -1
    s.deadline, s.window_until, s.peek_until = -1, -1, -1
    s.probe_tick = -100
    s.raw_left, s.phase, s.phase_tick = 0, 0, -1
    s.window, s.episode, s.exhausted = false, false, false
    s.reason = reason or "reset"
end
pro.epoch = 0
pro.reset("startup")

function pro.observe(tick, tickbase, command, choke)
    local s = pro.state
    if not pro.finite(tick) or not pro.finite(tickbase) or tickbase < 0 then
        pro.reset("invalid_tickbase")
        return
    end
    if command <= s.last_command then return end
    if tick < s.seen or (s.baseline and math.abs(tickbase - s.baseline) > 64) then
        pro.reset("clock_discontinuity")
    end
    if not s.baseline then
        s.baseline, s.seen, s.last_command = tickbase, tick, command
        return
    end
    local gap = s.baseline - tickbase
    if gap > pro.capacity(0) + 2 then
        pro.reset("oversized_correction")
        s.baseline, s.seen, s.last_command = tickbase, tick, command
        return
    end
    s.baseline = math.max(s.baseline, tickbase)
    s.seen, s.last_command = tick, command
    local gap_left = math.max(0, s.baseline - tickbase - 1)
    local left = math.min(pro.capacity(choke), gap_left)
    s.raw_left = left
    if gap_left <= 0 then
        s.episode, s.window, s.exhausted = false, false, false
        s.deadline, s.window_until = -1, -1
        s.reason = "recovered"
        return
    end
    if not s.episode then
        pro.epoch = pro.epoch + 1
        s.episode, s.exhausted = true, left <= 0
        s.started, s.deadline, s.initial_left = tick, tick + left, left
        s.phase, s.last_send, s.cache = 0, -1, nil
    else
        s.deadline = math.min(s.deadline, tick + left)
    end
end

function pro.enabled()
    local me = entity.get_local_player()
    return ui.get(master) and pro.selected() and me and entity.is_alive(me)
        and (hl_active(hl_ref.dt) or hl_active(hl_ref.os)), me
end

client.set_event_callback("run_command", function(cmd)
    local enabled = pro.enabled()
    if not enabled then pro.reset("inactive"); return end
    local n = cmd.command_number
    if pro.finite(n) and n > pro.state.last_command then
        pro.state.pending = n
        pro.state.choke = math.max(0, cmd.chokedcommands or 0)
    end
end)

client.set_event_callback("predict_command", function(cmd)
    local enabled, me = pro.enabled()
    if not enabled then pro.reset("inactive"); return end
    if not pro.state.pending or cmd.command_number ~= pro.state.pending then return end
    pro.state.pending = nil
    pro.observe(globals.tickcount(), entity.get_prop(me, "m_nTickBase"),
        cmd.command_number, pro.state.choke)
end)

function pro.blocked(cmd, me)
    local function pressed(v) return v == true or type(v) == "number" and v ~= 0 end
    if pressed(cmd.in_use) or pressed(cmd.in_attack) or pressed(cmd.in_attack2) then return "input" end
    if pro.duck and ui.get(pro.duck) then return "fake_duck" end
    local move = entity.get_prop(me, "m_MoveType")
    if move == 8 or move == 9 then return "ladder_or_noclip" end
    local flags = entity.get_prop(me, "m_fFlags") or 0
    if bit.band(flags, 64) ~= 0 then return "frozen" end
    local weapon = entity.get_player_weapon(me)
    if not weapon then return "no_weapon" end
    local class = entity.get_classname(weapon) or ""
    if class:find("Grenade", 1, true) or class:find("Molotov", 1, true)
        or class:find("Incendiary", 1, true) or class == "CC4" then return "utility" end
    if (entity.get_prop(weapon, "m_fThrowTime") or 0) > 0 then return "throwing" end
end

function pro.probe(me, need_peek)
    local s, tick = pro.state, globals.tickcount()
    if s.context and tick >= s.probe_tick and tick - s.probe_tick < 2
        and (not need_peek or s.context.peek_checked) then return s.context end
    s.probe_tick = tick
    local ctx = {peek=false, peek_checked=need_peek}
    s.context = ctx
    local x, y, z = client.eye_position()
    if not pro.finite(x) or not pro.finite(y) or not pro.finite(z) then return ctx end
    local enemies = {}
    for _, enemy in ipairs(entity.get_players(true)) do
        if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
            local ex, ey, ez = entity.hitbox_position(enemy, 0)
            if pro.finite(ex) and pro.finite(ey) and pro.finite(ez) then
                enemies[#enemies+1] = {id=enemy, x=ex, y=ey, z=ez, d=(ex-x)^2+(ey-y)^2+(ez-z)^2}
            end
        end
    end
    table.sort(enemies, function(a,b) return a.d < b.d end)
    if #enemies == 0 then return ctx end
    if not need_peek or type(client.trace_bullet) ~= "function"
        or type(client.trace_line) ~= "function" then return ctx end
    local vx = entity.get_prop(me, "m_vecVelocity[0]") or 0
    local vy = entity.get_prop(me, "m_vecVelocity[1]") or 0
    local vz = entity.get_prop(me, "m_vecVelocity[2]") or 0
    if not pro.finite(vx) or not pro.finite(vy) or not pro.finite(vz) or vx*vx+vy*vy < 625 then return ctx end
    local interval = globals.tickinterval()
    if not pro.finite(interval) or interval <= 0 then return ctx end
    local points = {}
    for _, horizon in ipairs({4,8}) do
        local dt = math.min(horizon, pro.capacity(0)) * interval
        local px, py, pz = x+vx*dt, y+vy*dt, z+vz*dt
        if bit.band(entity.get_prop(me,"m_fFlags") or 0,1) == 0 then
            pz = pz - 400*dt*dt
        end
        local ok, fraction = checked_call("pro.probe", client.trace_line, me,x,y,z,px,py,pz)
        if ok and pro.finite(fraction) then
            fraction = math.max(0,math.min(1,fraction)-0.02)
            points[#points+1] = {x+(px-x)*fraction,y+(py-y)*fraction,z+(pz-z)*fraction}
        end
    end
    local function exposed(enemy, sx,sy,sz, tx,ty,tz)
        local ok, hit, damage = checked_call("exposed", client.trace_bullet, me,sx,sy,sz,tx,ty,tz)
        return ok and hit == enemy and pro.finite(damage) and damage > 0
    end
    for i=1, math.min(3,#enemies) do
        local enemy, current, future = enemies[i].id, false, false
        for _, box in ipairs({0,4}) do
            local tx,ty,tz = entity.hitbox_position(enemy,box)
            if pro.finite(tx) and pro.finite(ty) and pro.finite(tz) then
                current = exposed(enemy,x,y,z,tx,ty,tz) or current
                for _, p in ipairs(points) do
                    future = exposed(enemy,p[1],p[2],p[3],tx,ty,tz) or future
                end
            end
        end
        if future and not current then ctx.peek = true; break end
    end
    return ctx
end

function pro.window(cmd, c)
    local s, tick = pro.state, globals.tickcount()
    local age = tick-s.seen
    local choke = math.max(0, cmd.chokedcommands or 0)
    local remaining = math.min(s.raw_left-math.max(0,age), s.deadline-tick, pro.capacity(choke))
    local valid = s.episode and not s.exhausted and age >= 0 and age <= 2
    local finish = math.min(s.deadline,
        (s.started or tick)+ui.get(c.def_duration), tick+remaining)
    if s.window then finish = math.min(finish,s.window_until) end
    if not valid or tick >= finish then
        if s.window or (s.episode and (age > 2 or tick >= finish)) then s.exhausted=true end
        s.window, s.window_until = false, -1
        s.reason = age > 2 and "stale" or s.episode and "guarded" or "waiting"
        return false, false, 0
    end
    local entered = not s.window
    s.window, s.window_until, s.reason = true, finish, "active"
    if entered then s.cache, s.phase, s.last_send = nil, 0, -1 end
    return true, entered, remaining
end

function pro.request(c, cmd, me)
    local s, tick = pro.state, globals.tickcount()
    local mode = ui.get(c.def_mode)
    if mode == "On peek" then
        local ctx = pro.probe(me,true)
        if ctx.peek then s.peek_until = tick + 7 end
        defensive_state.peeking = ctx.peek
    end
    local wanted = mode == "Always" or (mode == "On peek" and tick <= s.peek_until)
    if not wanted or s.episode then return end
    cmd.force_defensive = true
    defensive_state.request = true
    s.reason = "request"
end

function pro.custom_way_phase(c, cmd)
    local s = pro.state
    s.way_sequences = s.way_sequences or {}
    local count = math.max(1,math.min(10,ui.get(c.def_yaw_way_count) or 1))
    local sequence = s.way_sequences[c]
    if not sequence or sequence.count ~= count then
        sequence = {count=count, phase=0, last_command=-1}
        s.way_sequences[c] = sequence
    end
    local command = cmd.command_number or globals.tickcount()
    if (cmd.chokedcommands or 0) == 0 and pro.finite(command) and command > sequence.last_command then
        if sequence.last_command >= 0 then sequence.phase=(sequence.phase+1)%(count*2) end
        sequence.last_command = command
    end
    return sequence.phase
end

function pro.angles(c, cmd)
    local s = pro.state
    local command = cmd.command_number or globals.tickcount()
    local clean = (cmd.chokedcommands or 0) == 0
    if clean and command ~= s.last_send then
        if s.last_send >= 0 then s.phase=s.phase+1 end
        s.last_send=command
    end
    local phase = s.phase
    local key = defensive_config_key(c)..":"..ui.get(c.yaw_base)
    if not s.cache or clean and (s.phase_tick ~= phase or s.config_key ~= key) then
        local cache = {}
        cache.pitch_mode, cache.pitch = calc_def_pitch(ui.get(c.def_pitch),c,phase)
        local yaw_mode = ui.get(c.def_yaw)
        local yaw_phase = yaw_mode == "Custom Way" and pro.custom_way_phase(c,cmd) or phase
        cache.yaw = calc_def_yaw(yaw_mode,0,c,yaw_phase)
        cache.base = ui.get(c.yaw_base)
        if cache.yaw then cache.yaw=math.max(-179,math.min(179,normalize_yaw(cache.yaw))) end
        s.cache, s.phase_tick, s.config_key = cache, phase, key
    end
    local cache = s.cache
    if cache.pitch_mode then nset(N.pitch,cache.pitch_mode); nset(N.pitch_add,cache.pitch or 0) end
    if cache.yaw then nset(N.yaw_base,cache.base); nset(N.yaw,"180"); nset(N.yaw_add,defensive_yaw(cache.yaw,true)) end
    apply_defensive_body(c,phase)
    nset(N.fs_body,false); nset(N.edge_yaw,false)
end

function pro.apply(c, cmd, me)
    defensive_state.request, defensive_state.peeking = false, false
    if not c or not ui.get(c.force_def) or not pro.enabled() then
        pro.reset("disabled"); return false
    end
    local reason = pro.blocked(cmd,me)
    if reason then pro.reset(reason); return false end
    local tick = globals.tickcount()
    if tick < pro.state.seen then pro.reset("clock_discontinuity") end
    local active, entered = pro.window(cmd,c)
    pro.request(c,cmd,me)
    if not active then return false end
    if entered and ui.get(c.force_break) then cmd.allow_send_packet=true end
    pro.angles(c,cmd)
    return true
end

local function apply_defensive(c, cmd, me)
    local selected = tostring(ui.get(defensive_backend) or "")
    local backend = string.find(selected, "Ünoins_qucy Pro", 1, true) and "UnoinsPro"
        or string.find(selected, "Ünoins_qucy", 1, true) and "Unoins" or "Gamesense"
    if active_defensive_backend ~= backend then
        clear_defensive_timings(true)
        active_defensive_backend = backend
    end
    if backend == "Gamesense" then return apply_timed_defensive("Gamesense", c, cmd, me) end
    if backend == "Unoins" then return apply_timed_defensive("Unoins", c, cmd, me) end
    return pro.apply(c, cmd, me)
end

local function apply_backstab_safety()
    nset(N.pitch, "Down")
    nset(N.pitch_add, 0)
    nset(N.yaw_base, "At targets")
    nset(N.yaw, "180")
    nset(N.yaw_add, 180)
    nset(N.yaw_jitter, "Off")
    nset(N.yaw_jit_add, 0)
    nset(N.body_yaw, "Off")
    nset(N.body_yaw_add, 0)
    nset(N.fs_body, false)
    nset(N.edge_yaw, false)
end
local hitgroup_names = {
    [0] = "generic",
    [1] = "head",
    [2] = "chest",
    [3] = "stomach",
    [4] = "left arm",
    [5] = "right arm",
    [6] = "left leg",
    [7] = "right leg",
    [8] = "neck",
    [10] = "gear"
}

local function hitlog_value(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local function hitlog_backtrack(event)
    local api = tonumber(event and event.backtrack)
    local tick = tonumber(event and event.tick)
    local delta
    if tick then
        delta = globals.tickcount() - tick
        local limit = math.max(64, hitlog_value(1 / globals.tickinterval()))
        if delta < 0 or delta > limit then delta = nil end
    end
    if delta and delta > 0 then return hitlog_value(delta) end
    if api and api > 0 then return hitlog_value(api) end
    if delta == 0 or api == 0 then return 0 end
end

local function hitlog_hitgroup(value)
    if type(value) == "string" and value ~= "" then return value:lower() end
    return hitgroup_names[tonumber(value) or 0] or "generic"
end

local function finish_hitlog(event, result)
    local id = event and event.id
    local shot = id and hitlog_shots[id] or nil
    if id then hitlog_shots[id] = nil end
    if not shot or not ui.get(master) or not ui.get(hitlog_enabled) then return end
    if result == "Hit" then
        if event.damage ~= nil then shot.damage = event.damage end
        if event.hitgroup ~= nil then shot.hitgroup = event.hitgroup end
    end
    local name = shot.target and entity.get_player_name(shot.target)
    if not name or name == "" then name = tostring(shot.target or "unknown") end
    client.log(string.format(
        "Ünoins_qucy~ %s %s in the %s for %d(bt:%s hc:%d)",
        result,
        name,
        hitlog_hitgroup(shot.hitgroup),
        hitlog_value(shot.damage),
        shot.backtrack == nil and "N/A" or tostring(shot.backtrack),
        hitlog_value(shot.hit_chance)
    ))
end
local rh_data, rh_shots = {}, {}
local rh_factors = { 1, -1, 0.5, -0.5, 0 }
local rh_enabled_last = false

local function rh_reset_player(idx)
    rh_data[idx] = {
        memory_id = nil,
        misses = 0,
        side = 1,
        brute_idx = 1,
        last_simtime = nil,
        last_eye_yaw = nil,
        jitter_score = 0,
        jitter_sign = 1,
        applied_yaw = nil,
        override_active = false
    }
end

local function rh_clear_override(idx)
    local d = rh_data[idx]
    if not d or not d.override_active then return true end
    d.restore_pending = true
    if d.owner ~= nil and type(entity.get_steam64) == "function" then
        local ok, owner = checked_call("resolver restore identity", entity.get_steam64, idx)
        if not ok or owner == nil then return false end
        if owner ~= d.owner then
            client.error_log("[Ünoins_qucy] Resolver restore skipped: player identity changed; new player left untouched.")
            d.override_active, d.restore_pending, d.applied_yaw = false, nil, nil
            return true
        end
    end
    if not plist or type(plist.set) ~= "function" or type(plist.get) ~= "function" then return false end
    local restored = true
    local function restore(key, value)
        local ok = checked_call("restore resolver " .. key, function()
            plist.set(idx, key, value)
            assert(plist.get(idx, key) == value, "restore readback mismatch")
        end)
        restored = ok and restored
    end
    if d.original_yaw_ok then restore("Force body yaw value", d.original_yaw) end
    restore("Force body yaw", d.original_force_ok and d.original_force or false)
    if d.original_correction_ok then restore("Correction active", d.original_correction) end
    if not restored then return false end
    d.applied_yaw, d.restore_pending = nil, nil
    d.override_active = false
    return true
end

local function rh_apply_override(idx, yaw)
    if not plist or type(plist.set) ~= "function" then return false end
    local d = rh_data[idx]
    if not d then return false end
    if d.restore_pending and not rh_clear_override(idx) then return false end
    yaw = math.max(-60, math.min(60, yaw or 0))
    yaw = yaw >= 0 and math.floor(yaw + 0.5) or math.ceil(yaw - 0.5)
    if d.override_active and d.applied_yaw == yaw then return true end
    if not d.override_active then
        local ok, force, value, correction = checked_call("rh_apply_override", function()
            return plist.get(idx, "Force body yaw"), plist.get(idx, "Force body yaw value"), plist.get(idx, "Correction active")
        end)
        if not ok or type(force) ~= "boolean"
            or type(value) ~= "number" or type(correction) ~= "boolean" then return false end
        d.owner = type(entity.get_steam64) == "function" and entity.get_steam64(idx) or nil
        d.original_force_ok, d.original_force = true, force
        d.original_yaw_ok, d.original_yaw = true, value
        d.original_correction_ok, d.original_correction = true, correction
    end
    d.override_active = true
    local ok = checked_call("rh_apply_override", function()
        plist.set(idx, "Correction active", true)
        plist.set(idx, "Force body yaw value", yaw)
        plist.set(idx, "Force body yaw", true)
    end)
    if ok then
        d.applied_yaw = yaw
        d.override_active = true
        return true
    end
    rh_clear_override(idx)
    return false
end

local function rh_clear_all()
    for idx, d in pairs(rh_data) do
        if rh_clear_override(idx) then rh_data[idx] = nil else d.discard = true end
    end
    rh_shots = {}
end

local function rh_release_all()
    for idx in pairs(rh_data) do rh_clear_override(idx) end
    rh_shots = {}
end
local rh_restore_time
client.set_event_callback("paint_ui", function()
    local now = globals.realtime()
    if rh_restore_time and now >= rh_restore_time and now-rh_restore_time < 0.5 then return end
    rh_restore_time = now
    for idx, d in pairs(rh_data) do
        if d.restore_pending and rh_clear_override(idx) and d.discard then rh_data[idx] = nil end
    end
end)
ui.set_callback(rh_enabled, function()
    if not ui.get(rh_enabled) then
        rh_clear_all()
        rh_enabled_last = false
    end
    update_vis()
end)

local function rh_magnitude(idx)
    local flags = entity.get_prop(idx, "m_fFlags") or 0
    if bit.band(flags, 1) == 0 then return 29 end
    local vx = entity.get_prop(idx, "m_vecVelocity[0]") or 0
    local vy = entity.get_prop(idx, "m_vecVelocity[1]") or 0
    return math.max(29, 58 - math.sqrt(vx * vx + vy * vy) * 0.116)
end

local function rh_gamesense_side(idx)
    local pose = entity.get_prop(idx, "m_flPoseParameter", 11)
    if not pro.finite(pose) then return 1 end
    return pose * 120 - 60 >= 0 and 1 or -1
end

local function rh_feedback(e)
    local shot = e.id and rh_shots[e.id]
    if e.id then rh_shots[e.id] = nil end
    if not shot or (e.target and e.target ~= shot.target) then return end
    local d = rh_data[shot.target]
    local now = globals.realtime()
    if not d or d ~= shot.state or now - shot.time > 2 or now < shot.time then return end
    return d, shot
end

local function rh_update_player(idx)
    if not rh_data[idx] then rh_reset_player(idx) end
    local d = rh_data[idx]
    if type(entity.get_steam64) == "function" then
        local ok, id = checked_call("resolver identity", entity.get_steam64, idx)
        if ok and id ~= nil then
            if d.memory_id ~= nil and d.memory_id ~= id then
                if not rh_clear_override(idx) then return end
                rh_reset_player(idx)
                d = rh_data[idx]
            end
            d.memory_id = id
        end
    end
    if not entity.is_alive(idx) or entity.is_dormant(idx) then
        d.last_simtime, d.last_eye_yaw = nil, nil
        rh_clear_override(idx)
        return
    end
    local simtime = entity.get_prop(idx, "m_flSimulationTime")
    if simtime and d.last_simtime ~= simtime then
        local _, eye_yaw = entity.get_prop(idx, "m_angEyeAngles")
        if eye_yaw and d.last_eye_yaw and d.last_simtime and simtime > d.last_simtime then
            local delta = normalize_yaw(eye_yaw - d.last_eye_yaw)
            if math.abs(delta) >= 20 then
                d.jitter_score = math.min(4, d.jitter_score + 1)
                d.jitter_sign = delta > 0 and 1 or -1
            else
                d.jitter_score = math.max(0, d.jitter_score - 0.5)
            end
        end
        d.last_eye_yaw, d.last_simtime = eye_yaw, simtime
    end
    if d.misses == 0 then
        rh_clear_override(idx)
        return
    end
    local sign = d.side * (d.jitter_score >= 2 and d.jitter_sign or 1)
    rh_apply_override(idx, rh_factors[d.brute_idx] * sign * rh_magnitude(idx))
end

local function rh_run()
    local now = globals.realtime()
    for id, shot in pairs(rh_shots) do
        if now - shot.time > 2 or now < shot.time then rh_shots[id] = nil end
    end
    local seen = {}
    for _, idx in ipairs(entity.get_players(true)) do
        seen[idx] = true
        rh_update_player(idx)
    end
    for idx, d in pairs(rh_data) do
        if not seen[idx] then
            d.last_simtime, d.last_eye_yaw = nil, nil
            rh_clear_override(idx)
        end
    end
end

client.set_event_callback("net_update_end", function()
    local me = entity.get_local_player()
    if ui.get(master) and ui.get(rh_enabled) and me and entity.is_alive(me) then
        rh_enabled_last = true
        rh_run()
    elseif rh_enabled_last then
        rh_release_all()
        rh_enabled_last = false
    end
end)

client.set_event_callback("aim_fire", function(e)
    if ui.get(master) and ui.get(hitlog_enabled) and e and e.id and e.target then
        hitlog_shots[e.id] = {
            target = e.target,
            hitgroup = e.hitgroup,
            damage = e.damage,
            backtrack = hitlog_backtrack(e),
            hit_chance = e.hit_chance
        }
    end
    if not ui.get(master) or not ui.get(rh_enabled) or not e.id or not e.target then return end
    if not rh_data[e.target] then rh_reset_player(e.target) end
    local d = rh_data[e.target]
    rh_shots[e.id] = {
        target = e.target,
        state = d,
        time = globals.realtime(),
        overridden = d.override_active and d.applied_yaw ~= nil,
        brute_idx = d.brute_idx,
        gs_side = rh_gamesense_side(e.target),
        jitter = d.jitter_score >= 2,
        jitter_sign = d.jitter_sign
    }
end)

client.set_event_callback("aim_hit", function(e)
    finish_hitlog(e, "Hit")
    if not ui.get(master) or not ui.get(rh_enabled) then return end
    rh_feedback(e)
end)

client.set_event_callback("aim_miss", function(e)
    finish_hitlog(e, "Miss")
    if not ui.get(master) or not ui.get(rh_enabled) then return end
    local d, shot = rh_feedback(e)
    if not d or e.reason ~= "?" then return end
    if not shot.overridden or d.misses == 0 then
        d.side = -shot.gs_side * (shot.jitter and shot.jitter_sign or 1)
        d.brute_idx = 1
    else
        d.brute_idx = shot.brute_idx % #rh_factors + 1
    end
    d.misses = d.misses + 1
end)

client.set_event_callback("player_death", function(e)
    local idx = e and e.userid and client.userid_to_entindex(e.userid) or nil
    if idx and rh_data[idx] then rh_clear_override(idx) end
end)

client.set_event_callback("level_init", function()
    hitlog_shots = {}
    rh_clear_all()
end)

client.set_event_callback("round_prestart", function()
    hitlog_shots = {}
    rh_release_all()
end)

local ladder_started = false

local function fast_ladder_command(cmd, me)
    if (entity.get_prop(me, "m_MoveType") or 0) ~= 9 or (cmd.forwardmove or 0) == 0 then
        ladder_started = false
        return
    end
    local weapon = entity.get_player_weapon(me)
    if weapon and (entity.get_prop(weapon, "m_fThrowTime") or 0) ~= 0 then return end
    if not ladder_started then
        ladder_started = true
        return
    end
    local pitch = client.camera_angles()
    local down = cmd.forwardmove < 0 or (pitch or 0) > 45
    cmd.in_moveleft, cmd.in_moveright = down and 1 or 0, down and 0 or 1
    cmd.in_forward, cmd.in_back = down and 1 or 0, down and 0 or 1
    cmd.pitch = 89
    cmd.yaw = normalize_yaw((cmd.move_yaw or cmd.yaw or 0) + 90)
end

local function apply_micromovement(me, cmd)
    if not me or not entity.is_alive(me) then return end
    local flags = entity.get_prop(me, "m_fFlags") or 0
    local on_gnd = bit.band(flags, 1) ~= 0
    if not on_gnd then return end
    local movetype = entity.get_prop(me, "m_MoveType") or 0
    if movetype == 9 then return end
    local gamerules = entity.get_game_rules()
    if gamerules and (entity.get_prop(gamerules, "m_bFreezePeriod") == 1) then return end
    if cmd.in_forward == 1 or cmd.in_back == 1 or cmd.in_moveleft == 1 or cmd.in_moveright == 1 then
        return
    end
    local vx = entity.get_prop(me, "m_vecVelocity[0]") or 0
    local vy = entity.get_prop(me, "m_vecVelocity[1]") or 0
    local speed_sqr = vx * vx + vy * vy
    if speed_sqr > 400 then return end
    if cmd.in_attack == 1 or cmd.in_attack2 == 1 or cmd.in_use == 1 then return end
    local duck_amount = entity.get_prop(me, "m_flDuckAmount") or 0
    local move_val = (duck_amount > 0) and 3.3 or 1.1
    local cmd_num = cmd.command_number or 0
    local side = (cmd_num % 2 == 0) and move_val or -move_val
    cmd.sidemove = side
end

client.set_event_callback("setup_command", function(cmd)
    aa_cancel()
    if not ui.get(master) then
        current_layer = "disabled"
        extras.native_set("moving_hitchance",extras.hitchance_ref,nil)
        return
    end
    capture_native()
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        if rh_enabled_last then
            rh_clear_all()
            rh_enabled_last = false
        end
        freestand_requested = false
        apply_native_freestand(false)
        reset_defensive_state()
        current_layer = "dead"
        extras.native_set("moving_hitchance",extras.hitchance_ref,nil)
        return
    end
    extras.pre_command(cmd, me)
    if ui.get(fast_ladder) then fast_ladder_command(cmd, me) end
    defensive_state.choked = cmd.chokedcommands or 0
    update_manual()
    local move_cond
    current_cond, move_cond = get_condition(me, cmd)
    extras.hitchance_control()
    update_aa_sequence(cmd)
    slow_pro.update(cmd, me)
    aa_begin(current_cond == "manual" and 70 or freestand_requested and 85 or 10)
    local c = apply_condition(current_cond, move_cond, cmd)
    local safe_head_active = move_cond == "Air+" and safe_head_selected(me)
    if current_cond == "manual" then
        if safe_head_active then
            aa_owner(90)
            apply_safe_head(cmd)
            current_layer = "safe_head"
        else
            defensive_state.request = false
            defensive_state.peeking = false
            clear_defensive_timings(true)
            current_layer = "manual"
        end
    else
        local knife_threat = find_backstab_threat(me)
        if knife_threat then
            defensive_state.request = false
            clear_defensive_timings(true)
            aa_owner(100)
            apply_backstab_safety()
            current_layer = "safety"
        elseif safe_head_active then
            aa_owner(90)
            apply_safe_head(cmd)
            current_layer = "safe_head"
        else
            aa_owner(88)
            local defensive_active = apply_defensive(c, cmd, me)
            if defensive_active then
                current_layer = "defensive"
            elseif freestand_requested then
                current_layer = "freestand"
            elseif defensive_state.request then
                current_layer = "request"
            else
                current_layer = "normal"
            end
        end
    end
    aa_commit()
    apply_native_freestand(
        freestand_requested
        and current_cond ~= "manual"
        and current_layer ~= "safety"
    )
    apply_micromovement(me, cmd)
    extras.post_command(cmd, me)
end)
local clan_full_strs = {
    ["Half-life.beta"] = "Half-life.lua",
    ["Ünoins_qucy"] = "Ünoins_qucy",
    ["gamesense"] = "gamesense",
    ["Ideal Yaw"] = "Ideal Yaw",
}
local clan_idx, clan_dir, clan_timer, prev_clan_mode, current_clan_tag = 1, 1, 0, "Off", nil

local function set_script_clan_tag(tag)
    if tag == "" and current_clan_tag == nil then return end
    if current_clan_tag == tag then return end
    client.set_clan_tag(tag)
    current_clan_tag = tag ~= "" and tag or nil
end

client.set_event_callback("net_update_start", function()
    if not ui.get(master) then return end
    local clan_mode = ui.get(clan_tag_sel)
    if clan_mode ~= prev_clan_mode then clan_idx = 1; clan_dir = 1; clan_timer = 0; prev_clan_mode = clan_mode end
    if clan_mode == "Off" then set_script_clan_tag(""); return end
    local full = clan_full_strs[clan_mode] if not full then set_script_clan_tag(""); return end
    clan_timer = clan_timer + 1
    if clan_timer < 20 then return end
    clan_timer = 0
    local chars = {}
    for char in full:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1] = char end
    local tag = table.concat(chars, "", 1, clan_idx)
    set_script_clan_tag(tag)
    clan_idx = clan_idx + clan_dir
    if clan_idx >= #chars then clan_dir = -1
    elseif clan_idx <= 1 then clan_dir = 1 end
end)
master_cleanup = function()
    restore_tp_viewmodel()
    rh_clear_all()
    rh_enabled_last = false
    reset_aa_sequence()
    reset_defensive_state()
    last_fl.on, last_fl.mode, last_fl.limit = false, "", 0
    current_layer = "disabled"
    clan_idx, clan_dir, clan_timer, prev_clan_mode = 1, 1, 0, "Off"
    set_script_clan_tag("")
end
local cond_colors = {
    ["Standing"] = {255, 238, 140},
    ["Moving"] = {255, 213, 79},
    ["Air"] = {255, 193, 7},
    ["Air+"] = {255, 152, 0},
    ["Duck"] = {255, 204, 128},
    ["Duck move"] = {255, 183, 77},
    ["manual"] = {255, 224, 100},
    ["Global"] = {235, 230, 210},
    ["Freestanding"] = {255, 167, 38},
    ["Slowwalk"] = {255, 224, 130},
}
local manual_dir = { left = "< LEFT", right = "RIGHT >", forward = "^ FORWARD" }

local function draw_min_damage()
    if not ui.get(dmg_indicator) then return end
    local me = entity.get_local_player() if not me or not entity.is_alive(me) then return end
    local dmg
    if hl_ref.md and hl_ref.md[2] and ui.get(hl_ref.md[2]) then dmg = hl_ref.md[3] and ui.get(hl_ref.md[3]) end
    if not dmg and hl_ref.mindmg and hl_ref.mindmg[1] then dmg = ui.get(hl_ref.mindmg[1]) end
    if not dmg then return end
    local w, h = client.screen_size()
    renderer.text(w / 2 + 10, h / 2 - 17, 255, 255, 255, 255, "b", 0, tostring(dmg))
end

client.set_event_callback("paint", function()
    if not ui.get(master) then return end
    local me = entity.get_local_player() if not me or not entity.is_alive(me) then return end
    draw_min_damage()
    if has_trigger(indicator_sel, "Ünoins_qucy") then
        local w, h = client.screen_size()
        local cr, cg, cb, ca = 255, 245, 157, 255
        local col = cond_colors[current_cond] or {255, 245, 157}
        local bx, by = 14, math.floor(h / 2 - 10)
        local label = current_cond:upper()
        if current_cond == "manual" then label = (manual_dir[manual_mode] or "MANUAL"):upper() end
        local show_group = ui.get(ind_groupname)
        local icon = 18
        renderer.rectangle(bx, by, icon, icon, 0, 0, 0, 200)
        renderer.rectangle(bx+1, by+1, icon-2, icon-2, col[1], col[2], col[3], 60)
        renderer.rectangle(bx+5, by+5, icon-10, icon-10, col[1], col[2], col[3], 255)
        renderer.rectangle(bx, by, icon, 1, cr, cg, cb, ca)
        renderer.rectangle(bx, by+icon-1, icon, 1, cr, cg, cb, ca)
        renderer.rectangle(bx, by, 1, icon, cr, cg, cb, ca)
        renderer.rectangle(bx+icon-1, by, 1, icon, cr, cg, cb, ca)
        local tx = bx + icon + 6
        if show_group then
            renderer.text(tx, by - 1, cr, cg, cb, ca, "b", 0, "ÜNOINS_QUCY")
            renderer.text(tx, by + 9, col[1], col[2], col[3], 255, nil, 0, label)
        else
            renderer.text(tx, by + 4, col[1], col[2], col[3], 255, "b", 0, label)
        end
        local flags = {}
        if current_layer == "safety" then
            flags[#flags+1] = "KNIFE"
        elseif current_layer == "defensive" then
            local timing = active_defensive_backend and defensive_timing[active_defensive_backend]
            local left = timing and math.max(0, timing.window_until - globals.tickcount()) or 0
            flags[#flags+1] = (active_defensive_backend == "UnoinsPro" and "PRO " or "DEF ") .. tostring(left)
        elseif current_layer == "request" then
            flags[#flags+1] = defensive_state.peeking and "PEEK" or "DEF READY"
        end
        if freestand_applied then
            flags[#flags+1] = "FS"
        end
        if edge_active and current_layer == "normal" then
            flags[#flags+1] = "EDGE"
        end
        if #flags > 0 then
            local fy = show_group and (by + 9) or (by + 4)
            local fw = renderer.measure_text(nil, label) or 40
            local is_pro = active_defensive_backend == "UnoinsPro"
            renderer.text(tx + fw + 8, fy, 255, is_pro and 156 or 179, is_pro and 156 or 71, 230, nil, 0, table.concat(flags, " "))
        end
    end
    local now = globals.realtime()
    local dk = hl_active(hl_ref.dt)
    if dk and not hl_dt_wh then hl_dt_st, hl_dt_lc = "lc", now + 0.25
    elseif not dk and hl_dt_wh then hl_dt_st, hl_dt_lc = "lc", now + 0.25
    elseif hl_dt_st == "lc" and now >= hl_dt_lc then hl_dt_st = dk and "active" or "off" end
    hl_dt_wh = dk
    if has_trigger(indicator_sel, "Half-life") then
        local sw, sh = client.screen_size()
        local cx, sy = sw * 0.5, sh * 0.52
        local b_on, m_on, o_on = hl_active(hl_ref.baim), hl_active(hl_ref.md), hl_active(hl_ref.os)
        local bt = (math.sin(now * 2.5) + 1) * 0.5
        local br, bg, bb = math.floor(130 + bt * 100), math.floor(100 + bt * 80), math.floor(70 + bt * 70)
        local function S(t, r, g, b, a) return {text = t, r = r, g = g, b = b, a = a or 255} end
        local dc, da
        if hl_dt_st == "active" then dc, da = {110, 200, 70}, 255
        elseif hl_dt_st == "lc" then dc, da = {255, 0, 0}, 255
        else dc, da = {255, 255, 255}, 80 end
        local L = {
            { S("HALF-LIFE", 255, 255, 255), S(" BETA", br, bg, bb) },
            { S("BODY YAW: ", 255, 255, 255), S(body_yaw(), 255, 255, 255) },
            { S("DT", dc[1], dc[2], dc[3], da) },
            { S("BAIM", 255, 255, 255, b_on and 255 or 80), S(" MD", 255, 255, 255, m_on and 255 or 80), S(" OS", 255, 255, 255, o_on and 255 or 80) },
        }
        local _, lh = renderer.measure_text("-", "X")
        local ls, sg, y = 1.2, 1.2, sy
        for _, segs in ipairs(L) do
            local x = cx
            for _, s in ipairs(segs) do
                renderer.text(x, y, s.r, s.g, s.b, s.a, "-", 0, s.text)
                x = x + renderer.measure_text("-", s.text) + sg
            end
            y = y + lh + ls
        end
    end
    if has_trigger(indicator_sel, "Ideal yaw") then
        local sw, sh = client.screen_size()
        local cx, cy = sw / 2, sh / 2
        renderer.text(cx, cy + 40, 215, 114, 44, 255, "", 0, "IDEAL YAW")
        renderer.text(cx, cy + 50, 199, 132, 216, 255, "", 0, "DYNAMIC")
        if hl_dt_st == "active" then renderer.text(cx, cy + 60, 10, 245, 5, 255, "", 0, "DT")
        elseif hl_dt_st == "lc" then renderer.text(cx, cy + 60, 245, 10, 5, 255, "", 0, "DT") end
    end
end)

client.set_event_callback("shutdown", function()
    extras.cleanup()
    restore_tp_viewmodel()
    hitlog_shots = {}
    rh_clear_all()
    reset_native()
    invalidate_freestand_controller()
    reset_aa_sequence()
    reset_defensive_state()
    native_visible(true)
    set_script_clan_tag("")
end)

extras.hitchance_ref = safe_ref("RAGE", "Aimbot", "Minimum hit chance")
extras.scope_ref = safe_ref("VISUALS", "Effects", "Remove scope overlay")
extras.legs_ref = safe_ref(TAB, "Other", "Leg movement")
extras.hotkey_modes = {"Always on", "On hotkey", "Toggle", "Off hotkey"}
extras.effect_groups = {
    Blood={violence_hblood=0}, Bloom={mat_disable_bloom=1}, Decals={r_drawdecals=0},
    Shadows={r_shadows=0, cl_csm_static_prop_shadows=0, cl_csm_shadows=0},
    Ropes={r_drawropes=0}, Debris={func_break_max_pieces=0, props_break_max_pieces=0},
    ["Weapon effects"]={muzzleflash_light=0, r_drawtracers_firstperson=0}
}
extras.grenades = {CHEGrenade="HE", CSmokeGrenade="Smoke", CMolotovGrenade="Fire", CIncendiaryGrenade="Fire", CFlashbang="Flash", CDecoyGrenade="Decoy"}

extras.finite = pro.finite

function extras.live()
    local me = entity.get_local_player()
    return ui.get(master) and me and entity.is_alive(me), me
end

function extras.has(ref, name)
    for _, value in ipairs(ui.get(ref) or {}) do if value == name then return true end end
    return false
end

function extras.pressed(value)
    return value == true or type(value) == "number" and value ~= 0
end

function extras.cvar_set(key, name, value)
    local saved = extras.cvars[key]
    local cv = saved and saved.ref or cvar and cvar[name]
    if not cv then return false end
    local ok, current = checked_call("extras.cvar_set", function() return cv:get_string() end)
    if not ok or current == nil then
        if saved and value == nil then saved.restore_pending = true end
        return false
    end
    current = tostring(current)
    if value == nil then
        if saved and current == saved.written then
            saved.restore_pending = true
            local restored = checked_call("restore cvar " .. key, function()
                cv:set_string(saved.before)
                assert(tostring(cv:get_string()) == saved.before, "restore readback mismatch")
            end)
            if not restored then return false end
        end
        extras.cvars[key] = nil
        return true
    end
    local wanted = tostring(value)
    if saved then saved.restore_pending = nil end
    if not saved then saved = {ref=cv, before=current}; extras.cvars[key] = saved
    elseif saved.written and current ~= saved.written then saved.before = current end
    if current ~= wanted then
        ok = checked_call("extras.cvar_set", function()
            if type(value) == "number" then cv:set_int(value) else cv:set_string(value) end
        end)
        if not ok then return false end
    end
    local read_ok, written = checked_call("extras.cvar_set", function() return cv:get_string() end)
    if read_ok and written ~= nil then saved.written = tostring(written) end
    return read_ok and saved.written == wanted
end

function extras.native_set(key, ref, value)
    local saved = extras.native[key]
    ref = saved and saved.ref or ref
    if not ref then return false end
    local current = ui.get(ref)
    if value == nil then
        if saved and current == saved.written then ui.set(ref, saved.before) end
        extras.native[key] = nil
        return true
    end
    if not saved then saved={ref=ref, before=current}; extras.native[key]=saved
    elseif current ~= saved.written then saved.before=current end
    if current ~= value then ui.set(ref, value) end
    saved.written=value
    return true
end

function extras.hitchance_dt_off()
    local ref=hl_ref.dt
    if not ref or not ref[1] then return false end
    local ok,enabled=checked_call("extras.hitchance_dt_off", ui.get,ref[1])
    if not ok or type(enabled)~="boolean" then return false end
    if not enabled then return true end
    if not ref[2] then return false end
    local key_ok,active=checked_call("extras.hitchance_dt_off", ui.get,ref[2])
    return key_ok and active==false
end

extras.release_weapons = {[40]="SSG 08", [38]="SCAR-20", [11]="G3SG1", [9]="AWP", [1]="Desert Eagle", [64]="R8 Revolver"}

function extras.weapon_id(me)
    local weapon=entity.get_player_weapon(me)
    if not weapon or weapon==0 then return end
    local id=entity.get_prop(weapon,"m_iItemDefinitionIndex")
    if not extras.finite(id) or id%1~=0 then return end
    return bit.band(id,0xFFFF),weapon
end

function extras.hitchance_control()
    local live,me=extras.live()
    local id,weapon
    if live and (ui.get(extras.ui.move_hitchance) or ui.get(extras.ui.noscope_hitchance)) then id,weapon=extras.weapon_id(me) end
    local name=extras.release_weapons[id]
    local wanted=live and name and ui.get(extras.ui.move_hitchance)
        and extras.has(extras.ui.move_hitchance_weapons,name) and current_cond=="Moving"
    if wanted then
        local vx,vy=entity.get_prop(me,"m_vecVelocity[0]"),entity.get_prop(me,"m_vecVelocity[1]")
        local flags,move=entity.get_prop(me,"m_fFlags"),entity.get_prop(me,"m_MoveType")
        local duck=entity.get_prop(me,"m_flDuckAmount")
        wanted=extras.finite(vx) and extras.finite(vy) and vx*vx+vy*vy>25
            and extras.finite(flags) and bit.band(flags,1)~=0 and bit.band(flags,64)==0
            and move~=8 and move~=9 and extras.finite(duck) and duck~=1
            and not (slow_key and ui.get(slow_key)) and extras.hitchance_dt_off()
    end
    local value
    if wanted then
        value=ui.get(extras.ui.move_hitchance_value)
    elseif live and ui.get(extras.ui.noscope_hitchance) and extras.noscope_profiles[id] then
        local zoom=entity.get_prop(weapon,"m_zoomLevel")
        if extras.finite(zoom) and zoom>=0 then
            local profile=extras.noscope_profiles[id]
            value=ui.get(zoom==0 and profile.unscoped or profile.scoped)
            if value==-1 then value=nil end
        end
    end
    extras.native_set("moving_hitchance",extras.hitchance_ref,value)
end

function extras.restore_fd()
    local saved = extras.fd
    if not saved then return end
    local _, mode, key = ui.get(pro.duck)
    if mode == 1 and key == 0 then ui.set(pro.duck, extras.hotkey_modes[saved.mode+1], saved.key) end
    extras.fd = nil
end

function extras.pose_restore()
    local me = entity.get_local_player()
    for index, saved in pairs(extras.pose) do
        if me == saved.me and entity.is_alive(me) and type(entity.set_prop) == "function" then
            local value = entity.get_prop(me, "m_flPoseParameter", index)
            if extras.finite(value) and math.abs(value-saved.written) < 0.00001 then
                entity.set_prop(me, "m_flPoseParameter", saved.before, index)
            end
        end
    end
    extras.pose = {}
end

function extras.cleanup()
    extras.pose_restore()
    extras.restore_fd()
    for key, saved in pairs(extras.cvars) do extras.cvar_set(key, nil, nil) end
    for key, saved in pairs(extras.native) do extras.native_set(key, nil, nil) end
    extras.drop, extras.velocity = {}, {}
    extras.velocity_preview = nil
    extras.velocity_visual = nil
    extras.scope_alpha, extras.stop_reason, extras.was_ground, extras.land_until = 0, "disabled", nil, nil
    last_fl.on = nil
end

function extras.sync()
    if extras.config_loading then return end
    for key, saved in pairs(extras.cvars) do
        if saved.restore_pending then extras.cvar_set(key, nil, nil) end
    end
    extras.hitchance_control()
    local live = extras.live()
    local wanted = {}
    if live and ui.get(extras.ui.fps) then
        for _, group in ipairs(ui.get(extras.ui.fps_groups)) do
            for name, value in pairs(extras.effect_groups[group] or {}) do
                local key = "fps:"..name
                wanted[key] = true
                extras.cvar_set(key, name, value)
            end
        end
    end
    for key in pairs(extras.cvars) do
        if key:sub(1,4) == "fps:" and not wanted[key] then extras.cvar_set(key, nil, nil) end
    end
    if live and ui.get(extras.ui.console) then
        extras.cvar_set("console:text", "con_filter_text", "gamesense")
        extras.cvar_set("console:enable", "con_filter_enable", 1)
    else
        extras.cvar_set("console:enable", "con_filter_enable", nil)
        extras.cvar_set("console:text", "con_filter_text", nil)
    end
    if not live or not ui.get(extras.ui.duck_fd) then extras.restore_fd() end
    if not live or not ui.get(extras.ui.drop) then extras.drop = {} end
    if not live or not ui.get(extras.ui.anim) then
        extras.pose_restore(); extras.native_set("legs", extras.legs_ref, nil)
        extras.was_ground, extras.land_until = nil, nil
    end
    if not live or not ui.get(extras.ui.scope) then
        extras.native_set("scope", extras.scope_ref, nil)
        extras.scope_alpha = 0
    end
    if not live or not ui.get(extras.ui.velocity) then extras.velocity = {} end
    if not ui.get(master) or not ui.get(extras.ui.velocity) then extras.velocity_preview = nil end
end

function extras.onshot()
    return extras.live() and ui.get(extras.ui.onshot) and hl_active(hl_ref.os)
        and not hl_active(hl_ref.dt) and not (pro.duck and ui.get(pro.duck))
end

function extras.duck_command(cmd, me)
    local wanted = ui.get(extras.ui.duck_fd) and pro.duck and not ui.is_menu_open()
        and extras.pressed(cmd.in_duck) and bit.band(entity.get_prop(me,"m_fFlags") or 0,1) ~= 0
        and (entity.get_prop(me,"m_flDuckAmount") or 0) > 0.75
    if not wanted then extras.restore_fd(); return end
    if extras.fd then return end
    local active, mode, key = ui.get(pro.duck)
    if active and extras.hotkey_modes[(tonumber(mode) or -1)+1] and type(key) == "number" then
        ui.set(pro.duck, "On hotkey", 0)
        extras.fd = {mode=mode, key=key}
    end
end

function extras.inventory(me)
    local result, seen = {}, {}
    for index=0,63 do
        local handle = entity.get_prop(me,"m_hMyWeapons",index)
        if extras.finite(handle) and handle > 0 then
            local ent = bit.band(handle,4095)
            local kind = extras.grenades[entity.get_classname(ent) or ""]
            if ent > 0 and kind and not seen[ent] and extras.has(extras.ui.drop_types,kind) then
                result[#result+1] = {ent=ent, kind=kind}; seen[ent]=true
            end
        end
    end
    return result
end

function extras.drop_command(cmd, me)
    local active = ui.get(extras.ui.drop) and ui.get(extras.ui.drop_key)
    local tick, weapon = globals.tickcount(), entity.get_player_weapon(me)
    local safe = active and not ui.is_menu_open() and not extras.pressed(cmd.in_attack)
        and not extras.pressed(cmd.in_attack2) and not extras.pressed(cmd.in_use)
        and weapon and (entity.get_prop(weapon,"m_fThrowTime") or 0) <= 0
    local s = extras.drop
    if not safe then extras.drop = {held=active}; return end
    if not s.held then s.queue, s.next_tick, s.started = extras.inventory(me), tick, tick end
    s.held = active
    if s.last_command == cmd.command_number then return end
    s.last_command = cmd.command_number
    if tick < (s.started or tick) or tick-(s.started or tick) > 96 then extras.drop={held=active}; return end
    if tick < (s.next_tick or 0) or not s.queue or #s.queue == 0 then return end
    local item = s.queue[1]
    local owned = false
    for _, entry in ipairs(extras.inventory(me)) do if entry.ent == item.ent and entry.kind == item.kind then owned=true end end
    if not owned or s.select_tick and tick-s.select_tick > 16 then
        table.remove(s.queue,1); s.select_tick=nil; return
    end
    if weapon ~= item.ent then
        cmd.weaponselect = item.ent
        s.select_tick = s.select_tick or tick
        return
    end
    client.exec("drop")
    table.remove(s.queue,1)
    s.select_tick, s.next_tick = nil, tick+4
end

function extras.stop_command(cmd, me)
    extras.stop_reason = "idle"
    if not ui.get(extras.ui.autostop) or ui.is_menu_open() then return end
    local flags, move = entity.get_prop(me,"m_fFlags") or 0, entity.get_prop(me,"m_MoveType")
    if bit.band(flags,1) == 0 or bit.band(flags,64) ~= 0 or move == 8 or move == 9
        or extras.pressed(cmd.in_jump) or extras.pressed(cmd.in_use) or extras.pressed(cmd.in_attack2)
        or pro.duck and ui.get(pro.duck) or extras.drop.queue and #extras.drop.queue > 0 then return end
    local weapon = entity.get_player_weapon(me)
    local class = weapon and entity.get_classname(weapon) or ""
    if not weapon or class == "CC4" or class:find("Knife",1,true) or class == "CWeaponTaser"
        or extras.grenades[class] then return end
    local clip = entity.get_prop(weapon,"m_iClip1")
    if not extras.finite(clip) or clip <= 0 or extras.pressed(entity.get_prop(weapon,"m_bInReload")) then return end
    local tb, interval = entity.get_prop(me,"m_nTickBase"), globals.tickinterval()
    if not extras.finite(tb) or not extras.finite(interval) or interval <= 0 then return end
    local ready = math.max(entity.get_prop(me,"m_flNextAttack") or 0, entity.get_prop(weapon,"m_flNextPrimaryAttack") or 0)
    if ready > tb*interval+interval then return end
    local _, camera_yaw = client.camera_angles()
    if not extras.finite(camera_yaw) then return end
    local wanted = extras.pressed(cmd.in_attack)
    if ui.get(extras.ui.stop_mode) == "Visible target" and not wanted then
        local ex,ey,ez = client.eye_position()
        if not extras.finite(ex) or not extras.finite(ey) or not extras.finite(ez) then return end
        local candidates = {}
        for _, ent in ipairs(entity.get_players(true)) do
            if ent ~= me and entity.is_alive(ent) and not entity.is_dormant(ent) then
                local x,y,z = entity.hitbox_position(ent,0)
                if extras.finite(x) and extras.finite(y) and extras.finite(z) then
                    local delta = math.abs(normalize_yaw(math.deg(math.atan2(y-ey,x-ex))-camera_yaw))
                    if delta <= ui.get(extras.ui.stop_fov) then candidates[#candidates+1]={ent=ent,d=delta} end
                end
            end
        end
        table.sort(candidates,function(a,b) return a.d<b.d end)
        for i=1,math.min(3,#candidates) do
            for _, box in ipairs({0,4}) do
                local x,y,z = entity.hitbox_position(candidates[i].ent,box)
                if extras.finite(x) and extras.finite(y) and extras.finite(z) and type(client.visible)=="function" then
                    if client.visible(x,y,z) then wanted=true; break end
                end
            end
            if wanted then break end
        end
    end
    if not wanted then return end
    local vx,vy = entity.get_prop(me,"m_vecVelocity[0]"), entity.get_prop(me,"m_vecVelocity[1]")
    if not extras.finite(vx) or not extras.finite(vy) then return end
    local speed = math.sqrt(vx*vx+vy*vy)
    if speed <= ui.get(extras.ui.stop_speed) then
        cmd.forwardmove, cmd.sidemove = 0, 0; extras.stop_reason="settled"; return
    end
    local yaw = cmd.move_yaw or cmd.yaw or camera_yaw
    if not extras.finite(yaw) then return end
    yaw = math.rad(yaw)
    local gain = math.min(450,speed*4)/speed
    cmd.forwardmove = (-vx*math.cos(yaw)-vy*math.sin(yaw))*gain
    cmd.sidemove = (-vx*math.sin(yaw)+vy*math.cos(yaw))*gain
    extras.stop_reason = "braking"
end

function extras.pre_command(cmd, me)
    extras.duck_command(cmd,me)
    extras.drop_command(cmd,me)
end

function extras.post_command(cmd, me)
    extras.stop_command(cmd,me)
end

function extras.pose_write(me, index, value)
    if type(entity.set_prop) ~= "function" then return end
    local before = entity.get_prop(me,"m_flPoseParameter",index)
    if not extras.finite(before) then return end
    value = math.max(0,math.min(1,value))
    entity.set_prop(me,"m_flPoseParameter",value,index)
    extras.pose[index]={me=me,before=before,written=value}
end

function extras.anim_frame()
    extras.pose_restore()
    local live, me = extras.live()
    if not live or not ui.get(extras.ui.anim) then extras.native_set("legs",extras.legs_ref,nil); return end
    local ground = bit.band(entity.get_prop(me,"m_fFlags") or 0,1) ~= 0
    local tick, amount = globals.tickcount(), ui.get(extras.ui.anim_amount)/100
    if ground and extras.was_ground == false then extras.land_until=tick+2 end
    extras.was_ground=ground
    if ground then
        local mode=ui.get(extras.ui.anim_ground)
        if mode == "Static" or mode == "Jitter" then
            local value = mode == "Jitter" and (math.floor(tick/ui.get(extras.ui.anim_delay))%2==0 and amount or 1-amount) or amount
            extras.pose_write(me,0,value); extras.native_set("legs",extras.legs_ref,"Always slide")
        elseif mode == "Moonwalk" then
            extras.pose_write(me,7,0); extras.native_set("legs",extras.legs_ref,"Never slide")
        else extras.native_set("legs",extras.legs_ref,nil) end
        if ui.get(extras.ui.anim_land) and extras.land_until and tick<extras.land_until then extras.pose_write(me,12,0.5) end
    else
        extras.native_set("legs",extras.legs_ref,nil)
        local mode=ui.get(extras.ui.anim_air)
        if mode ~= "Off" then extras.pose_write(me,6,mode=="Cycle" and (0.5+0.5*math.sin(tick*0.35))*amount or amount) end
    end
end

function extras.scope_state()
    local live, me = extras.live()
    if not live or not ui.get(extras.ui.scope)
        or not extras.pressed(entity.get_prop(me,"m_bIsScoped")) then return false,false end
    local weapon=entity.get_player_weapon(me)
    if not weapon or weapon==0 then return false,false end
    local zoom=entity.get_prop(weapon,"m_zoomLevel")
    return true,extras.finite(zoom) and zoom>0 and not extras.pressed(entity.get_prop(me,"m_bResumeZoom"))
end

function extras.scope_active()
    local _,active=extras.scope_state()
    return active
end

function extras.scope_control(phase)
    local owned,active=extras.scope_state()
    local value
    if owned then value=phase~="paint" end
    extras.native_set("scope",extras.scope_ref,value)
    return active
end

function extras.frame_dt()
    local dt=globals.frametime()
    return extras.finite(dt) and math.max(0,math.min(0.1,dt)) or 0
end

function extras.scope_paint()
    local active=extras.scope_control("paint")
    local live=extras.live()
    if not live or not ui.get(extras.ui.scope) then extras.scope_alpha=0; return end
    local alpha=extras.scope_alpha or 0
    alpha=alpha+((active and 1 or 0)-alpha)*(1-math.exp(-extras.frame_dt()*16))
    extras.scope_alpha=alpha
    if alpha<0.01 then return end
    local sw,sh=client.screen_size()
    local x,y=math.floor(sw/2),math.floor(sh/2)
    local r,g,b,a=ui.get(extras.ui.scope_color)
    local gap,length,width=ui.get(extras.ui.scope_gap),ui.get(extras.ui.scope_length),ui.get(extras.ui.scope_width)
    local coverage=width==1 and 0.35 or 1
    local style=ui.get(extras.ui.scope_style)
    for _,arm in ipairs({{"Top",0,-1},{"Bottom",0,1},{"Left",-1,0},{"Right",1,0}}) do
        if not extras.has(extras.ui.scope_exclude,arm[1]) then
            local dx,dy=arm[2],arm[3]
            if style=="Diagonal" then dx,dy=(dx-dy)*0.7071,(dx+dy)*0.7071 end
            local pieces=style=="Soft" and 16 or 1
            for i=0,pieces-1 do
                local start=gap+length*i/pieces
                local finish=gap+length*(i+1)/pieces
                local opacity=style=="Soft" and (1-i/pieces) or 1
                for w=0,width-1 do
                    local offset=w-(width-1)/2
                    renderer.line(x+dx*start-dy*offset,y+dy*start+dx*offset,x+dx*finish-dy*offset,y+dy*finish+dx*offset,r,g,b,math.floor(a*alpha*opacity*coverage))
                end
            end
        end
    end
end

function extras.velocity_paint()
    local live,me=extras.live()
    local now,dt=globals.realtime(),extras.frame_dt()
    if not ui.get(master) then extras.velocity={}; extras.velocity_preview=nil; extras.velocity_visual=nil; return end
    if not ui.get(extras.ui.velocity) then
        extras.velocity={}; extras.velocity_preview=nil
        extras.velocity_fade(now)
        return
    end
    local value=live and entity.get_prop(me,"m_flVelocityModifier")
    local valid=extras.finite(value) and value>=0 and value<=1
    if not valid then extras.velocity={} end
    local s=extras.velocity
    if s.time and now<s.time then extras.velocity={}; s=extras.velocity end
    local visible=false
    if valid then
        local entered=value<0.995 and not s.slow
        local recovered=value>=0.995 and s.slow
        if entered then s.pulse=now end
        if recovered then s.recovered=now end
        if s.raw and value<s.raw-0.025 then s.pulse=now end
        s.slow,s.raw,s.time=value<0.995,value,now
        visible=s.slow or s.recovered and now-s.recovered<0.55
        s.alpha=(s.alpha or 0)+((visible and 1 or 0)-(s.alpha or 0))*(1-math.exp(-dt*(visible and 13 or 8)))
        s.display=(s.display or value)+(value-(s.display or value))*(1-math.exp(-dt*11))
    end
    if ui.is_menu_open() and not visible then
        local visual=extras.velocity_visual
        local preview=extras.velocity_preview or {alpha=visual and visual.fade_start and visual.alpha or 1,display=1}
        extras.velocity_preview=preview
        local elapsed=preview.start and now-preview.start
        if elapsed and elapsed<0 then preview.start=nil; elapsed=nil end
        local t=elapsed and math.min(1,elapsed/0.75) or 1
        preview.display=t*t*(3-2*t)
        preview.alpha=preview.alpha+(1-preview.alpha)*(1-math.exp(-dt*16))
        extras.velocity_draw(preview.display,preview,now,true)
        return
    end
    extras.velocity_preview=nil
    if valid and s.alpha>=0.01 then
        extras.velocity_draw(value,s,now,false)
    elseif extras.velocity_visual and extras.velocity_visual.preview then
        extras.velocity_fade(now)
    else
        extras.velocity_visual=nil
    end
end

function extras.velocity_fade(now)
    local visual=extras.velocity_visual
    if not visual then return end
    if not visual.fade_start then visual.fade_start,visual.fade_alpha=now,visual.alpha end
    local t=(now-visual.fade_start)/0.30
    if t<0 or t>=1 then extras.velocity_visual=nil; return end
    visual.alpha=visual.fade_alpha*(1-t*t*(3-2*t))
    extras.velocity_draw(visual.value,visual,now,visual.preview,true)
end

function extras.velocity_particles(cx,cy,scale,r,g,b,a,alpha,now,pulse)
    for i=0,39 do
        local layer=i%2
        local phase=now*(layer==0 and 0.16 or -0.12)+math.floor(i/2)/20+layer*0.025
        local angle=phase*math.pi*2
        local shimmer=0.5+0.5*math.sin(now*3.2+i*1.7)
        local radius=(15.6+layer*2.6+math.sin(now*2+i)*0.35+pulse*0.55)*scale
        local size=math.max(1,(1.05+shimmer*0.25+pulse*0.2)*scale)
        local x,y=cx+math.cos(angle)*radius,cy+math.sin(angle)*radius
        local halo=size+1.6*scale
        renderer.rectangle(x-halo/2,y-halo/2,halo,halo,r,g,b,math.floor(a*alpha*(0.06+shimmer*0.08)))
        renderer.rectangle(x-size/2,y-size/2,size,size,r,g,b,math.floor(a*alpha*(0.36+shimmer*0.44)))
    end
end

function extras.velocity_draw(value,s,now,preview,fading)
    if not fading then
        local visual=extras.velocity_visual or {}
        visual.value,visual.display,visual.alpha=value,s.display,s.alpha
        visual.pulse,visual.slow,visual.preview=s.pulse,s.slow,preview
        visual.fade_start,visual.fade_alpha=nil,nil
        extras.velocity_visual=visual
    end
    local sw,sh=client.screen_size()
    local scale=ui.get(extras.ui.velocity_scale)/100
    local w,h=190*scale,49*scale
    local x=math.max(4,math.min(sw-w-4,sw*ui.get(extras.ui.velocity_x)/100-w/2))
    local y=math.max(4,math.min(sh-h-4,sh*ui.get(extras.ui.velocity_y)/100-h/2))-(1-s.alpha)*8*scale
    local cr,cg,cb,ca=ui.get(extras.ui.velocity_color)
    local recovered_state=value>=0.995
    if recovered_state then cr,cg,cb=134,222,187 end
    local function rect(px,py,pw,ph,r,g,b,a) renderer.rectangle(px,py,pw,ph,r,g,b,math.floor(a*s.alpha)) end
    local function line(x1,y1,x2,y2,r,g,b,a) renderer.line(x1,y1,x2,y2,r,g,b,math.floor(a*s.alpha)) end
    rect(x-2*scale,y-2*scale,w+4*scale,h+4*scale,0,0,0,35)
    rect(x,y,w,h,17,20,27,222)
    rect(x,y,2*scale,h,cr,cg,cb,ca)
    line(x+2*scale,y,x+w,y,75,81,97,90)
    local cx,cy=x+26*scale,y+23*scale
    local pulse=s.pulse and math.max(0,1-(now-s.pulse)/0.65) or 0
    local progress=math.max(0,math.min(1,s.display))
    extras.velocity_particles(cx,cy,scale,cr,cg,cb,ca,s.alpha,now,pulse)
    for i=0,23 do
        local a1=math.rad(135+i*270/24+1.5)
        local a2=math.rad(135+(i+1)*270/24-1.5)
        local active=i/24<progress
        local radius=(13+(active and pulse*0.9 or 0))*scale
        line(cx+math.cos(a1)*radius,cy+math.sin(a1)*radius,cx+math.cos(a2)*radius,cy+math.sin(a2)*radius,
            active and cr or 64,active and cg or 70,active and cb or 84,active and ca or 150)
    end
    local angle=math.rad(135+270*progress)
    line(cx,cy,cx+math.cos(angle)*9*scale,cy+math.sin(angle)*9*scale,cr,cg,cb,ca)
    rect(cx-scale,cy-scale,2*scale,2*scale,235,239,248,ca)
    for i=0,2 do
        local shift=((now*30+i*7)%21)*scale
        local opacity=(1-shift/(21*scale))*pulse*90
        line(cx-7*scale-shift,cy+17*scale+i*2*scale,cx-2*scale-shift,cy+17*scale+i*2*scale,cr,cg,cb,opacity)
    end
    local tx=x+49*scale
    renderer.text(tx,y+8*scale,cr,cg,cb,math.floor(ca*s.alpha),"b",0,preview and "PREVIEW" or recovered_state and "RECOVERED" or "MOMENTUM")
    renderer.text(x+w-10*scale,y+8*scale,235,239,248,math.floor(ca*s.alpha),"r",0,string.format("%d%%",math.floor(value*100+0.5)))
    renderer.text(tx,y+23*scale,151,161,180,math.floor(210*s.alpha),"-",0,preview and "Animation preview" or recovered_state and "Movement restored" or "Movement slowed")
    local bw=w-61*scale
    rect(tx,y+h-8*scale,bw,2*scale,48,54,68,190)
    rect(tx,y+h-8*scale,bw*progress,2*scale,cr,cg,cb,ca)
    if s.slow or preview then
        local light=((now*0.7)%1)*bw*progress
        rect(tx+light,y+h-8*scale,math.min(10*scale,math.max(0,bw*progress-light)),2*scale,240,245,255,65)
    end
end

function extras.changed()
    if extras.config_loading then return end
    last_fl.on=nil
    extras.sync()
    extras.scope_control()
    if update_vis then update_vis() end
end

function extras.velocity_changed()
    local enabled=ui.get(extras.ui.velocity)
    if enabled and not extras.velocity_enabled and ui.get(master) then
        local visual=extras.velocity_visual
        extras.velocity={}
        extras.velocity_preview={start=globals.realtime(),alpha=visual and visual.fade_start and visual.alpha or 1,display=0}
    elseif not enabled and extras.velocity_enabled then
        local visual=extras.velocity_visual
        if visual and not visual.fade_start then visual.fade_start,visual.fade_alpha=globals.realtime(),visual.alpha end
    end
    extras.velocity_enabled=enabled
    extras.changed()
end
for _, item in ipairs(extras.controls) do ui.set_callback(item.ref,extras.changed) end
ui.set_callback(extras.ui.velocity,extras.velocity_changed)
client.set_event_callback("paint_ui",function()
    local now=globals.realtime()
    if not extras.sync_time or now<extras.sync_time or now-extras.sync_time>=0.25 then extras.sync_time=now; extras.sync() end
    extras.scope_control("paint_ui")
    extras.velocity_paint()
end)
client.set_event_callback("pre_render",function() extras.scope_control(); extras.anim_frame() end)
client.set_event_callback("post_render",extras.pose_restore)
client.set_event_callback("paint",extras.scope_paint)
client.set_event_callback("level_init",extras.cleanup)
client.set_event_callback("round_prestart",extras.cleanup)
client.set_event_callback("player_death",function(e)
    if e and client.userid_to_entindex(e.userid)==entity.get_local_player() then extras.cleanup() end
end)
extras.qucy={alpha=0,channels={}}

function extras.qucy_read(now,live)
    if not live then
        local phase=math.floor(now/2.4)%3
        return {preview=true,flags={DT=phase~=1,HS=phase==1,FD=false,FS=phase==2}}
    end
    return {preview=false,flags={DT=hl_active(hl_ref.dt),HS=hl_active(hl_ref.os),FD=pro.duck and ui.get(pro.duck)==true or false,
        FS=freestand_applied==true and ui.get(fs_hotkey)==true and N.freestand~=nil and ui.get(N.freestand)==true}}
end

local qucy_starry_b64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAIN0lEQVR4nL1XD0xT2xk/596WUigtlEKhrUCpUGBYEkAqeQlEQvgzl0wfEYIQAWfMW8icMWAUTRRmJA4D0Yznxnxuc/5hsYZIVBghWNmccVHytiBQIKioQMHyp/YP7eXes3z3UcOUZc6n+5J7z3fuOfd83/l+359zEPrvRCOEMPo/EAWv4uLiQwaD4WFGRsY3xcXFX/gGe3t7+fHPSXh+fp6Oi4sbj4qKIrGxsSQuLo6kpaX9qq2tTQwT6urq6M8mHCGEysrKIvV6/YJarWZjYmK80dHRbEREBCjyqKWlZSPM2bVrl+CTC0bftYQQIo6IiLAIhcINQqGQYxiGksvljFKpFNrt9imxWLzNbDZ/W15eLrh8+fLKp1CAeqfPcBy3QlEUcrlcSKPRILlcLrRYLCvPnz9XTU1N9ebn56eB8MLCQuGnVICAFTDGKxqNxsZxHNJqtcjpdKKhoSEYEIjFYpZhmNCnT5/+edOmTaldXV1MX18f/39ra6uAEPJRTkqt4XkHCwgIGBGJRMjhcHDz8/PQR2ARQgjtdru5ubm5ULFYfC89Pb02JyeHg39sNlvkoUOHlGvg/OCwFfiY0tJSdO3aNdjtIMYY2e12JBQKoY+8Xi//qNVqatu2bVx8fLxkYGDgl/Pz899OTEz0jo+PByCE5tYowP3PFnC5XHwrFAqfE0J4wfAADP7+/shoNKKWlhYUFxdHtbW1MY8ePSJJSUk/A/g4wGyN8ObmZtk7lsC3b9+m9u7dS0O71kKUj0lKSgI/QBzHTdA0jwa9srKCQkJCkMFgQPv370cPHz5Ehw8fBr8QDg8Pc1ar9UclJSU/PHr06ITb7Q4BZerr63UOhyMJeIwxvybwYLkLFy6w0K76HC8br7EGz09OTooyMzPHhEKhyuFwoMTERKq6uhoxDIMqKytRWFgYCg4OBkU58Fq1Wj3DMMwPDhw4sFJUVMSdPHky+NixY69W1/NHCLn37Nmj0Gg0SovFIn39+vVSb2/vsE85vBYPyHSnTp1is7Kyfvrs2bOvw8LC2PT0dLqqqgqBEhMTE0ihUIBDIoFAgFiWZRUKBU1R1K9dLtfdtLS0qpGRkfq5uTkSFRX1tVQqDRkeHp632+2x8fHxwdPT03hxcRHyy9+Tk5N/Yjabh/8tdED4kSNH6P7+/vM6na41IiKCjo2NZV++fIksFgsPhw9uaEUiEe3xeIhMJvtKq9X+KSEhoSA8PNzsdDr/kpCQkEpRlHZ2djaN47gQu92OYS7DMOyGDRu2iMXigwDFu7GLGxsbYYeUwWDoDQoKcrndbspisRCpVMqHI4Ql7B4cFCzhcDgwjI+MjBCTycSOj4+L7HY7ZE5uamqKI4RwUqmUgOW8Xi8RiURCpVLpSk5O/j3IWy95sBUVFdevX7/ecevWLX+JRII3btyIwRFZluV3Dg8IByf1eDzwHfv5+WGr1Uq/ePGCREdHk/T0dGphYQHWp2CNsbEx1uVyQZFzIoT2NzU1/bW2tpZ6q8DNmzeBJ4ODgylPnjwpAKz0ej2GfODn58cLA8Eg0MeDFSBiVqOG74NvGo1GMDeanp4G2Fiv18t6PB6Akw4PD8/r7u7+pqysTNDU1MSuzQM8Pzg4mOF2uwMCAwMhvvHo6ChaXl5GEokEhYeH88qAQBAGtQLggDFIWpA55XI5KioqQl1dXaAsC+EMlJqa+g+5XP7ljRs3/rZ7927BlStX+GJG+RS4d+8eHxYWi0UDWIEQWHRychLNzs6iwsJCFBUVBY7HzwefmJmZ4ZUCWlpa4pU7ceIEun//Pnv37l1Wo9HQGOMenU63p7OzM7Wnp6cDZF66dOltJaV8DMQ5kFwuh2oIIY4CAwP5ojQ+Ps5jHhQUBFmRBAUFERAOSgC9evUKxcTEoNOnT0NJh4xJa7VaWqVS1Y+OjhaaTKbfQeAcP36cfjdNUz7m7NmzfD8jI6MrJCTE5vV6McdxvFXcbjcaGBhAMpkMRUZGYoZhMPBgEbASmLy2thYshRsaGpiEhARzXl7el2az+QQkHMAb1qmvrwdI1i9GEomET5EymUyhUqneDA0NyaEAARTgiOB0AI1AIFj2eDyLmZmZkVqtluTk5GCFQsGaTCaqr6+vMyUlpa6jo2Po8ePHvg0SH97rEQWvnp4efuLFixfP19XVdc3NzcWEhoaSxcVFyFy8E75584YLCAiAfqfBYJhQq9X8EQoSVHt7O+ns7MQ6ne4xCNfr9X6Q0FbN7asH6ytw9epVQV5eHtfe3v7zBw8efKVUKkcg5Xq9Xgri1maz8cLB1G63+4lIJBpUqVRfWK1WbmZmhrLZbOTOnTuUVCpdqKmpMYHXnzt3bqWxsfE9c6+rQH9/P68hnHgqKipqUlJSTkml0lG1Wv10eXkZT05OsjRNsxKJBKx0OjQ09McADZRvp9PJdXd3w5mR2rp16y9yc3OHS0tLcX5+/gefB94jo9EoI4SIKisra6BEQ1bLzc0lRqPxtwcPHkzesWMHyc7OZuPj4wESkpiYSMrLy5sIIYLs7OyPPzGbTCZqaWnp7bnf4XCImpubs1JSUsa2b99+Fb5lZWWdB6VUKhUTExNDNm/e/LK1tbWcEOK3+tsnu0FhH2O32/lLSVVV1Ybk5GQmLCyM02q13L59+/5JCPkuEXwP4dR/+E581zGpVOreuXMnrVAoVvR6/R9SU1Nnt2zZggUCwW8wxvaCggKR716BPhNhQgi/O0KI/5kzZ/5YXV1tdTqdkoaGBso39rFEfcAc/mxXUlIiwBgvMwwzJBKJKgIDAx1WqxVS9mfb+Xr03hny+9K/AH3A5pgJJC2ZAAAAAElFTkSuQmCC"
local qucy_starry_raw = b64_decode(qucy_starry_b64)
local qucy_starry_texture
local qucy_texture_attempts, qucy_texture_retry = 0, nil
function extras.qucy_emblem_texture()
    if qucy_starry_texture then return qucy_starry_texture end
    local now = globals.realtime()
    if qucy_texture_attempts >= 3 then return end
    if qucy_texture_retry and now < qucy_texture_retry and now >= qucy_texture_retry-2 then return end
    qucy_texture_attempts = qucy_texture_attempts + 1
    qucy_texture_retry = now + 2
    qucy_starry_texture = renderer.load_png(qucy_starry_raw, 32, 32)
    if not qucy_starry_texture and qucy_texture_attempts == 1 then
        client.error_log("[Ünoins_qucy] Indicator PNG failed to load; retrying at most twice. Reload Lua after correcting renderer support.")
    end
    return qucy_starry_texture
end

function extras.qucy_draw(data, s, now)
    local sw, sh = client.screen_size()
    local cr, cg, cb, ca = ui.get(extras.ui.qucy_color)
    local _, height = renderer.measure_text("-", "X")
    local row = math.max(8, math.min(10, height or 8)) + 3
    local title = data.preview and "PREVIEW" or "Ünoins_qucy"
    local title_width = renderer.measure_text("-b", title) or 38
    local function measure(label) return renderer.measure_text("-", label) or (#label * 5) end
    local width = math.max(title_width + 20, measure("DT") + measure("HS") + 20, measure("FS") + measure("FD") + 6)
    local x = math.floor(math.max(4, math.min(sw - width - 5, sw / 2 + 4)))
    local y = math.floor(math.max(4, math.min(sh - row * 3 - 5, sh / 2 + ui.get(extras.ui.qucy_offset))))
    local function alpha(a) return math.floor(math.max(0, math.min(255, a * s.alpha * ca / 255)) + 0.5) end
    local function text(px, py, r, g, b, a, flags, label)
        renderer.text(px + 1, py + 1, 0, 0, 0, alpha(a * 0.8), flags, width, label)
        renderer.text(px, py, r, g, b, alpha(a), flags, width, label)
    end
    local function path(px, py, points, r, g, b, a)
        for i = 1, #points - 1 do
            local p, q = points[i], points[i + 1]
            renderer.line(px + p[1] + 1, py + p[2] + 1, px + q[1] + 1, py + q[2] + 1, 0, 0, 0, alpha(a * 0.7))
            renderer.line(px + p[1], py + p[2], px + q[1], py + q[2], r, g, b, alpha(a))
        end
    end

    local emblem_alpha = alpha(255)
    if emblem_alpha > 0 then
        local emblem = extras.qucy_emblem_texture()
        if emblem then
            local pulse = 1 + math.sin(now * 2.8) * 0.04
            local ew = math.floor(16 * pulse + 0.5)
            local eh = math.floor(16 * pulse + 0.5)
            renderer.texture(emblem, x + 1, y - 2, ew, eh, 0, 0, 0, alpha(130), "f")
            renderer.texture(emblem, x, y - 3, ew, eh, cr, cg, cb, emblem_alpha, "f")
        end
    end

    text(x + 19, y, 208, 225, 216, 235, "-b", title)
    local chars = {}
    for char in title:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1] = char end
    local num_chars = #chars
    local sweep = (now * 0.24 % 1) * (num_chars + 4) - 2
    for i = 1, num_chars do
        local shine = math.max(0, 1 - math.abs(i - sweep) / 1.4)
        if shine > 0.03 then
            local prefix = i == 1 and "" or table.concat(chars, "", 1, i - 1)
            local offset = i == 1 and 0 or (renderer.measure_text("-b", prefix) or 0)
            renderer.text(x + 19 + offset, y, cr, cg, cb, alpha(shine * 220), "-b", width, chars[i])
        end
    end

    local hs_drop = math.max(1, math.floor(((height or 10) - 6) / 2 + 0.5))
    local dt_drop = math.max(0, math.floor(((height or 10) - 7) / 2 + 0.5))
    local glyphs = {
        DT = {{3, 0}, {1, 3}, {2.5, 3}, {0, 7}},
        HS = {{0, 0}, {4.5, 0}, {4.5, 3}, {2.25, 5.5}, {0, 3}, {0, 0}}
    }
    local function status(px, py, key, glyph)
        local active = s.channels[key] or 0
        local rr, gg, bb = math.floor(120 + (cr - 120) * active), math.floor(135 + (cg - 135) * active), math.floor(126 + (cb - 126) * active)
        local opacity = glyph and (85 + 170 * active) or (255 * active)
        if glyph then
            path(px, py + (key == "HS" and hs_drop or dt_drop), glyph, rr, gg, bb, opacity * (1 - active * 0.08 * (0.5 + 0.5 * math.sin(now * 2.2))))
            px = px + 6.5
        end
        text(px, py, rr, gg, bb, opacity, "-", key)
        return px + measure(key) + 4
    end

    local px = x
    for _, key in ipairs({"DT", "HS"}) do px = status(px, y + row, key, glyphs[key]) + 1 end

    px = x
    for _, key in ipairs({"FS", "FD"}) do
        if (s.channels[key] or 0) > 0.003 then px = status(px, y + row * 2, key) end
    end
end

function extras.qucy_paint()
    local s=extras.qucy
    local now=globals.realtime()
    local dt=math.max(0,math.min(0.1,s.time and now-s.time or globals.frametime()))
    s.time=now
    local me=entity.get_local_player()
    local live=me and entity.is_alive(me)
    local wanted=ui.get(master) and ui.get(indicator_sel)=="Ünoins_qucy new" and (live or ui.is_menu_open())
    local step=1-math.exp(-dt*14)
    s.alpha=s.alpha+((wanted and 1 or 0)-s.alpha)*step
    if not wanted and s.alpha<0.003 then s.alpha=0;s.data=nil;return end
    if wanted then s.data=extras.qucy_read(now,live) end
    if not s.data then return end
    for key,active in pairs(s.data.flags) do
        local value=s.channels[key] or 0
        s.channels[key]=value+((active and 1 or 0)-value)*step
    end
    extras.qucy_draw(s.data,s,now)
end
client.set_event_callback("paint_ui",extras.qucy_paint)
extras.changed()

-- Kupetis