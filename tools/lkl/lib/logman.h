#ifndef __LOGMAN_H__
#define __LOGMAN_H__
#include<stdint.h>
#pragma pack(push,1)
typedef struct 
{
        unsigned int type;
        unsigned int prio;
        unsigned long long sector;
        int count;
} vlad_log_rec;
#pragma pack(pop)
int vlad_init_log(const char * fname,size_t size);
void vlad_log(const vlad_log_rec * req);
void vlad_close_log(void);
#endif
