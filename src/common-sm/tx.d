
import std.format;
import core.sys.posix.unistd;
import core.stdc.errno;

import edsm, pool, ioctx, esrc, disp;

/* SMD
$init
$idle
$work

+init M0 idle

@idle M1
+idle M0 work

@work D1
@work D2
+work M0 idle
*/

class TxSm : StageMachine {

    private static int number = -1;

    enum ulong M0_IDLE = 0;
    enum ulong M0_WORK = 0;
    enum ulong M1_DONE = 1;
    enum ulong M2_FAIL = 2;

    StageMachine client;
    RestRoom rR;
    IoContext ctx;
    private uint pos;

    Io io;

    this(MessageDispatcher md, RestRoom rR) {
        super(md, format("TX-%d", ++number));
        this.rR = rR;

        Stage init, idle, work;
        init = addStage("INIT", &txInitEnter);
        idle = addStage("IDLE", &txIdleEnter);
        work = addStage("WORK", &txWorkEnter);

        init.addReflex("M0", idle);

        idle.addReflex("M1", &txIdleM1);
        idle.addReflex("M0", work);

        work.addReflex("D1", &txWorkD1);
        work.addReflex("D2", &txWorkD2);
        work.addReflex("M0", idle);
    }

    void txInitEnter() {
        io = newIo();
        msgTo(this, M0_IDLE);
    }

    void txIdleEnter() {
        rR.put(this);
    }

    void txIdleM1(StageMachine src, Object o) {
        assert(o !is null, format("%s : '%s' did not supplied i/o context", name, src.name));

        client = src;
        ctx = cast(IoContext)o;
        io.id = ctx.fd;
        msgTo(this, M0_WORK);
    }

    void txWorkEnter() {
        ctx.error = IoError.Ok;
        ctx.errno = 0;
        pos = 0;
        io.enableCanWrite();
    }

    private void done(ulong mcodeForClient) {
        msgTo(this, M0_IDLE);
        msgTo(client, mcodeForClient);
    }

    void txWorkD1(StageMachine src, Object o) {
        size_t r;
        auto io = cast(Io)o;
        ulong mcode = M1_DONE;

        if (0 == ctx.cnt)
            /* request for async connect */
            goto done__;

        r = write(io.id, ctx.buf[pos .. $].ptr, ctx.cnt);
        if (-1 == r) {
            mcode = M2_FAIL;
            ctx.error = IoError.System;
            ctx.errno = errno();
            goto done__;
        }

        pos += r;
        ctx.cnt -= r;
        if (ctx.cnt > 0) {
            io.enableCanWrite();
            return;
        }

        done__:
        done(mcode);
    }

    void txWorkD2(StageMachine src, Object o) {
        ctx.error = IoError.HangUp;
        done(M2_FAIL);
    }
}
