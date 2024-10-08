```Python
# Credits
__author__ = 'João Tonini'
__copyright__ = 'Copyright 2024'
__credits__ = None
__version__ = str(math.pi**2)[:5]
__maintainer__ = 'George Flanagin'
__email__ = ['jtonini@richmond.edu']
__status__ = 'Research'
__license__ = 'MIT'


import os
import platform
import subprocess
import time
import shutil
import sys
```
- I really like the dictionary :smile:
```Python
# Custom print function to control displayed messages
def custom_print(message_type):
    messages = {
        "header": "This is a University of Richmond (UofR) computer system.",
        "version": "This version of the script is from...",
        "processing": "Your request is being processed, please wait, and a web browser will open with Jupyter..."
    }
    print(messages.get(message_type, ""))
```


- Is there any other place to call?
```Python
# Display the initial messages
custom_print("header")
custom_print("version")
custom_print("processing")
```


- include `current_os` in [default_browser](#default_browser)
- The current method works great with logger
```Python
# Determine the current operating system
current_os = platform.system()
```

- import python module [webbrowser](https://docs.python.org/3/library/webbrowser.html#module-webbrowser)
- use dict to replace if and elif, so it will be easier to maintain
    - e.g: `{'Darwin' : 'open'}`
- The current method works great with logger
```Python
# Determine the default browser launcher
def default_browser():
    browser_exe = os.environ.get('BROWSER')
    if not browser_exe:
        if current_os == 'Linux':
            browser_exe = subprocess.check_output(['xdg-settings', 'get', 'default-web-browser'], stderr=subprocess.DEVNULL).decode().strip()
        elif current_os == "Darwin":  # macOS
            browser_exe = "open"
        elif current_os == "Windows":
            browser_exe = "start"
        else:
            browser_exe = None
    return browser_exe
```
- include this part to [default_browser](#default-browser) as an exception
```Python
launcher = default_browser()
if not launcher:
    sys.exit("Cannot determine how to start your browser. This script is not for you.")
```



- Environment variables, with their default values.(Global object)
- Class variables
- Config file
```Python
# Variables
cluster = "spydur"
created_files = ["tunnelspec.txt", "urlspec.txt", "salloc.txt", "jparams.txt"]
jupyter_exe = "/usr/local/sw/anaconda/anaconda3/bin/jupyter notebook --NotebookApp.open_browser=False"
jupyter_port = 0
partition = "basic"
runtime = 1
thisjob = ""
thisnode = ""
```
- For future returncode in func [slurm_jupyter](#slurm-jupyter)
```Python
def run_command(cmd, shell=False, returncode=False):
    try:
        result = subprocess.run(cmd, shell=shell, check=True, text=True, capture_output=True)

        if returncode:
            return result.returncode
        else:
            return result.stdout
    
    except subprocess.CalledProcessError:
        return None
```
- new func [checkopt_command](#checkopt-command)
```Python
def checkopt_command(cmd, shell=False):
    try:
        result = subprocess.check_output(cmd, shell=shell, stderr=subprocess.DEVNULL)
        return result.decoded().strip()
    except subprocess.CalledProcessError:
        return None
```
```Python
# Function to run shell commands
def run_command(cmd, shell=False):
    try:
        # Suppress all shell command output
        result = subprocess.run(cmd, shell=shell, check=True, text=True, capture_output=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None
```
- :)
```Python
# Function to limit runtime to a maximum of 8 hours
def limit_time(runtime):
    return min(runtime, 8)
```
- [next](https://docs.python.org/3/library/pdb.html#pdbcommand-next)
    - get the first port from the generator that is available
```Python
# Skyler:
def open_port(name_fragment, lower=9500, upper=9600):
    result = run_command(['ss', '-tuln'])
    filepath = os.path.expanduser(f"~/openport.{name_fragment}.txt")
    
    x = next((port for port in range(lower, upper+1) if f":{port}" not in result]), None)
    if x is not None:
        with open(filepath, 'w') as file:
            file.write(f"{x}")
        return x
    return None
```
```Python
# Function to find an open port within a specified range
def open_port(name_fragment, lower=9500, upper=9600):
    for port in range(lower, upper + 1):
        result = subprocess.run(['ss', '-tuln'], capture_output=True, text=True)
        if f":{port} " not in result.stdout:
            with open(os.path.expanduser(f"~/openport.{name_fragment}.txt"), 'w') as file:
                file.write(f"{port}")
            return port
    return None
```

```Python
#Skyler:
cmd = ['bash', 'open_port.sh']
if port:
    run_command(cmd).strip()
```
```
# Function to handle port script on HPC headnode
def open_port_script(name_fragment):
    port = open_port(name_fragment)
    if port:
        run_command(['bash', 'open_port.sh'])
```

- Easier to maintain
```Python
cmd = f"ssh {me}@{cluster} 'sinfo -o \"%P\"'"
partitions = run_command(cmd, shell=True).strip().split()
```
```
# Function to validate partition
def valid_partition(partition):
    if not partition:
        return False

    partitions = run_command(f"ssh {me}@{cluster} 'sinfo -o \"%P\"'", shell=True).split()
    return partition in partitions
```

- helper func for [slurm_jupyter](#slurm-jupyter)
```Python
def run_and_check(cmd, shell=False, returncode=False, sleep_time=None):
    result = run_command(cmd, shell=shell, returncode=returncode)
    if result != 0:
        return False
    if sleep_time:
        time.sleep(sleep_time)
    return True
```
```Python
#Skyler:
def slurm_jupyter():
    # files/file paths variables
    jp = 'jparams.txt'
    computenode = os.path.expanduser("~/openport.computenode.txt")
    tunnelspec = os.path.expanduser("~/tunnelspec.txt")


    # os variables
    gpu = os.environ.get('gpu', 'NONE')
    partition = os.environ.get('partition')
    runtime = os.environ.get('runtime')
    
   
    with open(jp, 'r') as f1:
        exec(f1.read(), globals())
    #?
    open_port_script('headnode')


    gpu_option = "" if gpu == "NONE" else f"--gpus={gpu}"
    s1_cmd = f"salloc --account {me} -p {partition} {gpu_option} --time={runtime}:00:00 --no-shell > salloc.txt 2>&1"
    if not run_and_check(s1_cmd, shell=True, returncode=True, sleep_time=5):
        return
    
    # cmd variables
    job_cmd = "cat salloc.txt | head -1 | awk '{print $NF}'"
    thisjob = checkopt_command(job_cmd, shell=True)
        
    node_cmd = f"squeue -o %N -j {thisjob} | tail -1"
    thisnode = checkopt_command(node_cmd, shell=True)

    s2_cmd = f"ssh {me}@{thisnode} 'source {thisscript} && open_port_script computenode'"
    if not run_and_check(s2_cmd, shell=True, returncode=True, sleep_time=1):
        return
    
    with open(computenode, 'r') as f2:
        jupyter_port = f2.read().strip()
    with open(tunnelspec, 'w') as f3:
        w1 = f"ssh -q -f -N -L {jupyter_port}:{thisnode}:{jupyter_port} {me}@{cluster}\n"
        w2 = f"export jupyter_port={jupyter_port}\n"

        f3. write(w1, w2)

    ssh1_cmd = f"ssh {me}@{thisnode} 'source /usr/local/sw/anaconda/anaconda3/bin/activate cleancondajupyter ; nohup {jupyter_exe} --ip=0.0.0.0 --port={jupyter_port} > jupyter.log 2>&1 & disown'"
    ssh2_cmd = f"ssh {me}@{thisnode} 'tac jupyter.log | grep -a -m 1 \"127\\.0\\.0\\.1\" > urlspec.txt'"

    run_command(ssh1_cmd, shell=True)
    time.sleep(5)
    run_command(ssh2_cmd, shell=True)

```
```Python
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
    
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        return
    else:
        time.sleep(5)
        thisjob = subprocess.check_output("cat salloc.txt | head -1 | awk '{print $NF}'", shell=True, stderr=subprocess.DEVNULL).decode().strip()
        thisnode = subprocess.check_output(f"squeue -o %N -j {thisjob} | tail -1", shell=True, stderr=subprocess.DEVNULL).decode().strip()

    result = subprocess.run(f"ssh {me}@{thisnode} 'source {thisscript} && open_port_script computenode'", shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        return
    time.sleep(1)
    
    with open(os.path.expanduser("~/openport.computenode.txt"), 'r') as file:
        jupyter_port = file.read().strip()

    with open(os.path.expanduser("~/tunnelspec.txt"), 'w') as file:
        file.write(f"ssh -q -f -N -L {jupyter_port}:{thisnode}:{jupyter_port} {me}@{cluster}\n")
        file.write(f"export jupyter_port={jupyter_port}\n")

    subprocess.run(f"ssh {me}@{thisnode} 'source /usr/local/sw/anaconda/anaconda3/bin/activate cleancondajupyter ; nohup {jupyter_exe} --ip=0.0.0.0 --port={jupyter_port} > jupyter.log 2>&1 & disown'", shell=True, capture_output=True, text=True)
    time.sleep(5)
    subprocess.run(f"ssh {me}@{thisnode} 'tac jupyter.log | grep -a -m 1 \"127\\.0\\.0\\.1\" > urlspec.txt'", shell=True, capture_output=True, text=True)
```

- Similar problem with [slurm_jupyter](#slurm-jupyter)
```Python
# Function to run the Jupyter setup
def run_jupyter(args):
    if len(args) < 2:
        return

    global me
    partition, me, runtime, gpu = args[0], args[1], int(args[2]) if len(args) > 2 else 1, args[3] if len(args) > 3 else 'NONE'

    if not valid_partition(partition):
        return

    runtime = limit_time(runtime)
    
    with open('jparams.txt', 'w') as file:
        file.write(f"export partition={partition}\nexport me={me}\nexport runtime={runtime}\nexport gpu={gpu}\n")

    subprocess.run(f"ssh {me}@{cluster} 'rm -fv {created_files}'", shell=True, capture_output=True, text=True)

    shutil.copy('jparams.txt', os.path.expanduser(f"~/{me}"))
    shutil.copy(__file__, os.path.expanduser(f"~/{me}"))

    subprocess.run(f"ssh {me}@{cluster} 'source jupyter.sh && slurm_jupyter'", shell=True, capture_output=True, text=True)
    
    if subprocess.run(f"scp {me}@{cluster}:~/tunnelspec.txt ~/.", shell=True, capture_output=True, text=True).returncode != 0:
        return
    
    with open(os.path.expanduser("~/tunnelspec.txt"), 'r') as file:
        for line in file:
            line = line.strip()
            if line.startswith("ssh -q"):
                subprocess.run(line, shell=True, capture_output=True, text=True)
            elif line.startswith("export"):
                key, value = line.split("=")
                os.environ[key.split()[1]] = value.strip()

    if subprocess.run(f"scp {me}@{cluster}:~/urlspec.txt ~/.", shell=True, capture_output=True, text=True).returncode != 0:
        return

    with open(os.path.expanduser("~/urlspec.txt"), 'r') as file:
        url = file.read().split()[-1]
    
    if not url:
        return

    if launcher:
        subprocess.run([launcher, url], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
```

```Python
if __name__ == "__main__":
    run_jupyter(sys.argv[1:])
```
