#pragma once
#include <Windows.h>
#include <string>
#include "ReadWrite.h"

class Channel : public ReadWrite
{
public:
	Channel();
	virtual ~Channel();
	bool Create(const char* name);
	bool Connect(const char* name);
	bool WaitForConnection();
	void Destroy();
	virtual bool NReadUInt32(unsigned int& value);
	void Flush();
protected:
	virtual bool Write(const void* buffer, unsigned int length);
	virtual bool Read(void* buffer, unsigned int length);
private:
	HANDLE m_pipe;
	HANDLE m_doneEvent;
	HANDLE m_readEvent;
	bool m_reading;
	bool m_creator;
	bool m_nreadFinish;
	bool m_result;
	unsigned int m_value;
	HANDLE m_threadHandle;

private:
	static DWORD WINAPI StaticNReadUInt32(LPVOID param);
	void ContinueNReadUInt32();
};