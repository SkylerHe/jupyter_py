###
#  
# Version 0.9 --- 23 May 2024
#
# Author: George Flanagin
# email:  gflanagin@richmond.edu
# Org:    University of Richmond
# 
# Let's find out what we are running. If this is not a bash 
# shell, the script will not work.
###
if [ ! -n "$BASH_VERSION" ]; then
    echo "This is not a bash shell, and this script will not succeed. :-("
    return 
fi

export thisscript="${BASH_SOURCE[0]}"

OS=$(uname)
case "$OS" in
    Linux*)
        export launcher="xdg-open"
        export thisversion=$(stat -c %y  "$thisscript")
        ;;
    Darwin*)    
        export launcher="open"
        export thisversion=$(stat -f %Sm  "$thisscript")
        ;;
    CYGWIN*)    
        export launcher="cygstart"
        export thisversion="unknown date"
        ;;
    MINGW*)     
        export launcher="start"
        export thisversion="unknown date"
        ;;
    *)         
        export launcher=""
        export thisversion="unknown date"
        ;;
esac

if [ -z "$launcher" ]; then
    echo "I cannot figure out how to start your browser. Sorry."
    echo "I guess this script is not for you."
    return 
fi
    
echo " "
echo "    To learn more about $thisscript, type 'run_jupyter'."
echo "     "
echo "    This script is intended to be run from the computer where"
echo "      you want to see the Jupyter Notebook, IOW, the computer"
echo "      with the web browser."
echo "     "
echo "    This version of the script is from $thisversion"
echo " "



########################################################################
# Environment variables, with their default values.
########################################################################

###
# In production, this will be the result of executing `whoami`,
#     shown here commented out. For testing, you can set it to 
#     any user who has an id on all the computers involved.
#
###
# If this is set, we use it. Not currently used, but we may 
# need this in future scripts.
###
export browser_exe="$BROWSER"
export cluster="spydur"
export created_files="tunnelspec.txt urlspec.txt salloc.txt jparams.txt"

###
# The exe we are running. Note that this location is on the compute node, which
# has /usr/local NFS mounted.
###
export jupyter_exe="/usr/local/sw/anaconda/anaconda3/bin/jupyter notebook --NotebookApp.open_browser=False"

###
# The port that Jupyter is listening on for a connection, and the
# same port that the browser will listen to on localhost.
###
export jupyter_port=0

###
# Default partition. Strictly speaking, the partition
# is not required, but it is a good idea to set this
# to the default on your cluster.
###
export partition=basic

###
# How long is the Jupyter session in hours?
###
export runtime=1

###
# These variables will be assigned by SLURM
###
export thisjob=
export thisnode=


########################################################################
# Shell functions.
########################################################################

# Find the default browser on the user's computer
function default_browser
{
    if [ -z $browser_exe ]; then
        browser_exe=$(xdg-settings get default-web-browser)
    fi
}

# Change this function as approprate for the environment.
function limit_time
{
    if (( $runtime > 8 )); then
        echo "Setting hours to the maximum of 8"
        runtime=8
    fi
}


# Search a range of ports for something not in use.
function open_port 
{
    if [ -z $1 ]; then
        echo "Usage: open_port {headnode|computenode}"
        return
    fi
    name_fragment="$1"
    lower=${2:-9500}
    upper=${3:-9600}
    

    for ((port = $lower; port <= $upper; port++)); do
        if ! ss -tuln | grep -q ":$port "; then
            echo "$port" > "$HOME/openport.$name_fragment.txt" 
            break
        fi
    done
}

# The easiest way to have the command as both a function and
# a script is to echo the function to a script, and then call it.
function open_port_script
{
    if [ -z "$1" ]; then
        echo "Usage: open_port_script {headnode|computenode}"
        return
    fi 
    type open_port | tail -n +2 > open_port.sh
    echo "open_port $1" >> open_port.sh
    chmod 755 open_port.sh
    ./open_port.sh
}

