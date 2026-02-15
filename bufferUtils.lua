--!native
--!strict

-- Values
local intSizes = { 8, 16, 32 }

local accessedTypes = { "boolean", "number", "string", "Vector3", "CFrame", "table", "buffer" }

local indexes = {
	boolean = 0,
	int8 = 1,
	int16 = 2,
	int32 = 3,
	float = 4,
	["string"] = 5,
	["Vector3"] = 6,
	["CFrame"] = 7,
	["table"] = 8,
	["buffer"] = 9,
}

local sizes = {
	boolean = 1,
	int8 = 8,
	int16 = 16,
	int32 = 32,
	float = 32,
	["string"] = 8,
	["Vector3"] = 96,
	["CFrame"] = 192,
}

-- Functions

--[=[
	@param b buffer;
	@param n number;
	@param size number;
	@param offset number?;
	
	@return ;
	
	Writes some signed integer to a buffer with given in bits offset. Uses
	2 complement method to represent the negative numbers.
]=]
local function writeInt(b: buffer, n: number, size: number, offset: number?)
	offset = offset or 0
	
	local usigned = if n >= 0 then n else bit32.rshift(n, size) + n
	
	for index = 0, size - 1 do
		local bit = bit32.band(bit32.rshift(usigned, index), 1)
		buffer.writebits(b, offset + index, 1, bit)
	end
end

--[=[
	@param b buffer;
	@param n number;
	@param offset number?;
	
	@return ;
	
	Writes some signed 32 bit float to a buffer with given in bits offset.
]=]
local function writeFloat32(b: buffer, n: number, offset: number?)
	offset = offset or 0
	
	local sign = if n > 0 then 0 else 1
	local exponent = math.floor(math.log(math.abs(n), 2))
	local mantissa = math.abs(n) / (2 ^ exponent) - 1
	
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
	@param n number;
	@param offset number?;
	
	@return number;
	
	Reads some signed integer written using 2 complement method from a
	buffer with given in bits offset.
]=]
local function readInt(b: buffer, size: number, offset: number?)
	offset = offset or 0
	
	local n = 0
	
	for index = 0, size - 1 do
		local bit = buffer.readbits(b, offset + index, 1)
		n += bit * 2^index
	end

	local signBit = 2 ^ (size - 1)
	if n >= signBit then
		n -= 2^size
	end

	return n
end

--[=[
	@param b buffer;
	@param offset number?;
	
	@return number;
	
	Reads some signed 32 bit float from a given buffer with given in bits
	offset.
]=]
local function readFloat32(b: buffer, offset: number?)
	offset = offset or 0
	
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
	@param b buffer;
	@param toCopy buffer;
	@param offset number?;
	
	@return ;
	
	Copies some buffer to another buffer at given in bits offset.
]=]
local function copyBuffer(b: buffer, toCopy: buffer, offset: number?)
	offset = offset or 0
	
	local lengthInBits = buffer.len(toCopy) * 8
	
	for index = 0, lengthInBits - 1 do
		buffer.writebits(b, offset + index, 1, buffer.readbits(toCopy, index, 1))
	end
end

--[=[
	@param b buffer;
	@param length number;
	@param offset number?;
	
	@return buffer;
	
	Reads some buffer from a given buffer at given in bits offset.
]=]
local function readCopiedBuffer(b: buffer, length: number, offset: number?): buffer
	offset = offset or 0
	local copiedBuffer = buffer.create(math.ceil(length / 8))
	
	for index = 0, length - 1 do
		buffer.writebits(copiedBuffer, index, 1, buffer.readbits(b, offset + index, 1))
	end
	
	return copiedBuffer
end

-- Vector3 To Buffer
local vector3ToBuffer = {}

--[=[
	@param v3 Vector3;
	
	@return buffer;
	
	Converts Vector3 to buffer. Every side threats as 32 bit floats.
]=]
function vector3ToBuffer.convert(v3: Vector3): buffer
	local v3Buffer = buffer.create(12)
	
	writeFloat32(v3Buffer, v3.X, 0)
	writeFloat32(v3Buffer, v3.Y, 32)
	writeFloat32(v3Buffer, v3.Z, 64)
	
	return v3Buffer
end

