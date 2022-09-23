
import std.container.slist;
import edsm;

alias SmPool = SList!(StageMachine);

class RestRoom {

    private SmPool _pool;

    this() {
        _pool = SmPool();
    }

    void put(StageMachine sm) {
        _pool.insertFront(sm);
    }

    StageMachine get() {
        StageMachine sm = _pool.front();
        _pool.removeFront();
        return sm;
    }

    bool empty() {
        return _pool.empty();
    }
}
