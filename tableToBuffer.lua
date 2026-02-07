-- Made By Larsen264

-- Types
type t = { [string | number | boolean | Vector3 | CFrame]: boolean | number | string | Vector3 | CFrame | t }

-- Values
local types = {
	boolean = 1,
	number = 8,
	["string"] = 8,
	Vector3 = 96,
	CFrame = 192,
}

local indexes = {
	boolean = 1,
	int = 2,
	float = 3,
	string = 4,
	Vector3 = 5,
	CFrame = 6,
	table = 7,
}

local SCOPE_SIZE = 19

-- Functions

--[=[
	@param b buffer;
	@param int number;
	@param bitCount number;
	@param offset number;
	
	@return ;
	
	Writes some signed integer to a buffer with given in bits offset. Uses
	2 complement method to represent the negative numbers.
]=]
local function writeInt(b: buffer, int: number, bitCount: number, offset: number)
	local unsigned = int >= 0 and int or bit32.rshift(int, bitCount) + int

	for index = 0, bitCount - 1 do
		local bit = bit32.band(bit32.rshift(unsigned, index), 1)
		buffer.writebits(b, offset + index, 1, bit)
	end
end

--[=[
	@param b buffer;
	@param int number;
	@param bitCount number;
	@param offset number;
	
	@return number;
	
	Reads some signed integer written using 2 complement method from a
	buffer with given in bits offset.
]=]
local function readInt(b: buffer, bitCount: number, offset: number)
	local value = 0

	for index = 0, bitCount - 1 do
		local bit = buffer.readbits(b, offset + index, 1)
		value += bit * 2^index
	end

	local signBit = 2 ^ (bitCount - 1)
	if value >= signBit then
		value -= 2^bitCount
	end

	return value
end

--[=[
	@param b buffer;
	@param float number;
	@param bitCount number;
	@param offset number;
	
	@return ;
	
	Writes some signed 32 bit float to a buffer with given in bits offset.
]=]
local function writeFloat(b: buffer, float: number, bitCount: number, offset: number)
	local sign = if float < 0 then 1 else 0
	local exponent = math.floor(math.log(math.abs(float), 2))
	local mantissa = math.abs(float) / (2 ^ exponent) - 1

	local exponentBits = exponent + 127
	local mantissaBits = math.floor(mantissa * 2^23 + 0.5)

	local bits = bit32.bor(
		bit32.lshift(sign, 31),
		bit32.lshift(exponentBits, 23),
		bit32.lshift(mantissaBits, 0)
	)

	for index = 0, 31 do
		local bit = bit32.band(bit32.rshift(bits, index), 1)
		buffer.writebits(b, offset + index, 1, bit)
	end
end

--[=[
	@param b buffer;
	@param bitCount number;
	@param offset number;
	
	@return number;
	
	Reads some signed 32 bit float from a given buffer with given in bits
	offset.
]=]
local function readFloat(b: buffer, bitCount: number, offset: number)
	local bits = 0

	for index = 0, 31 do
		local bit = buffer.readbits(b, offset + index, 1)
		bits = bit32.bor(bits, bit32.lshift(bit, index))
	end

	local sign = bit32.rshift(bits, 31)
	local exponent = bit32.band(bit32.rshift(bits, 23), 0xff)
	local mantissa = bit32.band(bits, 0x7FFFFF)

	local value = (1 + mantissa/2^23) * 2^(exponent - 127)
	if sign == 1 then
		value = -value
	end

	return value
end

--[=[
	@param n number;
	
	@return number;
	
	Counts what size some number is in bits. Returnes only 8, 16, 32.
]=]
local function returnNumberSize(n: number)
	if n % 1 ~= 0 then
		return 32
	end

	for _, bits in ipairs({8, 16, 32}) do
		local max = 2^(bits - 1) - 1
		local min = -2^(bits - 1)
		if n >= min and n <= max then
			return bits
		end
	end

	return 32
end

-- String To Buffer
local stringToBuffer = {}

--[=[
	@param str string;
	@return number;
	
	Returnes new buffer size in bits if it was generated using .convert() method.
]=]
function stringToBuffer.bufferSize(str: string)
	return 16 + (str:len() * 8)
end

--[=[
	@param str string;
	
	@return buffer;
	
	Converts string into new buffer. Also writes at start its length.
]=]
function stringToBuffer.convert(str: string): buffer
	local bufferSize = stringToBuffer.bufferSize(str) / 8
	local strBuffer = buffer.create(bufferSize)
	local numericStr = str:split("")

	for index, letter in ipairs(numericStr) do
		numericStr[index] = string.byte(letter)
	end

	local offset = 16

	buffer.writebits(strBuffer, 0, 16, str:len())

	for index, numericLetter in ipairs(numericStr) do
		buffer.writebits(strBuffer, offset + ((index - 1) * 8), 8, numericLetter)
	end

	return strBuffer
