/* Flush a file's data to stable storage, portably.
 *
 * The Ada side did open()/fsync()/close() directly, which does not link on Windows: mingw has
 * no fsync, and no O_DIRECTORY. Windows flushes with FlushFileBuffers on a file HANDLE, and a
 * directory cannot be flushed that way at all -- so a directory sync is a best-effort no-op
 * there, which is what the caller already treats it as.
 */

#ifdef _WIN32

#include <windows.h>

int http_client_fsync_path(const char *path, int is_directory) {
    HANDLE h;
    if (path == NULL) return 0;

    /* A directory handle cannot be flushed on Windows; report best-effort success. */
    if (is_directory) return 1;

    h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;

    if (!FlushFileBuffers(h)) {
        CloseHandle(h);
        return 0;
    }
    CloseHandle(h);
    return 1;
}

#else

#include <fcntl.h>
#include <unistd.h>

int http_client_fsync_path(const char *path, int is_directory) {
    int fd;
    int rc;
    int flags = O_RDONLY;

    if (path == NULL) return 0;

#ifdef O_DIRECTORY
    if (is_directory) flags |= O_DIRECTORY;
#else
    (void) is_directory;
#endif

    fd = open(path, flags);
    if (fd < 0) return 0;

    rc = fsync(fd);
    if (close(fd) != 0) return 0;
    return rc == 0 ? 1 : 0;
}

#endif
