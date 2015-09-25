#include <unistd.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>
#include <string.h>
#include <malloc.h>
#include <openssl/md5.h>
#include <map>
#define __STDC_FORMAT_MACROS 
#include <inttypes.h>
#include <time.h>
#include <assert.h>
#include <errno.h>
#include <mcheck.h>
#include <sys/resource.h>

#ifndef __COMMON__
#define __COMMON__

#define LEN 2048
#define MAXNUM 50000000
#define SLEEP 15
#define MEGABYTE (1024 * 1024)

#define DCID_NONE 0
#define DCID_INVALID 1

#define CACHE_NODE_DELETED     1

/*
 * 128 bits md5sum
 */
typedef struct
{
    union
    {
        unsigned char digest_uchar[16];
        uint32_t digest_uint[4];
    };
}md5_digest_t;

/*
 * linked list node
 */
typedef struct cache_l_node
{
    struct cache_l_node *child;
    md5_digest_t digest;
    uint64_t flag:8;
    uint64_t dcid:56;
} cache_l_node_t;

/*
 * linked list cache
 */
typedef struct cache_l
{
    cache_l_node_t **cache_root;
    
    uint32_t bits;
    uint32_t mask;
    
    size_t max_nodes;
    size_t num_nodes;
} cache_l_t;

extern void display_mallinfo();
extern void output_top();
extern void uint64_to_md5(uint64_t input, md5_digest_t &output );
extern int32_t md5_digest_compare(const md5_digest_t &a, const md5_digest_t &b);
extern void set_stack_limit();


#endif
