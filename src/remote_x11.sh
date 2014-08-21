#!/bin/sh

set -euf

host="$1"
shift

if [ "x$DISPLAY" = x ]; then
    echo "Error: DISPLAY variable not set." 1>&2
    exit 1
fi

# Display number.
ndisp="${DISPLAY#*:}"	# Remove hostname.
ndisp="${ndisp%.*}"	# Should i remove screen number?

# Find unused local port. This check skips only ports, where someone listens,
# but if port is in use due to some error (e.g. previous socat instance was
# terminated abnormally), the check will think the port is free.
lport=$((6000 + $ndisp + 1))
while [ 0 ]; do
    echo "Trying to local port $lport.." 1>&2
    if socat OPEN:/dev/null TCP:127.0.0.1:$lport 2>/dev/null; then
	lport=$(($lport + 1))
    else
	break
    fi
done

sock="/tmp/.X11-unix/X$ndisp"	# Current display's unix domain socket..
dport=$((6000 + $ndisp))	# .. and TCP port.
if [ -S "$sock" ]; then
    echo "Listen on port $lport and connect to unix domain socket '$sock'." 1>&2
    socat TCP-LISTEN:$lport,bind=127.0.0.1 UNIX-CONNECT:"$sock" &
elif socat OPEN:/dev/null TCP:127.0.0.1:$dport 2>/dev/null; then
    echo "Listen on port $lport and connect to TCP port $dport." 1>&2
    socat TCP-LISTEN:$lport,bind=127.0.0.1 TCP:127.0.0.1:$dport &
else
    echo "Error: can't connect to X server on display '$ndisp'". 1>&2
    exit 1
fi
socat_pid="$!"
trap "/bin/kill -HUP \"\$socat_pid\" 2>/dev/null" INT QUIT EXIT 

# Or add to key: command="sockauth=\"$(mktemp --tmpdir sockauth.XXXXXX)\"; export XAUTHORITY=\"$sockauth\"; export DISPLAY=127.0.0.1:9; xauth nmerge -; eval \"$SSH_ORIGINAL_COMMAND\"" 
remoteauth="$(mktemp --tmpdir remoteauth.XXXXXX)"
# Hardcoded port on remote side.
rport=6009
rdisp=9
xauth -f "$remoteauth" generate :0 . trusted timeout 50
xauth -f "$remoteauth" nlist \
    | cut -d' ' -f9 \
    | ssh -C -R 6009:127.0.0.1:$lport "$host" \
	"remoteauth=\"\$(mktemp --tmpdir remoteauth.XXXXXX)\"
	 export XAUTHORITY=\"\$remoteauth\"
	 export DISPLAY=127.0.0.1:$rdisp
	 read d
	 xauth add ':$rdisp' . \"\$d\"
	 $*
	 rm -f \"\$remoteauth\"
	 "
# When ssh runs in the background (with '-f'), command it runs can't read
# stdin.

rm -f "$remoteauth"
# socat will be killed by `trap` action,

