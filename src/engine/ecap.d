
/*
1) timers and signals
   * Linux - are fds, have to be read
   * FreeBSD - are not fds
2) adding existing event source to set
   * Linux - error EEXIST
   * FreeBSD - ok
3) timefd_settime() in Linux
4) bytes avail for EPOLLIN/EVFLT_READ
   * Linux - ioctl(FIONREAD)
   * FreeBSD - returned with event
5) events representation
   * Linux - bitmask, including ERR/HUP
   * FreeBSD - number (called 'filter'), ERR/EOF separately in flags
*/

import std.stdio;
import std.format;
import std.string;
import core.sys.posix.unistd;
import core.stdc.errno;
import core.stdc.string;

import msgq, esrc;

enum ulong D0 = 0; /* data available, read() will not block */
enum ulong D1 = 1; /* write() will not block */
enum ulong D2 = 2; /* error */
enum ulong L0 = 0; /* incoming connection, accept() will not block */

interface IEventQueue {

    bool wait();

    /* signals */
    int signalId(int signo);
    void enableSignal(Signal sg);
    void disableSignal(Signal sg);

    /* timers */
    int timerId();
    void enableTimer(Timer tm, uint msec);
    void disableTimer(Timer tm);

    /* i/o */
    void enableCanRead(Io io);
    void enableCanWrite(Io io);
    void disableIo(Io io);

    /* listening socket */
    void enableCanAccept(TCPListener tcpa);
    void disableCanAccept(TCPListener tcpa);

    /* file system */
}

abstract class AEventQueue {

    private int id;
    private bool done;
    private MessageQueue mq;

    this(MessageQueue mq) {
        this.mq = mq;
    }

    ~this() {
        close(id);
    }

    void stop() {
        done = true;
    }
}

