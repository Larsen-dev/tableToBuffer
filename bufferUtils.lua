--!native
--!strict

-- Values
local intSizes = { 8, 16, 32 }

local accessedTypes = { "boolean", "number", "string", "Vector3", "Vector2", "CFrame", "table", "buffer", "Enum", "EnumItem", "Instance" }

local indexes = {
	boolean = 0,
	int8 = 1,
	int16 = 2,
	int32 = 3,
	float32 = 4,
	float64 = 5,
	["string"] = 6,
	["Vector3"] = 7,
	["Vector2"] = 8,
	["CFrame"] = 9,
	["table"] = 10,
	["buffer"] = 11,
	["Enum"] = 12,
	["EnumItem"] = 13,
	["Instance"] = 14,
}

local sizes = {
	boolean = 1,
	int8 = 8,
	int16 = 16,
	int32 = 32,
	float32 = 32,
	float64 = 64,
	["string"] = 8,
	["Vector3"] = 192,
	["Vector2"] = 64,
	["CFrame"] = 384,
	["Enum"] = 10,
	["EnumItem"] = 12
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
	
	if n == 0 then
		local sign = if 1 / n == -math.huge then 1 else 0

		for index = 0, 31 do
			local bit = (index == 31) and sign or 0
			buffer.writebits(b, offset + index, 1, bit)
		end

		return
	end
	
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
	@param b number;
	@param offset number?;
	
	@return ;
	
	Writes 64 bit float to a buffer with given in bits offset. Uses IEE-754
	standard.
]=]
local function writeFloat64(b: buffer, n: number, offset: number?)
	offset = offset or 0

	if n == 0 then
		local sign = if 1 / n == -math.huge then 1 else 0

		for index = 0, 63 do
			local bit = (index == 63) and sign or 0
			buffer.writebits(b, offset + index, 1, bit)
		end

		return
	end

	local sign = (n < 0) and 1 or 0
	local exponent = math.floor(math.log(math.abs(n), 2))
	local mantissa = math.abs(n) / (2 ^ exponent) - 1

	local exponentBits = exponent + 1023
	local mantissaBits = math.floor(mantissa * 2^52 + 0.5)

	local mantissaHighBits = math.floor(mantissaBits / 2^32)
	local mantissaLowBits = mantissaBits % 2^32

	local high =
		bit32.lshift(sign, 31)
		+ bit32.lshift(exponentBits, 20)
		+ bit32.band(mantissaHighBits, 0xFFFFF)

	for index = 0, 31 do
		local bit = bit32.band(bit32.rshift(high, index), 1)
		buffer.writebits(b, offset + index, 1, bit)
	end

	for index = 0, 31 do
		local bit = bit32.band(bit32.rshift(mantissaLowBits, index), 1)
		buffer.writebits(b, offset + 32 + index, 1, bit)
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
	@param offset number?;
	
	@return number;
	
	Reads some written in the buffer 64 bit float written using IEE-754
	standard at some offset in bits.
]=]
local function readFloat64(b: buffer, offset: number?)
	offset = offset or 0

	local high = 0

	for index = 0, 31 do
		local bit = buffer.readbits(b, offset + index, 1)
		high += bit * 2^index
	end

	local mantissaLow = 0

	for index = 0, 31 do
		local bit = buffer.readbits(b, offset + 32 + index, 1)
		mantissaLow += bit * 2^index
	end

	local sign = bit32.rshift(high, 31)
	local exponentBits = bit32.band(bit32.rshift(high, 20), 0x7FF)
	local mantissaHigh = bit32.band(high, 0xFFFFF)

	if exponentBits == 0 and mantissaHigh == 0 and mantissaLow == 0 then
		return if sign == 1 then -0 else 0
	end

	local exponent = exponentBits - 1023
	local mantissa = 1 + ((mantissaHigh * 2^32 + mantissaLow) / 2^52)
	local value = mantissa * (2 ^ exponent)

	return if sign == 1 then -value else value
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

--[=[
	@param inst Instance;
	@param path { string };
	
	@return { string };
	
	Fills given table with given instance path. Be careful when use it from
	client.
]=]
local function instancePath(inst: Instance, path: { string }): { string }
	table.insert(path, inst.Name)

	if inst == game or not inst.Parent then
		return path
	else
		return instancePath(inst.Parent, path)
	end
