#include <sys/mount.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/reboot.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>

static void poweroff(int sig) { sync(); reboot(RB_POWER_OFF); }
static void reboot_(int sig)  { sync(); reboot(RB_AUTOBOOT); }

int main(void) {
    mount("devtmpfs", "/dev",  "devtmpfs", 0, 0);
    mount("proc",     "/proc", "proc",     0, 0);
    mount("sysfs",    "/sys",  "sysfs",    0, 0);

    int fd = open("/dev/console", O_RDWR);
    if (fd >= 0) {
        dup2(fd, 0);
        dup2(fd, 1);
        dup2(fd, 2);
        if (fd > 2) close(fd);
    }

    setsid();
    ioctl(0, TIOCSCTTY, 1);

    signal(SIGUSR2, poweroff);
    signal(SIGTERM, poweroff);
    signal(SIGUSR1, reboot_);

    char *argv[] = { "sysinit", 0 };
    char *envp[] = { "PATH=/bin:/usr/bin", "HOME=/", "TERM=linux", 0 };

    pid_t pid = fork();
    if (pid == 0) {
        execve("/sbin/sysinit", argv, envp);
        _exit(127);
    }

    for (;;) wait(NULL);
}
