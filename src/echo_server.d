
import std.stdio: writeln;

import ecap, msgq, esrc, edsm, disp;
import ioctx, pool;
import rx, tx, listener, worker;

class EchoServer {

    MessageDispatcher md;
    uint maxClients;
    RestRoom rxPool, txPool, wrkPool;
    RxSm[] rxMachines;
    TxSm[] txMachines;
    WorkerSm[] wrkMachines;
    Listener reception;

    this(uint maxClients = 100) {
        md = new MessageDispatcher();
        this.maxClients = maxClients;
    }

    void ini() {

        rxPool = new RestRoom();
        foreach (k; 0 .. maxClients) {
            auto sm = new RxSm(md, rxPool);
            rxMachines ~= sm;
            sm.run();
        }

        txPool = new RestRoom();
        foreach (k; 0 .. maxClients) {
            auto sm = new TxSm(md, txPool);
            txMachines ~= sm;
            sm.run();
        }

        wrkPool = new RestRoom();
        foreach (k; 0 .. maxClients) {
            auto sm = new WorkerSm(md, wrkPool, rxPool, txPool);
            wrkMachines ~= sm;
            sm.run();
        }

        reception = new Listener(md, wrkPool);
        reception.run();
    }

    void run() {
        md.loop();
    }
}

void main(string[] args) {

    auto prog = new EchoServer(100);
    prog.ini();

    writeln(" === Hello, world! === ");
    prog.run();
    writeln(" === Goodbye, world! === ");
}