version(linux) {

import core.sys.linux.epoll;
import core.sys.linux.sys.signalfd;
import core.sys.linux.timerfd;
import core.sys.posix.sys.ioctl;

align (1) struct EpollEvent {
    align(1):
    uint event_mask;
    EventSource es;
    /* just do not want to use that union, epoll_data_t */
}
static assert(EpollEvent.sizeof == 12);

extern (C) {
    int epoll_ctl(int epfd, int op, int fd, EpollEvent *desiredEvents);
    int epoll_wait(int epfd, EpollEvent *events, int maxEvents, int timeout);
}

final class EventQueue : AEventQueue, IEventQueue {

    enum uint ePollIn = EPOLLIN;
    enum uint ePollOut = EPOLLOUT;
    enum uint ePollErr = EPOLLERR;
    enum uint ePollHup = EPOLLHUP;
    enum uint ePollRdHup = EPOLLRDHUP;

    this(MessageQueue mq) {
        super(mq);
        id = epoll_create1(0);
        assert(id > 0, format("epoll_create1() : %s", fromStringz(strerror(errno))));
    }

    private void _enableEventSource(EventSource es, bool forCanWrite = false) {

        uint em = forCanWrite ? EPOLLOUT : EPOLLIN;
        em |= EPOLLONESHOT;
        auto e = EpollEvent(em, es);
        int r = epoll_ctl(id, EPOLL_CTL_ADD, es.id, &e);
        if (-1 == r) {
            auto err = errno();
            assert(err == EEXIST, format("epoll_ctl(ADD) : %s", fromStringz(strerror(err))));
            r = epoll_ctl(id, EPOLL_CTL_MOD, es.id, &e);
            assert(r == 0, format("epoll_ctl(MOD) : %s", fromStringz(strerror(errno))));
        }
    }

    private void _disableEventSource(EventSource es) {
        auto e = EpollEvent(0, es);
        int r = epoll_ctl(id, EPOLL_CTL_MOD, es.id, &e);
        assert(r == 0, format("epoll_ctl(MOD) : %s", fromStringz(strerror(errno))));
    }

    int timerId() {
        int id = timerfd_create(CLOCK_REALTIME, 0);
        assert(id > 0, format("timerfd_create() : %s", fromStringz(strerror(errno))));
        return id;
    }

    private void _setTimer(int fd, uint msec) {

        itimerspec t;

        /* first expiration */
        t.it_value.tv_sec = msec / 1000;
        t.it_value.tv_nsec = (msec % 1000) * 1000 * 1000;

        /* period is zero, oneshot */
//        t.it_interval.tv_sec = 0;
//        t.it_interval.tv_nsec = 0;

        int r = timerfd_settime(fd, 0, &t, null);
        assert(r == 0, format("timerfd_settime(%d): %s", id, fromStringz(strerror(errno))));
    }

    void enableTimer(Timer tm, uint msec) {
        _setTimer(tm.id, msec);
        _enableEventSource(tm);
    }

    void disableTimer(Timer tm) {
        _disableEventSource(tm);
        _setTimer(tm.id, 0);
    }

    int signalId(int signo) {
        sigset_t sset;
        sigemptyset(&sset);
        sigaddset(&sset, signo);
        int id = signalfd(-1, &sset, SFD_CLOEXEC);
        assert(id > 0, format("signalfd(%d) : %s", signo, fromStringz(strerror(errno))));
        return id;
    }

    void enableSignal(Signal sg) {
        _enableEventSource(sg);
    }

    void disableSignal(Signal sg) {
        _disableEventSource(sg);
    }

    void enableCanRead(Io io) {
        _enableEventSource(io, false);
    }

    void enableCanWrite(Io io) {
        _enableEventSource(io, true);
    }

    void disableIo(Io io) {
        _disableEventSource(io);
    }

    void enableCanAccept(TCPListener tcpa) {
        _enableEventSource(tcpa, false);
    }

    void disableCanAccept(TCPListener tcpa) {
        _disableEventSource(tcpa);
    }

    private void _readTimerInfo(Timer tm) {
        size_t r = read(tm.id, &tm.nexp, tm.nexp.sizeof);
        assert(r == tm.nexp.sizeof, "read(timerfd) failed");
        if (tm.nexp > 1)
            writefln("WRN: timer-%d overrun! (number of expirations = %d)", tm.number, tm.nexp);
    }

    private void _readSignalInfo(Signal sg) {
        signalfd_siginfo si;
        size_t r = read(sg.id, &si, si.sizeof);
        assert(r == si.sizeof, "read(sigfd) failed");
        // sg.pid = ... etc ...
    }

    private ulong _getEventInfo(uint em, EventSource es) {

        if (em & (EventQueue.ePollErr | EventQueue.ePollHup | EventQueue.ePollRdHup))
            return D2;

        final switch (es.tag) {

        /* i/o channel */
        case 'D':
            if (em & EventQueue.ePollIn) {
                int ba;
                int r = ioctl(es.id, FIONREAD, &ba);
                assert(r == 0, format("ioctl(%d): %s", es.id, fromStringz(strerror(errno))));
                Io io = cast(Io)es;
                io._bytesAvail = ba;
                return D0;
            }
            if (em & EventQueue.ePollOut)
                return D1;
        break;

        /* listening socket */
        case 'L':
            return L0;

        /* timer */
        case 'T':
            Timer tm = cast(Timer)es;
            _readTimerInfo(tm);
            return tm.number;

        /* signal */
        case 'S':
            Signal sg = cast(Signal)es;
            _readSignalInfo(sg);
            return sg.number;

        /* file system */
//        case 'F':
//          return ...;
        }
        assert(false, format("illegal event source tag '%c'", es.tag));
    }

    bool wait() {

        const int maxEvents = 8;
        EpollEvent[maxEvents] events;

        if (done)
            return false;

        int n = epoll_wait(id, events.ptr, maxEvents, -1);
        if (-1 == n) {
            writefln("epoll_wait(): %s", fromStringz(strerror(errno)));
            return false;
        }

        foreach (k; 0 .. n) {
            EventSource s = events[k].es;
            ulong ecode = _getEventInfo(events[k].event_mask, s);
            //mq.putMsg(null, s.owner, ecode, s);
            mq ~= Message(null, s.owner, ecode, s);
        }

        return true;
    }
}} /* version(linux) */