end

--[=[
	@param b buffer;
	@param str string;
	@param lengthOffset number?;
	@param offset number?;
	
	@return ;
	
	Writes in buffer string at offset with its length at lengthOffset.
	Also offset and lengthOffset should be written in bits.
]=]
function stringToBuffer.write(b: buffer, str: string, lengthOffset: number?, offset: number?): (number, number)
	lengthOffset = lengthOffset or 0
	offset = offset or lengthOffset + 16

	local numericStr = str:split("")

	for index, letter in ipairs(numericStr) do
		numericStr[index] = string.byte(letter)
	end

	buffer.writebits(b, lengthOffset, 16, str:len())

	for index, numericLetter in ipairs(numericStr) do
		buffer.writebits(b, offset + ((index - 1) * 8), 8, numericLetter)
	end

	return (#numericStr + 2) * 8, offset
end

--[=[
	@param b buffer;
	@param offset number?;
	@param lengthOffset number?;
	
	@return string;
	
	Reads written in buffer string, written using .write() or .convert() methods.
	Does not work with buffer made using buffer.fromstring() method.
	Also offset and lengthOffset should be written in bits, not in bytes.
]=]
function stringToBuffer.read(b: buffer, offset: number?, lengthOffset: number?): string
	local str = ""

	lengthOffset = lengthOffset or 0
	offset = offset or lengthOffset + 16

	local length = (buffer.readbits(b, lengthOffset, 16) - 1) * 8

	for index = 0, length, 8 do
		str = str.. string.char(buffer.readbits(b, offset + index, 8))
	end

	return str
end

--[=[
	@param b buffer;
	
	@return string;
	
	Reads roblox generated buffer with string inside.
]=]
function stringToBuffer.readRoblox(b: buffer): string
	local str: string = ""
	local border = buffer.len(b)

	for index = 0, border - 1 do
		str = str.. string.char(buffer.readbits(b, index * 8, 8))
	end

	return str
end

-- Vector3 To Buffer
local vector3ToBuffer = {}

--[=[
	@param v3 Vector3;
	
	@return buffer;
	
	Converts Vector3 to buffer. Every side threats as 32 bit floats.
]=]
function vector3ToBuffer.convert(v3: Vector3)
	local v3Buffer = buffer.create(3 * 4)

	writeFloat(v3Buffer, v3.X, 32, 0)
	writeFloat(v3Buffer, v3.X, 32, 32)
	writeFloat(v3Buffer, v3.X, 32, 64)

	return v3Buffer
end

--[=[
	@param v3Buffer buffer;
	@param v3 Vector3;
	@param offset number;
	
	@return ;
	
	Writes Vector3 in buffer at given in bits offset. Every side threats as
	32 bit floats.
]=]
function vector3ToBuffer.write(v3Buffer: buffer, v3: Vector3, offset: number?)
	offset = offset or 0

	writeFloat(v3Buffer, v3.X, 32, offset)
	writeFloat(v3Buffer, v3.X, 32, offset + 32)
	writeFloat(v3Buffer, v3.X, 32, offset + 64)
end

--[=[
	@param v3Buffer buffer;
	@param offset number?;
	
	@return Vector3;
	
	Reads Vector3 from buffer at given in bits offset.
]=]
function vector3ToBuffer.read(v3Buffer: buffer, offset: number?)
	offset = offset or 0

	local x = readFloat(v3Buffer, 32, offset)
	local y = readFloat(v3Buffer, 32, offset + 32)
	local z = readFloat(v3Buffer, 32, offset + 64)

	return Vector3.new(x, y, z)
end

-- CFrame To Buffer
local cframeToBuffer = {}

--[=[
	@param cf CFrame;
	
	@return buffer;
	
	Converts CFrame to buffer. Every side threats as 32 bit floats.
]=]
function cframeToBuffer.convert(cf: CFrame)
	local cfBuffer = buffer.create(6 * 4)

	writeFloat(cfBuffer, cf.X, 32, 0)
	writeFloat(cfBuffer, cf.Y, 32, 32)
	writeFloat(cfBuffer, cf.Z, 32, 64)
	writeFloat(cfBuffer, cf.Rotation.X, 32, 96)
	writeFloat(cfBuffer, cf.Rotation.Y, 32, 128)
	writeFloat(cfBuffer, cf.Rotation.Z, 32, 160)
	
	return cfBuffer
end

--[=[
	@param cfBuffer buffer;
	@param cf CFrame;
	@param offset number?;
	
	@return buffer;
	
	Writes CFrame to some buffer at given offset in bits. Every side
	threats as 32 bit floats.
]=]
function cframeToBuffer.write(cfBuffer: buffer, cf: CFrame, offset: number?)
	offset = offset or 0

	writeFloat(cfBuffer, cf.X, 32, offset + 0)
	writeFloat(cfBuffer, cf.Y, 32, offset + 32)
	writeFloat(cfBuffer, cf.Z, 32, offset + 64)
	writeFloat(cfBuffer, cf.Rotation.X, 32, offset + 96)
	writeFloat(cfBuffer, cf.Rotation.Y, 32, offset + 128)
	writeFloat(cfBuffer, cf.Rotation.Z, 32, offset + 160)
end

--[=[
	@param cfBuffer buffer;
	@param offset number?;
	
	@return CFrame;
	
	Reads CFrame from buffer at given in bits offset.
]=]
function cframeToBuffer.read(cfBuffer: buffer, offset: number?)
	offset = offset or 0

	local x = readFloat(cfBuffer, 32, offset)
	local y = readFloat(cfBuffer, 32, offset + 32)
	local z = readFloat(cfBuffer, 32, offset + 64)
	local rx = readFloat(cfBuffer, 32, offset + 96)
	local ry = readFloat(cfBuffer, 32, offset + 128)
	local rz = readFloat(cfBuffer, 32, offset + 160)

	return CFrame.new(x, y, z) * CFrame.Angles(rx, ry, rz)
end

-- Functions

--[=[
	@param t table;
	
	@return number, number, number;
	
	Iterates through table and returnes size for future buffer. First
	number is full buffer size in bits, second is scopes size in bits and
	third is size of buffer in bytes.
]=]
local function countBufferSize(t: t)
	local scopesSize = 0
	local size = 16

	for key, value in t do
		scopesSize += SCOPE_SIZE * 2
		size += SCOPE_SIZE * 2

		local keyType = typeof(key)
		local valueType = typeof(value)

		if keyType == "string" then
			size += stringToBuffer.bufferSize(key) - 16
		elseif keyType == "number" then
			size += returnNumberSize(key)
		else
			size += types[keyType]
		end

		if valueType == "string" then
			size += stringToBuffer.bufferSize(value) - 16
		elseif valueType == "number" then
			size += returnNumberSize(value)
		elseif valueType == "table" then
			local valueSize, valueScopesSize, _ = countBufferSize(value)

			size += valueSize
		else
			size += types[valueType]
		end
	end

	return size, scopesSize, math.ceil(size / 8)
end

--[=[
	@param b buffer;
	@param scopeOffset: number;
	@param offset: number;
	@param value: string | number | boolean | Vector3 | CFrame;
	
	@return number, number;
	
	Writes some key with scopes into buffer. Scopes have information
	about what size is given key and how to transform it when reading.
	Returns next scope offset and next value offset.
]=]
local function writeKey(b: buffer, scopeOffset: number, offset: number, key: string | number | boolean | Vector3 | CFrame)
	local keyType = typeof(key)
	local size = types[keyType]
	local index = indexes[keyType]
	
	if keyType == "string" then
		size = stringToBuffer.bufferSize(key) - 16
	elseif keyType == "number" then
		size = returnNumberSize(key)
		
		index = if key % 1 == 0 then 2 else 3
	end
	
	buffer.writebits(b, scopeOffset, 3, index)
	buffer.writebits(b, scopeOffset + 3, 16, size)
	
	if keyType == "string" then
		stringToBuffer.write(b, key, scopeOffset + 3, offset)
	elseif keyType == "Vector3" then
		vector3ToBuffer.write(b, key, offset)
	elseif keyType == "CFrame" then	
		cframeToBuffer.write(b, key, offset)
	elseif keyType == "number" then
		if key % 1 == 0 then
			writeInt(b, key, size, offset)
		else
			writeFloat(b, key, size, offset)
		end
	elseif keyType == "boolean" then
		buffer.writebits(b, offset, size, key and 1 or 0)
	end
	
	return scopeOffset + SCOPE_SIZE, offset + size
end

--[=[
	@param b buffer;
	@param scopeOffset: number;
	@param offset: number;
	@param value: string | number | boolean | Vector3 | CFrame | t;
	
	@return number, number;
	
	Writes some value with scopes into buffer. Scopes have information
	about what size is given value and how to transform it when reading.
	Returns next scope offset and next key offset.
]=]
local function writeValue(b: buffer, scopeOffset: number, offset: number, value: string | number | boolean | Vector3 | CFrame | t)
	local valueType = typeof(value)
	local size = types[valueType]
	local index = indexes[valueType]
	local valueScopesSize

	if valueType == "string" then
		size = stringToBuffer.bufferSize(value) - 16
	elseif valueType == "number" then
		size = returnNumberSize(value)
		
		index = if value % 1 == 0 then 2 else 3
	elseif valueType == "table" then
		size, valueScopesSize, _ = countBufferSize(value)
	end

	buffer.writebits(b, scopeOffset, 3, index)
	buffer.writebits(b, scopeOffset + 3, 16, size)

	if valueType == "string" then
		stringToBuffer.write(b, value, scopeOffset + 3, offset)
	elseif valueType == "Vector3" then
		vector3ToBuffer.write(b, value, offset)
	elseif valueType == "CFrame" then	
		cframeToBuffer.write(b, value, offset)
	elseif valueType == "number" then
		if value % 1 == 0 then
			writeInt(b, value, size, offset)
		else
			writeFloat(b, value, size, offset)
		end
	elseif valueType == "boolean" then
		buffer.writebits(b, offset, size, value and 1 or 0)
	elseif valueType == "table" then
		local valueScopeOffset = offset + 16
		local valueOffset = offset + 16 + valueScopesSize
		
		buffer.writebits(b, offset, 16, valueScopesSize)
		
		for key, valueInValue in value do
			valueScopeOffset, valueOffset = writeKey(b, valueScopeOffset, valueOffset, key)
			valueScopeOffset, valueOffset = writeValue(b, valueScopeOffset, valueOffset, valueInValue)
		end
	end
	
	return scopeOffset + SCOPE_SIZE, offset + size
end

--[=[
	@param b buffer;
	@param tableToFill t;
	@param startOffset number?;
	
	@return t;
	
	Reads written in buffer table from startOffset given in bits and
	recursivly fills every nested table, if there are.
]=]
local function read(b: buffer, tableToFill: t, startOffset: number?)
	startOffset = startOffset or 0
	
	local scopesSize = buffer.readbits(b, startOffset, 16)
	local scopeOffset = startOffset + 16
	local offset = startOffset + 16 + scopesSize
	
	local key
	
	for scopeIndex = 0, scopesSize - SCOPE_SIZE, SCOPE_SIZE do
		local index = buffer.readbits(b, scopeOffset + scopeIndex, 3)
		local size = buffer.readbits(b, scopeOffset + scopeIndex + 3, 16)
		
		if scopeIndex % 2 == 0 then
			if index == 1 then
				key = buffer.readbits(b, offset, size) == 1
			elseif index == 2 then
				key = readInt(b, size, offset)
			elseif index == 3 then
				key = readFloat(b, size, offset)
			elseif index == 4 then
				size *= 8
				key = stringToBuffer.read(b, offset, scopeOffset + scopeIndex + 3)
			elseif index == 5 then
				key = vector3ToBuffer.read(b, offset)
			elseif index == 6 then
				key = cframeToBuffer.read(b, offset)
			end
		else
			local value
			
			if index == 1 then
				value = buffer.readbits(b, offset, size) == 1
			elseif index == 2 then
				value = readInt(b, size, offset)
			elseif index == 3 then
				value = readFloat(b, size, offset)
			elseif index == 4 then
				value = stringToBuffer.read(b, offset, scopeOffset + scopeIndex + 3)
			elseif index == 5 then
				value = vector3ToBuffer.read(b, offset)
			elseif index == 6 then
				value = cframeToBuffer.read(b, offset)
			elseif index == 7 then
				value = read(b, {}, offset)
			end
			
			tableToFill[key] = value
		end
		
		offset += size
	end
	
	return tableToFill
end

-- Table To Buffer
local tableToBuffer = {}

--[=[
	@param t table;
	
	@return number, number, number;
	
	Iterates through table and returnes size for future buffer in bytes.
]=]
function tableToBuffer.length(t: t): number
	local _, _, size = countBufferSize(t)
	
	return size
end

--[=[
	@param tableToConvert t;
	
	@return buffer;
	
	Converts given table to buffer using this scheme:
	scopesSize (16) -> scopes (every 19 bit) -> key -> value.
]=]
function tableToBuffer.convert(tableToConvert: t): buffer
	local actualSize, scopesSize, size = countBufferSize(tableToConvert)
	local tableBuffer = buffer.create(size)
	local scopesOffset = 16
	local offset = 16 + scopesSize
	
	buffer.writebits(tableBuffer, 0, 16, scopesSize)
	
	for key, value in tableToConvert do
		scopesOffset, offset = writeKey(tableBuffer, scopesOffset, offset, key)
		scopesOffset, offset = writeValue(tableBuffer, scopesOffset, offset, value)
	end
	
	return tableBuffer
end

--[=[
	@param b buffer;
	
	@return t;
	
	Reads written in given buffer table using this scheme:
	scopesSize (16) -> scopes (every 19 bit) -> key -> value.
]=]
function tableToBuffer.read(b: buffer)
	return read(b, {} :: t)
end

return {
	tableToBuffer = tableToBuffer,
	stringToBuffer = stringToBuffer,
	vector3ToBuffer = vector3ToBuffer,
	cframeToBuffer = cframeToBuffer,
}
