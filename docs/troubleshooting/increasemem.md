---
title: "Increasing Memory"
description: "How to increase the memory that will be used by OpenSIPS?"
---

How to increase the memory that will be used by **OpenSIPS**?

## Increase Private Memory Size

OpenSIPS has its own memory manager. Even if you have lot of memory in the system, OpenSIPS will use only the memory size it was configured, and you may get "out of memory" errors sooner than expected. This does not mean that there is a memory leak, but insufficient allocated size for your subscriber population. Common cases for large needs of private memory are: loading user location contacts, doing NAT pinging. Actual OpenSIPS versions overcome the first issue by implementing database FETCH support. The other cases will be taken in consideration very soon.

By default the size of private memory chunk used by each OpenSIPS process is 1 MB.

To increase the size of private memory you need to compile OpenSIPS from sources. Once you get the sources from SVN or the opensips.org's download site, do the following steps:

- edit the file "**config.h**" and search for the next lines:

```c
/*used only if PKG_MALLOC is defined*/
#define PKG_MEM_POOL_SIZE 1024*1024
```

- change the value of PKG_MEM_POOL_SIZE to desired size, for example to have 4MB of private memory:

```c
#define PKG_MEM_POOL_SIZE 4*1024*1024
```

- recompile and reinstall OpenSIPS

```bash
make all; make install;
```

In OpenSIPS 1.8 and higher you can increase the private memory size without recompiling, by passing the -M parameter at OpenSIPS startup. :

```bash

opensips -M 8

# this will run OpenSIPS with 8 MB of private memory per process

```

---

## Increase Share Memory Size

To increase the share memory size use '-m' command line parameter of OpenSIPS.

```bash

opensips -m 256

# this will run OpenSIPS with 256MB of share memory

```

---

## Let the memory grow (OpenSIPS 4.1 and later)

With the HG_MALLOC allocator both sizes can be given as `INIT:CAP`: OpenSIPS
starts with INIT and grows on demand up to CAP, so a pool no longer has to be
sized for the worst case up front:

```bash

opensips -a HG_MALLOC -m 256:2g -M 8:32

# 256 MB of shared memory growing up to 2 GB, 8 MB of private memory per process growing up to 32 MB

```

See [Out Of Memory](/troubleshooting/outofmem#let-the-pool-grow-opensips-41-and-later) for monitoring and host requirements.
