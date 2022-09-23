
import std.stdio;
import std.format;

import edsm, esrc, disp;

class Stopper : StageMachine {

    enum ulong M0_IDLE = 0;
    Signal sg0, sg1;
    Timer tm0;

    this(MessageDispatcher md) {
        super(md, "STOPPER");

        Stage init, idle;
        init = addStage("INIT", &stopperInitEnter);
        idle = addStage("IDLE", &stopperIdleEnter);

        init.addReflex("M0", idle);

        idle.addReflex("S0", &stopperIdleS0);
        idle.addReflex("S1", &stopperIdleS1);
        idle.addReflex("T0", &stopperIdleT0);
    }

    void stopperInitEnter() {
        sg0 = newSignal(Signal.sigInt);
        sg1 = newSignal(Signal.sigTerm);
        tm0 = newTimer();
        msgTo(this, M0_IDLE);

        writeln(typeid(tm0));
        writeln(typeid(sg0));
        writeln(typeid(sg1));
    }

    void stopperIdleEnter() {
        sg0.enable();
        sg1.enable();
        tm0.start(3000);
    }

    void stopperIdleT0(StageMachine src, Object o) {
        writefln("%s() : tick", __FUNCTION__);
        tm0.start(3000);
    }

    void _bye() {
        stopEventQueue();
    }

    void stopperIdleS0(StageMachine src, Object o) {
        _bye();
    }

    void stopperIdleS1(StageMachine src, Object o) {
        _bye();
    }
}
