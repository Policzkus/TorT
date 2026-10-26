--!strict
-- Your own ragdoll (RagdollService knocked you down: the car hit you). Your body is your own
-- physics, so it's thrown from here (the character's RagdollPush) and falls loose until the joints
-- lock back (Ragdoll goes false), when you're stood up where you landed. It's all seen from your
-- own eyes (the user didn't want it in third person): the view goes where your head goes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RagdollController = {}

local FOLLOW = 20 -- how quickly the view catches up with your head (per second)
local SPIN = 7 -- radians/s of tumble at most

local player = Players.LocalPlayer
local random = Random.new()
local watching: Model? = nil -- the character whose eyes the view is in while it's down

local function parts(character: Model): { BasePart }
	local found = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(found, part)
		end
	end
	return found
end

-- The view stays in your eyes and goes with your head: thrown, tumbling, landing wherever it lands
-- (eased a touch so the physics' jitter doesn't shake it). Your arms and legs show, flopping; your
-- own head stays hidden so you don't see the inside of it.
local function eyes(character: Model)
	local camera = Workspace.CurrentCamera
	local head = character:FindFirstChild("Head") :: BasePart?
	if camera == nil or head == nil then
		return
	end
	watching = character
	local eye = head.CFrame:ToObjectSpace(camera.CFrame) -- where you were looking from, and which way
	camera.CameraType = Enum.CameraType.Scriptable
	local body = parts(character)
	RunService:BindToRenderStep("RagdollEyes", Enum.RenderPriority.Camera.Value + 4, function(dt)
		if watching ~= character or head.Parent == nil then
			RunService:UnbindFromRenderStep("RagdollEyes")
			return
		end
		camera.CFrame = camera.CFrame:Lerp(head.CFrame * eye, math.min(1, dt * FOLLOW))
		for _, part in body do
			part.LocalTransparencyModifier = if part == head then 1 else 0
		end
	end)
end

local function release(character: Model)
	if watching ~= character then
		return
	end
	watching = nil
	RunService:UnbindFromRenderStep("RagdollEyes")
	local camera = Workspace.CurrentCamera
	-- Back on whoever you are now (killed while down, it's a new body at the spawn).
	local current = player.Character or character
	local humanoid = current:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function fall(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid == nil or root == nil then
		return
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	local push = character:GetAttribute("RagdollPush")
	local throw = if typeof(push) == "Vector3" then push else Vector3.new(0, 20, 0)
	for _, part in parts(character) do
		if not part.Anchored then
			part.AssemblyLinearVelocity = throw -- every loose piece goes together
		end
	end
	local axis = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.3, 0.3), random:NextNumber(-1, 1))
	if axis.Magnitude > 0.1 then
		root.AssemblyAngularVelocity = axis.Unit * random:NextNumber(SPIN * 0.5, SPIN)
	end
	eyes(character)
end

-- Up on your feet where you landed, facing the way you were.
local function getUp(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	release(character)
	if humanoid == nil or root == nil then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), params)
	local floor = if hit then hit.Position.Y else root.Position.Y - humanoid.HipHeight
	local at = Vector3.new(root.Position.X, floor + humanoid.HipHeight + root.Size.Y / 2 + 0.1, root.Position.Z)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	root.CFrame = CFrame.lookAt(at, at + look.Unit)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

local function watch(character: Model)
	if watching and watching ~= character then
		release(watching :: Model) -- a new character while the old one was down
	end
	character:GetAttributeChangedSignal("Ragdoll"):Connect(function()
		if player.Character ~= character then
			return
		end
		if character:GetAttribute("Ragdoll") == true then
			fall(character)
		else
			getUp(character)
		end
	end)
end

function RagdollController.Start()
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

return RagdollController
