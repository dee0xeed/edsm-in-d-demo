
import std.stdio;
import std.format;

import edsm, pool, ioctx, esrc, disp;

/* SMD
$init
$work

+init M0 work

@work D0    --> L0
@work M0
@work M1    ---
            S0, S1
*/

class Listener : StageMachine {

    enum ulong M0_WORK = 0;
    enum ulong M1_WORK = 1;
    enum ulong M0_GONE = 0;

    RestRoom workerPool;
    ushort port;
    TCPListener reception;
    Signal sg0, sg1;

    this(MessageDispatcher md, RestRoom wPool, ushort port = 1111) {
        super(md, "LISTENER");
        workerPool = wPool;
        this.port = port;

        Stage init, work;
        init = addStage("INIT", &listenerInitEnter);
        work = addStage("WORK", &listenerWorkEnter);

        init.addReflex("M0", work);

        work.addReflex("L0", &listenerWorkL0);
        work.addReflex("M0", &listenerWorkM0);
        work.addReflex("S0", &listenerWorkS0);
        work.addReflex("S1", &listenerWorkS1);
    }

    void listenerInitEnter() {
        reception = newTCPListener(port);
        sg0 = newSignal(Signal.sigInt);
        sg1 = newSignal(Signal.sigTerm);
        msgTo(this, M0_WORK);
    }

    void listenerWorkEnter() {
        reception.enable();
        sg0.enable();
        sg1.enable();
    }

    /* incoming connection */
    void listenerWorkL0(StageMachine src, Object o) {
        Client client = reception.acceptClient();
        writefln("client from '%s:%d' (fd = %d)", client.addr, client.port, client.fd);
        reception.enable();

        if (workerPool.empty()) {
            msgTo(this, M0_GONE, client);
            return;
        }

        StageMachine worker = workerPool.get();
        msgTo(worker, M1_WORK, client);
    }

    /* message from worker machine (client gone) */
    /* or from self (if no workers were available) */
    void listenerWorkM0(StageMachine src, Object o) {
        Client client = cast(Client)o;
        client.destroy();
    }

    void listenerWorkS0(StageMachine src, Object o) {
        stopEventQueue();
    }

    void listenerWorkS1(StageMachine src, Object o) {
        stopEventQueue();
    }
}
