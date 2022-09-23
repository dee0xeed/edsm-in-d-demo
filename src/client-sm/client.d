
import std.stdio;
import std.format;
import core.stdc.string : memcpy, strerror;
import std.string : fromStringz;

import edsm, pool, ioctx, esrc, disp;

class WrkMachine : StageMachine {

    enum ulong M0_CONN = 0;
    enum ulong M0_SEND = 0;
    enum ulong M0_RECV = 0;
    enum ulong M0_TWIX = 0;
    enum ulong M3_WAIT = 3;
    enum ulong M1_WORK = 1;
    private static int number = -1;

    string host, port;
    ClientSocket sk;
    Timer tm;
    IoContext ioCtx;
    RestRoom rxRestRoom, txRestRoom;
    int myNumber;

    bool myNeedMore(ubyte[] buf, uint cnt) {
        if (0x0A == buf[cnt - 1])
            return false;
        return true;
    }

    this(MessageDispatcher md, RestRoom rxrR, RestRoom txrR, string host, string port) {

        this.host = host;
        this.port = port;
        myNumber = ++number;
        super(md, format("CLIENT-%d", myNumber));
        rxRestRoom = rxrR;
        txRestRoom = txrR;

        ioCtx = new IoContext(1024);
        ioCtx.needMore = &myNeedMore;
        ioCtx.rxTimeOut = 10000;

        Stage init, conn, send, recv, twix, wait;
        init = addStage("INIT", &clientInitEnter);
        conn = addStage("CONN", &clientConnEnter);
        send = addStage("SEND", &clientSendEnter);
        recv = addStage("RECV", &clientRecvEnter);
        twix = addStage("TWIX", &clientTwixEnter);
        wait = addStage("WAIT", &clientWaitEnter);

        init.addReflex("M0", conn);

        conn.addReflex("M1", &clientConnM1);
        conn.addReflex("M2", &clientConnM2);
        conn.addReflex("M0", send);
        conn.addReflex("M3", wait);

        send.addReflex("M1", &clientSendM1);
        send.addReflex("M2", &clientSendM2);
        send.addReflex("M0", recv);
        send.addReflex("M3", wait);

        recv.addReflex("M1", &clientRecvM1);
        recv.addReflex("M2", &clientRecvM2);
        recv.addReflex("M0", twix);
        recv.addReflex("M3", wait);

        twix.addReflex("T0", send);
        wait.addReflex("T0", conn);
    }

    void clientInitEnter() {
        tm = newTimer();
        sk = newClientSocket(host, port);
        msgTo(this, M0_CONN);
    }

    void clientConnEnter() {
        sk.getId();
        ioCtx.fd = sk.id;
        sk.startConnect();
        StageMachine txSm = txRestRoom.get();
        ioCtx.cnt = 0;
        msgTo(txSm, M1_WORK, ioCtx);
    }

    /* message from tx machine, connection succeded */
    void clientConnM1(StageMachine src, Object o) {
        writefln("%s: connected to '%s:%s'", name, sk.host, sk.port);
        msgTo(this, M0_SEND);
    }

    /* message from tx machine, connection failed */
    void clientConnM2(StageMachine src, Object o) {
        int e = sk.getError();
        writefln("%s: connection to '%s:%s' failed (%s)", name, sk.host, sk.port, fromStringz(strerror(e)));
        msgTo(this, M3_WAIT);
    }

    void clientSendEnter() {
        static ulong seqn;
        StageMachine txSm = txRestRoom.get();
        string request = format("%s-%d\n", name, seqn++);
        //ioCtx.buf[] = cast(ubyte[])request.dup;
        ioCtx.cnt = cast(uint)request.length;
        memcpy(ioCtx.buf.ptr, request.ptr, ioCtx.cnt);
        msgTo(txSm, M1_WORK, ioCtx);
    }

    void clientSendM1(StageMachine src, Object o) {
        msgTo(this, M0_RECV);
    }

    void clientSendM2(StageMachine src, Object o) {
        msgTo(this, M3_WAIT);
    }

    void clientRecvEnter() {
        StageMachine rxSm = rxRestRoom.get();
        msgTo(rxSm, M1_WORK, ioCtx);
    }

    /* message from rx machine, success */
    void clientRecvM1(StageMachine src, Object o) {
        char[] reply = cast(char[])ioCtx.buf[0 .. ioCtx.cnt - 1];
        writefln("___CHECK, %s: got '%s' from server", name, reply);
        msgTo(this, M0_TWIX);
    }

    /* message from rx machine, failure */
    void clientRecvM2(StageMachine src, Object o) {
        msgTo(this, M3_WAIT);
    }

    /* 'Have a break, have a KitKat' :) */
    void clientTwixEnter() {
        tm.start(300);
    }

    void clientWaitEnter() {
        sk.putId();
        tm.start(5000);
    }
}