--[=[
	@param b buffer;
	@param v3 Vector3;
	@param offset number;
	
	@return ;
	
	Writes Vector3 in buffer at given in bits offset. Every side threats as
	32 bit floats.
]=]
function vector3ToBuffer.write(b: buffer, v3: Vector3, offset: number?)
	offset = offset or 0
	
	if buffer.len(b) * 8 - offset < 92 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end
	
	writeFloat32(b, v3.X, offset + 0)
	writeFloat32(b, v3.Y, offset + 32)
	writeFloat32(b, v3.Z, offset + 64)
end

--[=[
	@param b buffer;
	@param offset number?;
	
	@return Vector3;
	
	Reads Vector3 from buffer at given in bits offset.
]=]
function vector3ToBuffer.read(b: buffer, offset: number?): Vector3
	offset = offset or 0
	
	local x = readFloat32(b, offset + 0)
	local y = readFloat32(b, offset + 32)
	local z = readFloat32(b, offset + 64)
	
	return Vector3.xAxis * x + Vector3.yAxis * y + Vector3.zAxis * z
end

-- CFrame To Buffer
local cframeToBuffer = {}

--[=[
	@param cf CFrame;
	
	@return buffer;
	
	Converts CFrame to buffer. Every side threats as 32 bit floats.
]=]
function cframeToBuffer.convert(cf: CFrame): buffer
	local cfBuffer = buffer.create(24)
	
	writeFloat32(cfBuffer, cf.Position.X, 0)
	writeFloat32(cfBuffer, cf.Position.Y, 32)
	writeFloat32(cfBuffer, cf.Position.Z, 64)
	writeFloat32(cfBuffer, cf.Rotation.Position.X, 96)
	writeFloat32(cfBuffer, cf.Rotation.Position.Y, 128)
	writeFloat32(cfBuffer, cf.Rotation.Position.Z, 160)
	
	return cfBuffer
end

--[=[
	@param b buffer;
	@param cf CFrame;
	@param offset number?;
	
	@return buffer;
	
	Writes CFrame to some buffer at given offset in bits. Every side
	threats as 32 bit floats.
]=]
function cframeToBuffer.write(b: buffer, cf: CFrame, offset: number?)
	offset = offset or 0
	
	if buffer.len(b) * 8 - offset < 192 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end
	
	writeFloat32(b, cf.Position.X, offset + 0)
	writeFloat32(b, cf.Position.Y, offset + 32)
	writeFloat32(b, cf.Position.Z, offset + 64)
	writeFloat32(b, cf.Rotation.Position.X, offset + 96)
	writeFloat32(b, cf.Rotation.Position.Y, offset + 128)
	writeFloat32(b, cf.Rotation.Position.Z, offset + 160)
end

--[=[
	@param b buffer;
	@param offset number?;
	
	@return CFrame;
	
	Reads CFrame from buffer at given in bits offset.
]=]
function cframeToBuffer.read(b: buffer, offset: number?): CFrame
	offset = offset or 0
	
	local x = readFloat32(b, offset)
	local y = readFloat32(b, offset + 32)
	local z = readFloat32(b, offset + 64)
	local rx = readFloat32(b, offset + 96)
	local ry = readFloat32(b, offset + 128)
	local rz = readFloat32(b, offset + 160)
	
	return CFrame.new(x, y, z) * CFrame.Angles(rx, ry, rz)
end

-- String To Buffer
local stringToBuffer = {}

--[=[
	@param str string;
	@return number;
	
	Returnes new buffer size in bits if it was generated using .convert() method.
]=]
function stringToBuffer.size(str: string): number
	return 24 + string.len(str) * 8
end

--[=[
	@param str string;
	
	@return buffer;
	
	Converts string into new buffer. Also writes at start its length.
]=]
function stringToBuffer.convert(str: string): buffer
	local size = stringToBuffer.size(str)
	local strBuffer = buffer.create(size / 8)
	
	buffer.writebits(strBuffer, 0, 24, size - 24)
	
	for index = 1, string.len(str) do
		local numChar = string.byte(string.sub(str, index, index))
		buffer.writebits(strBuffer, 24 + ((index - 1) * 8), 8, numChar)
	end
	
	return strBuffer
end