end

-- Vector3 To Buffer
local vector3ToBuffer = {}

--[=[
	@param v3 Vector3;
	
	@return buffer;
	
	Converts Vector3 to buffer. Every side threats as 64 bit float.
]=]
function vector3ToBuffer.convert(v3: Vector3): buffer
	local v3Buffer = buffer.create(12)
	
	writeFloat64(v3Buffer, v3.X, 0)
	writeFloat64(v3Buffer, v3.Y, 32)
	writeFloat64(v3Buffer, v3.Z, 64)
	
	return v3Buffer
end

--[=[
	@param b buffer;
	@param v3 Vector3;
	@param offset number;
	
	@return ;
	
	Writes Vector3 in buffer at given in bits offset. Every side threats as
	64 bit float.
]=]
function vector3ToBuffer.write(b: buffer, v3: Vector3, offset: number?)
	offset = offset or 0
	
	if buffer.len(b) * 8 - offset < 92 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end
	
	writeFloat64(b, v3.X, offset + 0)
	writeFloat64(b, v3.Y, offset + 32)
	writeFloat64(b, v3.Z, offset + 64)
end

--[=[
	@param b buffer;
	@param offset number?;
	
	@return Vector3;
	
	Reads Vector3 from buffer at given in bits offset.
]=]
function vector3ToBuffer.read(b: buffer, offset: number?): Vector3
	offset = offset or 0
	
	local x = readFloat64(b, offset + 0)
	local y = readFloat64(b, offset + 32)
	local z = readFloat64(b, offset + 64)
	
	return Vector3.xAxis * x + Vector3.yAxis * y + Vector3.zAxis * z
end

-- Vector2 To Buffer
local vector2ToBuffer = {}

--[=[
	@param v2 Vector2;
	
	@return buffer;
	
	Converts Vector2 to buffer. Every side threats as 32 bit floats.
]=]
function vector2ToBuffer.convert(v2: Vector2): buffer
	local v2Buffer = buffer.create(8)

	writeFloat32(v2Buffer, v2.X, 0)
	writeFloat32(v2Buffer, v2.Y, 32)

	return v2Buffer
end

--[=[
	@param b buffer;
	@param v2 Vector2;
	@param offset number?;
	
	@return ;
	
	Writes Vector2 to buffer. Every side threats as 32 bit floats.
]=]
function vector2ToBuffer.write(b: buffer, v2: Vector2, offset: number?)
	offset = offset or 0

	if buffer.len(b) * 8 - offset < 64 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end

	writeFloat32(b, v2.X, offset)
	writeFloat32(b, v2.Y, offset + 32)
end

--[=[
	@param b buffer;
	@param offset number?;
	
	@return Vector2;
	
	Reads Vector2 from buffer. Every side threats as 32 bit floats.
]=]
function vector2ToBuffer.read(b: buffer, offset: number?): Vector2
	offset = offset or 0

	if buffer.len(b) * 8 - offset < 192 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end

	local x = readFloat32(b, offset)
	local y = readFloat32(b, offset + 32)

	return Vector2.xAxis * x + Vector2.yAxis * y
end

-- CFrame To Buffer
local cframeToBuffer = {}

--[=[
	@param cf CFrame;
	
	@return buffer;
	
	Converts CFrame to buffer. Every side threats as 64 bit float.
]=]
function cframeToBuffer.convert(cf: CFrame): buffer
	local cfBuffer = buffer.create(24)
	
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	
	writeFloat64(cfBuffer, cf.Position.X, 0)
	writeFloat64(cfBuffer, cf.Position.Y, 32)
	writeFloat64(cfBuffer, cf.Position.Z, 64)
	writeFloat64(cfBuffer, rx, 96)
	writeFloat64(cfBuffer, ry, 128)
	writeFloat64(cfBuffer, rz, 160)
	
	return cfBuffer
end

