extern "C" {
#include <lua.hpp>
}

#include <Windows.h>
#include <ImageHlp.h>
#include <Psapi.h>
#include <string.h>
#include "Channel.h"

struct ExeInfo
{
	unsigned long entryPoint;
	bool managed;
	bool i386;
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

bool getExeInfo(const char* fileName, ExeInfo& info)
{
	LOADED_IMAGE loadedImage;
	if (!MapAndLoad(fileName, NULL, &loadedImage, FALSE, TRUE)) {
		return false;
	}

	info.managed = false;
	if (loadedImage.FileHeader->Signature == IMAGE_NT_SIGNATURE) {
		DWORD netHeaderAddress = loadedImage.FileHeader->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_COM_DESCRIPTOR].VirtualAddress;

		if (netHeaderAddress) {
			info.managed = true;
		}
	}
	info.entryPoint = loadedImage.FileHeader->OptionalHeader.AddressOfEntryPoint;
	info.i386 = loadedImage.FileHeader->FileHeader.Machine == IMAGE_FILE_MACHINE_I386;
	UnMapAndLoad(&loadedImage);
	return true;
}

void setBreakPoint(HANDLE hProcess, LPVOID entryPoint, bool set, BYTE* data) {
	DWORD protection;
	if (VirtualProtectEx(hProcess, entryPoint, 1, PAGE_EXECUTE_READWRITE, &protection)) {
		BYTE buffer[1];
		if (set) {
			SIZE_T numBytesRead;
			ReadProcessMemory(hProcess, entryPoint, data, 1, &numBytesRead);
			buffer[0] = 0xCC;
		}
		else {
			buffer[0] = data[0];
		}

		SIZE_T numBytesWritten;
		WriteProcessMemory(hProcess, entryPoint, buffer, 1, &numBytesWritten);
		VirtualProtectEx(hProcess, entryPoint, 1, protection, &protection);

		FlushInstructionCache(hProcess, entryPoint, 1);
	}
}

bool getStartUpDirectory(char* path, int maxPathLength) {
	if (!GetModuleFileNameA(NULL, path, maxPathLength)) return false;
	char* lastSlash = strrchr(path, '\\');
	if (lastSlash == NULL) return false;
	lastSlash[1] = 0;
	return true;
}

std::string injectDll(DWORD processId, const char* dllFileName) {

	std::string message("");
	bool success = true;
	char fullFileName[260];
	if (!getStartUpDirectory(fullFileName, 260)) return "get start up failed";
	strcat(fullFileName, dllFileName);

	HANDLE process = OpenProcess(PROCESS_ALL_ACCESS, FALSE, processId);
	if (process == NULL) return "open process failed";

	HMODULE kernelModule = GetModuleHandleA("Kernel32");
	FARPROC loadLibraryProc = GetProcAddress(kernelModule, "LoadLibraryA");

	DWORD exitCode;
	size_t length = strlen(fullFileName) + 1;
	void* remoteString = VirtualAllocEx(process, NULL, length, MEM_COMMIT, PAGE_READWRITE);
	DWORD numBytesWritten;
	WriteProcessMemory(process, remoteString, fullFileName, length, &numBytesWritten);
	char* remoteFileName = static_cast<char*>(remoteString);
	
	DWORD threadId;
	HANDLE thread = CreateRemoteThread(process, NULL, 0, (LPTHREAD_START_ROUTINE)loadLibraryProc, remoteFileName, 0, &threadId);
	if (thread == NULL) {
		success = false;
		message = "create remote thread failed";
	}
	else {
		WaitForSingleObject(thread, INFINITE);
		GetExitCodeThread(thread, &exitCode);
		CloseHandle(thread);
	}

	HMODULE dllHandle = reinterpret_cast<HMODULE>(exitCode);
	if (dllHandle == NULL) {
		success = false;
		message = std::string("inject dll failed, dll path:") +fullFileName;
	}

	if (remoteFileName != NULL) {
		VirtualFreeEx(process, remoteFileName, 0, MEM_RELEASE);
		remoteFileName = NULL;
	}

	if (process != NULL) {
		CloseHandle(process);
	}

	return message;
}

bool hasModule(const char* name, HANDLE hProcess)
{
	HMODULE hMods[1024];
	DWORD cbNeeded;
	if (EnumProcessModules(hProcess, hMods, sizeof(hMods), &cbNeeded))
	{
		for (size_t i = 0; i < (cbNeeded / sizeof(HMODULE)); i++)
		{
			char filePath[MAX_PATH];
			if (GetModuleFileNameExA(hProcess, hMods[i], filePath, MAX_PATH))
			{
				std::string moduleName = filePath;
				size_t found = moduleName.find_last_of("\\/");
				if (found != std::string::npos && moduleName.substr(found + 1) == name)
				{
					return true;
				}
			}
		}
	}
	return false;
}

