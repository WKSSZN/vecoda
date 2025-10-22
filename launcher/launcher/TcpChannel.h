#pragma once
#define _WINSOCK_DEPRECATED_NO_WARNINGS
#include <WS2tcpip.h>
#include "ReadWrite.h"

class TcpChannelDelegate;
class TcpChannel :
    public ReadWrite
{
public:
    virtual ~TcpChannel();
    TcpChannel();

    bool Connect(const char* serverIP, int port);
    void Disconnect();
    virtual bool NReadUInt32(unsigned int& value);
protected:
    virtual bool Write(const void* buffer, unsigned int length);
    virtual bool Read(void* buffer, unsigned int length);
private:
    SOCKET m_socket;
    bool m_connected;
    char nreadBuffer[4];
    int nreadCnt;
    friend class TcpChannelDelegate;
};