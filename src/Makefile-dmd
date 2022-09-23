
.PHONY: all clean cleanall

all: echo-server echo-client

echo-server: engine/*.d common-sm/*.d server-sm/*.d pool.d echo_server.d
	dmd engine/*.d common-sm/*.d server-sm/*.d pool.d echo_server.d -ofecho-server

echo-client: engine/*.d common-sm/*.d client-sm/*.d pool.d echo_client.d
	dmd engine/*.d common-sm/*.d client-sm/*.d pool.d echo_client.d -ofecho-client

clean:
	rm -f `find . -name "*.o"`
cleanall:
	rm -f `find . -name "*.o"` echo-server echo-client
