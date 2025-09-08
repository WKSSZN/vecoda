#include "Hook.h"

HANDLE g_trampolineHeap = NULL;
static unsigned char code[2048];
static size_t index;
//static struct mhguard {
//	mhguard() {
//		MH_Initialize();
//	}
//	~mhguard() {
//		MH_Uninitialize();
//		if (g_trampolineHeap != NULL)
//		{
//			HeapDestroy(g_trampolineHeap);
//		}
//	}
//	static mhguard h;
//};
static MH_STATUS _st = MH_Initialize();

// for jump insts at start of function
#ifdef WIN64
#define FIX16(x) (((x+0xf)>>4)<<4)
#else
static size_t callIndex;
#endif

void* Alloc(size_t size)
{
	if (g_trampolineHeap == NULL)
	{
		g_trampolineHeap = HeapCreate(0x00040000, 1024 * 2, 0);
	}

	return HeapAlloc(g_trampolineHeap, 0, size);
}

void* Hook(void* function, void* hook)
{
	return NULL;
}

void* HookFunction(void* function, void* hook, void* api, size_t functionArgNum)
{
	void* instance = InstanceFunction(hook, api, functionArgNum);
	void* original;
	MH_CreateHook(function, instance, &original);
	MH_EnableHook(function);
	return original;
}

void* InstanceFunction(void* function, void* upValue, size_t functionArgNum)
{
	functionArgNum;
#ifdef WIN64
	size_t rspSize = 32;
	if (functionArgNum > 3)
	{
		// functionArgNum+1= new function arg num
		rspSize += (functionArgNum + 1 - 4) * 8; // arguments after 4th putting on the stack
	}
	rspSize = FIX16(rspSize) + 8;
#else
#endif
	index = 0;
#ifdef WIN64
	//push rdi
	code[index++] = 0x57;

	// push rax
	code[index++] = 0x50;

	// sub rsp espSize
	code[index++] = 0x48;
	if (rspSize >= 0x80)
	{
		code[index++] = 0x81;
		code[index++] = 0xec;
		*(unsigned long*)(code + index) = static_cast<unsigned long>(rspSize);
		index += sizeof(unsigned long);
	}
	else
	{
		code[index++] = 0x83;
		code[index++] = 0xec;
		code[index++] = (char)rspSize;
	}
	for (size_t i = functionArgNum; i > 0; i--)
	{
		if (i == 1)
		{
			// mov rdx, rcx
			code[index++] = 0x48;
			code[index++] = 0x8b;
			code[index++] = 0xd1;
		}
		else if (i == 2)
		{
			// mov r8, rdx
			code[index++] = 0x4c;
			code[index++] = 0x8b;
			code[index++] = 0xc2;
		}
		else if (i == 3)
		{
			// mov r9, r8
			code[index++] = 0x4d;
			code[index++] = 0x8b;
			code[index++] = 0xc8;
		}
		else if (i == 4)
		{
			// mov qword ptr [rsp+20h], r9
			code[index++] = 0x4c;
			code[index++] = 0x89;
			code[index++] = 0x4c;
			code[index++] = 0x24;
			code[index++] = 0x20;
		}
		else
		{
			size_t srcRsp = rspSize + 0x30 + (i - 4) * 8;
			size_t dstRsp = 0x20 + (i - 4) * 8;
			// mov rax, qword ptr [rsp+srcRsp]
			code[index++] = 0x48;
			code[index++] = 0x8b;
			if (srcRsp >= 0x80)
			{
				code[index++] = 0x84;
				code[index++] = 0x24;
				*(unsigned long*)(code + index) = static_cast<unsigned long>(srcRsp);
				index += sizeof(unsigned long);
			}
			else
			{
				code[index++] = 0x44;
				code[index++] = 0x24;
				code[index++] = (char)srcRsp;
			}

			// mov qword ptr [rsp+dstRsp]
			code[index++] = 0x48;
			code[index++] = 0x89;
			if (dstRsp >= 0x80)
			{
				code[index++] = 0x84;
				code[index++] = 0x24;
				*(unsigned long*)(code + index) = static_cast<unsigned long>(dstRsp);
				index += sizeof(unsigned long);
			}
			else
			{
				code[index++] = 0x44;
				code[index++] = 0x24;
				code[index++] = (char)dstRsp;
			}
		}
	}

	// mov rcx upValue
	code[index++] = 0x48;
	code[index++] = 0xb9;
	*(void**)(code + index) = upValue;
	index += sizeof(void*);

	// mov rax hook
	code[index++] = 0x48;
	code[index++] = 0xb8;
	*(void**)(code + index) = function;
	index += sizeof(void*);

	// call rax
	code[index++] = 0xff;
	code[index++] = 0xd0;

	// add rsp respSize
	if (rspSize >= 0x80)
	{
		code[index++] = 0x48;
		code[index++] = 0x81;
		code[index++] = 0xc4;
		*(unsigned long*)(code + index) = static_cast<unsigned long>(rspSize);
		index += sizeof(unsigned long);
	}
	else
	{
		code[index++] = 0x48;
		code[index++] = 0x83;
		code[index++] = 0xc4;
		code[index++] = (char)rspSize;
	}
	// pop rax
	code[index++] = 0x58;

	// pop rdi
	code[index++] = 0x5f;
#else
	unsigned long inst = 0x2474ff | (functionArgNum * 4) << 24;
	for (size_t i = 0; i < functionArgNum; i++)
	{
		*(unsigned long*)(code + index) = inst; // push[esp+functionArgNum*4]
		index += 4;
	}

	// push extraArg
	code[index++] = 0x68;
	*(void**)(code + index) = upValue;
	index += 4;

	// call function
	code[index++] = 0xe8;
	callIndex = index;
	*(unsigned long*)(code + index) = 0;
	index += 4;

	//add esp n clean call args
	code[index++] = 0x83;
	code[index++] = 0xc4;
	code[index++] = static_cast<unsigned char>((functionArgNum + 1) * 4);
#endif

	// ret
	code[index++] = 0xc3;

	void* instance = Alloc(index);
	memcpy_s(instance, index, code, index);

#ifdef WIN64
#else
	unsigned char* p = (unsigned char*)instance;
	*(unsigned long*)(p + callIndex) = (unsigned long)function - (unsigned long)p - callIndex - 4;
#endif 

	return instance;
}