extern "C" {
	int launchProcess(lua_State* L) {
		const char* exeFileName = luaL_checkstring(L, 1);
		const char* commandArgs = luaL_checkstring(L, 2);
		const char* currentDirectory = luaL_checkstring(L, 3);
		char exeCommand[256];
		_snprintf_s(exeCommand, 256, "\"%s\" %s", exeFileName, commandArgs);
		STARTUPINFOA startUpInfo = { 0 };
		startUpInfo.cb = sizeof(STARTUPINFOA);

		PROCESS_INFORMATION processInfo;

		ExeInfo exeInfo;
		if (!getExeInfo(exeFileName, exeInfo) || exeInfo.entryPoint == 0) {
			return luaL_error(L, "Error: The entry point for the application could not be located");
		}
		if (!exeInfo.i386) {
			return luaL_error(L, "Error: Debugging 64-bit applications is not supported");
		}

		DWORD flags = DEBUG_PROCESS | DEBUG_ONLY_THIS_PROCESS | CREATE_NEW_CONSOLE;

		if (!CreateProcessA(NULL, const_cast<LPSTR>(exeCommand), NULL, NULL, TRUE, flags, NULL, currentDirectory, &startUpInfo, &processInfo)) {
			luaL_error(L, "Error: Create Proccess Failed with app:%s, working directory:%s", exeCommand, currentDirectory);
		}

		if (!exeInfo.managed) {
			unsigned long entryPoint = exeInfo.entryPoint;

			BYTE breakPointData;
			bool done = false;

			while (!done) {
				DEBUG_EVENT debugEvent;
				WaitForDebugEvent(&debugEvent, INFINITE);

				DWORD continueStatus = DBG_EXCEPTION_NOT_HANDLED;
				if (debugEvent.dwDebugEventCode == EXCEPTION_DEBUG_EVENT) {
					if (debugEvent.u.Exception.ExceptionRecord.ExceptionCode == EXCEPTION_SINGLE_STEP ||
						debugEvent.u.Exception.ExceptionRecord.ExceptionCode == EXCEPTION_BREAKPOINT) {
						CONTEXT context;
						context.ContextFlags = CONTEXT_FULL;

						GetThreadContext(processInfo.hThread, &context);

						if (context.Eip == entryPoint + 1) {
							setBreakPoint(processInfo.hProcess, (LPVOID)entryPoint, false, &breakPointData);
							done = true;

							--context.Eip;
							SetThreadContext(processInfo.hThread, &context);
							SuspendThread(processInfo.hThread);
						}
						continueStatus = DBG_CONTINUE;
					}
				}
				else if (debugEvent.dwDebugEventCode == EXIT_PROCESS_DEBUG_EVENT) {
					done = true;
				}
				else if (debugEvent.dwDebugEventCode == CREATE_PROCESS_DEBUG_EVENT) {
					entryPoint += reinterpret_cast<size_t>(debugEvent.u.CreateProcessInfo.lpBaseOfImage);
					setBreakPoint(processInfo.hProcess, reinterpret_cast<void*>(entryPoint), true, &breakPointData);

					CloseHandle(debugEvent.u.CreateProcessInfo.hFile);
				}
				else if (debugEvent.dwDebugEventCode == LOAD_DLL_DEBUG_EVENT) {
					CloseHandle(debugEvent.u.LoadDll.hFile);
				}

				ContinueDebugEvent(debugEvent.dwProcessId, debugEvent.dwThreadId, continueStatus);
			}
		}
		DebugActiveProcessStop(processInfo.dwProcessId);

		DWORD exitCode;
		if (GetExitCodeProcess(processInfo.hProcess, &exitCode) && exitCode != STILL_ACTIVE) {
			return luaL_error(L, "The process has terminated unexpectedly");
		}

		char eventChannelName[256];
		_snprintf(eventChannelName, 256, "Vecoda.Event.%x", processInfo.dwProcessId);
		char commandChannelName[256];
		_snprintf(commandChannelName, 256, "Vecoda.Command.%x", processInfo.dwProcessId);

		Channel* eventChannel = new Channel();
		if (!eventChannel->Create(eventChannelName)) {
			delete eventChannel;
			return luaL_error(L, "create event channel failed");
		}
		Channel* commandChannel = new Channel();
		if (!commandChannel->Create(commandChannelName)) {
			delete commandChannel;
			return luaL_error(L, "create command channel failed");
		}

		// inject dll
		std::string message;
		if ((message = injectDll(processInfo.dwProcessId, "LuaInject.dll")).size() != 0) {
			delete eventChannel;
			delete commandChannel;
			return luaL_error(L, "Error: LuaInject.dll could not be loaded into the process:%s", message.c_str());
		}

		eventChannel->WaitForConnection();
		

		unsigned int eventId;
		eventChannel->ReadUInt32(eventId);
		if (eventId != EventId_Initialize) {
			return luaL_error(L, "Dll has not Inittialize Event");
		}

		unsigned int function;
		eventChannel->ReadUInt32(function);

		DWORD threadId;
		HANDLE thread = CreateRemoteThread(processInfo.hProcess, NULL, 0, (LPTHREAD_START_ROUTINE)function, NULL, 0, &threadId);
		if (thread == NULL) {
			return luaL_error(L, "run dll thread failed");
		}

		WaitForSingleObject(thread, INFINITE);
		GetExitCodeThread(thread, &exitCode);

		CloseHandle(thread);
		thread = NULL;

		lua_newtable(L);
		lua_pushlightuserdata(L, eventChannel);
		luaL_getmetatable(L, "CHANNELMETA");
		lua_setmetatable(L, -2);
		lua_setfield(L, -2, "EventChannel");
		lua_pushlightuserdata(L, commandChannel);
		luaL_getmetatable(L, "CHANNELMETA");
		lua_setmetatable(L, -2);
		lua_setfield(L, -2, "CommandChannel");
		lua_pushlightuserdata(L, processInfo.hProcess);
		lua_setfield(L, -2, "Process");
		lua_pushlightuserdata(L, processInfo.hThread);
		lua_setfield(L, -2, "Thread");
		luaL_getmetatable(L, "FRONTENDMETA");
		lua_setmetatable(L, -2);
		return 1;
	}

	int attachProcess(lua_State* L)
	{
		DWORD processId = luaL_checkinteger(L, 1);
		HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ | PROCESS_TERMINATE | PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION | PROCESS_VM_WRITE, FALSE, processId);
		if (hProcess == NULL)
		{
			return luaL_error(L, "open process[%x] failed", processId);
		}
		bool needInject = !hasModule("LuaInject.dll", hProcess);
		Channel* eventChannel;
		Channel* commandChannel;

		if (needInject)
		{
			char pipeName[256];
			_snprintf(pipeName, 256, "Vecoda.Event.%x", processId);
			eventChannel = new Channel();
			if (!eventChannel->Create(pipeName)) {
				delete eventChannel;
				return luaL_error(L, "create event channel failed");
			}
			_snprintf(pipeName, 256, "Vecoda.Command.%x", processId);
			commandChannel = new Channel();
			if (!commandChannel->Create(pipeName)) {
				delete commandChannel;
				return luaL_error(L, "create command channel failed");
			}
			auto message = injectDll(processId, "LuaInject.dll");
			if (message.size() != 0)
			{
				delete eventChannel;
				delete commandChannel;
				return luaL_error(L, "Error: LuaInject.dll could not be loaded into the process:%s", message.c_str());
			}
			
			eventChannel->WaitForConnection();


			unsigned int eventId;
			eventChannel->ReadUInt32(eventId);
			if (eventId != EventId_Initialize) {
				return luaL_error(L, "Dll has not Inittialize Event");
			}

			unsigned int function;
			eventChannel->ReadUInt32(function);

			DWORD threadId;
			HANDLE thread = CreateRemoteThread(hProcess, NULL, 0, (LPTHREAD_START_ROUTINE)function, NULL, 0, &threadId);
			if (thread == NULL) {
				return luaL_error(L, "run dll thread failed");
			}

			DWORD exitCode;
			WaitForSingleObject(thread, INFINITE);
			GetExitCodeThread(thread, &exitCode);

			CloseHandle(thread);
			lua_pushnil(L);
		}
		else
		{
			char pipeName[256];
			_snprintf(pipeName, 256, "Vecoda.Attach.%x", processId);
			Channel retachChannel;
			if (!retachChannel.Connect(pipeName))
			{
				return luaL_error(L, "failed to connect to process %x", processId);
			}
			_snprintf(pipeName, 256, "Vecoda.Event.%x", processId);
			eventChannel = new Channel();
			if (!eventChannel->Create(pipeName)) {
				delete eventChannel;
				return luaL_error(L, "create event channel failed");
			}
			_snprintf(pipeName, 256, "Vecoda.Command.%x", processId);
			commandChannel = new Channel();
			if (!commandChannel->Create(pipeName)) {
				delete commandChannel;
				return luaL_error(L, "create command channel failed");
			}
			lua_newtable(L);
			lua_newtable(L);
			int vms = lua_gettop(L);
			retachChannel.WriteUInt32(0);
			unsigned int num;
			retachChannel.ReadUInt32(num);
			for (size_t i = 0; i < num; i++)
			{
				unsigned int vm;
				retachChannel.ReadUInt32(vm);
				lua_pushnumber(L, vm);
				lua_rawseti(L, vms, i + 1);
			}
			lua_setfield(L, -2, "vms");
			lua_newtable(L);
			int scripts = lua_gettop(L);
			retachChannel.ReadUInt32(num);
			for (size_t i = 0; i < num; i++)
			{
				std::string str;
				lua_newtable(L);
				retachChannel.ReadString(str);
				lua_pushstring(L, str.c_str());
				lua_setfield(L, -2, "name");
				retachChannel.ReadString(str);
				lua_pushstring(L, str.c_str());
				lua_setfield(L, -2, "source");
				unsigned int state;
				retachChannel.ReadUInt32(state);
				lua_pushnumber(L, static_cast<lua_Number>(state));
				lua_setfield(L, -2, "state");
				lua_rawseti(L, scripts, i + 1);
			}
			lua_setfield(L, -2, "scripts");
		}

		lua_newtable(L);
		lua_pushlightuserdata(L, eventChannel);
		luaL_getmetatable(L, "CHANNELMETA");
		lua_setmetatable(L, -2);
		lua_setfield(L, -2, "EventChannel");
		lua_pushlightuserdata(L, commandChannel);
		luaL_getmetatable(L, "CHANNELMETA");
		lua_setmetatable(L, -2);
		lua_setfield(L, -2, "CommandChannel");
		lua_pushlightuserdata(L, hProcess);
		lua_setfield(L, -2, "Process");
		luaL_getmetatable(L, "FRONTENDMETA");
		lua_setmetatable(L, -2);
		return 2;
	}

	int channel_readUInt32(lua_State* L) {
		Channel* channel = (Channel*)lua_touserdata(L, 1);
		unsigned int value;
		if (channel->ReadUInt32(value)) {
			lua_pushinteger(L, value);
			return 1;
		}
		return 0;
	}
	int channel_nReadUInt32(lua_State* L) {
		Channel* channel = (Channel*)lua_touserdata(L, 1);
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
	int channel_readString(lua_State* L) {
		Channel* channel = (Channel*)lua_touserdata(L, 1);
		std::string value;
		if (channel->ReadString(value)) {
			lua_pushstring(L, value.c_str());
			return 1;
		}
		return 0;

	}
	int channel_readBool(lua_State* L) {
		Channel* channel = (Channel*)lua_touserdata(L, 1);
		bool value;
		if (channel->ReadBool(value)) {
			lua_pushboolean(L, value);
			return 1;
		}
		return 0;
	}
	int channel_writeUInt32(lua_State* L) {
		Channel* channel = (Channel*)lua_touserdata(L, 1);
		unsigned int value = luaL_checkinteger(L, 2);
		lua_pushboolean(L, channel->WriteUInt32(value));
		return 1;
	}
	int channel_writeString(lua_State* L) {
		Channel* channel = (Channel*)lua_touserdata(L, 1);
		const char* str = luaL_checkstring(L, 2);
		lua_pushboolean(L, channel->WriteString(str));
		return 1;
	}
	int channel_writeBool(lua_State* L) {
		Channel* channel = (Channel*)lua_touserdata(L, 1);
		int value = lua_toboolean(L, 2);
		lua_pushboolean(L, channel->WriteBool(value != 0));
		return 1;
	}
	int channel_gc(lua_State* L) {
		Channel* channel = (Channel*)lua_touserdata(L, 1);
		delete channel;
		return 0;
	}
	int frontentd_stop(lua_State* L) {
		luaL_checktype(L, 1, LUA_TTABLE);
		bool kill = lua_toboolean(L, 2);
		lua_getfield(L, 1, "Process");
		luaL_checktype(L, -1, LUA_TLIGHTUSERDATA);
		HANDLE process = (HANDLE)lua_touserdata(L, -1);
		lua_getfield(L, 1, "CommandChannel");
		Channel* commandChannel = static_cast<Channel*>(lua_touserdata(L, -1));
		if (commandChannel != nullptr) {
			commandChannel->WriteUInt32(CommandId::CommandId_Detach);
			commandChannel->WriteBool(!kill);
		}
		lua_pushnil(L);
		lua_setfield(L, 1, "EventChannel");
		lua_pushnil(L);
		lua_setfield(L, 1, "CommandChannel");
		
		if (kill) {
			TerminateProcess(process, 0);
		}
		CloseHandle(process);
		lua_pushnil(L);
		lua_setfield(L, 1, "Process");
		return 0;
	}

	int frontentd_resume(lua_State* L) {
		luaL_checktype(L, 1, LUA_TTABLE);
		lua_getfield(L, 1, "Thread");
		HANDLE hThread = (HANDLE)lua_touserdata(L, -1);
		if (hThread) {
			ResumeThread(hThread);
			CloseHandle(hThread);
			lua_pushnil(L);
			lua_setfield(L, 1, "Thread");
		}
		return 0;
	}
}