version(FreeBSD) {

/* see
 * https://forum.dlang.org/thread/igvuvampctdfmlidgxwq@forum.dlang.org
 * https://issues.dlang.org/show_bug.cgi?id=22615
 */

import core.sys.freebsd.config;
import core.sys.freebsd.sys.event;

final class EventQueue : AEventQueue, IEventQueue {

    this(MessageQueue mq) {
        super(mq);
        id = kqueue();
        assert(id > 0, format("kqueue() failed : %s", fromStringz(strerror(errno))));
        writefln("### FreeBSD_version = %s", __FreeBSD_version);
        writefln("### sizeof(kevent_t) = %s", kevent_t.sizeof);
    }

    private void _enableEvent(short filter, EventSource es, ulong data) {

        kevent_t ke;
        // EV_SET(&ke, es.id, filter, EV_ADD | EV_ENABLE | EV_DISPATCH, 0, data, cast(void*)es, [0, 0, 0, 0]);
        EV_SET(&ke, es.id, filter, EV_ADD | EV_ENABLE | EV_DISPATCH, 0, data, cast(void*)es);
        int r = kevent(id, &ke, 1, null, 0, null);
        assert(r != -1, format("kevent(ENABLE) : %s", fromStringz(strerror(errno))));
    }

    private void _disableEvent(short filter, EventSource es) {
        kevent_t ke;
        // EV_SET(&ke, es.id, filter, EV_DISABLE, 0, 0, cast(void*)es, [0, 0, 0, 0]);
        EV_SET(&ke, es.id, filter, EV_DISABLE, 0, 0, cast(void*)es);
        int r = kevent(id, &ke, 1, null, 0, null);
        assert(r != -1, format("kevent(DISABLE) : %s", fromStringz(strerror(errno))));
    }

    int timerId() {
        static int tid = 0;
        return tid++;
    }

    void enableTimer(Timer tm, uint msec) {
        _enableEvent(EVFILT_TIMER, tm, msec);
    }

    void disableTimer(Timer tm) {
        _disableEvent(EVFILT_TIMER, tm);
    }

    int signalId(int signo) {
        return signo;
    }

    void enableSignal(Signal sg) {
        _enableEvent(EVFILT_SIGNAL, sg, 0);
    }

    void disableSignal(Signal sg) {
        _disableEvent(EVFILT_SIGNAL, sg);
    }

    void enableCanRead(Io io) {
        _enableEvent(EVFILT_READ, io, 0);
    }

    void enableCanWrite(Io io) {
        _enableEvent(EVFILT_WRITE, io, 0);
    }

    void disableIo(Io io) {
        _disableEvent(EVFILT_READ, io);
        _disableEvent(EVFILT_WRITE, io);
    }

    void enableCanAccept(TCPListener tcpa) {
        _enableEvent(EVFILT_READ, tcpa, 0);
    }

    void disableCanAccept(TCPListener tcpa) {
        _disableEvent(EVFILT_READ, tcpa);
    }

    private ulong _getEventInfo(ref kevent_t ke, EventSource es) {

        if (ke.flags & (EV_ERROR | EV_EOF))
            return D2;

        final switch (es.tag) {

        /* i/o channel */
        case 'D':
            if (EVFILT_READ == ke.filter) {
                Io io = cast(Io)es;
                io._bytesAvail = ke.data;
                return D0;
            }
            if (EVFILT_WRITE == ke.filter)
                return D1;
        break;

        /* listening socket */
        case 'L':
            return L0;

        /* timer */
        case 'T':
            Timer tm = cast(Timer)es;
            tm.nexp = ke.data;
            return tm.number;

        /* signal */
        case 'S':
            Signal sg = cast(Signal)es;
            // _readSignalInfo(sg);
            return sg.number;

        /* file system */
//        case 'F':
//          return ...;
        }
        assert(false, format("%s() - unexpected filter %d", __FUNCTION__, ke.filter));
    }

    private int kqueue_wait(kevent_t *earr, int len) {
        int n;
        n = kevent(id, null, 0, earr, len, null);
        if (-1 == n)
            writefln("kevent(): %s", fromStringz(strerror(errno)));
        return n;
    }

    bool wait() {

        const int maxEvents = 8;
        kevent_t[maxEvents] events;

        if (done)
            return false;

        int n = kqueue_wait(events.ptr, maxEvents);
        if (-1 == n)
            return false;

        foreach (k; 0 .. n) {
            EventSource s = cast(EventSource)events[k].udata;
            ulong ecode = _getEventInfo(events[k], s);
            mq ~= Message(null, s.owner, ecode, s);
        }

        return true;
    }

}} /* version(FreeBSD) */