--[=[
	@param b buffer;
	@param cf CFrame;
	@param offset number?;
	
	@return buffer;
	
	Writes CFrame to some buffer at given offset in bits. Every side
	threats as 64 bit float.
]=]
function cframeToBuffer.write(b: buffer, cf: CFrame, offset: number?)
	offset = offset or 0
	
	if buffer.len(b) * 8 - offset < 192 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end
	
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	
	writeFloat64(b, cf.Position.X, offset + 0)
	writeFloat64(b, cf.Position.Y, offset + 32)
	writeFloat64(b, cf.Position.Z, offset + 64)
	writeFloat64(b, rx, offset + 96)
	writeFloat64(b, ry, offset + 128)
	writeFloat64(b, rz, offset + 160)
end

--[=[
	@param b buffer;
	@param offset number?;
	
	@return CFrame;
	
	Reads CFrame from buffer at given in bits offset.
]=]
function cframeToBuffer.read(b: buffer, offset: number?): CFrame
	offset = offset or 0
	
	local x = readFloat64(b, offset)
	local y = readFloat64(b, offset + 32)
	local z = readFloat64(b, offset + 64)
	local rx = readFloat64(b, offset + 96)
	local ry = readFloat64(b, offset + 128)
	local rz = readFloat64(b, offset + 160)
	
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

-- Enum To Buffer
local enumToBuffer = {}
enumToBuffer.enums = Enum:GetEnums()

--[=[
	@param enum Enum;
	
	@return buffer;
	
	Converts given enum to buffer.
]=]
function enumToBuffer.convert(enum: Enum): buffer
	local indexOfEnum = table.find(enumToBuffer.enums, enum)
	if not indexOfEnum then error("No such Enum.") end

	local enumBuffer = buffer.create(2)
	buffer.writebits(enumBuffer, 0, 10, indexOfEnum)

	return enumBuffer
end

--[=[
	@param b buffer;
	@param enum Enum;
	@param offset number?;
	
	@return ;
	
	Writes given enum to buffer at given offset.
]=]
function enumToBuffer.write(b: buffer, enum: Enum, offset: number?)
	offset = offset or 0

	if buffer.len(b) * 8 - offset < 10 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end

	local indexOfEnum = table.find(enumToBuffer.enums, enum)
	if not indexOfEnum then error("No such Enum.") end

	buffer.writebits(b, offset, 10, indexOfEnum)
end

--[=[
	@param b buffer;
	@param offset number?;
	
	@return Enum;
	
	Reads enum from buffer at given offset.
]=]
function enumToBuffer.read(b: buffer, offset: number?): Enum
	offset = offset or 0

	if buffer.len(b) * 8 - offset < 10 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end

	local indexOfEnum = buffer.readbits(b, offset, 10)

	return enumToBuffer.enums[indexOfEnum]
end

-- EnumItem To Buffer
local enumItemToBuffer = {}
enumItemToBuffer.enumsValues = {} :: { EnumItem }

for _, enum in ipairs(Enum:GetEnums()) do
	for _, enumItem in ipairs(enum:GetEnumItems()) do
		table.insert(enumItemToBuffer.enumsValues, enumItem)
	end
end

--[=[
	@param enumItem EnumItem;
	
	@return buffer;
	
	Converts given enumItem item to buffer.
]=]
function enumItemToBuffer.convert(enumItem: EnumItem): buffer
	local indexOfEnumItem = table.find(enumItemToBuffer.enumsValues, enumItem)
	if not indexOfEnumItem then error("No such EnumItem.") end

	local enumItemBuffer = buffer.create(2)
	buffer.writebits(enumItemBuffer, 0, 12, indexOfEnumItem)

	return enumItemBuffer
end

--[=[
	@param b buffer;
	@param enumItem EnumItem;
	@param offset number?;
	
	@return ;
	
	Writes given enumItem to buffer at given offset.
]=]
function enumItemToBuffer.write(b: buffer, enumItem: EnumItem, offset: number?)
	offset = offset or 0

	if buffer.len(b) * 8 - offset < 12 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end

	local indexOfEnumItem = table.find(enumItemToBuffer.enumsValues, enumItem)
	if not indexOfEnumItem then error("No such EnumItem.") end

	buffer.writebits(b, offset, 12, indexOfEnumItem)
end