--[=[
	@param b buffer;
	@param str string;
	@param scopeOffset number?;
	@param offset number?;
	
	@return ;
	
	Writes in buffer string at offset with its length at lengthOffset.
	Also offset and lengthOffset should be written in bits.
]=]
function stringToBuffer.write(b: buffer, str: string, scopeOffset: number?, offset: number?)
	scopeOffset = scopeOffset or 0
	offset = offset or scopeOffset + 24
	
	local size = stringToBuffer.size(str)
	
	if buffer.len(b) * 8 - offset < size - 24 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b)))
	end
	
	buffer.writebits(b, scopeOffset, 24, size - 24)
	
	for index = 1, string.len(str) do
		local numChar = string.byte(string.sub(str, index, index))
		buffer.writebits(b, offset + ((index - 1) * 8), 8, numChar)
	end
end

--[=[
	@param b buffer;
	@param scopeOffset number?;
	@param offset number?;
	
	@return string;
	
	Reads written in buffer string, written using .write() or .convert() methods.
	Does not work with buffer made using buffer.fromstring() method.
	Also offset and lengthOffset should be written in bits, not in bytes.
]=]
function stringToBuffer.read(b: buffer, scopeOffset: number?, offset: number?): string
	scopeOffset = scopeOffset or 0
	offset = offset or scopeOffset + 24
	
	local length = buffer.readbits(b, scopeOffset, 24) / 8
	local strBuffer = buffer.create(length)
	
	for index = 0, length - 1 do
		local numChar = buffer.readbits(b, offset + index * 8, 8)
		buffer.writebits(strBuffer, index * 8, 8, numChar)
	end
	
	return buffer.tostring(strBuffer)
end

-- Values
local SCOPE_SIZE = 28

-- Types
export type t = { [boolean | string | number | Vector3 | CFrame | buffer]: boolean | string | number | Vector3 | CFrame | t | buffer }

-- Table To Buffer functions

--[=[
	@param n number;
	
	@return number;
	
	Counts what size some number is in bits. Returns only 8, 16, 32.
]=]
local function returnNumberSizeInBits(n: number)
	for _, size in intSizes do
		if n >= -(2^size / 2) and n <= 2^size / 2 - 1 then
			return size
		end
	end

	warn(string.format("%d is out of bit size range: 8, 16, 32.", n))

	return 64
end

--[=[
	@param v any;
	
	@return string;
	
	Checks and returns type of given value and returnes it's adapted string
	equivalent.
]=]
local function checkAndReturnValueType(v: any): string
	local vType = typeof(v)

	if not table.find(accessedTypes, vType) then
		error(string.format("%s is not an accessed type.", vType))
	end

	if vType == "number" then
		if v % 1 ~= 0 then
			return "float"
		end

		local bitSize = returnNumberSizeInBits(v)

		if bitSize == 8 then
			return "int8"
		elseif bitSize == 16 then
			return "int16"
		elseif bitSize == 32 then
			return "int32"
		elseif bitSize == 64 then
			return "int64"
		end
	end

	return vType
end

