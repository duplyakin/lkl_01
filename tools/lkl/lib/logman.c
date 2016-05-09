#include <sys/mman.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include "logman.h"
static size_t f_size=0,f_pos=0;
static int log_fd=-1;
static pthread_mutex_t log_mutex=PTHREAD_MUTEX_INITIALIZER;
static vlad_log_rec* plog = NULL;

int vlad_init_log(const char * fname,size_t size)
{
    log_fd = open(fname, O_CREAT|O_RDWR, 0666);
    if (log_fd < 0)
	return -errno;
    f_size=size/sizeof(vlad_log_rec);
    assert( ftruncate(log_fd,f_size*sizeof(vlad_log_rec)) == 0);
    plog = mmap(NULL,f_size*sizeof(vlad_log_rec), PROT_READ|PROT_WRITE, MAP_SHARED, log_fd, 0);
    if ( plog == (void *)(-1) )
    {
	int err = errno;
	close(log_fd);
	log_fd = -1;
	return -err;
    }
    f_pos=0;
    return 0;
}

void vlad_log(const vlad_log_rec* req)
{
    pthread_mutex_lock(&log_mutex);
    if (f_pos == f_size)
    {
	int code=-1;
	munmap(plog,f_size*sizeof(vlad_log_rec));
	f_size*=2;
	do
	{
	    code = ftruncate(log_fd,f_size*sizeof(vlad_log_rec));
	    if (code == -1)
	    	assert(errno == EINTR);
	} 
	while (code != 0);
	plog = (vlad_log_rec *)mmap(NULL,f_size*sizeof(vlad_log_rec), PROT_READ|PROT_WRITE, MAP_SHARED, log_fd, 0 );
	assert( plog != (void *)(-1) );
    }
    memcpy(plog+f_pos++,req,sizeof(vlad_log_rec));
    pthread_mutex_unlock(&log_mutex);
}

void vlad_close_log(void)
{
    if (plog && plog != (void *)(-1))
	munmap(plog,f_size*sizeof(vlad_log_rec));
    if (log_fd >= 0)	
    {
	int code;
	do
	{
	    code = ftruncate(log_fd,f_pos*sizeof(vlad_log_rec));
	    if (code == -1)
	    	assert(errno == EINTR);
	} 
	while (code != 0);
	close(log_fd);
    }
    plog = NULL;
    log_fd = -1;
}
