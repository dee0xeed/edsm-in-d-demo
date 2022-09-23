
import ecap, msgq, edsm;
import std.stdio;

final class MessageDispatcher {

    EventQueue eq;
    MessageQueue mq;

    this() {
        mq = new MessageQueue();
        eq = new EventQueue(mq);
    }

    void loop() {
        do {
            Message msg;
            while (mq.getMsg(msg)) {
                StageMachine sm = msg.dst;
                sm.reactTo(msg);
            }
        } while (eq.wait());
    }
}