--[=[
	@param t t;
	
	@return number, number, number;
	
	Returns information about table: it's size in bytes, scopes size and byte size.
]=]
local function tableToBufferSize(t: t): (number, number, number)
	local scopesSize = 0
	local size = 24

	for key, value in t do
		scopesSize += SCOPE_SIZE * 2
		size += SCOPE_SIZE * 2

		local keyType = checkAndReturnValueType(key)
		local valueType = checkAndReturnValueType(value)

		if keyType == "string" then
			size += stringToBuffer.size(key :: string) - 24
		elseif keyType == "buffer" then
			size += buffer.len(key :: buffer) * 8
		else
			size += sizes[keyType :: string] :: number
		end

		if valueType == "string" then
			size += stringToBuffer.size(value :: string) - 24
		elseif valueType == "table" then
			size += tableToBufferSize(value :: t)
		elseif valueType == "buffer" then
			size += buffer.len(value :: buffer) * 8
		else
			size += sizes[valueType :: string] :: number
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
local function writeKey(b: buffer, scopeOffset: number, offset: number, key: boolean | string | number | Vector3 | CFrame | buffer): (number, number)
	local keyType = checkAndReturnValueType(key)
	
	local index = indexes[keyType]
	local size: number
	
	if keyType == "string" then
		size = stringToBuffer.size(key :: string) - 24
	elseif keyType == "buffer" then
		size = buffer.len(key :: buffer) * 8
	else
		size = sizes[keyType]
	end
	
	buffer.writebits(b, scopeOffset, 4, index)
	buffer.writebits(b, scopeOffset + 4, 24, size)
	
	if keyType == "string" then
		stringToBuffer.write(b, key :: string, scopeOffset + 4, offset)
	elseif keyType == "float" then
		writeFloat32(b, key :: number, offset)
	elseif keyType == "Vector3" then
		vector3ToBuffer.write(b, key :: Vector3, offset)
	elseif keyType == "CFrame" then
		cframeToBuffer.write(b, key :: CFrame, offset)
	elseif keyType == "boolean" then
		writeInt(b, key == true and 1 or 0, 1, offset)
	elseif keyType == "buffer" then
		copyBuffer(b, key :: buffer, offset)
	else
		writeInt(b, key :: number, size, offset)
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
local function writeValue(b: buffer, scopeOffset: number, offset: number, value: boolean | string | number | Vector3 | CFrame | t | buffer): (number, number)
	local valueType = checkAndReturnValueType(value)

	local index = indexes[valueType]
	local size: number

	if valueType == "string" then
		size = stringToBuffer.size(value :: string) - 24
	elseif valueType == "table" then
		size = tableToBufferSize(value :: t)
	elseif valueType == "buffer" then
		size = buffer.len(value :: buffer) * 8
	else
		size = sizes[valueType]
	end
	
	buffer.writebits(b, scopeOffset, 4, index)
	buffer.writebits(b, scopeOffset + 4, 24, size)
	
	if valueType == "string" then
		stringToBuffer.write(b, value :: string, scopeOffset + 4, offset)
	elseif valueType == "float" then
		writeFloat32(b, value :: number, offset)
	elseif valueType == "Vector3" then
		vector3ToBuffer.write(b, value :: Vector3, offset)
	elseif valueType == "CFrame" then
		cframeToBuffer.write(b, value :: CFrame, offset)
	elseif valueType == "boolean" then
		writeInt(b, value == true and 1 or 0, 1, offset)
	elseif valueType == "table" then
		local valueSize, valueScopesSize = tableToBufferSize(value :: t)
		
		local valueScopeOffset = offset + 24
		local valueOffset = offset + 24 + valueScopesSize
		
		buffer.writebits(b, offset, 24, valueScopesSize)
		
		for key, valueInValue in value do
			valueScopeOffset, valueOffset = writeKey(b, valueScopeOffset, valueOffset, key)
			valueScopeOffset, valueOffset = writeValue(b, valueScopeOffset, valueOffset, valueInValue)
		end
	elseif valueType == "buffer" then
		copyBuffer(b, value :: buffer, offset)
	else
		writeInt(b, value :: number, size, offset)
	end
	
	return scopeOffset + SCOPE_SIZE, offset + size
end

-- Table To Buffer
local tableToBuffer = {}

--[=[
	@param t table;
	
	@return number, number, number;
	
	Iterates through table and returnes sizes for future buffer: in bits,
	scopes size in bits and future buffer's size in bytes.
]=]
function tableToBuffer.size(t: t): (number, number, number)
	return tableToBufferSize(t)
end

--[=[
	@param tableToConvert t;
	
	@return buffer;
	
	Converts given table to buffer using this scheme:
	scopesSize (24) -> scopes (every 28 bit) -> key -> value.
]=]
function tableToBuffer.convert(t: t): buffer
	local size, scopesSize, sizeInBytes = tableToBuffer.size(t)
	local tBuffer = buffer.create(sizeInBytes)
	
	local scopesOffset = 24
	local offset = scopesSize + 24
	
	buffer.writebits(tBuffer, 0, 24, scopesSize)
	
	for key, value in t do
		scopesOffset, offset = writeKey(tBuffer, scopesOffset, offset, key)
		scopesOffset, offset = writeValue(tBuffer, scopesOffset, offset, value)
	end
	
	return tBuffer
end

