# --- build: strongSwan 6.0.5 + the email-OTP patch ---------------------------
FROM ubuntu:22.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
ARG STRONGSWAN_VERSION=6.0.5

# python3 is required: strongSwan 6.x uses it to generate strongswan.d/*.conf.
# Without it those files are empty and charon loads no plugins.
# systemd only provides systemd.pc, which ./configure insists on.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config gperf bison flex \
        git ca-certificates python3 systemd libgmp-dev libssl-dev

RUN git clone --depth 1 --branch "$STRONGSWAN_VERSION" \
        https://github.com/strongswan/strongswan.git /strongswan
COPY src/xauth-email-token.patch /
WORKDIR /strongswan
RUN git apply /xauth-email-token.patch \
    && ./autogen.sh \
    && ./configure --prefix=/usr --sysconfdir=/etc \
        --enable-unity --enable-xauth-generic --enable-openssl --enable-stroke \
    && make -j"$(nproc)" \
    && make install DESTDIR=/out \
    && rm -rf /out/lib   # systemd units only; /lib is a symlink in the runtime image

# --- runtime ---------------------------------------------------------------
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
# iproute2/procps/iptables are used by vpn.sh (ip, pkill, NAT bypass).
RUN apt-get update && apt-get install -y --no-install-recommends \
        libssl3 libgmp10 iproute2 procps iptables \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/ /

# No journald in a container: have charon write a log file that vpn.sh follows.
RUN printf '%s\n' \
    'charon {' \
    '  filelog {' \
    '    charon {' \
    '      path = /var/log/charon.log' \
    '      default = 1' \
    '      ike = 2' \
    '      cfg = 2' \
    '      knl = 2' \
    '      flush_line = yes' \
    '    }' \
    '  }' \
    '}' > /etc/strongswan.d/zz-filelog.conf

COPY vpn.sh /usr/local/bin/vpn.sh
RUN chmod 755 /usr/local/bin/vpn.sh
ENTRYPOINT ["/usr/local/bin/vpn.sh"]
