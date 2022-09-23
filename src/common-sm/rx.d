
import std.stdio;
import std.format;
import core.sys.posix.unistd;
import core.stdc.errno;

import edsm, pool, ioctx, esrc, disp;

/* SMD
T180000

$init
$idle
$work

+init M0 idle

@idle M1
+idle M0 work

@work D0
@work D2
@work T0
@work M2
+work M0 idle
*/

class RxSm : StageMachine {

    enum ulong M0_IDLE = 0;
    enum ulong M0_WORK = 0;
    enum ulong M1_DONE = 1;
    enum ulong M2_FAIL = 2;

    private static int number = -1;
    StageMachine client;
    RestRoom rR;
    IoContext ctx;

    Io io;
    Timer tm;

    private void done(ulong mcodeForClient) {
        msgTo(this, M0_IDLE);
        msgTo(client, mcodeForClient);
    }

    this(MessageDispatcher md, RestRoom rR) {
        super(md, format("RX-%d", ++number));
        this.rR = rR;

        Stage init, idle, work;
        init = addStage("INIT", &rxInitEnter);
        idle = addStage("IDLE", &rxIdleEnter);
        work = addStage("WORK", &rxWorkEnter, &rxWorkLeave);

        init.addReflex("M0", idle);

        idle.addReflex("M1", &rxIdleM1);
        idle.addReflex("M0", work);

        work.addReflex("D0", &rxWorkD0);
        work.addReflex("D2", &rxWorkD2);
        work.addReflex("T0", &rxWorkT0);
        work.addReflex("M0", idle);
    }

    void rxInitEnter() {
        io = newIo();
        tm = newTimer();
        msgTo(this, M0_IDLE);
    }

    void rxIdleEnter() {
        rR.put(this);
    }

    void rxIdleM1(StageMachine src, Object o) {
        assert(o !is null, format("%s : '%s' did not supplied i/o context", name, src.name));

        client = src;
        ctx = cast(IoContext)o;
        assert(ctx.needMore !is null, format("%s : '%s' did not specified needMore()", name, client.name));
        io.id = ctx.fd;
        msgTo(this, M0_WORK);
    }

    void rxWorkEnter() {
        ctx.cnt = 0;
        ctx.buf[] = 0;
        ctx.error = IoError.Ok;
        ctx.errno = 0;

        io.enableCanRead();
        tm.start(ctx.rxTimeOut ? ctx.rxTimeOut : 60000);
    }

    void rxWorkD0(StageMachine src, Object o) {

        size_t r;
        ulong freeSpace, totalBytes;
        auto io = cast(Io)o;

        long ba = io.bytesAvail;
        if (0 == ba) {
            ctx.error = IoError.HangUp;
            goto failure__;
        }

        freeSpace = ctx.buf.length - ctx.cnt;
        totalBytes = ctx.cnt + ba;
        if (freeSpace < ba)
            ctx.buf.length = totalBytes;

        r = read(io.id, ctx.buf[ctx.cnt .. $].ptr, ba);
        if (-1 == r) {
            ctx.error = IoError.System;
            ctx.errno = errno();
            goto failure__;
        }

        ctx.cnt += r;
        if (ctx.needMore(ctx.buf, ctx.cnt)) {
            io.enableCanRead();
        } else {
            done(M1_DONE);
        }
        return;

        failure__:
        done(M2_FAIL);
    }

    void rxWorkD2(StageMachine src, Object o) {
        ctx.error = IoError.HangUp;
        done(M2_FAIL);
    }

    void rxWorkT0(StageMachine src, Object o) {
        ctx.error = IoError.TimeOut;
        done(M2_FAIL);
    }

    void rxWorkLeave() {
        tm.stop();
    }
}