function tableToBuffer.write(b: buffer, t: t, scopesOffset: number?, offset: number?)
	local size, scopesSize, sizeInBytes = tableToBuffer.size(t)
	
	scopesOffset = scopesOffset or 24
	offset = offset or scopesSize + 24
	
	if buffer.len(b) * 8 - offset < size then
		error(string.format("buffer's length %d is not enough", buffer.len(b)))
	end
	
	buffer.writebits(b, 0, 24, scopesSize)
	
	for key, value in t do
		scopesOffset, offset = writeKey(b, scopesOffset, offset, key)
		scopesOffset, offset = writeValue(b, scopesOffset, offset, value)
	end
end

--[=[
	@param b buffer;
	
	@return t;
	
	Reads written in given buffer table using this scheme:
	scopesSize (24) -> scopes (every 28 bit) -> key -> value.
]=]
function tableToBuffer.read(b: buffer, scopesOffset: number?, offset: number?): t
	scopesOffset = scopesOffset or 0
	
	local scopesSize = buffer.readbits(b, scopesOffset, 24)
	
	scopesOffset += 24
	offset = offset or scopesOffset + scopesSize
	
	local descriptors = {} :: { {
		keyIndex: number,
		keySize: number,
		keySizeOffset: number,
		valueIndex: number,
		valueSize: number,
		valueSizeOffset: number,
	} }
	local readOffset = scopesOffset

	while readOffset < scopesOffset + scopesSize do
		local keyIndex = buffer.readbits(b, readOffset, 4)
		local keySize = buffer.readbits(b, readOffset + 4, 24)

		local valueIndex = buffer.readbits(b, readOffset + SCOPE_SIZE, 4)
		local valueSize = buffer.readbits(b, readOffset + SCOPE_SIZE + 4, 24)
		
		table.insert(descriptors, {
			keyIndex = keyIndex,
			keySize = keySize,
			keySizeOffset = readOffset + 4,
			valueIndex = valueIndex,
			valueSize = valueSize,
			valueSizeOffset = readOffset + SCOPE_SIZE + 4,
		})

		readOffset += SCOPE_SIZE * 2
	end

	local t = {} :: t

	for _, descriptor in ipairs(descriptors) do
		local key
		if descriptor.keyIndex == indexes["string"] then
			key = stringToBuffer.read(b, descriptor.keySizeOffset, offset)
		elseif descriptor.keyIndex == indexes["Vector3"] then
			key = vector3ToBuffer.read(b, offset)
		elseif descriptor.keyIndex == indexes["CFrame"] then
			key = cframeToBuffer.read(b, offset)
		elseif descriptor.keyIndex == indexes["boolean"] then
			key = readInt(b, descriptor.keySize, offset) == 1
		elseif descriptor.keyIndex == indexes["float"] then
			key = readFloat32(b, offset)
		elseif descriptor.keyIndex == indexes["buffer"] then
			key = readCopiedBuffer(b, descriptor.keySize, offset)
		else
			key = readInt(b, descriptor.keySize, offset)
		end

		offset += descriptor.keySize

		local value
		if descriptor.valueIndex == indexes["string"] then
			value = stringToBuffer.read(b, descriptor.valueSizeOffset, offset)
		elseif descriptor.valueIndex == indexes["Vector3"] then
			value = vector3ToBuffer.read(b, offset)
		elseif descriptor.valueIndex == indexes["CFrame"] then
			value = cframeToBuffer.read(b, offset)
		elseif descriptor.valueIndex == indexes["boolean"] then
			value = readInt(b, descriptor.valueSize, offset) == 1
		elseif descriptor.valueIndex == indexes["float"] then
			value = readFloat32(b, offset)
		elseif descriptor.valueIndex == indexes["table"] then
			value = tableToBuffer.read(b, offset)
		elseif descriptor.valueIndex == indexes["buffer"] then
			value = readCopiedBuffer(b, descriptor.valueSize, offset)
		else
			value = readInt(b, descriptor.valueSize, offset)
		end

		offset += descriptor.valueSize

		t[key] = value
	end

	return t
end

return table.freeze({
	tableToBuffer = tableToBuffer,
	stringToBuffer = stringToBuffer,
	vector3ToBuffer = vector3ToBuffer,
	cframeToBuffer = cframeToBuffer,
})
