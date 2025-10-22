#pragma once
extern "C" {
#include <lua.hpp>
}
#include <Windows.h>
#include <typeinfo>
#include <memory>

#if defined(__i386__) || defined(_M_IX86)
using Address = unsigned long;
#define PC(a) (a.Eip)
#else
using Address = DWORD64;
#define PC(a) (a.Rip)
#endif

struct ExeInfo
{
	Address entryPoint;
	bool managed;
	WORD arch;
};

union AttachParam
{
	struct {
		DWORD processId;
	} p;
	struct {
		const char* ip;
		int port;
	} i;
};

enum AttachType
{
	ProcessAttach,
	IPAttach,
	None
};

enum EventId
{
	EventId_Initialize = 11,   // Sent when the backend is ready to have its initialize function called
	EventId_CreateVM = 1,    // Sent when a script VM is created.
	EventId_DestroyVM = 2,    // Sent when a script VM is destroyed.
	EventId_LoadScript = 3,    // Sent when script data is loaded into the VM.
	EventId_Break = 4,    // Sent when the debugger breaks on a line.
	EventId_SetBreakpoint = 5,    // Sent when a breakpoint has been added in the debugger.
	EventId_Exception = 6,    // Sent when the script encounters an exception (e.g. crash).
	EventId_LoadError = 7,    // Sent when there is an error loading a script (e.g. syntax error).
	EventId_Message = 9,    // Event containing a string message from the debugger.
	EventId_SessionEnd = 8,    // This is used internally and shouldn't be sent.
	EventId_NameVM = 10,   // Sent when the name of a VM is set.
};

enum CommandId
{
	CommandId_Continue = 1,    // Continues execution until the next break point.
	CommandId_StepOver = 2,    // Steps to the next line, not entering any functions.
	CommandId_StepInto = 3,    // Steps to the next line, entering any functions.
	CommandId_ToggleBreakpoint = 4,    // Toggles a breakpoint on a line on and off.
	CommandId_Break = 5,    // Instructs the debugger to break on the next line of script code.
	CommandId_Evaluate = 6,    // Evaluates the value of an expression in the current context.
	CommandId_Detach = 8,    // Detaches the debugger from the process.
	CommandId_PatchReplaceLine = 9,    // Replaces a line of code with a new line.
	CommandId_PatchInsertLine = 10,   // Adds a new line of code.
	CommandId_PatchDeleteLine = 11,   // Deletes a line of code.
	CommandId_LoadDone = 12,   // Signals to the backend that the frontend has finished processing a load.
	CommandId_IgnoreException = 13,   // Instructs the backend to ignore the specified exception message in the future.
	CommandId_DeleteAllBreakpoints = 14,// Instructs the backend to clear all breakpoints set
};

template<typename T>
T* _getPointer(lua_State* L)
{
	return *reinterpret_cast<T**>(lua_touserdata(L, 1));
}

template<typename T>
int _readUInt32(lua_State* L)
{
	T* channel = _getPointer<T>(L);
	unsigned int value;
	if (channel->ReadUInt32(value)) {
		lua_pushinteger(L, value);
		return 1;
	}
	return 0;
}

template<typename T>
int _readUInt(lua_State* L) {
	T* channel = _getPointer<T>(L);
	uint64_t value;
	if (channel->ReadUInt(value)) {
		lua_pushinteger(L, value);
		return 1;
	}
	return 0;
}

template<typename T>
int _nReadUInt32(lua_State* L) {
	T* channel = _getPointer<T>(L);
	unsigned int value;
	if (channel->NReadUInt32(value)) {
		lua_pushinteger(L, value);
		return 1;
	}
	else {
		lua_pushnil(L);
		if (value == 0xffffffff) { // 断开连接了
			lua_pushboolean(L, 1);
			return 2;
		}
		return 1;
	}
}

template<typename T>
int _readString(lua_State* L) {
	T* channel = _getPointer<T>(L);
	std::string value;
	if (channel->ReadString(value)) {
		lua_pushstring(L, value.c_str());
		return 1;
	}
	return 0;

}

template<typename T>
int _readBool(lua_State* L) {
	T* channel = _getPointer<T>(L);
	bool value;
	if (channel->ReadBool(value)) {
		lua_pushboolean(L, value);
		return 1;
	}
	return 0;
}

template<typename T>
int _writeUInt32(lua_State* L) {
	T* channel = _getPointer<T>(L);
	unsigned int value = static_cast<unsigned int>(luaL_checkinteger(L, 2));
	lua_pushboolean(L, channel->WriteUInt32(value));
	return 1;
}

template<typename T>
int _writeUInt(lua_State* L) {
	T* channel = _getPointer<T>(L);
	uint64_t value = static_cast<uint64_t>(luaL_checkinteger(L, 2));
	lua_pushboolean(L, channel->WriteUInt(value));
	return 1;
}

template<typename T>
int _writeString(lua_State* L) {
	T* channel = _getPointer<T>(L);
	const char* str = luaL_checkstring(L, 2);
	lua_pushboolean(L, channel->WriteString(str));
	return 1;
}

template<typename T>
int _writeBool(lua_State* L) {
	T* channel = _getPointer<T>(L);
	int value = lua_toboolean(L, 2);
	lua_pushboolean(L, channel->WriteBool(value != 0));
	return 1;
}

template<typename T>
int _gc(lua_State* L) {
	T* channel = _getPointer<T>(L);
	delete channel;
	return 0;
}

template<typename T>
const char* MetaName(const char* prefix)
{
	static char cache[100];
	sprintf_s(cache, "_META_%s_%s", prefix, typeid(T).name());
	return cache;
}

template<typename T>
void GetMetatable(lua_State* L, const char* prefix, luaL_Reg* funcs)
{
	const char* name = MetaName<T>(prefix);
	int t = luaL_getmetatable(L, name);
	if (t == LUA_TNIL)
	{
		lua_pop(L, 1);
		luaL_newmetatable(L, name);
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
		luaL_setfuncs(L, funcs, 0);
	}
}

template<typename T>
void PushRead(lua_State* L, T* p)
{
	static luaL_Reg funcs[] = {
		{"ReadUInt32", _readUInt32<T>},
		{"NReadUInt32", _nReadUInt32<T>},
		{"ReadUInt", _readUInt<T>},
		{"ReadString", _readString<T>},
		{"ReadBool", _readBool<T>},
		{"__gc", _gc<T>},
		{NULL, NULL}
	};

	T** userdata = reinterpret_cast<T**>(lua_newuserdata(L, sizeof(T**)));
	*userdata = p;

	GetMetatable<T>(L, "READ", funcs);
	lua_setmetatable(L, -2);
}

template<typename T>
void PushWrite(lua_State* L, T* p)
{
	static luaL_Reg funcs[] = {
	{"WriteUInt32", _writeUInt32<T>},
	{"WriteUInt", _writeUInt<T>},
	{"WriteString", _writeString<T>},
	{"WriteBool", _writeBool<T>},
	{"__gc", _gc<T>},
	{NULL, NULL}
	};

	T** userdata = reinterpret_cast<T**>(lua_newuserdata(L, sizeof(T**)));
	*userdata = p;

	GetMetatable<T>(L, "WRITE", funcs);
	lua_setmetatable(L, -2);
}