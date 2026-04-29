FROM judge0/compilers:1.4.0 AS production

ENV JUDGE0_HOMEPAGE "https://judge0.com"
LABEL homepage=$JUDGE0_HOMEPAGE

ENV JUDGE0_SOURCE_CODE "https://github.com/judge0/judge0"
LABEL source_code=$JUDGE0_SOURCE_CODE

ENV JUDGE0_MAINTAINER "Herman Zvonimir Došilović <hermanz.dosilovic@gmail.com>"
LABEL maintainer=$JUDGE0_MAINTAINER

ENV PATH "/usr/local/ruby-2.7.0/bin:/opt/.gem/bin:$PATH"
ENV GEM_HOME "/opt/.gem/"

# Debian Buster reached End-of-Life; its packages were moved to the archive
# mirror. Redirect all sources before any apt-get call so every subsequent
# RUN apt-get update succeeds without a Release-file 404.
RUN sed -i \
      -e 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' \
      -e 's|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g' \
      -e '/buster-updates/d' \
    /etc/apt/sources.list

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      cron \
      libpq-dev \
      sudo && \
    rm -rf /var/lib/apt/lists/* && \
    echo "gem: --no-document" > /root/.gemrc && \
    gem install bundler:2.1.4 && \
    npm install -g --unsafe-perm aglio@2.3.0

# ── cgroup v2 fix: rebuild isolate from ioi/isolate v2.1 ─────────────────────
# The base image ships isolate built from judge0/isolate@ad39cc4d (cgroup v1
# era). We replace it with the upstream ioi/isolate v2.1 which has full cgroup
# v2 support via --cg flag. v2.1 is used instead of the latest (v2.4) because
# v2.4 uses SYS_quotactl_fd (added in Linux 5.14) which is absent in the
# Debian Buster kernel headers bundled in the base image.
# We skip isolate-cg-keeper (systemd unit helper) since it isn't used by
# Judge0's worker — only `isolate` and `isolate-check-environment` are needed.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libcap-dev \
      libseccomp-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/* && \
    git clone --depth 1 --branch v2.1 https://github.com/ioi/isolate.git /tmp/isolate && \
    cd /tmp/isolate && \
    make -j$(nproc) isolate isolate-check-environment default.cf && \
    install -m 4755 isolate /usr/local/bin/isolate && \
    install isolate-check-environment /usr/local/bin/isolate-check-environment && \
    install -m 644 default.cf /usr/local/etc/isolate && \
    # Override cg_root: the generated default.cf uses "auto:/run/isolate/cgroup"
    # which requires isolate-cg-helper (a systemd service). In Docker without
    # systemd we point directly at the host cgroupfs hierarchy.
    sed -i 's|^cg_root = .*|cg_root = /sys/fs/cgroup/isolate|' /usr/local/etc/isolate && \
    mkdir -p /run/isolate/locks && \
    mkdir -p /var/local/lib/isolate && \
    rm -rf /tmp/isolate && \
    isolate --version
# ─────────────────────────────────────────────────────────────────────────────

EXPOSE 2358

WORKDIR /api

COPY Gemfile* ./
RUN RAILS_ENV=production bundle

COPY cron /etc/cron.d
RUN cat /etc/cron.d/* | crontab -

COPY . .

# Fix Windows CRLF line endings on all shell scripts so they run correctly
# in the Linux container. This is needed when building from a Windows host.
RUN apt-get update && \
    apt-get install -y --no-install-recommends dos2unix && \
    rm -rf /var/lib/apt/lists/* && \
    find /api -name '*.sh' -exec dos2unix {} + && \
    dos2unix /api/docker-entrypoint.sh && \
    find /api/scripts -type f -exec dos2unix {} + && \
    chmod +x /api/docker-entrypoint.sh /api/scripts/server /api/scripts/workers /api/scripts/load-config

ENTRYPOINT ["/api/docker-entrypoint.sh"]
CMD ["/api/scripts/server"]

RUN useradd -u 1000 -m -r judge0 && \
    echo "judge0 ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers && \
    chown judge0: /api/tmp/

USER judge0

ENV JUDGE0_VERSION "1.13.1"
LABEL version=$JUDGE0_VERSION


FROM production AS development

CMD ["sleep", "infinity"]
