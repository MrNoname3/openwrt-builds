# OpenWRT 18.06 buildroot environment for the TP-Link TL-WR941ND v4 (ar71xx/tiny).
#
# Debian bullseye is chosen on purpose: the OpenWRT 18.06 branch still drives its
# build system with Python 2, which bullseye ships (python2 + python-is-python2),
# while also providing python3 for the few host tools that need it.
#
# The buildroot REFUSES to run as root, so we create an unprivileged 'builder'
# user (uid 1000) that matches the typical rootless-Podman host user. When the
# container is started with --userns=keep-id the host uid maps 1:1, so files
# written into the bind-mounted source tree are owned correctly on the host.

FROM debian:bullseye

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies per the OpenWRT 18.06 "build system setup" docs (Debian),
# plus a few extras used while fetching package sources (svn/hg/rsync).
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc g++ make file unzip bzip2 gzip tar xz-utils patch \
        diffutils findutils time \
        git subversion mercurial rsync wget curl ca-certificates \
        gawk gettext \
        python2 python-is-python2 python3 \
        perl \
        libncurses5-dev libncursesw5-dev zlib1g-dev libssl-dev libelf-dev \
        xsltproc \
        locales \
    && rm -rf /var/lib/apt/lists/*

# Firmware analysis tools: unpack/inspect squashfs rootfs and locate the
# kernel/rootfs blobs inside a factory image (useful for phase 3 partitioning).
RUN apt-get update && apt-get install -y --no-install-recommends \
        squashfs-tools binwalk cpio \
    && rm -rf /var/lib/apt/lists/*

# OpenWRT's build system expects a UTF-8 locale.
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Unprivileged build user (fallback for non-keep-id runs).
RUN useradd -m -u 1000 -s /bin/bash builder

# The bind-mounted source tree lives here; HOME points at it too so nothing
# tries to write into a possibly read-only in-image home under keep-id mapping.
WORKDIR /work
ENV HOME=/work

CMD ["bash"]
