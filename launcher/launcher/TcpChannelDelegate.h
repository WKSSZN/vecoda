#ifndef TCP_CHANNEL_DELEGATE_H_
#define TCP_CHANNEL_DELEGATE_H_
#include "ReadWrite.h"
#include "TcpChannel.h"
#include <memory>

class TcpChannelDelegate :
    public ReadWrite
{
public:
    TcpChannelDelegate(const std::shared_ptr<TcpChannel>& channel)
    {
        this->channel = channel;
        this->SetPointerSize(channel->GetPointerSize());
    }
    virtual bool NReadUInt32(unsigned int& value)
    {
        return channel->NReadUInt32(value);
    }
    virtual ~TcpChannelDelegate()
    {

    }
protected:
    virtual bool Write(const void* buffer, unsigned int length)
    {
        return channel->Write(buffer, length);
    }
    virtual bool Read(void* buffer, unsigned int length)
    {
        return channel->Read(buffer, length);
    }
private:
    std::shared_ptr<TcpChannel> channel;
};

#endif