
alias needMoreData = bool delegate(ubyte[] buf, uint cnt);

enum IoError : int {
    System = -1,
    Ok = 0,
    HangUp = 1,
    TimeOut = 2,
}

class IoContext {
    int fd;
    ubyte[] buf;
    uint cnt;
    IoError error;
    int errno;
    needMoreData needMore;
    uint rxTimeOut;

    this(uint bufSize) {
        buf = new ubyte[bufSize];
    }
}