# Create the job on the headnode.
function slurm_jupyter
{
    # Pickup the value of partition, runtime, and gpu.
    source jparams.txt
    # find an open port on the headnode.
    #  This will create a file named $HOME/openport.headnode.txt
    open_port_script headnode

    # This command only creates a reservation for our session. We
    # are using this to retrieve the SLURM_JOBID and the name of
    # the node. 
    if [ "$gpu" == "NONE" ]; then
        export cmd="salloc --account $me -p "$partition" --time=$runtime:00:00 --no-shell > salloc.txt 2>&1"
    else
        export cmd="salloc --account $me -p $partition --gpus=$gpu --time=$runtime:00:00 --no-shell > salloc.txt 2>&1"
    fi
        
    eval "$cmd"

    # If we don't have a compute node, we are sunk.
    if [ ! $? ]; then
        echo "salloc was unable to allocate a compute node for you."
        cat salloc.txt
        return
    else
        echo "-------------------------------------"
        cat salloc.txt
        echo "-------------------------------------"
        sleep 5
        export thisjob=$(cat salloc.txt | head -1 | awk '{print $NF}')
        echo "your request is granted. Job ID $thisjob"

        thisnode=$(squeue -o %N -j $thisjob | tail -1)
        echo "JOB $thisjob will be executing on $thisnode"
    fi

    # Connect to the compute node and find an open port. Keep in mind
    # the script is already there because the $HOME directory is
    # NFS mounted everywhere on the system. Now, there will be a file
    # named $HOME/openport.computenode.txt
    ssh "$me@$thisnode" "source $thisscript && open_port_script computenode"
    if [ ! $? ]; then
        echo "Died trying to get computenode port."
        return
    fi
    sleep 1
    export jupyter_port=$(cat $HOME/openport.computenode.txt)

    # Now we have all the information needed to create the tunnel.
    # Let's make the command that creates the tunnel. We don't want
    # to execute it /here/, so we write it to a file. 
    cat <<EOF >"$HOME/tunnelspec.txt"
ssh -q  -f -N -L $jupyter_port:$thisnode:$jupyter_port $me@$cluster
export jupyter_port=$jupyter_port
EOF

    # Now we need to start the Jupyter Notebook.
    ssh "$me@$thisnode" "source /usr/local/sw/anaconda/anaconda3/bin/activate cleancondajupyter ; nohup $jupyter_exe --ip=0.0.0.0 --port=$jupyter_port > jupyter.log 2>&1 & disown"
    echo "Jupyter notebook started on $thisnode:$jupyter_port"
    echo "Waiting for five seconds for it to fully start."
    sleep 5
    ssh "$me@$thisnode" 'tac jupyter.log | grep -a -m 1 "127\.0\.0\.1" > urlspec.txt'
}


function valid_partition
{
    if [ -z "$1" ]; then
        echo "no parition name given" 
        false
        return
    fi

    export partitions=$(ssh "$me@$cluster" "sinfo -o '%P'")
    export partitions=$(echo "$partitions" | tr '\n' ' ')

    if echo "$partitions" | grep -q "$1" ; then
        true
    else
        false
    fi
}

###
# This is the "entry point" that launches Jupyter. It should be run
# from the workstation.
###
function run_jupyter
{
    if [ -z $2 ]; then
        echo "Usage:"
        echo "  run_jupyter PARTITION USERNAME [HOURS] [GPU]"
        echo " "
        echo " PARTITION -- the name of the partition where you want "
        echo "    your job to run. This is the only required parameter."
        echo " "
        echo " USERNAME -- the name of the user on the *cluster*. "
        echo " "
        echo " HOURS -- defaults to 1, max is 8."
        echo " " 
        echo " GPU -- defaults to 0, max depends on the node."
        echo " "
        return
    fi

    # Need to set $me first so that valid_partition can check it.
    export me="$2"
    partition="$1"  
    if valid_partition "$partition" ; then
        echo "Using partition $partition"
    else
        echo "Partition $partition not found. Cannot continue."
        return
    fi 


    runtime=${3-1}  # default to one hour.
    gpu=${4-NONE}  # if not provided, then nothing. 

    # Save the arguments.    
    cat<<EOF >jparams.txt
export partition=$partition
export me=$me
export runtime=$runtime
export gpu=$gpu
EOF
    ###
    # Remove any old files. If we don't do this, in the case of an 
    # error, this script might load a file left behind by a previous
    # notebook.
    ###

    ssh "$me@$cluster" "rm -fv $created_files"

    ###
    # copy the parameters to the headnode (which shares $HOME
    # with all the compute nodes.
    ###
    scp jparams.txt "$me@$cluster:~/." 2>/dev/null
    if [ ! $? ]; then
        echo "Could not copy parameters to $me@$cluster"
        return
    else
        echo "Parameters copied to $me@$cluster"
    fi

    # copy this file to the headnode.
    scp "$thisscript" "$me@$cluster:~/." 2>/dev/null
    if [ ! $? ]; then
        echo "Could not copy $thisscript commands to $me@$cluster"
        return
    else
        echo "Copied $thisscript commands to $me@$cluster"
    fi
    sleep 1

    ssh "$me@$cluster" "source jupyter.sh && slurm_jupyter"
    if [ ! $? ]; then
        echo "Unable to run slurm_jupyter on $me@$cluster."
        return
    else
        echo "Notebook launched."
    fi
    echo "Retrieving URL to launch notebook."
    #@@@ HERE

    scp "$me@$cluster:~/tunnelspec.txt" "$HOME" 
    if [ ! $? ]; then
        echo "Unable to retrieve tunnelspec.txt"
        return
    else
        echo "Retrieved tunnel spec."
    fi

    if [ ! -s "$HOME/tunnelspec.txt" ]; then
        echo "Empty tunnelspec."
        return
    fi

    # Open the tunnel.
    source "$HOME/tunnelspec.txt"
    if [ ! $? ]; then
        echo "Could not create tunnel!"
        return
    else
        echo "Tunnel created."
    fi 

    scp "$me@$cluster:urlspec.txt" "$HOME/."
    if [ ! $? ]; then
        echo "Could not retrieve URL for Jupyter notebook."
        return
    fi
        
    url=$(awk '{print $NF}' "$HOME/urlspec.txt")
    if [ -z "$url" ]; then
        echo "Empty URL spec. Cannot continue."
        return
    fi

    $launcher "$url"
}

