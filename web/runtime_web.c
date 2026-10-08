/* What the Goose runtime needs from the system, as a browser can give it.

   The runtime reserves a large region of address space for each data stack
   with mmap, counting on pages being committed only when touched, and puts
   a PROT_NONE guard after it. WebAssembly has one linear memory and no page
   protection; but memory it grows into is zero and, in a browser, takes no
   real memory until written. So the runtime is compiled with mmap, mprotect
   and munmap renamed to these, which hand out fresh memory from the end of
   the heap. There is no guard: the regions are sized (GS_STACK_RESERVE) well
   past what the program uses. */

#include <stddef.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/mman.h>

#define REGION_ALIGN 65536

void *gs_web_mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    (void)addr, (void)prot, (void)flags, (void)fd, (void)offset;
    /* Past the heap's end: memory nothing has written yet, so zero. */
    void *p = sbrk((intptr_t)(length + REGION_ALIGN));
    if (p == (void *)-1) return MAP_FAILED;
    return (void *)(((uintptr_t)p + REGION_ALIGN - 1) & ~(uintptr_t)(REGION_ALIGN - 1));
}

int gs_web_mprotect(void *addr, size_t length, int prot) {
    (void)addr, (void)length, (void)prot;
    return 0;
}

/* Regions are given up only when a thread program ends, which a web build
   (one thread) does at exit. */
int gs_web_munmap(void *addr, size_t length) {
    (void)addr, (void)length;
    return 0;
}
