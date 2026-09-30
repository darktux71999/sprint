#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/uio.h>

int __pthread_key_create(pthread_key_t *key, void (*dtor)(void *))
{
	return pthread_key_create(key, dtor);
}

int __xstat64(int ver, const char *path, struct stat *st)
{
	(void)ver;
	return stat(path, st);
}

int __fxstat64(int ver, int fd, struct stat *st)
{
	(void)ver;
	return fstat(fd, st);
}

FILE *fopen64(const char *path, const char *mode)
{
	return fopen(path, mode);
}

int open64(const char *path, int flags, ...)
{
	va_list ap;
	int mode = 0;

	va_start(ap, flags);
	if (flags & O_CREAT)
		mode = va_arg(ap, int);
#ifdef O_TMPFILE
	else if ((flags & O_TMPFILE) == O_TMPFILE)
		mode = va_arg(ap, int);
#endif
	va_end(ap);
	return open(path, flags, mode);
}

int openat64(int dirfd, const char *path, int flags, ...)
{
	va_list ap;
	int mode = 0;

	va_start(ap, flags);
	if (flags & O_CREAT)
		mode = va_arg(ap, int);
#ifdef O_TMPFILE
	else if ((flags & O_TMPFILE) == O_TMPFILE)
		mode = va_arg(ap, int);
#endif
	va_end(ap);
	return openat(dirfd, path, flags, mode);
}

int creat64(const char *path, mode_t mode)
{
	return creat(path, mode);
}

void *mmap64(void *addr, size_t len, int prot, int flags, int fd, off_t off)
{
	return mmap(addr, len, prot, flags, fd, off);
}

ssize_t preadv64(int fd, const struct iovec *iov, int iovcnt, off_t offset)
{
	return preadv(fd, iov, iovcnt, offset);
}

ssize_t pwritev64(int fd, const struct iovec *iov, int iovcnt, off_t offset)
{
	return pwritev(fd, iov, iovcnt, offset);
}

int __register_atfork(void (*prepare)(void), void (*parent)(void),
                      void (*child)(void), void *dso)
{
	(void)dso;
	return pthread_atfork(prepare, parent, child);
}

char *__rawmemchr(const char *s, int c)
{
	while (*s != (char)c)
		s++;
	return (char *)s;
}

int __finitef(float v)
{
	return isfinite(v);
}

int __finite(double v)
{
	return isfinite(v);
}

int __open_2(const char *path, int flags)
{
	return open(path, flags, 0);
}

int __open64_2(const char *path, int flags)
{
	return open(path, flags, 0);
}

char *__strdup(const char *s)
{
	return strdup(s);
}

int __vsnprintf_chk(char *s, size_t maxlen, int flag, size_t slen,
                    const char *fmt, va_list ap)
{
	(void)flag;
	if (slen < maxlen)
		abort();
	return vsnprintf(s, maxlen, fmt, ap);
}

int __snprintf_chk(char *s, size_t maxlen, int flag, size_t slen,
                   const char *fmt, ...)
{
	va_list ap;
	int r;
	(void)flag;
	if (slen < maxlen)
		abort();
	va_start(ap, fmt);
	r = vsnprintf(s, maxlen, fmt, ap);
	va_end(ap);
	return r;
}

int __vfprintf_chk(FILE *stream, int flag, const char *fmt, va_list ap)
{
	(void)flag;
	return vfprintf(stream, fmt, ap);
}

int __fprintf_chk(FILE *stream, int flag, const char *fmt, ...)
{
	va_list ap;
	int r;
	(void)flag;
	va_start(ap, fmt);
	r = vfprintf(stream, fmt, ap);
	va_end(ap);
	return r;
}

int __printf_chk(int flag, const char *fmt, ...)
{
	va_list ap;
	int r;
	(void)flag;
	va_start(ap, fmt);
	r = vprintf(fmt, ap);
	va_end(ap);
	return r;
}

int __vprintf_chk(int flag, const char *fmt, va_list ap)
{
	(void)flag;
	return vprintf(fmt, ap);
}

int __sprintf_chk(char *s, int flag, size_t slen, const char *fmt, ...)
{
	va_list ap;
	int r;
	(void)flag;
	va_start(ap, fmt);
	if (slen < (size_t)-1) {
		r = vsnprintf(s, slen, fmt, ap);
		if (r >= 0 && (size_t)r >= slen)
			abort();
	} else {
		r = vsprintf(s, fmt, ap);
	}
	va_end(ap);
	return r;
}

char *__strcpy_chk(char *dest, const char *src, size_t dlen)
{
	size_t len = strlen(src);
	if (dlen != (size_t)-1 && len >= dlen)
		abort();
	return memcpy(dest, src, len + 1);
}

char *__strcat_chk(char *dest, const char *src, size_t dlen)
{
	size_t dest_len = dlen == (size_t)-1 ? strlen(dest) : strnlen(dest, dlen);
	size_t src_len = strlen(src);
	if (dlen != (size_t)-1 &&
	    (dest_len == dlen || src_len >= dlen - dest_len))
		abort();
	return memcpy(dest + dest_len, src, src_len + 1);
}

char *__strncpy_chk(char *dest, const char *src, size_t n, size_t dlen)
{
	if (n > dlen)
		abort();
	return strncpy(dest, src, n);
}

void *__memcpy_chk(void *dest, const void *src, size_t n, size_t dlen)
{
	if (n > dlen)
		abort();
	return memcpy(dest, src, n);
}

void *__memmove_chk(void *dest, const void *src, size_t n, size_t dlen)
{
	if (n > dlen)
		abort();
	return memmove(dest, src, n);
}

void *__memset_chk(void *dest, int c, size_t n, size_t dlen)
{
	if (n > dlen)
		abort();
	return memset(dest, c, n);
}
