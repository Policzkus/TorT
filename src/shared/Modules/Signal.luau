--!strict
-- Minimal signal. Each handler runs in its own thread so one error can't break the others.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

type Handler = { fn: (...any) -> (), connection: Connection }

function Signal.new(): Signal
	local self = setmetatable({}, Signal) :: any
	self._handlers = {} :: { Handler }
	return self
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local handlers: { Handler } = self._handlers
	local connection = { Connected = true } :: any
	local entry: Handler = { fn = fn, connection = connection }
	function connection.Disconnect(conn: Connection)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(handlers, entry)
		if index then
			table.remove(handlers, index)
		end
	end
	table.insert(handlers, entry)
	return connection
end

function Signal:Once(fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	-- Copy so handlers can disconnect while we iterate.
	for _, entry in table.clone(self._handlers) do
		if entry.connection.Connected then
			task.spawn(entry.fn, ...)
		end
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, entry in self._handlers do
		entry.connection.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
