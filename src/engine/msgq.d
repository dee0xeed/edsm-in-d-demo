
import std.container.dlist;
import edsm;
import esrc;

struct Message {
    StageMachine src;   /* null for messages from OS */
    StageMachine dst;
    ulong code;
    Object o;           /* EventSource for messages from OS */
}

final class MessageQueue {

    private DList!(Message) q;

    this() {
        q = DList!(Message)();
    }

    void putMsg(StageMachine src, StageMachine dst, ulong code, Object o = null) {
        auto m = Message(src, dst, code, o);
        q.insertBack(m);
    }

    /* mq += Message(src, dst, code, obj); */
    /* mq ~= Message(src, dst, code, obj); */
    MessageQueue opOpAssign(string op)(Message m)
    if ("+" == op || "~" == op) {
        q.insertBack(m);
        return this;
    }

    bool getMsg(out Message m) {
        if (q.empty)
            return false;

        m = q.front();
        q.removeFront();
        return true;
    }
}
