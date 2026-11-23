--[[
	AOT_FW  -  Attack on Titan: Freedom War
	INSTALADOR + SCRIPT en un solo archivo. Ejecutalo UNA vez: se guarda a si mismo en la carpeta workspace
	(AOT_FW.lua + AOTFW_boot.lua) y se re-ejecuta solo en cada servidor nuevo (apagalo con el toggle
	"Auto-ejecutar al cambiar de servidor"). Para actualizarlo, ejecuta el archivo nuevo.
]]
local __q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
local __SRC = [=====[
--[[
	AOT_FW.lua  -  Attack on Titan: Freedom War  (v1)        RightShift = mostrar / ocultar

	IMPORTANTE (lee esto):
	  * Este script NO conoce los nombres internos del juego (valores, remotes). Por eso usa BUSQUEDA POR PATRONES:
	    marca  ✔  = funciona sin saber nada del juego (ESP, hitbox, emotes, ropa, staff, caballo...)
	    marca  ◐  = depende de que el juego guarde el dato con un nombre parecido (gas, hojas, cooldowns...).
	  * Pulsa "Inspector" dentro del juego: guarda AOTFW_dump.txt (carpeta workspace) con los remotes y valores reales.
	    Mandame ese archivo y ajusto los patrones EXACTOS para que las funciones ◐ funcionen al 100%.
	  * No existe un script "indetectable". Aqui solo hay buenas practicas para dejar poco rastro:
	    GUI oculta con nombre aleatorio, el hook de remotes solo se instala si activas algo que lo necesita,
	    todo en pcall, sin warn/print, valores con limites razonables y tasas de disparo moderadas.
]]

-- RED DE SEGURIDAD: si algo falla al cargar, el error sale en pantalla y se guarda en AOTFW_error.txt
local __ok, __err = xpcall(function()
pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = "AOT FW", Text = "cargando... (RightShift = menu)", Duration = 5 }) end)
if getgenv and getgenv().AOTFW_Unload then pcall(getgenv().AOTFW_Unload) end
if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Player = Players.LocalPlayer
if not Player then Players:GetPropertyChangedSignal("LocalPlayer"):Wait() Player = Players.LocalPlayer end

local CFG_FILE = "AOTFW_cfg.json"
local DUMP_FILE = "AOTFW_dump.txt"
local BOOT_LOG = "AOTFW_boot_log.txt"
-- true = al re-ejecutar (o al cambiar de servidor) reactiva, poco a poco, lo que dejaste ON.
-- Se puede apagar desde el menu ("Recordar opciones al reentrar").
local AUTO_RESTORE = true
local SavedON = {}
local restoring = false
local bootTime = tick()

-- PROTECTOR ANTI-CRASH: antes de cada paso riesgoso se anota que paso va; si Roblox se cierra,
-- en el siguiente arranque se sabe cual fue y esa opcion NO se restaura sola (la puedes activar a mano).
local CRASH_FILE = "AOTFW_crash.txt"
local Crash = { stage = "ok", id = "", bad = {} }
local function crashRead()
	pcall(function()
		if isfile and readfile and isfile(CRASH_FILE) then
			local st, id, bad = readfile(CRASH_FILE):match("^(%w*)|([^|]*)|(.*)$")
			if st then
				Crash.stage, Crash.id = st, id
				for b in (bad or ""):gmatch("[^,]+") do Crash.bad[b] = true end
			end
		end
	end)
