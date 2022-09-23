
import std.stdio;
import std.format;

import msgq, ecap, esrc, disp;

alias Action = void delegate(StageMachine src, Object o);
alias Enter = void delegate();
alias Leave = void delegate();

final class Reflex {
    Action action;
    Stage nextStage;
}

final class Stage {
    string name;
    private Enter enter;
    private Leave leave;
    private Reflex[string] reflexes;

    final void addReflex(string eventName, Action a) {
        assert(
            eventName !in reflexes,
            format("'%s' already has reflex for '%s'", name, eventName)
        );

        Reflex r = new Reflex();
        r.action = a;
        reflexes[eventName] = r;
    }

    final void addReflex(string eventName, Stage s) {
        assert(
            eventName !in reflexes,
            format("'%s' already has reflex for '%s'", name, eventName)
        );

        Reflex r = new Reflex();
        r.nextStage = s;
        reflexes[eventName] = r;
    }
}

abstract class StageMachine {
    string name;
    private bool isRunning;
    private Stage[string] stages;
    private Stage currentStage;

    private bool hasIo;
    private int tm_number;
    private int sg_number;

    private EventQueue eq;
    private MessageQueue mq;

    this(MessageDispatcher md, string name) {
        this.name = name;
        eq = md.eq;
        mq = md.mq;
    }

    final Stage addStage(string stageName, Enter enter = null, Leave leave = null) {
        assert(
            stageName !in stages,
            format("'%s' already has stage '%s'", name, stageName)
        );

        Stage s = new Stage();
        s.name = stageName;
        s.enter = enter;
        s.leave = leave;
        stages[stageName] = s;
        return s;
    }

    final Timer newTimer() {
        Timer tm = new Timer(eq, tm_number++);
        tm.owner = this;
        return tm;
    }

    final Signal newSignal(int signum) {
        Signal sg = new Signal(eq, signum, sg_number++);
        sg.owner = this;
        return sg;
    }

    final Io newIo(int fd) {
        assert(!hasIo, format("'%s' already has Io channel", name));

        Io io = new Io(eq, fd);
        io.owner = this;
        hasIo = true;
        return io;
    }

    final Io newIo() {
        assert(!hasIo, format("'%s' already has Io channel", name));

        Io io = new Io(eq);
        io.owner = this;
        hasIo = true;
        return io;
    }

    final TCPListener newTCPListener(ushort port) {
        assert(!hasIo, format("'%s' already has Io channel", name));

        TCPListener l = new TCPListener(eq, port);
        l.owner = this;
        hasIo = true;
        return l;
    }

    final ClientSocket newClientSocket(string host, string port) {
        assert(!hasIo, format("'%s' already has Io channel", name));

        ClientSocket s = new ClientSocket(eq, host, port);
        s.owner = this;
        hasIo = true;
        return s;
    }

    final void run() {
        assert(!isRunning, format("'%s' is already started", name));
        assert(stages.length > 0, format("'%s' has no stages", name));

        Stage si = stages.get("INIT", null);
        assert(si !is null, format("'%s' has no 'INIT' stage", name));

        foreach (skey; stages.byKey) {
            Stage s = stages[skey];
            assert(s.reflexes.length > 0, format("'%s' has no reflexes for stage '%s'", name, s.name));
            foreach (rkey; s.reflexes.byKey) {
                Reflex r = s.reflexes[rkey];
                assert(
                    (r.action is null) ^ (r.nextStage is null),
                    format("'%s' has illegal reflex for '%s' at stage '%s'", name, rkey, s.name)
                );
            }
        }

        currentStage = si;
        si.enter();
        isRunning = true;
    }

    /* this method is state machine engine */
    final void reactTo(ref Message m) {
        string eventName;

        if (m.src is null) {
            EventSource ch = cast(EventSource)m.o;
            eventName = format("%c%u", ch.tag, m.code);
        } else {
            eventName = format("M%u", m.code);
        }

        writefln (
            "'%s @ %s' got '%s' from '%s'", name, currentStage.name, eventName,
            m.src ? (m.src is this ? "SELF" : m.src.name) : "OS"
        );

        if (eventName !in currentStage.reflexes) {
            writefln (
                "'%s @ %s' DROPPED '%s' from '%s'", name, currentStage.name, eventName,
                m.src ? (m.src is this ? "SELF" : m.src.name)  : "OS"
            );
            return;
        }

        Reflex r = currentStage.reflexes[eventName];

        /* action */
        if (r.action) {
            r.action(m.src, m.o);
            return;
        }

        /* transition */
        if (currentStage.leave)
            currentStage.leave();

        Stage nextStage = r.nextStage;

        if (nextStage.enter)
            nextStage.enter();

        currentStage = nextStage;
    }

    final void msgTo(StageMachine sm, ulong code, Object o = null) {
        mq.putMsg(this, sm, code, o);
    }

    final void stopEventQueue() {
        eq.stop();
    }
}
