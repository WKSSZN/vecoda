#pragma once
#include <string>

class ReadWrite {
public:
	virtual ~ReadWrite() = default;
	bool WriteUInt32(unsigned int value);
	bool WriteUInt(uint64_t value);
	bool WriteString(const char* value);
	bool WriteString(const std::string & value);
	bool WriteBool(bool value);
	bool ReadUInt32(unsigned int& value);
	bool ReadUInt(uint64_t& value);
	bool ReadString(std::string& value);
	bool ReadBool(bool& value);
	virtual bool NReadUInt32(unsigned int& value) = 0;
	inline void SetPointerSize(size_t size) { m_size = size; }
	inline size_t GetPointerSize() const { return m_size; }
protected:
	virtual bool Write(const void* buffer, unsigned int length) = 0;
	virtual bool Read(void* buffer, unsigned int length) = 0;
private:
	size_t m_size = 4;
};