end
local function crashWrite(stage, id)
	Crash.stage, Crash.id = stage, id or ""
	pcall(function()
		if writefile then
			local list = {}
			for k in pairs(Crash.bad) do list[#list + 1] = k end
			writefile(CRASH_FILE, ("%s|%s|%s"):format(stage, id or "", table.concat(list, ",")))
		end
	end)
end
crashRead()
local prevCrashStage, prevCrashId = Crash.stage, Crash.id
-- arranque RAPIDO si la ultima vez termino bien; arranque lento y escalonado solo despues de un crash
local FAST = (prevCrashStage == "ok")
if (prevCrashStage == "restore" or prevCrashStage == "boot") and prevCrashId ~= "" then Crash.bad[prevCrashId] = true end
crashWrite("boot", "")

-- log de arranque: si Roblox se cierra, el ultimo paso escrito en AOTFW_boot_log.txt dice donde fue
local function blog(m)
	pcall(function()
		if appendfile then appendfile(BOOT_LOG, ("[%s] %s\n"):format(os.date("%H:%M:%S"), tostring(m))) end
	end)
end
pcall(function() if writefile then writefile(BOOT_LOG, "") end end)
blog("inicio")

local Alive, Conns = true, {}

-- MODULOS: cada sistema que corre solo arranca escalonado y anotado. Si Roblox se cierra, el modulo
-- que estaba arrancando queda marcado y se omite en el siguiente arranque (el resto sigue funcionando).
local modN = 0
local function mod(name, fn)
	modN = modN + 1
	local id = "mod:" .. name
	local delay = FAST and (0.3 + modN * 0.2) or (2 + modN * 0.8)
	task.spawn(function()
		task.wait(delay)
		if not Alive then return end
		if Crash.bad[id] then blog("modulo omitido (crash previo): " .. name) return end
		crashWrite("boot", id)
		blog("modulo: " .. name)
		task.delay(2.5, function()
			if Crash.id == id and Crash.stage == "boot" then crashWrite("boot", "") end
		end)
		pcall(fn)
	end)
end
local function connect(sig, fn)
	local c = sig:Connect(function(...) pcall(fn, ...) end)
	Conns[#Conns + 1] = c
	return c
end
local function getChar() return Player.Character end
local function getRoot() local c = getChar() return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = getChar() return c and c:FindFirstChildOfClass("Humanoid") end
local function rname()
	local t = {}
	for i = 1, 10 do t[i] = string.char(math.random(97, 122)) end
	return table.concat(t)
end

local setStatus = function() end
local function notify(text)
	setStatus(text)
	pcall(function() StarterGui:SetCore("SendNotification", { Title = "AOT FW", Text = tostring(text), Duration = 6 }) end)
end

------------------------------------------------------------------
-- AJUSTES
------------------------------------------------------------------
local ON = { autorestore = true, autoexec = true, espall = true, tpsmooth = true }
local VAL = {
	NapeMult = 4, LegMult = 3, HumanSize = 8, BladeMult = 3, NapeNear = 60,
	HookScale = 1.5, HookSpeedScale = 3, TPSpeed = 140,
	ShiftSpeed = 40, HorseSpeed = 60,
	AuraRange = 40, AuraRate = 6, ThrowRate = 8,
	StaffRank = 100,
	AimPull = 0.12, AimMaxStep = 1.2, AimFOV = 25, AimRange = 250, HookAssistFOV = 45, UIScale = 1.2,
}
local IGNORE = setmetatable({}, { __mode = "k" }) -- tablas propias: el escaner de memoria no las toca
IGNORE[ON] = true
IGNORE[VAL] = true

local function syncAuto()
	pcall(function() if writefile then writefile("AOTFW_auto.txt", ON.autoexec and "1" or "0") end end)
end
local function saveCfg()
	if not writefile or restoring then return end
	syncAuto()
	pcall(function() writefile(CFG_FILE, HttpService:JSONEncode({ ON = ON, VAL = VAL })) end)
end
local function loadCfg()
	if not (isfile and readfile) then return end
	pcall(function()
		if not isfile(CFG_FILE) then return end
		local d = HttpService:JSONDecode(readfile(CFG_FILE))
		if type(d) ~= "table" then return end
		for k, v in pairs(d.ON or {}) do if type(v) == "boolean" then SavedON[k] = v end end
		if SavedON.autorestore == nil then SavedON.autorestore = true end
		for _, k in ipairs({ "autorestore", "autoexec", "espall", "tpsmooth" }) do
			if SavedON[k] == false then ON[k] = false end
		end
		for k, v in pairs(d.VAL or {}) do if type(VAL[k]) == "number" and type(v) == "number" then VAL[k] = v end end
	end)
end

------------------------------------------------------------------
-- MOTOR DE PATRONES  (valores, atributos y tablas en memoria)
------------------------------------------------------------------
local function has(key, list)
	for _, p in ipairs(list) do
		if p:sub(1, 1) == "=" then
			if key == p:sub(2) then return true end
		elseif key:find(p, 1, true) then
			return true
		end
	end
	return false
end
local function norm(s) return (tostring(s):lower():gsub("[%s_%-%.]", "")) end

-- mode: max (rellena al maximo) | zero (a 0 / false) | unlock (false -> true) | scale (base * VAL[val])
local RULES = {
	{ on = "gas", mode = "max", inc = { "gas" }, exc = { "max", "cost", "use", "drain", "consum", "rate", "regen", "refill", "sound", "bar", "effect", "particle", "smoke", "pressure", "speed", "boost", "force" } },
	{ on = "blades", mode = "max", arrays = true, inc = { "blade", "sword" }, exc = { "max", "durab", "sharp", "throw", "damage", "sound", "cost", "name", "model", "color", "equip", "slot" } },
	{ on = "durab", mode = "max", arrays = true, inc = { "durab", "sharp", "bladehealth", "bladehp", "bladelife", "swordhealth", "swordhp", "bladecondition" }, exc = { "max", "drain", "cost", "loss", "decay" } },
	{ on = "durab", mode = "zero", inc = { "=broken", "=isbroken", "bladebroken", "swordbroken", "bladebreak", "swordbreak" }, exc = { "max" } },
	{ on = "hooktimer", mode = "max", inc = { "hooktime", "hooktimer", "hookduration", "hooklife", "hookdur", "ropetime", "ropetimer" }, exc = { "max", "cooldown" } },
	{ on = "shiftstam", mode = "max", inc = { "stamina" }, exc = { "max", "drain", "regen", "cost", "rate" } },
	{ on = "shifttimer", mode = "max", inc = { "shiftertimer", "shifttimer", "shiftertime", "shifttime", "titantimer", "titantime", "transformtime", "shiftduration", "shifterduration" }, exc = { "max", "cooldown", "cd" } },
	{ on = "horsestam", mode = "max", scope = "horse", inc = { "stamina" }, exc = { "max", "drain", "regen", "cost", "rate" } },
	{ on = "nocd", mode = "zero", inc = { "cooldown", "=cd" }, exc = { "nocooldown", "max", "display", "label" } },
	{ on = "hood", mode = "max", inc = { "hood" }, exc = { "cooldown", "delay", "speed", "time", "quick", "name", "color", "model", "duration" } },
	{ on = "quickhood", mode = "zero", inc = { "hood" }, also = { "cooldown", "delay", "time", "duration", "cd" } },
	{ on = "unlockskills", mode = "unlock", inc = { "impulse", "dodge", "evade", "evasion", "dash", "parry", "counter" }, exc = { "cooldown", "cost", "damage", "time", "speed", "distance", "force", "count", "level" } },
	{ on = "special", mode = "max", inc = { "special" }, also = { "use", "charge", "count", "left", "remain", "amount", "ammo" }, exc = { "max" } },
	{ on = "unlockemotes", mode = "unlock", inc = { "emote" }, exc = { "cooldown", "name", "id", "count", "speed", "time" } },
	{ on = "hookrange", mode = "scale", val = "HookScale", inc = { "hookrange", "hookdist", "hookmaxdist", "hookreach", "hooklength", "maxhook", "ropelength", "ropedist", "ropemax" }, exc = { "min" } },
	{ on = "insthook", mode = "scale", val = "HookSpeedScale", inc = { "hookspeed", "hookvelocity", "hookshootspeed", "ropespeed" } },
	{ on = "insthook", mode = "zero", inc = { "hookdelay", "hookcd", "hookcooldown", "hookwait", "hooktravel" } },
	{ on = "nocannon", mode = "zero", inc = { "cannon" }, also = { "cooldown", "delay", "reload", "cd", "time" } },
	{ on = "antiburn", mode = "zero", inc = { "burn" } },
	{ on = "nodetect", mode = "zero", inc = { "detected", "aggro", "spotted", "noticed" }, exc = { "cooldown" } },
}
for i, r in ipairs(RULES) do
	r.idx = i
	r.seen = setmetatable({}, { __mode = "k" })
	IGNORE[r] = true
	IGNORE[r.inc] = true
end

local Active = {} -- rule -> lista de entradas
local function ruleMatches(rule, k)
	if not has(k, rule.inc) then return false end
	if rule.also and not has(k, rule.also) then return false end
	if rule.exc and has(k, rule.exc) then return false end
	return true
end

local function eGet(e)
	if e.t then return rawget(e.t, e.k) end
	if e.attr then return e.inst:GetAttribute(e.attr) end
	return e.inst.Value
end
local function eSet(e, v)
	if e.t then rawset(e.t, e.k, v) return end
	if e.attr then e.inst:SetAttribute(e.attr, v) return end
	e.inst.Value = v
end
local function eName(e) return tostring(e.k or e.attr or (e.inst and e.inst.Name) or "") end

-- busca el "maximo" propio del dato (hermano llamado Max..., ...Max)
local function findCap(e)
	local base = norm(eName(e))
	local function isCap(n)
		n = norm(n)
		return n == "max" .. base or n == base .. "max"
	end
	if e.t then
		for k2, v2 in next, e.t do
			if type(k2) == "string" and type(v2) == "number" and isCap(k2) then e.capT, e.capK = e.t, k2 return end
		end
	elseif e.attr then
		for n, v in pairs(e.inst:GetAttributes()) do
			if type(v) == "number" and isCap(n) then e.capInst, e.capAttr = e.inst, n return end
		end
	elseif e.inst.Parent then
		for _, s in ipairs(e.inst.Parent:GetChildren()) do
			if s:IsA("ValueBase") and s ~= e.inst and isCap(s.Name) then e.capInst = s return end
		end
	end
end
local function readCap(e)
	if e.capT then return rawget(e.capT, e.capK) end
	if e.capInst and e.capAttr then return e.capInst:GetAttribute(e.capAttr) end
	if e.capInst then return e.capInst.Value end
end

local applyEntry
local HW = {}
IGNORE[HW] = true

local function register(rule, owner, id, e)
	local s = rule.seen[owner]
	if not s then s = {} rule.seen[owner] = s end
	if s[id] then return end
	s[id] = true
	local list = Active[rule]
	if not list then list = {} Active[rule] = list end
	if #list >= 400 then return end
	pcall(findCap, e)
	list[#list + 1] = e
	-- hojas / durabilidad: se vuelve a poner en el MISMO instante en que el juego la baja
	if (rule.on == "durab" or rule.on == "blades") and e.inst and not e.t then
		local sig = e.attr and e.inst:GetAttributeChangedSignal(e.attr) or e.inst.Changed
		local calls, t0 = 0, tick()
		Conns[#Conns + 1] = sig:Connect(function()
			if not (Alive and ON[rule.on]) then return end
			local now = tick()
			if now - t0 > 1 then t0, calls = now, 0 end
			calls = calls + 1
			if calls > 30 then return end -- evita un ping-pong infinito con los scripts del juego
			pcall(applyEntry, rule, e)
		end)
	end
end

applyEntry = function(rule, e)
	local cur = eGet(e)
	local mode = rule.mode
	if mode == "max" then
		if type(cur) == "number" then
			local cap = readCap(e)
			local hw = math.max(e.max or cur, cur, type(cap) == "number" and cap or 0)
			if rule.on == "durab" or rule.on == "blades" then
				-- recuerda el valor mas alto visto con ese nombre (una hoja nueva llega llena)
				local key = rule.on .. ":" .. norm(eName(e))
				hw = math.max(hw, HW[key] or 0)
				HW[key] = hw
			end
			e.max = hw
			if cur < e.max then eSet(e, e.max) end
		elseif cur == false then
			eSet(e, true)
		end
	elseif mode == "zero" then
		if type(cur) == "number" and cur ~= 0 then eSet(e, 0) elseif cur == true then eSet(e, false) end
	elseif mode == "unlock" then
		if type(cur) == "boolean" then
			local n = norm(eName(e))
			local want = true
			if n:find("unlock", 1, true) then want = true elseif n:find("lock", 1, true) then want = false end
			if cur ~= want then eSet(e, want) end
		end
	elseif mode == "scale" then
		if type(cur) == "number" then
			e.base = e.base or cur
			local target = e.base * (VAL[rule.val] or 1)
			if cur ~= target then eSet(e, target) end
		end
	end
end

local function restoreRule(rule)
	local list = Active[rule]
	if list and rule.mode == "scale" then
		for _, e in ipairs(list) do
			if e.base then pcall(eSet, e, e.base) end
		end
	end
	Active[rule] = nil
	rule.seen = setmetatable({}, { __mode = "k" })
end

-- aplica los valores: 1 vez por frame (+ 2a pasada ligera solo para hojas/durabilidad)
local function runRule(rule, list)
	local ok = pcall(function()
		for i = 1, #list do applyEntry(rule, list[i]) end
	end)
	if not ok then
		for i = #list, 1, -1 do
			if not pcall(applyEntry, rule, list[i]) then table.remove(list, i) end
		end
	end
end
local function applyAll(fastOnly)
	for rule, list in pairs(Active) do
		if ON[rule.on] and (not fastOnly or rule.on == "durab" or rule.on == "blades") then
			runRule(rule, list)
		end
	end
end
mod("reglas", function()
	connect(RunService.Heartbeat, function() applyAll(false) end)
	connect(RunService.Stepped, function() applyAll(true) end)
end)

-- caballo montado
local function mountedModel()
	local hum = getHum()
	local seat = hum and hum.SeatPart
	if not seat then return nil end
	local m = seat:FindFirstAncestorOfClass("Model")
	if m and m ~= getChar() then return m, seat end
	return nil
end

local Scan = { dirty = true, gcBusy = false, lastInst = 0, lastGC = 0 }
function Scan.kick() Scan.dirty = true end
local function slow(t) return ON.lite and t * 2.5 or t end

local function activeRules(onlyGC)
	local out = {}
	for _, rule in ipairs(RULES) do
		if ON[rule.on] and (not onlyGC or not rule.scope) then out[#out + 1] = rule end
	end
	return out
end

local function scanInstances()
	local act = activeRules(false)
	if #act == 0 then return end
	local roots = {}
	local c = getChar()
	if c then roots[#roots + 1] = { c, "me" } end
	roots[#roots + 1] = { Player, "me" }
	local pf = ReplicatedStorage:FindFirstChild(Player.Name)
	if pf then roots[#roots + 1] = { pf, "me" } end
	if ON.horsestam then
		local hm = mountedModel()
		if hm then roots[#roots + 1] = { hm, "horse" } end
	end
	local n = 0
	local function consider(inst, kind)
		n = n + 1
		if n % 300 == 0 then task.wait() end
		local isVal = inst:IsA("NumberValue") or inst:IsA("IntValue") or inst:IsA("BoolValue")
		local nm = isVal and norm(inst.Name) or nil
		local attrs = inst:GetAttributes()
		local hasAttrs = next(attrs) ~= nil
		if not (nm or hasAttrs) then return end
		for _, rule in ipairs(act) do
			if (rule.scope == "horse") == (kind == "horse") then
				if nm and ruleMatches(rule, nm) then
					register(rule, inst, "v", { inst = inst })
				end
				if hasAttrs then
					for an, av in pairs(attrs) do
						if (type(av) == "number" or type(av) == "boolean") and ruleMatches(rule, norm(an)) then
							register(rule, inst, "a" .. an, { inst = inst, attr = an })
						end
					end
				end
			end
		end
	end
	for _, r in ipairs(roots) do
		consider(r[1], r[2])
		for _, d in ipairs(r[1]:GetDescendants()) do consider(d, r[2]) end
	end
end

-- getgc es lo mas pesado del script: se filtra rapido por fragmentos y se cede el turno a menudo
local function scanGC()
	if not getgc or Scan.gcBusy or not ON.deepscan then return end
	if tick() - bootTime < 12 or not (getChar() and getRoot()) then return end -- no tocar la memoria mientras el juego carga
	local act = activeRules(true)
	if #act == 0 then return end
	Scan.gcBusy = true
	local frags = {}
	for _, rule in ipairs(act) do
		for _, p in ipairs(rule.inc) do frags[#frags + 1] = (p:sub(1, 1) == "=") and p:sub(2) or p end
	end
	local function inspectTable(t)
		local cnt = 0
		for k, v in next, t do
			cnt = cnt + 1
			if cnt > 120 then break end
			if type(k) == "string" and #k < 40 then
				local tv = type(v)
				if tv == "number" or tv == "boolean" or tv == "table" then
					local nk = k:lower()
					if nk:find("[%s_%-%.]") then nk = nk:gsub("[%s_%-%.]", "") end
					local hit = false
					for i = 1, #frags do
						if nk:find(frags[i], 1, true) then hit = true break end
					end
					if hit then
						if tv == "table" then
							if not IGNORE[v] then
								for _, rule in ipairs(act) do
									if rule.arrays and ruleMatches(rule, nk) then
										local c3 = 0
										for ik, iv in next, v do
											c3 = c3 + 1
											if c3 > 16 then break end
											if type(iv) == "number" then register(rule, v, "i" .. tostring(ik), { t = v, k = ik }) end
										end
									end
								end
							end
						else
							for _, rule in ipairs(act) do
								if ruleMatches(rule, nk) then register(rule, t, "g" .. k, { t = t, k = k }) end
							end
						end
					end
				end
			end
		end
	end
	blog("getgc: inicio")
	pcall(function()
		local all = getgc(true)
		for i = 1, #all do
			if i % 2000 == 0 then
				task.wait()
				if not Alive then return end
			end
			local t = all[i]
			if type(t) == "table" and not IGNORE[t] then pcall(inspectTable, t) end
		end
	end)
	Scan.gcBusy = false
	blog("getgc: fin")
end

connect(Player.CharacterAdded, function()
	task.wait(2)
	Scan.kick()
end)

mod("escaneo", function()
	while Alive do
		task.wait(slow(0.5))
		local now = tick()
		local act = activeRules(false)
		if #act > 0 then
			if Scan.dirty or now - Scan.lastInst > slow(5) then
				Scan.lastInst = now
				pcall(scanInstances)
			end
			-- getgc: al activar / al reaparecer; cada 45 s si algun dato aun no aparecio; cada ~25 s solo para hojas
			local missing = false
			for _, rule in ipairs(act) do
				if not rule.scope and not (Active[rule] and #Active[rule] > 0) then missing = true break end
			end
			local volatile = ON.durab or ON.blades
			if ON.deepscan and (Scan.dirty or (missing and now - Scan.lastGC > 45) or (volatile and now - Scan.lastGC > slow(25))) then
				Scan.lastGC = now
				task.spawn(scanGC)
			end
			Scan.dirty = false
		end
	end
end)

------------------------------------------------------------------
-- HOOK DE REMOTES (solo se instala si activas algo que lo necesita)
------------------------------------------------------------------
local BLOCK = {
	antiwipe = { "wipe", "permadeath", "resetdata", "deletedata", "perma" },
	nodetect = { "detect", "aggro", "spotted" },
	antiburn = { "burn" },
	antihook = { "hooked", "grabbed", "enemyhook" },
}
local Hook = { installed = false, learning = nil, anyBlock = false, cache = {} }
for _, l in pairs(BLOCK) do IGNORE[l] = true end
IGNORE[BLOCK] = true
IGNORE[Hook] = true

local function blockedName(name)
	local v = Hook.cache[name]
	if v ~= nil then return v end
	v = false
	local l = norm(name)
	for toggle, pats in pairs(BLOCK) do
		if ON[toggle] and has(l, pats) then v = true break end
	end
	Hook.cache[name] = v
	return v
end

function Hook.install()
	if Hook.installed then return true end
	if not (hookmetamethod and getnamecallmethod) then return false end
	local wrap = newcclosure or function(f) return f end
	local old
	local ok = pcall(function()
		old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
			local m = getnamecallmethod()
			if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance"
				and (not checkcaller or not checkcaller()) then
				if Hook.anyBlock and blockedName(self.Name) then return nil end
				local L = Hook.learning
				if L then L.hits[#L.hits + 1] = { remote = self, method = m, args = table.pack(...) } end
			end
			return old(self, ...)
		end))
	end)
	Hook.installed = ok and old ~= nil
	blog("hook de remotes: " .. tostring(Hook.installed))
	return Hook.installed
end

------------------------------------------------------------------
-- TITANES / SHIFTERS: nuca, piernas, lista
------------------------------------------------------------------
local NAPE_PAT = { "nape", "weakpoint", "weakspot" }
local LEG_PAT = { "leg", "knee", "ankle", "shin", "thigh", "foot", "calf" }
local NAPES = setmetatable({}, { __mode = "k" })

local function modelRoot(inst)
	local cur, best = inst, nil
	while cur and cur ~= workspace and cur ~= game do
		if cur:IsA("Model") then best = cur end
		cur = cur.Parent
	end
	return best
end

local GiftPrompts = {}
local function considerPrompt(d)
	if d:IsA("ProximityPrompt") then
		local nm = norm((d.Parent and d.Parent.Name or "") .. d.ObjectText .. d.Name)
		if has(nm, { "gift", "present", "regalo" }) then GiftPrompts[d] = true end
	end
end
local function consNape(d)
	if d:IsA("BasePart") then
		local n = d.Name:lower()
		if n:find("nape", 1, true) or n:find("weak", 1, true) then
			if has(norm(n), NAPE_PAT) then NAPES[d] = true end
		end
	elseif d:IsA("ProximityPrompt") then
		considerPrompt(d)
	end
end
mod("nucas", function()
	task.wait(FAST and 1 or 4) -- deja que el juego termine de cargar antes de recorrer el mapa
	blog("escaneo de nucas: inicio")
	local n = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		consNape(d)
		n = n + 1
		if n % 200 == 0 then task.wait() end
	end
	blog("escaneo de nucas: fin")
end)
-- instancias nuevas: solo se anotan y se procesan en tandas (no frena la entrada a servidores llenos)
local AddQ, AddN = {}, 0
mod("nucas-nuevas", function()
	connect(workspace.DescendantAdded, function(d) AddN = AddN + 1 AddQ[AddN] = d end)
	local head = 1
	while Alive do
		task.wait(0.1)
		local stop = math.min(AddN, head + 149)
		for i = head, stop do
			local d = AddQ[i]
			AddQ[i] = nil
			if d then pcall(consNape, d) end
		end
		head = stop + 1
		if head > AddN then head, AddN = 1, 0 end
	end
end)

-- modelo -> parte de la nuca (resultado en cache 0.25 s: lo piden varios sistemas a la vez)
local tmCache, tmT = {}, 0
local function titanModels()
	local now = tick()
	if now - tmT < 0.25 then return tmCache end
	tmT = now
	local set = {}
	local me = getChar()
	for p in pairs(NAPES) do
		if p.Parent then
			if p:IsDescendantOf(workspace) then
				local m = modelRoot(p)
				if m and m ~= me and not set[m] then set[m] = p end
			end
		else
			NAPES[p] = nil
		end
	end
	tmCache = set
	return set
end

local ORIG = setmetatable({}, { __mode = "k" })
local NapeBig = setmetatable({}, { __mode = "k" })
local function isDead(m)
	local h = m and m:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health <= 0
end
-- El hitbox se agranda en la parte REAL (invisible) y una copia soldada con el tamano original
-- mantiene el aspecto del titan igual: asi no se ve deformado ni "buguado".
local DECOY_KEEP = { SpecialMesh = true, Decal = true, Texture = true, SurfaceAppearance = true, BlockMesh = true, CylinderMesh = true, FileMesh = true }
local function makeDecoy(p, o)
	if o.decoy or o.Transparency >= 0.9 then return end
	pcall(function()
		local arch = p.Archivable
		p.Archivable = true
		local d = p:Clone()
		p.Archivable = arch
		if not d then return end
		for _, x in ipairs(d:GetDescendants()) do
			if not DECOY_KEEP[x.ClassName] then pcall(function() x:Destroy() end) end
		end
		d.Name = "Visual"
		d.Anchored = false
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.Massless = true
		d.Size = o.Size
		d.Transparency = o.Transparency
		d.CFrame = p.CFrame
		local w = Instance.new("WeldConstraint")
		w.Part0 = p
		w.Part1 = d
		w.Parent = d
		d.Parent = p.Parent
		o.decoy = d
		o.decals = {}
		for _, x in ipairs(p:GetChildren()) do
			if x:IsA("Decal") or x:IsA("Texture") then o.decals[x] = x.Transparency x.Transparency = 1 end
		end
		p.Transparency = 1
	end)
end
local function restorePart(p)
	local o = ORIG[p]
	if not o then return end
	ORIG[p] = nil
	pcall(function()
		if o.decoy then o.decoy:Destroy() end
		for x, t in pairs(o.decals or {}) do if x.Parent then x.Transparency = t end end
		if p.Parent then
			p.Size = o.Size
			p.CanCollide = o.CanCollide
			p.Massless = o.Massless
			p.Transparency = o.Transparency
		end
	end)
end
local function setSize(p, size, cat)
	local o = ORIG[p]
	if not o then
		o = { Size = p.Size, CanCollide = p.CanCollide, Massless = p.Massless, Transparency = p.Transparency, cat = cat }
		ORIG[p] = o
	end
	o.cat = cat
	o.set = size
	if cat ~= "human" and size ~= o.Size then makeDecoy(p, o) end
	if p.Size ~= size then p.Size = size end
	if p.CanCollide then p.CanCollide = false end
	if not p.Massless then p.Massless = true end
end
-- escala SIEMPRE desde el tamano original (no se acumula al mover el slider)
local function scaleFromBase(p, mult, cat)
	local o = ORIG[p]
	if o and o.set and p.Size ~= o.set and (p.Size - o.set).Magnitude > 0.05 then
		o.Size = p.Size -- el juego lo reescalo: nuevo tamano base
	end
	if mult <= 1.001 then
		if o then restorePart(p) end
		return
	end
	local base = o and o.Size or p.Size
	setSize(p, base * mult, cat)
end
local function restoreCat(cat)
	for p, o in pairs(ORIG) do
		if o.cat == cat then restorePart(p) end
	end
end

local LegCache = setmetatable({}, { __mode = "k" })
local function legsOf(model)
	local c = LegCache[model]
	if c and tick() - c.t < 5 then return c.list end
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local nm = norm(d.Name)
			if has(nm, LEG_PAT) and not has(nm, NAPE_PAT) then list[#list + 1] = d end
		end
	end
	LegCache[model] = { t = tick(), list = list }
	return list
end

mod("hitbox", function()
	local wasNape, wasLeg, wasHuman, wasBlade = false, false, false, false
	while Alive do
		task.wait(slow(ON.nape and 0.12 or 0.3))
		pcall(function()
			if ON.nape then
				wasNape = true
				for m, nape in pairs(titanModels()) do
					if nape.Parent and isDead(m) then
						restorePart(nape)
					elseif nape.Parent then
						local root = getRoot()
						local big = NapeBig[nape]
						local d = root and (nape.Position - root.Position).Magnitude or 0
						if big then big = d <= VAL.NapeNear * 1.25 else big = d <= VAL.NapeNear end
						scaleFromBase(nape, big and math.clamp(VAL.NapeMult, 1, 30) or 1, "nape")
						NapeBig[nape] = big
					end
				end
			elseif wasNape then
				wasNape = false
				restoreCat("nape")
			end
			if ON.legs then
				wasLeg = true
				for m in pairs(titanModels()) do
					for _, p in ipairs(legsOf(m)) do
						if p.Parent then
							if isDead(m) then restorePart(p) else scaleFromBase(p, math.clamp(VAL.LegMult, 1, 15), "leg") end
						end
					end
				end
			elseif wasLeg then
				wasLeg = false
				restoreCat("leg")
			end
				if ON.bladebox then
					wasBlade = true
					local ch = getChar()
					if ch then
						local m = math.clamp(VAL.BladeMult, 1, 12)
						for _, d in ipairs(ch:GetDescendants()) do
							if d:IsA("BasePart") and d.Parent and (d:FindFirstAncestorOfClass("Tool") or d.Parent:IsA("Tool")) then
								local nm = norm(d.Name)
								if has(nm, { "blade", "sword", "hoja", "lamina", "steel", "edge" }) then
									scaleFromBase(d, m, "blade")
								end
							end
						end
					end
				elseif wasBlade then
					wasBlade = false
					restoreCat("blade")
				end
			if ON.human or ON.pvpaim then
				wasHuman = true
				local s = math.clamp(VAL.HumanSize, 2, 30)
				local multi = #Teams:GetTeams() > 1
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= Player and plr.Character and not (multi and plr.Team ~= nil and plr.Team == Player.Team) then
						local r = plr.Character:FindFirstChild("HumanoidRootPart")
						if r then
							setSize(r, Vector3.new(s, s, s), "human")
							if r.Transparency ~= 1 then r.Transparency = 1 end
						end
					end
				end
			elseif wasHuman then
				wasHuman = false
				restoreCat("human")
			end
		end)
	end
end)

------------------------------------------------------------------
-- CAPUCHA VISIBLE: se ve en tu personaje (si el juego la quita o la oculta, se vuelve a poner)
------------------------------------------------------------------
local HOOD_PAT = { "hood", "capucha", "cowl" }
mod("capucha", function()
	local keep, keepChar, lastSeen = nil, nil, 0
	while Alive do
		task.wait(slow(0.5))
		if ON.hoodvisual or ON.hood then
			pcall(function()
				local ch = getChar()
				if not ch then return end
				if keepChar ~= ch then keep, keepChar, lastSeen = nil, ch, tick() end
				local found = false
				for _, d in ipairs(ch:GetDescendants()) do
					if d:IsA("Accessory") and has(norm(d.Name), HOOD_PAT) then
						found = true
						if not keep then pcall(function() d.Archivable = true keep = d:Clone() end) end
						for _, q in ipairs(d:GetDescendants()) do
							if q:IsA("BasePart") then
								if q.Transparency > 0 then q.Transparency = 0 end
								if q.LocalTransparencyModifier > 0 then q.LocalTransparencyModifier = 0 end
							end
						end
					elseif d:IsA("BasePart") and has(norm(d.Name), HOOD_PAT) and not d:FindFirstAncestorOfClass("Accessory") then
						found = true
						if d.Transparency > 0 then d.Transparency = 0 end
						if d.LocalTransparencyModifier > 0 then d.LocalTransparencyModifier = 0 end
					end
				end
				if found then
					lastSeen = tick()
				elseif keep and tick() - lastSeen > 1 then
					local hum = ch:FindFirstChildOfClass("Humanoid")
					if hum then hum:AddAccessory(keep:Clone()) lastSeen = tick() end
				end
			end)
		end
	end
end)

------------------------------------------------------------------
-- AUTO RECARGAR HOJAS: pulsa R cuando las hojas se rompen o se acaban
------------------------------------------------------------------
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local function pressR()
	if not VIM then return end
	pcall(function()
		VIM:SendKeyEvent(true, Enum.KeyCode.R, false, game)
		task.wait(0.05)
		VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game)
	end)
end
local BLADE_NAMES = { "blade", "sword", "hoja", "lamina", "durab", "sharp", "ammo", "uses" }
local BLADE_EXC = { "max", "cost", "damage", "dmg", "name", "model", "color", "sound", "price", "speed", "rate", "range" }
local function bladeValueBroken(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ValueBase") then
			local nm = norm(d.Name)
			if has(nm, BLADE_NAMES) and not has(nm, BLADE_EXC) then
				local v = d.Value
				if type(v) == "number" and v <= 0 then return true end
				if type(v) == "boolean" and has(nm, { "broken", "break", "empty" }) and v == true then return true end
			end
		end
	end
	for k, v in pairs(inst:GetAttributes()) do
		local nm = norm(k)
		if has(nm, BLADE_NAMES) and not has(nm, BLADE_EXC) then
			if type(v) == "number" and v <= 0 then return true end
			if type(v) == "boolean" and has(nm, { "broken", "break", "empty" }) and v == true then return true end
		end
	end
	return false
end
mod("autorecarga", function()
	local lastPress, seenBlade = 0, setmetatable({}, { __mode = "k" })
	while Alive do
		task.wait(slow(0.4))
		if ON.autoreload then
			pcall(function()
				local ch = getChar()
				local hum = getHum()
				if not ch or not hum or hum.Health <= 0 or UIS:GetFocusedTextBox() then return end
				if tick() - lastPress < 2 then return end
				local broken = bladeValueBroken(ch) or bladeValueBroken(Player)
				local tool = ch:FindFirstChildOfClass("Tool")
				if tool and has(norm(tool.Name), BLADE_NAMES) then
					-- hojas que estaban puestas y desaparecieron = rotas
					local have = false
					for _, d in ipairs(tool:GetDescendants()) do
						if d:IsA("BasePart") and has(norm(d.Name), { "blade", "hoja", "lamina", "steel" }) then have = true break end
					end
					if have then seenBlade[tool] = true elseif seenBlade[tool] then broken = true end
				end
				if broken then
					lastPress = tick()
					pressR()
				end
			end)
		end
	end
end)

------------------------------------------------------------------
-- APRENDER ACCIONES (golpe a la nuca, lanzar hoja)  ->  Kill-Aura / Blade Throw Spam
------------------------------------------------------------------
local Learned = {}
IGNORE[Learned] = true

local function classify(a)
	local tp = typeof(a)
	if tp == "string" or tp == "number" or tp == "boolean" then return { raw = a } end
	if tp == "Instance" then
		if a == getChar() then return { k = "me" } end
		local m = modelRoot(a)
		if m and m ~= getChar() and not Players:GetPlayerFromCharacter(m) then
			for p in pairs(NAPES) do
				if p.Parent and p:IsDescendantOf(m) then
					if a == m then return { k = "tmodel" } end
					return { k = "tpart", n = a.Name }
				end
			end
		end
		return { keep = a }
	end
	if tp == "Vector3" or tp == "CFrame" then
		local pos = (tp == "Vector3") and a or a.Position
		for _, nape in pairs(titanModels()) do
			if (nape.Position - pos).Magnitude < 30 then return { k = (tp == "Vector3") and "pos" or "cfpos" } end
		end
		return { keep = a }
	end
	return { keep = a }
end

local function learn(id, secs)
	if Hook.learning then return end
	if not Hook.install() then notify("tu executor no tiene hookmetamethod") return end
	Hook.learning = { hits = {} }
	for i = secs, 1, -1 do
		if not Alive then break end
		setStatus(("APRENDER %s: hazlo 2-3 veces (%ds)"):format(id == "hit" and "GOLPE A NUCA" or "LANZAR HOJA", i))
		task.wait(1)
	end
	local L = Hook.learning
	Hook.learning = nil
	if not L then return end
	local count = {}
	for _, h in ipairs(L.hits) do count[h.remote] = (count[h.remote] or 0) + 1 end
	local keep, seen = {}, {}
	for _, h in ipairs(L.hits) do
		-- descarta remotes que se disparan sin parar (movimiento, camara...)
		if count[h.remote] <= 10 and not seen[h.remote] then
			seen[h.remote] = true
			local tpl = {}
			for i = 1, h.args.n do tpl[i] = classify(h.args[i]) end
			keep[#keep + 1] = { remote = h.remote, method = h.method, n = h.args.n, tpl = tpl }
		end
	end
	Learned[id] = keep
	if #keep == 0 then notify("no vi ninguna accion: intentalo de nuevo") else notify(("aprendido (%d llamada/s)"):format(#keep)) end
end

local function buildArgs(e, titan, nape)
	local args = {}
	for i = 1, e.n do
		local tpl, v = e.tpl[i], nil
		if tpl.raw ~= nil then v = tpl.raw
		elseif tpl.keep ~= nil then v = tpl.keep
		elseif tpl.k == "me" then v = getChar()
		elseif titan then
			if tpl.k == "tmodel" then v = titan
			elseif tpl.k == "tpart" then v = titan:FindFirstChild(tpl.n, true) or nape
			elseif tpl.k == "pos" then v = nape and nape.Position
			elseif tpl.k == "cfpos" then v = nape and nape.CFrame end
		end
		args[i] = v
	end
	return args
end

local function fire(e, args)
	local r = e.remote
	if not (r and r.Parent) then return end
	if e.method == "InvokeServer" then
		task.spawn(function() pcall(function() r:InvokeServer(table.unpack(args, 1, e.n)) end) end)
	else
		pcall(function() r:FireServer(table.unpack(args, 1, e.n)) end)
	end
end

-- Kill-Aura: repite el golpe aprendido sobre las nucas cercanas
mod("killaura", function()
	while Alive do
		task.wait(1 / math.clamp(VAL.AuraRate, 1, 20))
		if ON.killaura and Learned.hit and #Learned.hit > 0 then
			pcall(function()
				local root = getRoot()
				if not root then return end
				local list = {}
				for m, nape in pairs(titanModels()) do
					local d = (nape.Position - root.Position).Magnitude
					if d <= VAL.AuraRange then list[#list + 1] = { m = m, n = nape, d = d } end
				end
				table.sort(list, function(a, b) return a.d < b.d end)
				for i = 1, math.min(3, #list) do
					for _, e in ipairs(Learned.hit) do fire(e, buildArgs(e, list[i].m, list[i].n)) end
				end
			end)
		end
	end
end)

-- Blade Throw Spam
mod("throwspam", function()
	while Alive do
		task.wait(1 / math.clamp(VAL.ThrowRate, 1, 30))
		if ON.throwspam and Learned.throw and #Learned.throw > 0 then
			pcall(function()
				for _, e in ipairs(Learned.throw) do fire(e, buildArgs(e, nil, nil)) end
			end)
		end
	end
end)

------------------------------------------------------------------
-- VELOCIDADES (shifter / caballo)
------------------------------------------------------------------
local shiftedFlag, shiftedT = false, 0
connect(RunService.Heartbeat, function()
	local hum = getHum()
	if ON.shiftspeed and hum then
		if tick() - shiftedT > 0.5 then
			shiftedT = tick()
			shiftedFlag = false
			local c = getChar()
			for p in pairs(NAPES) do
				if c and p.Parent and p:IsDescendantOf(c) then shiftedFlag = true break end
			end
		end
		if shiftedFlag then hum.WalkSpeed = math.clamp(VAL.ShiftSpeed, 8, 120) end
	end
	if ON.horsespeed or ON.horsegod then
		local m, seat = mountedModel()
		if m then
			local hh = m:FindFirstChildOfClass("Humanoid")
			if ON.horsespeed then
				local sp = math.clamp(VAL.HorseSpeed, 8, 150)
				if hh then hh.WalkSpeed = sp end
				if seat and seat:IsA("VehicleSeat") then seat.MaxSpeed = sp end
			end
			if ON.horsegod and hh then hh.Health = hh.MaxHealth end
		end
	end
end)

------------------------------------------------------------------
-- ESP
------------------------------------------------------------------
local espParent = (gethui and gethui()) or game:GetService("CoreGui")
local espFolder = Instance.new("Folder")
espFolder.Name = rname()
pcall(function() espFolder.Parent = espParent end)
local ESPobjs = {}

-- ¿es un jugador del bando Warriors? (equipo, atributo o valor de texto que contenga "warrior")
local WARRIOR_PAT = { "warrior" }
local SHIFT_PAT = { "warrior", "shifter", "armored", "colossal", "femaletitan", "transform" }
local Shifters = setmetatable({}, { __mode = "k" }) -- jugadores vistos transformados alguna vez
local function isWarrior(plr)
	local t = plr.Team
	if t and has(norm(t.Name), WARRIOR_PAT) then return true end
	local c = plr.Character
	for _, key in ipairs({ "Team", "Faction", "Role", "Class", "Side", "Group", "Rank", "Branch" }) do
		local a = plr:GetAttribute(key)
		if type(a) == "string" and has(norm(a), WARRIOR_PAT) then return true end
		local ca = c and c:GetAttribute(key)
		if type(ca) == "string" and has(norm(ca), WARRIOR_PAT) then return true end
	end
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		for _, d in ipairs(ls:GetChildren()) do
			if d:IsA("StringValue") and has(norm(d.Value), WARRIOR_PAT) then return true end
		end
	end
	for _, d in ipairs(plr:GetChildren()) do
		if d:IsA("StringValue") and has(norm(d.Value), WARRIOR_PAT) then return true end
	end
	-- busqueda ancha: cualquier valor/atributo con "warrior" en el nombre o el texto (datos del jugador y del personaje)
	local function attrHit(inst)
		for k, v in pairs(inst:GetAttributes()) do
			if has(norm(k), SHIFT_PAT) and v ~= false and v ~= 0 and v ~= "" then return true end
			if type(v) == "string" and has(norm(v), SHIFT_PAT) then return true end
		end
		return false
	end
	if attrHit(plr) or (c and attrHit(c)) then return true end
	for _, d in ipairs(plr:GetDescendants()) do
		if d:IsA("ValueBase") then
			local nm = norm(d.Name)
			if has(nm, SHIFT_PAT) and d.Value ~= false and d.Value ~= 0 and d.Value ~= "" then return true end
			if d:IsA("StringValue") and has(norm(d.Value), SHIFT_PAT) then return true end
		end
	end
	-- texto sobre la cabeza del jugador (rango / titulo) que diga "warrior"
	if c then
		for _, d in ipairs(c:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and has(norm(d.Text), SHIFT_PAT) then return true end
		end
	end
	-- herramientas de transformacion en la mochila / en la mano
	local function toolHit(cont)
		if not cont then return false end
		for _, t in ipairs(cont:GetChildren()) do
			if t:IsA("Tool") and has(norm(t.Name), { "transform", "shift", "titanform" }) then return true end
		end
		return false
	end
	if toolHit(plr:FindFirstChild("Backpack")) or toolHit(c) then return true end
	return false
end

local WC = setmetatable({}, { __mode = "k" })
local function warriorCached(plr)
	local c, now = WC[plr], tick()
	if c and now - c.t < 6 then return c.v end
	local v = isWarrior(plr)
	WC[plr] = { t = now, v = v }
	return v
end

-- si ese jugador esta transformado, devuelve (modelo del titan, nuca)
local TitanOwner = setmetatable({}, { __mode = "k" }) -- titan -> jugador que se transformo ahi
local TitanSeen = setmetatable({}, { __mode = "k" })
local function trackOwners(tm)
	local late = tick() - bootTime > 20
	for m, nape in pairs(tm) do
		if not TitanSeen[m] then
			TitanSeen[m] = true
			if late and nape and nape.Parent then
				local best, bd = nil, 18
				for _, plr in ipairs(Players:GetPlayers()) do
					local r = plr ~= Player and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
					if r then
						local d = (r.Position - nape.Position).Magnitude
						if d < bd then best, bd = plr, d end
					end
				end
				if best then TitanOwner[m] = best end
			end
		end
	end
end
local OWNER_KEYS = { "Owner", "Player", "User", "Shifter", "UserId", "PlayerName", "Creator" }
local function playerTitan(plr, tm)
	local c = plr.Character
	if c then
		for p in pairs(NAPES) do
			if p.Parent and p:IsDescendantOf(c) then return c, p end
		end
	end
	for m, nape in pairs(tm) do
		if TitanOwner[m] == plr and m.Parent then return m, nape end
	end
	local pn, dn = norm(plr.Name), norm(plr.DisplayName)
	for m, nape in pairs(tm) do
		local nm = norm(m.Name)
		if nm:find(pn, 1, true) or (#dn > 2 and nm:find(dn, 1, true)) then return m, nape end
		for _, key in ipairs(OWNER_KEYS) do
			local a = m:GetAttribute(key)
			if a ~= nil and (tostring(a) == plr.Name or tostring(a) == tostring(plr.UserId)) then return m, nape end
			local v = m:FindFirstChild(key)
			if v and v:IsA("ValueBase") and (tostring(v.Value) == plr.Name or tostring(v.Value) == tostring(plr.UserId)) then return m, nape end
		end
	end
	return nil
end

local function clearEsp(m)
	local o = ESPobjs[m]
	if o then
		pcall(function() o.hl:Destroy() end)
		pcall(function() o.bb:Destroy() end)
		ESPobjs[m] = nil
	end
end

mod("esp", function()
	while Alive do
		task.wait(slow(0.4))
		pcall(function()
			local root = getRoot()
			local want, order = {}, {}
			local tm
			if ON.espwarrior then
				tm = titanModels()
				trackOwners(tm)
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= Player then
						local m, nape = playerTitan(plr, tm)
						if m then Shifters[plr] = true end
						if warriorCached(plr) or Shifters[plr] then
							local c = plr.Character
							if c and c ~= m then -- forma HUMANA marcada (tambien mientras es titan, si el cuerpo sigue ahi)
								local part = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
								if part then
									want[c] = { col = Color3.fromRGB(255, 190, 40), part = part, name = plr.Name .. " [WARRIOR]", pri = true }
								end
							end
							if m and not isDead(m) then -- forma TITAN marcada
								want[m] = { col = Color3.fromRGB(255, 100, 30), part = nape, name = plr.Name .. " [WARRIOR TITAN]", pri = true }
							end
						end
					end
				end
			end
			if ON.espwarrior and ON.espall then
				for _, plr in ipairs(Players:GetPlayers()) do
					local c = plr.Character
					if plr ~= Player and c and not want[c] then
						local part = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
						if part then want[c] = { col = Color3.fromRGB(190, 190, 190), part = part, name = plr.Name } end
					end
				end
			end
			if ON.esptitan then
				for m, nape in pairs(tm or titanModels()) do
					if not want[m] and not isDead(m) then
						want[m] = { col = Color3.fromRGB(255, 80, 80), part = nape, name = "TITAN" }
					end
				end
			end
			if ON.espplayer then
				for _, plr in ipairs(Players:GetPlayers()) do
					local c = plr.Character
					if plr ~= Player and c and not want[c] then
						want[c] = { col = Color3.fromRGB(255, 255, 255), part = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"), name = plr.Name }
					end
				end
			end
			for m, info in pairs(want) do
				local pos = info.part and info.part.Position
				local d = (pos and root) and (pos - root.Position).Magnitude or 1e9
				order[#order + 1] = { m = m, info = info, d = d, pri = info.pri and 0 or 1 }
			end
			table.sort(order, function(a, b)
				if a.pri ~= b.pri then return a.pri < b.pri end
				return a.d < b.d
			end)
			local keep = {}
			for i = 1, math.min(24, #order) do -- Roblox solo dibuja ~31 Highlights
				local m, info = order[i].m, order[i].info
				keep[m] = true
				local o = ESPobjs[m]
				if not o then
					local hl = Instance.new("Highlight")
					hl.FillTransparency = 0.75
					hl.OutlineTransparency = 0
					hl.Adornee = m
					hl.Parent = espFolder
					local bb = Instance.new("BillboardGui")
					bb.AlwaysOnTop = true
					bb.Size = UDim2.new(0, 120, 0, 18)
					bb.StudsOffset = Vector3.new(0, 2, 0)
					bb.Adornee = info.part
					bb.Parent = espFolder
					local tl = Instance.new("TextLabel")
					tl.Size = UDim2.new(1, 0, 1, 0)
					tl.BackgroundTransparency = 1
					tl.Font = Enum.Font.GothamBold
					tl.TextSize = 12
					tl.TextStrokeTransparency = 0.4
					tl.Parent = bb
					o = { hl = hl, bb = bb, tl = tl }
					ESPobjs[m] = o
				end
				o.hl.FillColor, o.hl.OutlineColor = info.col, info.col
				o.tl.TextColor3 = info.col
				local txt = ("%s  %dm"):format(info.name, math.floor(order[i].d))
				if o.tl.Text ~= txt then o.tl.Text = txt end
			end
			for m in pairs(ESPobjs) do
				if not keep[m] or not m.Parent then clearEsp(m) end
			end
		end)
	end
end)

------------------------------------------------------------------
-- EXTRAS: ropa, emotes, equipo, staff, regalos
------------------------------------------------------------------
------------------------------------------------------------------
-- AYUDA DE PUNTERIA (nuca de titanes / PvP) y CLICK TP
------------------------------------------------------------------
local function aimCandidates(forceNape)
	local out = {}
	if ON.napeaim or forceNape then
		for _, nape in pairs(titanModels()) do out[#out + 1] = nape end
	end
	if ON.pvpaim then
		local multiTeam = #Teams:GetTeams() > 1
		for _, plr in ipairs(Players:GetPlayers()) do
			local c = plr.Character
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			if plr ~= Player and hum and hum.Health > 0 and not (multiTeam and plr.Team ~= nil and plr.Team == Player.Team) then
				local part = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
				if part then out[#out + 1] = part end
			end
		end
	end
	return out
end

local aimCache, aimT = {}, 0
local aimBind = rname()
local mouseDelta, lastMove = Vector2.new(), 0
connect(UIS.InputChanged, function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseMovement then
		mouseDelta = Vector2.new(inp.Delta.X, inp.Delta.Y)
		if mouseDelta.Magnitude > 0 then lastMove = tick() end
	end
end)

-- Q / E (ganchos ODM): durante un instante la camara se orienta al objetivo para que el gancho acierte
local hookWindow = 0
connect(UIS.InputBegan, function(inp)
	if not ON.hookassist or UIS:GetFocusedTextBox() then return end
	if inp.KeyCode == Enum.KeyCode.Q or inp.KeyCode == Enum.KeyCode.E then hookWindow = tick() + 0.35 end
end)

local function aimStep()
	local hooking = ON.hookassist and tick() < hookWindow
	if not (ON.napeaim or ON.pvpaim or hooking) then return end
	if UIS:GetFocusedTextBox() then return end
	if not hooking then
		if ON.aimhold and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
		-- solo ayuda mientras TU mueves el mouse: nunca te deja la camara bloqueada
		if tick() - lastMove > 0.25 then return end
	end
	local cam, root = workspace.CurrentCamera, getRoot()
	if not (cam and root) then return end
	if hooking or tick() - aimT > 0.25 then
		aimT = tick()
		aimCache = aimCandidates(hooking)
	end
	local fov = hooking and VAL.HookAssistFOV or VAL.AimFOV
	local look, origin = cam.CFrame.LookVector, cam.CFrame.Position
	local best, bestAng
	for _, p in ipairs(aimCache) do
		if p.Parent then
			local v = p.Position - origin
			local dist = v.Magnitude
			if dist > 1 and dist <= VAL.AimRange then
				local ang = math.deg(math.acos(math.clamp(look:Dot(v.Unit), -1, 1)))
				if ang <= fov and (not bestAng or ang < bestAng) then best, bestAng = p, ang end
			end
		end
	end
	if not best or bestAng < 0.5 then return end
	if not hooking and mouseDelta.Magnitude > 4 then
		-- si te alejas del objetivo, la ayuda se suelta (libertad total)
		local sp = cam:WorldToViewportPoint(best.Position)
		local c = cam.ViewportSize / 2
		local toT = Vector2.new(sp.X - c.X, sp.Y - c.Y)
		if toT.Magnitude > 1 and toT.Unit:Dot(mouseDelta.Unit) < -0.2 then return end
	end
	local pull = hooking and 0.6 or math.clamp(VAL.AimPull, 0.02, 0.5)
	local maxStep = hooking and 8 or math.clamp(VAL.AimMaxStep, 0.2, 5)
	local factor = math.min(pull, maxStep / math.max(bestAng, 0.01))
	cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(origin, best.Position), factor)
end
-- se ejecuta DESPUES de la camara del juego, asi solo la empuja un poco
mod("aim", function()
	RunService:BindToRenderStep(aimBind, Enum.RenderPriority.Camera.Value + 1, function() pcall(aimStep) end)
end)

local tpToken = 0
connect(UIS.InputBegan, function(inp, processed)
	if processed or not ON.clicktp then return end
	if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local cam, root = workspace.CurrentCamera, getRoot()
	if not (cam and root) then return end
	local loc = UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(loc.X, loc.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getChar() }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	if res then
		local target = res.Position + Vector3.new(0, 4, 0)
		if ON.tpsmooth then
			-- TP suave: avanza en pasos pequenos a velocidad limitada (los anti-teleport suelen vigilar los saltos grandes)
			tpToken = tpToken + 1
			local my = tpToken
			task.spawn(function()
				local t0 = tick()
				while Alive and my == tpToken and tick() - t0 < 40 do
					local r = getRoot()
					if not r then break end
					local dt = task.wait()
					dt = tonumber(dt) or 0.03
					local cur = r.CFrame.Position
					local delta = target - cur
					local dist = delta.Magnitude
					if dist < 2 then break end
					local step = math.min(dist, math.clamp(VAL.TPSpeed, 30, 500) * math.min(dt, 0.1))
					r.CFrame = CFrame.new(cur + delta.Unit * step) * (r.CFrame - r.CFrame.Position)
					r.AssemblyLinearVelocity = Vector3.zero
				end
			end)
		else
			root.CFrame = CFrame.new(target) * (root.CFrame - root.CFrame.Position)
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end)

local function fetchClothing(id, class)
	id = tonumber(id)
	if not id then return nil end
	local obj
	pcall(function()
		local t = game:GetObjects("rbxassetid://" .. id)
		obj = t and t[1]
	end)
	if obj then
		local o = obj:IsA(class) and obj or obj:FindFirstChildOfClass(class)
		if o then return o:Clone() end
	end
	local x = Instance.new(class)
	if class == "Shirt" then x.ShirtTemplate = "rbxassetid://" .. id else x.PantsTemplate = "rbxassetid://" .. id end
	return x
end

local function applyClothes(shirtId, pantsId)
	local c = getChar()
	if not c then return end
	local function put(id, class)
		if not id or id == "" then return end
		local n = fetchClothing(id, class)
		if not n then notify("ID de ropa invalido") return end
		for _, old in ipairs(c:GetChildren()) do
			if old:IsA(class) then old:Destroy() end
		end
		n.Parent = c
	end
	put(shirtId, "Shirt")
	put(pantsId, "Pants")
	notify("ropa aplicada (solo la ves tu)")
end

local EmoteTrack
local function playEmote(id)
	local hum = getHum()
	id = tonumber(id)
	if not (hum and id) then notify("pon un ID de animacion") return end
	local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 2)
	if not animator then return end
	if EmoteTrack then pcall(function() EmoteTrack:Stop() end) end
	local a = Instance.new("Animation")
	a.AnimationId = "rbxassetid://" .. id
	local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
	if not (ok and tr) then notify("no pude cargar esa animacion") return end
	EmoteTrack = tr
	tr.Priority = Enum.AnimationPriority.Action
	tr.Looped = true
	tr:Play()
end
local function stopEmote()
	if EmoteTrack then pcall(function() EmoteTrack:Stop() end) EmoteTrack = nil end
end

local teamIdx = 0
local function nextTeam()
	local list = Teams:GetTeams()
	if #list == 0 then notify("no hay equipos") return end
	teamIdx = teamIdx % #list + 1
	pcall(function() Player.Team = list[teamIdx] end)
	notify("equipo (local): " .. list[teamIdx].Name)
end

local Staff = { warned = {} }
function Staff.check(plr)
	if not ON.staff or plr == Player or Staff.warned[plr] then return end
	local gid = (game.CreatorType == Enum.CreatorType.Group) and game.CreatorId or nil
	if not gid then return end
	local ok, rank = pcall(function() return plr:GetRankInGroup(gid) end)
	if ok and rank >= VAL.StaffRank then
		Staff.warned[plr] = true
		notify(("STAFF en el servidor: %s (rango %d)"):format(plr.Name, rank))
	end
end
connect(Players.PlayerAdded, function(plr) task.spawn(Staff.check, plr) end)
function Staff.all()
	for _, plr in ipairs(Players:GetPlayers()) do task.spawn(Staff.check, plr) end
end

-- recoger regalos cercanos (la lista de prompts se arma una vez y se actualiza por eventos)
mod("regalos", function()
	while Alive do
		task.wait(slow(0.6))
		if ON.gifts and fireproximityprompt then
			pcall(function()
				local root = getRoot()
				if not root then return end
				for d in pairs(GiftPrompts) do
					if not d.Parent then
						GiftPrompts[d] = nil
					elseif d.Enabled then
						local part = d.Parent:IsA("BasePart") and d.Parent or d.Parent:FindFirstChildWhichIsA("BasePart", true)
						if part and (part.Position - root.Position).Magnitude <= math.max(d.MaxActivationDistance, 12) then
							fireproximityprompt(d)
						end
					end
				end
			end)
		end
	end
end)

------------------------------------------------------------------
-- INSPECTOR: guarda AOTFW_dump.txt con lo que hay de verdad en el juego
------------------------------------------------------------------
local function inspect()
	if not writefile then notify("tu executor no tiene writefile") return end
	notify("Inspector: recopilando... (unos segundos)")
	local out = {}
	local function add(s) out[#out + 1] = s end
	add("== AOT FW dump ==  PlaceId " .. tostring(game.PlaceId) .. "  " .. os.date("%Y-%m-%d %H:%M"))

	add("\n-- REMOTES (RemoteEvent / RemoteFunction) --")
	local n = 0
	for _, d in ipairs(game:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			n = n + 1
			if n <= 400 then add(d.ClassName .. "  " .. d:GetFullName()) end
		end
		if n % 800 == 0 then task.wait() end
	end

	add("\n-- VALORES Y ATRIBUTOS (personaje / jugador) --")
	local function dumpInst(root)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("ValueBase") then add(("%s = %s"):format(d:GetFullName(), tostring(d.Value))) end
			for an, av in pairs(d:GetAttributes()) do add(("%s @%s = %s"):format(d:GetFullName(), an, tostring(av))) end
		end
	end
	if getChar() then dumpInst(getChar()) end
	dumpInst(Player)
	local pf = ReplicatedStorage:FindFirstChild(Player.Name)
	if pf then dumpInst(pf) end

	add("\n-- TABLAS EN MEMORIA con claves parecidas a lo que busca el script --")
	if getgc and ON.deepscan then
		local frag = { "gas", "blade", "durab", "stamina", "cooldown", "hook", "hood", "special", "shift", "titan", "emote", "cannon", "burn", "impulse", "dodge" }
		local found, cnt = {}, 0
		for _, t in ipairs(getgc(true)) do
			cnt = cnt + 1
			if cnt % 3000 == 0 then task.wait() end
			if type(t) == "table" and not IGNORE[t] then
				pcall(function()
					local c2 = 0
					for k, v in next, t do
						c2 = c2 + 1
						if c2 > 120 then break end
						if type(k) == "string" and (type(v) == "number" or type(v) == "boolean") then
							local nk = norm(k)
							if has(nk, frag) and #found < 600 then found[#found + 1] = ("%s = %s"):format(k, tostring(v)) end
						end
					end
				end)
			end
		end
		for _, l in ipairs(found) do add(l) end
	else
		add(getgc and "(busqueda profunda desactivada: activala en el menu y repite el Inspector)" or "(tu executor no tiene getgc)")
	end

	add("\n-- TITANES / SHIFTERS (modelos con parte de nuca) --")
	local k = 0
	for m, nape in pairs(titanModels()) do
		k = k + 1
		if k <= 15 then add(("%s   nuca: %s   size %s"):format(m:GetFullName(), nape:GetFullName(), tostring(nape.Size))) end
	end
	add("total: " .. k)

	add("\n-- JUGADORES (equipo / atributos / titan) --")
	local tmI = titanModels()
	for _, plr in ipairs(Players:GetPlayers()) do
		local attrs = {}
		for an, av in pairs(plr:GetAttributes()) do attrs[#attrs + 1] = an .. "=" .. tostring(av) end
		local m = playerTitan(plr, tmI)
		add(("%s  equipo:%s  warrior:%s  titan:%s  attrs:[%s]"):format(plr.Name, plr.Team and plr.Team.Name or "-", tostring(isWarrior(plr)), m and m:GetFullName() or "no", table.concat(attrs, ",")))
		local ls = plr:FindFirstChild("leaderstats")
		if ls then
			for _, d in ipairs(ls:GetChildren()) do if d:IsA("ValueBase") then add("    leaderstats." .. d.Name .. " = " .. tostring(d.Value)) end end
		end
	end

	add("\n-- EQUIPOS --")
	for _, t in ipairs(Teams:GetTeams()) do add(t.Name) end
	add("\nGrupo del juego: " .. tostring(game.CreatorType) .. " " .. tostring(game.CreatorId))

	pcall(function() writefile(DUMP_FILE, table.concat(out, "\n")) end)
	notify("Inspector listo: abre " .. DUMP_FILE .. " en la carpeta workspace y mandamelo")
end

------------------------------------------------------------------
-- INTERFAZ
------------------------------------------------------------------
local COL = {
	bg = Color3.fromRGB(18, 18, 20), card = Color3.fromRGB(28, 28, 31), line = Color3.fromRGB(48, 48, 54),
	text = Color3.fromRGB(228, 228, 232), sub = Color3.fromRGB(128, 128, 138), good = Color3.fromRGB(120, 200, 140),
}
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function round(p, r)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
	new("UIStroke", { Color = COL.line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

loadCfg() -- antes de crear los botones, para que muestren su estado guardado
blog("config cargada")
local gui = new("ScreenGui", { Name = rname(), ResetOnSpawn = false, DisplayOrder = 997 })
if not pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end) or not gui.Parent then
	gui.Parent = Player:WaitForChild("PlayerGui")
end

local main = new("Frame", { Size = UDim2.new(0, 360, 0, 600), Position = UDim2.new(0, 16, 0, 40), BackgroundColor3 = COL.bg, BorderSizePixel = 0 }, gui)
round(main, 10)
local uiScale = new("UIScale", { Scale = math.clamp(VAL.UIScale, 0.8, 1.8) }, main)
local title = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = "  AOT Freedom War  ·  RightShift oculta",
	TextColor3 = COL.text, Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
}, main)
do
	local dragging, ds, sp
	title.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, ds, sp = true, i.Position, main.Position
			i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	connect(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - ds
			main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
		end
	end)
end
local body = new("ScrollingFrame", {
	Size = UDim2.new(1, -16, 1, -38), Position = UDim2.new(0, 8, 0, 32), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, ScrollBarImageColor3 = COL.line, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, main)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)
local ord = 0
local function nxt() ord = ord + 1 return ord end

local function section(text)
	new("TextLabel", { Size = UDim2.new(1, -6, 0, 24), BackgroundTransparency = 1, Text = text, TextColor3 = COL.sub, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = nxt() }, body)
end
local function button(text, cb)
	local b = new("TextButton", { Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = COL.card, Text = text, TextColor3 = COL.text, Font = Enum.Font.GothamMedium, TextSize = 13, LayoutOrder = nxt() }, body)
	round(b, 8)
	b.MouseButton1Click:Connect(function() pcall(cb, b) end)
	return b
end

local BLOCK_IDS = { "antiwipe", "nodetect", "antiburn", "antihook" }
local function onToggle(id)
	blog("toggle " .. id .. " = " .. tostring(ON[id]))
	Hook.cache = {}
	local any = false
	for _, b in ipairs(BLOCK_IDS) do if ON[b] then any = true end end
	Hook.anyBlock = any
	if any then Hook.install() end
	for _, rule in ipairs(RULES) do
		if rule.on == id then
			if ON[id] then Scan.kick() else restoreRule(rule) end
		end
	end
	if id == "staff" and ON.staff then task.spawn(Staff.all) end
	if id == "deepscan" and ON.deepscan then Scan.kick() end
	saveCfg()
end

local Refresh = {}
local function toggle(mark, text, id)
	local b
	local function refresh()
		b.Text = ("%s  %s:  %s"):format(mark, text, ON[id] and "ON" or "OFF")
		b.TextColor3 = ON[id] and COL.good or COL.text
	end
	b = button("", function() ON[id] = not ON[id] refresh() onToggle(id) end)
	Refresh[id] = refresh
	refresh()
end

local activeDrag = nil
connect(UIS.InputChanged, function(i)
	if activeDrag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		activeDrag(i.Position.X)
	end
end)
connect(UIS.InputEnded, function(i)
	if activeDrag and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
		activeDrag = nil
		saveCfg()
	end
end)
local function slider(text, min, max, step, key, fmt, onChange)
	local r = new("Frame", { Size = UDim2.new(1, -6, 0, 48), BackgroundColor3 = COL.card, LayoutOrder = nxt() }, body)
	round(r, 8)
	new("TextLabel", { Size = UDim2.new(1, -70, 0, 18), Position = UDim2.new(0, 10, 0, 4), BackgroundTransparency = 1, Text = text, TextColor3 = COL.text, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, r)
	local val = new("TextLabel", { Size = UDim2.new(0, 56, 0, 18), Position = UDim2.new(1, -64, 0, 4), BackgroundTransparency = 1, Text = "", TextColor3 = COL.good, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right }, r)
	local hit = new("Frame", { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 24), BackgroundTransparency = 1 }, r)
	local track = new("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0.5, -3), BackgroundColor3 = COL.bg, BorderSizePixel = 0 }, hit)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, track)
	local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COL.good, BorderSizePixel = 0 }, track)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, fill)
	local knob = new("Frame", { Size = UDim2.new(0, 12, 0, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = COL.text, BorderSizePixel = 0 }, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	local function refresh()
		local v = VAL[key]
		local rel = math.clamp((v - min) / (max - min), 0, 1)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
		val.Text = fmt and fmt(v) or tostring(v)
	end
	local function fromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		local v = min + rel * (max - min)
		VAL[key] = math.clamp(math.floor(v / step + 0.5) * step, min, max)
		refresh()
		if onChange then pcall(onChange, VAL[key]) end
	end
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			activeDrag = fromX
			fromX(i.Position.X)
		end
	end)
	refresh()
end
local function textbox(placeholder)
	local t = new("TextBox", { Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = COL.card, PlaceholderText = placeholder, Text = "", TextColor3 = COL.text, PlaceholderColor3 = COL.sub, Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false, LayoutOrder = nxt() }, body)
	round(t, 8)
	return t
end
local function x(v) return "x" .. tostring(v) end

section("TELEPORT  (activalo aqui)")
toggle("✔", "Click TP (clic izquierdo = teletransporte)", "clicktp")
toggle("✔", "TP suave (evita el anti-teleport)", "tpsmooth")
slider("Velocidad del TP suave", 40, 400, 10, "TPSpeed")
section("MENU")
slider("Tamano del menu", 0.8, 1.8, 0.05, "UIScale", x, function(v) uiScale.Scale = v end)
toggle("✔", "Modo ligero (menos CPU, menos tirones)", "lite")
toggle("◐", "Busqueda profunda getgc (solo si algo no funciona)", "deepscan")
toggle("✔", "Recordar opciones al reentrar", "autorestore")
toggle("✔", "Auto-ejecutar al cambiar de servidor", "autoexec")

section("RECURSOS   (✔ = seguro · ◐ = por patron)")
toggle("◐", "Gas infinito", "gas")
toggle("◐", "Hojas infinitas", "blades")
toggle("◐", "Auto recargar hojas (pulsa R al romperse)", "autoreload")
toggle("◐", "Durabilidad de hojas infinita", "durab")
toggle("◐", "Sin cooldown", "nocd")
toggle("◐", "No perder habilidades especiales", "special")
toggle("◐", "No perder capucha", "hood")
toggle("◐", "Capucha rapida", "quickhood")
toggle("✔", "Capucha visible en tu personaje", "hoodvisual")
toggle("◐", "Sin cooldown de canon", "nocannon")
section("GANCHO")
toggle("◐", "Rango de gancho", "hookrange")
slider("Rango de gancho (multiplicador)", 1, 3, 0.1, "HookScale", x)
toggle("◐", "Gancho instantaneo", "insthook")
slider("Velocidad de gancho (multiplicador)", 1, 6, 0.5, "HookSpeedScale", x)
toggle("◐", "Timer de gancho infinito", "hooktimer")
toggle("◐", "Anti hook (bloquea remotes)", "antihook")
section("PROTECCION / DESBLOQUEOS")
toggle("◐", "Desbloquear skills (impulso, esquiva...)", "unlockskills")
toggle("◐", "Desbloquear emotes", "unlockemotes")
toggle("◐", "Anti quemadura", "antiburn")
toggle("◐", "Desactivar deteccion de titanes", "nodetect")
toggle("◐", "Anti-Wipe (bloquea remotes)", "antiwipe")
section("SHIFTER")
toggle("◐", "Stamina de shifter infinita", "shiftstam")
toggle("◐", "Timer de shifter infinito", "shifttimer")
toggle("✔", "Velocidad de shifter", "shiftspeed")
slider("Velocidad de shifter", 8, 120, 2, "ShiftSpeed")
section("HITBOX  (solo tu cliente)")
toggle("✔", "Hitbox de nuca (titan/shifter)", "nape")
slider("Tamano de nuca", 1, 30, 0.5, "NapeMult", x)
slider("Distancia para agrandar la nuca", 15, 150, 5, "NapeNear")
toggle("✔", "Hitbox de hojas (alcance de las espadas)", "bladebox")
slider("Tamano de hojas", 1, 12, 0.5, "BladeMult")
toggle("✔", "Hitbox de piernas (titan/shifter)", "legs")
slider("Tamano de piernas", 1, 15, 0.5, "LegMult", x)
toggle("✔", "Hitbox de humanos", "human")
slider("Tamano de humanos", 2, 30, 1, "HumanSize")
section("COMBATE   (aprende la accion UNA vez)")
button("🎓  Aprender golpe a la nuca", function() task.spawn(learn, "hit", 8) end)
toggle("✔", "Titan Kill-Aura", "killaura")
slider("Alcance del Kill-Aura", 10, 120, 5, "AuraRange")
slider("Golpes por segundo (aura)", 1, 20, 1, "AuraRate")
button("🎓  Aprender lanzar hoja", function() task.spawn(learn, "throw", 8) end)
toggle("✔", "Blade Throw Spam", "throwspam")
slider("Lanzamientos por segundo", 1, 30, 1, "ThrowRate")
section("CABALLO")
toggle("✔", "Velocidad del caballo", "horsespeed")
slider("Velocidad del caballo", 8, 150, 2, "HorseSpeed")
toggle("◐", "Stamina infinita del caballo", "horsestam")
toggle("◐", "Caballo invencible (puede no tener efecto)", "horsegod")
section("VISUAL")
toggle("✔", "ESP titanes / shifters", "esptitan")
toggle("✔", "ESP Warriors (humano y titan)", "espwarrior")
toggle("✔", "   ...y mostrar tambien al resto en gris", "espall")
toggle("✔", "ESP jugadores", "espplayer")
section("AYUDA DE PUNTERIA  (no te bloquea la camara)")
toggle("✔", "Ayuda a la nuca de los titanes", "napeaim")
toggle("✔", "Ayuda en PvP (cabeza + hitbox grande)", "pvpaim")
toggle("✔", "Ayuda para Q / E (ganchos ODM)", "hookassist")
toggle("✔", "Solo mientras mantienes clic derecho", "aimhold")
slider("Fuerza (bajo = mas libre)", 0.02, 0.5, 0.01, "AimPull")
slider("Giro maximo por frame (grados)", 0.2, 5, 0.1, "AimMaxStep")
slider("Campo de la ayuda (grados)", 5, 90, 1, "AimFOV")
slider("Campo para Q / E (grados)", 10, 90, 1, "HookAssistFOV")
slider("Distancia maxima", 30, 600, 10, "AimRange")

local shirtBox = textbox("ID de camisa")
local pantsBox = textbox("ID de pantalon")
button("👕  Cambiar ropa (solo local)", function() applyClothes(shirtBox.Text, pantsBox.Text) end)
local emoteBox = textbox("ID de animacion (emote custom)")
button("💃  Reproducir emote", function() playEmote(emoteBox.Text) end)
button("⏹  Parar emote", stopEmote)
section("OTROS")
toggle("✔", "Aviso de staff", "staff")
slider("Rango minimo para avisar", 2, 255, 1, "StaffRank")
toggle("✔", "Recoger regalos cercanos", "gifts")
button("🔁  Cambiar de equipo (local)", nextTeam)
section("HERRAMIENTAS")
button("🔎  Inspector (guardar AOTFW_dump.txt)", function() task.spawn(inspect) end)

local status = new("TextLabel", { Size = UDim2.new(1, -6, 0, 48), BackgroundTransparency = 1, Text = "listo", TextColor3 = COL.sub, Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = nxt() }, body)
setStatus = function(t) status.Text = tostring(t) end

connect(UIS.InputBegan, function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
end)

------------------------------------------------------------------
-- DESCARGA / ARRANQUE
------------------------------------------------------------------
local function unload()
	Alive = false
	pcall(function() RunService:UnbindFromRenderStep(aimBind) end)
	Hook.anyBlock = false
	Hook.learning = nil
	for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
	restoreCat("nape") restoreCat("leg") restoreCat("human")
	for _, rule in ipairs(RULES) do pcall(restoreRule, rule) end
	for m in pairs(ESPobjs) do clearEsp(m) end
	stopEmote()
	pcall(function() espFolder:Destroy() end)
	pcall(function() gui:Destroy() end)
end
if getgenv then getgenv().AOTFW_Unload = unload end
button("Cerrar menu", unload)

blog("menu creado")
-- reactiva lo que dejaste ON la ultima vez: espera a que el juego cargue y va de una en una
if AUTO_RESTORE and SavedON.autorestore ~= false then
	task.spawn(function()
		local list = {}
		for id, v in pairs(SavedON) do
			if v and id ~= "autorestore" and id ~= "deepscan" then list[#list + 1] = id end
		end
		table.sort(list)
		if #list == 0 and not SavedON.deepscan then crashWrite("ok", "") return end
		if prevCrashStage == "boot" and prevCrashId == "" then
			-- el arranque anterior se cerro antes de terminar: esta vez NO se restaura nada solo
			notify("El arranque anterior fallo: no restauro opciones esta vez. Activa a mano lo que necesites.")
			crashWrite("ok", "")
			return
		end
		setStatus("restaurando tus opciones guardadas...")
		while Alive and (tick() - bootTime < (FAST and 3 or 12) or not (getChar() and getRoot())) do task.wait(0.25) end
		-- primero lo ligero, al final lo que usa hooks
		local heavy = { antiwipe = true, nodetect = true, antiburn = true, antihook = true }
		table.sort(list, function(a, b)
			if (heavy[a] or false) ~= (heavy[b] or false) then return not heavy[a] end
			return a < b
		end)
		if SavedON.deepscan then list[#list + 1] = "deepscan" end
		restoring = true
		local skipped = {}
		for _, id in ipairs(list) do
			if not Alive then break end
			if Crash.bad[id] then
				skipped[#skipped + 1] = id
			else
				crashWrite("restore", id)
				ON[id] = true
				if Refresh[id] then pcall(Refresh[id]) end
				pcall(onToggle, id)
				blog("restaurado " .. id)
				task.wait(FAST and (heavy[id] and 0.7 or 0.2) or (heavy[id] and 1.5 or 0.6))
			end
		end
		crashWrite("ok", "")
		restoring = false
		if #skipped > 0 then
			notify("Omitida por haber cerrado Roblox antes: " .. table.concat(skipped, ", ") .. " (activala a mano si quieres)")
		end
		saveCfg()
		setStatus("listo: opciones guardadas restauradas")
	end)
end
-- el archivo AOTFW_boot.lua (creado por el instalador) se re-encola solo en cada servidor;
-- aqui solo se avisa si el executor no puede y se sincroniza el interruptor "Auto-ejecutar"
pcall(function()
	if not (queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)) then
		notify("Tu executor no tiene queue_on_teleport: tendras que ejecutar el script a mano en cada servidor.")
	end
	syncAuto()
end)
setStatus("listo. Activa lo que necesites (se recuerda al reentrar).")
blog("arranque completo")
if not (AUTO_RESTORE and SavedON.autorestore ~= false) then crashWrite("ok", "") end
end, function(e) return tostring(e) .. "\n" .. tostring(debug and debug.traceback and debug.traceback() or "") end)
if not __ok then
	pcall(function() if writefile then writefile("AOTFW_error.txt", tostring(__err)) end end)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = "AOT FW: ERROR al cargar", Text = tostring(__err):sub(1, 180), Duration = 15 })
	end)
end

]=====]
local __BOOT = [=====[
-- AOTFW_boot.lua: se re-encola solo en cada servidor y carga AOT_FW.lua (guardado por el instalador)
local q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
local auto = true
pcall(function() if isfile("AOTFW_auto.txt") and readfile("AOTFW_auto.txt") == "0" then auto = false end end)
if not auto then return end
if q then q('loadstring(readfile("AOTFW_boot.lua"))()') end
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(0.3)
local f = loadstring(readfile("AOT_FW.lua"))
if f then f() end
]=====]
local __loader = loadstring or load
if writefile then
	pcall(writefile, "AOT_FW.lua", __SRC)
	pcall(writefile, "AOTFW_boot.lua", __BOOT)
end
local __auto = true
pcall(function() if isfile and isfile("AOTFW_auto.txt") and readfile("AOTFW_auto.txt") == "0" then __auto = false end end)
if __q and __auto and writefile then pcall(__q, 'loadstring(readfile("AOTFW_boot.lua"))()') end
local __f, __e = __loader(__SRC)
if __f then __f() else
	pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = "AOT FW", Text = "error: " .. tostring(__e):sub(1, 150), Duration = 15 }) end)
end
