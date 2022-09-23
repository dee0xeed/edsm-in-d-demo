
import std.stdio : writeln, writefln;
import core.stdc.stdlib: exit;
import std.conv;

import ecap, msgq, esrc, edsm, disp;
import ioctx, pool;
import rx, tx, client, stopper;

class EchoClient {

    MessageDispatcher md;
    string host, port;
    uint nConnections;
    RestRoom rxPool, txPool;
    RxSm[] rxMachines;
    TxSm[] txMachines;
    WrkMachine[] wrkMachines;
    Stopper stopper;

    this(string host, string port, uint nConnections = 1) {
        md = new MessageDispatcher();
        this.host = host;
        this.port = port;
        this.nConnections = nConnections;
    }

    void ini() {

        rxPool = new RestRoom();
        foreach (k; 0 .. nConnections) {
            auto sm = new RxSm(md, rxPool);
            rxMachines ~= sm;
            sm.run();
        }

        txPool = new RestRoom();
        foreach (k; 0 .. nConnections) {
            auto sm = new TxSm(md, txPool);
            txMachines ~= sm;
            sm.run();
        }

        foreach (k; 0 .. nConnections) {
            auto sm = new WrkMachine(md, rxPool, txPool, host, port);
            wrkMachines ~= sm;
            sm.run();
        }

        stopper = new Stopper(md);
        stopper.run();
    }

    void run() {
        md.loop();
    }
}

void main(string[] args) {

    if (args.length != 4) {
        writefln("Usage: %s <host> <port> <nconnections>", args[0]);
        exit(0);
    }

    string host = args[1];
    string port = args[2];
    uint nConnections = to!uint(args[3]);

    auto prog = new EchoClient(host, port, nConnections);
    prog.ini();
    writeln(" === Hello, world! === ");
    prog.run();
    writeln(" === Goodbye, world! === ");
}
