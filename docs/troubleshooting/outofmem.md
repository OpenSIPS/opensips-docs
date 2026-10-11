---
title: Out Of Memory
description: How to troubleshoot "out of memory" or "no more memory" messages in
  OpenSIPS 3.x and later.
---
This tutorial focuses on troubleshooting "out of memory" or "no more memory"
messages in **OpenSIPS 3.x and later**. Instructions for older OpenSIPS versions
are available in the [Legacy versions](#legacy-versions) section.

## Potential causes

Memory starvation usually has one of two causes:

1. **The memory pool is too small.** The configured shared or private memory is
   not sufficient for the current workload.
2. **A memory leak or memory corruption.** Some memory is not properly freed, so
   the available pool is gradually exhausted.

## Determine the cause

Stop sending traffic to the proxy without stopping OpenSIPS, then wait about
five minutes so that most calls can close and temporary objects, such as
transactions and location records, can be freed.

Resume traffic by placing several calls:

* If the memory errors do not return, the configured memory pool was probably
  too small.
* If the errors return even after memory should have been released, investigate
  a possible memory leak or memory corruption.

If the result is inconclusive, continue with the memory-debugging procedure.

## Increase an undersized memory pool

Use the `-m` option to increase the shared-memory pool and the `-M` option to
increase the private-memory pool allocated to each OpenSIPS process. Both values
are specified in MB (from OpenSIPS 4.1 they also take a `k`/`m`/`g` suffix).

For example:

```bash
opensips -m 256 -M 8
```

Make these options persistent in the service configuration used by your
installation before restarting OpenSIPS by editing:

* `/etc/default/opensips` on Debian-based systems
* `/etc/sysconfig/opensips` on Red Hat-based systems


### Let the pool grow (OpenSIPS 4.1 and later)

With the HG_MALLOC allocator the pools can be elastic: `-m INIT:CAP` starts at
INIT, grows on demand up to CAP and gives memory back when it is no longer
used, so the size does not have to be guessed for the busiest hour:

```bash
opensips -a HG_MALLOC -m 128:1024 -M 8:32
```

HG_MALLOC pins its memory: run OpenSIPS with `LimitMEMLOCK=infinity` (or
`ulimit -l unlimited`) - required for an elastic arena on hugetlb pages, and
it keeps the arena from being swapped on the others. `opensips-cli -x mi core:hg_advise` reports what `-m` and `-M`
should be from the peaks actually reached, and the `hgmem:hg_shm_grow_blocked`
and `hgmem:hg_pkg_grow_blocked` statistics show when an arena cannot grow any
further. See the HG_MALLOC documentation (`mem/README.hg_malloc.md` in the
source tree) for details.

## Debug memory usage on OpenSIPS 3.x and later

### 1. Enable memory debugging

Add the following command-line option to the OpenSIPS startup options:

```text
-a Q_MALLOC_DBG
```

Package installations commonly store these options in:

* `/etc/default/opensips` on Debian-based systems
* `/etc/sysconfig/opensips` on Red Hat-based systems

For example:

```text
OPTIONS="-a Q_MALLOC_DBG"
```

Unlike older OpenSIPS versions, OpenSIPS 3.x and later do not need to be
recompiled to enable this memory allocator.

### 2. Enable memory dump logging

Add the following global parameter to the OpenSIPS configuration:

```opensips
memdump = 1
```

Ensure that the configured logging level allows memory dump messages to be
written to the OpenSIPS log.

### 3. Restart OpenSIPS

Restart OpenSIPS so that both the debugging allocator and the configuration
change take effect.

### 4. Reproduce and isolate the problem

Reproduce the memory growth, then stop sending traffic without stopping
OpenSIPS. When possible, wait about 20 minutes before taking a dump. This gives
temporary allocations enough time to be released and makes persistent
allocations easier to identify.

### 5. Dump the memory status at run time

For **OpenSIPS 4.x and later**, use the `mem` class MI commands:

```bash
opensips-cli -x mi mem:pkg_dump <pid>
opensips-cli -x mi mem:shm_dump
```

For **OpenSIPS 3.x**, dump the private memory of a specific process and the
global shared-memory pool with:

```bash
opensips-cli -x mi mem_pkg_dump <pid>
opensips-cli -x mi mem_shm_dump
```

The package-memory command must be run for the process whose private memory you
want to inspect. Repeat it for other processes if the affected process is not
known.

### 6. Dump the memory status at shutdown

Stop OpenSIPS normally. The memory manager will dump its status while shutting
down, after most normal allocations have been cleaned up. Memory that remains
allocated may indicate a leak.

A memory status dump looks similar to:

```text
0(17665) Memory status (shm):
0(17665) qm_status (0xb5a7e000):
0(17665)  heap size= 33554432
0(17665)  used= 1592952, used+overhead=1811564, free=31742868
0(17665)  max used (+overhead)= 1811564
0(17665) dumping all alloc'ed. fragments:
0(17665)       0. N  address=0xb5ab240c frag=0xb5ab23f4 size=4 used=1
0(17665)             alloc'd from mem/shm_mem.c: shm_mem_init_mallocs(199)
0(17665)         start check=f0f0f0f0, end check= c0c0c0c0, abcdefed
0(17665)       1. N  address=0xb5ab2440 frag=0xb5ab2428 size=4 used=1
0(17665)             alloc'd from timer.c: init_timer(52)
0(17665)         start check=f0f0f0f0, end check= c0c0c0c0, abcdefed
```

Look for a large amount of memory still allocated from the same source
location, especially after traffic has stopped or OpenSIPS has shut down.

If you cannot interpret the memory dump, upload the logs to an HTTP server and
send the link, together with the OpenSIPS version and reproduction details, to
the `devel@lists.opensips.org` mailing list.

## Legacy versions

OpenSIPS 2.4 and earlier require compile-time memory-debugging options.

### OpenSIPS 2.2 through 2.4

Run `make menuconfig` from the source directory and navigate to:

```text
Configure Compile Options -> Configure Compile Flags
```

Check `QM_MALLOC` and `DBG_MALLOC`, save the changes, then recompile and
reinstall OpenSIPS.

### OpenSIPS 1.8 through 2.1

Run `make menuconfig` from the source directory and navigate to:

```text
Configure Compile Options -> Configure Compile Flags
```

Uncheck `F_MALLOC`, check `DBG_QM_MALLOC`, save the changes, then recompile and
reinstall OpenSIPS.

### OpenSIPS 1.7 and earlier

Edit `Makefile.defs`, remove `-DF_MALLOC` from the `DEFS` string, and add:

```text
-DDBG_QM_MALLOC
```

Then recompile and reinstall OpenSIPS.

### Dump memory on OpenSIPS 2.4 and earlier

Set `memdump = 1` in the OpenSIPS configuration, ensure the logging level
allows the dump messages, and restart OpenSIPS.

At run time, send `SIGUSR1` to an OpenSIPS process to dump that process's
private-memory status:

```bash
kill -SIGUSR1 <pid>
```

To dump the shared-memory pool, send the signal to the attendant process. Use
`opensipsctl fifo ps` and select the first PID to identify it.

As with newer versions, stop traffic and wait about 20 minutes before taking a
run-time dump. A normal shutdown also produces a memory status dump.
