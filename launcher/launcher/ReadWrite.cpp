#include "ReadWrite.h"
#include <string.h>

bool ReadWrite::WriteUInt32(unsigned int value)
{
	unsigned int temp = value;
	return Write(&value, 4);
}
bool ReadWrite::WriteUInt(uint64_t value)
{
	uint64_t temp = value;
	return Write(&temp, static_cast<unsigned int>(m_size));
}
bool ReadWrite::WriteString(const char* value)
{
	unsigned int length = static_cast<unsigned int>(strlen(value));
	if (!WriteUInt32(length))
	{
		return false;
	}
	if (length > 0)
	{
		return Write(value, length);
	}
	return true;
}
bool ReadWrite::WriteString(const std::string& value)
{
	unsigned int length = static_cast<unsigned int>(value.length());
	if (!WriteUInt32(length))
	{
		return false;
	}
	if (length > 0)
	{
		return Write(value.c_str(), length);
	}
	return true;
}
bool ReadWrite::WriteBool(bool value)
{
	return WriteUInt32(value ? 1 : 0);
}
bool ReadWrite::ReadUInt32(unsigned int& value)
{
	unsigned int temp;
	if (!Read(&temp, 4))
	{
		value = 0;
		return false;
	}
	value = temp;
	return true;
}
bool ReadWrite::ReadUInt(uint64_t& value)
{
	uint64_t temp = 0;
	if (!Read(&temp, static_cast<unsigned int>(m_size)))
	{
		value = 0;
		return false;
	}
	value = temp;
	return true;
}
bool ReadWrite::ReadString(std::string& value)
{
	unsigned int length;

	if (!ReadUInt32(length))
	{
		return false;
	}

	if (length != 0)
	{

		char* buffer = new char[(size_t)length + 1];

		if (!Read(buffer, length))
		{
			delete[] buffer;
			return false;
		}

		buffer[length] = 0;
		value = buffer;

		delete[] buffer;

	}
	else
	{
		value.clear();
	}

	return true;
}
bool ReadWrite::ReadBool(bool& value)
{
	unsigned int temp;

	if (ReadUInt32(temp))
	{
		value = temp != 0;
		return true;
	}

	return false;
}