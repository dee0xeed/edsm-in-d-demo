
import std.stdio;
import std.format;
import std.string;

import core.sys.posix.signal;
import core.sys.posix.unistd;
import core.sys.posix.sys.ioctl;
import core.stdc.errno;
import core.stdc.string;

import ecap, edsm;

interface IEventSource {
    void enable();
    void disable();
}

abstract class EventSource {

    int id;                 /* fd (usually, but not always :( ) */
    char tag;               /* 'D', 'T', 'S', 'L' etc */
    StageMachine owner;
    EventQueue eq;

    this(EventQueue eq, char tag) {
        this.tag = tag;
        this.eq = eq;
    }

    ~this() {
       // close(id), if is fd...
       // writefln("   !!! %s() : %s (owner %s, fd = %d) this @ 0x%x", __FUNCTION__, this, owner.name, id, cast(void*)this);
    }
}

/* for timers and signals */
abstract class NumberedEventSource : EventSource {
    ulong number;

    this(EventQueue eq, char tag, ulong number) {
        super(eq, tag);
        this.number = number;
    }
}

final class Signal : NumberedEventSource, IEventSource {

    enum int sigInt = SIGINT;
    enum int sigTerm = SIGTERM;

    this(EventQueue eq, int signo, ulong n) {
        super(eq, 'S', n);

        sigset_t sset;

        /* block the signal */
        sigemptyset(&sset);
        sigaddset(&sset, signo);
        sigprocmask(SIG_BLOCK, &sset, null);

        id = eq.signalId(signo);
    }

    void enable() {
        eq.enableSignal(this);
    }

    void disable() {
        eq.disableSignal(this);
    }
}

final class Timer : NumberedEventSource {

    ulong nexp; /* >1 => overrun */

    this(EventQueue eq, ulong n) {
        super(eq, 'T', n);
        id = eq.timerId();
    }

    void start(uint interval_ms) {
        eq.enableTimer(this, interval_ms);
    }

    void stop() {
        eq.disableTimer(this);
    }
}

class Io : EventSource {

    long _bytesAvail;

    this(EventQueue eq) {
        super(eq, 'D');
        id = -1;
    }

    this(EventQueue eq, int fd) {
        super(eq, 'D');
        id = fd;
    }
/*
    this(string serDev, int baudRate, string param = "8N1") {
        // TODO
        // int fd = open(serDev, ...);
        // setup...
        // this(fd);
    }
*/
    long bytesAvail() {
        return _bytesAvail;
    }

    void enableCanRead() {
        eq.enableCanRead(this);
    }

    void enableCanWrite() {
        eq.enableCanWrite(this);
    }
}

final class ClientSocket : Io {

    import core.sys.posix.sys.socket;
    import core.sys.posix.netinet.in_;
    import core.sys.posix.netdb;
    import core.stdc.string;
    import core.sys.posix.fcntl;

    string host;
    string port;
    addrinfo hints;
    addrinfo *ai;

    this(EventQueue eq, string host, string port) {
        super(eq);
        this.host = host;
        this.port = port;
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
    }

    void getId() {
        int err = getaddrinfo(toStringz(host), toStringz(port), &hints, &ai);
        assert(0 == err, format("getaddrinfo('%s:%s'): %s", host, port, fromStringz(gai_strerror(err))));
        id = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol);
        assert(id > 0, format("socket() failed"));
    }

    void startConnect() {

        int flags = fcntl(id, F_GETFL);
        flags |= O_NONBLOCK;
        fcntl(id, F_SETFL, flags);

        int r = connect(id, ai.ai_addr, ai.ai_addrlen);
        if (-1 == r) {
            auto e = errno();
            assert(e == EINPROGRESS, format("connect(): %s", fromStringz(strerror(e))));
        }
    }

    bool connOk() {
        /*
        tcp_info tcpi; // linux specific, see /usr/include/linux/tcp.h
        socklen_t tcpi_len = tcpi.sizeof;

        getsockopt(id, SOL_TCP, TCP_INFO, &tcpi, &tcpi_len);
        if (tcpi.tcpi_state != TCP_ESTABLISHED)
            return false;
        */
        return true; // TODO
    }

    void putId() {
        freeaddrinfo(ai);
        close(id);
    }

    int getError() {
        int e;
        socklen_t optlen = e.sizeof;
        getsockopt(id, SOL_SOCKET, SO_ERROR, &e, &optlen);
        return e;
    }
}

class Client {
    int fd;
    string addr;
    ushort port;

    this(int fd, string addr, ushort port) {
        this.fd = fd;
        this.addr = addr;
        this.port = port;
    }

    ~this() {
        close(fd);
    }
}

final class TCPListener : EventSource, IEventSource {

    import core.sys.posix.sys.socket;
    import core.sys.posix.netinet.in_;
    import core.stdc.string;

    this(EventQueue eq, ushort port) {
        super(eq, 'L');
        int sk = socket(AF_INET, SOCK_STREAM, 0);
        assert(sk > 0, format("socket(): %s", fromStringz(strerror(errno))));
        int on = 1;
        setsockopt(sk, SOL_SOCKET, SO_REUSEADDR, &on, on.sizeof);

        sockaddr_in myAddr;
        myAddr.sin_family = AF_INET;
        myAddr.sin_port = htons(port);
        bind(sk, cast(sockaddr*)&myAddr, myAddr.sizeof);
        listen(sk, 128);
        id = sk;
    }

    void enable() {
        eq.enableCanAccept(this);
    }

    void disable() {
        eq.disableCanAccept(this);
    }

    Client acceptClient() {
        sockaddr_in peerAddr;
        socklen_t addrLength = peerAddr.sizeof;
        char[32] addr;
        int sk = accept(id, cast(sockaddr*)&peerAddr, &addrLength);
        assert(sk > 0, format("accept(): %s", fromStringz(strerror(errno))));
        inet_ntop(AF_INET, &peerAddr.sin_addr, addr.ptr, cast(uint)addr.length);
        return new Client(sk, addr[0 .. strlen(addr.ptr)].idup, peerAddr.sin_port);
    }
}
