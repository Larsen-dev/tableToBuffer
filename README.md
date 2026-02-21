# bufferUtils
Simple utility to convert mixed lua/luau tables to buffers. Can store: numbers, strings, Vector3s, Vector2s, CFrames, buffers, Enums, EnumItems, Instances and nested tables.

Created for people who don't want to use libraries as ByteNet, but stores table less-efficient than ByteNet do it, because of scopes written at the start of the buffer, so table
could be serialised back. Table store scheme looks like:
`scopesSize (24 bits) -> scopes (28 for every) -> key -> value`

Also has built-in:
- strings bufferisation functions;
- Vector3 bufferisation functions;
- Vector2 bufferisation functions;
- CFrame bufferisation functions;
- Enum bufferisation functions;
- EnumItem bufferisation functions;

# Limits
Limits are too high to reach them. If there's no bufferisation method for your type of value you can just store it as your self written buffer. Works with EncodingService.
Engine limits make limit of maximum able indexes to store nearly to ~90000, because it'll take more time and resources to wrap all data to buffers than engine gives.
