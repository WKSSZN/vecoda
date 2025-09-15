/*

Decoda
Copyright (C) 2007-2013 Unknown Worlds Entertainment, Inc. 

This file is part of Decoda.

Decoda is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Decoda is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Decoda.  If not, see <http://www.gnu.org/licenses/>.

*/

#ifndef HOOK_H
#define HOOK_H
#include <MinHook.h>
#include <type_traits>

void* HookFunction(void* function, void* hook, void* api, size_t functionArgNum);
void* InstanceFunction(void* function, void* upValue, size_t functionArgNum);

template<typename R, typename... Args>
using TargetFuncPtr = R(*)(Args...);

template<typename R, typename I, typename... Args>
using InstanceFuncPtr = R(*)(I, Args...);

template<typename R, typename I, typename... Args>
TargetFuncPtr<R, Args...> HookFunction(TargetFuncPtr<R, Args...> function, InstanceFuncPtr<R, I, Args...> hook, I api)
{
	constexpr std::size_t argNum = sizeof...(Args);
	return reinterpret_cast<TargetFuncPtr<R, Args...>>(HookFunction(function, hook, reinterpret_cast<void*>(api), argNum));
}

template<typename R, typename... Args>
TargetFuncPtr<R, Args...> HookFunction(TargetFuncPtr<R, Args...> function, TargetFuncPtr<R, Args...> hook)
{
	void* original;
	MH_CreateHook(function, hook, &original);
	MH_EnableHook(function);
	return reinterpret_cast<TargetFuncPtr<R, Args...>>(original);
}

#if defined(__i386__) || defined(_M_IX86)
template<typename R, typename... Args>
using TargetStdFuncPtr = R(__stdcall*)(Args...);

template<typename R, typename... Args>
TargetStdFuncPtr<R, Args...> HookFunction(TargetStdFuncPtr<R, Args...> function, TargetStdFuncPtr<R, Args...> hook)
{
	void* original;
	MH_CreateHook(function, hook, &original);
	MH_EnableHook(function);
	return reinterpret_cast<TargetStdFuncPtr<R, Args...>>(original);
}
#endif // WIN32



template<typename R, typename I, typename... Args>
TargetFuncPtr<R, Args...> InstanceFunction(InstanceFuncPtr<R, I, Args...> function, I api)
{
	constexpr std::size_t argNum = sizeof...(Args);
	return reinterpret_cast<TargetFuncPtr<R, Args...>>(InstanceFunction(function, reinterpret_cast<void*>(api), argNum));
}

#endif