#!/bin/sh

set -euf

### Library

# Retry to run command in background, until it succeedes. If it fails (exits
# with >0), run step function to change some resource, and retry to run
# the command. Note, that retry itself runs in the background. To terminate,
# kill entire process group.
# 1 - step function.
# 2.. - cmd to retry (run through eval).
retry()
{
    local step="$1"
    shift 1

    while [ 0 ]; do
	eval "$@" &
	if wait "$!"; then
	    break
	else
	    eval "$step"
	fi
    done &
}


### Main

host="$1"
cmd="$2"

if [ "x$DISPLAY" = x ]; then
    echo "Error: DISPLAY variable not set."
    exit 1
fi

# Display number.
ndisp="${DISPLAY#*:}"	# Remove hostname.
ndisp="${ndisp%.*}"	# Should i remove screen number?

sock="/tmp/.X11-unix/X$ndisp"
if [ -S "$sock" ]; then
    echo "Connect to unix domain socket '$sock'."
    lport=$((6000 + $ndisp + 1))
    retry 'lport=$(($lport + 1));' \
	  'echo "Try to listen on port $lport.."
	   socat TCP-LISTEN:$lport,bind=127.0.0.1 UNIX-CONNECT:"$sock"
	  '
else
    # Check, that someone really listens on $port?
    dport=$((6000 + $ndisp))
    echo "Connect to TCP port $dport."
    retry 'lport=$(($lport + 1));' \
	  'echo "Try to listen on port $lport.."
	   socat TCP-LISTEN:$lport,bind=127.0.0.1 TCP:127.0.0.1:$dport
	  '
fi
retry_pid="$!"
retry_pgid="$(ps --no-headings -p "$retry_pid" -o pgid \
		| sed -e's/[[:space:]]//g')"
trap "/bin/kill -TERM -\"\$retry_pgid\" 2>/dev/null" INT QUIT EXIT 

# Or add to key: command="sockauth=\"$(mktemp --tmpdir sockauth.XXXXXX)\"; export XAUTHORITY=\"$sockauth\"; export DISPLAY=127.0.0.1:9; xauth nmerge -; eval \"$SSH_ORIGINAL_COMMAND\"" 
# Hardcoded port on remote side.

remoteauth="$(mktemp --tmpdir remoteauth.XXXXXX)"
xauth -f "$remoteauth" generate :0 . trusted timeout 50
xauth -f "$remoteauth" nlist \
    | cut -d' ' -f9 \
    | ssh -R 6009:127.0.0.1:$lport "$host" \
	"remoteauth=\"\$(mktemp --tmpdir remoteauth.XXXXXX)\"
	 export XAUTHORITY=\"\$remoteauth\"
	 export DISPLAY=127.0.0.1:9
	 read d
	 xauth add ':9' . \"\$d\"
	 xauth list
	 echo \$DISPLAY
	 $cmd
	 #rm -f \"\$remoteauth\"
	 "
# socat will be killed by `trap` action,