static luaL_Reg luaLibs[] =
{
	{"Launch", launchProcess},
	{"Attach", attachProcess},
	{NULL, NULL}
};

static luaL_Reg channelLibs[] =
{
	{"ReadUInt32", channel_readUInt32},
	{"NReadUInt32", channel_nReadUInt32},
	{"ReadString", channel_readString},
	{"ReadBool", channel_readBool},
	{"WriteUInt32", channel_writeUInt32},
	{"WriteString", channel_writeString},
	{"WriteBool", channel_writeBool},
	{"__gc", channel_gc},
	{NULL, NULL},
};

static luaL_Reg frontentdLibs[] =
{
	{"Stop", frontentd_stop},
	{"Resume", frontentd_resume},
	{NULL, NULL}
};

void setEnums(lua_State* L) {
	struct
	{
		const char* key;
		int data;
	} tables[]{
		{"EventId_Initialize", 11},   // Sent when the backend is ready to have its initialize function called
		{"EventId_CreateVM", 1},    // Sent when a script VM is created.
		{"EventId_DestroyVM", 2},    // Sent when a script VM is destroyed.
		{"EventId_LoadScript", 3},    // Sent when script data is loaded into the VM.
		{"EventId_Break", 4},    // Sent when the debugger breaks on a line.
		{"EventId_SetBreakpoint", 5},    // Sent when a breakpoint has been added in the debugger.
		{"EventId_Exception", 6},    // Sent when the script encounters an exception (e.g. crash).
		{"EventId_LoadError", 7},    // Sent when there is an error loading a script (e.g. syntax error).
		{"EventId_Message", 9},    // Event containing a string message from the debugger.
		{"EventId_SessionEnd", 8},    // This is used internally and shouldn't be sent.
		{"EventId_NameVM", 10},   // Sent when the name of a VM is set.
		{"CommandId_Continue", 1},    // Continues execution until the next break point.
		{"CommandId_StepOver", 2},    // Steps to the next line, not entering any functions.
		{"CommandId_StepInto", 3},    // Steps to the next line, entering any functions.
		{"CommandId_ToggleBreakpoint", 4},    // Toggles a breakpoint on a line on and off.
		{"CommandId_Break", 5},    // Instructs the debugger to break on the next line of script code.
		{"CommandId_Evaluate", 6},    // Evaluates the value of an expression in the current context.
		{"CommandId_Variable", 7},    // Get variables in the current context.
		{"CommandId_Detach", 8},    // Detaches the debugger from the process.
		{"CommandId_PatchReplaceLine", 9},    // Replaces a line of code with a new line.
		{"CommandId_PatchInsertLine", 10},   // Adds a new line of code.
		{"CommandId_PatchDeleteLine", 11},   // Deletes a line of code.
		{"CommandId_LoadDone", 12},   // Signals to the backend that the frontend has finished processing a load.
		{"CommandId_IgnoreException", 13},   // Instructs the backend to ignore the specified exception message in the future.
		{"CommandId_DeleteAllBreakpoints", 14},// Instructs the backend to clear all breakpoints set
		{"CommandId_StepOut", 15},// step out of cur func
	};

	for (int i = 0; i < sizeof(tables) / sizeof(tables[0]); i++) {
		lua_pushinteger(L, tables[i].data);
		lua_setfield(L, -2, tables[i].key);
	}
}

extern "C" __declspec(dllexport)
int luaopen_launcher(lua_State * L) {
	luaL_newmetatable(L, "CHANNELMETA");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	luaL_setfuncs(L, channelLibs, 0);

	luaL_newmetatable(L, "FRONTENDMETA");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	luaL_setfuncs(L, frontentdLibs, 0);
	lua_newtable(L);
	setEnums(L);
	luaL_setfuncs(L, luaLibs, 0);
	return 1;
}