-- PBRTuner (LocalScript in StarterPlayerScripts) - VoxToRoblox 1.4
-- Lets you raise/lower live the strength of the normal map, roughness, metalness and glow
-- of a SurfaceAppearance, through attributes on the MeshPart.
--
-- USAGE: give the MeshPart the tag "PBRTuner" (Properties > Tags) and these attributes (all optional):
--   PBR_Normal         relief strength           1 = as exported by the .bat, 0 = flat, 2 = double
--   PBR_Roughness      multiplies roughness      1 = unchanged, 0.5 = shinier/more polished
--   PBR_RoughnessAdd   adds to roughness         -1..1
--   PBR_Metalness      multiplies metalness      1 = unchanged
--   PBR_MetalnessAdd   adds to metalness         0..1 (works even if the map is black)
--   PBR_Emissive       glow strength             (= EmissiveStrength)
-- Change the values during Play (Client view) and see the result instantly. When you like them,
-- set the same values in Edit mode so they are saved.
-- The original maps must be set on the SurfaceAppearance (ColorMap, NormalMap,
-- RoughnessMap, MetalnessMap and optionally EmissiveMaskContent).
-- Note: uses EditableImage. In published games the Mesh/Image APIs must be enabled
-- (Game Settings > Security) and the owner account must be verified.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")

local TAG = "PBRTuner"
local DEFAULTS = {
	PBR_Normal = 1,
	PBR_Roughness = 1,
	PBR_RoughnessAdd = 0,
	PBR_Metalness = 1,
	PBR_MetalnessAdd = 0,
}

-- (game scripts cannot read NormalMap/ColorMap..., only the *Content versions)
local function loadImage(content)
	if typeof(content) ~= "Content" or content.SourceType == Enum.ContentSourceType.None then
		return nil
	end
	local ok, img = pcall(function()
		return AssetService:CreateEditableImageAsync(content)
	end)
	if not ok then
		warn("[PBRTuner] could not open " .. tostring(content.Uri) .. ": " .. tostring(img))
		return nil
	end
	return img
end

local function copyBuffer(b)
	local c = buffer.create(buffer.len(b))
	buffer.copy(c, 0, b)
	return c
end

local function attr(part, name)
	local v = part:GetAttribute(name)
	if typeof(v) ~= "number" then
		return DEFAULTS[name]
	end
	return v
end

local tuned = {}

