local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BASE_RADIUS = 48
local STUDIO_RADIUS = 8
local RADIUS = if RunService:IsStudio() then STUDIO_RADIUS else BASE_RADIUS

local BASE_PART_SIZE = 20
local PART_SIZE_Y = 100
local ORIGIN_Y = -5
local OFFSET_Y = ORIGIN_Y - PART_SIZE_Y / 2

local UPDATE_DISTANCE_STEP = BASE_PART_SIZE * 3
local FRAMERATE_UPDATE_STEP = 2

local WAVE_SCALE = 75
local WAVE_SPEED = 0.225
local WAVE_AMPLITUDE = 5

local DIAMETER = RADIUS * 2 + 1

local player = Players.LocalPlayer
local renderLoop
local mask = {}
local grid = {}
local buckets = {}

for x = 1, DIAMETER do
	for z = 1, DIAMETER do
		local part = Instance.new("Part")
		part.Size = vector.create(BASE_PART_SIZE, PART_SIZE_Y, BASE_PART_SIZE)
		part.Color = Color3.fromRGB(0, 83, 114)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = workspace

		local cell = table.create(10)

		cell[1] = x
		cell[2] = z
		cell[3] = 0
		cell[4] = 0
		cell[5] = part
		cell[6] = 0
		cell[7] = 0
		cell[8] = 0
		cell[9] = true

		grid[x] = grid[x] or {}
		grid[x][z] = cell

		table.insert(mask, cell)
	end
end

local lastCenterX = 0
local lastCenterZ = 0
local originX = 0
local originZ = 0

local function calculateY(x, z, t)
	return math.noise(x / WAVE_SCALE, z / WAVE_SCALE, t * WAVE_SPEED) * WAVE_AMPLITUDE
end

local function calculateOffsetX(x)
	return (x - 1 - originX + DIAMETER) % DIAMETER - RADIUS
end

local function calculateOffsetZ(z)
	return (z - 1 - originZ + DIAMETER) % DIAMETER - RADIUS
end

local function moveCell(cell, centerX, centerZ)
	local offsetX = calculateOffsetX(cell[1])
	local offsetZ = calculateOffsetZ(cell[2])

	local worldX = (centerX + offsetX) * BASE_PART_SIZE
	local worldZ = (centerZ + offsetZ) * BASE_PART_SIZE

	cell[3] = worldX
	cell[4] = worldZ
	cell[7] = offsetX
	cell[8] = offsetZ
end

local function updateVisibilityForCell(cell)
	local offsetX = calculateOffsetX(cell[1])
	local offsetZ = calculateOffsetZ(cell[2])

	local rendered = offsetX ^ 2 + offsetZ ^ 2 <= RADIUS ^ 2
	local part = cell[5]

	if not rendered then
		part.Transparency = 1
	else
		part.Transparency = 0
	end

	cell[9] = rendered
end

local function updateFrameRateForCell(cell)
	local offsetX = cell[7]
	local offsetZ = cell[8]

	local distance = math.max(math.abs(offsetX), math.abs(offsetZ))
	local distanceStuds = distance * BASE_PART_SIZE

	local previousBucket = buckets[cell[6]]

	if previousBucket and cell[10] then
		local lastCell = previousBucket[#previousBucket]
		previousBucket[cell[10]] = lastCell
		lastCell[10] = cell[10]
		previousBucket[#previousBucket] = nil
	end

	local updateEvery = math.floor(distanceStuds / UPDATE_DISTANCE_STEP)
	cell[6] = updateEvery

	buckets[updateEvery] = buckets[updateEvery] or {}
	local bucket = buckets[updateEvery]
	table.insert(bucket, cell)
	cell[10] = #bucket
end

local function updateVisibility()
	for _, cell in mask do
		updateVisibilityForCell(cell)
	end
end

local function updateFrameRate()
	for _, cell in mask do
		updateFrameRateForCell(cell)
	end
end

local function recycleX(dx, centerX, centerZ)
	local index

	if dx > 0 then
		originX = (originX + 1) % DIAMETER
		index = (originX - 1 + DIAMETER) % DIAMETER + 1
	else
		originX = (originX - 1 + DIAMETER) % DIAMETER
		index = originX + 1
	end

	for _, cell in grid[index] do
		moveCell(cell, centerX, centerZ)
	end
end

local function recycleZ(dz, centerX, centerZ)
	local index

	if dz > 0 then
		originZ = (originZ + 1) % DIAMETER
		index = (originZ - 1 + DIAMETER) % DIAMETER + 1
	else
		originZ = (originZ - 1 + DIAMETER) % DIAMETER
		index = originZ + 1
	end

	for x = 1, DIAMETER do
		local cell = grid[x][index]
		moveCell(cell, centerX, centerZ)
	end
end

local function moveGrid(centerX, centerZ)
	local dx = centerX - lastCenterX
	local dz = centerZ - lastCenterZ

	if dx ~= 0 then
		recycleX(dx, centerX, centerZ)
	end

	if dz ~= 0 then
		recycleZ(dz, centerX, centerZ)
	end

	lastCenterX = centerX
	lastCenterZ = centerZ
end

local function setPosition(cell, y)
	local part = cell[5] :: Part
	local x = cell[3] :: number
	local z = cell[4] :: number
	part.Position = vector.create(x, y, z)
end

local function setupGrid()
	originX = 0
	originZ = 0
	lastCenterX = 0
	lastCenterZ = 0

	for _, cell in mask do
		moveCell(cell, 0, 0)
		setPosition(cell, OFFSET_Y)
		updateFrameRateForCell(cell)
		updateVisibilityForCell(cell)
	end
end

local frameCount = 0

local function updateGrid()
	local clockTime = os.clock()

	frameCount += 1

	for updateEvery, bucket in buckets do
		if frameCount % (updateEvery + 1) == 0 then
			for _, cell in bucket do
				local worldX = cell[3] :: number
				local worldZ = cell[4] :: number
				local worldY = OFFSET_Y

				if cell[9] then
					worldY += calculateY(worldX, worldZ, clockTime)
				end

				setPosition(cell, worldY)
			end
		end
	end
end

player.CharacterAdded:Connect(function(char)
	setupGrid()

	if not renderLoop then
		renderLoop = RunService.RenderStepped:Connect(updateGrid)
	end

	local hrp = char:WaitForChild("HumanoidRootPart") :: Part
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid

	local lastGridX = 0
	local lastGridZ = 0
	local lastGridXStep = 0
	local lastGridZStep = 0

	local moveLoop

	local moveDirectionChanged
	moveDirectionChanged = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		local moveDirection = humanoid.MoveDirection

		if moveDirection == vector.zero then
			if moveLoop then
				moveLoop:Disconnect()
				moveLoop = nil
			end

			return
		end

		if moveLoop then
			return
		end

		moveLoop = RunService.Heartbeat:Connect(function()
			local position = hrp.Position
			local gridX = math.round(position.X / BASE_PART_SIZE)
			local gridZ = math.round(position.Z / BASE_PART_SIZE)

			if gridX ~= lastGridX or gridZ ~= lastGridZ then
				moveGrid(gridX, gridZ)
				updateVisibility()
			end

			if
				math.abs(gridX - lastGridXStep) >= FRAMERATE_UPDATE_STEP
				or math.abs(gridZ - lastGridZStep) >= FRAMERATE_UPDATE_STEP
			then
				updateFrameRate()

				lastGridXStep = gridX
				lastGridZStep = gridZ
			end

			lastGridX = gridX
			lastGridZ = gridZ
		end)
	end)

	player.CharacterRemoving:Once(function()
		moveDirectionChanged:Disconnect()
	end)
end)
