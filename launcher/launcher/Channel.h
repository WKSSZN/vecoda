#pragma once
#include <Windows.h>
#include <string>

class Channel
{
public:
	Channel();
	virtual ~Channel();
	bool Create(const char* name);
	bool Connect(const char* name);
	bool WaitForConnection();
	void Destroy();
	bool WriteUInt32(unsigned int value);
	bool WriteUInt(size_t);
	bool WriteString(const char* value);
	bool WriteString(const std::string& value);
	bool WriteBool(bool value);
	bool ReadUInt32(unsigned int& value);
	bool ReadUInt(size_t&);
	bool ReadString(std::string& value);
	bool ReadBool(bool& value);
	bool NReadUInt32(unsigned int& value);
	void Flush();
private:
	bool Write(const void* buffer, unsigned int length);
	bool Read(void* buffer, unsigned int length);
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