local function setup(part)
	if tuned[part] or not part:IsA("MeshPart") then
		return
	end
	local sa = part:FindFirstChildOfClass("SurfaceAppearance")
	if not sa then
		warn("[PBRTuner] " .. part:GetFullName() .. " has no SurfaceAppearance")
		return
	end
	tuned[part] = true

	-- the original maps (read once)
	local layers = {}
	local function prep(content)
		local src = loadImage(content)
		if not src then
			return nil
		end
		local size = src.Size
		local base = src:ReadPixelsBuffer(Vector2.zero, size)
		local work = AssetService:CreateEditableImage({ Size = size })
		work:WritePixelsBuffer(Vector2.zero, size, base)
		return { base = base, work = work, size = size }
	end
	layers.normal = prep(sa.NormalMapContent)
	layers.rough = prep(sa.RoughnessMapContent)
	layers.metal = prep(sa.MetalnessMapContent)
	if not (layers.normal or layers.rough or layers.metal) then
		warn("[PBRTuner] " .. part:GetFullName() .. ": the SurfaceAppearance has no NormalMap/RoughnessMap/MetalnessMap")
		tuned[part] = nil
		return
	end
	-- (CreateSurfaceAppearanceAsync only accepts EditableImages)
	local colorImg = loadImage(sa.ColorMapContent)
	if not colorImg then
		tuned[part] = nil
		return
	end

	-- a new SurfaceAppearance that points at the live (editable) copies
	local content = {
		ColorMap = Content.fromObject(colorImg),
	}
	if layers.normal then
		content.NormalMap = Content.fromObject(layers.normal.work)
	end
	if layers.rough then
		content.RoughnessMap = Content.fromObject(layers.rough.work)
	end
	if layers.metal then
		content.MetalnessMap = Content.fromObject(layers.metal.work)
	end
	local emisImg = loadImage(sa.EmissiveMaskContent)
	local newSA, usedKey
	for _, key in ipairs({ "EmissiveMask", false }) do
		local c = table.clone(content)
		if key and emisImg then
			c[key] = Content.fromObject(emisImg)
		end
		local ok, res = pcall(function()
			return AssetService:CreateSurfaceAppearanceAsync(c)
		end)
		if ok then
			newSA, usedKey = res, key
			break
		end
	end
	if not newSA then
		warn("[PBRTuner] could not create the editable SurfaceAppearance for " .. part:GetFullName())
		tuned[part] = nil
		return
	end
	newSA.Name = "SurfaceAppearance"
	newSA.AlphaMode = sa.AlphaMode
	newSA.ResampleMode = sa.ResampleMode
	newSA.Color = sa.Color
	pcall(function()
		newSA.EmissiveStrength = sa.EmissiveStrength
		newSA.EmissiveTint = sa.EmissiveTint
	end)
	-- (whoever changes the original's glow - e.g. a cinematic - still drives the new one)
	local syncConns = {}
	for _, prop in ipairs({ "EmissiveStrength", "EmissiveTint", "Color" }) do
		local ok, conn = pcall(function()
			return sa:GetPropertyChangedSignal(prop):Connect(function()
				newSA[prop] = sa[prop]
			end)
		end)
		if ok then
			table.insert(syncConns, conn)
		end
	end
	sa.Parent = nil -- (on this client only: the original stays on the server)
	newSA.Parent = part
	part:SetAttribute("PBR_Status", "active" .. (usedKey and " (+emissive)" or ""))

	local function apply()
		local s = attr(part, "PBR_Normal")
		local rm, ra = attr(part, "PBR_Roughness"), attr(part, "PBR_RoughnessAdd")
		local mm, ma = attr(part, "PBR_Metalness"), attr(part, "PBR_MetalnessAdd")
		local e = part:GetAttribute("PBR_Emissive")
		if typeof(e) == "number" then
			pcall(function()
				sa.EmissiveStrength = e
			end)
		end
		local L = layers.normal
		if L then
			local src, out = L.base, copyBuffer(L.base)
			for i = 0, buffer.len(src) - 4, 4 do
				local x = (buffer.readu8(src, i) / 127.5 - 1) * s
				local y = (buffer.readu8(src, i + 1) / 127.5 - 1) * s
				local z = buffer.readu8(src, i + 2) / 127.5 - 1
				local inv = 1 / math.max(math.sqrt(x * x + y * y + z * z), 1e-4)
				buffer.writeu8(out, i, math.clamp(math.floor((x * inv + 1) * 127.5 + 0.5), 0, 255))
				buffer.writeu8(out, i + 1, math.clamp(math.floor((y * inv + 1) * 127.5 + 0.5), 0, 255))
				buffer.writeu8(out, i + 2, math.clamp(math.floor((z * inv + 1) * 127.5 + 0.5), 0, 255))
			end
			L.work:WritePixelsBuffer(Vector2.zero, L.size, out)
			task.wait()
		end
		for _, pair in ipairs({ { layers.rough, rm, ra }, { layers.metal, mm, ma } }) do
			local Lg, mult, add = pair[1], pair[2], pair[3]
			if Lg then
				local src, out = Lg.base, copyBuffer(Lg.base)
				for i = 0, buffer.len(src) - 4, 4 do
					local v = math.clamp(buffer.readu8(src, i) * mult + add * 255, 0, 255)
					v = math.floor(v + 0.5)
					buffer.writeu8(out, i, v)
					buffer.writeu8(out, i + 1, v)
					buffer.writeu8(out, i + 2, v)
				end
				Lg.work:WritePixelsBuffer(Vector2.zero, Lg.size, out)
				task.wait()
			end
		end
	end

	-- recompute when an attribute changes (debounced: dragging a slider fires many changes)
	local pending, running = false, false
	local function request()
		pending = true
		if running then
			return
		end
		running = true
		task.spawn(function()
			while pending do
				pending = false
				apply()
			end
			running = false
		end)
	end
	local attrConn = part.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 4) == "PBR_" and name ~= "PBR_Status" then
			request()
		end
	end)
	request()

	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(game) then
			attrConn:Disconnect()
			for _, c in ipairs(syncConns) do
				c:Disconnect()
			end
			tuned[part] = nil
		end
	end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
	if inst:IsDescendantOf(workspace) then
		task.spawn(setup, inst)
	end
end)
for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
	if inst:IsDescendantOf(workspace) then
		task.spawn(setup, inst)
	end
end
-- (tagged parts that arrive later into the workspace, e.g. clones from ReplicatedStorage)
workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("MeshPart") and CollectionService:HasTag(inst, TAG) then
		task.spawn(setup, inst)
	end
end)
