#include "TcpChannel.h"

TcpChannel::TcpChannel() : m_socket(INVALID_SOCKET), m_connected(false), nreadCnt(0), nreadBuffer()
{
}

TcpChannel::~TcpChannel()
{
	Disconnect();
	WSACleanup();
}

bool TcpChannel::Connect(const char* serverIP, int port)
{
	WSADATA wsaData;
	if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0)
	{
		return false;
	}

	if (m_connected)
	{
		Disconnect();
	}

	m_socket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (m_socket == INVALID_SOCKET)
	{
		return false;
	}

	sockaddr_in serverAddr;
	serverAddr.sin_family = AF_INET;
	serverAddr.sin_port = htons(port);

	if (inet_pton(AF_INET, serverIP, &serverAddr.sin_addr) != 1)
	{
		hostent* host = gethostbyname(serverIP);
		if (host == nullptr)
		{
			closesocket(m_socket);
			m_socket = INVALID_SOCKET;
			return false;
		}
		serverAddr.sin_addr = *reinterpret_cast<in_addr*>(host->h_addr);
	}

	unsigned long nonblock = 1;
	if (ioctlsocket(m_socket, FIONBIO, &nonblock) == SOCKET_ERROR)
	{
		closesocket(m_socket);
		m_socket = INVALID_SOCKET;
		return false;
	}

	if (connect(m_socket, (sockaddr*)&serverAddr, sizeof(serverAddr)) == SOCKET_ERROR)
	{
		int error = WSAGetLastError();
		if (error != WSAEWOULDBLOCK)
		{
			closesocket(m_socket);
			m_socket = INVALID_SOCKET;
			return false;
		}

		fd_set writefds, exceptfds;
		FD_ZERO(&writefds);
		FD_ZERO(&exceptfds);
		FD_SET(m_socket, &writefds);
		FD_SET(m_socket, &exceptfds);

		timeval timeout;
		timeout.tv_sec = 20l;
		timeout.tv_usec = 0;

		int result = select(0, NULL, &writefds, &exceptfds, &timeout);
		if (result == 0 || result == SOCKET_ERROR || FD_ISSET(m_socket, &exceptfds))
		{
			closesocket(m_socket);
			m_socket = INVALID_SOCKET;
			return false;
		}
	}

	nonblock = 0;
	ioctlsocket(m_socket, FIONBIO, &nonblock);

	m_connected = true;
	return true;
}

void TcpChannel::Disconnect()
{
	if (m_socket != INVALID_SOCKET)
	{
		closesocket(m_socket);
		m_socket = INVALID_SOCKET;
		m_connected = false;
	}
}

bool TcpChannel::Write(const void* buffer, unsigned int length)
{
	if (!m_connected)
	{
		return false;
	}

	const char* data = static_cast<const char*>(buffer);
	unsigned int totalSent = 0;

	while (totalSent < length)
	{
		int sent = send(m_socket, data + totalSent, length - totalSent, 0);
		if (sent == SOCKET_ERROR)
		{
			Disconnect();
			return false;
		}
		totalSent += sent;
	}
	return true;
}

bool TcpChannel::Read(void* buffer, unsigned int length)
{
	if (!m_connected)
	{
		return false;
	}

	char* data = static_cast<char*>(buffer);
	unsigned int totalReceived = 0;

	while (totalReceived < length)
	{
		int received = recv(m_socket, data + totalReceived, length - totalReceived, 0);
		if (received == SOCKET_ERROR)
		{
			Disconnect();
			return false;
		}
		if (received == 0)
		{
			Disconnect();
			return false;
		}
		totalReceived += received;
	}
	return true;
}

bool TcpChannel::NReadUInt32(unsigned int& value)
{
	if (!m_connected)
	{
		value = 0xffffffff;
		return false;
	}

	u_long originalMode = 0;
	ioctlsocket(m_socket, FIONBIO, &originalMode);

	u_long nonBlocking = 1;
	ioctlsocket(m_socket, FIONBIO, &nonBlocking);

	bool success = false;
	
	int received = recv(m_socket, nreadBuffer + nreadCnt, 4 - nreadCnt, 0);
	if (received + nreadCnt == 4)
	{
		value = *reinterpret_cast<unsigned int*>(nreadBuffer);
		nreadCnt = 0;
		success = true;
	}
	else if (received == SOCKET_ERROR)
	{
		int error = WSAGetLastError();
		if (error != WSAEWOULDBLOCK)
		{
			Disconnect();
			value = 0xffffffff;
		}
	}
	else if (received == 0)
	{
		value = 0xffffffff;
		Disconnect();
	}
	else
	{
		nreadCnt += received;
	}
	ioctlsocket(m_socket, FIONBIO, &originalMode);
	return success;
}