
import std.stdio;
import std.format;
import std.string;

import edsm, pool, ioctx, esrc, disp;
import rx, tx;

/* SMD

$init
$idle
$getp
$ackp

+init M0 idle

@idle M1
+idle M0 getp

@getp M1
@getp M2
+getp M0 ackp
+getp M3 idle

@ackp M1
@ackp M2
+ackp M0 getp
+ackp M3 idle

*/

class WorkerSm : StageMachine {

    enum ulong M0_IDLE = 0;
    enum ulong M0_GETP = 0;
    enum ulong M0_ACKP = 0;
    enum ulong M3_IDLE = 3;
    enum ulong M0_GONE = 0;
    enum ulong M1_WORK = 1;
    private static int number = -1;

    StageMachine listener;
    Client client;
    IoContext ioCtx;
    RestRoom myRestRoom, rxRestRoom, txRestRoom;

    bool myNeedMore(ubyte[] buf, uint cnt) {
        if (0x0A == buf[cnt - 1])
            return false;
        return true;
    }

    this(MessageDispatcher md, RestRoom myrR, RestRoom rxrR, RestRoom txrR) {

        super(md, format("WORKER-%d", ++number));
        myRestRoom = myrR;
        rxRestRoom = rxrR;
        txRestRoom = txrR;

        ioCtx = new IoContext(1024);
        ioCtx.needMore = &myNeedMore;
        ioCtx.rxTimeOut = 10000;

        Stage init, idle, getp, ackp;
        init = addStage("INIT", &workerInitEnter);
        idle = addStage("IDLE", &workerIdleEnter);
        getp = addStage("GETP", &workerGetpEnter);
        ackp = addStage("ACKP", &workerAckpEnter);

        init.addReflex("M0", idle);

        idle.addReflex("M1", &workerIdleM1);
        idle.addReflex("M0", getp);

        getp.addReflex("M1", &workerGetpM1);
        getp.addReflex("M2", &workerGetpM2);
        getp.addReflex("M0", ackp);
        getp.addReflex("M3", idle);

        ackp.addReflex("M1", &workerAckpM1);
        ackp.addReflex("M2", &workerAckpM2);
        ackp.addReflex("M0", getp);
        ackp.addReflex("M3", idle);
    }

    void workerInitEnter() {
        msgTo(this, M0_IDLE);
    }

    void workerIdleEnter() {
        myRestRoom.put(this);
    }

    /* message from listener */
    void workerIdleM1(StageMachine src, Object o) {
        listener = src;
        client = cast(Client)o;
        ioCtx.fd = client.fd;
        msgTo(this, M0_GETP);
    }

    void workerGetpEnter() {
        StageMachine rxSm = rxRestRoom.get();
        msgTo(rxSm, M1_WORK, ioCtx);
    }

    /* message from rx machine, success */
    void workerGetpM1(StageMachine src, Object o) {
        char[] s = cast(char[])ioCtx.buf[0 .. $];
        writefln("got '%s' from '%s:%d'", s.strip("\n\x00"), client.addr, client.port);
        msgTo(this, M0_ACKP);
    }

    /* message from rx machine, failure */
    void workerGetpM2(StageMachine src, Object o) {
        msgTo(this, M3_IDLE);
        msgTo(listener, M0_GONE, client);
    }

    void workerAckpEnter() {
        StageMachine txSm = txRestRoom.get();
        msgTo(txSm, M1_WORK, ioCtx);
    }

    /* message from tx machine, success */
    void workerAckpM1(StageMachine src, Object o) {
        msgTo(this, M0_GETP);
    }

    /* message from tx machine, failure */
    void workerAckpM2(StageMachine src, Object o) {
        msgTo(this, M3_IDLE);
        msgTo(listener, M0_GONE, client);
    }
}
