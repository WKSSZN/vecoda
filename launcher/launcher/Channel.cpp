#include "Channel.h"
#include <stdio.h>
#include <assert.h>

Channel::Channel()
{
    m_pipe = INVALID_HANDLE_VALUE;
    m_doneEvent = INVALID_HANDLE_VALUE;
    m_readEvent = INVALID_HANDLE_VALUE;
    m_creator = false;
    m_reading = false;
    m_nreadFinish = false;
    m_value = 0;
    m_threadHandle = INVALID_HANDLE_VALUE;
}

Channel::~Channel()
{
    Destroy();
}

bool Channel::Create(const char* name)
{
    char pipeName[256];
    _snprintf(pipeName, 256, "\\\\.\\pipe\\%s", name);

    DWORD bufferSize = 2048;

    m_pipe = CreateNamedPipeA(pipeName, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE, 1, bufferSize, bufferSize, 0, NULL);
    if (m_pipe != INVALID_HANDLE_VALUE)
    {
        // Remember that we're the creator of the pipe so we can properly
        // destroy it.
        m_creator = true;
    }
    else {
        LPVOID lpMsgBuf;
        DWORD dw = GetLastError();
        if (FormatMessage(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, dw, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), (LPTSTR)&lpMsgBuf, 0, NULL) == 0) {
            MessageBox(NULL, (LPCTSTR)lpMsgBuf, TEXT("Error"), MB_OK);

            LocalFree(lpMsgBuf);
        }
    }

    if (m_pipe != INVALID_HANDLE_VALUE)
    {
        m_doneEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
        m_readEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
    }

    return m_pipe != INVALID_HANDLE_VALUE;
}

bool Channel::Connect(const char* name)
{
    char pipeName[256];
    _snprintf(pipeName, 256, "\\\\.\\pipe\\%s", name);

    m_pipe = CreateFileA(pipeName, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);

    if (m_pipe != INVALID_HANDLE_VALUE)
    {
        m_doneEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
        m_readEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
        DWORD flags = PIPE_READMODE_MESSAGE;
        SetNamedPipeHandleState(m_pipe, &flags, NULL, NULL);
    }

    return m_pipe != INVALID_HANDLE_VALUE;
}

bool Channel::WaitForConnection()
{
    return ConnectNamedPipe(m_pipe, NULL) != FALSE;
}

void Channel::Destroy()
{
    if (m_creator)
    {
        FlushFileBuffers(m_pipe);
        DisconnectNamedPipe(m_pipe);
        m_creator = false;
    }

    if (m_doneEvent != INVALID_HANDLE_VALUE)
    {

        // Signal the done event so that if we're currently blocked reading,
        // we'll stop.

        SetEvent(m_doneEvent);

        CloseHandle(m_doneEvent);
        m_doneEvent = INVALID_HANDLE_VALUE;

    }

    if (m_readEvent != INVALID_HANDLE_VALUE)
    {
        CloseHandle(m_readEvent);
        m_readEvent = INVALID_HANDLE_VALUE;
    }

    if (m_pipe != INVALID_HANDLE_VALUE)
    {
        CloseHandle(m_pipe);
        m_pipe = INVALID_HANDLE_VALUE;
    }

    if (m_threadHandle != INVALID_HANDLE_VALUE) {
        WaitForSingleObject(m_threadHandle, INFINITE);
        CloseHandle(m_threadHandle);
        m_threadHandle = INVALID_HANDLE_VALUE;
    }

}

bool Channel::Write(const void* buffer, unsigned int length)
{

    assert(m_pipe != INVALID_HANDLE_VALUE);

    if (length == 0)
    {
        // Because of the way message pipes work, writing 0 is different than
        // writing nothing.
        return true;
    }

    OVERLAPPED overlapped = { 0 };
    overlapped.hEvent = m_readEvent;

    BOOL result = WriteFile(m_pipe, buffer, length, NULL, &overlapped) != 0;

    if (result == FALSE)
    {
        DWORD error = GetLastError();

        if (error == ERROR_IO_PENDING)
        {
            // Wait for the operation to complete so that we don't need to keep around
            // the buffer.
            WaitForSingleObject(m_readEvent, INFINITE);

            DWORD numBytesWritten = 0;

            if (GetOverlappedResult(m_pipe, &overlapped, &numBytesWritten, FALSE))
            {
                result = (numBytesWritten == length);
            }
        }
    }

    return result == TRUE;

}

bool Channel::NReadUInt32(unsigned int& value)
{
    assert(m_pipe != INVALID_HANDLE_VALUE);

    if (m_nreadFinish) {
        value = m_value;
        CloseHandle(m_threadHandle);
        m_nreadFinish = false;
        m_reading = false;
        m_threadHandle = INVALID_HANDLE_VALUE;
        return m_result;
    }
    if (!m_reading) {
        m_reading = true;
        m_threadHandle = CreateThread(NULL, 0, Channel::StaticNReadUInt32, this, 0, NULL);
    }
    value = 0;
    return false;
}

bool Channel::Read(void* buffer, unsigned int length)
{

    assert(m_pipe != INVALID_HANDLE_VALUE);

    if (length == 0)
    {
        // Because of the way message pipes work, reading 0 is different than
        // reading nothing.
        return true;
    }

    OVERLAPPED overlapped = { 0 };
    overlapped.hEvent = m_readEvent;

    DWORD numBytesRead;
    BOOL result = ReadFile(m_pipe, buffer, length, &numBytesRead, &overlapped);

    if (result == FALSE)
    {

        DWORD error = GetLastError();

        if (error == ERROR_IO_PENDING)
        {

            // Wait for the operation to complete.

            HANDLE events[] =
            {
                m_readEvent,
                m_doneEvent,
            };

            WaitForMultipleObjects(2, events, FALSE, INFINITE);

            if (WaitForSingleObject(m_doneEvent, 0) == WAIT_OBJECT_0)
            {
                // The pipe has been closed.
                result = FALSE;
            }
            else if (GetOverlappedResult(m_pipe, &overlapped, &numBytesRead, FALSE))
            {
                result = (numBytesRead == length);
            }

        }

    }

    return result == TRUE;

}

DWORD __stdcall Channel::StaticNReadUInt32(LPVOID param)
{
    Channel* self = (Channel*)param;
    self->ContinueNReadUInt32();
    return 0;
}

void Channel::ContinueNReadUInt32()
{
    OVERLAPPED overlapped = { 0 };
    overlapped.hEvent = m_readEvent;
    DWORD numBytesRead;
    BOOL result = ReadFile(m_pipe, &m_value, 4, &numBytesRead, &overlapped);
    if (result == FALSE)
    {

        DWORD error = GetLastError();

        if (error == ERROR_IO_PENDING)
        {

            // Wait for the operation to complete.

            HANDLE events[] =
            {
                m_readEvent,
                m_doneEvent,
            };

            WaitForMultipleObjects(2, events, FALSE, INFINITE);

            if (WaitForSingleObject(m_doneEvent, 0) == WAIT_OBJECT_0)
            {
                m_value = 0xffffffff;
                // The pipe has been closed.
                result = FALSE;
            }
            else if (GetOverlappedResult(m_pipe, &overlapped, &numBytesRead, FALSE))
            {
                result = (numBytesRead == 4);
            }
            else {
                m_value = 0xffffffff;
            }

        }
        else
        {
            m_value = 0xffffffff;
        }
    }
    m_nreadFinish = true;
    m_result = result;
}

void Channel::Flush()
{
    //FlushFileBuffers(m_pipe);
}
