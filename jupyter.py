import os
import platform
import subprocess
import time
import shutil
import sys
from pathlib import Path

# Determine the current operating system
current_os = platform.system()

# Determine the default browser launcher
def default_browser():
    browser_exe = os.environ.get('BROWSER')
    if not browser_exe:
        if current_os == 'Linux':
            browser_exe = subprocess.check_output(['xdg-settings', 'get', 'default-web-browser']).decode().strip()
        elif current_os == "Darwin":  # macOS
            browser_exe = "open"
        elif current_os == "Windows":
            browser_exe = "start"
        else:
            browser_exe = None
    return browser_exe

launcher = default_browser()
if not launcher:
    sys.exit("Cannot determine how to start your browser. This script is not for you.")

# Variables
cluster = "spydur"
created_files = ["tunnelspec.txt", "urlspec.txt", "salloc.txt", "jparams.txt"]
jupyter_exe = "/usr/local/sw/anaconda/anaconda3/bin/jupyter notebook --NotebookApp.open_browser=False"
jupyter_port = 0
partition = "basic"
runtime = 1
thisjob = ""
thisnode = ""

# Function to run shell commands
def run_command(cmd, shell=False):
    try:
        result = subprocess.run(cmd, shell=shell, check=True, text=True, capture_output=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e.cmd}")
        print(e.output)
        return None

# Function to limit runtime to a maximum of 8 hours
def limit_time(runtime):
    if runtime > 8:
        print("Setting hours to the maximum of 8")
        runtime = 8
    return runtime

# Function to find an open port within a specified range
def open_port(name_fragment, lower=9500, upper=9600):
    for port in range(lower, upper + 1):
        result = subprocess.run(['ss', '-tuln'], capture_output=True, text=True)
        if f":{port} " not in result.stdout:
            with open(os.path.expanduser(f"~/openport.{name_fragment}.txt"), 'w') as file:
                file.write(f"{port}")
            return port
    print(f"No open port found in range {lower}-{upper} for {name_fragment}.")
    return None

# Function to handle port script on HPC headnode
def open_port_script(name_fragment):
    port = open_port(name_fragment)
    if port:
        run_command(['bash', 'open_port.sh'])

# Function to validate partition
def valid_partition(partition):
    if not partition:
        print("No partition name given")
        return False

    partitions = run_command(f"ssh {me}@{cluster} 'sinfo -o \"%P\"'", shell=True).split()
    return partition in partitions

# Function to create SLURM job and set up tunnel
def slurm_jupyter():
    with open('jparams.txt', 'r') as file:
        params = file.read()
    exec(params, globals())
    
    open_port_script('headnode')
    
    gpu = os.environ.get('gpu', 'NONE')
    partition = os.environ.get('partition')
    runtime = os.environ.get('runtime')
    
    if gpu == "NONE":
        cmd = f"salloc --account {me} -p {partition} --time={runtime}:00:00 --no-shell > salloc.txt 2>&1"
    else:
        cmd = f"salloc --account {me} -p {partition} --gpus={gpu} --time={runtime}:00:00 --no-shell > salloc.txt 2>&1"
    
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0:
        print("salloc was unable to allocate a compute node for you.")
        with open('salloc.txt', 'r') as file:
            print(file.read())
        return
    else:
        with open('salloc.txt', 'r') as file:
            print("-------------------------------------")
            print(file.read())
            print("-------------------------------------")
        time.sleep(5)
        thisjob = subprocess.check_output("cat salloc.txt | head -1 | awk '{print $NF}'", shell=True).decode().strip()
        print(f"Your request is granted. Job ID {thisjob}")

        thisnode = subprocess.check_output(f"squeue -o %N -j {thisjob} | tail -1", shell=True).decode().strip()
        print(f"JOB {thisjob} will be executing on {thisnode}")

    result = subprocess.run(f"ssh {me}@{thisnode} 'source {thisscript} && open_port_script computenode'", shell=True)
    if result.returncode != 0:
        print("Died trying to get compute node port.")
        return
    time.sleep(1)
    
    with open(os.path.expanduser("~/openport.computenode.txt"), 'r') as file:
        jupyter_port = file.read().strip()

    with open(os.path.expanduser("~/tunnelspec.txt"), 'w') as file:
        file.write(f"ssh -q -f -N -L {jupyter_port}:{thisnode}:{jupyter_port} {me}@{cluster}\n")
        file.write(f"export jupyter_port={jupyter_port}\n")

    subprocess.run(f"ssh {me}@{thisnode} 'source /usr/local/sw/anaconda/anaconda3/bin/activate cleancondajupyter ; nohup {jupyter_exe} --ip=0.0.0.0 --port={jupyter_port} > jupyter.log 2>&1 & disown'", shell=True)
    print(f"Jupyter notebook started on {thisnode}:{jupyter_port}")
    print("Waiting for five seconds for it to fully start.")
    time.sleep(5)
    subprocess.run(f"ssh {me}@{thisnode} 'tac jupyter.log | grep -a -m 1 \"127\\.0\\.0\\.1\" > urlspec.txt'", shell=True)

# Function to run the Jupyter setup
def run_jupyter(args):
    if len(args) < 2:
        print("Usage:")
        print("  run_jupyter PARTITION USERNAME [HOURS] [GPU]")
        print(" ")
        print(" PARTITION -- the name of the partition where you want ")
        print("    your job to run. This is the only required parameter.")
        print(" ")
        print(" USERNAME -- the name of the user on the *cluster*. ")
        print(" ")
        print(" HOURS -- defaults to 1, max is 8.")
        print(" ")
        print(" GPU -- defaults to 0, max depends on the node.")
        print(" ")
        return

    global me
    partition, me, runtime, gpu = args[0], args[1], int(args[2]) if len(args) > 2 else 1, args[3] if len(args) > 3 else 'NONE'

    if not valid_partition(partition):
        print(f"Partition {partition} not found. Cannot continue.")
        return

    runtime = limit_time(runtime)
    
    with open('jparams.txt', 'w') as file:
        file.write(f"export partition={partition}\nexport me={me}\nexport runtime={runtime}\nexport gpu={gpu}\n")

    subprocess.run(f"ssh {me}@{cluster} 'rm -fv {created_files}'", shell=True)

    shutil.copy('jparams.txt', os.path.expanduser(f"~/{me}"))
    shutil.copy(__file__, os.path.expanduser(f"~/{me}"))

    subprocess.run(f"ssh {me}@{cluster} 'source jupyter.sh && slurm_jupyter'", shell=True)
    
    if subprocess.run(f"scp {me}@{cluster}:~/tunnelspec.txt ~/.", shell=True).returncode != 0:
        print("Unable to retrieve tunnelspec.txt")
        return
    print("Retrieved tunnel spec.")
    
    with open(os.path.expanduser("~/tunnelspec.txt"), 'r') as file:
        for line in file:
            line = line.strip()
            if line.startswith("ssh -q"):
                # Execute the SSH tunnel command
                subprocess.run(line, shell=True)
            elif line.startswith("export"):
                # Set the environment variable
                key, value = line.split("=")
                os.environ[key.split()[1]] = value.strip()

    if subprocess.run(f"scp {me}@{cluster}:~/urlspec.txt ~/.", shell=True).returncode != 0:
        print("Could not retrieve URL for Jupyter notebook.")
        return

    with open(os.path.expanduser("~/urlspec.txt"), 'r') as file:
        url = file.read().split()[-1]
    
    if not url:
        print("Empty URL spec. Cannot continue.")
        return

    if launcher:
        subprocess.run([launcher, url])

if __name__ == "__main__":
    run_jupyter(sys.argv[1:])

