--!strict
-- The shape of the generated house data files next to this one (art/scripts/housekit.py writes
-- them while it builds a Blender house). Everything is in the model's Blender coordinates: x right,
-- y back from the street, z up, the front wall at y = 0.

export type Hinged = {
	name: string, -- the door slab mesh
	kind: string,
	hinge: Vector3,
	yaw: number, -- degrees the hinge frame turns from facing the street
	angle: number,
	openable: boolean,
	prompt: string?,
}

export type Room = { id: string, lamp: Vector3, figure: boolean, attic: boolean }

export type Data = {
	style: string,
	door: { x: number, y: number, sill: number }, -- front door slab centre (y is its plane)
	hinged: { Hinged },
	colliders: { { size: Vector3, centre: Vector3, yaw: number } },
	lights: { { name: string, at: Vector3, range: number, brightness: number, color: Color3, shadows: boolean } },
	anchors: { { name: string, at: Vector3, yaw: number } },
	rooms: { Room },
	yard: { fence: string, pathFrom: number, tree: Vector3, graves: { Vector3 } },
}

return nil
