local function assert(cond, message)
	tests = tests + 1
	_G.assert(cond, message)
end

local value, cursor = readVarInt("\x00", 1)
assert(value == 0)
assert(cursor == 2)

local value, cursor = readVarInt("\x01", 1)
assert(value == 1)
assert(cursor == 2)

local value, cursor = readVarInt("\x80\x01", 1)
assert(value == 128)
assert(cursor == 3)

local value, cursor = readVarInt("\xAF\xDB\xE2\x0A", 1)
assert(value == 22588847)
assert(cursor == 5)

local value, cursor = readVarZig("\xDE\xB6\xC5\x15\xB4", 1)
assert(value == 22588847)
assert(cursor == 5)

local value, cursor = readVarZig("\xB4\xA1\xAD\xEE\x39", 1)
assert(value == 7766124634)
assert(cursor == 6)