--[=[
	@param b buffer;
	@param offset number?;
	
	@return EnumItem;
	
	Reads some enumItem from a given buffer at given in bits offset.
]=]
function enumItemToBuffer.read(b: buffer, offset: number?): EnumItem
	offset = offset or 0

	if buffer.len(b) * 8 - offset < 12 then
		error(string.format("buffer's length %d is not enough.", buffer.len(b) * 8))
	end

	local indexOfEnumItem = buffer.readbits(b, offset, 12)

	return enumItemToBuffer.enumsValues[indexOfEnumItem]
end

-- Values
local SCOPE_SIZE = 28

-- Types
type accesed = boolean | string | number | Vector3 | Vector2 | CFrame | buffer | Enum | EnumItem | Instance
export type t = { [accesed]: accesed | t }

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

	warn(string.format("%d is out of bit size range: 8, 16, 32, 64.", n))

	return 32
end

--[=[
	@param n number;
	
	@return number;
	
	Returns numbers after float point as int.
]=]
local function returnAfterCommaAsInt(n: number): number
	return if n % 1 == 0 then n else returnAfterCommaAsInt(n * 10)
end

--[=[
	@param n number;
	
	@return number;
	
	Returns number's with float point size in bits.
]=]
local function returnFloatSizeInBits(n: number): number
	return if returnAfterCommaAsInt(math.abs(n)) % 1 < 2^23 then 32 else 64
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
		return if v % 1 == 0 then string.format("int%d", returnNumberSizeInBits(v))
			else string.format("float%d", returnFloatSizeInBits(v))
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
		elseif keyType == "Instance" then
			size += tableToBufferSize(instancePath(key :: Instance, {}) :: t)
		else
			size += sizes[keyType :: string] :: number
		end

		if valueType == "string" then
			size += stringToBuffer.size(value :: string) - 24
		elseif valueType == "table" then
			size += tableToBufferSize(value :: t)
		elseif valueType == "buffer" then
			size += buffer.len(value :: buffer) * 8
		elseif valueType == "Instance" then
			size += tableToBufferSize(instancePath(value :: Instance, {}) :: t)
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
local function writeKey(b: buffer, scopeOffset: number, offset: number, key: accesed): (number, number)
	local keyType = checkAndReturnValueType(key)
	
	local index = indexes[keyType]
	local size: number
	
	if keyType == "string" then
		size = stringToBuffer.size(key :: string) - 24
	elseif keyType == "buffer" then
		size = buffer.len(key :: buffer) * 8
	elseif keyType == "Instance" then
		size = 0

		local pathToInstance = instancePath(key :: Instance, {})

		for _, name in ipairs(pathToInstance) do
			size += stringToBuffer.size(name)
		end
	else
		size = sizes[keyType]
	end
	
	buffer.writebits(b, scopeOffset, 4, index)
	buffer.writebits(b, scopeOffset + 4, 24, size)
	
	if keyType == "string" then
		stringToBuffer.write(b, key :: string, scopeOffset + 4, offset)
	elseif keyType == "float32" then
		writeFloat32(b, key :: number, offset)
	elseif keyType == "float64" then
		writeFloat64(b, key :: number, offset)
	elseif keyType == "Vector3" then
		vector3ToBuffer.write(b, key :: Vector3, offset)
	elseif keyType == "Vector2" then
		vector2ToBuffer.write(b, key :: Vector2, offset)
	elseif keyType == "CFrame" then
		cframeToBuffer.write(b, key :: CFrame, offset)
	elseif keyType == "boolean" then
		buffer.writebits(b, offset, 1, key == true and 1 or 0)
	elseif keyType == "buffer" then
		copyBuffer(b, key :: buffer, offset)
	elseif keyType == "Enum" then
		enumToBuffer.write(b, key :: Enum, offset)
	elseif keyType == "EnumItem" then
		enumItemToBuffer.write(b, key :: EnumItem, offset)
	elseif keyType == "Instance" then
		local pathToInstance = instancePath(key :: Instance, {})

		for _, name in ipairs(pathToInstance) do
			stringToBuffer.write(b, name, offset)
			offset += stringToBuffer.size(name)
		end
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
local function writeValue(b: buffer, scopeOffset: number, offset: number, value: accesed | t): (number, number)
	local valueType = checkAndReturnValueType(value)

	local index = indexes[valueType]
	local size: number

	if valueType == "string" then
		size = stringToBuffer.size(value :: string) - 24
	elseif valueType == "table" then
		size = tableToBufferSize(value :: t)
	elseif valueType == "buffer" then
		size = buffer.len(value :: buffer) * 8
	elseif valueType == "Instance" then
		size = 0

		local pathToInstance = instancePath(value :: Instance, {})

		for _, name in ipairs(pathToInstance) do
			size += stringToBuffer.size(name)
		end
	else
		size = sizes[valueType]
	end
	
	buffer.writebits(b, scopeOffset, 4, index)
	buffer.writebits(b, scopeOffset + 4, 24, size)
	
	if valueType == "string" then
		stringToBuffer.write(b, value :: string, scopeOffset + 4, offset)
	elseif valueType == "float32" then
		writeFloat32(b, value :: number, offset)
	elseif valueType == "float64" then
		writeFloat64(b, value :: number, offset)
	elseif valueType == "Vector3" then
		vector3ToBuffer.write(b, value :: Vector3, offset)
	elseif valueType == "Vector2" then
		vector2ToBuffer.write(b, value :: Vector2, offset)
	elseif valueType == "CFrame" then
		cframeToBuffer.write(b, value :: CFrame, offset)
	elseif valueType == "boolean" then
		buffer.writebits(b, offset, 1, value == true and 1 or 0)
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
	elseif valueType == "Enum" then
		enumToBuffer.write(b, value :: Enum, offset)
	elseif valueType == "EnumItem" then
		enumItemToBuffer.write(b, value :: EnumItem, offset)
	elseif valueType == "Instance" then
		local pathToInstance = instancePath(value :: Instance, {})

		for _, name in ipairs(pathToInstance) do
			stringToBuffer.write(b, name, offset)
			offset += stringToBuffer.size(name)
		end
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
			key = buffer.readbits(b, offset, 1) == 1
		elseif descriptor.keyIndex == indexes["float32"] then
			key = readFloat32(b, offset)
		elseif descriptor.keyIndex == indexes["float64"] then
			key = readFloat64(b, offset)
		elseif descriptor.keyIndex == indexes["buffer"] then
			key = readCopiedBuffer(b, descriptor.keySize, offset)
		elseif descriptor.keyIndex == indexes["Enum"] then
			key = enumToBuffer.read(b, offset)
		elseif descriptor.keyIndex == indexes["EnumItem"] then
			key = enumItemToBuffer.read(b, offset)
		elseif descriptor.keyIndex == indexes["Instance"] then
			key = game

			local border = 0

			while border < descriptor.keySize do
				local instanceName = stringToBuffer.read(b, offset)
				key = key:FindFirstChild(instanceName) :: Instance

				if not key then
					break
				end

				border += stringToBuffer.size(instanceName)
			end

			if not key then
				warn("Couldn't find valid instance, skipping key.")

				continue
			end
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
			value = buffer.readbits(b, offset, 1) == 1
		elseif descriptor.valueIndex == indexes["float32"] then
			value = readFloat32(b, offset)
		elseif descriptor.valueIndex == indexes["float64"] then
			value = readFloat64(b, offset)
		elseif descriptor.valueIndex == indexes["table"] then
			value = tableToBuffer.read(b, offset)
		elseif descriptor.valueIndex == indexes["buffer"] then
			value = readCopiedBuffer(b, descriptor.valueSize, offset)
		elseif descriptor.valueIndex == indexes["Enum"] then
			value = enumToBuffer.read(b, offset)
		elseif descriptor.valueIndex == indexes["EnumItem"] then
			value = enumItemToBuffer.read(b, offset)
		elseif descriptor.valueIndex == indexes["Instance"] then
			value = game

			local border = 0

			while border < descriptor.keySize do
				local instanceName = stringToBuffer.read(b, offset)
				value = value:FindFirstChild(instanceName) :: Instance

				if not value then
					break
				end

				border += stringToBuffer.size(instanceName)
			end

			if not value then
				warn("Couldn't find valid instance, skipping key.")

				continue
			end
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
	vector2ToBuffer = vector2ToBuffer,
	cframeToBuffer = cframeToBuffer,
	enumToBuffer = enumToBuffer,
	enumItemToBuffer = enumItemToBuffer,
})
